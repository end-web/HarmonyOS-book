import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { PreferenceService, WidgetPlayerSnapshot } from './PreferenceService';
import { Book, Chapter } from '../model/Book';
import { PlayerState } from '../model/PlayerState';
import { ColorPickerUtils } from '../utils/ColorPickerUtils';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Widget';

/** 卡片名,与 form_config.json 里 forms[].name 严格一致 */
export const WIDGET_PLAYER = 'PlayerCard';

/** 单张图片大小上限：鸿蒙卡片 formImages 通道单图限制 ~2MB（再大会被框架拒绝） */
const MAX_IMG_BYTES = 1.5 * 1024 * 1024;

interface BuildBindingResult {
  binding: formBindingData.FormBindingData;
  imgFile: fileIo.File | null;
}

/**
 * 鸿蒙官方推荐的卡片图片传递方式：
 *   1) 网络图直接传 https URL（最稳，无需 FD）
 *   2) 本地图通过 formImages 传 FD，卡片侧用 memory://<key> 加载
 *   3) imgName 每次更新必须变（否则卡片 ImageCache 不会刷新，闪一下又是旧图）
 *
 * 我们的策略：
 *   - 始终先把网络封面下到沙箱，主路径用 file FD（memory://），更稳定
 *   - 同时把 https URL 也回填一份做兜底（网络可达且体积合规时卡片能直接用）
 *   - 失败时卡片自动回退到默认占位
 */
export class WidgetUpdater {
  /** 主进程的 Context,用于沙箱写入封面缓存 */
  private static appContext: common.Context | null = null;
  /** url -> 沙箱文件路径 */
  private static coverPathCache: Map<string, string> = new Map();
  /** url -> 文件大小（字节），>MAX_IMG_BYTES 的不走 FD 通道 */
  private static coverSizeCache: Map<string, number> = new Map();

  static setContext(ctx: common.Context): void {
    WidgetUpdater.appContext = ctx;
  }

  /**
   * 把网络封面下到沙箱，返回 { localPath, sizeBytes }；失败返回 null。
   * - 已下载过：直接复用
   * - 失败：返回 null（外层用 https URL 兜底）
   */
  private static async downloadCover(url: string): Promise<string | null> {
    if (!url || !url.startsWith('http')) return null;
    const cached = WidgetUpdater.coverPathCache.get(url);
    if (cached) return cached;
    if (!WidgetUpdater.appContext) return null;
    try {
      const filesDir = WidgetUpdater.appContext.filesDir;
      const fileName = `widget_cover_${WidgetUpdater.hash(url)}.img`;
      const filePath = `${filesDir}/${fileName}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.size > 0) {
          WidgetUpdater.coverPathCache.set(url, filePath);
          WidgetUpdater.coverSizeCache.set(url, stat.size);
          return filePath;
        }
      } catch (_e) { /* not exist, continue */ }

      const httpClient = http.createHttp();
      try {
        const resp = await httpClient.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 8000,
          readTimeout: 8000,
        });
        if (resp.responseCode === 200 && resp.result) {
          const buf = resp.result as ArrayBuffer;
          if (buf.byteLength > MAX_IMG_BYTES) {
            hilog.warn(DOMAIN, TAG, 'cover too big (%{public}d bytes), drop FD path: %{public}s',
              buf.byteLength, url);
            return null;
          }
          const f = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          await fileIo.write(f.fd, buf);
          await fileIo.close(f);
          WidgetUpdater.coverPathCache.set(url, filePath);
          WidgetUpdater.coverSizeCache.set(url, buf.byteLength);
          return filePath;
        }
        hilog.warn(DOMAIN, TAG, 'download cover bad status %{public}d for %{public}s',
          resp.responseCode, url);
      } finally {
        httpClient.destroy();
      }
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'download cover failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    return null;
  }

  private static hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }

  /**
   * 给 formProvider 准备一份 binding（鸿蒙官方推荐结构）：
   *   平铺字段 + imgName + formImages 全部塞在同一个对象里（不要再包一层 data 字符串）
   *   卡片侧用 Image('memory://' + this.imgName) 加载
   *   imgName 每次更新都变,否则卡片 ImageCache 不会刷新
   *
   * 返回 { binding, imgFile }，调用方在 updateForm 完成后必须 close imgFile 释放 fd
   */
  private static async buildPlayerBinding(snap: WidgetPlayerSnapshot)
    : Promise<BuildBindingResult> {
    const data: Record<string, Object> = WidgetUpdater.snapshotToFormData(snap);
    let imgFile: fileIo.File | null = null;
    let imgName = '';
    if (snap.cover && (snap.cover.startsWith('http') || snap.cover.startsWith('/') || snap.cover.startsWith('file://'))) {
      try {
        let localPath: string | null = null;
        if (snap.cover.startsWith('http')) {
          localPath = await WidgetUpdater.downloadCover(snap.cover);
        } else if (snap.cover.startsWith('file://')) {
          localPath = snap.cover.substring('file://'.length);
        } else if (snap.cover.startsWith('/')) {
          localPath = snap.cover;
        }
        if (localPath) {
          imgFile = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
          imgName = `cover_${WidgetUpdater.hash(snap.bookId)}_${snap.updatedAt}`;
          data['imgName'] = imgName;
          const imgMap: Record<string, number> = {};
          imgMap[imgName] = imgFile.fd;
          data['formImages'] = imgMap;
        }
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'open cover fd failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
    return { binding: formBindingData.createFormBindingData(data), imgFile };
  }

  private static closeFd(f: fileIo.File | null): void {
    if (!f) return;
    try { fileIo.closeSync(f); } catch (_e) { /* ignore */ }
  }

  /** 把当前 PlayerState 写入快照,并广播给所有听书卡片 */
  static async updatePlayerCard(state: PlayerState | null): Promise<void> {
    const snap = WidgetUpdater.buildSnapshot(state);
    await WidgetUpdater.ensureBgColor(snap);
    await PreferenceService.setWidgetPlayerSnapshot(snap);
    const ids = await PreferenceService.getWidgetFormIds(WIDGET_PLAYER);
    if (ids.length === 0) return;
    const built = await WidgetUpdater.buildPlayerBinding(snap);
    try {
      for (const id of ids) {
        try {
          await formProvider.updateForm(id, built.binding);
        } catch (err) {
          const e = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'updatePlayerCard fail id=%{public}s code=%{public}d msg=%{public}s',
            id, e.code, e.message);
          // 16500001 invalid id / 16500100 not removed / 16501001 form not exist
          // 这三种都是死 ID，从持久化里清掉，下次重新添加卡片时由 onAddForm 重新登记
          if (e.code === 16500001 || e.code === 16500100 || e.code === 16501001) {
            await PreferenceService.removeWidgetFormId(WIDGET_PLAYER, id);
          }
        }
      }
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  /** 单卡片推送(onAddForm/onUpdateForm 用),内部走 fd 通道并自动关闭 fd */
  static async pushPlayerSnapshotToForm(formId: string, snap: WidgetPlayerSnapshot): Promise<void> {
    await WidgetUpdater.ensureBgColor(snap);
    const built = await WidgetUpdater.buildPlayerBinding(snap);
    try {
      await formProvider.updateForm(formId, built.binding);
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  /** 阅读卡片已废弃,保留空方法做兼容,避免 DataService 等历史调用点报错 */
  static async updateReaderCard(): Promise<void> {
    // no-op
  }

  /** 没有快照时,从 lastPlayed + cachedBooks 拼一份兜底快照(冷启动卡片首次添加用)。
   *  注意:这里 isPlaying 必须保持 false —— 兜底是给"主进程从未推过快照"的场景用的,
   *  此时主进程那边肯定不在播。
   *  ★ 不再写回 preferences:FormExt 与主进程的 preferences 缓存不互通,
   *  如果 FormExt 因缓存陈旧错读出 null 走到这里,写回会用 false 覆盖
   *  主进程刚 put 的真值(磁盘也被污染),卡片就会卡在"暂停"。 */
  static async seedSnapshotFromLastPlayed(): Promise<WidgetPlayerSnapshot | null> {
    const last = await PreferenceService.getLastPlayed();
    if (!last) return null;
    const cachedJson = await PreferenceService.getCachedBooks();
    const importedJson = await PreferenceService.getImportedBooks();
    let book: Book | undefined;
    try {
      const cached = JSON.parse(cachedJson) as Book[];
      const imported = JSON.parse(importedJson) as Book[];
      book = imported.find((b) => b.id === last.bookId) ?? cached.find((b) => b.id === last.bookId);
    } catch (_e) { /* ignore */ }
    if (!book) return null;
    const snap: WidgetPlayerSnapshot = {
      bookId: book.id,
      bookTitle: book.title,
      author: book.author,
      cover: book.cover,
      chapterId: last.chapterId,
      chapterTitle: last.chapterTitle ?? '',
      progressMs: last.progressMs,
      durationMs: last.durationMs ?? 0,
      isPlaying: false,
      updatedAt: Date.now(),
    };
    return snap;
  }

  /** EntryAbility 启动时调:把兜底快照写回 preferences 给桌面卡片使用。
   *  和 seedSnapshotFromLastPlayed 分开,确保只有主进程会写盘。 */
  static async seedAndPersistFromLastPlayed(): Promise<WidgetPlayerSnapshot | null> {
    const snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
    if (snap) {
      await PreferenceService.setWidgetPlayerSnapshot(snap);
    }
    return snap;
  }

  /** 把当前 preference 里的快照推送到所有听书卡片(seed 后调用) */
  static async pushSnapshotToCards(): Promise<void> {
    const ids = await PreferenceService.getWidgetFormIds(WIDGET_PLAYER);
    if (ids.length === 0) return;
    const snap = await PreferenceService.getWidgetPlayerSnapshot();
    if (!snap) return;
    const built = await WidgetUpdater.buildPlayerBinding(snap);
    try {
      for (const id of ids) {
        try {
          await formProvider.updateForm(id, built.binding);
        } catch (err) {
          const e = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'pushSnapshotToCards fail id=%{public}s code=%{public}d',
            id, e.code);
          if (e.code === 16500001 || e.code === 16500100 || e.code === 16501001) {
            await PreferenceService.removeWidgetFormId(WIDGET_PLAYER, id);
          }
        }
      }
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  static buildSnapshot(state: PlayerState | null): WidgetPlayerSnapshot {
    const book: Book | null = state?.currentBook ?? null;
    const chapter: Chapter | null = state?.currentChapter ?? null;
    let bgColor = '';
    if (book?.cover) {
      const rgb = ColorPickerUtils.getCached(book.cover);
      if (rgb) {
        bgColor = ColorPickerUtils.toHex(ColorPickerUtils.darken(rgb, 0.05));
      }
    }
    return {
      bookId: book?.id ?? '',
      bookTitle: book?.title ?? '',
      author: book?.author ?? '',
      cover: book?.cover ?? '',
      chapterId: chapter?.id ?? '',
      chapterTitle: chapter?.title ?? '',
      progressMs: state?.progressMs ?? 0,
      durationMs: state?.durationMs ?? 0,
      isPlaying: state?.isPlaying ?? false,
      updatedAt: Date.now(),
      bgColor: bgColor,
    };
  }

  /** 异步提取封面色并补充到快照中（缓存 miss 时主动提取） */
  private static async ensureBgColor(snap: WidgetPlayerSnapshot): Promise<void> {
    if (snap.bgColor && snap.bgColor.length > 0) return;
    if (!snap.cover) return;
    try {
      let rgb = ColorPickerUtils.getCached(snap.cover);
      if (!rgb) {
        if (snap.cover.startsWith('http')) {
          rgb = await ColorPickerUtils.pickFromUrl(snap.cover);
        } else if (snap.cover.startsWith('/')) {
          rgb = await ColorPickerUtils.pickFromFile(snap.cover);
        }
      }
      if (rgb) {
        snap.bgColor = ColorPickerUtils.toHex(ColorPickerUtils.darken(rgb, 0.05));
      }
    } catch (_e) { /* ignore */ }
  }

  static snapshotToFormData(snap: WidgetPlayerSnapshot): Record<string, Object> {
    return {
      'hasBook': snap.bookId.length > 0 ? 1 : 0,
      'bookId': snap.bookId,
      'bookTitle': snap.bookTitle || '没有正在播放的书',
      'author': snap.author,
      'cover': snap.cover,
      'chapterTitle': snap.chapterTitle || '点击挑一本',
      'isPlaying': snap.isPlaying ? 1 : 0,
      'bgColor': snap.bgColor || '',
    };
  }
}