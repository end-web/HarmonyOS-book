import { BookInfo, SearchResult, TocItem } from '../../model/BookSource';
import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { LocalRuleHttpClient } from './LocalRuleHttpClient';
import {
  LocalRuleContentResult,
  LocalRuleDocument,
  LocalRuleExecutionLimits,
  LocalRuleFetchResult,
  LocalRuleRequestPlan
} from './LocalRuleRuntimeTypes';
import { LocalRuleStageExtractor } from './LocalRuleStageExtractor';
import { LocalRuleScriptRuntime } from './LocalRuleScriptRuntime';
import { LocalRuleUrlAnalyzer } from './LocalRuleUrlAnalyzer';
import { TingYouSourceAdapter } from './tingyou/TingYouSourceAdapter';
import { CoverPrefetcher } from '../CoverPrefetcher';

class LocalRuleSearchResult implements SearchResult {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  completed: boolean | undefined = undefined;
  lastChapter: string = '';
  wordCount: string = '';
  sourceName: string = '';
  sourceUrl: string = '';
  variables: Record<string, string> = {};
}

class LocalRuleBookInfo implements BookInfo {
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

class LocalRuleTocItem implements TocItem {
  name: string = '';
  url: string = '';
  isVip: boolean = false;
  isPay: boolean = false;
  isVolume: boolean = false;
  updateTime: string = '';
  duration: number = 0;
  variables: Record<string, string> = {};
}

/** 本地规则源旁路 Dispatcher；它从不调用或修改 BuiltInDispatcher。 */
export class LocalRuleDispatcher {
  static async search(source: LocalRuleSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    if (!source.isSearchEnabled()) return [];
    try {
      return await LocalRuleDispatcher.searchStrict(source, keyword, page);
    } catch (error) {
      LocalRuleDispatcher.logFailure(source, 'search', error as Object);
      return [];
    }
  }

  /** 健康检查需要绕过启用开关，并保留网络或规则异常供上层判定。 */
  static async searchForHealthCheck(source: LocalRuleSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    return LocalRuleDispatcher.searchStrict(source, keyword, page);
  }

  static async testSearch(source: LocalRuleSource, keyword: string = '测试'): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const startedAt = Date.now();
    if (!source.canExecute()) {
      health.status = LocalRuleSourceStatus.UNSUPPORTED;
      health.message = source.validationMessage || '书源包含当前版本不支持的能力';
      return health;
    }
    try {
      const results = await LocalRuleDispatcher.searchStrict(source, keyword, 1);
      health.responseTimeMs = Date.now() - startedAt;
      if (results.length === 0) {
        health.status = LocalRuleSourceStatus.FAILED;
        health.message = '请求成功，但搜索规则没有解析出有效书籍';
      } else {
        health.status = LocalRuleSourceStatus.READY;
        health.message = `搜索正常，共 ${results.length} 条`;
      }
    } catch (error) {
      health.responseTimeMs = Date.now() - startedAt;
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = LocalRuleDispatcher.errorMessage(error as Object);
    }
    return health;
  }

  static async getBookInfo(source: LocalRuleSource, bookUrl: string,
    variables: Record<string, string> = {}): Promise<BookInfo | null> {
    if (!source.canExecute()) return null;
    try {
      await LocalRuleDispatcher.prepareVariables(source, variables, bookUrl);
      const isTingYouBook = TingYouSourceAdapter.canResolveBook(source, bookUrl);
      if (isTingYouBook) {
        try {
          const apiInfo = await TingYouSourceAdapter.getBookInfo(source, bookUrl);
          if (apiInfo !== null) {
            apiInfo.coverUrl = LocalRuleDispatcher.prepareCover(
              source, apiInfo.coverUrl, bookUrl, variables);
            console.info(`[LocalRuleDispatcher] detail ${source.bookSourceName}: ` +
              `api=true, category=${apiInfo.kind}, completed=${String(apiInfo.completed)}, ` +
              `count=${apiInfo.wordCount}`);
            return apiInfo;
          }
        } catch (error) {
          console.warn(`[LocalRuleDispatcher] TingYou API detail failed, fallback to HTML: ` +
            LocalRuleDispatcher.errorMessage(error as Object));
        }
      }
      const fetch = await LocalRuleHttpClient.fetch(source, bookUrl, variables);
      LocalRuleDispatcher.assertFetch(fetch, '详情');
      const responseDocument = LocalRuleStageExtractor.createDocument(fetch.body, fetch.requestUrl);
      let fieldDocument = responseDocument;
      if (source.ruleBookInfo.init.trim()) {
        const initialized = await LocalRuleStageExtractor.extract(responseDocument,
          source.ruleBookInfo.init, source, variables);
        if (initialized) fieldDocument = LocalRuleStageExtractor.createDocument(initialized, fetch.requestUrl);
      }

      const info = new LocalRuleBookInfo();
      info.name = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extractFirst(fieldDocument,
        source.ruleBookInfo.name, source, variables), 120);
      info.author = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.author, source, variables), 120);
      info.coverUrl = await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.coverUrl, source, variables, true);
      info.coverUrl = LocalRuleDispatcher.prepareCover(
        source, info.coverUrl, fetch.requestUrl, variables);
      info.intro = LocalRuleDispatcher.sanitizeIntro(LocalRuleStageExtractor.limit(
        await LocalRuleStageExtractor.extract(fieldDocument,
          source.ruleBookInfo.intro, source, variables), LocalRuleExecutionLimits.MAX_INTRO_CHARS));
      info.kind = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.kind, source, variables), 256);
      const status = await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.status, source, variables);
      if (status.trim()) info.completed = LocalRuleDispatcher.isCompleted(status);
      info.wordCount = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.wordCount, source, variables), 80);
      info.lastChapter = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.lastChapter, source, variables), 256);
      info.tocUrl = await LocalRuleStageExtractor.extract(fieldDocument,
        source.ruleBookInfo.tocUrl, source, variables, true);
      if (!info.tocUrl) info.tocUrl = fetch.requestUrl;
      if (isTingYouBook) LocalRuleDispatcher.normalizeTingYouFallbackInfo(info);
      info.variables = LocalRuleDispatcher.copyVariables(variables);
      info.variables['bookUrl'] = fetch.requestUrl;
      console.info(`[LocalRuleDispatcher] detail ${source.bookSourceName}: ` +
        `responseChars=${fetch.body.length}, name=${info.name.length > 0}, ` +
        `tocUrl=${info.tocUrl}`);
      return info;
    } catch (error) {
      LocalRuleDispatcher.logFailure(source, 'getBookInfo', error as Object);
      return null;
    }
  }

  static async getBookToc(source: LocalRuleSource, tocUrl: string,
    variables: Record<string, string> = {}): Promise<TocItem[]> {
    if (!source.canExecute()) return [];
    try {
      await LocalRuleDispatcher.prepareVariables(source, variables, tocUrl);
      const output: TocItem[] = [];
      const chapterUrls = new Set<string>();
      const pageUrls = new Set<string>();
      let currentUrl = tocUrl;
      let pageCount = 0;
      let responseCharacters = 0;
      while (currentUrl && pageCount < 100 && output.length < LocalRuleExecutionLimits.MAX_TOC_ITEMS) {
        if (pageUrls.has(currentUrl)) break;
        pageUrls.add(currentUrl);
        pageCount++;
        const fetch = await LocalRuleHttpClient.fetch(source, currentUrl, variables);
        LocalRuleDispatcher.assertFetch(fetch, '目录');
        if (responseCharacters + fetch.body.length > LocalRuleExecutionLimits.MAX_STAGE_RESPONSE_CHARS) break;
        responseCharacters += fetch.body.length;
        const document = LocalRuleStageExtractor.createDocument(fetch.body, fetch.requestUrl);
        const elements = await LocalRuleStageExtractor.selectList(document,
          source.ruleToc.chapterList, source, variables);
        for (const element of elements) {
          if (output.length >= LocalRuleExecutionLimits.MAX_TOC_ITEMS) break;
          const itemVariables = LocalRuleDispatcher.copyVariables(variables);
          const item = new LocalRuleTocItem();
          item.name = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.chapterName, source, itemVariables), 256);
          const chapterUrl = await LocalRuleStageExtractor.extract(element,
            source.ruleToc.chapterUrl, source, itemVariables, true);
          if (!chapterUrl || chapterUrls.has(chapterUrl)) continue;
          chapterUrls.add(chapterUrl);
          item.url = chapterUrl;
          itemVariables['chapterUrl'] = chapterUrl;
          itemVariables['tocUrl'] = fetch.requestUrl;
          if (!item.name) item.name = `第 ${output.length + 1} 章`;
          item.isVip = LocalRuleStageExtractor.parseBoolean(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.isVip, source, itemVariables));
          item.isPay = LocalRuleStageExtractor.parseBoolean(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.isPay, source, itemVariables));
          item.isVolume = LocalRuleStageExtractor.parseBoolean(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.isVolume, source, itemVariables));
          item.updateTime = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.updateTime, source, itemVariables), 80);
          item.duration = LocalRuleStageExtractor.parseDuration(await LocalRuleStageExtractor.extract(element,
            source.ruleToc.duration, source, itemVariables));
          item.variables = LocalRuleDispatcher.copyVariables(itemVariables);
          output.push(item);
        }
        const nextUrl = await LocalRuleStageExtractor.extract(document,
          source.ruleToc.nextTocUrl, source, variables, true);
        if (!nextUrl || pageUrls.has(nextUrl)) break;
        currentUrl = nextUrl;
      }
      console.info(`[LocalRuleDispatcher] toc ${source.bookSourceName}: ` +
        `responseChars=${responseCharacters}, pages=${pageCount}, results=${output.length}`);
      return output;
    } catch (error) {
      LocalRuleDispatcher.logFailure(source, 'getBookToc', error as Object);
      return [];
    }
  }

  static async resolveContent(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): Promise<LocalRuleContentResult> {
    const safe = new LocalRuleContentResult();
    if (!source.canExecute()) return safe;
    try {
      if (TingYouSourceAdapter.canResolve(source, chapterUrl)) {
        return await TingYouSourceAdapter.resolveContent(source, chapterUrl);
      }
      await LocalRuleDispatcher.prepareVariables(source, variables, chapterUrl);
      await LocalRuleHttpClient.hydrateCookies(source.bookSourceUrl);
      safe.requestHeaders = LocalRuleDispatcher.getAudioHeaders(source, chapterUrl, variables);
      const direct = LocalRuleDispatcher.resolveDirectAudioRequest(source, chapterUrl, variables);
      if (direct !== undefined) return direct;
      return await LocalRuleDispatcher.resolveContentStrict(source, chapterUrl, variables);
    } catch (error) {
      LocalRuleDispatcher.logFailure(source, 'resolveContent', error as Object);
      return safe;
    }
  }

  static async getContent(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): Promise<string> {
    const result = await LocalRuleDispatcher.resolveContent(source, chapterUrl, variables);
    return result.content;
  }

  static async getAudioUrl(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): Promise<string> {
    const result = await LocalRuleDispatcher.resolveContent(source, chapterUrl, variables);
    return result.audioUrl || chapterUrl;
  }

  /** 明确的本地音频直链无需先作为正文完整下载；返回 undefined 时继续原解析链。 */
  static resolveDirectAudioRequest(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): LocalRuleContentResult | undefined {
    if (!source.isAudio()) return undefined;
    try {
      const plan: LocalRuleRequestPlan = LocalRuleHttpClient.prepareRequest(source, chapterUrl, variables);
      if (plan.method !== 'GET' || plan.body !== undefined ||
        !LocalRuleDispatcher.looksLikeDirectAudioPath(plan.url)) return undefined;
      const result = new LocalRuleContentResult();
      result.audioUrl = plan.url;
      result.requestHeaders = plan.headers;
      return result;
    } catch (_error) {
      return undefined;
    }
  }

  static getAudioHeaders(source: LocalRuleSource, _audioUrl: string,
    variables: Record<string, string> = {}): Record<string, string> {
    try {
      const headers = LocalRuleHttpClient.getSessionHeaders(source, _audioUrl, variables);
      const sourceHost = LocalRuleDispatcher.requestHost(source.bookSourceUrl);
      const audioHost = LocalRuleDispatcher.requestHost(_audioUrl);
      if (sourceHost && sourceHost === audioHost) return headers;
      const safeHeaders: Record<string, string> = {};
      const keys = Object.keys(headers);
      for (const key of keys) {
        const lower = key.toLowerCase();
        if (lower === 'cookie' || lower === 'authorization' || lower === 'proxy-authorization') continue;
        safeHeaders[key] = headers[key] ?? '';
      }
      return safeHeaders;
    } catch (_error) {
      return {};
    }
  }

  private static async searchStrict(source: LocalRuleSource, keyword: string,
    page: number): Promise<SearchResult[]> {
    if (!source.canExecute()) throw new Error(source.validationMessage || '书源不可执行');
    if (!source.searchUrl.trim()) throw new Error('书源没有搜索地址');
    const variables: Record<string, string> = {};
    await LocalRuleDispatcher.prepareVariables(source, variables, source.bookSourceUrl, keyword, page);
    const searchAddress = await LocalRuleScriptRuntime.resolveAddress(
      source.searchUrl, source, variables, keyword, page);
    const fetch = await LocalRuleHttpClient.fetch(source, searchAddress, variables, keyword, page);
    LocalRuleDispatcher.assertFetch(fetch, '搜索');
    const document = LocalRuleStageExtractor.createDocument(fetch.body, fetch.requestUrl);
    const elements = await LocalRuleStageExtractor.selectList(document,
      source.ruleSearch.bookList, source, variables);
    const output: SearchResult[] = [];
    const seen = new Set<string>();
    const maximum = Math.min(elements.length, LocalRuleExecutionLimits.MAX_SEARCH_RESULTS);
    for (let index = 0; index < maximum; index++) {
      const element = elements[index];
      const itemVariables = LocalRuleDispatcher.copyVariables(variables);
      const item = await LocalRuleDispatcher.extractSearchResult(element, source, itemVariables);
      if (!item.name || !item.bookUrl || seen.has(item.bookUrl)) continue;
      seen.add(item.bookUrl);
      output.push(item);
    }
    console.info(`[LocalRuleDispatcher] search ${source.bookSourceName}: ` +
      `responseChars=${fetch.body.length}, elements=${elements.length}, results=${output.length}`);
    return output;
  }

  private static async extractSearchResult(element: LocalRuleDocument, source: LocalRuleSource,
    variables: Record<string, string>): Promise<LocalRuleSearchResult> {
    const item = new LocalRuleSearchResult();
    item.name = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.name, source, variables), 120);
    item.author = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.author, source, variables), 120);
    item.coverUrl = await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.coverUrl, source, variables, true);
    item.coverUrl = LocalRuleDispatcher.prepareCover(
      source, item.coverUrl, element.baseUrl, variables);
    item.bookUrl = await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.bookUrl, source, variables, true);
    item.intro = LocalRuleDispatcher.sanitizeIntro(LocalRuleStageExtractor.limit(
      await LocalRuleStageExtractor.extract(element,
        source.ruleSearch.intro, source, variables), LocalRuleExecutionLimits.MAX_INTRO_CHARS));
    item.kind = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.kind, source, variables), 256);
    const status = await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.status, source, variables);
    if (status.trim()) item.completed = LocalRuleDispatcher.isCompleted(status);
    item.lastChapter = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.lastChapter, source, variables), 256);
    item.wordCount = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(element,
      source.ruleSearch.wordCount, source, variables), 80);
    item.sourceName = source.bookSourceName;
    item.sourceUrl = source.bookSourceUrl;
    item.variables = LocalRuleDispatcher.copyVariables(variables);
    item.variables['bookUrl'] = item.bookUrl;
    return item;
  }

  private static async resolveContentStrict(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string>): Promise<LocalRuleContentResult> {
    const result = new LocalRuleContentResult();
    result.requestHeaders = LocalRuleDispatcher.getAudioHeaders(source, chapterUrl, variables);
    const pageUrls = new Set<string>();
    const contents: string[] = [];
    let currentUrl = chapterUrl;
    let pageCount = 0;
    let totalCharacters = 0;
    let responseCharacters = 0;
    while (currentUrl && pageCount < 50 && totalCharacters < LocalRuleExecutionLimits.MAX_CONTENT_CHARS) {
      if (pageUrls.has(currentUrl)) break;
      pageUrls.add(currentUrl);
      pageCount++;
      const fetch = await LocalRuleHttpClient.fetch(source, currentUrl, variables);
      LocalRuleDispatcher.assertFetch(fetch, '正文');
      if (responseCharacters + fetch.body.length > LocalRuleExecutionLimits.MAX_STAGE_RESPONSE_CHARS) break;
      responseCharacters += fetch.body.length;
      const document = LocalRuleStageExtractor.createDocument(fetch.body, fetch.requestUrl);
      if (!result.title) {
        result.title = LocalRuleStageExtractor.limit(await LocalRuleStageExtractor.extract(document,
          source.ruleContent.title, source, variables), 256);
      }
      if (!result.audioUrl) {
        result.audioUrl = await LocalRuleStageExtractor.extract(document,
          source.ruleContent.audioUrl, source, variables, true);
      }
      const extractedContent = await LocalRuleStageExtractor.extract(document,
        source.ruleContent.content, source, variables);
      if (source.isAudio()) {
        if (!result.audioUrl) {
          result.audioUrl = LocalRuleDispatcher.firstResolvedUrl(extractedContent, fetch.requestUrl);
        }
      } else {
        let content = extractedContent;
        if (content.includes('<') && content.includes('>')) content = LocalRuleStageExtractor.stripHtml(content);
        content = LocalRuleStageExtractor.applyCleanup(content, source.ruleContent.replaceRegex);
        if (content) {
          totalCharacters += content.length;
          if (totalCharacters > LocalRuleExecutionLimits.MAX_CONTENT_CHARS) {
            const overflow = totalCharacters - LocalRuleExecutionLimits.MAX_CONTENT_CHARS;
            content = content.substring(0, Math.max(0, content.length - overflow));
          }
          if (content) contents.push(content);
        }
      }
      if (!result.audioUrl) {
        result.audioUrl = LocalRuleDispatcher.matchAudioUrl(fetch.body,
          source.ruleContent.sourceRegex, fetch.requestUrl);
      }
      if (source.isAudio() && result.audioUrl) break;
      const nextUrl = await LocalRuleStageExtractor.extract(document,
        source.ruleContent.nextContentUrl, source, variables, true);
      if (!nextUrl || pageUrls.has(nextUrl)) break;
      result.nextContentUrl = nextUrl;
      currentUrl = nextUrl;
    }
    result.content = contents.join('\n\n').trim();
    result.requestHeaders = LocalRuleDispatcher.getAudioHeaders(
      source, result.audioUrl || chapterUrl, variables);
    console.info(`[LocalRuleDispatcher] content ${source.bookSourceName}: ` +
      `responseChars=${responseCharacters}, pages=${pageCount}, contentChars=${result.content.length}, ` +
      `audio=${result.audioUrl.length > 0}`);
    return result;
  }

  private static matchAudioUrl(body: string, pattern: string, baseUrl: string): string {
    if (!pattern.trim()) return '';
    try {
      const match = new RegExp(pattern, 'i').exec(body);
      if (match === null) return '';
      const value = match.length > 1 ? match[1] : match[0];
      return LocalRuleUrlAnalyzer.resolveUrl(baseUrl, value ?? '');
    } catch (_error) {
      return '';
    }
  }

  private static firstResolvedUrl(value: string, baseUrl: string): string {
    const trimmed = value.trim();
    if (!trimmed) return '';
    try {
      const parsed = JSON.parse(trimmed) as Object;
      if (typeof parsed === 'string') {
        const resolved = LocalRuleUrlAnalyzer.resolveUrl(baseUrl, parsed);
        if (resolved) return resolved;
      } else if (Array.isArray(parsed)) {
        const values = parsed as Object[];
        for (const item of values) {
          if (item === undefined || item === null || typeof item === 'object') continue;
          const resolved = LocalRuleUrlAnalyzer.resolveUrl(baseUrl, String(item));
          if (resolved) return resolved;
        }
      }
    } catch (_error) {
      // 普通字符串继续按行尝试。
    }
    const lines = trimmed.split(new RegExp('\\r?\\n', 'g'));
    for (const line of lines) {
      const resolved = LocalRuleUrlAnalyzer.resolveUrl(baseUrl, line.trim());
      if (resolved) return resolved;
    }
    return '';
  }

  private static looksLikeDirectAudioPath(url: string): boolean {
    const lower = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) return false;
    const authorityStart = lower.indexOf('://') + 3;
    const pathStart = lower.indexOf('/', authorityStart);
    if (pathStart < 0) return false;
    let suffix = lower.length;
    const query = lower.indexOf('?', pathStart);
    const hash = lower.indexOf('#', pathStart);
    if (query >= 0) suffix = Math.min(suffix, query);
    if (hash >= 0) suffix = Math.min(suffix, hash);
    const path = lower.substring(pathStart, suffix);
    return path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.aac') ||
      path.endsWith('.flac') || path.endsWith('.wav') || path.endsWith('.ogg') ||
      path.endsWith('.mp4') || path.endsWith('.m3u8') || path.endsWith('.opus') ||
      path.endsWith('.wma') || path.endsWith('.ape');
  }

  private static requestHost(url: string): string {
    const schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return '';
    const start = schemeEnd + 3;
    let end = url.length;
    const slash = url.indexOf('/', start);
    const query = url.indexOf('?', start);
    const hash = url.indexOf('#', start);
    if (slash >= 0) end = Math.min(end, slash);
    if (query >= 0) end = Math.min(end, query);
    if (hash >= 0) end = Math.min(end, hash);
    return url.substring(start, end).toLowerCase();
  }

  private static prepareCover(source: LocalRuleSource, rawUrl: string,
    refererUrl: string, variables: Record<string, string>): string {
    if (!rawUrl.trim()) return '';
    try {
      const plan = LocalRuleHttpClient.prepareRequest(source, rawUrl, variables);
      const sourceHost = LocalRuleDispatcher.requestHost(source.bookSourceUrl);
      const coverHost = LocalRuleDispatcher.requestHost(plan.url);
      if (sourceHost && coverHost && sourceHost !== coverHost) {
        const filtered: Record<string, string> = {};
        const names = Object.keys(plan.headers);
        for (const name of names) {
          const lower = name.toLowerCase();
          if (lower === 'cookie' || lower === 'authorization' || lower === 'proxy-authorization') continue;
          filtered[name] = plan.headers[name] ?? '';
        }
        plan.headers = filtered;
      }
      let hasReferer = false;
      const headerNames = Object.keys(plan.headers);
      for (const name of headerNames) {
        if (name.toLowerCase() === 'referer') hasReferer = true;
      }
      if (!hasReferer && refererUrl.startsWith('http')) plan.headers['Referer'] = refererUrl;
      CoverPrefetcher.registerHeaders(plan.url, plan.headers);
      return plan.url;
    } catch (_error) {
      return rawUrl;
    }
  }

  private static isCompleted(value: string): boolean {
    const clean = value.trim().toLowerCase();
    return clean === '1' || clean === 'true' || clean === 'completed' || clean === 'finished' ||
      clean.includes('完结') || clean.includes('完本');
  }

  private static normalizeTingYouFallbackInfo(info: LocalRuleBookInfo): void {
    const statusText = info.kind.trim().toLowerCase();
    const isStatus = statusText.includes('完结') || statusText.includes('完本') ||
      statusText.includes('连载') || statusText.includes('更新中');
    if (!isStatus) return;
    if (statusText.includes('连载') || statusText.includes('更新中')) {
      info.completed = false;
    } else {
      info.completed = true;
    }
    // 旧听友规则把 album-status 配到了 kind；清空后由搜索快照保留真实分类。
    info.kind = '';
  }

  private static sanitizeIntro(value: string): string {
    const clean = value.trim();
    const compact = clean.replace(new RegExp('\\s+', 'g'), '');
    const placeholders: string[] = ['=.=','==', '暂无', '暂无简介', '暂无介绍', '无'];
    return placeholders.includes(compact) ? '' : clean;
  }

  private static async prepareVariables(source: LocalRuleSource,
    variables: Record<string, string>, baseUrl: string,
    keyword: string = '', page: number = 1): Promise<void> {
    variables['key'] = variables['key'] ?? keyword;
    variables['searchKey'] = variables['searchKey'] ?? keyword;
    variables['keyword'] = variables['keyword'] ?? keyword;
    variables['searchKeyRaw'] = variables['searchKeyRaw'] ?? keyword;
    variables['page'] = variables['page'] ?? String(Math.max(1, page));
    variables['pageIndex'] = variables['pageIndex'] ?? String(Math.max(1, page));
    const header = source.header.trim();
    if (header.length === 0 || (!LocalRuleScriptRuntime.hasScript(header) && !header.includes('{{'))) return;
    variables['__header'] = '{}';
    try {
      const resolved = await LocalRuleScriptRuntime.resolveText(header, baseUrl, source, variables);
      variables['__header'] = resolved.trim().length > 0 ? resolved : '{}';
    } catch (error) {
      variables['__header'] = source.header;
      console.warn(`[LocalRuleDispatcher] dynamic header ${source.bookSourceName} failed: ` +
        LocalRuleDispatcher.errorMessage(error as Object));
    }
  }

  private static assertFetch(fetch: LocalRuleFetchResult, stage: string): void {
    if (fetch.ok) return;
    throw new Error(`${stage}请求失败：${fetch.errorMessage || '未知错误'}`);
  }

  private static copyVariables(input: Record<string, string>): Record<string, string> {
    const output: Record<string, string> = {};
    const keys = Object.keys(input);
    for (const key of keys) output[key] = input[key] ?? '';
    return output;
  }

  private static logFailure(source: LocalRuleSource, stage: string, error: Object): void {
    console.warn(`[LocalRuleDispatcher] ${stage} ${source.bookSourceName} failed: ` +
      LocalRuleDispatcher.errorMessage(error));
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '规则执行失败';
    return String(error || '规则执行失败');
  }
}
