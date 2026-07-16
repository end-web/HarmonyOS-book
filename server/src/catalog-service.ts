import type { AppConfig } from './config.js';
import type { AppDatabase } from './database.js';
import type {
  AudioBook, AudioBookCandidate, AudioChapter, AudioResolution, SearchOutcome, SourceProvider, SourceRecord
} from './types.js';
import { errorCode, mapLimit, stableId, withTimeout } from './utils.js';
import { ArchiveProvider } from './providers/archive-provider.js';
import { GuoweiProvider } from './providers/guowei-provider.js';
import { LegadoProvider } from './providers/legado-provider.js';
import { PodcastProvider } from './providers/podcast-provider.js';
import type { ReaderClient } from './providers/reader-client.js';

const SOURCE_VALIDATION_SAMPLE_SIZE = 3;
const AUDIO_PROBE_TIMEOUT_MS = 15000;

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

interface CandidateValidationSuccess {
  ok: true;
  stage: 'resolve';
}

interface CandidateValidationFailure {
  ok: false;
  stage: 'detail' | 'chapters' | 'resolve';
  errorCode: string;
}

type CandidateValidationOutcome = CandidateValidationSuccess | CandidateValidationFailure;

export class CatalogService {
  private readonly providers: Record<SourceRecord['kind'], SourceProvider>;
  private healthTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly db: AppDatabase,
    private readonly config: AppConfig,
    reader: ReaderClient
  ) {
    this.providers = {
      archive: new ArchiveProvider(),
      podcast: new PodcastProvider(),
      legado: new LegadoProvider(reader),
      guowei: new GuoweiProvider({
        baseUrl: config.GUOWEI_API_BASE_URL ?? 'https://yssapi.guoweitech.com/',
        signingKey: config.GUOWEI_SIGNING_KEY ?? '',
        timeoutMs: config.SOURCE_TIMEOUT_MS
      })
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
  async validateSource(source: SourceRecord, keyword?: string, quarantineOnFailure = false): Promise<SourceValidationOutcome> {
    const started = Date.now();
    const search = await this.searchSource(source, (keyword || source.testKeyword || 'Alice').trim(), 1);
    if (!search.ok) {
      const outcome: SourceValidationOutcome = {
        ok: false,
        stage: 'search',
        latencyMs: Date.now() - started,
        errorCode: search.errorCode ?? 'SOURCE_ERROR'
      };
      if (quarantineOnFailure) this.quarantineSource(source, outcome.errorCode ?? 'SOURCE_ERROR', outcome.stage);
      return outcome;
    }
    const sampleSize = source.kind === 'guowei' ? 1 : SOURCE_VALIDATION_SAMPLE_SIZE;
    const candidates = search.items.slice(0, sampleSize);
    if (candidates.length === 0) {
      const latencyMs = Date.now() - started;
      this.db.recordHealth(source.id, false, latencyMs, 'SOURCE_EMPTY');
      const outcome: SourceValidationOutcome = { ok: false, stage: 'search', latencyMs, errorCode: 'SOURCE_EMPTY' };
      if (quarantineOnFailure) this.quarantineSource(source, outcome.errorCode ?? 'SOURCE_EMPTY', outcome.stage);
      return outcome;
    }

    for (const candidate of candidates) {
      const candidateOutcome = await this.validateCandidate(source, candidate);
      if (candidateOutcome.ok) continue;
      const latencyMs = Date.now() - started;
      this.db.recordHealth(source.id, false, latencyMs, candidateOutcome.errorCode);
      const outcome: SourceValidationOutcome = {
        ok: false,
        stage: candidateOutcome.stage,
        latencyMs,
        errorCode: candidateOutcome.errorCode
      };
      if (quarantineOnFailure) this.quarantineSource(source, candidateOutcome.errorCode, candidateOutcome.stage);
      return outcome;
    }
    return { ok: true, stage: 'resolve', latencyMs: Date.now() - started };
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
      this.reportRuntimeFailure(source, 'chapters', error);
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
    try {
      const resolution = await withTimeout(
        this.providers[source.kind].resolve(source, book, chapter),
        Math.max(this.config.SOURCE_TIMEOUT_MS, 30000),
        'AUDIO_RESOLVE_TIMEOUT'
      );
      if (source.kind === 'legado' || source.kind === 'guowei') await this.probeAudioResolution(resolution);
      return resolution;
    } catch (error) {
      this.reportRuntimeFailure(source, 'resolve', error);
      throw error;
    }
  }

  async checkAllSources(): Promise<void> {
    const sources = this.db.listSources(true);
    await mapLimit(sources, Math.min(2, this.config.SOURCE_CONCURRENCY), async (source) => {
      await this.validateSource(source, source.testKeyword, true);
    });
  }

  private async validateCandidate(source: SourceRecord, candidate: AudioBookCandidate): Promise<CandidateValidationOutcome> {
    const provider = this.providers[source.kind];
    let stage: CandidateValidationFailure['stage'] = 'detail';
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
      await this.probeAudioResolution(resolution);
      return { ok: true, stage: 'resolve' };
    } catch (error) {
      return { ok: false, stage, errorCode: errorCode(error) };
    }
  }

  private async probeAudioResolution(resolution: AudioResolution): Promise<void> {
    const headers: Record<string, string> = {
      Accept: 'audio/*,application/vnd.apple.mpegurl,application/x-mpegurl;q=0.9,*/*;q=0.1',
      Range: 'bytes=0-4095'
    };
    for (const [key, value] of Object.entries(resolution.headers)) {
      const lower = key.toLowerCase();
      if (lower === 'host' || lower === 'content-length' || lower === 'range' || !value) continue;
      headers[key] = value;
    }
    const response = await withTimeout(fetch(resolution.url, {
      headers,
      redirect: 'follow',
      signal: AbortSignal.timeout(AUDIO_PROBE_TIMEOUT_MS)
    }), AUDIO_PROBE_TIMEOUT_MS + 1000, 'AUDIO_PROBE_TIMEOUT');
    if (!response.ok) throw new Error(`AUDIO_PROBE_HTTP_${response.status}`);

    const finalUrl = response.url || resolution.url;
    const pathname = new URL(finalUrl).pathname.toLowerCase();
    const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
    const isHls = resolution.format === 'hls' || pathname.endsWith('.m3u8') ||
      contentType.includes('mpegurl') || contentType.includes('vnd.apple.mpegurl');
    if (isHls) {
      const manifest = await withTimeout(response.text(), AUDIO_PROBE_TIMEOUT_MS, 'AUDIO_PROBE_TIMEOUT');
      if (!manifest.includes('#EXTM3U')) throw new Error('AUDIO_PROBE_INVALID_HLS');
      return;
    }
    if (contentType.includes('text/html') || contentType.includes('application/json')) {
      throw new Error('AUDIO_PROBE_NOT_AUDIO');
    }
    await response.body?.cancel();
  }

  private reportRuntimeFailure(source: SourceRecord, stage: 'chapters' | 'resolve', error: unknown): void {
    const code = errorCode(error);
    this.db.recordHealth(source.id, false, 0, code);
    this.quarantineSource(source, code, stage);
  }

  private quarantineSource(source: SourceRecord, errorCode: string, stage: SourceValidationOutcome['stage']): void {
    if ((source.kind !== 'legado' && source.kind !== 'guowei') || !source.enabled ||
      errorCode === 'SOURCE_TIMEOUT' || errorCode === 'SOURCE_UPSTREAM_ERROR') return;
    const current = this.db.getSource(source.id);
    if (!current || !current.enabled) return;
    this.db.updateSource(source.id, { enabled: false });
    this.db.clearCache();
    this.db.audit('source.quarantined', source.id, JSON.stringify({
      name: source.name,
      stage,
      errorCode
    }));
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
