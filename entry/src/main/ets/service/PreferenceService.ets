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
const KEY_DEFAULT_TAB = 'default_tab';
const KEY_READER_FONT_SIZE = 'reader_font_size';
const KEY_READER_LINE_SPACING = 'reader_line_spacing';
const KEY_READER_BG_MODE = 'reader_bg_mode';
const KEY_READER_FONT_FAMILY = 'reader_font_family';
const KEY_READER_BRIGHTNESS = 'reader_brightness';
const KEY_READER_SCROLL_POS = 'reader_scroll_pos_v2';
const KEY_READER_BOOKMARKS = 'reader_bookmarks';
const KEY_READER_FLIP_MODE = 'reader_flip_mode';
const KEY_AUDIO_INTERRUPT_MODE = 'audio_interrupt_mode';
const KEY_AUDIO_AUTO_RESUME = 'audio_auto_resume';
const KEY_PRIVACY_AGREED_VERSION = 'privacy_agreed_version';

export interface PlayHistoryItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  updatedAt: number;
}

export interface LastPlayedItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
}

export interface ReaderBookmark {
  chapterId: string;
  chapterTitle: string;
  paraIndex: number;
  preview: string;
  addedAt: number;
}

interface ScrollPosEntry {
  key: string;
  paraIndex: number;
}

interface BookmarkBucket {
  bookId: string;
  list: ReaderBookmark[];
}

export class PreferenceService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
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

  static async ensureReady(context: common.UIAbilityContext): Promise<void> {
    if (PreferenceService.store) return;
    await PreferenceService.init(context);
  }

  private static ensureStore(): preferences.Preferences {
    if (!PreferenceService.store) {
      throw new Error('PreferenceService not initialized');
    }
    return PreferenceService.store;
  }

  static async getFavorites(): Promise<string[]> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_FAVORITES, '[]') as string;
    return JSON.parse(raw) as string[];
  }

  static async toggleFavorite(bookId: string): Promise<boolean> {
    const s = PreferenceService.ensureStore();
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
    return added;
  }

  static async isFavorite(bookId: string): Promise<boolean> {
    const list = await PreferenceService.getFavorites();
    return list.includes(bookId);
  }

  static async getHistory(): Promise<PlayHistoryItem[]> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_HISTORY, '[]') as string;
    return JSON.parse(raw) as PlayHistoryItem[];
  }

  static async upsertHistory(item: PlayHistoryItem): Promise<void> {
    const s = PreferenceService.ensureStore();
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
  }

  static async removeHistory(bookId: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    const list = await PreferenceService.getHistory();
    const filtered = list.filter((it) => it.bookId !== bookId);
    await s.put(KEY_HISTORY, JSON.stringify(filtered));
    await s.flush();
  }

  static async setLastPlayed(bookId: string, chapterId: string, progressMs: number = 0): Promise<void> {
    const s = PreferenceService.ensureStore();
    const item: LastPlayedItem = { bookId, chapterId, progressMs };
    await s.put(KEY_LAST_PLAYED, JSON.stringify(item));
    await s.flush();
  }

  static async getLastPlayed(): Promise<LastPlayedItem | null> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_LAST_PLAYED, '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as LastPlayedItem;
    } catch (e) {
      return null;
    }
  }

  static async getColorMode(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_COLOR_MODE, ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) as number;
  }

  static async setColorMode(mode: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_COLOR_MODE, mode);
    await s.flush();
  }

  static async getImportedBooks(): Promise<string> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_IMPORTED_BOOKS, '[]') as string;
  }

  static async saveImportedBooks(json: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_IMPORTED_BOOKS, json);
    await s.flush();
  }

  static async getSourceSubscriptions(): Promise<string> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_SOURCE_SUBSCRIPTIONS, '[]') as string;
  }

  static async saveSourceSubscriptions(json: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_SOURCE_SUBSCRIPTIONS, json);
    await s.flush();
  }

  static async getBookSources(): Promise<string> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_BOOK_SOURCES, '[]') as string;
  }

  static async saveBookSources(json: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_BOOK_SOURCES, json);
    await s.flush();
  }

  static async getDefaultTab(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_DEFAULT_TAB, 0) as number;
  }

  static async setDefaultTab(idx: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_DEFAULT_TAB, idx);
    await s.flush();
  }

  static async getReaderFontSize(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_FONT_SIZE, 18) as number;
  }

  static async setReaderFontSize(size: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_FONT_SIZE, size);
    await s.flush();
  }

  static async getReaderLineSpacing(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_LINE_SPACING, 1.8) as number;
  }

  static async setReaderLineSpacing(v: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_LINE_SPACING, v);
    await s.flush();
  }

  static async getReaderBgMode(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_BG_MODE, -1) as number;
  }

  static async setReaderBgMode(mode: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_BG_MODE, mode);
    await s.flush();
  }

  static async getReaderFontFamily(): Promise<string> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_FONT_FAMILY, 'HarmonyOS Sans') as string;
  }

  static async setReaderFontFamily(family: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_FONT_FAMILY, family);
    await s.flush();
  }

  static async getPrivacyAgreedVersion(): Promise<string> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_PRIVACY_AGREED_VERSION, '') as string;
  }

  static async setPrivacyAgreedVersion(version: string): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_PRIVACY_AGREED_VERSION, version);
    await s.flush();
  }

  static async getReaderBrightness(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_BRIGHTNESS, -1) as number;
  }

  static async setReaderBrightness(v: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_BRIGHTNESS, v);
    await s.flush();
  }

  /** 0=共享焦点（默认，听书与其他音乐互斥）, 1=独立焦点（不与本应用其他音频互斥） */
  static async getAudioInterruptMode(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_INTERRUPT_MODE, 0) as number;
  }

  static async setAudioInterruptMode(mode: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_INTERRUPT_MODE, mode);
    await s.flush();
  }

  /** 失去焦点暂停后，是否在系统通知 RESUME 时自动恢复播放 */
  static async getAudioAutoResume(): Promise<boolean> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_AUTO_RESUME, true) as boolean;
  }

  static async setAudioAutoResume(enabled: boolean): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_AUTO_RESUME, enabled);
    await s.flush();
  }

  static async getReaderFlipMode(): Promise<number> {
    const s = PreferenceService.ensureStore();
    return await s.get(KEY_READER_FLIP_MODE, 0) as number;
  }

  static async setReaderFlipMode(v: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    await s.put(KEY_READER_FLIP_MODE, v);
    await s.flush();
  }

  static async getReaderScrollPos(bookId: string, chapterId: string): Promise<number> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_READER_SCROLL_POS, '[]') as string;
    const arr = JSON.parse(raw) as ScrollPosEntry[];
    const key = `${bookId}:${chapterId}`;
    const hit = arr.find((e) => e.key === key);
    return hit ? hit.paraIndex : 0;
  }

  static async setReaderScrollPos(bookId: string, chapterId: string, paraIndex: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_READER_SCROLL_POS, '[]') as string;
    const arr = JSON.parse(raw) as ScrollPosEntry[];
    const key = `${bookId}:${chapterId}`;
    const idx = arr.findIndex((e) => e.key === key);
    if (paraIndex <= 0) {
      if (idx >= 0) arr.splice(idx, 1);
    } else if (idx >= 0) {
      arr[idx].paraIndex = paraIndex;
    } else {
      arr.push({ key, paraIndex });
    }
    if (arr.length > 200) {
      arr.splice(0, arr.length - 200);
    }
    await s.put(KEY_READER_SCROLL_POS, JSON.stringify(arr));
    await s.flush();
  }

  static async getBookmarks(bookId: string): Promise<ReaderBookmark[]> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_READER_BOOKMARKS, '[]') as string;
    const arr = JSON.parse(raw) as BookmarkBucket[];
    const hit = arr.find((b) => b.bookId === bookId);
    return hit ? hit.list : [];
  }

  static async addBookmark(bookId: string, mark: ReaderBookmark): Promise<void> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_READER_BOOKMARKS, '[]') as string;
    const arr = JSON.parse(raw) as BookmarkBucket[];
    let bucket = arr.find((b) => b.bookId === bookId);
    if (!bucket) {
      bucket = { bookId, list: [] };
      arr.push(bucket);
    }
    const dup = bucket.list.findIndex((m) => m.chapterId === mark.chapterId && m.paraIndex === mark.paraIndex);
    if (dup >= 0) bucket.list.splice(dup, 1);
    bucket.list.unshift(mark);
    if (bucket.list.length > 100) {
      bucket.list.length = 100;
    }
    await s.put(KEY_READER_BOOKMARKS, JSON.stringify(arr));
    await s.flush();
  }

  static async removeBookmark(bookId: string, chapterId: string, paraIndex: number): Promise<void> {
    const s = PreferenceService.ensureStore();
    const raw = await s.get(KEY_READER_BOOKMARKS, '[]') as string;
    const arr = JSON.parse(raw) as BookmarkBucket[];
    const bucket = arr.find((b) => b.bookId === bookId);
    if (!bucket) return;
    bucket.list = bucket.list.filter((m) => !(m.chapterId === chapterId && m.paraIndex === paraIndex));
    await s.put(KEY_READER_BOOKMARKS, JSON.stringify(arr));
    await s.flush();
  }
}
