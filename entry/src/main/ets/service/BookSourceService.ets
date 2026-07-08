import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookSource, SearchResult, TocItem, SourceSubscription, BookInfo, HomeBlockSection } from '../model/BookSource';
import { AnalyzeRule, AnalyzeContext, BookContext } from './rule/AnalyzeRule';
import { AnalyzeUrl, AnalyzedUrl } from './rule/AnalyzeUrl';
import { HttpClient } from './http/HttpClient';
import { HttpResult } from './http/HttpResult';
import { SourceDataService } from './SourceDataService';
import { getJSExecutor } from './js/JSExecutor';
import { getSourceContext } from './rule/SourceContext';
import { getJsoup } from './rule/JsoupBridge';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';
import { BuiltInDispatcher } from './builtin/BuiltInDispatcher';
import { getWebViewAudioExtractor } from './builtin/WebViewAudioExtractor';
import { DataUrlHandler } from './DataUrlHandler';
import { getJavaBridge } from './rule/JavaBridge';
import { getCookieManager } from './rule/CookieManager';
import { SourceVariableStore } from './SourceVariableStore';
import { getCacheService } from './CacheService';
import { getRateLimiter } from './ConcurrentRateLimiter';
import { PreferenceService, type ExploreNavItem } from './PreferenceService';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { SourceRuntime, SourceEngineAdapter, SourceFetchAdapter, SourceImportParser } from '@listenbook/source-runtime';

const TAG = 'BookSourceService';

interface PostInfo {
  url: string;
  body: string;
}

interface TemplateContext {
  key?: string;
  page?: number;
  speakText?: string;
  speakSpeed?: number;
  book?: Object;
  chapter?: Object;
  baseUrl?: string;
  result?: Object;
}

interface ExploreSection {
  source: BookSource;
  books: SearchResult[];
}

interface MaoyanConfig {
  host: string;
  aesKey: string;
  authorization: string;
  headers: Record<string, string>;
}

interface MaoyanCrypto {
  doFinal: (data: string, op: string) => string;
}

interface MaoyanCategory {
  title: string;
  id: string;
  channel: number;
}

interface MaoyanSort {
  label: string;
  value: number;
  suffix: string;
}

/** 订阅源单分类抓取结果（含分页信息） */
export interface ExploreFetchResult {
  books: SearchResult[];
  nextUrl: string;
  nextPage?: number;
}

class HomeBlockImpl implements HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;

  constructor(title: string, books: SearchResult[], moreUrl: string, layout: string,
              sourceName: string, sourceUrl: string) {
    this.title = title;
    this.books = books;
    this.moreUrl = moreUrl;
    this.layout = layout;
    this.sourceName = sourceName;
    this.sourceUrl = sourceUrl;
  }
}

/**
 * 简单异步互斥锁 — 保护全局 SourceContext / JavaBridge 的并发访问。
 * 多源并行搜索/首页聚合时，prepareSourceContext 会覆盖全局单例状态，
 * 此锁确保 "设置上下文 → JS 求值 → 规则解析" 的临界区不被其他源打断。
 */
class AsyncMutex {
  private locked: boolean = false;
  private waiters: Array<() => void> = [];

  async withLock<T>(fn: () => Promise<T>): Promise<T> {
    while (this.locked) {
      await new Promise<void>((resolve: () => void): void => {
        this.waiters.push(resolve);
      });
    }
    this.locked = true;
    try {
      return await fn();
    } finally {
      this.locked = false;
      const next = this.waiters.shift();
      if (next) next();
    }
  }
}

export class BookSourceService {
  /** 保护 SourceContext 并发访问的互斥锁 */
  private static contextLock: AsyncMutex = new AsyncMutex();
  // ──────────────────── 辅助方法 ────────────────────

  private static isMaoyanSource(source: BookSource): boolean {
    const name = source.bookSourceName || '';
    const comment = source.bookSourceComment || '';
    const sourceUrl = source.bookSourceUrl || '';
    return name.includes('猫眼') || comment.includes('maoyankanshu') || sourceUrl.includes('yichnmedia.com');
  }

  private static isAggregateAudioSource(source: BookSource): boolean {
    return source.bookSourceType === 0 && !!source.jsLib && source.jsLib.includes('getCloudSettings');
  }

  private static getMaoyanConfig(source: BookSource): MaoyanConfig {
    let aesKey = '4395daa50ad6baf7';
    let authorization = 'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkueGluZ2xpYW5nZ2xvYmFsLmNvbVwvYXV0aFwvdGhpcmQiLCJpYXQiOjE3MDY4NjA2NzcsImV4cCI6MTgwMDE3MjY3NywibmJmIjoxNzA2ODYwNjc3LCJqdGkiOiJxdXBGbWo5cnJRMHFoTFVIIiwic3ViIjozMjY4ODcsInBydiI6ImExY2IwMzcxODAyOTZjNmExOTM4ZWYzMGI0Mzc5NDY3MmRkMDE2YzUifQ.CQsDsiDJyyriPmJuT6A38KIvGgq6BEOMWl8H5plqArQ';
    const comment = source.bookSourceComment || '';
    const pairRegex = /\["([0-9a-fA-F]{16,32})",\s*"(bearer[^"]+)"\]/g;
    let match: RegExpExecArray | null = pairRegex.exec(comment);
    while (match !== null) {
      // 该源中最后一组是 xingliangglobal 新 AES 配置；保留默认值兜底。
      aesKey = match[1];
      authorization = match[2];
      match = pairRegex.exec(comment);
    }

    const headers = AnalyzeUrl.mergeHeaders(source.header || '', {
      'client-device': getJavaBridge().md5Encode(aesKey),
      'Authorization': authorization,
    });
    return {
      host: 'http://api.xingliangglobal.com',
      aesKey,
      authorization,
      headers,
    };
  }

  private static decodeDataUrlPayload(dataUrl: string): string {
    const base64Idx = dataUrl.indexOf('base64,');
    if (base64Idx < 0) return '';
    const encoded = dataUrl.substring(base64Idx + 7);
    const configIdx = encoded.lastIndexOf(',{');
    const payload = configIdx > 0 ? encoded.substring(0, configIdx) : encoded;
    return DataUrlHandler.base64Decode(payload).trim();
  }

  private static resolveMaoyanApiUrl(rawUrl: string, host: string, page: number = 1): string {
    let url = (rawUrl || '').replace(/[\r\n\t]/g, '').trim();
    if (DataUrlHandler.isDataUrl(url)) {
      url = BookSourceService.decodeDataUrlPayload(url);
    }
    url = url.replace(/\{\{page\}\}/g, String(page));
    if (!url) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return BookSourceService.normalizeMaoyanUrl(url, host);
    }
    if (url.startsWith('/')) {
      return host + url;
    }
    return host + '/' + url;
  }

  private static normalizeMaoyanUrl(url: string, host: string): string {
    if (!url) return '';
    if (url.startsWith('//')) return 'http:' + url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url.replace(/^https?:\/\/api\.[^/]+\.com/i, host);
    }
    if (url.startsWith('/')) return host + url;
    return url;
  }

  private static asRecord(value: Object | undefined | null): Record<string, Object> | null {
    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      return value as Record<string, Object>;
    }
    return null;
  }

  private static valueToText(value: Object | undefined | null): string {
    if (value === undefined || value === null) return '';
    if (Array.isArray(value)) {
      const parts: string[] = [];
      for (const item of value as Object[]) {
        const rec = BookSourceService.asRecord(item);
        if (rec) {
          const label = BookSourceService.getStringField(rec, ['className', 'categoryName', 'tagName', 'name', 'title']);
          if (label) parts.push(label);
        } else {
          const s = String(item).trim();
          if (s) parts.push(s);
        }
      }
      return parts.join(' ');
    }
    const rec = BookSourceService.asRecord(value);
    if (rec) {
      const label = BookSourceService.getStringField(rec, ['className', 'categoryName', 'tagName', 'name', 'title']);
      return label || JSON.stringify(value);
    }
    return String(value).trim();
  }

  private static getStringField(record: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const text = BookSourceService.valueToText(record[key]);
      if (text) return text;
    }
    return '';
  }

  private static getMaoyanList(parsed: Record<string, Object>): Object[] {
    const data = parsed['data'];
    if (Array.isArray(data)) return data as Object[];
    const dataRec = BookSourceService.asRecord(data);
    if (dataRec) {
      const keys = ['list', 'books', 'items', 'data'];
      for (const key of keys) {
        const value = dataRec[key];
        if (Array.isArray(value)) return value as Object[];
      }
    }
    const rootKeys = ['list', 'books', 'items'];
    for (const key of rootKeys) {
      const value = parsed[key];
      if (Array.isArray(value)) return value as Object[];
    }
    return [];
  }

  private static getMaoyanDataRecord(parsed: Record<string, Object>): Record<string, Object> {
    const dataRec = BookSourceService.asRecord(parsed['data']);
    return dataRec || parsed;
  }

  private static getMaoyanNovelId(record: Record<string, Object>): string {
    return BookSourceService.getStringField(record, ['novelId', 'bookId', 'id']);
  }

  private static getMaoyanLastChapter(record: Record<string, Object>): string {
    const lastObj = BookSourceService.asRecord(record['lastChapter']) ||
      BookSourceService.asRecord(record['latestChapter']);
    if (lastObj) {
      const title = BookSourceService.getStringField(lastObj, ['chapterName', 'name', 'title']);
      const time = BookSourceService.getStringField(lastObj, ['updatedAt', 'updateTime', 'time']);
      return `${title} ${time}`.trim();
    }
    return BookSourceService.getStringField(record, ['lastChapterName', 'latestChapterName', 'lastChapter']);
  }

  private static getMaoyanKind(record: Record<string, Object>): string {
    const parts: string[] = [];
    const score = BookSourceService.getStringField(record, ['averageScore', 'score']);
    if (score) parts.push(score.includes('分') ? score : `${score}分`);
    const category = BookSourceService.getStringField(record, ['categoryNames', 'categoryName', 'category']);
    if (category) parts.push(category);
    const tags = BookSourceService.getStringField(record, ['tagNames', 'tags']);
    if (tags) parts.push(tags);
    const status = BookSourceService.getStringField(record, ['statusText', 'status']);
    const isComplete = BookSourceService.getStringField(record, ['isComplete', 'complete']);
    if (status && status !== '0' && status !== '1') {
      parts.push(status);
    } else if (isComplete) {
      parts.push(isComplete === '1' || isComplete === 'true' ? '完结' : '连载');
    }
    return parts.join('\n');
  }

  private static mapMaoyanBook(source: BookSource, item: Object, host: string): SearchResult | null {
    const record = BookSourceService.asRecord(item);
    if (!record) return null;
    const name = BookSourceService.getStringField(record, ['novelName', 'bookName', 'name', 'title']);
    if (!name) return null;
    const author = BookSourceService.getStringField(record, ['authorName', 'author']);
    const coverRaw = BookSourceService.getStringField(record, ['cover', 'coverUrl', 'picUrl', 'image']);
    const novelId = BookSourceService.getMaoyanNovelId(record);
    const urlRaw = BookSourceService.getStringField(record, ['bookUrl', 'url']);
    const bookUrl = novelId ? `${host}/novel/${novelId}` : BookSourceService.normalizeMaoyanUrl(urlRaw, host);
    const variables: Record<string, string> = {};
    if (novelId) variables['novelId'] = novelId;
    variables['maoyanHost'] = host;
    return {
      name,
      author,
      coverUrl: BookSourceService.normalizeMaoyanUrl(coverRaw, host),
      bookUrl,
      intro: BookSourceService.getStringField(record, ['summary', 'intro', 'description', 'rankInfo']),
      kind: BookSourceService.getMaoyanKind(record),
      lastChapter: BookSourceService.getMaoyanLastChapter(record),
      wordCount: BookSourceService.getStringField(record, ['wordNum', 'wordCount', 'words']),
      sourceName: source.bookSourceName,
      sourceUrl: source.bookSourceUrl,
      variables,
    };
  }

  private static extractMaoyanNovelId(bookUrl: string, variables?: Record<string, string>): string {
    if (variables && variables['novelId']) return variables['novelId'];
    let url = (bookUrl || '').trim();
    if (DataUrlHandler.isDataUrl(url)) url = BookSourceService.decodeDataUrlPayload(url);
    const novelMatch = url.match(/\/novel\/([^/?#]+)/);
    if (novelMatch) return decodeURIComponent(novelMatch[1]);
    const queryMatch = url.match(/[?&](?:novelId|bookId|id)=([^&#]+)/);
    if (queryMatch) return decodeURIComponent(queryMatch[1]);
    if (/^[A-Za-z0-9_-]+$/.test(url)) return url;
    return '';
  }

  private static bytesToHex(bytes: number[]): string {
    return bytes.map((b: number) => (b & 0xFF).toString(16).padStart(2, '0')).join('');
  }

  private static base64ToBytes(s: string): number[] {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const map: Map<string, number> = new Map();
    for (let i = 0; i < alphabet.length; i++) map.set(alphabet.charAt(i), i);
    let clean = (s || '').replace(/-/g, '+').replace(/_/g, '/').replace(/[^A-Za-z0-9+/=]/g, '');
    while (clean.length % 4 !== 0) clean += '=';
    const bytes: number[] = [];
    for (let i = 0; i < clean.length; i += 4) {
      const c1 = map.get(clean.charAt(i)) ?? 0;
      const c2 = map.get(clean.charAt(i + 1)) ?? 0;
      const c3 = map.get(clean.charAt(i + 2)) ?? 0;
      const c4 = map.get(clean.charAt(i + 3)) ?? 0;
      bytes.push(((c1 << 2) | (c2 >> 4)) & 0xFF);
      if (clean.charAt(i + 2) !== '=') bytes.push(((c2 << 4) | (c3 >> 2)) & 0xFF);
      if (clean.charAt(i + 3) !== '=') bytes.push(((c3 << 6) | c4) & 0xFF);
    }
    return bytes;
  }

  private static decryptMaoyanPath(encrypted: string, aesKey: string): string {
    const raw = (encrypted || '').trim();
    if (!raw) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('/')) return raw;
    try {
      const cipherHex = /^[0-9a-fA-F]+$/.test(raw) && raw.length % 2 === 0
        ? raw
        : BookSourceService.bytesToHex(BookSourceService.base64ToBytes(raw));
      const javaBridge = getJavaBridge();
      const crypto = javaBridge.createSymmetricCrypto(
        'AES/CBC/PKCS5Padding',
        javaBridge.hexEncodeToString(aesKey),
        javaBridge.hexEncodeToString('0123456789abcdef'),
      ) as MaoyanCrypto;
      const plainHex = crypto.doFinal(cipherHex, 'decrypt');
      return javaBridge.hexDecodeToString(plainHex);
    } catch (e) {
      console.warn(`[${TAG}] decryptMaoyanPath failed: ${e}`);
      return '';
    }
  }

  private static async fetchMaoyanJsonWithConfig(config: MaoyanConfig, rawUrl: string, page: number = 1): Promise<Record<string, Object> | null> {
    const url = BookSourceService.resolveMaoyanApiUrl(rawUrl, config.host, page);
    if (!url) return null;
    const body = await HttpClient.get(url, config.headers);
    hilog.info(0x9527, 'MaoyanDbg', 'url=%{public}s bodyLen=%{public}d head=%{public}s',
      url, body.length, body.substring(0, 400));
    try {
      return JSON.parse(body) as Record<string, Object>;
    } catch (e) {
      console.warn(`[${TAG}] fetchMaoyanJson parse failed: ${e}, url=${url}`);
      return null;
    }
  }

  private static async searchMaoyanBooks(source: BookSource, keyword: string, page: number): Promise<SearchResult[]> {
    const config = BookSourceService.getMaoyanConfig(source);
    const parsed = await BookSourceService.fetchMaoyanJsonWithConfig(
      config,
      `/search?keyword=${encodeURIComponent(keyword)}&page=${page}`,
      page,
    );
    if (!parsed) return [];
    const list = BookSourceService.getMaoyanList(parsed);
    const results: SearchResult[] = [];
    for (const item of list) {
      const mapped = BookSourceService.mapMaoyanBook(source, item, config.host);
      if (mapped) results.push(mapped);
    }
    return results;
  }

  private static async getMaoyanBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    const config = BookSourceService.getMaoyanConfig(source);
    const novelId = BookSourceService.extractMaoyanNovelId(bookUrl, variables);
    if (!novelId) return null;
    const parsed = await BookSourceService.fetchMaoyanJsonWithConfig(config, `/novel/${novelId}`);
    if (!parsed) return null;
    const record = BookSourceService.getMaoyanDataRecord(parsed);
    const name = BookSourceService.getStringField(record, ['novelName', 'bookName', 'name', 'title']);
    const coverRaw = BookSourceService.getStringField(record, ['cover', 'coverUrl', 'picUrl', 'image']);
    const vars: Record<string, string> = {};
    vars['novelId'] = novelId;
    vars['maoyanHost'] = config.host;
    return {
      name,
      author: BookSourceService.getStringField(record, ['authorName', 'author']),
      coverUrl: BookSourceService.normalizeMaoyanUrl(coverRaw, config.host),
      intro: BookSourceService.getStringField(record, ['summary', 'intro', 'description']),
      kind: BookSourceService.getMaoyanKind(record),
      wordCount: BookSourceService.getStringField(record, ['wordNum', 'wordCount', 'words']),
      lastChapter: BookSourceService.getMaoyanLastChapter(record),
      tocUrl: `${config.host}/novel/${novelId}/chapters`,
      variables: vars,
    };
  }

  private static async getMaoyanToc(source: BookSource, tocUrl: string, variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    const config = BookSourceService.getMaoyanConfig(source);
    let url = BookSourceService.resolveMaoyanApiUrl(tocUrl, config.host);
    if (!url.includes('/chapters')) {
      const novelId = BookSourceService.extractMaoyanNovelId(url, variables);
      if (!novelId) return [];
      url = `${config.host}/novel/${novelId}/chapters`;
    }
    const parsed = await BookSourceService.fetchMaoyanJsonWithConfig(config, url);
    if (!parsed) return [];
    const list = BookSourceService.getMaoyanList(parsed);
    const items: TocItem[] = [];
    for (const item of list) {
      const record = BookSourceService.asRecord(item);
      if (!record) continue;
      let name = BookSourceService.getStringField(record, ['chapterName', 'name', 'title']);
      if (!name) continue;
      if (bookName) name = ChapterTitleFormatter.stripBookPrefix(name, bookName);
      const encryptedPath = BookSourceService.getStringField(record, ['path', 'chapterUrl', 'url']);
      const decryptedPath = BookSourceService.decryptMaoyanPath(encryptedPath, config.aesKey);
      const chapterUrl = BookSourceService.resolveMaoyanApiUrl(decryptedPath || encryptedPath, config.host);
      if (!chapterUrl) continue;
      const wordNum = BookSourceService.getStringField(record, ['wordNum', 'wordCount', 'words']);
      const updatedAt = BookSourceService.getStringField(record, ['updatedAt', 'updateTime', 'time']);
      const tocItem: TocItem = { name, url: chapterUrl };
      const infoParts: string[] = [];
      if (wordNum) infoParts.push(`章节字数：${wordNum}`);
      if (updatedAt) infoParts.push(`更新时间：${updatedAt}`);
      if (infoParts.length > 0) tocItem.updateTime = infoParts.join('　');
      items.push(tocItem);
    }
    return items;
  }

  private static async getMaoyanTextContent(source: BookSource, chapterUrl: string): Promise<string> {
    const config = BookSourceService.getMaoyanConfig(source);
    let rawUrl = (chapterUrl || '').replace(/[\r\n\t]/g, '').trim();
    if (DataUrlHandler.isDataUrl(rawUrl)) {
      rawUrl = BookSourceService.decodeDataUrlPayload(rawUrl);
    }
    if (rawUrl && !rawUrl.startsWith('http://') && !rawUrl.startsWith('https://') && !rawUrl.startsWith('/')) {
      const decrypted = BookSourceService.decryptMaoyanPath(rawUrl, config.aesKey);
      if (decrypted) rawUrl = decrypted;
    }
    const url = BookSourceService.resolveMaoyanApiUrl(rawUrl, config.host);
    const parsed = await BookSourceService.fetchMaoyanJsonWithConfig(config, url);
    if (!parsed) return '';
    const directContent = BookSourceService.getStringField(parsed, ['content']);
    if (directContent) return directContent.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const dataRec = BookSourceService.asRecord(parsed['data']);
    if (dataRec) {
      const content = BookSourceService.getStringField(dataRec, ['content', 'body', 'text']);
      return content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    }
    const data = BookSourceService.valueToText(parsed['data']);
    return data.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  private static getMaoyanExploreNavigation(): ExploreNavItem[] {
    const nav: ExploreNavItem[] = [];
    const push = (title: string, url: string): void => {
      nav.push({ title, url });
    };

    const rankTitles = ['必读榜', '完本榜', '更新榜', '搜索榜', '潜力榜', '评论榜'];
    for (let channel = 1; channel <= 2; channel++) {
      const channelTitle = channel === 1 ? '男生' : '女生';
      for (let i = 0; i < rankTitles.length; i++) {
        push(`${channelTitle} · ${rankTitles[i]}`, `/module/rank?type=${i + 1}&channel=${channel}&page={{page}}`);
      }
      push(`${channelTitle} · 人气完本`, `/module/mep2bM?channel=${channel}&page={{page}}`);
      push(`${channelTitle} · 新书速递`, `/module/YerEdO?channel=${channel}&page={{page}}`);
    }

    const categories: MaoyanCategory[] = [
      { title: '玄幻', id: 'lejRej', channel: 1 },
      { title: '武侠', id: 'nel5aK', channel: 1 },
      { title: '都市', id: 'mbk5ez', channel: 1 },
      { title: '仙侠', id: 'vbmOeY', channel: 1 },
      { title: '军事', id: 'penRe7', channel: 1 },
      { title: '历史', id: 'xbojag', channel: 1 },
      { title: '游戏', id: 'mep2bM', channel: 1 },
      { title: '科幻', id: 'zbq2dp', channel: 1 },
      { title: '轻小说', id: 'YerEdO', channel: 1 },
      { title: '现代言情', id: '9avmeG', channel: 2 },
      { title: '古代言情', id: 'DdwRb1', channel: 2 },
      { title: '幻想言情', id: '7ax9by', channel: 2 },
      { title: '青春校园', id: 'Pdy7aQ', channel: 2 },
      { title: '唯美纯爱', id: 'kazYeJ', channel: 2 },
      { title: '同人衍生', id: '9aAOdv', channel: 2 },
    ];
    const sorts: MaoyanSort[] = [
      { label: '热度', value: 1, suffix: '' },
      { label: '更新', value: 2, suffix: '' },
      { label: '评分', value: 3, suffix: '' },
      { label: '新书', value: 4, suffix: '' },
      { label: '连载', value: 1, suffix: '&isComplete=0' },
      { label: '完结', value: 1, suffix: '&isComplete=1' },
    ];
    for (const category of categories) {
      const channelTitle = category.channel === 1 ? '男生' : '女生';
      for (const sort of sorts) {
        push(`${channelTitle} · ${category.title} · ${sort.label}`,
          `/novel?sort=${sort.value}&categoryId=${category.id}${sort.suffix}&page={{page}}`);
      }
    }
    return nav;
  }

  private static async getMaoyanExploreBooksByUrl(
    source: BookSource, categoryUrl: string, page: number
  ): Promise<ExploreFetchResult> {
    const empty: ExploreFetchResult = { books: [], nextUrl: '' };
    const config = BookSourceService.getMaoyanConfig(source);
    const parsed = await BookSourceService.fetchMaoyanJsonWithConfig(config, categoryUrl, page);
    if (!parsed) return empty;
    const list = BookSourceService.getMaoyanList(parsed);
    const books: SearchResult[] = [];
    for (const item of list) {
      const mapped = BookSourceService.mapMaoyanBook(source, item, config.host);
      if (mapped) books.push(mapped);
    }
    const nextUrl = books.length > 0 && categoryUrl.includes('{{page}}') ? categoryUrl : '';
    return { books, nextUrl, nextPage: page + 1 };
  }

  /**
   * 构建 JS 执行上下文，注入 jsLib、源变量、cache 等
   */
  private static buildJsContext(source: BookSource, extra?: Record<string, Object>): Record<string, Object> {
    const ctx: Record<string, Object> = {};
    // 注入 jsLib
    if (source.jsLib) {
      ctx['_jsLib'] = source.jsLib;
    }
    // 注入源变量
    try {
      const sourceVars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
      const javaVars: Record<string, string> = {};
      for (const k of Object.keys(sourceVars)) {
        javaVars[k] = String(sourceVars[k]);
      }
      ctx['_javaVars'] = javaVars;
      // 注入完整的源变量 JSON（供 source.getVariable() 返回）
      ctx['_sourceVar'] = JSON.stringify(sourceVars);
    } catch (e) {
      console.warn(`[${TAG}] buildJsContext: sourceVars error: ${e}`);
    }
    // 合并额外上下文
    if (extra) {
      for (const k of Object.keys(extra)) {
        ctx[k] = extra[k];
      }
    }
    return ctx;
  }

  private static prepareSourceContext(source: BookSource, variables?: Record<string, string>): void {
    getSourceContext().setSource({
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: source.bookSourceType,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginCheckJs: source.loginCheckJs,
      header: source.header,
      jsLib: source.jsLib,
    });
    getJavaBridge().setVariables(BookSourceService.cloneVariables(variables));
  }

  private static cloneVariables(variables?: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {};
    if (!variables) return out;
    for (const k of Object.keys(variables)) {
      out[k] = variables[k];
    }
    return out;
  }

  private static mergeVariables(base?: Record<string, string>, extra?: Record<string, string>): Record<string, string> {
    const out = BookSourceService.cloneVariables(base);
    if (extra) {
      for (const k of Object.keys(extra)) {
        out[k] = extra[k];
      }
    }
    return out;
  }

  private static getSourceVarJson(source: BookSource): string {
    try {
      return JSON.stringify(SourceVariableStore.getSourceVariables(source.bookSourceUrl));
    } catch {
      return '';
    }
  }

  private static configureAnalyzeContext(
    ctx: AnalyzeContext,
    source: BookSource,
    variables?: Record<string, string>,
    book?: BookContext,
    chapter?: Record<string, Object>,
  ): void {
    ctx.jsLib = source.jsLib || '';
    ctx.sourceVarJson = BookSourceService.getSourceVarJson(source);
    if (variables) ctx.variables = BookSourceService.cloneVariables(variables);
    if (book) ctx.book = book;
    if (chapter) ctx.chapter = chapter;
  }

  private static async analyzeRequestUrl(
    source: BookSource,
    rawUrl: string,
    variables?: Record<string, string>,
    page?: number,
    key?: string,
    baseUrl?: string,
  ): Promise<AnalyzedUrl> {
    return BookSourceService.contextLock.withLock(async (): Promise<AnalyzedUrl> => {
      BookSourceService.prepareSourceContext(source, variables);
      const analyzeUrl = new AnalyzeUrl(rawUrl, {
        key,
        page,
        baseUrl: baseUrl || source.bookSourceUrl,
        _jsLib: source.jsLib || '',
        _sourceVar: BookSourceService.getSourceVarJson(source),
      }, source.header, variables);
      const analyzed = await analyzeUrl.getUrl();
      BookSourceService.mergeLoginHeaders(source, analyzed.headers);
      BookSourceService.patchKnownSearchRequest(source, analyzed);
      if (!analyzed.charset) {
        const inferred = BookSourceService.inferCharset(source);
        if (inferred) analyzed.charset = inferred;
      }
      return analyzed;
    });
  }

  private static patchKnownSearchRequest(source: BookSource, analyzed: AnalyzedUrl): void {
    const sourceHost = (source.bookSourceUrl || '').toLowerCase();
    const requestUrl = (analyzed.url || '').toLowerCase();
    if (!BookSourceService.isJiuJiuXswHost(sourceHost) && !BookSourceService.isJiuJiuXswHost(requestUrl)) return;
    if (!requestUrl.includes('/e/search/index.php')) return;
    if ((analyzed.method || 'GET').toUpperCase() !== 'POST') return;

    let body = analyzed.body || '';
    if (!body) return;
    body = body.replace('show=writer,title', 'show=title,writer');
    body = BookSourceService.appendFormParamIfMissing(body, 'tbname', 'download');
    body = BookSourceService.appendFormParamIfMissing(body, 'tempid', '2');
    body = BookSourceService.appendFormParamIfMissing(body, 'orderby', 'newstime');
    body = BookSourceService.appendFormParamIfMissing(body, 'myorder', '0');
    analyzed.body = body;

    if (!BookSourceService.findHeaderKey(analyzed.headers, 'Content-Type')) {
      analyzed.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
  }

  private static isJiuJiuXswHost(url: string): boolean {
    return url.includes('ijjxsw.com') || url.includes('ijjjjxsw.com') || url.includes('jjjjxsw.com');
  }

  private static appendFormParamIfMissing(body: string, key: string, value: string): string {
    const encodedKey = encodeURIComponent(key);
    if (body === encodedKey + '=' || body.startsWith(encodedKey + '=') || body.includes('&' + encodedKey + '=')) return body;
    const prefix = body.length > 0 ? '&' : '';
    return body + prefix + encodedKey + '=' + encodeURIComponent(value);
  }

  private static getLoginCookieHeader(source: BookSource): string {
    try {
      const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
      const raw = vars['_loginHeader'];
      if (raw !== undefined && raw !== null) {
        const headers = BookSourceService.parseLoginHeaders(raw);
        const cookieKey = BookSourceService.findHeaderKey(headers, 'Cookie');
        if (cookieKey) return headers[cookieKey] || '';
      }
    } catch { /* ignore */ }
    try {
      return getCookieManager().getCookie(source.bookSourceUrl) || '';
    } catch {
      return '';
    }
  }

  private static parseLoginHeaders(raw: Object): Record<string, string> {
    let loginHeaders: Record<string, string> = {};
    try {
      if (typeof raw === 'string') {
        const text = (raw as string).trim();
        if (!text) return loginHeaders;
        loginHeaders = JSON.parse(text) as Record<string, string>;
      } else if (typeof raw === 'object') {
        loginHeaders = raw as Record<string, string>;
      }
    } catch {
      return loginHeaders;
    }
    return loginHeaders;
  }

  private static mergeLoginHeaders(source: BookSource, headers: Record<string, string>): void {
    let raw: Object | undefined = undefined;
    try {
      const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
      raw = vars['_loginHeader'];
    } catch {
      raw = undefined;
    }
    if (raw === undefined || raw === null) return;
    const loginHeaders = BookSourceService.parseLoginHeaders(raw as Object);
    const keys = Object.keys(loginHeaders);
    for (const key of keys) {
      const value = loginHeaders[key];
      if (value === undefined || value === null || String(value).length === 0) continue;
      BookSourceService.mergeHeaderValue(headers, key, String(value));
    }
  }

  private static mergeHeaderValue(headers: Record<string, string>, key: string, value: string): void {
    const existingKey = BookSourceService.findHeaderKey(headers, key);
    if (!existingKey) {
      headers[key] = value;
      return;
    }
    if (key.toLowerCase() === 'cookie') {
      const existing = headers[existingKey];
      headers[existingKey] = existing ? existing + '; ' + value : value;
      return;
    }
    if (!headers[existingKey]) {
      headers[existingKey] = value;
    }
  }

  private static findHeaderKey(headers: Record<string, string>, key: string): string {
    const lower = key.toLowerCase();
    const keys = Object.keys(headers);
    for (const current of keys) {
      if (current.toLowerCase() === lower) return current;
    }
    return '';
  }

  /**
   * 处理 data: URL — 解码 base64 数据并存入 JavaBridge 变量
   * 返回 true 表示是 data: URL 并已处理，false 表示不是
   */
  private static handleDataUrl(url: string): boolean {
    if (!DataUrlHandler.isDataUrl(url)) return false;
    const parsed = DataUrlHandler.parse(url);
    if (!parsed) return false;
    // 将解码的数据存入 JavaBridge 变量
    const javaBridge = getJavaBridge();
    const dataKeys = Object.keys(parsed.data);
    for (const k of dataKeys) {
      javaBridge.put(k, String(parsed.data[k]));
    }
    return true;
  }

  /**
   * 解析时长字符串为秒数
   * 支持格式：
   * - 纯数字秒数："1234"
   * - 时分秒："01:23:45" -> 1*3600 + 23*60 + 45 = 5025
   * - 分秒："23:45" -> 23*60 + 45 = 1425
   * - 带中文："1小时23分45秒"
   */
  private static parseDuration(durationStr: string): number {
    if (!durationStr) return 0;
    const trimmed = durationStr.trim();

    // 1. 尝试纯数字
    const numMatch = /^(\d+)$/.exec(trimmed);
    if (numMatch) {
      return parseInt(numMatch[1], 10);
    }

    // 2. 尝试 HH:MM:SS 或 MM:SS
    const colonMatch = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(trimmed);
    if (colonMatch) {
      const part1 = parseInt(colonMatch[1], 10);
      const part2 = parseInt(colonMatch[2], 10);
      const part3 = colonMatch[3] ? parseInt(colonMatch[3], 10) : 0;
      // 如果有第三部分，格式是 HH:MM:SS；否则是 MM:SS
      if (colonMatch[3]) {
        return part1 * 3600 + part2 * 60 + part3;
      } else {
        return part1 * 60 + part2;
      }
    }

    // 3. 尝试中文格式："1小时23分45秒" 或 "23分45秒"
    const zhMatch = /(?:(\d+)小时)?(?:(\d+)分)?(?:(\d+)秒)?/.exec(trimmed);
    if (zhMatch) {
      const hours = zhMatch[1] ? parseInt(zhMatch[1], 10) : 0;
      const minutes = zhMatch[2] ? parseInt(zhMatch[2], 10) : 0;
      const seconds = zhMatch[3] ? parseInt(zhMatch[3], 10) : 0;
      if (hours > 0 || minutes > 0 || seconds > 0) {
        return hours * 3600 + minutes * 60 + seconds;
      }
    }

    return 0;
  }

  // ──────────────────── 书源管理 ────────────────────

  static async fetchSourcesFromUrl(subscriptionUrl: string): Promise<BookSource[]> {
    return SourceRuntime.fetchSourcesFromUrl(subscriptionUrl);
  }

  static parseSourcesFromJson(jsonText: string): BookSource[] {
    return SourceRuntime.parseSourcesFromJson(jsonText);
  }

  /**
   * 展开聚合源：为每个听书子源创建独立的书源条目
   * 光遇聚合等聚合源内部集合了多个平台（番茄、七猫、喜马拉雅等），
   * 每个子源共用同一台服务器和 jsLib，但各自只搜指定平台。
   *
   * @param sources 原始导入的书源列表
   * @returns 展开后的书源列表（包含原始源 + 子源）
   */
  static async expandAggregateSources(sources: BookSource[]): Promise<BookSource[]> {
    return SourceRuntime.expandAggregateSources(sources);
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    return SourceImportParser.buildSubscription(url, sources);
  }

  // ──────────────────── 搜索 ────────────────────

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.search(source, keyword, page);
    }
    if (BookSourceService.isMaoyanSource(source)) {
      return BookSourceService.searchMaoyanBooks(source, keyword, page);
    }

    // 真正的聚合听书源搜索时临时设置搜索模式为"听书"
    // 这样服务端只搜听书后端（喜马拉雅、懒人听书等），不搜小说/漫画
    // 搜索完成后恢复原设置，不影响用户配置
    const isAggregate = BookSourceService.isAggregateAudioSource(source);
    let savedSearchMode = '';
    if (isAggregate) {
      try {
        const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
        const moreSettings: Record<string, Object> = (vars['更多设置'] as Record<string, Object>) || {} as Record<string, Object>;
        savedSearchMode = (moreSettings['搜索模式'] as string) || '';
        moreSettings['搜索模式'] = '听书';
        SourceVariableStore.setSourceVariable(source.bookSourceUrl, '更多设置', moreSettings);
      } catch { /* ignore */ }
    }

    try {
      if (!source.searchUrl) return [];

      const searchUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, source.searchUrl);
      const analyzed = await BookSourceService.analyzeRequestUrl(source, searchUrl, undefined, page, keyword);
      let analyzedUrl = analyzed.url;
      const analyzedMethod = analyzed.method;
      const analyzedBody = analyzed.body;
      const analyzedCharset = analyzed.charset;
      const analyzedHeaders: Record<string, string> = {};
      const hdrKeys = Object.keys(analyzed.headers);
      for (const hk of hdrKeys) analyzedHeaders[hk] = analyzed.headers[hk];
      // 聚合子源：自动带上 qttoken cookie
      try {
        const cookieManager = getCookieManager();
        const hostMatch = analyzedUrl.match(/^(https?:\/\/[^/]+)/);
        if (hostMatch) {
          const cookie = cookieManager.getCookie(hostMatch[1]);
          if (cookie && cookie.includes('qttoken') && !analyzedHeaders['Cookie']) {
            analyzedHeaders['Cookie'] = cookie;
          }
        }
      } catch { /* ignore */ }

      hilog.info(0x9527, 'FushuDbg', '[%{public}s] REQ method=%{public}s url=%{public}s body=%{public}s',
        source.bookSourceName, analyzedMethod, analyzedUrl, analyzedBody);

      // 处理 data: URL — 搜索 URL 返回 data: 编码的参数
      // data: URL 的 base64 内容需要作为 result 传给 bookList 规则
      let body: string;
      if (DataUrlHandler.isDataUrl(analyzedUrl)) {
        BookSourceService.handleDataUrl(analyzedUrl);
        // 提取 base64 部分作为 result（bookList JS 规则需要）
        const base64Idx = analyzedUrl.indexOf('base64,');
        if (base64Idx >= 0) {
          const afterBase64 = analyzedUrl.substring(base64Idx + 7);
          // 去掉末尾的 ,{config} 部分，只保留 base64 数据
          const lastComma = afterBase64.lastIndexOf(',{');
          body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
        } else {
          body = '';
        }
      } else {
        const tmpAnalyzed: AnalyzedUrl = { url: analyzedUrl, method: analyzedMethod, body: analyzedBody, headers: analyzedHeaders, charset: analyzedCharset, retry: 0 };
        body = await BookSourceService.fetch(tmpAnalyzed);
      }

      // 执行 loginCheckJs（搜索前验证）
      // 仅当响应看起来不是正常数据时才执行（如 HTML 跳转页、空数据等）
      // 正常 JSON/XML 响应直接跳过，避免引擎不支持的 JS API 导致卡死
      if (source.loginCheckJs && BookSourceService.needsLoginCheck(body)) {
        body = await BookSourceService.executeLoginCheck(source, body, keyword);
        // loginCheck 返回重试标记 → POST 已建立搜索会话，重新 GET 原始 URL
        if (body === '__RETRY_SEARCH__') {
          const tmpAnalyzed: AnalyzedUrl = { url: analyzedUrl, method: analyzedMethod, body: analyzedBody, headers: analyzedHeaders, charset: analyzedCharset, retry: 0 };
          body = await BookSourceService.fetch(tmpAnalyzed);
        }
      }

      hilog.info(0x9527, 'FushuDbg', '[%{public}s] bodyLen=%{public}d head=%{public}s',
        source.bookSourceName, body.length, body.substring(0, 350));

      // 检查 checkKeyWord（反爬检测，软警告）
      // 原意：响应被反爬拦截（如跳转到验证页）时会缺少这个关键词
      // 不强制要求响应必须包含它，缺失只记录警告，继续解析
      if (source.ruleSearch?.checkKeyWord) {
        if (!body.includes(source.ruleSearch.checkKeyWord)) {
          console.warn(`[${TAG}] [AntiCrawl?] Response missing checkKeyWord "${source.ruleSearch.checkKeyWord}", may be blocked. Continue parsing anyway.`);
        }
      }

      const rule = source.ruleSearch;
      // 子源：从搜索 URL 提取服务器地址（用于构造详情/目录 URL）
      const serverHostMatch = analyzedUrl.match(/^(https?:\/\/[^/]+)/);
      const serverHost = serverHostMatch ? serverHostMatch[1] : '';
      const ctx = new AnalyzeContext(analyzedUrl);
      BookSourceService.configureAnalyzeContext(ctx, source);
      const analyzer = new AnalyzeRule(body, ctx);
      const items: Object[] = await analyzer.getElements(rule.bookList);
      hilog.info(0x9527, 'FushuDbg', '[%{public}s] bookList=%{public}s matched=%{public}d',
        source.bookSourceName, rule.bookList, items.length);
      if (items.length === 0) {
        const webResults = await BookSourceService.tryJiuJiuWebSearchFallback(source, keyword, page);
        if (webResults.length > 0) return webResults;
        return [];
      }

      // 子源标识：bookSourceGroup 以 '聚合听书,' 开头
      const isSubSource = (source.bookSourceGroup || '').startsWith('聚合听书,');

      const results: SearchResult[] = [];
      for (let idx = 0; idx < items.length; idx++) {
        const item: Object = items[idx];
        const itemCtx = new AnalyzeContext(analyzedUrl, ctx.variables);
        BookSourceService.configureAnalyzeContext(itemCtx, source, ctx.variables);
        const a = new AnalyzeRule(item, itemCtx);
        const name = await a.getString(rule.name) || '';
        if (!name) continue;
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const wordCount = rule.wordCount ? await a.getString(rule.wordCount) || '' : '';
        // updateTime（Legado 对齐）
        if (rule.updateTime) {
          const ut = await a.getString(rule.updateTime) || '';
          if (ut) itemCtx.variables['updateTime'] = ut;
        }

        let finalBookUrl: string;
        if (isSubSource && !source.jsLib && serverHost) {
          // 子源：根据 item 字段构造完整的详情 URL
          const itemRec = item as Record<string, Object>;
          const bookId = String(itemRec['book_id'] || bookUrlRaw || '');
          const srcName = String(itemRec['source'] || '');
          const tab = String(itemRec['tab'] || '听书');
          finalBookUrl = `${serverHost}/detail?book_id=${encodeURIComponent(bookId)}&source=${encodeURIComponent(srcName)}&tab=${encodeURIComponent(tab)}`;
        } else {
          finalBookUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, bookUrlRaw);
        }

        const result: SearchResult = {
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, coverUrlRaw),
          bookUrl: finalBookUrl,
          intro, kind, lastChapter, wordCount,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
          variables: itemCtx.variables,
        };
        results.push(result);
      }
      return results;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] searchBooks error: ${msg}`);
      return [];
    } finally {
      // 恢复聚合源的搜索模式设置
      if (isAggregate && savedSearchMode) {
        try {
          const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
          const moreSettings: Record<string, Object> = (vars['更多设置'] as Record<string, Object>) || {} as Record<string, Object>;
          moreSettings['搜索模式'] = savedSearchMode;
          SourceVariableStore.setSourceVariable(source.bookSourceUrl, '更多设置', moreSettings);
        } catch { /* ignore */ }
      }
    }
  }

  private static async tryJiuJiuWebSearchFallback(source: BookSource, keyword: string, page: number): Promise<SearchResult[]> {
    if (page !== 1) return [];
    const sourceHost = (source.bookSourceUrl || '').toLowerCase();
    if (!BookSourceService.isJiuJiuXswHost(sourceHost)) return [];
    try {
      const extractor = getWebViewAudioExtractor();
      const startUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, '/');
      const cookie = BookSourceService.getLoginCookieHeader(source);
      if (cookie) {
        extractor.syncCookies(BookSourceService.jiuJiuCookieSyncUrls(source, startUrl), cookie);
      }
      const html = await extractor.extractHtml(startUrl, BookSourceService.buildJiuJiuWebSearchJs(keyword), 2200);
      if (!html || html.length === 0) return [];
      return BookSourceService.parseSearchResultsFromBody(source, html, startUrl);
    } catch (e) {
      console.warn(`[${TAG}] JiuJiu Web search fallback failed: ${e}`);
      return [];
    }
  }

  private static buildJiuJiuWebSearchJs(keyword: string): string {
    const kw = JSON.stringify(keyword);
    return `(function(){
      try {
        if (location.pathname.indexOf('/e/search/index.php') >= 0) {
          return document.documentElement.outerHTML;
        }
        var form = document.querySelector('form.search') || document.querySelector('form[action*="/e/search/index.php"]');
        if (!form) return document.documentElement.outerHTML;
        var input = form.querySelector('input[name="keyboard"]');
        if (input) input.value = ${kw};
        form.submit();
        return '__WAIT__';
      } catch(e) {
        return document.documentElement.outerHTML;
      }
    })()`;
  }

  private static jiuJiuCookieSyncUrls(source: BookSource, startUrl: string): string[] {
    const urls: string[] = [];
    const add = (url: string): void => {
      const text = (url || '').trim();
      if (text && !urls.includes(text)) urls.push(text);
    };
    add(source.bookSourceUrl);
    add(startUrl);
    add('https://www.ijjxsw.com');
    add('https://ijjxsw.com');
    add('https://www.ijjjjxsw.com');
    add('https://ijjjjxsw.com');
    add('https://www.jjjjxsw.com');
    add('https://jjjjxsw.com');
    return urls;
  }

  private static async parseSearchResultsFromBody(source: BookSource, body: string, baseUrl: string): Promise<SearchResult[]> {
    const rule = source.ruleSearch;
    const ctx = new AnalyzeContext(baseUrl);
    BookSourceService.configureAnalyzeContext(ctx, source);
    const analyzer = new AnalyzeRule(body, ctx);
    const items: Object[] = await analyzer.getElements(rule.bookList);
    if (items.length === 0) return BookSourceService.parseJiuJiuSearchLinks(source, body, baseUrl);
    const results: SearchResult[] = [];
    for (let idx = 0; idx < items.length; idx++) {
      const item: Object = items[idx];
      const itemCtx = new AnalyzeContext(baseUrl, ctx.variables);
      BookSourceService.configureAnalyzeContext(itemCtx, source, ctx.variables);
      const a = new AnalyzeRule(item, itemCtx);
      const name = await a.getString(rule.name) || '';
      if (!name) continue;
      const author = await a.getString(rule.author) || '';
      const coverUrlRaw = await a.getString(rule.coverUrl) || '';
      const bookUrlRaw = await a.getString(rule.bookUrl) || '';
      const intro = await a.getString(rule.intro) || '';
      const kind = await a.getString(rule.kind) || '';
      const lastChapter = await a.getString(rule.lastChapter) || '';
      const wordCount = rule.wordCount ? await a.getString(rule.wordCount) || '' : '';
      const result: SearchResult = {
        name,
        author,
        coverUrl: AnalyzeUrl.resolveUrl(baseUrl, coverUrlRaw),
        bookUrl: AnalyzeUrl.resolveUrl(baseUrl, bookUrlRaw),
        intro,
        kind,
        lastChapter,
        wordCount,
        sourceName: source.bookSourceName,
        sourceUrl: source.bookSourceUrl,
        variables: itemCtx.variables,
      };
      results.push(result);
    }
    return results;
  }

  private static parseJiuJiuSearchLinks(source: BookSource, body: string, baseUrl: string): SearchResult[] {
    const results: SearchResult[] = [];
    const seen = new Set<string>();
    const regex = /<a\b[^>]*href=["']([^"']*\/txt\/\d+\.html[^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null = regex.exec(body);
    while (match !== null) {
      const rawUrl = match[1] || '';
      const name = BookSourceService.cleanHtmlText(match[2] || '');
      const bookUrl = AnalyzeUrl.resolveUrl(baseUrl, rawUrl);
      if (name && bookUrl && !seen.has(bookUrl)) {
        seen.add(bookUrl);
        const result: SearchResult = {
          name,
          author: '',
          coverUrl: '',
          bookUrl,
          intro: '',
          kind: '',
          lastChapter: '',
          wordCount: '',
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
        };
        results.push(result);
      }
      match = regex.exec(body);
    }
    return results;
  }

  private static cleanHtmlText(html: string): string {
    return (html || '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&#39;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // ──────────────────── 书籍详情 ────────────────────

  static async getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getBookInfo(source, bookUrl);
    }
    if (BookSourceService.isMaoyanSource(source)) {
      return BookSourceService.getMaoyanBookInfo(source, bookUrl, variables);
    }
    try {
      const rule = source.ruleBookInfo;
      if (!rule) return null;
      BookSourceService.prepareSourceContext(source, variables);

      // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
      let processedUrl = bookUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
        return `{{java.get('${key}')}}`;
      });

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(processedUrl)) {
        BookSourceService.handleDataUrl(processedUrl);
        // data: URL 本身不需要 HTTP 请求，直接用空 body 继续解析规则
        // 规则中的 JS 会通过 java.get() 获取已解码的数据
      }

      // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
      let body: string;
      if (DataUrlHandler.isDataUrl(processedUrl)) {
        BookSourceService.handleDataUrl(processedUrl);
        const base64Idx = processedUrl.indexOf('base64,');
        if (base64Idx >= 0) {
          const afterBase64 = processedUrl.substring(base64Idx + 7);
          const lastComma = afterBase64.lastIndexOf(',{');
          body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
        } else {
          body = '';
        }
      } else {
        const analyzed = await BookSourceService.analyzeRequestUrl(source, processedUrl, variables, undefined, undefined, bookUrl);
        processedUrl = analyzed.url;
        body = await BookSourceService.fetch(analyzed);
      }
      const ctx = new AnalyzeContext(processedUrl, variables);
      BookSourceService.configureAnalyzeContext(
        ctx,
        source,
        variables,
        { origin: source.bookSourceUrl, bookUrl: bookUrl, name: '' } as BookContext,
      );
      const analyzer = new AnalyzeRule(body, ctx);

      // init 规则：预处理内容
      if (rule.init) {
        const initContent = await analyzer.getString(rule.init);
        if (initContent) {
          analyzer.setContent(initContent);
        }
      }

      const name = await analyzer.getString(rule.name) || '';
      const author = await analyzer.getString(rule.author) || '';
      const coverUrlRaw = await analyzer.getString(rule.coverUrl) || '';
      const intro = await analyzer.getString(rule.intro) || '';
      const kind = rule.kind ? await analyzer.getString(rule.kind) || '' : '';
      const wordCount = rule.wordCount ? await analyzer.getString(rule.wordCount) || '' : '';
      const lastChapter = rule.lastChapter ? await analyzer.getString(rule.lastChapter) || '' : '';
      // updateTime（Legado 对齐）
      if (rule.updateTime) {
        const ut = await analyzer.getString(rule.updateTime) || '';
        if (ut) ctx.variables['updateTime'] = ut;
      }
      const tocUrlRaw = await analyzer.getString(rule.tocUrl) || '';
      // tocUrl 可能包含多行（多个匹配结果用 \n 连接），只取第一个有效 URL
      const tocUrlFirst = tocUrlRaw.split('\n').map((s: string) => s.trim())
        .find((s: string) => s.length > 0 && !s.toLowerCase().startsWith('javascript:')) || '';
      const tocUrlResolved = tocUrlFirst ? AnalyzeUrl.resolveUrl(processedUrl, tocUrlFirst) : '';

      return {
        name, author,
        coverUrl: AnalyzeUrl.resolveUrl(processedUrl, coverUrlRaw),
        intro, kind, wordCount, lastChapter,
        tocUrl: tocUrlResolved || bookUrl,
        variables: BookSourceService.mergeVariables(variables, ctx.variables),
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getBookInfo error: ${msg}, bookUrl=${bookUrl}`);
      return null;
    }
  }

  // ──────────────────── 目录（支持分页） ────────────────────

  static async getBookToc(source: BookSource, tocUrl: string, variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      const builtinItems = await BuiltInDispatcher.getBookToc(source, tocUrl);
      // 内置源也去重(部分站点详情页+播放页会返回重复章节)
      const seenBuiltin = new Set<string>();
      const uniqueBuiltin: TocItem[] = [];
      for (const item of builtinItems) {
        if (seenBuiltin.has(item.url)) continue;
        seenBuiltin.add(item.url);
        // 内置源也统一剥书名前缀（书源把书名拼到章节名时）
        if (bookName) {
          item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
        }
        uniqueBuiltin.push(item);
      }
      return uniqueBuiltin;
    }
    if (BookSourceService.isMaoyanSource(source)) {
      return BookSourceService.getMaoyanToc(source, tocUrl, variables, bookName);
    }
    const rule = source.ruleToc;
    const allItems: TocItem[] = [];
    let currentUrl: string = tocUrl.replace(/[\r\n\t]/g, '').trim();
    BookSourceService.prepareSourceContext(source, variables);

    // preUpdateJs：TOC 抓取前执行 JS（Legado 对齐）
    // 可用于刷新 tocUrl、重新获取 bookInfo 等
    if (rule.preUpdateJs) {
      try {
        const bookCtx: BookContext = { origin: source.bookSourceUrl, bookUrl: tocUrl, name: '' };
        const bookExtra: Record<string, Object> = {};
        bookExtra['book'] = bookCtx as Object;
        const jsCtx = BookSourceService.buildJsContext(source, bookExtra);
        const executor = getJSExecutor();
        const evalCtx: Record<string, Object> = {};
        evalCtx['result'] = currentUrl as Object;
        evalCtx['baseUrl'] = source.bookSourceUrl as Object;
        evalCtx['book'] = bookCtx as Object;
        const jsCtxKeys = Object.keys(jsCtx);
        for (const k of jsCtxKeys) evalCtx[k] = jsCtx[k];
        const preResult = await executor.eval(rule.preUpdateJs, evalCtx);
        if (preResult && typeof preResult === 'string' && preResult.startsWith('http')) {
          currentUrl = preResult;
        }
      } catch (e) {
        console.warn(`[${TAG}] preUpdateJs error: ${e}`);
      }
    }

    // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
    // 某些书源（如猫眼看书）的 bookUrl 包含 {aQnGo9} 占位符，需要手动转换
    currentUrl = currentUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
      return `{{java.get('${key}')}}`;
    });

    // 处理 data: URL（代理书源的中间路由机制）
    if (DataUrlHandler.isDataUrl(currentUrl)) {
      BookSourceService.handleDataUrl(currentUrl);
    }

    let hasMore: boolean = true;
    const visitedUrls = new Set<string>();
    const maxPages = 50;

    while (hasMore && !visitedUrls.has(currentUrl) && visitedUrls.size < maxPages) {
      visitedUrls.add(currentUrl);
      try {
        let resolvedPageUrl = currentUrl;
        // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
        let body: string;
        if (DataUrlHandler.isDataUrl(currentUrl)) {
          BookSourceService.handleDataUrl(currentUrl);
          const base64Idx = currentUrl.indexOf('base64,');
          if (base64Idx >= 0) {
            const afterBase64 = currentUrl.substring(base64Idx + 7);
            const lastComma = afterBase64.lastIndexOf(',{');
            body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
          } else {
            body = '';
          }
        } else {
          const analyzed = await BookSourceService.analyzeRequestUrl(source, currentUrl, variables, undefined, undefined, tocUrl);
          resolvedPageUrl = analyzed.url;
          body = await BookSourceService.fetch(analyzed);
        }

        // 检测 JS 反爬页面（如水山听书：base64 混淆重定向，bodyLen 很小且含 atob）
        // 用 WebView 渲染获取真实 HTML
        if (body.length < 3000 && (body.includes('atob') || body.includes('base64')) && body.includes('Loading')) {
          try {
            const extractor = getWebViewAudioExtractor();
            body = await extractor.extract(resolvedPageUrl, 'document.documentElement.outerHTML', 3000);
          } catch (e) {
            console.warn(`[${TAG}] getBookToc: WebView render failed: ${e}`);
          }
        }

        const ctx = new AnalyzeContext(resolvedPageUrl, variables);
        BookSourceService.configureAnalyzeContext(
          ctx,
          source,
          variables,
          { origin: source.bookSourceUrl, bookUrl: tocUrl, name: '' } as BookContext,
        );
        const analyzer = new AnalyzeRule(body, ctx);
        // Legado 对齐：chapterList 支持 -/+ 前缀
        // - 前缀：反转列表（旧章节在前）
        // + 前缀：默认顺序（新章节在前，等同于无前缀）
        let chapterListRule = rule.chapterList;
        let reverseList = false;
        if (chapterListRule.startsWith('-')) {
          reverseList = true;
          chapterListRule = chapterListRule.substring(1);
        } else if (chapterListRule.startsWith('+')) {
          chapterListRule = chapterListRule.substring(1);
        }
        const items: Object[] = await analyzer.getElements(chapterListRule);
        if (reverseList) items.reverse();

        for (let idx = 0; idx < items.length; idx++) {
          const item: Object = items[idx];
          const a = new AnalyzeRule(item, ctx);
          let name = await a.getString(rule.chapterName) || '';
          let url = await a.getString(rule.chapterUrl) || '';
          if (!name) continue;

          // formatJs：章节标题后处理 JS（Legado 对齐）
          // 变量：index（1-based）、title（章节标题）、gInt（全局计数器）
          if (rule.formatJs) {
            try {
              const chapterInfo: Record<string, Object> = {};
              chapterInfo['title'] = name as Object;
              chapterInfo['url'] = url as Object;
              chapterInfo['index'] = allItems.length as Object;
              const extraCtx: Record<string, Object> = {};
              extraCtx['index'] = (allItems.length + 1) as Object;
              extraCtx['title'] = name as Object;
              extraCtx['gInt'] = allItems.length as Object;
              extraCtx['chapter'] = chapterInfo as Object;
              const jsCtx = BookSourceService.buildJsContext(source, extraCtx);
              const executor = getJSExecutor();
              const fmtCtx: Record<string, Object> = {};
              fmtCtx['result'] = name as Object;
              fmtCtx['baseUrl'] = resolvedPageUrl as Object;
              fmtCtx['index'] = (allItems.length + 1) as Object;
              fmtCtx['title'] = name as Object;
              fmtCtx['gInt'] = allItems.length as Object;
              const jsCtxKeys = Object.keys(jsCtx);
              for (const k of jsCtxKeys) fmtCtx[k] = jsCtx[k];
              const fmtResult = await executor.eval(rule.formatJs, fmtCtx);
              if (fmtResult && typeof fmtResult === 'string') {
                name = fmtResult;
              }
            } catch (e) {
              console.warn(`[${TAG}] formatJs error: ${e}`);
            }
          }

          // 修复 @js:result+',{...}' 未正确执行的情况
          // 如果 URL 包含字面量 "result+" 说明 JS 拼接失败，手动处理
          if (url.includes("result+'") || url.includes('result+"')) {
            const hrefVal = await a.getString('a@href') || '';
            if (hrefVal) {
              const configMatch = url.match(/result\+['"](.*)['"]/);
              url = configMatch ? hrefVal + configMatch[1] : hrefVal;
            }
          }

          url = url ? AnalyzeUrl.resolveUrl(resolvedPageUrl, url) : '';
          if (!url) url = resolvedPageUrl;

          const tocItem: TocItem = { name, url };
          if (rule.isVip) {
            const vip = await a.getString(rule.isVip);
            tocItem.isVip = vip === 'true' || vip === '1';
          }
          if (rule.isVolume) {
            const vol = await a.getString(rule.isVolume);
            tocItem.isVolume = vol === 'true' || vol === '1';
          }
          if (rule.updateTime) {
            tocItem.updateTime = await a.getString(rule.updateTime) || undefined;
          }
          if (rule.duration) {
            try {
              const durationStr = await a.getString(rule.duration) || '';
              if (durationStr) {
                // 尝试解析时长：支持秒数（如 "1234"）和时分秒格式（如 "01:23:45" 或 "23:45"）
                const parsed = BookSourceService.parseDuration(durationStr);
                if (parsed > 0) {
                  tocItem.duration = parsed;
                }
              }
            } catch (e) {
              hilog.warn(0, TAG, 'getBookToc: parse duration failed for chapter=%{public}s, error=%{public}s',
                name.substring(0, 30), String(e));
            }
          }
          allItems.push(tocItem);
        }

        // 下一页
        if (rule.nextTocUrl) {
          const nextUrlRaw = await analyzer.getString(rule.nextTocUrl);
          const nextUrl = nextUrlRaw ? AnalyzeUrl.resolveUrl(resolvedPageUrl, nextUrlRaw) : '';
          if (nextUrl) {
            currentUrl = nextUrl;
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : JSON.stringify(e);
        console.error(`[${TAG}] getBookToc page error: ${msg}, url=${currentUrl}`);
        hasMore = false;
      }
    }

    // 按 URL 去重(部分书源会返回重复章节,导致集数翻倍)
    const seenUrls = new Set<string>();
    const uniqueItems: TocItem[] = [];
    for (const item of allItems) {
      if (seenUrls.has(item.url)) continue;
      seenUrls.add(item.url);
      // 数据层统一剥书名前缀，让详情页/播放页/桌面卡片/媒体卡片都拿干净标题
      if (bookName) {
        item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
      }
      uniqueItems.push(item);
    }
    return uniqueItems;
  }

  // ──────────────────── 音频 URL ────────────────────

  static async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getAudioUrl(source, chapterUrl);
    }
    try {
      const rule = source.ruleContent;
      const contentRule = rule.audioUrl || rule.content;
      BookSourceService.prepareSourceContext(source);

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(chapterUrl)) {
        BookSourceService.handleDataUrl(chapterUrl);
      }

      // 拆分 Legado ",{...}" 配置语法（如 url,{webView:"true"}）
      const analyzedChapter = await BookSourceService.analyzeRequestUrl(source, chapterUrl);
      const split = AnalyzeUrl.splitUrlConfig(chapterUrl);
      const realUrl = analyzedChapter.url;
      const webViewVal = split.config.webView;
      // 触发 WebView 嗅探/取值的两个条件：
      //  1. chapterUrl 显式带 ,{"webView":true} 配置
      //  2. content 规则存在 sourceRegex 或 webJs（说明站点必须靠浏览器执行才能拿到音频 URL）
      const useWebView = webViewVal === true || String(webViewVal) === 'true'
        || !!(rule.sourceRegex && rule.sourceRegex.length > 0)
        || !!(rule.webJs && rule.webJs.length > 0);

      if (!contentRule || contentRule.trim().length === 0) {
        return realUrl;
      }

      const trimmed = contentRule.trim();
      if (trimmed === '@js:baseUrl' || trimmed === 'baseUrl') {
        return realUrl;
      }

      // WebView 模式：用 WebView 加载页面，提取音频 URL
      if (useWebView) {
        try {
          const extractor = getWebViewAudioExtractor();
          // 优先使用书源自定义 webJs，否则用内置通用提取逻辑
          const defaultJsExpr = `(function(){
            var result = '';
            // 1. 尝试 audio 标签
            var audios = document.querySelectorAll('audio');
            for(var i=0;i<audios.length;i++){
              if(audios[i].src) return audios[i].src;
            }
            // 2. 尝试 source 标签
            var sources = document.querySelectorAll('source');
            for(var i=0;i<sources.length;i++){
              if(sources[i].src) return sources[i].src;
            }
            // 3. 从页面 HTML 中用正则提取音频 URL
            var html = document.body.innerHTML;
            var patterns = [
              /https?:\\/\\/[^"'\\s<>]+\\.mp3[^"'\\s<>]*/gi,
              /https?:\\/\\/[^"'\\s<>]+\\.m4a[^"'\\s<>]*/gi,
              /"(https?:\\/\\/[^"]+\\.(?:mp3|m4a|wav|ogg|aac)[^"]*)"/gi,
              /'(https?:\\/\\/[^']+\\.(?:mp3|m4a|wav|ogg|aac)[^']*)'/gi
            ];
            for(var p=0;p<patterns.length;p++){
              var m = html.match(patterns[p]);
              if(m && m[0]) return m[0].replace(/['"]/g,'');
            }
            // 4. 尝试从 window 对象中查找音频 URL 变量
            var commonVars = ['audioUrl', 'audio_url', 'mp3Url', 'mp3_url', 'mediaUrl', 'media_url', 'playUrl', 'play_url', 'src', 'url'];
            for(var v=0;v<commonVars.length;v++){
              if(window[commonVars[v]] && typeof window[commonVars[v]] === 'string' && window[commonVars[v]].match(/\\.mp3|\\.m4a/)){
                return window[commonVars[v]];
              }
            }
            // 5. 尝试从 script 标签中提取 URL
            var scripts = document.querySelectorAll('script');
            for(var s=0;s<scripts.length;s++){
              var scriptText = scripts[s].textContent || scripts[s].innerText || '';
              var urlMatch = scriptText.match(/https?:\\/\\/[^"'\\s]+\\.(?:mp3|m4a)/);
              if(urlMatch) return urlMatch[0];
            }
            // 6. 返回页面标题和前 500 字符的 HTML 作为调试信息
            return 'DEBUG:title=' + document.title + ',bodyLen=' + html.length + ',html=' + html.substring(0, 500);
          })()`;
          // 如果书源定义了 webJs，使用它；否则用增强的默认提取逻辑（支持 iframe）
          const jsExpr = rule.webJs ? rule.webJs : `(function(){
            var result = '';
            // 1. 尝试主页面的 audio 标签
            var audios = document.querySelectorAll('audio');
            for(var i=0;i<audios.length;i++){
              if(audios[i].src) return audios[i].src;
            }
            // 2. 尝试 iframe 内的 audio 标签（跨域 iframe 无法访问，静默失败）
            try {
              var iframes = document.querySelectorAll('iframe');
              for(var j=0;j<iframes.length;j++){
                var iframeDoc = iframes[j].contentDocument || iframes[j].contentWindow.document;
                if(iframeDoc){
                  var iframeAudios = iframeDoc.querySelectorAll('audio');
                  for(var k=0;k<iframeAudios.length;k++){
                    if(iframeAudios[k].src) return iframeAudios[k].src;
                  }
                }
              }
            } catch(e) { /* 跨域 iframe 无法访问，忽略 */ }
            // 3. 尝试 source 标签
            var sources = document.querySelectorAll('source');
            for(var i=0;i<sources.length;i++){
              if(sources[i].src) return sources[i].src;
            }
            // 4. 从页面 HTML 中用正则提取音频 URL
            var html = document.body.innerHTML;
            var patterns = [
              /https?:\\/\\/[^"'\\s<>]+\\.mp3[^"'\\s<>]*/gi,
              /https?:\\/\\/[^"'\\s<>]+\\.m4a[^"'\\s<>]*/gi,
              /"(https?:\\/\\/[^"]+\\.(?:mp3|m4a|wav|ogg|aac)[^"]*)"/gi,
              /'(https?:\\/\\/[^']+\\.(?:mp3|m4a|wav|ogg|aac)[^']*)'/gi
            ];
            for(var p=0;p<patterns.length;p++){
              var m = html.match(patterns[p]);
              if(m && m[0]) return m[0].replace(/['"]/g,'');
            }
            return '';
          })()`;
          // 网络嗅探（onInterceptRequest）+ DOM 取值（runJavaScript）双路径并行：
          // - sourceRegex 在 WebView 任一请求 URL 命中时立即返回
          // - 两路均失败时才报错让上层处理
          const audioUrl = await extractor.extract(realUrl, jsExpr, 15000, rule.sourceRegex || '');
          if (audioUrl && !audioUrl.startsWith('DEBUG:')) {
            // 嗅探/解析得到真实音频 URL 后，仍按 content 规则做一次后处理
            // （如本源的 <js>result.replace(IP)</js> 换源 IP）
            return await BookSourceService.applyContentPostProcess(source, realUrl, audioUrl);
          }
          if (audioUrl.startsWith('DEBUG:')) {
            console.warn(`[${TAG}] getAudioUrl WebView debug: ${audioUrl}`);
          }
          // WebView 提取失败，抛出错误让上层处理
          throw new Error(`书源 ${source.bookSourceName} 无法提取音频 URL，可能需要更新书源规则`);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          console.error(`[${TAG}] getAudioUrl WebView failed: ${msg}`);
          throw e instanceof Error ? e : new Error(msg);
        }
      }

      const body = await BookSourceService.fetch(analyzedChapter);
      const chapterCtx: Record<string, Object> = {};
      chapterCtx['url'] = realUrl as Object;
      chapterCtx['chapterUrl'] = realUrl as Object;
      const ctx = new AnalyzeContext(realUrl);
      BookSourceService.configureAnalyzeContext(
        ctx,
        source,
        undefined,
        { origin: source.bookSourceUrl, bookUrl: realUrl, name: '' } as BookContext,
        chapterCtx,
      );
      const analyzer = new AnalyzeRule(body, ctx);
      const audioUrl = await analyzer.getString(contentRule);
      if (!audioUrl) return realUrl;

      return AnalyzeUrl.resolveUrl(realUrl, audioUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`[${TAG}] getAudioUrl error: ${msg}, url=${chapterUrl.substring(0, 100)}`);
      // 失败兜底：绝不返回带 ,{...} 配置后缀的原始 URL（AVPlayer 无法识别会直接报错），
      // 剥掉配置后缀只留干净 URL
      return AnalyzeUrl.splitUrlConfig(chapterUrl).url;
    }
  }

  /**
   * 对嗅探/解析得到的真实音频 URL 再跑一遍 content 规则做后处理。
   * 仅当 content 规则是 JS（<js>...</js> 或 @js:）时执行——典型如本源用
   * `<js>result=result.replace(旧IP,新IP)</js>` 把音频域名换成可用节点。
   * 非 JS 规则（CSS/JSONPath）针对页面 HTML 设计，不应作用在裸 URL 上，直接原样返回。
   */
  private static async applyContentPostProcess(
    source: BookSource, baseUrl: string, audioUrl: string
  ): Promise<string> {
    const rule = source.ruleContent;
    const contentRule = (rule.audioUrl || rule.content || '').trim();
    const isJs = contentRule.startsWith('<js>') || contentRule.toLowerCase().startsWith('@js:')
      || contentRule.toLowerCase().startsWith('js:');
    if (!isJs) return audioUrl;
    try {
      const ctx = new AnalyzeContext(baseUrl);
      ctx.jsLib = source.jsLib || '';
      // content 为裸 URL 字符串，JS 里的 result 即这个 URL
      const analyzer = new AnalyzeRule(audioUrl, ctx);
      const processed = await analyzer.getString(contentRule);
      if (processed && (processed.startsWith('http://') || processed.startsWith('https://'))) {
        return processed;
      }
    } catch (e) {
      console.warn(`[${TAG}] getAudioUrl postProcess failed: ${e}`);
    }
    return audioUrl;
  }

  // ──────────────────── 文本内容（支持多页） ────────────────────

  static async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getTextContent(source, chapterUrl, nextChapterUrl);
    }
    if (BookSourceService.isMaoyanSource(source)) {
      return BookSourceService.getMaoyanTextContent(source, chapterUrl);
    }
    try {
      const rule = source.ruleContent;
      const allContent: string[] = [];
      let currentUrl: string = chapterUrl;
      BookSourceService.prepareSourceContext(source);
      const resolvedNextChapterUrl = nextChapterUrl ? AnalyzeUrl.resolveUrl(chapterUrl, nextChapterUrl) : '';
      const chapterCtx: Record<string, Object> = {};
      chapterCtx['url'] = chapterUrl as Object;
      chapterCtx['chapterUrl'] = chapterUrl as Object;
      if (nextChapterUrl) chapterCtx['nextUrl'] = nextChapterUrl as Object;

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(currentUrl)) {
        BookSourceService.handleDataUrl(currentUrl);
      }
      let hasMore: boolean = true;
      const visitedUrls = new Set<string>();
      const maxPages = 20;

      while (hasMore && !visitedUrls.has(currentUrl) && visitedUrls.size < maxPages) {
        visitedUrls.add(currentUrl);

        // 防止循环到下一章
        if (resolvedNextChapterUrl && AnalyzeUrl.resolveUrl(chapterUrl, currentUrl) === resolvedNextChapterUrl) break;

        // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
        let resolvedPageUrl = currentUrl;
        let body: string;
        if (DataUrlHandler.isDataUrl(currentUrl)) {
          BookSourceService.handleDataUrl(currentUrl);
          const base64Idx = currentUrl.indexOf('base64,');
          if (base64Idx >= 0) {
            const afterBase64 = currentUrl.substring(base64Idx + 7);
            const lastComma = afterBase64.lastIndexOf(',{');
            body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
          } else {
            body = '';
          }
        } else {
          const analyzed = await BookSourceService.analyzeRequestUrl(source, currentUrl);
          resolvedPageUrl = analyzed.url;
          body = await BookSourceService.fetch(analyzed);
        }
        const ctx = new AnalyzeContext(resolvedPageUrl);
        BookSourceService.configureAnalyzeContext(
          ctx,
          source,
          undefined,
          { origin: source.bookSourceUrl, bookUrl: chapterUrl, name: '' } as BookContext,
          chapterCtx,
        );
        const analyzer = new AnalyzeRule(body, ctx);
        const content = await analyzer.getString(rule.content);
        if (content) {
          allContent.push(content);
        }

        // 下一页
        if (rule.nextContentUrl) {
          const nextUrl = await analyzer.getString(rule.nextContentUrl);
          if (nextUrl) {
            const resolved = AnalyzeUrl.resolveUrl(resolvedPageUrl, nextUrl);
            if (resolved !== resolvedNextChapterUrl) {
              currentUrl = resolved;
            } else {
              hasMore = false;
            }
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      }

      let result = allContent.join('\n');

      // title 规则：从内容页提取章节标题（部分书源标题只在正文页中）
      // 返回格式：title\ncontent
      if (rule.title && result) {
        try {
          // 用第一页的 body 提取标题
          const firstPageCtx = new AnalyzeContext(chapterUrl);
          BookSourceService.configureAnalyzeContext(
            firstPageCtx,
            source,
            undefined,
            { origin: source.bookSourceUrl, bookUrl: chapterUrl, name: '' } as BookContext,
            chapterCtx,
          );
          // 需要重新解析第一页（因为 analyzer 已经迭代完了）
          // 简化处理：从 result 中尝试提取标题（如果有 HTML 结构）
          const titleAnalyzer = new AnalyzeRule(result, firstPageCtx);
          const extractedTitle = await titleAnalyzer.getString(rule.title);
          if (extractedTitle) {
            result = extractedTitle + '\n' + result;
          }
        } catch (e) {
          console.warn(`[${TAG}] title rule error: ${e}`);
        }
      }

      // sourceRegex：提取音频 URL（bookSourceType=1 时使用）
      if (rule.sourceRegex && result) {
        try {
          const regex = new RegExp(rule.sourceRegex);
          const match = result.match(regex);
          if (match && match[0]) {
            result = match[0];
          } else {
            console.warn(`[${TAG}] sourceRegex no match: ${rule.sourceRegex}`);
          }
        } catch (e) {
          console.error(`[${TAG}] sourceRegex error: ${e}`);
        }
      }

      // 应用全局替换规则
      if (rule.replaceRegex && result) {
        try {
          const replaceRules = rule.replaceRegex.split('&&');
          for (const rr of replaceRules) {
            const parts = rr.split('##');
            if (parts.length >= 1) {
              const pattern = parts[0];
              const replacement = parts.length > 1 ? parts[1] : '';
              const regex = new RegExp(pattern, 'g');
              result = result.replace(regex, replacement);
            }
          }
        } catch { /* ignore replace errors */ }
      }

      return result;
    } catch (e) {
      console.error(`[${TAG}] getTextContent error:`, e);
      return '';
    }
  }

  // ──────────────────── 发现/推荐 ────────────────────

  /**
   * 解析订阅源的发现导航（Legado 风格 exploreUrl）
   * 形态 1：纯 URL（含 @js:/<js> 模板，跑完是普通字符串）→ 包成 [{title:'发现', url}]
   * 形态 2：JSON 数组 [{title, url, style?}, ...]（@js: 跑完返回 JSON 字符串）→ 直接采用
   * 返回的每一项都满足：title 非空、url 非空（自动 trim {{page}} 占位保留）
   */
  private static async parseExploreNavigation(source: BookSource): Promise<ExploreNavItem[]> {
    if (!source.exploreUrl || source.exploreUrl.length === 0) return [];
    if (BookSourceService.isMaoyanSource(source)) {
      return BookSourceService.getMaoyanExploreNavigation();
    }

    // 先查缓存（30 天 TTL，含版本戳）
    const sourceVersion = source.lastUpdateTime || 0;
    const cached = await PreferenceService.getExploreNavCache(source.bookSourceUrl, sourceVersion);
    if (cached) {
      return cached;
    }

    let raw = '';
    const trimmedUrl = source.exploreUrl.trim();

    // 快速路径：如果是 @js: 开头，直接用 JSExecutor 跑（绕过 AnalyzeUrl 的模板处理开销）
    if (/^@?js:/i.test(trimmedUrl)) {
      try {
        const jsCode = trimmedUrl.replace(/^@?js:/i, '').trim();
        const executor = getJSExecutor();
        const ctx: Record<string, Object> = {};
        ctx['java'] = getJavaBridge();
        ctx['source'] = getSourceContext();
        ctx['baseUrl'] = source.bookSourceUrl;
        if (source.jsLib) ctx['_jsLib'] = source.jsLib;
        // 8s 超时（首次解析慢可以接受，后续走缓存秒开）
        const timeoutPromise = new Promise<string>((_, reject) => {
          setTimeout(() => reject(new Error('JS execution timeout')), 8000);
        });
        const result = await Promise.race([
          executor.eval(jsCode, ctx),
          timeoutPromise
        ]);
        raw = result !== null && result !== undefined ? String(result) : '';
      } catch (e) {
        console.error(`[${TAG}] parseExploreNavigation: JS execution failed: ${e}`);
        return [];
      }
    } else {
      // 普通 URL：走原有 AnalyzeUrl 逻辑
      try {
        const placeholder = '__EXPLORE_PAGE_PLACEHOLDER__';
        const exploreUrlSafe = source.exploreUrl.replace(/\{\{page\}\}/g, placeholder);
        const analyzeUrl = new AnalyzeUrl(exploreUrlSafe, {
          page: 1, baseUrl: source.bookSourceUrl,
          _jsLib: source.jsLib || '',
        }, source.header);
        const analyzed = await analyzeUrl.getUrl();
        raw = analyzed.url.replace(new RegExp(placeholder, 'g'), '{{page}}');
      } catch (e) {
        console.warn(`[${TAG}] parseExploreNavigation: AnalyzeUrl failed: ${e}`);
        raw = source.exploreUrl;
      }
    }
    const trimmed = raw.trim();
    // 形态 2：JSON 数组
    if (trimmed.startsWith('[')) {
      try {
        const arr: Object = JSON.parse(trimmed);
        if (Array.isArray(arr)) {
          const items: Object[] = arr as Object[];
          const out: ExploreNavItem[] = [];
          for (const it of items) {
            const obj = it as Record<string, Object>;
            const title = obj && typeof obj['title'] === 'string' ? (obj['title'] as string).trim() : '';
            const url = obj && typeof obj['url'] === 'string' ? (obj['url'] as string).trim() : '';
            if (!title || !url) continue;
            // 过滤分组标题（url 为 null 或空）
            out.push({ title, url });
          }
          // 写缓存
          if (out.length > 0) {
            PreferenceService.setExploreNavCache(source.bookSourceUrl, sourceVersion, out).catch((e: Object) => {
              console.warn(`[${TAG}] parseExploreNavigation: cache write failed: ${e}`);
            });
          }
          return out;
        }
      } catch (e) {
        console.warn(`[${TAG}] parseExploreNavigation: JSON.parse failed: ${e}`);
      }
    }
    // 形态 1：纯 URL，整体作为单个分类
    if (trimmed.length > 0) {
      const nav: ExploreNavItem[] = [{ title: '发现', url: trimmed }];
      PreferenceService.setExploreNavCache(source.bookSourceUrl, sourceVersion, nav).catch((e: Object) => {
        console.warn(`[${TAG}] parseExploreNavigation: cache write failed: ${e}`);
      });
      return nav;
    }
    return [];
  }

  /**
   * 用 ruleExplore 解析指定分类 URL 的书列表（含下一页 URL，订阅源专用）
   */
  static async getExploreBooksByUrl(
    source: BookSource, categoryUrl: string, page: number = 1
  ): Promise<ExploreFetchResult> {
    const empty: ExploreFetchResult = { books: [], nextUrl: '' };
    try {
      if (!source.ruleExplore || !categoryUrl) return empty;
      if (BookSourceService.isMaoyanSource(source)) {
        return BookSourceService.getMaoyanExploreBooksByUrl(source, categoryUrl, page);
      }

      return await BookSourceService.contextLock.withLock(async (): Promise<ExploreFetchResult> => {
        BookSourceService.prepareSourceContext(source);
        const resolvedCategoryUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, categoryUrl);
        const analyzeUrl = new AnalyzeUrl(resolvedCategoryUrl, {
          page, baseUrl: source.bookSourceUrl,
          _jsLib: source.jsLib || '',
        }, source.header);
        const analyzed = await analyzeUrl.getUrl();
      if (!analyzed.charset) {
        const inferred = BookSourceService.inferCharset(source);
        if (inferred) analyzed.charset = inferred;
      }
      let body = await BookSourceService.fetch(analyzed);

      // JS 反爬兜底（与 getBookToc 保持一致）
      if (body.length < 3000 && (body.includes('atob') || body.includes('base64')) && body.includes('Loading')) {
        try {
          const extractor = getWebViewAudioExtractor();
          body = await extractor.extract(analyzed.url, 'document.documentElement.outerHTML', 3000);
        } catch (e) {
          console.warn(`[${TAG}] getExploreBooksByUrl: WebView render failed: ${e}`);
        }
      }

      const rule = source.ruleExplore;
      const ctx = new AnalyzeContext(analyzed.url);
      ctx.jsLib = source.jsLib || '';
      const analyzer = new AnalyzeRule(body, ctx);
      const items: Object[] = await analyzer.getElements(rule.bookList);
      if (items.length === 0) {
        return empty;
      }

      const results: SearchResult[] = [];
      for (let idx = 0; idx < items.length; idx++) {
        const item: Object = items[idx];
        const itemCtx = new AnalyzeContext(analyzed.url);
        itemCtx.jsLib = source.jsLib || '';
        const a = new AnalyzeRule(item, itemCtx);
        const name = await a.getString(rule.name) || '';
        if (!name) continue;
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const wordCount = rule.wordCount ? await a.getString(rule.wordCount) || '' : '';

        results.push({
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(analyzed.url, coverUrlRaw),
          bookUrl: AnalyzeUrl.resolveUrl(analyzed.url, bookUrlRaw),
          intro, kind, lastChapter, wordCount,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
          variables: itemCtx.variables,
        });
      }

      // 简单翻页：URL 中含 {{page}} 时直接 page+1；否则不分页
      let nextUrl = '';
      if (categoryUrl.includes('{{page}}') && results.length > 0) {
        nextUrl = categoryUrl;
      }
      const ret: ExploreFetchResult = { books: results, nextUrl, nextPage: page + 1 };
      return ret;
      }); // close contextLock.withLock
    } catch (e) {
      console.error(`[${TAG}] getExploreBooksByUrl error: ${e}`);
      return empty;
    }
  }

  /**
   * 兼容旧接口：取首个分类的前 N 本书
   */
  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getExploreBooks(source);
    }
    if (!source.ruleExplore) return [];
    const nav = await BookSourceService.parseExploreNavigation(source);
    if (nav.length === 0) return [];
    const first = nav[0];
    const r = await BookSourceService.getExploreBooksByUrl(source, first.url, 1);
    return r.books;
  }

  static async getAllExploreBooks(): Promise<ExploreSection[]> {
    const sources = await SourceDataService.getSources();
    const enabledSources = sources.filter((s: BookSource) =>
      s.enabled !== false && s.exploreUrl && s.exploreUrl.length > 0 && s.ruleExplore
    );

    const results: ExploreSection[] = [];
    const tasks = enabledSources.map(async (source: BookSource) => {
      try {
        const books = await BookSourceService.getExploreBooks(source);
        if (books.length > 0) {
          results.push({ source, books });
        }
      } catch { /* ignore */ }
    });

    await Promise.all(tasks);
    return results;
  }

  /** 内置源首页推荐板块（一个源多个板块） */
  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getHomeBlocks(source);
  }

  /**
   * 聚合所有启用源的首页推荐板块：
   * - 内置源：每个源可能产出多个板块（精品多人 / 最新作品 / 热播 ...）
   * - 订阅源：每个源用 getExploreBooks 取前 N 本，包成一个"发现"板块
   * 顺序：保持 SourceDataService.getSources() 的原顺序（用户订阅在前、内置在后）。
   * 单源 8s 超时，超时/失败该源直接跳过，不影响其他源。
   */
  static async getAllHomeBlocks(): Promise<HomeBlockSection[]> {
    const all: HomeBlockSection[] = [];
    await BookSourceService.streamAllHomeBlocks((blocks) => {
      for (const b of blocks) all.push(b);
    });
    return all;
  }

  /**
   * 渐进式聚合所有启用源的首页推荐板块。每完成一个源立即回调，便于 UI 边来边渲染。
   * 单源 8s 超时，超时/失败该源直接跳过。
   * 内置源优先（天下书音等先跑），订阅源限制并发数避免把网络打饱和。
   */
  static async streamAllHomeBlocks(onSource: (blocks: HomeBlockSection[], source: BookSource) => void): Promise<void> {
    const sources = await SourceDataService.getSources();
    const enabled = sources.filter((s: BookSource) => s.enabled !== false);
    const PER_SOURCE_TIMEOUT_MS = 15000;
    const MAX_CONCURRENCY = 6;

    // 内置源优先（一定有 home blocks），订阅源在后（多数没 ruleExplore，会立刻返回空）
    const ordered: BookSource[] = [];
    for (const s of enabled) {
      if (BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) ordered.push(s);
    }
    for (const s of enabled) {
      if (!BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) ordered.push(s);
    }

    const runOne = async (source: BookSource): Promise<void> => {
      const work: Promise<HomeBlockSection[]> = (async () => {
        const isBuiltin = BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl);
        if (isBuiltin) {
          const r = await BookSourceService.getHomeBlocks(source);
          return r;
        }
        if (!source.exploreUrl || source.exploreUrl.length === 0 || !source.ruleExplore) {
          return [] as HomeBlockSection[];
        }
        // 订阅源：解析发现导航 → 取前 N 个分类并发抓书 → 每个分类一个板块
        // 字段对齐内置源：title=「源名 · 分类名」、moreUrl=分类原始 URL（带 {{page}}）
        const nav = await BookSourceService.parseExploreNavigation(source);
        if (nav.length === 0) {
          return [] as HomeBlockSection[];
        }
        const HOME_BLOCKS_PER_SOURCE = 5;
        const HOME_BOOKS_PER_BLOCK = 10;
        const NAV_FETCH_CONCURRENCY = 3;
        const picked = nav.slice(0, HOME_BLOCKS_PER_SOURCE);
        const results: (HomeBlockSection | null)[] = new Array(picked.length).fill(null);
        let cur = 0;
        const fetchers: Promise<void>[] = [];
        for (let i = 0; i < Math.min(NAV_FETCH_CONCURRENCY, picked.length); i++) {
          fetchers.push((async () => {
            while (cur < picked.length) {
              const idx = cur++;
              const nv = picked[idx];
              try {
                const r = await BookSourceService.getExploreBooksByUrl(source, nv.url, 1);
                if (r.books.length === 0) continue;
                const limit = Math.min(HOME_BOOKS_PER_BLOCK, r.books.length);
                const layout = idx === 0 ? 'horizontal' : 'horizontal';
                results[idx] = new HomeBlockImpl(
                  nv.title,
                  r.books.slice(0, limit),
                  nv.url,
                  layout,
                  source.bookSourceName,
                  source.bookSourceUrl,
                );
              } catch (e) {
                console.warn(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} cat=${nv.title} error: ${e}`);
              }
            }
          })());
        }
        await Promise.all(fetchers);
        const sections: HomeBlockSection[] = [];
        for (const s of results) if (s) sections.push(s);
        return sections;
      })();

      const timeout = new Promise<HomeBlockSection[]>((resolve) => {
        setTimeout(() => {
          console.warn(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} TIMEOUT`);
          resolve([] as HomeBlockSection[]);
        }, PER_SOURCE_TIMEOUT_MS);
      });

      try {
        const blocks = await Promise.race([work, timeout]);
        if (blocks.length > 0) onSource(blocks, source);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} error ${msg}`);
      }
    };

    // 简单的固定并发池：每个 worker 串行从队列取任务
    let cursor = 0;
    const workers: Promise<void>[] = [];
    for (let i = 0; i < MAX_CONCURRENCY; i++) {
      workers.push((async () => {
        while (cursor < ordered.length) {
          const idx = cursor++;
          await runOne(ordered[idx]);
        }
      })());
    }
    await Promise.all(workers);
  }

  // ──────────────────── HTTP 工具 ────────────────────

  private static async fetch(analyzed: AnalyzedUrl): Promise<string> {
    if (analyzed.method === 'POST') {
      return HttpClient.post(analyzed.url, analyzed.body || '', analyzed.headers, analyzed.charset);
    }
    return HttpClient.get(analyzed.url, analyzed.headers, analyzed.charset);
  }

  /**
   * 判断是否需要执行 loginCheckJs
   * 仅当响应是有效 JSON 且包含实际数据时才跳过
   * "data":null 等空数据响应仍需 loginCheck 处理
   */
  private static needsLoginCheck(body: string): boolean {
    const trimmed = body.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        const parsed: Object = JSON.parse(trimmed);
        // JSON 数组且有数据 → 跳过
        if (Array.isArray(parsed) && parsed.length > 0) return false;
        // JSON 对象：检查 data 字段是否有实际数据
        if (typeof parsed === 'object' && parsed !== null) {
          const data = (parsed as Record<string, Object>)['data'];
          if (data !== null && data !== undefined) return false;
        }
        // data 为 null 或空 → 仍需 loginCheck
        return true;
      } catch {
        return true;
      }
    }
    return true;
  }

  /**
   * 执行 loginCheckJs（搜索前验证）
   * 原生实现 Legado loginCheckJs 的常见模式，不依赖 JS 引擎
   * 支持：HTML 跳转页面处理、"data":null 时从 loginCheckJs 提取 POST 配置建立会话
   */
  private static async executeLoginCheck(source: BookSource, body: string, keyword: string): Promise<string> {
    try {
      if (!source.loginCheckJs) return body;

      // 模式 1：HTML 跳转页面（含"即将跳转"）
      if (body.includes('即将跳转')) {
        try {
          const hrefMatch = body.match(/class="notfoud-container"[^>]*>[\s\S]*?<a[^>]+href="([^"]+)"/);
          if (hrefMatch) {
            const redirectUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, hrefMatch[1]);
            const newBody = await HttpClient.get(redirectUrl);
            return newBody;
          }
        } catch (e) {
          console.warn(`[${TAG}] loginCheck redirect failed: ${e}`);
        }
      }

      // 模式 2："data":null → 从 loginCheckJs 提取 POST URL 建立搜索会话
      if (body.includes('"data":null')) {
        const postInfo = BookSourceService.extractPostFromLoginCheckJs(source.loginCheckJs, source.bookSourceUrl, keyword);
        if (postInfo) {
          try {
            const headers: Record<string, string> = {
              'Content-Type': 'application/x-www-form-urlencoded',
            };
            if (source.header) {
              try {
                const h = JSON.parse(source.header) as Record<string, string>;
                if (h['User-Agent']) headers['User-Agent'] = h['User-Agent'];
                if (h['Referer']) headers['Referer'] = h['Referer'];
              } catch { /* ignore */ }
            }
            await HttpClient.post(postInfo.url, postInfo.body, headers);
            return '__RETRY_SEARCH__';
          } catch (e) {
            console.warn(`[${TAG}] loginCheck POST session failed: ${e}`);
          }
        }
      }

      return body;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] executeLoginCheck error: ${msg}`);
      return body;
    }
  }

  /**
   * 从 loginCheckJs 代码中提取 POST URL 和 body 参数（通用）
   * 支持 Legado 常见模式：source.key + `/path,{"body":"searchword=${key}","method":"POST"}`
   */
  private static extractPostFromLoginCheckJs(js: string, baseUrl: string, keyword: string): PostInfo | null {
    // 匹配 URL 路径（可能在模板字面量或字符串拼接中）
    const urlMatch = js.match(/["'`]([^"'`]*?\.html)/);
    if (!urlMatch) return null;
    const path = urlMatch[1];
    const fullUrl = AnalyzeUrl.resolveUrl(baseUrl, path);

    // 匹配 body 参数（如 "searchword=${key}" 或 "searchword=xxx"）
    const bodyMatch = js.match(/"body"\s*:\s*"([^"]+)"/);
    let postBody = '';
    if (bodyMatch) {
      postBody = bodyMatch[1]
        .replace(/\$\{key\}/g, encodeURIComponent(keyword))
        .replace(/\$\{searchKey\}/g, encodeURIComponent(keyword));
    } else {
      postBody = `searchword=${encodeURIComponent(keyword)}`;
    }

    const result: PostInfo = { url: fullUrl, body: postBody };
    return result;
  }

  private static async fetchWithSource(url: string, source: BookSource): Promise<string> {
    // 并发限速（Legado concurrentRate 对齐）
    if (source.concurrentRate) {
      const limiter = getRateLimiter(source.concurrentRate);
      if (limiter) await limiter.acquire();
    }
    const cleanUrl = url.replace(/[\r\n\t]/g, '').trim();
    const analyzeUrl = new AnalyzeUrl(cleanUrl, { baseUrl: source.bookSourceUrl }, source.header);
    const analyzed = await analyzeUrl.getUrl();
    // 若详情/章节 URL 自身没声明 charset，复用 search/explore 的 charset 推断
    if (!analyzed.charset) {
      const inferred = BookSourceService.inferCharset(source);
      if (inferred) analyzed.charset = inferred;
    }
    return BookSourceService.fetch(analyzed);
  }

  /** 从 source.searchUrl / exploreUrl 中提取 ,{ "charset": "..." } 作为该源默认编码 */
  private static inferCharset(source: BookSource): string {
    const candidates: string[] = [];
    if (source.searchUrl) candidates.push(source.searchUrl);
    if (source.exploreUrl) candidates.push(source.exploreUrl);
    for (const c of candidates) {
      const m = c.match(/,\s*\{[^}]*"charset"\s*:\s*"([^"]+)"/i);
      if (m) return m[1];
    }
    return '';
  }
}

class ListenBookSourceRuntimeAdapter implements SourceEngineAdapter {
  async searchBooks(source: BookSource, keyword: string, page?: number): Promise<SearchResult[]> {
    return BookSourceService.searchBooks(source, keyword, page || 1);
  }

  async getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    return BookSourceService.getBookInfo(source, bookUrl, variables);
  }

  async getBookToc(source: BookSource, tocUrl: string, variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    return BookSourceService.getBookToc(source, tocUrl, variables, bookName);
  }

  async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    return BookSourceService.getAudioUrl(source, chapterUrl);
  }

  async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    return BookSourceService.getTextContent(source, chapterUrl, nextChapterUrl);
  }

  async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    return BookSourceService.getExploreBooks(source);
  }

  async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    return BookSourceService.getHomeBlocks(source);
  }
}

class ListenBookSourceFetchAdapter implements SourceFetchAdapter {
  async fetchText(url: string): Promise<string> {
    return HttpClient.get(url);
  }
}

SourceRuntime.setFetchAdapter(new ListenBookSourceFetchAdapter());
SourceRuntime.setAdapter(new ListenBookSourceRuntimeAdapter());
