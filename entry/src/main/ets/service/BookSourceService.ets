import { DataService } from './DataService';
/** 用户导入规则源的统一内容门面。 */
import { AudioSource, Book, Chapter } from '../model/Book';
import { BookInfo, BookSource, SearchResult, TocItem } from '../model/BookSource';
import { LocalRuleSource, LocalRuleSourceHealth, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { TextChapterContent, TextSourceError } from '../model/TextReading';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { DownloadPolicy } from './DownloadPolicy';
import { LocalRuleContentResult } from './rulesource/LocalRuleRuntimeTypes';
import { LocalRuleDispatcher } from './rulesource/LocalRuleDispatcher';
import { NativeRuleSourceDispatcher } from './rulesource/NativeRuleSourceDispatcher';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { LocalRulePanelService } from './rulesource/LocalRulePanelService';
import { LocalRuleDiagnostics } from './rulesource/LocalRuleDiagnostics';
import { TalebookSourceIdentity } from './rulesource/talebook/TalebookSourceIdentity';
import { TalebookSourceAdapter } from './rulesource/talebook/TalebookSourceAdapter';
import { SearchCache } from '../utils/SearchCache';

class AudioBookLoad {
  book: Book;
  listeners: Array<(book: Book) => void> = [];
  promise: Promise<Book>;

  constructor(book: Book) {
    this.book = book;
    this.promise = Promise.resolve(book);
  }
}

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
  private static audioLoads: Map<string, AudioBookLoad> = new Map();

  static pendingAudioBook(bookId: string): Promise<Book> | undefined {
    return BookSourceService.audioLoads.get(bookId)?.promise;
  }

  /** 目录任务独立于页面生命周期；重进详情复用任务，播放时继续补全同一份章节数组。 */
  static async loadAudioBook(book: Book, onUpdate: (book: Book) => void): Promise<Book> {
    const active = BookSourceService.audioLoads.get(book.id);
    if (active !== undefined) {
      active.listeners.push(onUpdate);
      onUpdate(active.book);
      return active.promise;
    }
    const value = BookSourceService.copyBook(book);
    value.chapters = [];
    value.tocComplete = false;
    const task = new AudioBookLoad(value);
    task.listeners.push(onUpdate);
    BookSourceService.audioLoads.set(book.id, task);
    SearchCache.put(value);
    task.promise = BookSourceService.fetchAudioBook(task).finally((): void => {
      task.listeners = [];
      if (BookSourceService.audioLoads.get(book.id) === task) BookSourceService.audioLoads.delete(book.id);
    });
    return task.promise;
  }

  private static notifyAudioBook(task: AudioBookLoad): void {
    for (const listener of task.listeners) listener(task.book);
  }

  private static async fetchAudioBook(task: AudioBookLoad): Promise<Book> {
    const startedAt = Date.now();
    const book = task.book;
    const source = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (source === undefined) throw new Error('书源已被删除或不可用');
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
    let tocUrl = book.bookUrl;
    if (info !== null) {
      tocUrl = info.tocUrl || tocUrl;
      if (info.name.trim()) book.title = info.name;
      if (info.author.trim()) book.author = info.author;
      if (info.coverUrl.trim()) book.cover = info.coverUrl;
      if (info.intro.trim()) book.intro = info.intro;
      else if (['=.=','==', '暂无', '暂无简介', '暂无介绍', '无'].includes(book.intro.replace(/\s+/g, ''))) book.intro = '';
      if (info.kind.trim()) book.category = info.kind;
      if (info.completed !== undefined) book.completed = info.completed;
      if (info.wordCount.trim()) book.wordCount = info.wordCount;
      if (info.lastChapter.trim()) book.latestChapterTitle = info.lastChapter;
      if (info.updateTime?.trim()) book.updateTime = info.updateTime;
      book.variables = BookSourceService.mergeVariables(BookSourceService.copyVariables(book.variables), info.variables);
    }
    BookSourceService.notifyAudioBook(task);
    const append = (items: TocItem[]): void => {
      const first = book.chapters.length === 0;
      for (const item of items) {
        const index = book.chapters.length;
        const chapter: Chapter = {
          id: `${book.id}-c${index}`, index: index + 1, title: item.name, duration: item.duration || 0,
          source: { type: 'url', value: item.url }, originSourceValue: item.url, variables: item.variables
        };
        book.chapters.push(chapter);
      }
      book.chapterCount = Math.max(book.chapterCount, book.chapters.length);
      if (first && items.length > 0) {
        console.info(`[BookSourceService] toc first ${source.bookSourceName}: ` +
          `chapters=${book.chapters.length}, elapsedMs=${Date.now() - startedAt}`);
      }
      BookSourceService.notifyAudioBook(task);
    };
    await BookSourceService.getBookToc(source, tocUrl, book.variables, book.title, append);
    if (book.chapters.length === 0) throw new Error('书源未返回有效章节');
    book.tocComplete = true;
    SearchCache.put(book);
    BookSourceService.notifyAudioBook(task);
    console.info(`[BookSourceService] toc complete ${source.bookSourceName}: ` +
      `chapters=${book.chapters.length}, elapsedMs=${Date.now() - startedAt}`);
    // 仅完整目录进入现有有界持久缓存，重进详情不再重复解析几千章。
    await DataService.upsertCachedBook(book);
    return book;
  }

  static async prepareAudioSource(_bookSourceUrl: string): Promise<void> {
    return;
  }

  static getAudioResolveTimeoutMs(source: BookSource, fallbackMs: number): number {
    if (source instanceof LocalRuleSource) {
      return Math.max(3000, Math.min(60000, source.respondTime));
    }
    return fallbackMs;
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
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
      if (TalebookSourceIdentity.isSourceUrl(source.bookSourceUrl)) {
        const results = await TalebookSourceAdapter.search(source, cleanKeyword);
        if (results.length === 0) {
          health.message = '搜索请求正常，当前关键词暂无匹配；可使用发现/阅读测试验证书库';
        } else {
          await BookSourceService.validateCandidate(source, results[0], source.isAudio() ? 'audio' : 'text');
          health.message = `搜索、详情、目录与内容解析正常：${results[0].name}`;
        }
      } else if (NativeRuleSourceDispatcher.isSource(source)) {
        health.message = await BookSourceService.testNativeRuleSource(source, cleanKeyword);
      } else {
        health.message = await BookSourceService.testRuleSource(source, cleanKeyword);
      }
      health.status = LocalRuleSourceStatus.READY;
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      console.warn(`[BookSourceService] testLocalSource ${source.bookSourceName} failed: ${health.message}`);
    }
    health.responseTimeMs = Date.now() - startedAt;
    return health;
  }

  /** 搜索校验允许无匹配结果；发现/阅读校验必须取得实际内容。 */
  static async testLocalSourceAvailability(source: LocalRuleSource,
    keyword: string): Promise<LocalRuleSourceHealth> {
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
      const results = NativeRuleSourceDispatcher.isSource(source)
        ? await NativeRuleSourceDispatcher.searchForHealthCheck(source, cleanKeyword, 1)
        : await LocalRuleDispatcher.searchForHealthCheck(source, cleanKeyword, 1);
      health.status = LocalRuleSourceStatus.READY;
      health.message = results.length > 0 ? `搜索正常，共 ${results.length} 条` :
        '搜索请求正常，当前关键词暂无匹配';
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      console.warn(`[BookSourceService] availability ${source.bookSourceName} failed: ${health.message}`);
    }
    health.responseTimeMs = Date.now() - startedAt;
    return health;
  }

  private static async testRuleSource(source: LocalRuleSource, keyword: string): Promise<string> {
    const results = await LocalRuleDispatcher.searchForHealthCheck(source, keyword, 1);
    if (results.length === 0) {
      return '搜索请求正常，当前关键词暂无匹配，已保留书源';
    }

    const contentType: 'audio' | 'text' = results[0].contentType ?? (source.isAudio() ? 'audio' : 'text');
    const bookName = await BookSourceService.validateCandidates(
      source, results, contentType, false);
    return contentType === 'audio'
      ? `搜索、详情、目录与音频解析正常：${bookName}`
      : `搜索、详情、目录与正文解析正常：${bookName}`;
  }

  static async testLocalSourceExploreReading(source: LocalRuleSource,
    isCancelled: () => boolean = (): boolean => false): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const variables = LocalRuleDiagnostics.open((): void => {});
    try {
      if (!source.enabledExplore || !source.exploreUrl.trim()) throw new Error('缺少发现地址或发现未启用');
      if (!source.canExecute()) throw new Error(source.validationMessage || '书源不可执行');
      BookSourceService.checkHealthCancellation(isCancelled);
      const panel = await LocalRulePanelService.load(source, false, variables);
      const entries = panel.entries.filter((entry): boolean => entry.url.trim().length > 0).slice(0, 8);
      if (entries.length === 0) throw new Error('没有解析出发现分类');
      const candidates: SearchResult[] = [];
      const seen = new Set<string>();
      let lastError = '';
      for (const entry of entries) {
        BookSourceService.checkHealthCancellation(isCancelled);
        try {
          const result = await LocalRuleDispatcher.explore(source, entry.url, 1, variables);
          for (const book of result.books) {
            if (seen.has(book.bookUrl)) continue;
            seen.add(book.bookUrl);
            candidates.push(book);
            if (candidates.length >= 4) break;
          }
        } catch (error) {
          lastError = error instanceof Error ? error.message : String(error);
        }
        if (candidates.length >= 4) break;
      }
      if (candidates.length === 0) throw new Error(lastError || '发现分类未返回可验证的书籍');
      for (const candidate of candidates) {
        BookSourceService.checkHealthCancellation(isCancelled);
        try {
          await BookSourceService.validateCandidate(source, candidate,
            source.isAudio() ? 'audio' : 'text', isCancelled, true);
          BookSourceService.checkHealthCancellation(isCancelled);
          health.status = LocalRuleSourceStatus.READY;
          health.message = `发现、详情、目录与${(candidate.contentType ?? (source.isAudio() ? 'audio' : 'text')) === 'audio' ? '音频' : '正文'}解析正常：${candidate.name}`;
          return health;
        } catch (error) {
          lastError = error instanceof Error ? error.message : String(error);
        }
      }
      throw new Error(lastError || '发现/阅读链路未取得有效内容');
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      return health;
    } finally {
      health.responseTimeMs = Date.now() - health.checkedAt;
      LocalRuleDiagnostics.close(variables);
    }
  }

  private static checkHealthCancellation(isCancelled: () => boolean): void {
    if (isCancelled()) throw new Error('书源校验已取消');
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
    contentType: 'audio' | 'text', isCancelled: () => boolean = (): boolean => false,
    publicOnly: boolean = false): Promise<void> {
    BookSourceService.checkHealthCancellation(isCancelled);
    const searchVariables = BookSourceService.copyVariables(result.variables);
    const info = await BookSourceService.getBookInfo(source, result.bookUrl, searchVariables);
    BookSourceService.checkHealthCancellation(isCancelled);
    if (info === null) throw new Error(`详情解析失败：${result.name}`);

    const variables = BookSourceService.mergeVariables(searchVariables, info.variables);
    const resolvedType = result.contentType ?? contentType;
    variables['__bookContentType'] = resolvedType;
    const tocUrl = info.tocUrl.trim().length > 0 ? info.tocUrl : result.bookUrl;
    const toc = await BookSourceService.getBookToc(source, tocUrl, variables, result.name);
    BookSourceService.checkHealthCancellation(isCancelled);
    if (toc.length === 0) throw new Error(`目录解析失败：${result.name}`);
    const chapters = publicOnly ? toc.filter((chapter: TocItem): boolean =>
      !chapter.isVolume && !chapter.isVip && !chapter.isPay) : toc;
    if (chapters.length === 0) throw new Error('目录正常，但没有可校验的免费章节');
    await BookSourceService.validateChapterCandidates(source, chapters, variables, resolvedType, isCancelled);
  }

  private static async validateChapterCandidates(source: LocalRuleSource, toc: TocItem[],
    variables: Record<string, string>, contentType: 'audio' | 'text',
    isCancelled: () => boolean = (): boolean => false): Promise<void> {
    const candidates = BookSourceService.preferredChapterCandidates(toc);
    let attempted = 0;
    let lastError = '';
    for (const chapter of candidates) {
      BookSourceService.checkHealthCancellation(isCancelled);
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
    if (NativeRuleSourceDispatcher.isSource(source)) {
      return NativeRuleSourceDispatcher.getBookInfo(source.bookSourceUrl, bookUrl);
    }
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined ? null : LocalRuleDispatcher.getBookInfo(
      localSource, bookUrl, BookSourceService.copyVariables(_variables));
  }

  static async getBookToc(source: BookSource, tocUrl: string,
    _variables?: Record<string, string>, bookName?: string,
    onBatch?: (items: TocItem[]) => void): Promise<TocItem[]> {
    const seen = new Set<string>();
    const unique: TocItem[] = [];
    const append = (batch: TocItem[]): void => {
      const added: TocItem[] = [];
      for (const item of batch) {
        if (!item.url || seen.has(item.url)) continue;
        seen.add(item.url);
        if (bookName) item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
        unique.push(item);
        added.push(item);
      }
      if (added.length > 0 && onBatch !== undefined) onBatch(added);
    };
    let items: TocItem[] = [];
    if (NativeRuleSourceDispatcher.isSource(source)) {
      items = await NativeRuleSourceDispatcher.getBookToc(source.bookSourceUrl, tocUrl);
    } else {
      const localSource = await BookSourceService.resolveLocalSource(source);
      if (localSource !== undefined) {
        items = await LocalRuleDispatcher.getBookToc(
          localSource, tocUrl, BookSourceService.copyVariables(_variables), onBatch === undefined ? undefined : append);
      }
    }
    append(items);
    return unique;
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string,
    _variables?: Record<string, string>): Promise<string> {
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
    const emptyHeaders: Record<string, string> = {};
    return { url: chapterUrl, headers: emptyHeaders };
  }

  static async loadTextBook(book: Book, onMetadata?: (book: Book) => void,
    metadataOnly: boolean = false): Promise<Book> {
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    const usesNativeAdapter = NativeRuleSourceDispatcher.isSourceUrl(book.sourceUrl);
    if (localSource === undefined || (!usesNativeAdapter && !localSource.isText() && book.contentType !== 'text') ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }

    const variables = BookSourceService.copyVariables(book.variables);
    variables['__bookContentType'] = 'text';
    const info = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.getBookInfo(book.sourceUrl, book.bookUrl)
      : await LocalRuleDispatcher.getBookInfo(localSource, book.bookUrl, variables);
    let tocUrl = book.bookUrl;
    let resolvedVariables = variables;
    if (info !== null) {
      if (info.tocUrl.length > 0) tocUrl = info.tocUrl;
      resolvedVariables = BookSourceService.mergeVariables(variables, info.variables);
    }
    const value = BookSourceService.copyBook(book);
    if (info !== null) {
      if (info.name.length > 0) value.title = info.name;
      if (info.author.length > 0) value.author = info.author;
      if (info.coverUrl.length > 0) value.cover = info.coverUrl;
      if (info.intro.length > 0) value.intro = info.intro;
      if (info.kind.length > 0) value.category = info.kind;
      if (info.completed !== undefined) value.completed = info.completed;
      if (info.wordCount.trim()) value.wordCount = info.wordCount;
      if (info.lastChapter.trim()) value.latestChapterTitle = info.lastChapter;
      if (info.updateTime?.trim()) value.updateTime = info.updateTime;
      value.variables = resolvedVariables;
    }
    if (metadataOnly) return value;
    if (onMetadata !== undefined) onMetadata(BookSourceService.copyBook(value));
    const toc = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.getBookToc(book.sourceUrl, tocUrl)
      : await LocalRuleDispatcher.getBookToc(localSource, tocUrl, resolvedVariables);
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
    if (book.id.startsWith('import_') && book.contentType === 'text' && book.sourceUrl.length === 0) {
      const content = await DataService.readImportedText(book, chapterUrl);
      return TextChapterContent.of(title, content, chapterUrl);
    }
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    const usesNativeAdapter = NativeRuleSourceDispatcher.isSourceUrl(book.sourceUrl);
    if (localSource === undefined || (!usesNativeAdapter && !localSource.isText() && book.contentType !== 'text') ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }
    const scopedVariables = BookSourceService.mergeVariables(
      BookSourceService.copyVariables(book.variables), chapterVariables);
    scopedVariables['__bookContentType'] = 'text';
    const result = usesNativeAdapter
      ? await NativeRuleSourceDispatcher.resolveContent(book.sourceUrl, chapterUrl)
      : await LocalRuleDispatcher.resolveContent(localSource, chapterUrl, scopedVariables);
    if (result.content.trim().length === 0) {
      throw new TextSourceError('EMPTY_CONTENT', '章节正文为空');
    }
    return TextChapterContent.of(result.title || title, result.content, chapterUrl);
  }

  static async getExploreBooksByUrl(source: BookSource, categoryUrl: string,
    _page: number = 1, resultLimit: number = 50): Promise<ExploreFetchResult> {
    const localSource = await BookSourceService.resolveLocalSource(source);
    if (localSource !== undefined) {
      const result = await LocalRuleDispatcher.explore(localSource, categoryUrl, _page, {}, resultLimit);
      return { books: result.books, nextUrl: result.nextUrl, nextPage: _page + 1 };
    }
    return { books: [], nextUrl: '' };
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
      wordCount: book.wordCount,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      totalDuration: book.totalDuration,
      chapterCount: book.chapterCount,
      rating: book.rating,
      tags: book.tags.slice(),
      chapters: book.chapters.slice(),
      tocComplete: book.tocComplete,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      chaptersDescending: book.chaptersDescending,
      completed: book.completed
    };
    return value;
  }
}
