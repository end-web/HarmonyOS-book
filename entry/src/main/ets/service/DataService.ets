import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book } from '../model/Book';
import { PreferenceService } from './PreferenceService';

const CACHED_BOOKS_FILE = 'cached_books_v1.json';

/**
 * 数据服务:承载本地导入的书 + 来自搜索的"缓存书"快照。
 * 缓存书让搜索得到的书也能被收藏 / 出现在书架 / 历史里。
 *
 * 缓存书改用「文件」持久化(filesDir),不再放 preferences:
 * preferences 默认 XML 模式不支持多进程并发(本应用有卡片 FormExtension 进程),
 * 大数据(整章目录)并发读写会损坏文件 → 冷启动收藏丢失。文件单进程写,稳。
 */
export class DataService {
  private static cache: Book[] | null = null;
  private static cachedBooksMem: Book[] | null = null;
  private static ctx: common.Context | null = null;

  /** 由 EntryAbility 启动时注入,用于缓存书文件读写 */
  static setContext(c: common.Context): void {
    DataService.ctx = c;
  }

  private static cachedFilePath(): string | null {
    return DataService.ctx ? `${DataService.ctx.filesDir}/${CACHED_BOOKS_FILE}` : null;
  }

  private static async readCachedFile(): Promise<string> {
    const path = DataService.cachedFilePath();
    if (!path) return '';
    try {
      return await fileIo.readText(path);
    } catch (_e) {
      return ''; // 文件不存在/读失败
    }
  }

  private static async writeCachedFile(json: string): Promise<void> {
    const path = DataService.cachedFilePath();
    if (!path) return;
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, json);
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
  }

  private static async load(): Promise<Book[]> {
    if (DataService.cache) return DataService.cache;
    DataService.cache = await DataService.getImportedBooks();
    return DataService.cache;
  }

  private static async loadCachedBooks(): Promise<Book[]> {
    if (DataService.cachedBooksMem) return DataService.cachedBooksMem;
    // 1) 优先从文件读
    let json = await DataService.readCachedFile();
    // 2) 文件还没有 → 从旧的 preferences 迁移一次,迁完落文件
    if (!json) {
      try {
        const old = await PreferenceService.getCachedBooks();
        if (old && old !== '[]') {
          json = old;
          await DataService.writeCachedFile(old);
        }
      } catch (_e) { /* ignore */ }
    }
    try {
      DataService.cachedBooksMem = json ? (JSON.parse(json) as Book[]) : [];
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
    DataService.cachedBooksMem = list;
    await DataService.writeCachedFile(JSON.stringify(list));
  }

  static async removeCachedBook(bookId: string): Promise<void> {
    const list = await DataService.loadCachedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    DataService.cachedBooksMem = filtered;
    await DataService.writeCachedFile(JSON.stringify(filtered));
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
