import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book } from '../model/Book';
import { PreferenceService } from './PreferenceService';

const CACHED_BOOKS_FILE = 'cached_books_v1.json';
/** 旧 preferences 缓存超过此字节数即判定含整章 TOC 巨值,合并进文件后压成元数据壳 */
const LEGACY_SLIM_THRESHOLD = 100 * 1024;

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
    let fileBooks = DataService.parseBookList(json);
    const favoriteIds = await DataService.safeFavoriteIds();
    if (json && fileBooks.length > 0 && DataService.containsAll(fileBooks, favoriteIds)) {
      DataService.cachedBooksMem = fileBooks;
      return DataService.cachedBooksMem;
    }

    // 2) 文件还没有 → 从旧的 preferences 迁移一次,迁完落文件
    //    文件已有但缺少收藏书时,也从旧缓存补齐。之前只在文件不存在时迁移,
    //    导致已生成的 1 本文件缓存挡住旧 preferences 里的完整书架缓存。
    let legacyRaw = '';
    let legacyBooks: Book[] = [];
    try {
      legacyRaw = await PreferenceService.getCachedBooks();
      legacyBooks = DataService.parseBookList(legacyRaw);
    } catch (_e) { /* ignore */ }

    if (legacyBooks.length > 0) {
      const merged = DataService.mergeBookLists(fileBooks, legacyBooks);
      if (merged.length !== fileBooks.length) {
        fileBooks = merged;
        await DataService.writeCachedFile(JSON.stringify(fileBooks));
      }
      // 一次性根治:旧 preferences 缓存把整章 TOC 攒成了 ~23MB 巨值。
      // preferences XML 模式每次 flush 都会全量重写整个 store(24MB) → 主进程 + 卡片
      // FormExtension 并发写时极易损坏,把幸存的收藏/进度一并带走(这正是收藏丢失的元凶)。
      // 确认这些书已并入文件缓存后,把 preferences 里的值压成"仅元数据壳"(去掉 chapters):
      // 体积降到几十 KB,既消除并发损坏隐患,又保留卡片冷启动兜底所需的标题/封面。
      if (legacyRaw.length > LEGACY_SLIM_THRESHOLD) {
        try {
          const slim: Book[] = legacyBooks.map((b: Book): Book => DataService.slimBook(b));
          await PreferenceService.putCachedBookJson(JSON.stringify(slim));
        } catch (_e) { /* 压缩失败保持原值,下次冷启动重试 */ }
      }
    }
    DataService.cachedBooksMem = fileBooks;
    return DataService.cachedBooksMem;
  }

  private static parseBookList(json: string): Book[] {
    if (!json || json === '[]') return [];
    try {
      const parsed: Object = JSON.parse(json) as Object;
      if (!Array.isArray(parsed)) return [];
      return parsed as Book[];
    } catch (_e) {
      return [];
    }
  }

  private static async safeFavoriteIds(): Promise<string[]> {
    try {
      return await PreferenceService.getFavorites();
    } catch (_e) {
      return [];
    }
  }

  private static containsAll(books: Book[], ids: string[]): boolean {
    if (ids.length === 0) return true;
    const set = new Set<string>();
    for (const book of books) {
      if (book && book.id) set.add(book.id);
    }
    for (const id of ids) {
      if (!set.has(id)) return false;
    }
    return true;
  }

  private static mergeBookLists(primary: Book[], legacy: Book[]): Book[] {
    const seen = new Set<string>();
    const merged: Book[] = [];
    for (const book of primary) {
      if (!book || !book.id || seen.has(book.id)) continue;
      merged.push(book);
      seen.add(book.id);
    }
    for (const book of legacy) {
      if (!book || !book.id || seen.has(book.id)) continue;
      merged.push(book);
      seen.add(book.id);
    }
    return merged;
  }

  /** 元数据壳:卡片冷启动兜底只用 id/标题/作者/封面,去掉 chapters + intro 砍掉绝大部分体积 */
  private static slimBook(b: Book): Book {
    return {
      id: b.id,
      contentType: b.contentType,
      title: b.title,
      author: b.author,
      narrator: b.narrator,
      cover: b.cover,
      category: b.category,
      intro: '',
      totalDuration: b.totalDuration,
      chapterCount: b.chapterCount,
      rating: b.rating,
      tags: b.tags,
      chapters: [],
      bookUrl: b.bookUrl,
      sourceUrl: b.sourceUrl,
      variables: b.variables,
      skipIntro: b.skipIntro,
      skipOutro: b.skipOutro
    };
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

  /** 清空缓存书池(文件 + 内存),用于"清空书架"。 */
  static async clearCachedBooks(): Promise<void> {
    DataService.cachedBooksMem = [];
    const path = DataService.cachedFilePath();
    if (path) {
      try { await fileIo.unlink(path); } catch (_e) { /* ignore */ }
    }
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
