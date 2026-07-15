/**
 * 内置音频源门面。
 *
 * 页面和播放服务继续使用稳定接口，具体网络协议分别封装在各内置音频源中。
 */
import { BookInfo, BookSource, HomeBlockSection, SearchResult, TocItem } from '../model/BookSource';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { BuiltInDispatcher } from './builtin/BuiltInDispatcher';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';

export interface ExploreFetchResult {
  books: SearchResult[];
  nextUrl: string;
  nextPage?: number;
}

export interface AudioRequestInfo {
  url: string;
  headers: Record<string, string>;
}

export class BookSourceService {
  static async prepareAudioSource(bookSourceUrl: string): Promise<void> {
    await BuiltInDispatcher.prepareAudio(bookSourceUrl);
  }

  static getAudioResolveTimeoutMs(source: BookSource, fallbackMs: number): number {
    return BuiltInDispatcher.getAudioResolveTimeoutMs(source, fallbackMs);
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.search(source, keyword, page);
  }

  static async getBookInfo(source: BookSource, bookUrl: string,
    _variables?: Record<string, string>): Promise<BookInfo | null> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return null;
    return BuiltInDispatcher.getBookInfo(source, bookUrl);
  }

  static async getBookToc(source: BookSource, tocUrl: string,
    _variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    const items = await BuiltInDispatcher.getBookToc(source, tocUrl);
    const seen = new Set<string>();
    const unique: TocItem[] = [];
    for (const item of items) {
      if (!item.url || seen.has(item.url)) continue;
      seen.add(item.url);
      if (bookName) item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
      unique.push(item);
    }
    return unique;
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string,
    _variables?: Record<string, string>): Promise<string> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return chapterUrl;
    return BuiltInDispatcher.getAudioUrl(source, chapterUrl);
  }

  static async resolveAudioRequest(source: BookSource, chapterUrl: string,
    variables?: Record<string, string>): Promise<AudioRequestInfo> {
    const url = await BookSourceService.getAudioUrl(source, chapterUrl, variables);
    const headers = BuiltInDispatcher.getAudioHeaders(source, url);
    return { url, headers };
  }

  static async getExploreBooksByUrl(source: BookSource, categoryUrl: string,
    page: number = 1): Promise<ExploreFetchResult> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return { books: [], nextUrl: '' };
    return BuiltInDispatcher.getExploreBooksByUrl(source, categoryUrl, page);
  }

  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getExploreBooks(source);
  }

  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getHomeBlocks(source);
  }
}
