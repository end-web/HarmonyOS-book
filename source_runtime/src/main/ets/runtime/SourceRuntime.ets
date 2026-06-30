import { BookInfo, BookSource, HomeBlockSection, SearchResult, SourceSubscription, TocItem } from '../model/BookSource';
import { AggregateSourceExpander } from './AggregateSourceExpander';
import { SourceFetchAdapter } from './SourceAdapters';
import { SourceImportParser } from './SourceImportParser';
import { SourceUrlResolver } from './SourceUrlResolver';

export interface SourceEngineAdapter {
  searchBooks(source: BookSource, keyword: string, page?: number): Promise<SearchResult[]>;
  getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null>;
  getBookToc(source: BookSource, tocUrl: string, variables?: Record<string, string>, bookName?: string): Promise<TocItem[]>;
  getAudioUrl(source: BookSource, chapterUrl: string): Promise<string>;
  getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string>;
  getExploreBooks(source: BookSource): Promise<SearchResult[]>;
  getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]>;
}

class EmptySourceEngineAdapter implements SourceEngineAdapter {
  async searchBooks(_source: BookSource, _keyword: string, _page?: number): Promise<SearchResult[]> {
    return [];
  }

  async getBookInfo(_source: BookSource, _bookUrl: string, _variables?: Record<string, string>): Promise<BookInfo | null> {
    return null;
  }

  async getBookToc(_source: BookSource, _tocUrl: string, _variables?: Record<string, string>, _bookName?: string): Promise<TocItem[]> {
    return [];
  }

  async getAudioUrl(_source: BookSource, chapterUrl: string): Promise<string> {
    return chapterUrl;
  }

  async getTextContent(_source: BookSource, _chapterUrl: string, _nextChapterUrl?: string): Promise<string> {
    return '';
  }

  async getExploreBooks(_source: BookSource): Promise<SearchResult[]> {
    return [];
  }

  async getHomeBlocks(_source: BookSource): Promise<HomeBlockSection[]> {
    return [];
  }
}

class EmptySourceFetchAdapter implements SourceFetchAdapter {
  async fetchText(_url: string): Promise<string> {
    return '';
  }
}

export class SourceRuntime {
  private static adapter: SourceEngineAdapter = new EmptySourceEngineAdapter();
  private static fetchAdapter: SourceFetchAdapter = new EmptySourceFetchAdapter();

  static setAdapter(adapter: SourceEngineAdapter): void {
    SourceRuntime.adapter = adapter;
  }

  static setFetchAdapter(adapter: SourceFetchAdapter): void {
    SourceRuntime.fetchAdapter = adapter;
  }

  static parseSourcesFromJson(jsonText: string): BookSource[] {
    return SourceImportParser.parseSources(jsonText).sources;
  }

  static convertToHarmonySources(content: string): string {
    return SourceImportParser.convertToHarmonySources(content);
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    return SourceImportParser.buildSubscription(url, sources);
  }

  static async fetchSourcesFromUrl(subscriptionUrl: string): Promise<BookSource[]> {
    const candidates = SourceUrlResolver.resolveCandidates(subscriptionUrl);
    for (const url of candidates) {
      try {
        const body = await SourceRuntime.fetchAdapter.fetchText(url);
        const sources = SourceRuntime.parseSourcesFromJson(body);
        if (sources.length > 0) return sources;
      } catch {
        continue;
      }
    }
    return [];
  }

  static async expandAggregateSources(sources: BookSource[]): Promise<BookSource[]> {
    return AggregateSourceExpander.expand(sources, SourceRuntime.fetchAdapter);
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    return SourceRuntime.adapter.searchBooks(source, keyword, page);
  }

  static async getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    return SourceRuntime.adapter.getBookInfo(source, bookUrl, variables);
  }

  static async getBookToc(source: BookSource, tocUrl: string, variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    return SourceRuntime.adapter.getBookToc(source, tocUrl, variables, bookName);
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    return SourceRuntime.adapter.getAudioUrl(source, chapterUrl);
  }

  static async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    return SourceRuntime.adapter.getTextContent(source, chapterUrl, nextChapterUrl);
  }

  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    return SourceRuntime.adapter.getExploreBooks(source);
  }

  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    return SourceRuntime.adapter.getHomeBlocks(source);
  }
}
