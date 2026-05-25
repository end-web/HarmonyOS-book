import { BookSource, SearchResult, TocItem, SourceSubscription } from '../model/BookSource';
import { AnalyzeRule } from './rule/AnalyzeRule';
import { HttpClient } from './http/HttpClient';

function parseHeaders(header: string): Record<string, string> {
  try {
    return JSON.parse(header) as Record<string, string>;
  } catch {
    return {};
  }
}

function buildSearchUrl(searchUrl: string, keyword: string, page: number): string {
  return searchUrl
    .replace(/\{\{keyword\}\}/g, encodeURIComponent(keyword))
    .replace(/\{\{page\}\}/g, String(page))
    .replace(/\{\{pageSize\}\}/g, '20');
}

export class BookSourceService {
  static async fetchSourcesFromUrl(subscriptionUrl: string): Promise<BookSource[]> {
    try {
      const body = await HttpClient.get(subscriptionUrl);
      const data: Object = JSON.parse(body) as Object;
      return Array.isArray(data) ? data as BookSource[] : [data as BookSource];
    } catch {
      return [];
    }
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    try {
      const url = buildSearchUrl(source.searchUrl, keyword, page);
      const headers = source.header ? parseHeaders(source.header) : undefined;
      const body = await HttpClient.get(url, headers);

      const rule = source.ruleSearch;
      const analyzer = new AnalyzeRule(body);
      const items = await analyzer.getElements(rule.bookList);
      if (items.length === 0) return [];

      const results: SearchResult[] = [];
      for (const item of items) {
        const a = new AnalyzeRule(item);
        const name = await a.getString(rule.name) || '';
        const author = await a.getString(rule.author) || '';
        const coverUrl = await a.getString(rule.coverUrl) || '';
        const bookUrl = await a.getString(rule.bookUrl) || '';
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const r: SearchResult = {
          name, author, coverUrl, bookUrl, intro, kind, lastChapter,
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
      const headers = source.header ? parseHeaders(source.header) : undefined;
      const body = await HttpClient.get(tocUrl, headers);

      const rule = source.ruleToc;
      const analyzer = new AnalyzeRule(body);
      const items = await analyzer.getElements(rule.chapterList);
      if (items.length === 0) return [];

      const toc: TocItem[] = [];
      for (const item of items) {
        const a = new AnalyzeRule(item);
        const name = await a.getString(rule.chapterName) || '';
        const url = await a.getString(rule.chapterUrl) || '';
        if (name && url) {
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
      const headers = source.header ? parseHeaders(source.header) : undefined;
      const body = await HttpClient.get(chapterUrl, headers);
      const rule = source.ruleContent;
      const analyzer = new AnalyzeRule(body);
      const audioUrl = await analyzer.getString(rule.audioUrl || rule.content);
      return audioUrl || chapterUrl;
    } catch {
      return chapterUrl;
    }
  }

  static async getTextContent(source: BookSource, chapterUrl: string): Promise<string> {
    try {
      const headers = source.header ? parseHeaders(source.header) : undefined;
      const body = await HttpClient.get(chapterUrl, headers);
      const rule = source.ruleContent;
      const analyzer = new AnalyzeRule(body);
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
}
