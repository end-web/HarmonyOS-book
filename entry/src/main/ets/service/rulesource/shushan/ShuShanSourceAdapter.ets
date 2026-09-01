import { BookInfo, BookSource, SearchResult, TocItem } from '../../../model/BookSource';
import { LocalRuleContentResult } from '../LocalRuleRuntimeTypes';
import { LocalRuleStageExtractor } from '../LocalRuleStageExtractor';
import {
  ShuShanApiClient,
  ShuShanCatalogItemDto,
  ShuShanContentResponseDto,
  ShuShanDetailDto,
  ShuShanSearchItemDto,
  ShuShanSearchResponseDto
} from './ShuShanApiClient';
import {
  ShuShanRoute,
  ShuShanRouteKind,
  ShuShanSourceIdentity
} from './ShuShanSourceIdentity';

class ShuShanMappedSearchResult implements SearchResult {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  contentType: 'audio' | 'text' = 'text';
  completed: boolean | undefined = undefined;
  lastChapter: string = '';
  wordCount: string = '';
  sourceName: string = '';
  sourceUrl: string = '';
  variables: Record<string, string> = {};
}

class ShuShanMappedBookInfo implements BookInfo {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  completed: boolean | undefined = undefined;
  wordCount: string = '';
  lastChapter: string = '';
  tocUrl: string = '';
  variables: Record<string, string> = {};
}

class ShuShanMappedTocItem implements TocItem {
  name: string = '';
  url: string = '';
  isVip: boolean = false;
  isPay: boolean = false;
  isVolume: boolean = false;
  updateTime: string = '';
  duration: number = 0;
  variables: Record<string, string> = {};
}

class ShuShanSearchGroup {
  items: ShuShanSearchItemDto[] = [];
  errorMessage: string = '';
}

/** 把书山原生协议映射到本地规则源的统一数据契约。 */
export class ShuShanSourceAdapter {
  static async search(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    return ShuShanSourceAdapter.searchInternal(source, keyword, page, false);
  }

  static async searchForHealthCheck(source: BookSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    return ShuShanSourceAdapter.searchInternal(source, keyword, page, true);
  }

  private static async searchInternal(source: BookSource, keyword: string, page: number,
    strict: boolean): Promise<SearchResult[]> {
    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) return [];
    const requestKeyword = strict ? ShuShanSourceAdapter.healthKeyword(cleanKeyword) : cleanKeyword;

    const tasks: Promise<ShuShanSearchGroup>[] = [];
    if (!strict && cleanKeyword.includes('@')) {
      tasks.push(ShuShanSourceAdapter.searchMode('', requestKeyword, page));
    } else {
      tasks.push(ShuShanSourceAdapter.searchMode('novel', requestKeyword, page));
      tasks.push(ShuShanSourceAdapter.searchMode('audio', requestKeyword, page));
    }
    const groups: ShuShanSearchGroup[] = await Promise.all<ShuShanSearchGroup>(tasks);
    const output: SearchResult[] = [];
    const errors: string[] = [];
    const seen = new Set<string>();
    for (const group of groups) {
      if (group.errorMessage.length > 0 && !errors.includes(group.errorMessage)) {
        errors.push(group.errorMessage);
      }
      for (const item of group.items) {
        const mapped = ShuShanSourceAdapter.mapSearchItem(source, item);
        if (mapped === undefined || seen.has(mapped.bookUrl)) continue;
        seen.add(mapped.bookUrl);
        output.push(mapped);
      }
    }
    if ((strict || output.length === 0) && errors.length > 0) throw new Error(errors.join('；'));
    return output;
  }

  static async getBookInfo(bookUrl: string): Promise<BookInfo | null> {
    const route = ShuShanRoute.parse(bookUrl);
    if (route.kind !== ShuShanRouteKind.BOOK) return null;
    const response = await ShuShanApiClient.detail(route);
    const detail = response.detail;
    const tab = detail.tab.trim() || route.tab;
    const provider = detail.source.trim() || route.provider;
    const providerBookUrl = detail.bookUrl.trim() || route.bookUrl;
    const bookId = detail.bookId.trim();
    const toneId = ShuShanSourceAdapter.defaultToneId(provider, tab, '');
    const info = new ShuShanMappedBookInfo();
    info.name = detail.title.trim() || route.title;
    info.author = detail.author;
    info.coverUrl = detail.cover;
    info.intro = ShuShanSourceAdapter.normalizedIntro(detail.desc);
    info.kind = ShuShanSourceAdapter.detailKind(detail, provider);
    info.completed = ShuShanSourceAdapter.isCompleted(detail.tags);
    info.wordCount = detail.wordCount;
    info.lastChapter = detail.latestChapterTitle;
    info.tocUrl = ShuShanRoute.catalog(
      tab, provider, providerBookUrl, bookId, info.name, toneId);
    info.variables = ShuShanSourceAdapter.routeVariables(
      tab, provider, providerBookUrl, bookId, '', toneId);
    return info;
  }

  static async getBookToc(tocUrl: string): Promise<TocItem[]> {
    const route = ShuShanRoute.parse(tocUrl);
    if (route.kind !== ShuShanRouteKind.CATALOG) return [];
    const response = await ShuShanApiClient.catalog(route);
    const output: TocItem[] = [];
    const seen = new Set<string>();
    for (const item of response.items) {
      const mapped = ShuShanSourceAdapter.mapCatalogItem(route, item);
      if (mapped === undefined || seen.has(mapped.url)) continue;
      seen.add(mapped.url);
      output.push(mapped);
    }
    return output;
  }

  static async resolveContent(chapterUrl: string): Promise<LocalRuleContentResult> {
    const route = ShuShanRoute.parse(chapterUrl);
    if (route.kind !== ShuShanRouteKind.CHAPTER) {
      throw new Error('书山聚合章节路由无效');
    }
    const response = await ShuShanApiClient.content(route);
    return ShuShanSourceAdapter.mapContent(route, response);
  }

  static async getContent(chapterUrl: string): Promise<string> {
    const result = await ShuShanSourceAdapter.resolveContent(chapterUrl);
    if (result.content.length === 0) throw new Error('书山聚合正文为空');
    return result.content;
  }

  static async getAudioUrl(chapterUrl: string): Promise<string> {
    const result = await ShuShanSourceAdapter.resolveContent(chapterUrl);
    if (result.audioUrl.length === 0) throw new Error('书山聚合音频地址为空');
    return result.audioUrl;
  }

  private static async searchMode(mode: string, keyword: string,
    page: number): Promise<ShuShanSearchGroup> {
    const group = new ShuShanSearchGroup();
    try {
      const response: ShuShanSearchResponseDto = await ShuShanApiClient.search(mode, keyword, page);
      group.items = ShuShanSourceAdapter.prioritizeDirectAudio(response.items);
    } catch (error) {
      const label = mode === 'audio' ? '听书' : (mode === 'novel' ? '小说' : '指定模式');
      group.errorMessage = `${label}搜索失败：${ShuShanSourceAdapter.errorMessage(error as Object)}`;
      console.warn(`[ShuShanSourceAdapter] ${mode || '指定模式'} search failed: ${group.errorMessage}`);
    }
    return group;
  }

  private static healthKeyword(keyword: string): string {
    const marker = keyword.lastIndexOf('@');
    if (marker <= 0) return keyword;
    const plainKeyword = keyword.substring(0, marker).trim();
    return plainKeyword.length > 0 ? plainKeyword : keyword;
  }

  static mapSearchItem(source: BookSource,
    item: ShuShanSearchItemDto): SearchResult | undefined {
    const title = item.title.trim();
    const provider = item.source.trim();
    const providerBookUrl = item.bookUrl.trim();
    const tab = item.tab.trim() || 'novel';
    if (title.length === 0 || provider.length === 0 || providerBookUrl.length === 0) return undefined;
    const result = new ShuShanMappedSearchResult();
    result.name = title;
    result.author = item.author;
    result.coverUrl = item.cover;
    result.bookUrl = ShuShanRoute.book(tab, provider, providerBookUrl, title);
    result.intro = ShuShanSourceAdapter.normalizedIntro(item.desc);
    result.kind = ShuShanSourceAdapter.searchKind(item);
    result.contentType = ShuShanSourceIdentity.contentType(tab);
    result.completed = ShuShanSourceAdapter.isCompleted(item.tags);
    result.lastChapter = item.latestChapterTitle;
    result.wordCount = item.wordCount;
    result.sourceName = source.bookSourceName;
    result.sourceUrl = source.bookSourceUrl;
    result.variables = ShuShanSourceAdapter.routeVariables(
      tab, provider, providerBookUrl, '', '', ShuShanSourceAdapter.defaultToneId(provider, tab, ''));
    return result;
  }

  static mapCatalogItem(route: ShuShanRoute,
    item: ShuShanCatalogItemDto): TocItem | undefined {
    const chapterId = item.chapterId.trim();
    const providerChapterUrl = item.url.trim();
    if (item.isVolume || (providerChapterUrl.length === 0 && chapterId.length === 0)) return undefined;
    const chapterRouteValue = providerChapterUrl.length > 0
      ? providerChapterUrl : `cid=${encodeURIComponent(chapterId)}`;
    const mapped = new ShuShanMappedTocItem();
    mapped.name = item.title.trim() || `第 ${chapterId || '1'} 章`;
    mapped.url = ShuShanRoute.chapter(route.tab, route.provider, route.bookUrl,
      route.bookId, route.title, chapterRouteValue, chapterId, route.toneId);
    mapped.isPay = item.isPay;
    mapped.isVip = item.isVip || item.isPay;
    mapped.updateTime = item.tag;
    mapped.variables = ShuShanSourceAdapter.routeVariables(route.tab, route.provider,
      route.bookUrl, route.bookId, chapterRouteValue, route.toneId);
    return mapped;
  }

  private static mapContent(route: ShuShanRoute,
    response: ShuShanContentResponseDto): LocalRuleContentResult {
    const result = new LocalRuleContentResult();
    const noHeaders: Record<string, string> = {};
    result.requestHeaders = noHeaders;
    result.title = response.title.trim();
    if (ShuShanSourceIdentity.contentType(route.tab) === 'audio') {
      const audioUrl = response.audioUrl.trim() || response.content.trim();
      if (!ShuShanApiClient.isHttpMediaUrl(audioUrl)) {
        throw new Error('书山聚合返回了无效音频地址');
      }
      result.audioUrl = audioUrl;
      return result;
    }

    let content = response.content.trim();
    if (content.includes('<') && content.includes('>')) {
      content = LocalRuleStageExtractor.stripHtml(content);
    }
    if (response.notice.trim().length > 0) content += `\n${response.notice.trim()}`;
    if (response.sayBody.trim().length > 0) {
      content += `\n【作者有话说】\n${response.sayBody.trim()}`;
    }
    result.content = content.trim();
    if (result.content.length === 0) throw new Error('书山聚合正文为空');
    return result;
  }

  private static searchKind(item: ShuShanSearchItemDto): string {
    const parts: string[] = [];
    ShuShanSourceAdapter.appendPart(parts, item.source);
    ShuShanSourceAdapter.appendPart(parts, item.tags);
    return parts.join(' · ');
  }

  private static prioritizeDirectAudio(items: ShuShanSearchItemDto[]): ShuShanSearchItemDto[] {
    const direct: ShuShanSearchItemDto[] = [];
    const remaining: ShuShanSearchItemDto[] = [];
    for (const item of items) {
      const provider = item.source.trim();
      if (provider === '番茄听书' || provider === '番茄畅听' || provider === '书旗听书') {
        direct.push(item);
      } else {
        remaining.push(item);
      }
    }
    direct.push(...remaining);
    return direct;
  }

  private static detailKind(detail: ShuShanDetailDto, provider: string): string {
    const parts: string[] = [];
    ShuShanSourceAdapter.appendPart(parts, provider);
    ShuShanSourceAdapter.appendPart(parts, detail.tags);
    return parts.join(' · ');
  }

  private static normalizedIntro(value: string): string {
    const clean = value.trim();
    if (clean.includes('<') || clean.includes('&nbsp;') || clean.includes('&#')) {
      return LocalRuleStageExtractor.stripHtml(clean);
    }
    return clean;
  }

  private static defaultToneId(provider: string, tab: string, fallback: string): string {
    const cleanFallback = fallback.trim();
    if (cleanFallback.length > 0) return cleanFallback;
    if (ShuShanSourceIdentity.contentType(tab) !== 'audio') return '';
    if (provider === '书旗听书') return 'yifei';
    if (provider === '番茄听书' || provider === '番茄畅听') return '1';
    return '';
  }

  private static routeVariables(tab: string, provider: string, bookUrl: string,
    bookId: string, chapterUrl: string, toneId: string): Record<string, string> {
    const variables: Record<string, string> = {};
    variables['shuShanTab'] = tab;
    variables['shuShanProvider'] = provider;
    variables['shuShanBookUrl'] = bookUrl;
    variables['shuShanBookId'] = bookId;
    variables['shuShanChapterUrl'] = chapterUrl;
    variables['shuShanToneId'] = toneId;
    return variables;
  }

  private static appendPart(parts: string[], value: string): void {
    const clean = value.trim();
    if (clean.length > 0 && !parts.includes(clean)) parts.push(clean);
  }

  private static isCompleted(value: string): boolean | undefined {
    const clean = value.trim().toLowerCase();
    if (clean.length === 0) return undefined;
    if (clean.includes('完结') || clean.includes('完本') || clean === 'completed' || clean === 'finished') {
      return true;
    }
    if (clean.includes('连载')) return false;
    return undefined;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '请求失败';
    return String(error || '请求失败');
  }
}
