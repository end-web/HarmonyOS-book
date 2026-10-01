import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Book, Chapter } from '../../model/Book';
import { BookSource, SearchResult } from '../../model/BookSource';
import { BookIdentity } from '../../utils/BookIdentity';
import { BookSourceService } from '../BookSourceService';
import { DataService } from '../DataService';
import { DownloadStore } from '../DownloadStore';
import { PreferenceService } from '../PreferenceService';
import { SourceDataService } from '../SourceDataService';
import { LocalRuleSourceImportParser } from '../rulesource/LocalRuleSourceImportParser';
import { LocalRuleSourceImportService } from '../rulesource/LocalRuleSourceImportService';

export class WearableSearchResult {
  books: Book[] = [];
  sourceCount: number = 0;
  failedCount: number = 0;
}

/** 复用已有规则运行边界、书籍身份和持久缓存，不另建手表内容源。 */
export class WearableLibraryService {
  static async shelf(context: common.UIAbilityContext): Promise<Book[]> {
    const ids = new Set<string>(await PreferenceService.getFavorites());
    for (const item of DownloadStore.getBooksSync()) ids.add(item.bookId);
    const books: Book[] = [];
    for (const id of ids) {
      const book = await DataService.getBookById(context, id);
      if (book && book.contentType !== 'text') books.push(book);
    }
    return books;
  }

  static async search(keyword: string, page: number, cancelled: () => boolean): Promise<WearableSearchResult> {
    const result = new WearableSearchResult();
    const sources = (await SourceDataService.getEnabledSources()).filter((source: BookSource): boolean =>
      source.bookSourceType === undefined || source.bookSourceType === 1);
    result.sourceCount = sources.length;
    const seen = new Set<string>();
    for (let offset = 0; offset < sources.length && !cancelled(); offset += 6) {
      const batches = await Promise.all(sources.slice(offset, offset + 6).map(async (source: BookSource): Promise<SearchResult[]> => {
        try {
          return await BookSourceService.searchBooks(source, keyword, page);
        } catch (_error) {
          result.failedCount++;
          return [];
        }
      }));
      if (cancelled()) break;
      for (const batch of batches) {
        for (const item of batch) {
          if (item.contentType === 'text') continue;
          const book = WearableLibraryService.toBook(item);
          if (seen.has(book.id)) continue;
          seen.add(book.id);
          result.books.push(book);
        }
      }
    }
    return result;
  }

  static toBook(result: SearchResult): Book {
    const chapters: Chapter[] = [];
    const book: Book = {
      id: BookIdentity.onlineAudioBookId(result.sourceUrl, result.bookUrl || result.name),
      contentType: 'audio', title: result.name, author: result.author, narrator: result.sourceName,
      cover: result.coverUrl, category: result.kind, intro: result.intro, totalDuration: 0,
      chapterCount: 0, rating: 0, tags: [result.sourceName], chapters: chapters,
      bookUrl: result.bookUrl, sourceUrl: result.sourceUrl, variables: result.variables,
      completed: result.completed
    };
    return book;
  }

  static async openBook(book: Book): Promise<Book> {
    if (book.chapters.length > 0) return book;
    return BookSourceService.loadAudioBook(book, (): void => {});
  }

  static async importSource(address: string): Promise<number> {
    const maxBytes = 2 * 1024 * 1024;
    const value = address.trim();
    if (!value.startsWith('https://') || value.length > 4096) throw new Error('invalid_source_address');
    const request = http.createHttp();
    try {
      const response = await request.request(value, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000, readTimeout: 20000, maxLimit: maxBytes
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string' || response.result.length > maxBytes) {
        throw new Error('source_response_rejected');
      }
      const report = LocalRuleSourceImportParser.parse(response.result);
      if (report.sources.length === 0) throw new Error('no_sources');
      const count = await LocalRuleSourceImportService.importSources(report.sources);
      SourceDataService.invalidateLocalSources();
      if (count === 0) throw new Error('no_imported_sources');
      return count;
    } finally {
      request.destroy();
    }
  }
}
