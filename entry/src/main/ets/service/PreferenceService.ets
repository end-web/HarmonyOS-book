import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 本地持久化：书架 / 播放历史 / 设置
 */
const STORE_NAME = 'listenbook_prefs';
const KEY_FAVORITES = 'favorite_book_ids';
const KEY_HISTORY = 'play_history';
const KEY_LAST_PLAYED = 'last_played';
const KEY_COLOR_MODE = 'color_mode';
const KEY_IMPORTED_BOOKS = 'imported_books';
const KEY_SOURCE_SUBSCRIPTIONS = 'source_subscriptions';
const KEY_BOOK_SOURCES = 'book_sources';
const KEY_BUILTIN_DISABLED = 'builtin_sources_disabled_v1';
const KEY_DEFAULT_TAB = 'default_tab';
const KEY_AUDIO_INTERRUPT_MODE = 'audio_interrupt_mode';
const KEY_AUDIO_AUTO_RESUME = 'audio_auto_resume';
const KEY_PRIVACY_AGREED_VERSION = 'privacy_agreed_version';
const KEY_HOME_GRID_COLUMNS = 'home_grid_columns';
const KEY_CACHED_BOOKS = 'cached_books_v1';
const KEY_PRELOAD_CHAPTERS = 'preload_chapters_count';
/** 卡片侧持久化的播放快照(由主进程写,FormExtensionAbility 读) */
const KEY_WIDGET_PLAYER_SNAPSHOT = 'widget_player_snapshot_v1';
/** 已添加的卡片 formId 集合(按卡片名分桶) */
const KEY_WIDGET_FORM_IDS = 'widget_form_ids_v1';
/** 每本书独立的最新播放进度,key = `${KEY_PROGRESS_PREFIX}${bookId}` */
const KEY_PROGRESS_PREFIX = 'progress_v1_';
/** 订阅源发现导航缓存,key = `${KEY_EXPLORE_NAV_PREFIX}${sourceUrlHash}` */
const KEY_EXPLORE_NAV_PREFIX = 'explore_nav_v1_';

export interface PlayHistoryItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  updatedAt: number;
  // 章节标题:TOC 刷新/连载更新导致位置索引漂移时,用标题重新定位章节(id 兜底)
  chapterTitle?: string;
  // 章节真实时长(ms):有声书 TOC 不带时长,prepared 时回写,用于冷启动滑块/百分比
  durationMs?: number;
}

export interface LastPlayedItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  chapterTitle?: string;
  durationMs?: number;
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
  /** 章节在 book.chapters 中的索引(便于快速渲染"X集/总集数") */
  chapterIndex: number;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
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
}

/** 卡片名 -> formId 列表 */
interface FormIdBucket {
  name: string;
  ids: string[];
}

/** 订阅源发现导航缓存项 */
export interface ExploreNavCache {
  sourceUrl: string;
  /** 源的 lastUpdateTime，用于版本戳 */
  sourceVersion: number;
  /** 缓存的导航 JSON 数组（已解析） */
  navigation: ExploreNavItem[];
  /** 缓存时间戳 */
  cachedAt: number;
}

/** 导航项 */
export interface ExploreNavItem {
  title: string;
  url: string;
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
    }
  }

  static async isFavorite(bookId: string): Promise<boolean> {
    const list = await PreferenceService.getFavorites();
    return list.includes(bookId);
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
    chapterTitle?: string, durationMs?: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const item: LastPlayedItem = { bookId, chapterId, progressMs, chapterTitle, durationMs };
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
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_PROGRESS_PREFIX + bookId);
    await s.flush();
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

  static async getSourceSubscriptions(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_SOURCE_SUBSCRIPTIONS, '[]') as string;
  }

  static async saveSourceSubscriptions(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_SOURCE_SUBSCRIPTIONS, json);
    await s.flush();
  }

  static async getBookSources(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_BOOK_SOURCES, '[]') as string;
  }

  static async saveBookSources(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_BOOK_SOURCES, json);
    await s.flush();
  }

  /** 内置源禁用列表（保存被用户关掉的内置源 ID） */
  static async getBuiltinDisabledIds(): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_BUILTIN_DISABLED, '[]') as string;
    try {
      const arr = JSON.parse(raw) as string[];
      return Array.isArray(arr) ? arr : [];
    } catch {
      return [];
    }
  }

  static async saveBuiltinDisabledIds(ids: string[]): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_BUILTIN_DISABLED, JSON.stringify(ids));
    await s.flush();
  }

  static async getDefaultTab(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_DEFAULT_TAB, 0) as number;
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

  // ──────────────────── 订阅源发现导航缓存 ────────────────────

  /**
   * 获取订阅源发现导航缓存（30 天 TTL，含版本戳）
   */
  static async getExploreNavCache(sourceUrl: string, sourceVersion: number): Promise<ExploreNavItem[] | null> {
    try {
      const s = await PreferenceService.ensureStore();
      const hash = PreferenceService.hashString(sourceUrl);
      const key = `${KEY_EXPLORE_NAV_PREFIX}${hash}`;
      const json = await s.get(key, '') as string;
      if (!json) return null;
      const cache: ExploreNavCache = JSON.parse(json) as ExploreNavCache;
      // 检查版本戳（源更新后自动失效）
      if (cache.sourceVersion !== sourceVersion) {
        return null;
      }
      // 检查 TTL（30 天）
      const age = Date.now() - cache.cachedAt;
      const TTL_MS = 30 * 24 * 60 * 60 * 1000;
      if (age > TTL_MS) {
        return null;
      }
      return cache.navigation;
    } catch (e) {
      console.warn(`[PreferenceService] getExploreNavCache failed: ${e}`);
      return null;
    }
  }

  /**
   * 保存订阅源发现导航缓存
   */
  static async setExploreNavCache(sourceUrl: string, sourceVersion: number, navigation: ExploreNavItem[]): Promise<void> {
    try {
      const s = await PreferenceService.ensureStore();
      const hash = PreferenceService.hashString(sourceUrl);
      const key = `${KEY_EXPLORE_NAV_PREFIX}${hash}`;
      const cache: ExploreNavCache = {
        sourceUrl,
        sourceVersion,
        navigation,
        cachedAt: Date.now(),
      };
      await s.put(key, JSON.stringify(cache));
      await s.flush();
    } catch (e) {
      console.warn(`[PreferenceService] setExploreNavCache failed: ${e}`);
    }
  }

  /** 简单字符串 hash（用于缓存 key） */
  private static hashString(str: string): string {
    let h: number = 5381;
    for (let i = 0; i < str.length; i++) {
      h = (((h << 5) + h) + str.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(36);
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
    return await s.get(KEY_PRELOAD_CHAPTERS, 3) as number;
  }

  static async setPreloadChapters(count: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PRELOAD_CHAPTERS, count);
    await s.flush();
  }
}
