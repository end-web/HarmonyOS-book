import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookSource, SearchResult, TocItem, SourceSubscription } from '../model/BookSource';
import { AnalyzeRule, AnalyzeContext } from './rule/AnalyzeRule';
import { HttpClient } from './http/HttpClient';
import { SourceDataService } from './SourceDataService';

const DOMAIN = 0x0000;
const TAG = 'BookSourceService';

interface ExploreSection {
  source: BookSource;
  books: SearchResult[];
}

function parseHeaders(header: string): Record<string, string> {
  try {
    return JSON.parse(header) as Record<string, string>;
  } catch {
    return {};
  }
}

function resolveUrl(base: string, relative: string): string {
  if (!relative) return '';
  if (relative.startsWith('http://') || relative.startsWith('https://') || relative.startsWith('//')) {
    return relative;
  }
  // 从 base URL 提取 origin
  const match = base.match(/^(https?:\/\/[^/]+)/);
  if (!match) return relative;
  const origin = match[1];
  if (relative.startsWith('/')) {
    return origin + relative;
  }
  // 相对路径
  const basePath = base.substring(0, base.lastIndexOf('/') + 1);
  return basePath + relative;
}

interface UrlConfig {
  method?: string;
  body?: string;
  charset?: string;
  headers?: Record<string, string>;
}

export interface ParsedUrl {
  url: string;
  method: string;
  body?: string;
  charset?: string;
  headers?: Record<string, string>;
}

/**
 * 解析 Legado URL 配置（格式：url, {"method":"POST","body":"...","headers":{...}}）
 * 所有 HTTP 请求场景共用：search / toc / content / audio
 */
export function parseUrlConfig(raw: string): ParsedUrl {
  const configMatch = raw.match(/^(.*?)\s*,\s*(\{[\s\S]*\})\s*$/);
  if (configMatch) {
    const url = configMatch[1].trim();
    try {
      const config: UrlConfig = JSON.parse(configMatch[2]) as UrlConfig;
      return {
        url,
        method: (config.method || 'GET').toUpperCase(),
        body: config.body,
        charset: config.charset,
        headers: config.headers,
      };
    } catch {
      // JSON 解析失败，当作普通 URL
    }
  }
  return { url: raw, method: 'GET' };
}

/**
 * 合并书源全局 header 与单次请求 header
 */
function mergeHeaders(sourceHeader: string | undefined, extra?: Record<string, string>): Record<string, string> {
  const headers: Record<string, string> = sourceHeader ? parseHeaders(sourceHeader) : {};
  if (extra) {
    const keys = Object.keys(extra);
    for (const k of keys) {
      headers[k] = extra[k];
    }
  }
  return headers;
}

/**
 * 通用 HTTP 请求：自动解析 url,{...} 配置，支持 GET/POST 和自定义 headers
 */
async function fetchWithConfig(rawUrl: string, sourceHeader?: string): Promise<string> {
  const parsed = parseUrlConfig(rawUrl);
  const headers = mergeHeaders(sourceHeader, parsed.headers);
  console.info(`[fetchWithConfig] url=${parsed.url}, method=${parsed.method}`);
  if (parsed.method === 'POST') {
    return HttpClient.post(parsed.url, parsed.body || '', headers);
  }
  return HttpClient.get(parsed.url, headers);
}

function buildSearchUrl(searchUrl: string, keyword: string, page: number): ParsedUrl {
  // 替换 Legado 标准模板变量
  let raw = searchUrl
    .replace(/\{\{key\}\}/g, encodeURIComponent(keyword))
    .replace(/\{\{keyword\}\}/g, encodeURIComponent(keyword))
    .replace(/\{\{searchKey\}\}/g, encodeURIComponent(keyword))
    .replace(/\{\{page\}\}/g, String(page))
    .replace(/\{\{searchPage\}\}/g, String(page))
    .replace(/\{\{pageSize\}\}/g, '20');

  return parseUrlConfig(raw);
}

export class BookSourceService {
  static async fetchSourcesFromUrl(subscriptionUrl: string): Promise<BookSource[]> {
    try {
      const body = await HttpClient.get(subscriptionUrl);
      return BookSourceService.parseSourcesFromJson(body);
    } catch {
      return [];
    }
  }

  static parseSourcesFromJson(jsonText: string): BookSource[] {
    try {
      const data: Object = JSON.parse(jsonText) as Object;
      return Array.isArray(data) ? data as BookSource[] : [data as BookSource];
    } catch {
      return [];
    }
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    try {
      const parsed = buildSearchUrl(source.searchUrl, keyword, page);
      const headers = mergeHeaders(source.header, parsed.headers);

      let body: string;
      if (parsed.method === 'POST') {
        body = await HttpClient.post(parsed.url, parsed.body || '', headers);
      } else {
        body = await HttpClient.get(parsed.url, headers);
      }

      const rule = source.ruleSearch;
      const ctx = new AnalyzeContext(source.bookSourceUrl);
      const analyzer = new AnalyzeRule(body, ctx);
      const items = await analyzer.getElements(rule.bookList);
      hilog.info(DOMAIN, TAG, `searchBooks: found ${items.length} items`);
      if (items.length === 0) return [];
      // 打印第一个 item 的内容用于调试
      if (items.length > 0) {
        const firstItem = typeof items[0] === 'string' ? items[0] : JSON.stringify(items[0]);
        hilog.info(DOMAIN, TAG, `searchBooks: first item=${firstItem.substring(0, 500)}`);
      }

      const results: SearchResult[] = [];
      const baseUrl = source.bookSourceUrl;
      for (const item of items) {
        const a = new AnalyzeRule(item, ctx);
        const name = await a.getString(rule.name) || '';
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        hilog.info(DOMAIN, TAG, `searchBooks: rule.bookUrl="${rule.bookUrl}", bookUrlRaw="${bookUrlRaw}"`);
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const r: SearchResult = {
          name, author,
          coverUrl: resolveUrl(baseUrl, coverUrlRaw),
          bookUrl: resolveUrl(baseUrl, bookUrlRaw),
          intro, kind, lastChapter,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
        };
        results.push(r);
      }
      return results;
    } catch {
      return [];
    }
  }

  static async getBookToc(source: BookSource, tocUrl: string): Promise<TocItem[]> {
    try {
      console.info(`[BookSourceService] getBookToc: url=${tocUrl}`);
      const body = await fetchWithConfig(tocUrl, source.header);
      console.info(`[BookSourceService] getBookToc: body length=${body.length}, first 200=${body.substring(0, 200)}`);

      const rule = source.ruleToc;
      console.info(`[BookSourceService] getBookToc: rule.chapterList=${rule.chapterList}`);
      const ctx = new AnalyzeContext(tocUrl);
      const analyzer = new AnalyzeRule(body, ctx);
      const items = await analyzer.getElements(rule.chapterList);
      console.info(`[BookSourceService] getBookToc: items.length=${items.length}`);
      if (items.length === 0) return [];

      const baseUrl = tocUrl;
      const toc: TocItem[] = [];
      for (const item of items) {
        const a = new AnalyzeRule(item, ctx);
        const name = await a.getString(rule.chapterName) || '';
        let url = await a.getString(rule.chapterUrl) || '';
        if (name && url) {
          // 有声书 chapterUrl 可能直接就是音频 URL（如 $.mp3Filepath）
          // 也可能包含 ,{...} 配置，此时 resolveUrl 只处理 URL 部分
          const parsed = parseUrlConfig(url);
          const resolved = resolveUrl(baseUrl, parsed.url);
          // 保留配置部分供 getAudioUrl 使用
          url = parsed.url !== url
            ? resolved + ',' + url.substring(url.indexOf(','))
            : resolved;
          const t: TocItem = { name, url };
          toc.push(t);
        }
      }
      return toc;
    } catch {
      return [];
    }
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    try {
      const rule = source.ruleContent;
      const contentRule = rule.audioUrl || rule.content;

      // ruleContent 为空 → chapterUrl 本身就是音频 URL
      if (!contentRule || contentRule.trim().length === 0) {
        return chapterUrl;
      }

      // @js:baseUrl → 直接返回 chapterUrl
      const trimmed = contentRule.trim();
      if (trimmed === '@js:baseUrl' || trimmed === 'baseUrl') {
        return chapterUrl;
      }

      // 判断是否需要请求：纯 JSONPath / CSS 选择器需要先请求内容
      // @js: 可能需要请求（取决于是否引用 src/result）
      const needsFetch = trimmed.startsWith('$.') || trimmed.startsWith('$[') ||
        trimmed.startsWith('@css:') || trimmed.startsWith('@@') ||
        trimmed.startsWith('//') || trimmed.startsWith('@xpath:') ||
        trimmed.includes('src') || trimmed.includes('result') ||
        trimmed.startsWith('@js:') || trimmed.startsWith('<js>');

      if (!needsFetch) {
        // 纯字段名如 playPathAacv224||playUrl64 → chapterUrl 的 JSON 响应中提取
        const body = await fetchWithConfig(chapterUrl, source.header);
        const contentCtx = new AnalyzeContext(chapterUrl);
        const analyzer = new AnalyzeRule(body, contentCtx);
        const audioUrl = await analyzer.getString(contentRule);
        return audioUrl || chapterUrl;
      }

      const body = await fetchWithConfig(chapterUrl, source.header);
      const contentCtx = new AnalyzeContext(chapterUrl);
      const analyzer = new AnalyzeRule(body, contentCtx);
      const audioUrl = await analyzer.getString(contentRule);
      return audioUrl || chapterUrl;
    } catch {
      return chapterUrl;
    }
  }

  static async getTextContent(source: BookSource, chapterUrl: string): Promise<string> {
    try {
      const body = await fetchWithConfig(chapterUrl, source.header);
      const rule = source.ruleContent;
      const textCtx = new AnalyzeContext(chapterUrl);
      const analyzer = new AnalyzeRule(body, textCtx);
      const content = await analyzer.getString(rule.content);
      return content || '';
    } catch {
      return '';
    }
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    const firstName = sources.length > 0 ? sources[0].bookSourceGroup || '未命名' : '未命名';
    const s: SourceSubscription = { url, name: firstName, count: sources.length, lastUpdate: Date.now() };
    return s;
  }

  /**
   * 从书源获取推荐/发现内容
   */
  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    try {
      if (!source.exploreUrl || !source.ruleExplore) {
        return [];
      }

      const headers: Record<string, string> = source.header ? parseHeaders(source.header) : {};
      const body = await HttpClient.get(source.exploreUrl, headers);

      const rule = source.ruleExplore;
      const ctx = new AnalyzeContext(source.bookSourceUrl);
      const analyzer = new AnalyzeRule(body, ctx);
      const items = await analyzer.getElements(rule.bookList);
      hilog.info(DOMAIN, TAG, `searchBooks: found ${items.length} items`);
      if (items.length === 0) return [];
      // 打印第一个 item 的内容用于调试
      if (items.length > 0) {
        const firstItem = typeof items[0] === 'string' ? items[0] : JSON.stringify(items[0]);
        hilog.info(DOMAIN, TAG, `searchBooks: first item=${firstItem.substring(0, 500)}`);
      }

      const results: SearchResult[] = [];
      const baseUrl = source.bookSourceUrl;
      for (const item of items) {
        const a = new AnalyzeRule(item, ctx);
        const name = await a.getString(rule.name) || '';
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        hilog.info(DOMAIN, TAG, `searchBooks: rule.bookUrl="${rule.bookUrl}", bookUrlRaw="${bookUrlRaw}"`);
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const r: SearchResult = {
          name, author,
          coverUrl: resolveUrl(baseUrl, coverUrlRaw),
          bookUrl: resolveUrl(baseUrl, bookUrlRaw),
          intro, kind, lastChapter,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
        };
        results.push(r);
      }
      return results;
    } catch {
      return [];
    }
  }

  /**
   * 从所有已启用书源获取推荐内容
   */
  static async getAllExploreBooks(): Promise<ExploreSection[]> {
    const sources = await SourceDataService.getSources();
    const enabledSources = sources.filter((s: BookSource) =>
      s.enabled !== false &&
      s.exploreUrl &&
      s.exploreUrl.length > 0 &&
      s.ruleExplore &&
      s.bookSourceType === 0  // 只获取文本源的推荐
    );

    const results: ExploreSection[] = [];

    // 并行获取所有书源的推荐
    const tasks = enabledSources.map(async (source: BookSource) => {
      try {
        const books = await BookSourceService.getExploreBooks(source);
        if (books.length > 0) {
          const section: ExploreSection = { source, books };
          results.push(section);
        }
      } catch {
        // 忽略单个书源的错误
      }
    });

    await Promise.all(tasks);
    return results;
  }
}
