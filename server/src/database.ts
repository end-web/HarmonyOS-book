import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { AudioBook, AudioBookCandidate, AudioChapter, AudioChapterCandidate, SourceRecord, SourceState } from './types.js';
import { stableId } from './utils.js';

interface SourceRow {
  id: string;
  kind: 'archive' | 'podcast' | 'legado';
  name: string;
  source_url: string;
  enabled: number;
  priority: number;
  state: SourceState;
  test_keyword: string;
  config_json: string;
  consecutive_failures: number;
  success_count: number;
  failure_count: number;
  last_latency_ms: number | null;
  last_success_at: string | null;
  last_failure_at: string | null;
  last_error_code: string | null;
  created_at: string;
  updated_at: string;
}

interface BookRow {
  id: string;
  source_id: string;
  external_id: string;
  title: string;
  author: string;
  narrator: string;
  cover: string;
  intro: string;
  category: string;
  latest_chapter: string;
  language: string;
  chapter_count: number;
  total_duration: number;
  raw_json: string;
}

interface ChapterRow {
  id: string;
  book_id: string;
  external_id: string;
  title: string;
  chapter_index: number;
  duration: number;
  raw_json: string;
}

export class AppDatabase {
  readonly db: DatabaseSync;

  constructor(filename: string) {
    fs.mkdirSync(path.dirname(path.resolve(filename)), { recursive: true });
    this.db = new DatabaseSync(filename);
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
    this.migrate();
    this.seedArchiveSource();
  }

  close(): void {
    this.db.close();
  }

  private transaction<T>(action: () => T): T {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const result = action();
      this.db.exec('COMMIT');
      return result;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sources (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK(kind IN ('archive', 'podcast', 'legado')),
        name TEXT NOT NULL,
        source_url TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 100,
        state TEXT NOT NULL DEFAULT 'unknown',
        test_keyword TEXT NOT NULL DEFAULT '',
        config_json TEXT NOT NULL DEFAULT '{}',
        consecutive_failures INTEGER NOT NULL DEFAULT 0,
        success_count INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_latency_ms INTEGER,
        last_success_at TEXT,
        last_failure_at TEXT,
        last_error_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sources_kind_url ON sources(kind, source_url);

      CREATE TABLE IF NOT EXISTS source_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        version INTEGER NOT NULL,
        config_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(source_id, version)
      );

      CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        external_id TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        narrator TEXT NOT NULL,
        cover TEXT NOT NULL,
        intro TEXT NOT NULL,
        category TEXT NOT NULL,
        latest_chapter TEXT NOT NULL,
        language TEXT NOT NULL,
        chapter_count INTEGER NOT NULL DEFAULT 0,
        total_duration INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(source_id, external_id)
      );

      CREATE TABLE IF NOT EXISTS chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        external_id TEXT NOT NULL,
        title TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        duration INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(book_id, external_id)
      );

      CREATE TABLE IF NOT EXISTS cache_entries (
        cache_key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        stale_until INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS health_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        ok INTEGER NOT NULL,
        latency_ms INTEGER NOT NULL,
        error_code TEXT,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_health_source_created ON health_events(source_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        target TEXT NOT NULL,
        detail TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    `);
  }

  private seedArchiveSource(): void {
    const now = new Date().toISOString();
    this.db.prepare(`
      INSERT INTO sources (id, kind, name, source_url, enabled, priority, state, test_keyword, config_json, created_at, updated_at)
      VALUES ('archive_librivox', 'archive', 'LibriVox 公版有声书', 'https://archive.org/details/librivoxaudio', 0, 20, 'unknown', 'Alice', '{}', ?, ?)
      ON CONFLICT(id) DO NOTHING
    `).run(now, now);
    this.db.prepare(`
      INSERT INTO sources (id, kind, name, source_url, enabled, priority, state, test_keyword, config_json, created_at, updated_at)
      VALUES ('podcast_apple', 'podcast', '开放播客目录', 'https://itunes.apple.com/search', 1, 5, 'unknown', '三国演义', '{}', ?, ?)
      ON CONFLICT(id) DO NOTHING
    `).run(now, now);
  }

  private sourceFromRow(row: SourceRow): SourceRecord {
    return {
      id: row.id,
      kind: row.kind,
      name: row.name,
      sourceUrl: row.source_url,
      enabled: row.enabled === 1,
      priority: row.priority,
      state: row.state,
      testKeyword: row.test_keyword,
      config: JSON.parse(row.config_json) as Record<string, unknown>,
      consecutiveFailures: row.consecutive_failures,
      successCount: row.success_count,
      failureCount: row.failure_count,
      lastLatencyMs: row.last_latency_ms,
      lastSuccessAt: row.last_success_at,
      lastFailureAt: row.last_failure_at,
      lastErrorCode: row.last_error_code,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }

  listSources(enabledOnly = false): SourceRecord[] {
    const sql = `SELECT * FROM sources ${enabledOnly ? 'WHERE enabled = 1' : ''} ORDER BY priority ASC, name ASC`;
    return (this.db.prepare(sql).all() as unknown as SourceRow[]).map((row) => this.sourceFromRow(row));
  }

  getSource(id: string): SourceRecord | null {
    const row = this.db.prepare('SELECT * FROM sources WHERE id = ?').get(id) as SourceRow | undefined;
    return row ? this.sourceFromRow(row) : null;
  }

  upsertLegadoSource(config: Record<string, unknown>, enabled: boolean, testKeyword: string): SourceRecord {
    const sourceUrl = String(config.bookSourceUrl ?? '').trim();
    const name = String(config.bookSourceName ?? '').trim();
    const id = stableId('legado', sourceUrl);
    const now = new Date().toISOString();
    const existing = this.getSource(id);
    const version = Number((this.db.prepare('SELECT MAX(version) AS value FROM source_versions WHERE source_id = ?').get(id) as { value: number | null } | undefined)?.value ?? 0) + 1;
    const configJson = JSON.stringify(config);
    this.transaction(() => {
      this.db.prepare(`
        INSERT INTO sources (id, kind, name, source_url, enabled, priority, state, test_keyword, config_json, created_at, updated_at)
        VALUES (?, 'legado', ?, ?, ?, 100, 'unknown', ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name = excluded.name, source_url = excluded.source_url,
          enabled = excluded.enabled, test_keyword = excluded.test_keyword, config_json = excluded.config_json,
          state = 'unknown', updated_at = excluded.updated_at
      `).run(id, name, sourceUrl, enabled ? 1 : 0, testKeyword, configJson, existing?.createdAt ?? now, now);
      this.db.prepare('INSERT INTO source_versions (source_id, version, config_json, created_at) VALUES (?, ?, ?, ?)')
        .run(id, version, configJson, now);
    });
    return this.getSource(id)!;
  }

  updateSource(id: string, input: {
    enabled?: boolean | undefined;
    name?: string | undefined;
    priority?: number | undefined;
    testKeyword?: string | undefined;
  }): SourceRecord | null {
    const current = this.getSource(id);
    if (!current) return null;
    const now = new Date().toISOString();
    this.db.prepare(`
      UPDATE sources SET enabled = ?, name = ?, priority = ?, test_keyword = ?, updated_at = ? WHERE id = ?
    `).run(input.enabled === undefined ? Number(current.enabled) : Number(input.enabled), input.name ?? current.name,
      input.priority ?? current.priority, input.testKeyword ?? current.testKeyword, now, id);
    return this.getSource(id);
  }

  deleteSource(id: string): boolean {
    const source = this.getSource(id);
    if (!source || source.kind === 'archive') return false;
    return Number(this.db.prepare('DELETE FROM sources WHERE id = ?').run(id).changes) > 0;
  }

  recordHealth(sourceId: string, ok: boolean, latencyMs: number, code?: string): void {
    const source = this.getSource(sourceId);
    if (!source) return;
    const now = new Date().toISOString();
    const failures = ok ? 0 : source.consecutiveFailures + 1;
    const state: SourceState = ok ? 'healthy' : failures >= 3 ? 'down' : 'degraded';
    this.transaction(() => {
      this.db.prepare(`
        UPDATE sources SET state = ?, consecutive_failures = ?, success_count = success_count + ?,
          failure_count = failure_count + ?, last_latency_ms = ?, last_success_at = ?, last_failure_at = ?,
          last_error_code = ?, updated_at = ? WHERE id = ?
      `).run(state, failures, ok ? 1 : 0, ok ? 0 : 1, latencyMs, ok ? now : source.lastSuccessAt,
        ok ? source.lastFailureAt : now, ok ? null : (code ?? 'SOURCE_ERROR'), now, sourceId);
      this.db.prepare('INSERT INTO health_events (source_id, ok, latency_ms, error_code, created_at) VALUES (?, ?, ?, ?, ?)')
        .run(sourceId, ok ? 1 : 0, latencyMs, ok ? null : (code ?? 'SOURCE_ERROR'), now);
      this.db.prepare(`DELETE FROM health_events WHERE id IN (
        SELECT id FROM health_events WHERE source_id = ? ORDER BY id DESC LIMIT -1 OFFSET 240
      )`).run(sourceId);
    });
  }

  healthHistory(sourceId: string, limit = 24): Array<{ ok: boolean; latencyMs: number; errorCode: string | null; createdAt: string }> {
    const rows = this.db.prepare(`
      SELECT ok, latency_ms, error_code, created_at FROM health_events WHERE source_id = ? ORDER BY id DESC LIMIT ?
    `).all(sourceId, limit) as Array<{ ok: number; latency_ms: number; error_code: string | null; created_at: string }>;
    return rows.reverse().map((row) => ({ ok: row.ok === 1, latencyMs: row.latency_ms, errorCode: row.error_code, createdAt: row.created_at }));
  }

  upsertBook(candidate: AudioBookCandidate): AudioBook {
    const id = stableId('book', candidate.sourceId, candidate.externalId);
    const existing = this.getBook(id);
    const now = new Date().toISOString();
    this.db.prepare(`
      INSERT INTO books (id, source_id, external_id, title, author, narrator, cover, intro, category,
        latest_chapter, language, chapter_count, total_duration, raw_json, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET title = excluded.title, author = excluded.author,
        narrator = excluded.narrator, cover = excluded.cover, intro = excluded.intro,
        category = excluded.category, latest_chapter = excluded.latest_chapter,
        language = excluded.language, raw_json = excluded.raw_json, updated_at = excluded.updated_at
    `).run(id, candidate.sourceId, candidate.externalId, candidate.title, candidate.author, candidate.narrator,
      candidate.cover, candidate.intro, candidate.category, candidate.latestChapter, candidate.language,
      existing?.chapterCount ?? 0, existing?.totalDuration ?? 0, JSON.stringify(candidate.raw), now);
    return this.getBook(id)!;
  }

  getBook(id: string): AudioBook | null {
    const row = this.db.prepare('SELECT * FROM books WHERE id = ?').get(id) as BookRow | undefined;
    if (!row) return null;
    return {
      id: row.id,
      sourceId: row.source_id,
      sourceName: this.getSource(row.source_id)?.name ?? '',
      externalId: row.external_id,
      title: row.title,
      author: row.author,
      narrator: row.narrator,
      cover: row.cover,
      intro: row.intro,
      category: row.category,
      latestChapter: row.latest_chapter,
      language: row.language,
      chapterCount: row.chapter_count,
      totalDuration: row.total_duration,
      raw: JSON.parse(row.raw_json) as Record<string, unknown>
    };
  }

  replaceChapters(book: AudioBook, chapters: AudioChapterCandidate[]): AudioChapter[] {
    const now = new Date().toISOString();
    const output: AudioChapter[] = [];
    this.transaction(() => {
      this.db.prepare('DELETE FROM chapters WHERE book_id = ?').run(book.id);
      const insert = this.db.prepare(`
        INSERT INTO chapters (id, book_id, external_id, title, chapter_index, duration, raw_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `);
      for (const chapter of chapters) {
        const id = stableId('chapter', book.id, chapter.externalId);
        insert.run(id, book.id, chapter.externalId, chapter.title, chapter.index, chapter.duration,
          JSON.stringify(chapter.raw), now);
        output.push({ ...chapter, id, bookId: book.id });
      }
      const totalDuration = chapters.reduce((sum, item) => sum + Math.max(0, item.duration), 0);
      this.db.prepare('UPDATE books SET chapter_count = ?, total_duration = ?, updated_at = ? WHERE id = ?')
        .run(chapters.length, totalDuration, now, book.id);
    });
    return output;
  }

  listChapters(bookId: string): AudioChapter[] {
    const rows = this.db.prepare('SELECT * FROM chapters WHERE book_id = ? ORDER BY chapter_index ASC')
      .all(bookId) as unknown as ChapterRow[];
    return rows.map((row) => ({
      id: row.id,
      bookId: row.book_id,
      externalId: row.external_id,
      title: row.title,
      index: row.chapter_index,
      duration: row.duration,
      raw: JSON.parse(row.raw_json) as Record<string, unknown>
    }));
  }

  getChapter(id: string): AudioChapter | null {
    const row = this.db.prepare('SELECT * FROM chapters WHERE id = ?').get(id) as ChapterRow | undefined;
    if (!row) return null;
    return {
      id: row.id,
      bookId: row.book_id,
      externalId: row.external_id,
      title: row.title,
      index: row.chapter_index,
      duration: row.duration,
      raw: JSON.parse(row.raw_json) as Record<string, unknown>
    };
  }

  getCache<T>(key: string, allowStale = false): T | null {
    const row = this.db.prepare('SELECT value_json, expires_at, stale_until FROM cache_entries WHERE cache_key = ?').get(key) as
      { value_json: string; expires_at: number; stale_until: number } | undefined;
    if (!row) return null;
    const deadline = allowStale ? row.stale_until : row.expires_at;
    if (Date.now() > deadline) return null;
    return JSON.parse(row.value_json) as T;
  }

  putCache(key: string, value: unknown, ttlSeconds: number, staleSeconds = 86400): void {
    const now = Date.now();
    this.db.prepare(`
      INSERT INTO cache_entries (cache_key, value_json, expires_at, stale_until, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(cache_key) DO UPDATE SET value_json = excluded.value_json, expires_at = excluded.expires_at,
        stale_until = excluded.stale_until, updated_at = excluded.updated_at
    `).run(key, JSON.stringify(value), now + ttlSeconds * 1000, now + (ttlSeconds + staleSeconds) * 1000,
      new Date(now).toISOString());
  }

  clearCache(): number {
    return Number(this.db.prepare('DELETE FROM cache_entries').run().changes);
  }

  audit(action: string, target: string, detail: string): void {
    this.db.prepare('INSERT INTO audit_logs (action, target, detail, created_at) VALUES (?, ?, ?, ?)')
      .run(action, target, detail.slice(0, 1000), new Date().toISOString());
  }

  listAuditLogs(limit = 100): Array<{ id: number; action: string; target: string; detail: string; createdAt: string }> {
    const rows = this.db.prepare('SELECT * FROM audit_logs ORDER BY id DESC LIMIT ?').all(limit) as
      Array<{ id: number; action: string; target: string; detail: string; created_at: string }>;
    return rows.map((row) => ({ id: row.id, action: row.action, target: row.target, detail: row.detail, createdAt: row.created_at }));
  }

  summary(): { sourceCount: number; healthy: number; degraded: number; down: number; cachedBooks: number; cachedChapters: number } {
    const sourceRows = this.db.prepare(`
      SELECT COUNT(*) AS total,
        SUM(CASE WHEN state = 'healthy' THEN 1 ELSE 0 END) AS healthy,
        SUM(CASE WHEN state = 'degraded' THEN 1 ELSE 0 END) AS degraded,
        SUM(CASE WHEN state = 'down' THEN 1 ELSE 0 END) AS down
      FROM sources WHERE enabled = 1
    `).get() as { total: number; healthy: number | null; degraded: number | null; down: number | null };
    const books = (this.db.prepare('SELECT COUNT(*) AS count FROM books').get() as { count: number }).count;
    const chapters = (this.db.prepare('SELECT COUNT(*) AS count FROM chapters').get() as { count: number }).count;
    return {
      sourceCount: sourceRows.total,
      healthy: sourceRows.healthy ?? 0,
      degraded: sourceRows.degraded ?? 0,
      down: sourceRows.down ?? 0,
      cachedBooks: books,
      cachedChapters: chapters
    };
  }
}
