import { BookInfo, BookSource, SearchResult, TocItem } from '../../../model/BookSource';
import { LocalRuleContentResult } from '../LocalRuleRuntimeTypes';
import { LocalRuleStageExtractor } from '../LocalRuleStageExtractor';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleExploreResult } from '../../../model/LocalRulePanel';
import { LocalRuleHttpClient } from '../LocalRuleHttpClient';
import { GuangYuAuthService } from './GuangYuAuthService';
import { GuangYuSettings } from './GuangYuSettings';
import {
  GuangYuApiClient,
  GuangYuCatalogItemDto,
  GuangYuContentResponseDto,
  GuangYuDetailDto,
  GuangYuSearchItemDto,
  GuangYuSearchResponseDto
} from './GuangYuApiClient';
import {
  GuangYuRoute,
  GuangYuRouteKind,
  GuangYuSourceIdentity
} from './GuangYuSourceIdentity';

const NOVEL_TAB: string = '小说';
const AUDIO_TAB: string = '听书';

class GuangYuMappedSearchResult implements SearchResult {
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

class GuangYuMappedBookInfo implements BookInfo {
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

class GuangYuMappedTocItem implements TocItem {
  name: string = '';
  url: string = '';
  isVip: boolean = false;
  isPay: boolean = false;
  isVolume: boolean = false;
  updateTime: string = '';
  duration: number = 0;
  variables: Record<string, string> = {};
}

class GuangYuSearchTabResult {
  items: GuangYuSearchItemDto[] = [];
  errorMessage: string = '';
}

/** 把光遇专用 API 映射到本地规则源统一契约。 */
export class GuangYuSourceAdapter {
  static async search(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    return GuangYuSourceAdapter.searchInternal(source, keyword, page, false);
  }

  static async searchForHealthCheck(source: BookSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    return GuangYuSourceAdapter.searchInternal(source, keyword, page, true);
  }

  private static async searchInternal(source: BookSource, keyword: string, page: number,
    strict: boolean): Promise<SearchResult[]> {
    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) return [];

    const settings = await GuangYuSettings.load();
    let tab = settings.mode === AUDIO_TAB ? AUDIO_TAB : NOVEL_TAB;
    let title = cleanKeyword;
    let provider = '';
    const shortcut = cleanKeyword.match(new RegExp('^([xt]):(.+)$', 'i'));
    if (shortcut !== null) {
      tab = shortcut[1].toLowerCase() === 't' ? AUDIO_TAB : NOVEL_TAB;
      title = shortcut[2];
    }
    const separator = title.lastIndexOf('@');
    if (separator > 0 && separator < title.length - 1) {
      provider = title.substring(separator + 1).trim();
      title = title.substring(0, separator).trim();
    }
    const tasks: Promise<GuangYuSearchTabResult>[] = [];
    tasks.push(GuangYuSourceAdapter.searchTab(tab, title, page, provider));
    if (strict && shortcut === null && separator < 0) {
      tasks.push(GuangYuSourceAdapter.searchTab(tab === NOVEL_TAB ? AUDIO_TAB : NOVEL_TAB, title, page));
    }
    const groups: GuangYuSearchTabResult[] = await Promise.all<GuangYuSearchTabResult>(tasks);
    const output: SearchResult[] = [];
    const errors: string[] = [];
    const seen = new Set<string>();
    for (const group of groups) {
      if (group.errorMessage.length > 0 && !errors.includes(group.errorMessage)) {
        errors.push(group.errorMessage);
      }
      for (const item of group.items) {
        const mapped = GuangYuSourceAdapter.mapSearchItem(source, item);
        if (mapped === undefined || seen.has(mapped.bookUrl)) continue;
        seen.add(mapped.bookUrl);
        output.push(mapped);
      }
    }
    if ((strict || output.length === 0) && errors.length > 0) {
      throw new Error(errors.join('；'));
    }
    return output;
  }

  static async explore(source: LocalRuleSource, address: string, page: number,
    variables: Record<string, string>, resultLimit: number): Promise<LocalRuleExploreResult> {
    await GuangYuAuthService.syncScriptSession();
    // 服务端发现列表仍会返回 HTTP 地址；仅将光遇自己的线路升级为 HTTPS。
    const secureAddress = address.replace(new RegExp('^http://(v[1-7]\\.qingtian618\\.com)(?=/|$)', 'i'), 'https://$1');
    const response = await LocalRuleHttpClient.fetch(source, secureAddress, variables, '', page);
    if (!response.ok) throw new Error(response.errorMessage || '光遇发现请求失败');
    const data = GuangYuApiClient.parseSearchResponse(response.body);
    const result = new LocalRuleExploreResult();
    const seen = new Set<string>();
    for (const item of data.items) {
      const mapped = GuangYuSourceAdapter.mapSearchItem(source, item);
      if (mapped === undefined || seen.has(mapped.bookUrl)) continue;
      seen.add(mapped.bookUrl);
      result.books.push(mapped);
      if (result.books.length >= resultLimit) break;
    }
    if (data.items.length > 0 && address.includes('{{page')) result.nextUrl = address;
    return result;
  }

  static async getBookInfo(bookUrl: string): Promise<BookInfo | null> {
    const route = GuangYuRoute.parse(bookUrl);
    if (route.kind !== GuangYuRouteKind.BOOK) return null;
    const response = await GuangYuApiClient.detail(route);
    const detail = response.detail;
    const info = new GuangYuMappedBookInfo();
    const tab = detail.tab || route.tab;
    const provider = detail.source || route.provider;
    const bookId = detail.bookId || route.bookId;
    const toneId = GuangYuSourceAdapter.detailToneId(route.toneId);
    info.name = detail.bookName || detail.aliasName;
    info.author = detail.author;
    info.coverUrl = detail.thumbUrl;
    info.intro = GuangYuSourceAdapter.detailIntro(detail, tab);
    info.kind = GuangYuSourceAdapter.detailKind(detail, provider);
    info.completed = GuangYuSourceAdapter.isCompleted(detail.status);
    info.wordCount = detail.wordNumber;
    info.lastChapter = GuangYuSourceAdapter.prefixedLastChapter(provider, detail.lastChapterTitle);
    info.tocUrl = GuangYuRoute.catalog(tab, provider, bookId, toneId,
      detail.catalogUrl || detail.tocUrl || route.upstreamUrl);
    info.variables = GuangYuSourceAdapter.routeVariables(tab, provider, bookId, '', toneId);
    return info;
  }

  static async getBookToc(tocUrl: string): Promise<TocItem[]> {
    const route = GuangYuRoute.parse(tocUrl);
    if (route.kind !== GuangYuRouteKind.CATALOG) return [];
    const response = await GuangYuApiClient.catalog(route);
    const settings = await GuangYuSettings.load();
    const output: TocItem[] = [];
    const seen = new Set<string>();
    for (const item of response.items) {
      const mapped = GuangYuSourceAdapter.mapCatalogItem(route, item);
      if (mapped === undefined || seen.has(mapped.url)) continue;
      if (settings.showSource) mapped.name = `[${item.source || route.provider}] ${mapped.name}`;
      seen.add(mapped.url);
      output.push(mapped);
    }
    return output;
  }

  static async resolveContent(chapterUrl: string, toneId: string = ''): Promise<LocalRuleContentResult> {
    const route = GuangYuRoute.parse(chapterUrl);
    if (route.kind !== GuangYuRouteKind.CHAPTER) {
      throw new Error('光遇聚合章节路由无效');
    }
    if (toneId.trim().length > 0) route.toneId = toneId.trim().substring(0, 128);
    const response = await GuangYuApiClient.content(route);
    return GuangYuSourceAdapter.mapContent(route, response);
  }

  static async getContent(chapterUrl: string): Promise<string> {
    const result = await GuangYuSourceAdapter.resolveContent(chapterUrl);
    if (result.content.length === 0) throw new Error('光遇聚合正文为空');
    return result.content;
  }

  static async getAudioUrl(chapterUrl: string, toneId: string = ''): Promise<string> {
    const result = await GuangYuSourceAdapter.resolveContent(chapterUrl, toneId);
    if (result.audioUrl.length === 0) throw new Error('光遇聚合音频地址为空');
    return result.audioUrl;
  }

  static isNonRetryableHealthError(error: Object): boolean {
    return GuangYuApiClient.isBusinessError(error);
  }

  private static async searchTab(tab: string, keyword: string,
    page: number, provider: string = ''): Promise<GuangYuSearchTabResult> {
    const result = new GuangYuSearchTabResult();
    try {
      const response: GuangYuSearchResponseDto = await GuangYuApiClient.search(tab, keyword, page, provider);
      result.items = response.items;
    } catch (error) {
      result.errorMessage = `${tab}搜索失败：${GuangYuSourceAdapter.errorMessage(error as Object)}`;
      console.warn(`[GuangYuSourceAdapter] ${tab} search failed: ${result.errorMessage}`);
    }
    return result;
  }

  private static mapSearchItem(source: BookSource,
    item: GuangYuSearchItemDto): GuangYuMappedSearchResult | undefined {
    const bookId = item.bookId.trim();
    const provider = item.source.trim();
    const tab = item.tab.trim() || NOVEL_TAB;
    if (!item.bookName.trim() || !bookId || !provider || GuangYuSourceAdapter.isNoticeItem(bookId, provider)) {
      return undefined;
    }
    const result = new GuangYuMappedSearchResult();
    result.name = item.bookName;
    result.author = item.author;
    result.coverUrl = item.thumbUrl;
    result.bookUrl = GuangYuRoute.book(tab, provider, bookId, item.tocUrl || item.detailUrl || item.bookUrl);
    result.intro = item.abstract;
    result.kind = GuangYuSourceAdapter.searchKind(item);
    result.contentType = GuangYuSourceIdentity.contentType(tab);
    result.completed = GuangYuSourceAdapter.isCompleted(item.status);
    result.lastChapter = GuangYuSourceAdapter.prefixedLastChapter(provider, item.lastChapterTitle);
    result.wordCount = item.wordNumber;
    result.sourceName = source.bookSourceName;
    result.sourceUrl = source.bookSourceUrl;
    result.variables = GuangYuSourceAdapter.routeVariables(tab, provider, bookId, '', '4');
    return result;
  }

  private static mapCatalogItem(route: GuangYuRoute,
    item: GuangYuCatalogItemDto): GuangYuMappedTocItem | undefined {
    const itemId = item.itemId.trim();
    if (itemId.length === 0) return undefined;
    const tab = item.tab.trim() || route.tab;
    const provider = item.source.trim() || route.provider;
    const mapped = new GuangYuMappedTocItem();
    mapped.name = item.title.trim() || `第 ${itemId} 章`;
    mapped.url = GuangYuRoute.chapter(tab, provider, route.bookId, itemId, route.toneId, item.contentUrl || item.url);
    mapped.isPay = item.isPay;
    mapped.isVip = item.isPay || GuangYuSourceAdapter.isVipProvider(provider);
    mapped.isVolume = item.isVolume;
    mapped.updateTime = item.firstPassTime;
    mapped.variables = GuangYuSourceAdapter.routeVariables(
      tab, provider, route.bookId, itemId, route.toneId);
    return mapped;
  }

  private static mapContent(route: GuangYuRoute,
    response: GuangYuContentResponseDto): LocalRuleContentResult {
    const result = new LocalRuleContentResult();
    const noHeaders: Record<string, string> = {};
    result.requestHeaders = noHeaders;
    result.title = response.title.trim();
    const content = response.content.trim();
    if (content.length === 0) {
      throw new Error(GuangYuSourceAdapter.contentErrorMessage(response));
    }
    if (GuangYuSourceIdentity.contentType(route.tab) === 'audio') {
      if (!GuangYuApiClient.isHttpMediaUrl(content)) {
        throw new Error('光遇聚合返回了无效音频地址');
      }
      result.audioUrl = content;
      return result;
    }
    result.content = content.includes('<') && content.includes('>')
      ? LocalRuleStageExtractor.stripHtml(content) : content;
    if (result.content.length === 0) throw new Error('光遇聚合正文为空');
    return result;
  }

  private static searchKind(item: GuangYuSearchItemDto): string {
    const parts: string[] = [];
    GuangYuSourceAdapter.appendPart(parts, item.source);
    GuangYuSourceAdapter.appendPart(parts, item.status);
    GuangYuSourceAdapter.appendPart(parts, item.score);
    GuangYuSourceAdapter.appendPart(parts, item.tags || item.category);
    return parts.join(' · ');
  }

  private static detailKind(detail: GuangYuDetailDto, provider: string): string {
    const parts: string[] = [];
    GuangYuSourceAdapter.appendPart(parts, provider);
    GuangYuSourceAdapter.appendPart(parts, detail.status);
    GuangYuSourceAdapter.appendPart(parts, detail.score);
    GuangYuSourceAdapter.appendPart(parts, detail.tags || detail.category);
    return parts.join(' · ');
  }

  private static detailIntro(detail: GuangYuDetailDto, tab: string): string {
    const intro = detail.abstract.trim();
    const tts = detail.bookTts.trim();
    if (GuangYuSourceIdentity.contentType(tab) !== 'audio' || tts.length === 0) return intro;
    return intro.length > 0 ? `${intro}\n\n${tts}` : tts;
  }

  static detailToneId(fallback: string): string {
    const cleanFallback = fallback.trim();
    return cleanFallback.length > 0 ? cleanFallback : '4';
  }

  static contentErrorMessage(response: GuangYuContentResponseDto): string {
    const message = response.message.trim();
    return message.length > 0 ? message : '光遇聚合内容为空';
  }

  private static appendPart(parts: string[], value: string): void {
    const clean = value.trim();
    if (clean.length > 0 && !parts.includes(clean)) parts.push(clean);
  }

  private static prefixedLastChapter(provider: string, title: string): string {
    const cleanProvider = provider.trim();
    const cleanTitle = title.trim();
    if (cleanTitle.length === 0) return '';
    return cleanProvider.length > 0 ? `${cleanProvider} ${cleanTitle}` : cleanTitle;
  }

  private static routeVariables(tab: string, provider: string, bookId: string,
    itemId: string, toneId: string): Record<string, string> {
    const variables: Record<string, string> = {};
    variables['guangYuTab'] = tab;
    variables['guangYuProvider'] = provider;
    variables['guangYuBookId'] = bookId;
    variables['guangYuItemId'] = itemId;
    variables['guangYuToneId'] = toneId.trim() || '4';
    return variables;
  }

  private static isCompleted(status: string): boolean | undefined {
    const clean = status.trim().toLowerCase();
    if (clean.length === 0) return undefined;
    if (clean === '1' || clean === 'true' || clean === 'completed' || clean === 'finished' ||
      clean.includes('完结') || clean.includes('完本')) return true;
    if (clean.includes('连载') || clean === '0' || clean === 'false') return false;
    return undefined;
  }

  private static isNoticeItem(bookId: string, provider: string): boolean {
    const normalizedBookId = bookId.trim().toLowerCase();
    const normalizedProvider = provider.trim().toLowerCase();
    return normalizedBookId === 'vip' || normalizedBookId === 'svip' ||
      normalizedProvider === 'vip' || normalizedProvider === 'svip';
  }

  private static isVipProvider(provider: string): boolean {
    const normalized = provider.trim().toLowerCase();
    return normalized.startsWith('vip_') || normalized.startsWith('svip_');
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '请求失败';
    return String(error || '请求失败');
  }
}
