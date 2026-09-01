/** 内置源优先、本地规则源旁路的统一内容门面。 */
import { AudioSource, Book, Chapter } from '../model/Book';
import { BookInfo, BookSource, HomeBlockSection, SearchResult, TocItem } from '../model/BookSource';
import { LocalRuleSource, LocalRuleSourceHealth, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { TextChapterContent, TextSourceError } from '../model/TextReading';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { DownloadPolicy } from './DownloadPolicy';
import { BuiltInDispatcher } from './builtin/BuiltInDispatcher';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';
import { LocalRuleContentResult } from './rulesource/LocalRuleRuntimeTypes';
import { LocalRuleDispatcher } from './rulesource/LocalRuleDispatcher';
import { NativeRuleSourceDispatcher } from './rulesource/NativeRuleSourceDispatcher';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { KK_BIQU_GE_SOURCE_URL } from './text/KkBiqugeHtmlParser';
import { KkBiqugeTextSource } from './text/KkBiqugeTextSource';

export interface ExploreFetchResult {
  books: SearchResult[];
  nextUrl: string;
  nextPage?: number;
}

export interface AudioRequestInfo {
  url: string;
  headers: Record<string, string>;
}

const HEALTH_MAX_BOOK_CANDIDATES: number = 3;
const HEALTH_MAX_CHAPTER_CANDIDATES: number = 3;
const NATIVE_SOURCE_HEALTH_FALLBACK_KEYWORDS: string[] = ['斗破苍穹', '凡人修仙传'];

class LocalSourceSearchProbe {
  results: SearchResult[] = [];
  errors: string[] = [];
}

class NativeContentHealthOutcome {
  contentType: 'audio' | 'text' = 'text';
  bookName: string = '';
  errorMessage: string = '';
}

export class NativeRuleSourceHealthPolicy {
  static assertSearchCoverage(results: SearchResult[], errors: string[]): void {
    const hasText = NativeRuleSourceHealthPolicy.hasContentType(results, 'text');
    const hasAudio = NativeRuleSourceHealthPolicy.hasContentType(results, 'audio');
    if (hasText && hasAudio) return;
    if (errors.length > 0) throw new Error(errors.join('；'));

    const missing: string[] = [];
    if (!hasText) missing.push('小说');
    if (!hasAudio) missing.push('听书');
    throw new Error(`${missing.join('、')}搜索未返回可验证书籍，严格测试不通过`);
  }

  private static hasContentType(results: SearchResult[], contentType: 'audio' | 'text'): boolean {
    for (const result of results) {
      if (result.contentType === contentType) return true;
    }
    return false;
  }
}

export class BookSourceService {
  static async prepareAudioSource(bookSourceUrl: string): Promise<void> {
    if (BuiltInSourceRegistry.isBuiltIn(bookSourceUrl)) {
      await BuiltInDispatcher.prepareAudio(bookSourceUrl);
    }
  }

  static getAudioResolveTimeoutMs(source: BookSource, fallbackMs: number): number {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getAudioResolveTimeoutMs(source, fallbackMs);
    }
    if (source instanceof LocalRuleSource) {
      return Math.max(3000, Math.min(60000, source.respondTime));
    }
    return fallbackMs;
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.search(source, keyword, page);
    }
    if (source instanceof LocalRuleSource && !source.isSearchEnabled()) return [];
    if (NativeRuleSourceDispatcher.isSource(source)) {
      return NativeRuleSourceDispatcher.search(source, keyword, page);
    }
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined ? [] : LocalRuleDispatcher.search(localSource, keyword, page);
  }

  static async testLocalSource(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const startedAt = Date.now();
    if (!source.canExecute()) {
      health.status = LocalRuleSourceStatus.UNSUPPORTED;
      health.message = source.validationMessage || '书源包含当前版本不支持的能力';
      return health;
    }

    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = '搜索测试关键词不能为空';
      return health;
    }

    try {
      if (NativeRuleSourceDispatcher.isSource(source)) {
        health.message = await BookSourceService.testNativeRuleSource(source, cleanKeyword);
      } else {
        health.message = await BookSourceService.testRuleSource(source, cleanKeyword);
      }
      health.status = LocalRuleSourceStatus.READY;
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
    }
    health.responseTimeMs = Date.now() - startedAt;
    return health;
  }

  private static async testRuleSource(source: LocalRuleSource, keyword: string): Promise<string> {
    const results = await LocalRuleDispatcher.searchForHealthCheck(source, keyword, 1);
    if (results.length === 0) {
      return '搜索请求正常，当前关键词暂无匹配，已保留书源';
    }

    const contentType: 'audio' | 'text' = source.isAudio() ? 'audio' : 'text';
    const bookName = await BookSourceService.validateCandidates(
      source, results, contentType, false);
    return source.isAudio()
      ? `搜索、详情、目录与音频解析正常：${bookName}`
      : `搜索、详情、目录与正文解析正常：${bookName}`;
  }

  private static async testNativeRuleSource(source: LocalRuleSource, keyword: string): Promise<string> {
    const probe = await BookSourceService.probeNativeRuleSourceSearch(source, keyword);
    NativeRuleSourceHealthPolicy.assertSearchCoverage(probe.results, probe.errors);
    if (NativeRuleSourceDispatcher.usesSingleContentHealthCheck(source.bookSourceUrl)) {
      const audioOutcome = await BookSourceService.validateNativeContentType(
        source, probe.results, 'audio');
      if (audioOutcome.errorMessage.length > 0) throw new Error(audioOutcome.errorMessage);
      return `小说与听书搜索正常；听书详情、目录与音频解析正常：${audioOutcome.bookName}`;
    }
    const textOutcome = await BookSourceService.validateNativeContentType(
      source, probe.results, 'text');
    const audioOutcome = await BookSourceService.validateNativeContentType(
      source, probe.results, 'audio');
    const errors: string[] = [];
    if (textOutcome.errorMessage.length > 0) errors.push(textOutcome.errorMessage);
    if (audioOutcome.errorMessage.length > 0) errors.push(audioOutcome.errorMessage);
    if (errors.length > 0) throw new Error(errors.join('；'));
    return `小说正文正常：${textOutcome.bookName}；听书音频正常：${audioOutcome.bookName}`;
  }

  private static async validateNativeContentType(source: LocalRuleSource, results: SearchResult[],
    contentType: 'audio' | 'text'): Promise<NativeContentHealthOutcome> {
    const outcome = new NativeContentHealthOutcome();
    outcome.contentType = contentType;
    try {
      outcome.bookName = await BookSourceService.validateCandidates(
        source, results, contentType, true);
    } catch (error) {
      const label = contentType === 'audio' ? '听书' : '小说';
      const message = error instanceof Error ? error.message : String(error);
      outcome.errorMessage = `${label}验证失败：${message}`;
    }
    return outcome;
  }

  private static async probeNativeRuleSourceSearch(source: LocalRuleSource,
    keyword: string): Promise<LocalSourceSearchProbe> {
    const probe = new LocalSourceSearchProbe();
    const keywords: string[] = [];
    BookSourceService.appendUnique(keywords, keyword);
    for (const fallback of NATIVE_SOURCE_HEALTH_FALLBACK_KEYWORDS) {
      BookSourceService.appendUnique(keywords, fallback);
    }
    const seen = new Set<string>();
    for (const currentKeyword of keywords) {
      try {
        const results = await NativeRuleSourceDispatcher.searchForHealthCheck(
          source, currentKeyword, 1);
        for (const result of results) {
          if (seen.has(result.bookUrl)) continue;
          seen.add(result.bookUrl);
          probe.results.push(result);
        }
        if (BookSourceService.hasContentType(probe.results, 'text') &&
          BookSourceService.hasContentType(probe.results, 'audio')) break;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.length > 0 && !probe.errors.includes(message)) probe.errors.push(message);
      }
    }
    return probe;
  }

  private static async validateCandidates(source: LocalRuleSource, results: SearchResult[],
    contentType: 'audio' | 'text', requireResultType: boolean): Promise<string> {
    let attempted = 0;
    let lastError = '';
    for (const result of results) {
      if (requireResultType && result.contentType !== contentType) continue;
      if (attempted >= HEALTH_MAX_BOOK_CANDIDATES) break;
      attempted++;
      try {
        await BookSourceService.validateCandidate(source, result, contentType);
        return result.name;
      } catch (error) {
        if (error instanceof Error && NativeRuleSourceDispatcher.isNonRetryableHealthError(
          source.bookSourceUrl, error)) {
          throw error;
        }
        lastError = error instanceof Error ? error.message : String(error);
      }
    }
    const label = contentType === 'audio' ? '听书' : '小说';
    if (attempted === 0) throw new Error(`${label}搜索未返回可验证的书籍`);
    throw new Error(`${label}全链路验证失败：${lastError || '未解析出有效内容'}`);
  }

  private static async validateCandidate(source: LocalRuleSource, result: SearchResult,
    contentType: 'audio' | 'text'): Promise<void> {
    const searchVariables = BookSourceService.copyVariables(result.variables);
    const info = await BookSourceService.getBookInfo(source, result.bookUrl, searchVariables);
    if (info === null) throw new Error(`详情解析失败：${result.name}`);

    const variables = BookSourceService.mergeVariables(searchVariables, info.variables);
    const tocUrl = info.tocUrl.trim().length > 0 ? info.tocUrl : result.bookUrl;
    const toc = await BookSourceService.getBookToc(source, tocUrl, variables, result.name);
    if (toc.length === 0) throw new Error(`目录解析失败：${result.name}`);
    await BookSourceService.validateChapterCandidates(source, toc, variables, contentType);
  }

  private static async validateChapterCandidates(source: LocalRuleSource, toc: TocItem[],
    variables: Record<string, string>, contentType: 'audio' | 'text'): Promise<void> {
    const candidates = BookSourceService.preferredChapterCandidates(toc);
    let attempted = 0;
    let lastError = '';
    for (const chapter of candidates) {
      if (attempted >= HEALTH_MAX_CHAPTER_CANDIDATES) break;
      attempted++;
      try {
        if (contentType === 'audio') {
          const request = await BookSourceService.resolveAudioRequest(
            source, chapter.url, variables, chapter.variables);
          if (!BookSourceService.isResolvedHttpAudio(chapter.url, request.url)) {
            throw new Error('未解析出可播放的 HTTP 音频地址');
          }
        } else {
          const scopedVariables = BookSourceService.mergeVariables(variables, chapter.variables);
          const content = NativeRuleSourceDispatcher.isSource(source)
            ? await NativeRuleSourceDispatcher.resolveContent(source.bookSourceUrl, chapter.url)
            : await LocalRuleDispatcher.resolveContent(source, chapter.url, scopedVariables);
          if (content.content.trim().length === 0) throw new Error('章节正文为空');
        }
        return;
      } catch (error) {
        if (error instanceof Error && NativeRuleSourceDispatcher.isNonRetryableHealthError(
          source.bookSourceUrl, error)) {
          throw error;
        }
        lastError = error instanceof Error ? error.message : String(error);
      }
    }
    if (attempted === 0) throw new Error('目录中没有可验证的章节');
    throw new Error(lastError || '章节内容解析失败');
  }

  private static preferredChapterCandidates(toc: TocItem[]): TocItem[] {
    const output: TocItem[] = [];
    const seen = new Set<string>();
    for (const item of toc) {
      if (item.isVolume || item.isPay || item.isVip) continue;
      BookSourceService.appendChapter(output, seen, item);
    }
    for (const item of toc) {
      if (item.isVolume) continue;
      BookSourceService.appendChapter(output, seen, item);
    }
    for (const item of toc) BookSourceService.appendChapter(output, seen, item);
    return output;
  }

  private static appendChapter(output: TocItem[], seen: Set<string>, item: TocItem): void {
    if (item.url.trim().length === 0 || seen.has(item.url)) return;
    seen.add(item.url);
    output.push(item);
  }

  private static hasContentType(results: SearchResult[], contentType: 'audio' | 'text'): boolean {
    for (const result of results) {
      if (result.contentType === contentType) return true;
    }
    return false;
  }

  private static appendUnique(values: string[], value: string): void {
    const clean = value.trim();
    if (clean.length > 0 && !values.includes(clean)) values.push(clean);
  }

  private static isResolvedHttpAudio(chapterUrl: string, audioUrl: string): boolean {
    const cleanAudioUrl = audioUrl.trim();
    if (DownloadPolicy.isResolvedAudioUrl(chapterUrl, cleanAudioUrl)) return true;
    if (cleanAudioUrl !== chapterUrl || !DownloadPolicy.isHttpUrl(cleanAudioUrl)) return false;
    const path = cleanAudioUrl.toLowerCase().split('?')[0].split('#')[0];
    return path.endsWith('.m3u8');
  }

  static async getBookInfo(source: BookSource, bookUrl: string,
    _variables?: Record<string, string>): Promise<BookInfo | null> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getBookInfo(source, bookUrl);
    }
    if (NativeRuleSourceDispatcher.isSource(source)) {
      return NativeRuleSourceDispatcher.getBookInfo(source.bookSourceUrl, bookUrl);
    }
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined ? null : LocalRuleDispatcher.getBookInfo(
      localSource, bookUrl, BookSourceService.copyVariables(_variables));
  }

  static async getBookToc(source: BookSource, tocUrl: string,
    _variables?: Record<string, string>, bookName?: string): Promise<TocItem[]> {
    let items: TocItem[] = [];
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      items = await BuiltInDispatcher.getBookToc(source, tocUrl);
    } else if (NativeRuleSourceDispatcher.isSource(source)) {
      items = await NativeRuleSourceDispatcher.getBookToc(source.bookSourceUrl, tocUrl);
    } else {
      const localSource = await BookSourceService.resolveLocalSource(source);
      if (localSource !== undefined) {
        items = await LocalRuleDispatcher.getBookToc(
          localSource, tocUrl, BookSourceService.copyVariables(_variables));
      }
    }
    const seen = new Set<string>();
    const unique: TocItem[] = [];
    for (const item of items) {
      if (!item.url || seen.has(item.url)) continue;
      seen.add(item.url);
      if (bookName) item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
      unique.push(item);
    }
    return unique;
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string,
    _variables?: Record<string, string>): Promise<string> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getAudioUrl(source, chapterUrl);
    }
    if (NativeRuleSourceDispatcher.isSource(source)) {
      return NativeRuleSourceDispatcher.getAudioUrl(source.bookSourceUrl, chapterUrl);
    }
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined
      ? chapterUrl : LocalRuleDispatcher.getAudioUrl(
        localSource, chapterUrl, BookSourceService.copyVariables(_variables));
  }

  static async resolveAudioRequest(source: BookSource, chapterUrl: string,
    variables?: Record<string, string>, chapterVariables?: Record<string, string>): Promise<AudioRequestInfo> {
    if (NativeRuleSourceDispatcher.isSource(source)) {
      const resolved = await NativeRuleSourceDispatcher.resolveContent(
        source.bookSourceUrl, chapterUrl);
      const info: AudioRequestInfo = {
        url: resolved.audioUrl,
        headers: resolved.requestHeaders
      };
      return info;
    }
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      const localSource = await BookSourceService.resolveLocalSource(source);
      if (localSource !== undefined) {
        const scopedVariables = BookSourceService.mergeVariables(
          BookSourceService.copyVariables(variables), chapterVariables);
        const result: LocalRuleContentResult = await LocalRuleDispatcher.resolveContent(
          localSource, chapterUrl, scopedVariables);
        const localUrl = result.audioUrl || chapterUrl;
        const localHeaders = Object.keys(result.requestHeaders).length > 0
          ? result.requestHeaders : LocalRuleDispatcher.getAudioHeaders(localSource, localUrl);
        return { url: localUrl, headers: localHeaders };
      }
    }
    const url = await BookSourceService.getAudioUrl(source, chapterUrl, variables);
    const headers = BuiltInDispatcher.getAudioHeaders(source, url);
    return { url, headers };
  }

  static async loadTextBook(book: Book): Promise<Book> {
    if (book.sourceUrl === KK_BIQU_GE_SOURCE_URL) {
      return KkBiqugeTextSource.loadBook(book);
    }
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    const usesNativeAdapter = NativeRuleSourceDispatcher.isSourceUrl(book.sourceUrl);
    if (localSource === undefined || (!usesNativeAdapter && !localSource.isText()) ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }

    const variables = BookSourceService.copyVariables(book.variables);
    const info = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.getBookInfo(book.sourceUrl, book.bookUrl)
      : await LocalRuleDispatcher.getBookInfo(localSource, book.bookUrl, variables);
    let tocUrl = book.bookUrl;
    let resolvedVariables = variables;
    if (info !== null) {
      if (info.tocUrl.length > 0) tocUrl = info.tocUrl;
      resolvedVariables = BookSourceService.mergeVariables(variables, info.variables);
    }
    const toc = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.getBookToc(book.sourceUrl, tocUrl)
      : await LocalRuleDispatcher.getBookToc(localSource, tocUrl, resolvedVariables);
    const value = BookSourceService.copyBook(book);
    if (info !== null) {
      if (info.name.length > 0) value.title = info.name;
      if (info.author.length > 0) value.author = info.author;
      if (info.coverUrl.length > 0) value.cover = info.coverUrl;
      if (info.intro.length > 0) value.intro = info.intro;
      if (info.kind.length > 0) value.category = info.kind;
      if (info.completed !== undefined) value.completed = info.completed;
      value.variables = resolvedVariables;
    }
    const chapters: Chapter[] = [];
    for (let index = 0; index < toc.length; index++) {
      const item = toc[index];
      const audioSource: AudioSource = { type: 'url', value: item.url };
      const chapter: Chapter = {
        id: `${value.id}-c${index}`,
        index: index + 1,
        title: item.name,
        duration: item.duration ?? 0,
        source: audioSource,
        originSourceValue: item.url,
        variables: item.variables
      };
      chapters.push(chapter);
    }
    value.chapters = chapters;
    value.chapterCount = chapters.length;
    return value;
  }

  static async getTextChapterContent(book: Book, chapterUrl: string,
    title: string, chapterVariables?: Record<string, string>): Promise<TextChapterContent> {
    if (book.sourceUrl === KK_BIQU_GE_SOURCE_URL) {
      return KkBiqugeTextSource.getChapterContent(chapterUrl, title);
    }
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    const usesNativeAdapter = NativeRuleSourceDispatcher.isSourceUrl(book.sourceUrl);
    if (localSource === undefined || (!usesNativeAdapter && !localSource.isText()) ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }
    const scopedVariables = BookSourceService.mergeVariables(
      BookSourceService.copyVariables(book.variables), chapterVariables);
    const result = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.resolveContent(book.sourceUrl, chapterUrl)
      : await LocalRuleDispatcher.resolveContent(localSource, chapterUrl, scopedVariables);
    if (result.content.trim().length === 0) {
      throw new TextSourceError('EMPTY_CONTENT', '章节正文为空');
    }
    return TextChapterContent.of(result.title || title, result.content, chapterUrl);
  }

  static async getExploreBooksByUrl(source: BookSource, categoryUrl: string,
    page: number = 1): Promise<ExploreFetchResult> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return { books: [], nextUrl: '' };
    return BuiltInDispatcher.getExploreBooksByUrl(source, categoryUrl, page);
  }

  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getExploreBooks(source);
  }

  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getHomeBlocks(source);
  }

  private static async resolveLocalSource(source: BookSource): Promise<LocalRuleSource | undefined> {
    if (source instanceof LocalRuleSource) return source;
    try {
      return await LocalRuleSourceRepository.getByUrl(source.bookSourceUrl);
    } catch (_error) {
      return undefined;
    }
  }

  private static copyVariables(input: Record<string, string> | undefined): Record<string, string> {
    const output: Record<string, string> = {};
    if (input === undefined) return output;
    const keys = Object.keys(input);
    for (const key of keys) output[key] = input[key] ?? '';
    return output;
  }

  private static mergeVariables(left: Record<string, string>,
    right: Record<string, string> | undefined): Record<string, string> {
    const output = BookSourceService.copyVariables(left);
    if (right === undefined) return output;
    const keys = Object.keys(right);
    for (const key of keys) output[key] = right[key] ?? '';
    return output;
  }

  private static copyBook(book: Book): Book {
    const value: Book = {
      id: book.id,
      contentType: book.contentType,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      cover: book.cover,
      category: book.category,
      intro: book.intro,
      totalDuration: book.totalDuration,
      chapterCount: book.chapterCount,
      rating: book.rating,
      tags: book.tags.slice(),
      chapters: book.chapters.slice(),
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      completed: book.completed
    };
    return value;
  }
}
