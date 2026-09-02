import { Book } from '../model/Book';

/** 最大缓存条目数，防止内存无限增长 */
const MAX_CACHE_SIZE = 80;

const searchCache: Map<string, Book> = new Map();

export class SearchCache {
  static put(book: Book): void {
    const id = book.id;
    const existing = searchCache.get(id);
    if (existing && existing.chapters.length > 0 && book.chapters.length === 0) {
      book.chapters = existing.chapters;
      if (book.chapterCount < existing.chapters.length) {
        book.chapterCount = existing.chapters.length;
      }
    }
    if (existing && book.cover.trim().length === 0 && existing.cover.trim().length > 0) {
      book.cover = existing.cover;
    }
    // 若已存在先删除，确保重新插入后在 Map 末尾（LRU 顺序）
    if (searchCache.has(id)) {
      searchCache.delete(id);
    }
    searchCache.set(id, book);
    // 超出上限时淘汰最早的条目
    while (searchCache.size > MAX_CACHE_SIZE) {
      const firstKey = searchCache.keys().next();
      if (firstKey.done) break;
      searchCache.delete(firstKey.value as string);
    }
  }

  static get(id: string): Book | null {
    const book = searchCache.get(id);
    if (!book) return null;
    // LRU：命中后移到末尾，延长生命周期
    searchCache.delete(id);
    searchCache.set(id, book);
    return book;
  }

  static remove(id: string): void {
    if (!id) return;
    searchCache.delete(id);
  }

  static clear(): void {
    searchCache.clear();
  }

  static size(): number {
    return searchCache.size;
  }
}
