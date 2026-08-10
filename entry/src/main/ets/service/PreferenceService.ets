import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { Book } from '../model/Book';

/** 书架收藏变化事件:加入/移出书架后触发,书架页据此自动刷新 */
export const EVT_FAVORITES_CHANGED = 'app.favorites.changed';

/**
 * 本地持久化：书架 / 播放历史 / 设置
 */
const STORE_NAME = 'listenbook_prefs';
const KEY_FAVORITES = 'favorite_book_ids';
const KEY_HISTORY = 'play_history';
const KEY_LAST_PLAYED = 'last_played';
const KEY_COLOR_MODE = 'color_mode';
const KEY_IMPORTED_BOOKS = 'imported_books';
const KEY_DEFAULT_TAB = 'default_tab';
const KEY_AUDIO_INTERRUPT_MODE = 'audio_interrupt_mode';
const KEY_AUDIO_AUTO_RESUME = 'audio_auto_resume';
const KEY_PRIVACY_AGREED_VERSION = 'privacy_agreed_version';
const KEY_HOME_GRID_COLUMNS = 'home_grid_columns';
const KEY_CACHED_BOOKS = 'cached_books_v1';
const KEY_PRELOAD_CHAPTERS = 'preload_chapters_count';
const KEY_SERVER_AUDIO_API_BASE = 'server_audio_api_base';
/** 卡片侧持久化的播放快照(由主进程写,FormExtensionAbility 读) */
const KEY_WIDGET_PLAYER_SNAPSHOT = 'widget_player_snapshot_v1';
/** 已添加的卡片 formId 集合(按卡片名分桶) */
const KEY_WIDGET_FORM_IDS = 'widget_form_ids_v1';
/** 每本书独立的最新播放进度,key = `${KEY_PROGRESS_PREFIX}${bookId}` */
const KEY_PROGRESS_PREFIX = 'progress_v1_';
/** 每本书的章节级播放进度,key = `${KEY_CHAPTER_PROGRESS_PREFIX}${bookId}` */
const KEY_CHAPTER_PROGRESS_PREFIX = 'chapter_progress_v1_';
const MAX_CHAPTER_PROGRESS_PER_BOOK = 200;
/** 每本书独立的跳过头尾设置,key = `${KEY_SKIP_PREFIX}${bookId}`。
 *  独立小 KV,不再搭车缓存书索引——避免冷启动走 legacy/persistUnsafe 兜底分支时把 skip 丢掉。 */
const KEY_SKIP_PREFIX = 'skip_v1_';
/** 华为账号登录身份标识(UnionID/OpenID),JSON 持久化 */
const KEY_HW_ACCOUNT = 'hw_account_v1';

export interface PlayHistoryItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  updatedAt: number;
  chapterTitle?: string;
  durationMs?: number;
  sourceUrl?: string;
  bookUrl?: string;
}

export interface LastPlayedItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  chapterTitle?: string;
  durationMs?: number;
  speed?: number;
}

/** 每本书独立的跳过头尾设置(秒) */
export interface SkipConfig {
  skipIntro: number;
  skipOutro: number;
}

export class BookSkipBackup {
  bookId: string = '';
  skipIntro: number = 0;
  skipOutro: number = 0;
}

export class PreferenceBackupSnapshot {
  favorites: string[] = [];
  history: PlayHistoryItem[] = [];
  lastPlayed: LastPlayedItem | null = null;
  progresses: PlayProgress[] = [];
  skipConfigs: BookSkipBackup[] = [];
  colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  defaultTab: number = 0;
  audioInterruptMode: number = 0;
  audioAutoResume: boolean = true;
  homeGridColumns: number = 3;
  preloadChapters: number = 3;
  serverAudioApiBase: string = '';
}

/**
 * 单本书的最新播放进度。
 * 与 PlayHistoryItem 的差异:per-book 一书一槽,永不溢出 50 条上限,
 * 切书前 reset AVPlayer 之前必须先把这条落盘,确保切回时拿到的是最新进度。
 */
export interface PlayProgress {
  bookId: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
  speed?: number;
  sourceUrl?: string;
  bookUrl?: string;
}

/** 单个章节的独立播放进度，用于手动切回章节时续播。 */
export class ChapterPlayProgress {
  bookId: string = '';
  chapterId: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  updatedAt: number = 0;
}

/** 卡片侧需要的最小快照,主进程写,FormExtensionAbility 读后渲染 */
export interface WidgetPlayerSnapshot {
  bookId: string;
  bookTitle: string;
  author: string;
  cover: string;
  chapterId: string;
  chapterTitle: string;
  progressMs: number;
  durationMs: number;
  isPlaying: boolean;
  updatedAt: number;
  bgColor?: string;
  bgTopColor?: string;
  bgBottomColor?: string;
  bgLeftColor?: string;
  bgRightColor?: string;
  bgDarkColor?: string;
}

/** 卡片名 -> formId 列表 */
interface FormIdBucket {
  name: string;
  ids: string[];
}

/** 华为账号登录身份标识(端侧直接返回,无需后端) */
export interface HwAccount {
  unionID: string;
  openID: string;
  /** 登录时间戳 */
  loginAt: number;
}

export class PreferenceService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;
  private static favoriteListener: (() => void) | null = null;
  private static historyListener: (() => void) | null = null;

  /** 由 EntryAbility 启动时注入,用于触发卡片刷新(避免与 WidgetUpdater 形成循环 import) */
  static onFavoriteChanged(cb: () => void): void {
    PreferenceService.favoriteListener = cb;
  }

  static onHistoryChanged(cb: () => void): void {
    PreferenceService.historyListener = cb;
  }

  private static notifyFavoriteChanged(): void {
    PreferenceService.favoriteListener?.();
  }

  private static notifyHistoryChanged(): void {
    PreferenceService.historyListener?.();
  }

  static async init(context: common.BaseContext): Promise<void> {
    if (PreferenceService.store) {
      return;
    }
    if (!PreferenceService.initPromise) {
      const options: preferences.Options = { name: STORE_NAME };
      PreferenceService.initPromise = preferences.getPreferences(context, options).then((s) => {
        PreferenceService.store = s;
      });
    }
    await PreferenceService.initPromise;
  }

  static async ensureReady(context: common.BaseContext): Promise<void> {
    if (PreferenceService.store) return;
    await PreferenceService.init(context);
  }

  /**
   * 抛弃当前进程内的 preferences 缓存,强制下次 init 重新从文件读。
   * preferences 不支持多进程并发,FormExtensionAbility 进程的内存缓存
   * 不会感知主进程后续 put 的值;每次进入 onUpdateForm 前调一次,
   * 才能拿到主进程最新写入的卡片快照(避免卡片显示暂停但实际还在播)。
   */
  static async invalidateCache(context: common.BaseContext): Promise<void> {
    try {
      await preferences.removePreferencesFromCache(context, { name: STORE_NAME });
    } catch (_e) { /* ignore */ }
    PreferenceService.store = null;
    PreferenceService.initPromise = null;
  }

  private static async ensureStore(): Promise<preferences.Preferences> {
    if (!PreferenceService.store) {
      if (PreferenceService.initPromise) {
        await PreferenceService.initPromise;
      }
      if (!PreferenceService.store) {
        throw new Error('PreferenceService not initialized');
      }
    }
    return PreferenceService.store;
  }

  static async getFavorites(): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_FAVORITES, '[]') as string;
    return JSON.parse(raw) as string[];
  }

  static async toggleFavorite(bookId: string): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const idx = list.indexOf(bookId);
    let added: boolean;
    if (idx >= 0) {
      list.splice(idx, 1);
      added = false;
    } else {
      list.unshift(bookId);
      added = true;
    }
    await s.put(KEY_FAVORITES, JSON.stringify(list));
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId } });
    return added;
  }

  static async removeFavorite(bookId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const idx = list.indexOf(bookId);
    if (idx >= 0) {
      list.splice(idx, 1);
      await s.put(KEY_FAVORITES, JSON.stringify(list));
      await s.flush();
      PreferenceService.notifyFavoriteChanged();
      emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId } });
    }
  }

  static async isFavorite(bookId: string): Promise<boolean> {
    const list = await PreferenceService.getFavorites();
    return list.includes(bookId);
  }

  // ===== 华为账号登录身份标识 =====

  static async getHwAccount(): Promise<HwAccount | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_HW_ACCOUNT, '') as string;
    if (!raw) {
      return null;
    }
    try {
      return JSON.parse(raw) as HwAccount;
    } catch (_e) {
      return null;
    }
  }

  static async setHwAccount(account: HwAccount): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_HW_ACCOUNT, JSON.stringify(account));
    await s.flush();
  }

  static async clearHwAccount(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_HW_ACCOUNT);
    await s.flush();
  }

  static async getHistory(): Promise<PlayHistoryItem[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_HISTORY, '[]') as string;
    return JSON.parse(raw) as PlayHistoryItem[];
  }

  static async upsertHistory(item: PlayHistoryItem): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getHistory();
    const idx = list.findIndex((it) => it.bookId === item.bookId);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
    list.unshift(item);
    if (list.length > 50) {
      list.length = 50;
    }
    await s.put(KEY_HISTORY, JSON.stringify(list));
    await s.flush();
    PreferenceService.notifyHistoryChanged();
  }

  static async removeHistory(bookId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getHistory();
    const filtered = list.filter((it) => it.bookId !== bookId);
    await s.put(KEY_HISTORY, JSON.stringify(filtered));
    await s.flush();
    PreferenceService.notifyHistoryChanged();
  }

  static async setLastPlayed(bookId: string, chapterId: string, progressMs: number = 0,
    chapterTitle?: string, durationMs?: number, speed?: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const item: LastPlayedItem = { bookId, chapterId, progressMs, chapterTitle, durationMs, speed };
    await s.put(KEY_LAST_PLAYED, JSON.stringify(item));
    await s.flush();
  }

  static async getLastPlayed(): Promise<LastPlayedItem | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_LAST_PLAYED, '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as LastPlayedItem;
    } catch (e) {
      return null;
    }
  }

  /**
   * 单本书最新进度。
   * 内存缓存命中时同步返回(快路径,supports 切书前后的快速读写);否则去 store 读。
   */
  private static progressMemo: Map<string, PlayProgress> = new Map();

  static async getProgress(bookId: string): Promise<PlayProgress | null> {
    if (!bookId) return null;
    const memo = PreferenceService.progressMemo.get(bookId);
    if (memo) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_PROGRESS_PREFIX + bookId, '') as string;
    if (!raw) return null;
    try {
      const p = JSON.parse(raw) as PlayProgress;
      PreferenceService.progressMemo.set(bookId, p);
      return p;
    } catch (_e) {
      return null;
    }
  }

  static getProgressSync(bookId: string): PlayProgress | null {
    if (!bookId) return null;
    return PreferenceService.progressMemo.get(bookId) ?? null;
  }

  static async saveProgress(p: PlayProgress): Promise<void> {
    if (!p || !p.bookId) return;
    PreferenceService.progressMemo.set(p.bookId, p);
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PROGRESS_PREFIX + p.bookId, JSON.stringify(p));
    await s.flush();
  }

  static async removeProgress(bookId: string): Promise<void> {
    if (!bookId) return;
    PreferenceService.progressMemo.delete(bookId);
    PreferenceService.chapterProgressMemo.delete(bookId);
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_PROGRESS_PREFIX + bookId);
    await s.delete(KEY_CHAPTER_PROGRESS_PREFIX + bookId);
    await s.flush();
  }

  private static chapterProgressMemo: Map<string, ChapterPlayProgress[]> = new Map();

  private static async loadChapterProgresses(bookId: string): Promise<ChapterPlayProgress[]> {
    const memo = PreferenceService.chapterProgressMemo.get(bookId);
    if (memo !== undefined) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_CHAPTER_PROGRESS_PREFIX + bookId, '') as string;
    if (!raw) {
      const empty: ChapterPlayProgress[] = [];
      PreferenceService.chapterProgressMemo.set(bookId, empty);
      return empty;
    }
    try {
      const items = JSON.parse(raw) as ChapterPlayProgress[];
      PreferenceService.chapterProgressMemo.set(bookId, items);
      return items;
    } catch (_e) {
      const empty: ChapterPlayProgress[] = [];
      PreferenceService.chapterProgressMemo.set(bookId, empty);
      return empty;
    }
  }

  static async getChapterProgress(bookId: string, chapterId: string): Promise<ChapterPlayProgress | null> {
    if (!bookId || !chapterId) return null;
    const items = await PreferenceService.loadChapterProgresses(bookId);
    for (const item of items) {
      if (item.chapterId === chapterId) return item;
    }
    return null;
  }

  static async saveChapterProgress(progress: ChapterPlayProgress): Promise<void> {
    if (!progress.bookId || !progress.chapterId) return;
    const saved = await PreferenceService.loadChapterProgresses(progress.bookId);
    const next = saved.filter((item: ChapterPlayProgress): boolean => item.chapterId !== progress.chapterId);
    next.unshift(progress);
    const limited = next.length > MAX_CHAPTER_PROGRESS_PER_BOOK
      ? next.slice(0, MAX_CHAPTER_PROGRESS_PER_BOOK) : next;
    PreferenceService.chapterProgressMemo.set(progress.bookId, limited);
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_CHAPTER_PROGRESS_PREFIX + progress.bookId, JSON.stringify(limited));
    await s.flush();
  }

  /**
   * 跳过头尾(每本书独立)。独立 KV 存储,不依赖缓存书索引。
   * 内存缓存命中同步返回,supports 冷启动恢复时贴回 currentBook。
   */
  private static skipMemo: Map<string, SkipConfig> = new Map();

  static async getSkipConfig(bookId: string): Promise<SkipConfig | null> {
    if (!bookId) return null;
    const memo = PreferenceService.skipMemo.get(bookId);
    if (memo) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_SKIP_PREFIX + bookId, '') as string;
    if (!raw) return null;
    try {
      const cfg = JSON.parse(raw) as SkipConfig;
      PreferenceService.skipMemo.set(bookId, cfg);
      return cfg;
    } catch (_e) {
      return null;
    }
  }

  static async saveSkipConfig(bookId: string, skipIntro: number, skipOutro: number): Promise<void> {
    if (!bookId) return;
    const cfg: SkipConfig = { skipIntro: skipIntro || 0, skipOutro: skipOutro || 0 };
    PreferenceService.skipMemo.set(bookId, cfg);
    const s = await PreferenceService.ensureStore();
    // 全 0 视为清除:删掉 key 保持 store 干净,读回落 null → 不覆盖
    if (cfg.skipIntro <= 0 && cfg.skipOutro <= 0) {
      await s.delete(KEY_SKIP_PREFIX + bookId);
    } else {
      await s.put(KEY_SKIP_PREFIX + bookId, JSON.stringify(cfg));
    }
    await s.flush();
  }

  /**
   * 把独立存储里的跳过头尾贴回 book 对象(store 有记录则以 store 为准)。
   * 冷启动恢复 currentBook / PlayerPage 载入书时调用,消除缓存书索引丢 skip 的影响。
   */
  static async applySkipConfig(book: Book | null | undefined): Promise<void> {
    if (!book || !book.id) return;
    const cfg = await PreferenceService.getSkipConfig(book.id);
    if (cfg) {
      book.skipIntro = cfg.skipIntro;
      book.skipOutro = cfg.skipOutro;
      return;
    }
    // store 无记录:若 book 自带非零 skip(旧方案存在缓存书壳里),一次性迁移进独立 store,
    // 让老用户无需重新设置,下次冷启动即从权威 store 读回。
    const bi = book.skipIntro ?? 0;
    const bo = book.skipOutro ?? 0;
    if (bi > 0 || bo > 0) {
      await PreferenceService.saveSkipConfig(book.id, bi, bo);
    }
  }

  static async getColorMode(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_COLOR_MODE, ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) as number;
  }

  static async setColorMode(mode: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_COLOR_MODE, mode);
    await s.flush();
  }

  static async getImportedBooks(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_IMPORTED_BOOKS, '[]') as string;
  }

  static async saveImportedBooks(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_IMPORTED_BOOKS, json);
    await s.flush();
  }

  static async getDefaultTab(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const idx = await s.get(KEY_DEFAULT_TAB, 0) as number;
    if (idx < 0 || idx > 3) return 0;
    return idx;
  }

  static async setDefaultTab(idx: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_DEFAULT_TAB, idx);
    await s.flush();
  }

  static async getPrivacyAgreedVersion(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_PRIVACY_AGREED_VERSION, '') as string;
  }

  static async setPrivacyAgreedVersion(version: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PRIVACY_AGREED_VERSION, version);
    await s.flush();
  }

  /** 0=共享焦点（默认，听书与其他音乐互斥）, 1=独立焦点（不与本应用其他音频互斥） */
  static async getAudioInterruptMode(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_INTERRUPT_MODE, 0) as number;
  }

  static async setAudioInterruptMode(mode: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_INTERRUPT_MODE, mode);
    await s.flush();
  }

  /** 失去焦点暂停后，是否在系统通知 RESUME 时自动恢复播放 */
  static async getAudioAutoResume(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_AUTO_RESUME, true) as boolean;
  }

  static async setAudioAutoResume(enabled: boolean): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_AUTO_RESUME, enabled);
    await s.flush();
  }

  /** 首页书籍栅格列数：1 / 2 / 3，默认 3 */
  static async getHomeGridColumns(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const v = await s.get(KEY_HOME_GRID_COLUMNS, 3) as number;
    if (v < 1) return 1;
    if (v > 3) return 3;
    return v;
  }

  static async setHomeGridColumns(cols: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const clamped = cols < 1 ? 1 : (cols > 3 ? 3 : cols);
    await s.put(KEY_HOME_GRID_COLUMNS, clamped);
    await s.flush();
  }

  /** 缓存书池：来自搜索 / 在线源的书籍快照,用于让收藏 + 历史能在书架/历史页找到对应 Book */
  static async getCachedBooks(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_CACHED_BOOKS, '[]') as string;
  }

  static async putCachedBookJson(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_CACHED_BOOKS, json);
    await s.flush();
  }

  /**
   * 清空"书架 + 播放记录":收藏 / 历史 / 每本进度 / 上次播放 / 卡片快照 / 旧缓存池。
   * 保留:应用设置、登录信息、卡片 formId 等其余偏好。
   */
  static async clearBookshelfAndHistory(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_FAVORITES);
    await s.delete(KEY_HISTORY);
    await s.delete(KEY_LAST_PLAYED);
    await s.delete(KEY_WIDGET_PLAYER_SNAPSHOT);
    await s.delete(KEY_CACHED_BOOKS);
    // 逐本进度 progress_v1_* + 逐本跳过头尾 skip_v1_*:枚举全部 key,前缀匹配删除
    try {
      const all = await s.getAll() as Record<string, Object>;
      for (const key of Object.keys(all)) {
        if (key.startsWith(KEY_PROGRESS_PREFIX) || key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)
          || key.startsWith(KEY_SKIP_PREFIX)) {
          await s.delete(key);
        }
      }
    } catch (_e) { /* ignore */ }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    PreferenceService.skipMemo.clear();
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  /** 清空在线收藏与播放记录，保留本地导入书的收藏和每本书的跳过头尾设置。 */
  static async clearOnlineFavoritesAndHistory(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    // 保留 import_* 收藏 ID
    const ids = await PreferenceService.getFavorites();
    const importIds = ids.filter((id: string) => id.startsWith('import_'));
    await s.put(KEY_FAVORITES, JSON.stringify(importIds));
    await s.delete(KEY_HISTORY);
    await s.delete(KEY_LAST_PLAYED);
    await s.delete(KEY_WIDGET_PLAYER_SNAPSHOT);
    await s.delete(KEY_CACHED_BOOKS);
    // 仅删 progress_v1_*，保留 skip_v1_*
    try {
      const all = await s.getAll() as Record<string, Object>;
      for (const key of Object.keys(all)) {
        if (key.startsWith(KEY_PROGRESS_PREFIX) || key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)) {
          await s.delete(key);
        }
      }
    } catch (_e) { /* ignore */ }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    // skipMemo 不清——跳过头尾设置是用户主动配置
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  /** 卡片快照:主进程写,FormExtensionAbility 在 onAddForm/onUpdateForm 里读 */
  static async getWidgetPlayerSnapshot(): Promise<WidgetPlayerSnapshot | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_PLAYER_SNAPSHOT, '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as WidgetPlayerSnapshot;
    } catch (_e) {
      return null;
    }
  }

  static async setWidgetPlayerSnapshot(snap: WidgetPlayerSnapshot): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_WIDGET_PLAYER_SNAPSHOT, JSON.stringify(snap));
    await s.flush();
  }

  /** 已添加到桌面的卡片 formId 列表(按卡片名 name 分桶) */
  static async getWidgetFormIds(name: string): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    const bucket = arr.find((b) => b.name === name);
    return bucket ? bucket.ids.slice() : [];
  }

  static async addWidgetFormId(name: string, formId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    let bucket = arr.find((b) => b.name === name);
    if (!bucket) {
      bucket = { name, ids: [] };
      arr.push(bucket);
    }
    if (!bucket.ids.includes(formId)) {
      bucket.ids.push(formId);
    }
    await s.put(KEY_WIDGET_FORM_IDS, JSON.stringify(arr));
    await s.flush();
  }

  static async removeWidgetFormId(name: string, formId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    const bucket = arr.find((b) => b.name === name);
    if (!bucket) return;
    bucket.ids = bucket.ids.filter((id) => id !== formId);
    await s.put(KEY_WIDGET_FORM_IDS, JSON.stringify(arr));
    await s.flush();
  }

  static async getPreloadChapters(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const count = await s.get(KEY_PRELOAD_CHAPTERS, 3) as number;
    if (count === 0 || count === 1 || count === 3 || count === 5 || count === 10) {
      return count;
    }
    return 3;
  }

  static async setPreloadChapters(count: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PRELOAD_CHAPTERS, count);
    await s.flush();
  }

  static async getServerAudioApiBase(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_SERVER_AUDIO_API_BASE, '') as string;
  }

  static async setServerAudioApiBase(apiBase: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_SERVER_AUDIO_API_BASE, apiBase);
    await s.flush();
  }

  static async clearServerAudioApiBase(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_SERVER_AUDIO_API_BASE);
    await s.flush();
  }

  /** 导出允许跨设备迁移的白名单偏好，不包含账号、卡片和本地导入数据。 */
  static async exportBackupSnapshot(): Promise<PreferenceBackupSnapshot> {
    const snapshot = new PreferenceBackupSnapshot();
    snapshot.favorites = (await PreferenceService.getFavorites())
      .filter((id: string) => !id.startsWith('import_'));
    snapshot.history = (await PreferenceService.getHistory())
      .filter((item: PlayHistoryItem) => !item.bookId.startsWith('import_'));
    const lastPlayed = await PreferenceService.getLastPlayed();
    snapshot.lastPlayed = lastPlayed && !lastPlayed.bookId.startsWith('import_') ? lastPlayed : null;
    snapshot.colorMode = await PreferenceService.getColorMode();
    snapshot.defaultTab = await PreferenceService.getDefaultTab();
    snapshot.audioInterruptMode = await PreferenceService.getAudioInterruptMode();
    snapshot.audioAutoResume = await PreferenceService.getAudioAutoResume();
    snapshot.homeGridColumns = await PreferenceService.getHomeGridColumns();
    snapshot.preloadChapters = await PreferenceService.getPreloadChapters();
    snapshot.serverAudioApiBase = await PreferenceService.getServerAudioApiBase();

    const s = await PreferenceService.ensureStore();
    const all = await s.getAll() as Record<string, Object>;
    for (const key of Object.keys(all)) {
      if (key.startsWith(KEY_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_PROGRESS_PREFIX.length);
        if (bookId.startsWith('import_')) continue;
        const progress = await PreferenceService.getProgress(bookId);
        if (progress) snapshot.progresses.push(progress);
      } else if (key.startsWith(KEY_SKIP_PREFIX)) {
        const bookId = key.substring(KEY_SKIP_PREFIX.length);
        if (bookId.startsWith('import_')) continue;
        const config = await PreferenceService.getSkipConfig(bookId);
        if (config) {
          const backup = new BookSkipBackup();
          backup.bookId = bookId;
          backup.skipIntro = config.skipIntro;
          backup.skipOutro = config.skipOutro;
          snapshot.skipConfigs.push(backup);
        }
      }
    }
    return snapshot;
  }

  /** 恢复跨设备偏好，保留目标设备已有的本地导入书数据。 */
  static async restoreBackupSnapshot(snapshot: PreferenceBackupSnapshot): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const localFavorites = (await PreferenceService.getFavorites())
      .filter((id: string) => id.startsWith('import_'));
    const localHistory = (await PreferenceService.getHistory())
      .filter((item: PlayHistoryItem) => item.bookId.startsWith('import_'));
    const restoredFavorites = snapshot.favorites
      .filter((id: string) => !!id && !id.startsWith('import_'));
    const restoredHistory = snapshot.history
      .filter((item: PlayHistoryItem) => !!item && !!item.bookId && !item.bookId.startsWith('import_'));
    await s.put(KEY_FAVORITES, JSON.stringify(localFavorites.concat(restoredFavorites)));
    await s.put(KEY_HISTORY, JSON.stringify(localHistory.concat(restoredHistory).slice(0, 50)));
    if (snapshot.lastPlayed && !snapshot.lastPlayed.bookId.startsWith('import_')) {
      await s.put(KEY_LAST_PLAYED, JSON.stringify(snapshot.lastPlayed));
    } else {
      await s.delete(KEY_LAST_PLAYED);
    }

    const all = await s.getAll() as Record<string, Object>;
    for (const key of Object.keys(all)) {
      if (key.startsWith(KEY_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_PROGRESS_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      } else if (key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_CHAPTER_PROGRESS_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      } else if (key.startsWith(KEY_SKIP_PREFIX)) {
        const bookId = key.substring(KEY_SKIP_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      }
    }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    PreferenceService.skipMemo.clear();
    for (const progress of snapshot.progresses) {
      if (!progress || !progress.bookId || progress.bookId.startsWith('import_')) continue;
      PreferenceService.progressMemo.set(progress.bookId, progress);
      await s.put(KEY_PROGRESS_PREFIX + progress.bookId, JSON.stringify(progress));
    }
    for (const skip of snapshot.skipConfigs) {
      if (!skip || !skip.bookId || skip.bookId.startsWith('import_')) continue;
      const config: SkipConfig = { skipIntro: skip.skipIntro, skipOutro: skip.skipOutro };
      PreferenceService.skipMemo.set(skip.bookId, config);
      await s.put(KEY_SKIP_PREFIX + skip.bookId, JSON.stringify(config));
    }

    await s.put(KEY_COLOR_MODE, snapshot.colorMode);
    await s.put(KEY_DEFAULT_TAB, snapshot.defaultTab);
    await s.put(KEY_AUDIO_INTERRUPT_MODE, snapshot.audioInterruptMode);
    await s.put(KEY_AUDIO_AUTO_RESUME, snapshot.audioAutoResume);
    await s.put(KEY_HOME_GRID_COLUMNS, snapshot.homeGridColumns);
    await s.put(KEY_PRELOAD_CHAPTERS, snapshot.preloadChapters);
    if (snapshot.serverAudioApiBase) {
      await s.put(KEY_SERVER_AUDIO_API_BASE, snapshot.serverAudioApiBase);
    } else {
      await s.delete(KEY_SERVER_AUDIO_API_BASE);
    }
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

}
