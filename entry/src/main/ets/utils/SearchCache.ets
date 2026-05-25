import { Book } from '../model/Book';

const searchCache: Map<string, Book> = new Map();

export class SearchCache {
  static put(book: Book): void {
    searchCache.set(book.id, book);
  }

  static get(id: string): Book | null {
    return searchCache.get(id) || null;
  }

  static clear(): void {
    searchCache.clear();
  }
}
