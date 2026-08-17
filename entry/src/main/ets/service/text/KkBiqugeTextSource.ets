import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book } from '../../model/Book';
import { TextChapterContent, TextSourceError } from '../../model/TextReading';
import { HttpClient, HttpResponse } from '../http/HttpClient';
import { SearchCache } from '../../utils/SearchCache';
import {
  KK_BIQU_GE_BASE_URL,
  KK_BIQU_GE_SOURCE_NAME,
  KK_BIQU_GE_SOURCE_URL,
  KkBiqugeHtmlParser
} from './KkBiqugeHtmlParser';

const SEARCH_INTERVAL_MS: number = 30000;
const MAX_CONTENT_PAGES: number = 32;
const TEXT_SOURCE_LOG_DOMAIN: number = 0x0000;
const TEXT_SOURCE_LOG_TAG: string = 'KkTextSource';

export class KkBiqugeTextSource {
  static readonly id: string = 'kk_biquge';
  static readonly displayName: string = KK_BIQU_GE_SOURCE_NAME;
  static readonly sourceUrl: string = KK_BIQU_GE_SOURCE_URL;
  static readonly homeUrl: string = KK_BIQU_GE_BASE_URL;

  private static searchAction: string = '';
  private static sessionCookies: Map<string, string> = new Map();
  private static lastSearchAt: number = 0;
  private static searchCache: Map<string, Book[]> = new Map();
  private static contentCache: Map<string, TextChapterContent> = new Map();
  private static contentRequests: Map<string, Promise<TextChapterContent>> = new Map();

  static async search(keyword: string): Promise<Book[]> {
    const key = keyword.trim();
    if (!key) return [];
    const cached = KkBiqugeTextSource.searchCache.get(key);
    if (cached !== undefined) return cached.slice();
    const now = Date.now();
    const remaining = SEARCH_INTERVAL_MS - (now - KkBiqugeTextSource.lastSearchAt);
    if (KkBiqugeTextSource.lastSearchAt > 0 && remaining > 0) {
      throw new TextSourceError('SEARCH_RATE_LIMIT', '电子书源搜索间隔为30秒', Math.ceil(remaining / 1000));
    }
    const startedAt = Date.now();
    try {
      const action = await KkBiqugeTextSource.getSearchAction();
      const separator = action.indexOf('?') >= 0 ? '&' : '?';
      const html = await KkBiqugeTextSource.getHtml(`${action}${separator}searchkey=${encodeURIComponent(key)}`);
      KkBiqugeTextSource.lastSearchAt = Date.now();
      const books = KkBiqugeHtmlParser.parseSearch(html);
      KkBiqugeTextSource.searchCache.set(key, books.slice());
      for (const book of books) SearchCache.put(book);
      hilog.info(TEXT_SOURCE_LOG_DOMAIN, TEXT_SOURCE_LOG_TAG,
        'search parsed, keyword=%{public}s books=%{public}d elapsedMs=%{public}d',
        key, books.length, Date.now() - startedAt);
      return books;
    } catch (e) {
      const error = e instanceof Error ? e : new Error(String(e));
      hilog.error(TEXT_SOURCE_LOG_DOMAIN, TEXT_SOURCE_LOG_TAG,
        'search failed, keyword=%{public}s elapsedMs=%{public}d error=%{public}s',
        key, Date.now() - startedAt, error.message);
      throw error;
    }
  }

  static async loadBook(book: Book): Promise<Book> {
    if (!book.bookUrl) throw new TextSourceError('INVALID_BOOK_URL', '电子书地址为空');
    const startedAt = Date.now();
    const html = await KkBiqugeTextSource.getHtml(book.bookUrl);
    const value = KkBiqugeHtmlParser.applyDetail(book, html);
    SearchCache.put(value);
    hilog.info(TEXT_SOURCE_LOG_DOMAIN, TEXT_SOURCE_LOG_TAG,
      'detail parsed, id=%{public}s chapters=%{public}d elapsedMs=%{public}d',
      value.id, value.chapters.length, Date.now() - startedAt);
    return value;
  }

  static async getChapterContent(url: string, title: string): Promise<TextChapterContent> {
    const cached = KkBiqugeTextSource.contentCache.get(url);
    if (cached !== undefined) return cached;
    const pending = KkBiqugeTextSource.contentRequests.get(url);
    if (pending !== undefined) return pending;
    const request = KkBiqugeTextSource.loadChapterContent(url, title);
    KkBiqugeTextSource.contentRequests.set(url, request);
    try {
      return await request;
    } finally {
      KkBiqugeTextSource.contentRequests.delete(url);
    }
  }

  private static async loadChapterContent(url: string, title: string): Promise<TextChapterContent> {
    const startedAt = Date.now();
    let currentUrl = url;
    let content = '';
    let pageCount = 0;
    const visitedUrls = new Set<string>();
    for (let page = 0; page < MAX_CONTENT_PAGES && currentUrl; page++) {
      if (visitedUrls.has(currentUrl)) break;
      visitedUrls.add(currentUrl);
      const html = await KkBiqugeTextSource.getHtml(currentUrl);
      const part = KkBiqugeHtmlParser.parseContent(title, currentUrl, html);
      if (part.content) content += (content ? '\n\n' : '') + part.content;
      pageCount++;
      const nextUrl = KkBiqugeHtmlParser.nextContentUrl(currentUrl, html);
      if (!nextUrl || nextUrl === currentUrl || visitedUrls.has(nextUrl)) break;
      currentUrl = nextUrl;
    }
    if (!content) throw new TextSourceError('EMPTY_CONTENT', '章节正文为空');
    const result = TextChapterContent.of(title, content, url);
    if (KkBiqugeTextSource.contentCache.size >= 20) KkBiqugeTextSource.contentCache.clear();
    KkBiqugeTextSource.contentCache.set(url, result);
    hilog.info(TEXT_SOURCE_LOG_DOMAIN, TEXT_SOURCE_LOG_TAG,
      'content parsed, pages=%{public}d chars=%{public}d elapsedMs=%{public}d',
      pageCount, content.length, Date.now() - startedAt);
    return result;
  }

  static needsVerification(error: Error): boolean {
    return error instanceof TextSourceError && error.code === 'VERIFY_REQUIRED';
  }

  static clearSearchCache(): void {
    KkBiqugeTextSource.searchCache.clear();
  }

  private static async getSearchAction(): Promise<string> {
    if (KkBiqugeTextSource.searchAction) return KkBiqugeTextSource.searchAction;
    const html = await KkBiqugeTextSource.getHtml(KK_BIQU_GE_BASE_URL + '/');
    KkBiqugeTextSource.searchAction = KkBiqugeHtmlParser.parseSearchAction(html);
    return KkBiqugeTextSource.searchAction;
  }

  private static async getHtml(url: string): Promise<string> {
    let response = await HttpClient.request(url, {
      method: 'GET',
      headers: KkBiqugeTextSource.requestHeaders(),
      timeout: 15000,
      retry: 1
    });
    KkBiqugeTextSource.captureSessionCookies(response);
    if (response.statusCode === 403 || KkBiqugeHtmlParser.isVerificationPage(response.body)) {
      hilog.info(TEXT_SOURCE_LOG_DOMAIN, TEXT_SOURCE_LOG_TAG,
        'challenge received, retry with cookies, status=%{public}d', response.statusCode);
      response = await HttpClient.request(url, {
        method: 'GET',
        headers: KkBiqugeTextSource.requestHeaders(),
        timeout: 15000,
        retry: 1
      });
      KkBiqugeTextSource.captureSessionCookies(response);
    }
    if (KkBiqugeHtmlParser.isVerificationPage(response.body)) {
      throw new TextSourceError('VERIFY_REQUIRED', '电子书源需要完成浏览器验证');
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw new TextSourceError('HTTP_ERROR', `电子书源请求失败 (${response.statusCode})`);
    }
    return response.body;
  }

  private static requestHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': KK_BIQU_GE_BASE_URL + '/'
    };
    const cookie = KkBiqugeTextSource.bestCookieHeader();
    if (cookie) headers['Cookie'] = cookie;
    return headers;
  }

  private static bestCookieHeader(): string {
    const serverCookies: string[] = [];
    KkBiqugeTextSource.sessionCookies.forEach((value: string, name: string): void => {
      serverCookies.push(`${name}=${value}`);
    });
    if (serverCookies.length > 0) return serverCookies.join('; ');
    try {
      const browserCookie = webview.WebCookieManager.fetchCookieSync(KK_BIQU_GE_BASE_URL);
      if (browserCookie) return browserCookie;
    } catch (_e) {
      // Web引擎尚未创建时使用HTTP会话Cookie。
    }
    return '';
  }

  private static captureSessionCookies(response: HttpResponse): void {
    const keys = Object.keys(response.headers);
    for (const key of keys) {
      if (key.toLowerCase() !== 'set-cookie') continue;
      const pattern = new RegExp('(?:^|,\\s*|\\n\\s*)([A-Za-z0-9_.-]+)=([^;,\\s]+)', 'g');
      let match: RegExpExecArray | null = pattern.exec(response.headers[key]);
      while (match !== null) {
        if (match.length > 2) KkBiqugeTextSource.sessionCookies.set(match[1], match[2]);
        match = pattern.exec(response.headers[key]);
      }
    }
  }
}
