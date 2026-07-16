/** 内置音频源注册表。 */
import { BookSource } from '../../model/BookSource';
import { BuiltInBook, IBuiltInSource } from './IBuiltInSource';

export const BUILTIN_SCHEME = 'builtin://eprendre/';

const sourcesById: Map<string, IBuiltInSource> = new Map();
const bookMetaCache: Map<string, BuiltInBook> = new Map();

class BuiltInBookSource implements BookSource {
  bookSourceUrl: string;
  bookSourceName: string;

  constructor(source: IBuiltInSource) {
    this.bookSourceUrl = BUILTIN_SCHEME + source.id;
    this.bookSourceName = source.name;
  }
}

export class BuiltInSourceRegistry {
  static register(source: IBuiltInSource): void {
    sourcesById.set(source.id, source);
  }

  static get(id: string): IBuiltInSource | undefined {
    return sourcesById.get(id);
  }

  static getByUrl(bookSourceUrl: string | undefined | null): IBuiltInSource | undefined {
    if (!bookSourceUrl || !bookSourceUrl.startsWith(BUILTIN_SCHEME)) return undefined;
    return sourcesById.get(bookSourceUrl.substring(BUILTIN_SCHEME.length));
  }

  static all(): IBuiltInSource[] {
    return Array.from(sourcesById.values());
  }

  static isBuiltIn(bookSourceUrl: string | undefined | null): boolean {
    return BuiltInSourceRegistry.getByUrl(bookSourceUrl) !== undefined;
  }

  static materialize(): BookSource[] {
    const list: BookSource[] = [];
    for (const source of BuiltInSourceRegistry.all()) {
      list.push(new BuiltInBookSource(source));
    }
    return list;
  }

  static toBookSource(source: IBuiltInSource): BookSource {
    return new BuiltInBookSource(source);
  }

  static cacheBookMeta(book: BuiltInBook): void {
    if (!book.bookUrl) return;
    bookMetaCache.set(book.bookUrl, book);
    if (bookMetaCache.size > 500) {
      const oldest = bookMetaCache.keys().next();
      if (!oldest.done && oldest.value !== undefined) {
        bookMetaCache.delete(oldest.value as string);
      }
    }
  }

  static getBookMeta(bookUrl: string): BuiltInBook | undefined {
    return bookMetaCache.get(bookUrl);
  }

  static evictBookMeta(bookUrl: string): void {
    if (!bookUrl) return;
    bookMetaCache.delete(bookUrl);
  }
}
