import { common } from '@kit.AbilityKit';
import { Book } from '../model/Book';
import { PreferenceService } from './PreferenceService';

/**
 * 数据服务:承载本地导入的书 + 来自搜索的"缓存书"快照。
 * 缓存书让搜索得到的书也能被收藏 / 出现在书架 / 历史里。
 */
export class DataService {
  private static cache: Book[] | null = null;
  private static cachedBooksMem: Book[] | null = null;

  private static async load(): Promise<Book[]> {
    if (DataService.cache) return DataService.cache;
    DataService.cache = await DataService.getImportedBooks();
    return DataService.cache;
  }

  private static async loadCachedBooks(): Promise<Book[]> {
    if (DataService.cachedBooksMem) return DataService.cachedBooksMem;
    try {
      const json = await PreferenceService.getCachedBooks();
      const parsed: Object = JSON.parse(json) as Object;
      DataService.cachedBooksMem = parsed as Book[];
    } catch (_e) {
      DataService.cachedBooksMem = [];
    }
    return DataService.cachedBooksMem;
  }

  /** 返回:本地导入书 + 缓存书(去重,本地优先) */
  static async getBooks(_context: common.UIAbilityContext): Promise<Book[]> {
    const local = await DataService.load();
    const cached = await DataService.loadCachedBooks();
    const seen = new Set<string>();
    const merged: Book[] = [];
    for (const b of local) {
      if (!seen.has(b.id)) {
        merged.push(b);
        seen.add(b.id);
      }
    }
    for (const b of cached) {
      if (!seen.has(b.id)) {
        merged.push(b);
        seen.add(b.id);
      }
    }
    return merged;
  }

  static async getBookById(_context: common.UIAbilityContext, id: string): Promise<Book | undefined> {
    const local = await DataService.load();
    const fromLocal = local.find((b) => b.id === id);
    if (fromLocal) return fromLocal;
    const cached = await DataService.loadCachedBooks();
    return cached.find((b) => b.id === id);
  }

  static async getImportedBooks(): Promise<Book[]> {
    try {
      const json = await PreferenceService.getImportedBooks();
      const parsed: Object = JSON.parse(json) as Object;
      return parsed as Book[];
    } catch (_e) {
      return [];
    }
  }

  static async addImportedBook(book: Book): Promise<void> {
    const list = await DataService.getImportedBooks();
    list.unshift(book);
    await PreferenceService.saveImportedBooks(JSON.stringify(list));
    DataService.cache = list;
  }

  static async removeImportedBook(bookId: string): Promise<void> {
    const list = await DataService.getImportedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    await PreferenceService.saveImportedBooks(JSON.stringify(filtered));
    DataService.cache = filtered;
  }

  /** 把搜索 / 在线源的书写入缓存池(去重,新数据覆盖旧的;最多 200 本) */
  static async upsertCachedBook(book: Book): Promise<void> {
    if (!book || !book.id) return;
    if (book.id.startsWith('import_')) return;
    const list = await DataService.loadCachedBooks();
    const idx = list.findIndex((b) => b.id === book.id);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
    list.unshift(book);
    if (list.length > 200) {
      list.length = 200;
    }
    await PreferenceService.putCachedBookJson(JSON.stringify(list));
    DataService.cachedBooksMem = list;
  }

  static async removeCachedBook(bookId: string): Promise<void> {
    const list = await DataService.loadCachedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    await PreferenceService.putCachedBookJson(JSON.stringify(filtered));
    DataService.cachedBooksMem = filtered;
  }

  /**
   * 在 book.chapters 中定位历史记录对应的章节索引。
   * 章节 id 是位置型(`${book.id}-c${idx}`),连载更新/TOC 重排后会漂移,
   * 因此优先用 chapterTitle 匹配(标题对同一集是稳定的),id 仅作兜底。
   * 返回 -1 表示定位失败(章节已不存在)。
   */
  static resolveChapterIndex(book: Book, chapterId: string, chapterTitle?: string): number {
    if (!book || !book.chapters || book.chapters.length === 0) return -1;
    // 标题优先:连载在头部插新章后,旧 id 会指向错误位置,标题能纠正
    if (chapterTitle) {
      const byTitle = book.chapters.findIndex((c) => c.title === chapterTitle);
      if (byTitle >= 0) return byTitle;
    }
    // 兜底:老记录没存标题时回退到 id
    return book.chapters.findIndex((c) => c.id === chapterId);
  }
}
