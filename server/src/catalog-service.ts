import type { AppConfig } from './config.js';
import type { AppDatabase } from './database.js';
import type {
  AudioBook, AudioChapter, AudioResolution, SearchOutcome, SourceProvider, SourceRecord
} from './types.js';
import { errorCode, mapLimit, stableId, withTimeout } from './utils.js';
import { ArchiveProvider } from './providers/archive-provider.js';
import { LegadoProvider } from './providers/legado-provider.js';
import { PodcastProvider } from './providers/podcast-provider.js';
import type { ReaderClient } from './providers/reader-client.js';

export interface SearchResponse {
  items: AudioBook[];
  sources: SearchOutcome[];
  partial: boolean;
  stale: boolean;
}

export interface SourceValidationOutcome {
  ok: boolean;
  stage: 'search' | 'detail' | 'chapters' | 'resolve';
  latencyMs: number;
  errorCode?: string;
}

export class CatalogService {
  private readonly providers: Record<'archive' | 'podcast' | 'legado', SourceProvider>;
  private healthTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly db: AppDatabase,
    private readonly config: AppConfig,
    reader: ReaderClient
  ) {
    this.providers = {
      archive: new ArchiveProvider(),
      podcast: new PodcastProvider(),
      legado: new LegadoProvider(reader)
    };
  }

  startHealthChecks(): void {
    if (this.config.NODE_ENV === 'test' || this.healthTimer) return;
    const run = (): void => { this.checkAllSources().catch(() => undefined); };
    const initial = setTimeout(run, 15000);
    initial.unref();
    this.healthTimer = setInterval(run, 30 * 60 * 1000);
    this.healthTimer.unref();
  }

  stopHealthChecks(): void {
    if (this.healthTimer) clearInterval(this.healthTimer);
    this.healthTimer = null;
  }

  async search(keyword: string, page: number): Promise<SearchResponse> {
    const key = stableId('search', keyword.toLowerCase(), String(page));
    const cached = this.db.getCache<SearchResponse>(key);
    if (cached) return cached;
    const sources = this.db.listSources(true);
    const outcomes = await mapLimit(sources, this.config.SOURCE_CONCURRENCY, async (source) =>
      await this.searchSource(source, keyword, page));
    const items: AudioBook[] = [];
    const seen = new Set<string>();
    for (const outcome of outcomes) {
      for (const candidate of outcome.items) {
        const dedupeKey = `${candidate.sourceId}\u001f${candidate.externalId}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        items.push(this.db.upsertBook(candidate));
      }
    }
    const response: SearchResponse = {
      items,
      sources: outcomes,
      partial: outcomes.some((item) => !item.ok),
      stale: false
    };
    if (items.length > 0 || outcomes.every((item) => item.ok)) {
      this.db.putCache(key, response, this.config.SEARCH_CACHE_TTL_SECONDS);
      return response;
    }
    const stale = this.db.getCache<SearchResponse>(key, true);
    return stale ? { ...stale, stale: true, partial: true, sources: outcomes } : response;
  }

  async testSource(source: SourceRecord, keyword?: string): Promise<SearchOutcome> {
    return await this.searchSource(source, (keyword || source.testKeyword || 'Alice').trim(), 1);
  }

  /**
   * 新目录来源只有在搜索、目录和首章解析全部可用时才允许自动启用。
   * 这里不写入书籍或章节缓存，避免健康检测污染用户搜索历史。
   */
  async validateSource(source: SourceRecord, keyword?: string): Promise<SourceValidationOutcome> {
    const started = Date.now();
    const search = await this.searchSource(source, (keyword || source.testKeyword || 'Alice').trim(), 1);
    if (!search.ok) {
      return {
        ok: false,
        stage: 'search',
        latencyMs: Date.now() - started,
        errorCode: search.errorCode ?? 'SOURCE_ERROR'
      };
    }
    const candidate = search.items[0];
    if (!candidate) {
      const latencyMs = Date.now() - started;
      this.db.recordHealth(source.id, false, latencyMs, 'SOURCE_EMPTY');
      return { ok: false, stage: 'search', latencyMs, errorCode: 'SOURCE_EMPTY' };
    }

    const provider = this.providers[source.kind];
    let stage: SourceValidationOutcome['stage'] = 'detail';
    try {
      const detail = await withTimeout(
        provider.getBook(source, candidate.externalId, candidate.raw),
        this.config.SOURCE_TIMEOUT_MS,
        'SOURCE_DETAIL_TIMEOUT'
      );
      const book: AudioBook = { ...detail, id: 'validation', chapterCount: 0, totalDuration: 0 };
      stage = 'chapters';
      const chapterCandidates = await withTimeout(
        provider.getChapters(source, book),
        Math.max(this.config.SOURCE_TIMEOUT_MS, 30000),
        'SOURCE_CHAPTER_TIMEOUT'
      );
      const firstChapter = chapterCandidates[0];
      if (!firstChapter) throw new Error('EMPTY_CHAPTERS');
      const chapter: AudioChapter = { ...firstChapter, id: 'validation', bookId: book.id };
      stage = 'resolve';
      const resolution = await withTimeout(
        provider.resolve(source, book, chapter),
        Math.max(this.config.SOURCE_TIMEOUT_MS, 30000),
        'AUDIO_RESOLVE_TIMEOUT'
      );
      if (!resolution.url) throw new Error('EMPTY_AUDIO_URL');
      return { ok: true, stage, latencyMs: Date.now() - started };
    } catch (error) {
      const latencyMs = Date.now() - started;
      const code = errorCode(error);
      this.db.recordHealth(source.id, false, latencyMs, code);
      return { ok: false, stage, latencyMs, errorCode: code };
    }
  }

  async getBook(id: string): Promise<AudioBook> {
    const cached = this.db.getBook(id);
    if (!cached) throw new Error('BOOK_NOT_FOUND');
    const source = this.requireSource(cached.sourceId);
    try {
      const candidate = await withTimeout(
        this.providers[source.kind].getBook(source, cached.externalId, cached.raw),
        this.config.SOURCE_TIMEOUT_MS
      );
      return this.db.upsertBook(candidate);
    } catch (error) {
      if (cached.title) return cached;
      throw error;
    }
  }

  async getChapters(bookId: string, refresh = false): Promise<AudioChapter[]> {
    const cached = this.db.listChapters(bookId);
    if (!refresh && cached.length > 0) return cached;
    const book = await this.getBook(bookId);
    const source = this.requireSource(book.sourceId);
    try {
      const chapters = await withTimeout(
        this.providers[source.kind].getChapters(source, book),
        Math.max(this.config.SOURCE_TIMEOUT_MS, 30000)
      );
      return this.db.replaceChapters(book, chapters);
    } catch (error) {
      if (cached.length > 0) return cached;
      throw error;
    }
  }

  async resolve(chapterId: string): Promise<AudioResolution> {
    let chapter = this.db.getChapter(chapterId);
    if (!chapter) throw new Error('CHAPTER_NOT_FOUND');
    const book = this.db.getBook(chapter.bookId);
    if (!book) throw new Error('BOOK_NOT_FOUND');
    const source = this.requireSource(book.sourceId);
    if (source.kind === 'legado') {
      const chapters = await this.getChapters(book.id);
      chapter = chapters.find((item) => item.id === chapterId) ?? chapter;
    }
    return await withTimeout(
      this.providers[source.kind].resolve(source, book, chapter),
      Math.max(this.config.SOURCE_TIMEOUT_MS, 30000),
      'AUDIO_RESOLVE_TIMEOUT'
    );
  }

  async checkAllSources(): Promise<void> {
    const sources = this.db.listSources(true);
    await mapLimit(sources, Math.min(2, this.config.SOURCE_CONCURRENCY), async (source) => {
      await this.testSource(source);
    });
  }

  private async searchSource(source: SourceRecord, keyword: string, page: number): Promise<SearchOutcome> {
    const started = Date.now();
    try {
      const items = await withTimeout(
        this.providers[source.kind].search(source, keyword, page),
        this.config.SOURCE_TIMEOUT_MS
      );
      const latencyMs = Date.now() - started;
      this.db.recordHealth(source.id, true, latencyMs);
      return { sourceId: source.id, sourceName: source.name, ok: true, latencyMs, items };
    } catch (error) {
      const latencyMs = Date.now() - started;
      const code = errorCode(error);
      this.db.recordHealth(source.id, false, latencyMs, code);
      return { sourceId: source.id, sourceName: source.name, ok: false, latencyMs, items: [], errorCode: code };
    }
  }

  private requireSource(id: string): SourceRecord {
    const source = this.db.getSource(id);
    if (!source || !source.enabled) throw new Error('SOURCE_NOT_AVAILABLE');
    return source;
  }
}
