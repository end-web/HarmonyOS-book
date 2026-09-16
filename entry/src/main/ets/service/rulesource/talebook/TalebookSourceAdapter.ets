import { BookInfo, BookSource, SearchResult, TocItem } from '../../../model/BookSource';
import { LocalRuleExploreResult } from '../../../model/LocalRulePanel';
import { LocalRuleContentResult } from '../LocalRuleRuntimeTypes';
import { LocalRuleHttpClient } from '../LocalRuleHttpClient';
import { TalebookApiClient } from './TalebookApiClient';
import { TalebookSourceIdentity } from './TalebookSourceIdentity';
import { TalebookEpub } from './TalebookEpub';
import { KkBiqugeHtmlParser } from '../../text/KkBiqugeHtmlParser';
import { CoverPrefetcher } from '../../CoverPrefetcher';

class TalebookFile {
  format: string = '';
  href: string = '';
}
class TalebookEdition {
  id: number = 0;
  book_id: number = 0;
  chapter_count: number = 0;
  chapters: TalebookChapter[] = [];
}
class TalebookChapter {
  number: number = 0;
  title: string = '';
  duration_ms: number = 0;
  audio_url: string = '';
}
class TalebookBook {
  id: number = 0;
  title: string = '';
  author: string = '';
  img: string = '';
  comments: string = '';
  edition: TalebookEdition = new TalebookEdition();
  files: TalebookFile[] = [];
}
class TalebookBooksResponse {
  total: number = 0;
  books: TalebookBook[] = [];
  book: TalebookBook = new TalebookBook();
  manifest: TalebookEdition = new TalebookEdition();
}

export class TalebookSourceAdapter {
  static async search(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    return (await TalebookSourceAdapter.list(source, keyword.trim(), page)).books;
  }

  static async list(source: BookSource, keyword: string = '', page: number = 1): Promise<LocalRuleExploreResult> {
    const audio = TalebookSourceIdentity.isAudio(source.bookSourceUrl);
    const offset = (Math.max(1, Math.floor(page)) - 1) * 60;
    const path = audio ? '/api/audios' : keyword
      ? `/api/search?name=${encodeURIComponent(keyword)}&start=${offset}&size=60`
      : `/api/recent?start=${offset}&size=60`;
    const body = await TalebookApiClient.request(source.bookSourceUrl, path);
    const response: TalebookBooksResponse = JSON.parse(body);
    if (!Array.isArray(response.books)) throw new Error('Talebook 书单格式不正确');
    let rows = response.books;
    if (audio) {
      const query = keyword.toLowerCase();
      rows = rows.filter((row: TalebookBook): boolean =>
        !query || `${row.title} ${row.author}`.toLowerCase().includes(query));
    }
    const total = audio ? rows.length : response.total;
    if (audio) rows = rows.slice(offset, offset + 60);
    const result = new LocalRuleExploreResult();
    const coverHeaders: Record<string, string> = {
      'Cookie': await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl,
        `${TalebookSourceIdentity.origin(source.bookSourceUrl)}/`)
    };
    for (const row of rows.slice(0, 60)) {
      if (!Number.isSafeInteger(row.id) || row.id <= 0 || !row.title) continue;
      if (audio && (!row.edition || !Number.isSafeInteger(row.edition.id) || row.edition.id <= 0)) continue;
      const bookUrl = TalebookApiClient.address(source.bookSourceUrl, audio
        ? `/api/audio/${row.edition.id}` : `/api/book/${row.id}`);
      const item: SearchResult = {
        name: row.title, author: row.author || '', coverUrl: row.img
          ? TalebookApiClient.address(source.bookSourceUrl, row.img) : '',
        bookUrl: bookUrl, intro: KkBiqugeHtmlParser.cleanText(row.comments || ''),
        kind: '', lastChapter: '', contentType: audio ? 'audio' : 'text',
        sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl
      };
      if (item.coverUrl) CoverPrefetcher.registerHeaders(item.coverUrl, coverHeaders);
      result.books.push(item);
    }
    if (rows.length > 0 && offset + 60 < total) {
      result.nextUrl = TalebookApiClient.address(source.bookSourceUrl, audio ? '/api/audios' : '/api/recent');
    }
    return result;
  }

  private static id(sourceUrl: string, address: string, audio: boolean): number {
    const target = TalebookApiClient.address(sourceUrl, address);
    const prefix = `${TalebookSourceIdentity.origin(sourceUrl)}/api/${audio ? 'audio' : 'book'}/`;
    const value = target.startsWith(prefix) ? target.substring(prefix.length) : '';
    if (!new RegExp('^[1-9][0-9]*$').test(value) || !Number.isSafeInteger(Number(value))) {
      throw new Error('Talebook 书籍地址无效');
    }
    return Number(value);
  }

  static async info(sourceUrl: string, bookUrl: string): Promise<BookInfo> {
    const audio = TalebookSourceIdentity.isAudio(sourceUrl);
    let id = TalebookSourceAdapter.id(sourceUrl, bookUrl, audio);
    if (audio) {
      const manifest: TalebookBooksResponse = JSON.parse(await TalebookApiClient.request(sourceUrl, `/api/audio/${id}`));
      id = manifest.manifest?.book_id ?? 0;
      if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Talebook 音频书籍信息缺失');
    }
    const response: TalebookBooksResponse = JSON.parse(await TalebookApiClient.request(sourceUrl, `/api/book/${id}`));
    const book = response.book;
    if (!book || !book.title) throw new Error('Talebook 书籍不存在');
    const info: BookInfo = {
      name: book.title, author: book.author || '', coverUrl: book.img
        ? TalebookApiClient.address(sourceUrl, book.img) : '',
      intro: KkBiqugeHtmlParser.cleanText(book.comments || ''), kind: '', wordCount: '',
      lastChapter: '', tocUrl: bookUrl
    };
    if (info.coverUrl) CoverPrefetcher.registerHeaders(info.coverUrl, {
      'Cookie': await LocalRuleHttpClient.getStoredCookieHeader(sourceUrl, info.coverUrl)
    });
    return info;
  }

  static async toc(sourceUrl: string, tocUrl: string): Promise<TocItem[]> {
    const audio = TalebookSourceIdentity.isAudio(sourceUrl);
    const id = TalebookSourceAdapter.id(sourceUrl, tocUrl, audio);
    if (audio) {
      const response: TalebookBooksResponse = JSON.parse(await TalebookApiClient.request(sourceUrl, `/api/audio/${id}`));
      if (!response.manifest || !Array.isArray(response.manifest.chapters)) throw new Error('Talebook 音频目录缺失');
      const result: TocItem[] = [];
      const seen = new Set<string>();
      for (const chapter of response.manifest.chapters.slice(0, 20000)) {
        const address = TalebookApiClient.address(sourceUrl, chapter.audio_url);
        TalebookSourceAdapter.requireAudioPath(sourceUrl, address);
        if (seen.has(address)) continue;
        seen.add(address);
        const item: TocItem = {
          name: chapter.title || `第 ${chapter.number} 章`, url: address,
          duration: Math.max(0, Math.floor((chapter.duration_ms || 0) / 1000))
        };
        result.push(item);
      }
      return result;
    }
    const response: TalebookBooksResponse = JSON.parse(await TalebookApiClient.request(sourceUrl, `/api/book/${id}`));
    const files = response.book?.files ?? [];
    if (files.some((file: TalebookFile): boolean => file.format.toUpperCase() === 'EPUB')) {
      return TalebookEpub.toc(sourceUrl, id);
    }
    if (files.some((file: TalebookFile): boolean => file.format.toUpperCase() === 'TXT')) {
      const chapter: TocItem = { name: response.book.title, url: TalebookApiClient.address(sourceUrl, `/api/book/${id}.TXT`) };
      return [chapter];
    }
    throw new Error('当前 Talebook 阅读支持 EPUB 和 TXT；此书没有可用格式');
  }

  private static requireAudioPath(sourceUrl: string, address: string): void {
    const path = address.substring(TalebookSourceIdentity.origin(sourceUrl).length);
    if (!new RegExp('^/media/audio/[1-9][0-9]*/chapter/[1-9][0-9]*\\.mp3$').test(path)) {
      throw new Error('Talebook 音频地址无效');
    }
  }

  static async content(sourceUrl: string, chapterUrl: string): Promise<LocalRuleContentResult> {
    const address = TalebookApiClient.address(sourceUrl, chapterUrl);
    const result = new LocalRuleContentResult();
    if (TalebookSourceIdentity.isAudio(sourceUrl)) {
      TalebookSourceAdapter.requireAudioPath(sourceUrl, address);
      // 删除来源后不允许仅凭旧章节地址继续读取或复用会话。
      await TalebookApiClient.request(sourceUrl, '/api/user/info');
      result.audioUrl = address;
      result.requestHeaders = {
        'Cookie': await LocalRuleHttpClient.getStoredCookieHeader(sourceUrl, address),
        'Referer': `${TalebookSourceIdentity.origin(sourceUrl)}/`
      };
      return result;
    }
    const path = address.substring(TalebookSourceIdentity.origin(sourceUrl).length);
    if (new RegExp('^/api/book/[1-9][0-9]*\\.TXT$', 'i').test(path)) {
      result.content = await TalebookApiClient.request(sourceUrl, address, false);
    } else {
      const prefix = new RegExp('^/get/extract/[1-9][0-9]*/').exec(path);
      if (!prefix) throw new Error('Talebook 正文地址无效');
      TalebookEpub.resource(`${TalebookSourceIdentity.origin(sourceUrl)}${prefix[0]}`, address, address);
      result.content = TalebookEpub.content(await TalebookApiClient.request(sourceUrl, address, false));
    }
    if (!result.content.trim()) throw new Error('Talebook 未返回正文');
    return result;
  }
}
