import { Book, BookChapter, BookSource, SearchBook } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { BookUrlResolver } from './BookUrlResolver';
import { CoverUrlNormalizer } from '../../utils/CoverUrlNormalizer';

/**
 * Compatibility helpers for ordinary imported-source data. This module deliberately contains no
 * publisher, aggregator, mirror, credential, signing key or private API knowledge.
 */
export class ExploreDataUrlEntry {
  title: string = '';
  url: string = '';
}

export class BookSourceDataUrlSupport {
  static isEncodedSource(url: string): boolean {
    // data URLs are decoded by AnalyzeUrl and then evaluated by the source's own rules.
    return false;
  }

  static sourceUsesGySearch(source: BookSource): boolean {
    return false;
  }

  static sourceUsesGyExplore(source: BookSource): boolean {
    return false;
  }

  static async getExplorePlatforms(http: HttpClient, source: BookSource,
    tab: string = ''): Promise<string[]> {
    return [];
  }

  static getSingleSitePlatformName(source: BookSource): string {
    const group = (source.bookSourceGroup || '').split(',')
      .map((item: string): string => item.trim())
      .filter((item: string): boolean => !!item)[0];
    if (group) return group;
    return (source.bookSourceName || source.bookSourceUrl || '默认站点').trim();
  }

  static buildRequestUrl(source: BookSource, rawUrl: string, page: string = '1',
    keyword: string = ''): string {
    // Function calls and templates are executed by the generic source runtime.
    return '';
  }

  static sourceBackendHost(source: BookSource): string {
    const configured = this.configuredOrigin(source.variable || '');
    if (configured) return configured;
    const sourceOrigin = this.origin(source.bookSourceUrl || '');
    if (sourceOrigin) return sourceOrigin;
    const declared = `${source.jsLib || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}`
      .match(/https?:\/\/[^'"`\s,)\]]+/i);
    return declared && declared[0] ? this.origin(declared[0]) : '';
  }

  static async search(http: HttpClient, source: BookSource, keyword: string,
    page: number = 1, maxResponseBytes?: number): Promise<SearchBook[]> {
    return [];
  }

  static async getExploreEntries(http: HttpClient, platform: string = '', tab: string = '',
    sourceType: string = '', bookSource?: BookSource): Promise<ExploreDataUrlEntry[]> {
    return [];
  }

  static normalizeExplorePlatform(platform: string): string {
    return (platform || '').trim();
  }

  static async explore(http: HttpClient, source: BookSource, url: string,
    page: number): Promise<SearchBook[]> {
    return [];
  }

  static async getBookInfo(http: HttpClient, source: BookSource, book: Book): Promise<Book> {
    return book;
  }

  static async getChapterList(http: HttpClient, source: BookSource,
    book: Book): Promise<BookChapter[]> {
    return [];
  }

  static async getContent(http: HttpClient, source: BookSource, book: Book,
    chapter: BookChapter): Promise<string> {
    return '';
  }

  static normalizeCoverUrl(source: BookSource, url: string, baseUrl: string = ''): string {
    const resolved = BookUrlResolver.resolve(url, baseUrl || source.bookSourceUrl);
    return CoverUrlNormalizer.normalize(resolved);
  }

  static normalizeCoverUrlFromItem(source: BookSource, primaryUrl: string, itemJson: string,
    baseUrl: string = ''): string {
    const primary = this.normalizeCoverUrl(source, primaryUrl, baseUrl);
    if (primary && !this.isUnresolved(primary)) return primary;
    const fallback = this.firstCoverFromJson(itemJson);
    return this.normalizeCoverUrl(source, fallback, baseUrl);
  }

  static normalizeCoverUrlFromResponse(source: BookSource, responseBody: string, bookId: string,
    baseUrl: string = ''): string {
    if (!responseBody || !bookId) return '';
    try {
      const value = JSON.parse(responseBody) as Object;
      const record = this.findRecord(value, bookId);
      return this.normalizeCoverUrl(source, record ? this.firstCover(record) : '', baseUrl);
    } catch (_) {
      return '';
    }
  }

  private static configuredOrigin(raw: string): string {
    try {
      const value = JSON.parse(raw || '{}') as Object;
      if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
      const record = value as Record<string, Object>;
      return this.origin(String(record['server'] || record['host'] || ''));
    } catch (_) {
      return '';
    }
  }

  private static origin(url: string): string {
    const match = /^(https?:\/\/[^/]+)/i.exec((url || '').trim());
    return match && match[1] ? match[1].replace(/\/+$/, '') : '';
  }

  private static firstCoverFromJson(text: string): string {
    try {
      return this.firstCover(JSON.parse(text || '{}') as Object);
    } catch (_) {
      return '';
    }
  }

  private static firstCover(value: Object | null | undefined): string {
    if (!value || typeof value !== 'object') return '';
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const found = this.firstCover(item);
        if (found) return found;
      }
      return '';
    }
    const record = value as Record<string, Object>;
    const keys = ['coverUrl', 'cover', 'cover_url', 'image', 'imageUrl', 'img', 'pic', 'thumbnail'];
    for (const key of keys) {
      const candidate = String(record[key] || '').trim();
      if (candidate && !this.isUnresolved(candidate)) return candidate;
    }
    for (const key of Object.keys(record)) {
      const found = this.firstCover(record[key]);
      if (found) return found;
    }
    return '';
  }

  private static findRecord(value: Object | null | undefined, id: string): Record<string, Object> | null {
    if (!value || typeof value !== 'object') return null;
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const found = this.findRecord(item, id);
        if (found) return found;
      }
      return null;
    }
    const record = value as Record<string, Object>;
    const keys = ['id', 'bookId', 'book_id', 'novelId', 'novel_id'];
    if (keys.some((key: string): boolean => String(record[key] || '') === id)) return record;
    for (const key of Object.keys(record)) {
      const found = this.findRecord(record[key], id);
      if (found) return found;
    }
    return null;
  }

  private static isUnresolved(value: string): boolean {
    return !value || value.includes('{{') || value.includes('}}') || value.includes('$..') || value.includes('$.');
  }
}
