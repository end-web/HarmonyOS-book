/**
 * BuiltInDispatcher - 把 IBuiltInSource 适配成 BookSourceService 的接口形态
 */

import { BookSource, BookInfo, SearchResult, TocItem, HomeBlockSection } from '../../model/BookSource';
import { BuiltInBook, BuiltInEpisode, IBuiltInSource } from './IBuiltInSource';
import { BuiltInSourceRegistry } from './BuiltInSourceRegistry';

const TAG = 'BuiltInDispatcher';

class SR implements SearchResult {
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  lastChapter: string = '';
  sourceName: string;
  sourceUrl: string;

  constructor(name: string, author: string, coverUrl: string, bookUrl: string, intro: string, kind: string, sourceName: string, sourceUrl: string) {
    this.name = name;
    this.author = author;
    this.coverUrl = coverUrl;
    this.bookUrl = bookUrl;
    this.intro = intro;
    this.kind = kind;
    this.sourceName = sourceName;
    this.sourceUrl = sourceUrl;
  }
}

class BI implements BookInfo {
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  kind: string;
  wordCount: string = '';
  lastChapter: string = '';
  tocUrl: string;

  constructor(name: string, author: string, coverUrl: string, intro: string, kind: string, tocUrl: string) {
    this.name = name;
    this.author = author;
    this.coverUrl = coverUrl;
    this.intro = intro;
    this.kind = kind;
    this.tocUrl = tocUrl;
  }
}

class TI implements TocItem {
  name: string;
  url: string;
  isVip: boolean;

  constructor(name: string, url: string, isVip: boolean = false) {
    this.name = name;
    this.url = url;
    this.isVip = isVip;
  }
}

class HBS implements HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;

  constructor(title: string, books: SearchResult[], moreUrl: string, layout: string, sourceName: string, sourceUrl: string) {
    this.title = title;
    this.books = books;
    this.moreUrl = moreUrl;
    this.layout = layout;
    this.sourceName = sourceName;
    this.sourceUrl = sourceUrl;
  }
}

function bookToSearchResult(book: BuiltInBook, source: IBuiltInSource, sourceUrl: string): SearchResult {
  BuiltInSourceRegistry.cacheBookMeta(book);
  return new SR(book.title, book.author, book.coverUrl, book.bookUrl, book.intro, book.status, source.name, sourceUrl);
}

export class BuiltInDispatcher {
  static async search(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin || !plugin.searchable) return [];
    try {
      const r = await plugin.search(keyword, page);
      const out: SearchResult[] = [];
      for (const b of r.books) out.push(bookToSearchResult(b, plugin, source.bookSourceUrl));
      return out;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] search ${plugin.name} error: ${msg}`);
      return [];
    }
  }

  static async getBookInfo(source: BookSource, bookUrl: string): Promise<BookInfo | null> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) return null;
    try {
      const detail = await plugin.getBookDetail(bookUrl, false, false);
      const meta = BuiltInSourceRegistry.getBookMeta(bookUrl);
      const name = meta ? meta.title : '';
      const author = meta ? meta.author : '';
      const cover = meta ? meta.coverUrl : '';
      const intro = detail.intro || (meta ? meta.intro : '');
      const kind = meta ? meta.status : '';
      return new BI(name, author, cover, intro, kind, bookUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getBookInfo ${plugin.name} error: ${msg}`);
      return null;
    }
  }

  static async getBookToc(source: BookSource, tocUrl: string): Promise<TocItem[]> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) return [];
    try {
      const detail = await plugin.getBookDetail(tocUrl, true, true);
      const out: TocItem[] = [];
      for (const ep of detail.episodes) out.push(new TI(ep.title, ep.url, !ep.isFree));
      return out;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getBookToc ${plugin.name} error: ${msg}`);
      return [];
    }
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) return chapterUrl;
    try {
      const audio = await plugin.getAudioUrl(chapterUrl);
      return audio || chapterUrl;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getAudioUrl ${plugin.name} error: ${msg}`);
      return chapterUrl;
    }
  }

  static getAudioHeaders(source: BookSource, audioUrl: string): Record<string, string> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) return {};
    try {
      return plugin.getAudioHeaders(audioUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getAudioHeaders ${plugin.name} error: ${msg}`);
      return {};
    }
  }

  static async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin || !plugin.getTextContent) return '';
    try {
      return await plugin.getTextContent(chapterUrl, nextChapterUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getTextContent ${plugin.name} error: ${msg}`);
      return '';
    }
  }

  /** 发现页：取每个内置源第一个分类 tab 的前 N 本 */
  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) return [];
    try {
      const menus = await plugin.getCategoryMenus();
      if (menus.length === 0 || menus[0].tabs.length === 0) return [];
      const firstTabUrl = menus[0].tabs[0].url;
      const cat = await plugin.getCategoryList(firstTabUrl);
      const out: SearchResult[] = [];
      const limit = Math.min(12, cat.books.length);
      for (let i = 0; i < limit; i++) {
        out.push(bookToSearchResult(cat.books[i], plugin, source.bookSourceUrl));
      }
      return out;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getExploreBooks ${plugin.name} error: ${msg}`);
      return [];
    }
  }

  /** 首页推荐板块（多个 section） */
  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    const plugin = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl);
    if (!plugin) {
      console.warn(`[${TAG}] getHomeBlocks: no plugin for ${source.bookSourceUrl}`);
      return [];
    }
    try {
      const blocks = await plugin.getHomeBlocks();
      const out: HomeBlockSection[] = [];
      for (const b of blocks) {
        const books: SearchResult[] = [];
        for (const bk of b.books) {
          books.push(bookToSearchResult(bk, plugin, source.bookSourceUrl));
        }
        if (books.length === 0) continue;
        out.push(new HBS(b.title, books, b.moreUrl, b.layout, plugin.name, source.bookSourceUrl));
      }
      return out;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getHomeBlocks ${plugin.name} error: ${msg}`);
      return [];
    }
  }
}
