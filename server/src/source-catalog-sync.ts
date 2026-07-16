import type { AppConfig } from './config.js';
import { AppDatabase, type SourceCatalogRecord } from './database.js';
import { CatalogService } from './catalog-service.js';
import { parseAudioSourceContent } from './source-import.js';
import { errorCode, mapLimit } from './utils.js';
import type { SourceRecord } from './types.js';

const YCKCEO_CATALOG_URL = 'https://www.yckceo.com/yuedu/shuyuan/index.html?shengyin=1';
const AOAO_CATALOG_URL = 'https://legado.aoaostar.com/';
const DEFAULT_TEST_KEYWORD = '三国演义';
const FETCH_TIMEOUT_MS = 30000;
const MAX_CATALOG_BYTES = 20_000_000;

interface CatalogDefinition {
  id: string;
  name: string;
  pageUrl: string;
  fetch: () => Promise<ParsedBatch>;
}

interface ParsedBatch {
  sources: Record<string, unknown>[];
  total: number;
  rejected: number;
}

export interface CatalogSyncResult {
  id: string;
  name: string;
  ok: boolean;
  total: number;
  audio: number;
  rejected: number;
  imported: number;
  changed: number;
  enabled: number;
  errorCode: string | null;
  completedAt: string;
}

export interface SourceSyncSummary {
  trigger: 'startup' | 'scheduled' | 'manual';
  startedAt: string;
  completedAt: string;
  catalogs: CatalogSyncResult[];
}

function uniqueSources(batches: ParsedBatch[]): ParsedBatch {
  const byUrl = new Map<string, Record<string, unknown>>();
  let total = 0;
  let rejected = 0;
  for (const batch of batches) {
    total += batch.total;
    rejected += batch.rejected;
    for (const source of batch.sources) {
      const url = String(source.bookSourceUrl ?? '').trim();
      if (url && !byUrl.has(url)) byUrl.set(url, source);
    }
  }
  const sources = Array.from(byUrl.values());
  return { sources, total, rejected: Math.max(rejected, total - sources.length) };
}

export class SourceCatalogSyncService {
  private readonly catalogs: CatalogDefinition[];
  private initialTimer: NodeJS.Timeout | null = null;
  private scheduleTimer: NodeJS.Timeout | null = null;
  private running: Promise<SourceSyncSummary> | null = null;
  private remainingTestBudget = 0;

  constructor(
    private readonly db: AppDatabase,
    private readonly config: AppConfig,
    private readonly catalog: CatalogService
  ) {
    this.catalogs = [
      {
        id: 'yckceo_audio',
        name: 'YCKCEO 有声书源',
        pageUrl: YCKCEO_CATALOG_URL,
        fetch: async () => await this.fetchYckCeo()
      },
      {
        id: 'aoaostar_sources',
        name: 'AOAOSTAR 阅读源',
        pageUrl: AOAO_CATALOG_URL,
        fetch: async () => await this.fetchAoaoStar()
      },
      {
        id: 'yiove_sources',
        name: 'Yiove 书源仓库',
        pageUrl: 'https://shuyuan.yiove.com/book-sources?page=1&page_size=200',
        fetch: async () => await this.fetchYiove()
      }
    ];
    for (const definition of this.catalogs) {
      this.db.ensureSourceCatalog(definition.id, definition.name, definition.pageUrl);
    }
  }

  start(): void {
    if (!this.config.SOURCE_SYNC_ENABLED || this.config.NODE_ENV === 'test' || this.scheduleTimer) return;
    this.initialTimer = setTimeout(() => {
      this.syncAll('startup').catch(() => undefined);
      this.scheduleNext();
    }, 20_000);
    this.initialTimer.unref();
  }

  stop(): void {
    if (this.initialTimer) clearTimeout(this.initialTimer);
    if (this.scheduleTimer) clearTimeout(this.scheduleTimer);
    this.initialTimer = null;
    this.scheduleTimer = null;
  }

  async syncAll(trigger: 'startup' | 'scheduled' | 'manual' = 'manual'): Promise<SourceSyncSummary> {
    if (this.running) return await this.running;
    const task = this.runAll(trigger);
    this.running = task;
    try {
      return await task;
    } finally {
      this.running = null;
    }
  }

  listCatalogs(): SourceCatalogRecord[] {
    return this.db.listSourceCatalogs();
  }

  private scheduleNext(): void {
    if (!this.config.SOURCE_SYNC_ENABLED) return;
    const delay = this.msUntilNextChinaRun(new Date());
    this.scheduleTimer = setTimeout(() => {
      this.scheduleTimer = null;
      this.syncAll('scheduled').catch(() => undefined);
      this.scheduleNext();
    }, delay);
    this.scheduleTimer.unref();
  }

  private msUntilNextChinaRun(now: Date): number {
    const offsetMs = 8 * 60 * 60 * 1000;
    const shifted = new Date(now.getTime() + offsetMs);
    const targetShifted = Date.UTC(
      shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate(),
      this.config.SOURCE_SYNC_HOUR_CST, this.config.SOURCE_SYNC_MINUTE_CST, 0, 0
    );
    const currentShifted = shifted.getTime();
    const next = targetShifted > currentShifted ? targetShifted : targetShifted + 24 * 60 * 60 * 1000;
    return Math.max(1000, next - currentShifted);
  }

  private async runAll(trigger: 'startup' | 'scheduled' | 'manual'): Promise<SourceSyncSummary> {
    const startedAt = new Date().toISOString();
    this.remainingTestBudget = this.config.SOURCE_SYNC_TEST_LIMIT;
    const catalogs = await mapLimit(this.catalogs, 1, async (definition) =>
      await this.syncCatalog(definition));
    const completedAt = new Date().toISOString();
    this.db.audit('source.catalog_sync', 'all', JSON.stringify({ trigger, catalogs }));
    return { trigger, startedAt, completedAt, catalogs };
  }

  private async syncCatalog(definition: CatalogDefinition): Promise<CatalogSyncResult> {
    this.db.markSourceCatalogStarted(definition.id);
    try {
      const batch = await definition.fetch();
      const sourceResults = batch.sources.map((source) => this.db.syncLegadoSource(
        source, this.config.SOURCE_SYNC_TEST_KEYWORD || DEFAULT_TEST_KEYWORD
      ));
      let changed = 0;
      for (const result of sourceResults) {
        if (result.changed) changed++;
        this.db.linkSourceCatalog(definition.id, result.source.id);
      }
      if (changed > 0) this.db.clearCache();
      const enabled = await this.testAndEnable(sourceResults);
      const result: CatalogSyncResult = {
        id: definition.id,
        name: definition.name,
        ok: true,
        total: batch.total,
        audio: batch.sources.length,
        rejected: batch.rejected,
        imported: sourceResults.length,
        changed,
        enabled,
        errorCode: null,
        completedAt: new Date().toISOString()
      };
      this.db.markSourceCatalogFinished(definition.id, {
        ok: result.ok,
        total: result.total,
        audio: result.audio,
        rejected: result.rejected,
        imported: result.imported,
        changed: result.changed
      });
      this.db.audit('source.catalog_sync_ok', definition.id, JSON.stringify(result));
      return result;
    } catch (error) {
      const code = error instanceof Error ? error.message : errorCode(error);
      const result: CatalogSyncResult = {
        id: definition.id,
        name: definition.name,
        ok: false,
        total: 0,
        audio: 0,
        rejected: 0,
        imported: 0,
        changed: 0,
        enabled: 0,
        errorCode: code,
        completedAt: new Date().toISOString()
      };
      this.db.markSourceCatalogFinished(definition.id, { ...result, errorCode: code });
      this.db.audit('source.catalog_sync_failed', definition.id, code);
      return result;
    }
  }

  private async testAndEnable(results: Array<{ source: SourceRecord; created: boolean; changed: boolean }>): Promise<number> {
    if (this.remainingTestBudget <= 0) return 0;
    let enabledCount = this.db.listSources(true).filter((source) => source.kind === 'legado').length;
    let enabled = 0;
    const candidates = results.filter((result) => result.created || result.changed ||
      (!result.source.enabled && result.source.state === 'unknown')).slice(0, this.remainingTestBudget);
    this.remainingTestBudget -= candidates.length;
    for (const result of candidates) {
      if (!result.source.enabled && enabledCount >= this.config.SOURCE_SYNC_MAX_ENABLED) continue;
      const outcome = await this.catalog.testSource(result.source, this.config.SOURCE_SYNC_TEST_KEYWORD);
      if (outcome.ok && outcome.items.length > 0 && !result.source.enabled) {
        this.db.updateSource(result.source.id, { enabled: true, priority: 30 + enabledCount });
        enabledCount++;
        enabled++;
      }
    }
    return enabled;
  }

  private async fetchYckCeo(): Promise<ParsedBatch> {
    const html = await this.fetchText(YCKCEO_CATALOG_URL);
    const ids = new Set<string>();
    const pattern = /name="ids\[\]"[^>]*value="(\d+)"/gi;
    for (const match of html.matchAll(pattern)) {
      if (match[1]) ids.add(match[1]);
    }
    if (ids.size === 0) throw new Error('YCKCEO_NO_AUDIO_ENTRIES');
    const batches = await mapLimit(Array.from(ids), Math.min(4, this.config.SOURCE_CONCURRENCY), async (id) => {
      try {
        const content = await this.fetchText(`https://www.yckceo.com/yuedu/shuyuan/json/id/${id}.json`);
        return parseAudioSourceContent(content, 10000);
      } catch (_error) {
        return { sources: [], total: 1, rejected: 1 };
      }
    });
    return uniqueSources(batches);
  }

  private async fetchAoaoStar(): Promise<ParsedBatch> {
    const html = await this.fetchText(AOAO_CATALOG_URL);
    const bookSectionEnd = html.indexOf('<h2 id="id_1">');
    const bookSection = bookSectionEnd > 0 ? html.substring(0, bookSectionEnd) : html;
    const urls = new Set<string>();
    const pattern = /https:\/\/legado\.aoaostar\.com\/sources\/[a-z0-9]+\.json/gi;
    for (const match of bookSection.matchAll(pattern)) {
      if (match[0]) urls.add(match[0]);
    }
    if (urls.size === 0) throw new Error('AOAOSTAR_NO_SOURCE_LINKS');
    const orderedUrls = Array.from(urls);
    try {
      const primaryContent = await this.fetchText(orderedUrls[0]!);
      const primary = parseAudioSourceContent(primaryContent, 10000);
      if (primary.sources.length > 0) return primary;
    } catch (_error) { /* fall back to the remaining curated collections */ }
    const batches = await mapLimit(orderedUrls.slice(1), Math.min(4, this.config.SOURCE_CONCURRENCY), async (url) => {
      try {
        const content = await this.fetchText(url);
        return parseAudioSourceContent(content, 10000);
      } catch (_error) {
        return { sources: [], total: 1, rejected: 1 };
      }
    });
    return uniqueSources(batches);
  }

  private async fetchYiove(): Promise<ParsedBatch> {
    const configured = this.config.SOURCE_CATALOG_YIOVE_IMPORT_URL;
    const match = configured.match(/^(.*\/)(\d+)-(\d+)$/);
    const urls = match ? [`${match[1]!}1-100`, `${match[1]!}2-100`] : [configured];
    const batches = await mapLimit(urls, 2, async (url) => {
      const content = await this.fetchText(url);
      return parseAudioSourceContent(content, 10000);
    });
    return uniqueSources(batches);
  }

  private async fetchText(url: string): Promise<string> {
    const response = await fetch(url, {
      headers: {
        Accept: 'application/json,text/plain;q=0.9,text/html;q=0.8',
        'User-Agent': 'JianHuanSourceSync/1.0 (+https://121.196.223.85)'
      },
      redirect: 'follow',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)
    });
    const contentLength = Number(response.headers.get('content-length') ?? 0);
    if (contentLength > MAX_CATALOG_BYTES) throw new Error('CATALOG_FILE_TOO_LARGE');
    const text = await response.text();
    if (text.length > MAX_CATALOG_BYTES) throw new Error('CATALOG_FILE_TOO_LARGE');
    if (!response.ok) {
      if (text.includes('Just a moment') || text.includes('cf-chl-')) {
        throw new Error('CATALOG_CLOUDFLARE_BLOCKED');
      }
      throw new Error(`CATALOG_HTTP_${response.status}`);
    }
    return text;
  }
}
