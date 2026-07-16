import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { afterEach, describe, expect, it } from 'vitest';
import { AppDatabase } from '../src/database.js';

const directories: string[] = [];

afterEach(() => {
  for (const directory of directories.splice(0)) fs.rmSync(directory, { recursive: true, force: true });
});

describe('catalog database', () => {
  it('seeds the public-domain source and persists books and chapters', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-db-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const source = db.getSource('podcast_apple');
    expect(source?.enabled).toBe(true);
    const book = db.upsertBook({
      sourceId: source!.id, sourceName: source!.name, externalId: 'demo', title: 'Demo', author: 'Author',
      narrator: 'Reader', cover: '', intro: '', category: 'Public domain', latestChapter: '', language: 'English', raw: {}
    });
    const chapters = db.replaceChapters(book, [{ externalId: 'one.mp3', title: 'One', index: 0, duration: 10, raw: {} }]);
    expect(db.getBook(book.id)?.chapterCount).toBe(1);
    expect(db.getChapter(chapters[0]!.id)?.duration).toBe(10);
    db.close();
  });

  it('preserves manual enablement and avoids duplicate versions on unchanged syncs', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-sync-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const config = {
      bookSourceName: 'Audio sync',
      bookSourceUrl: 'https://audio.example.com',
      bookSourceType: 1,
      searchUrl: 'https://audio.example.com/search?q={{key}}'
    };
    const first = db.syncLegadoSource(config, 'demo');
    expect(first.created).toBe(true);
    db.updateSource(first.source.id, { enabled: true });
    const second = db.syncLegadoSource(config, 'demo');
    expect(second.changed).toBe(false);
    expect(second.source.enabled).toBe(true);
    const versions = (db.db.prepare('SELECT COUNT(*) AS count FROM source_versions WHERE source_id = ?')
      .get(first.source.id) as { count: number }).count;
    expect(versions).toBe(1);
    db.close();
  });

  it('upgrades the source kind constraint without losing existing sources, books or chapters', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-migration-'));
    directories.push(directory);
    const filename = path.join(directory, 'legacy.db');
    const legacy = new DatabaseSync(filename);
    legacy.exec(`
      PRAGMA foreign_keys = ON;
      CREATE TABLE sources (
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
      CREATE UNIQUE INDEX idx_sources_kind_url ON sources(kind, source_url);
      CREATE TABLE books (
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
      CREATE TABLE chapters (
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
      INSERT INTO sources VALUES (
        'legacy_source', 'legado', '旧音频源', 'https://legacy.example.com', 1, 100, 'healthy', '测试', '{}',
        0, 3, 1, 120, '2026-07-15T00:00:00.000Z', '2026-07-14T00:00:00.000Z', NULL,
        '2026-07-01T00:00:00.000Z', '2026-07-15T00:00:00.000Z'
      );
      INSERT INTO books VALUES (
        'legacy_book', 'legacy_source', 'book-url', '旧书', '作者', '播音', '', '', '有声书', '', '中文',
        1, 60, '{}', '2026-07-15T00:00:00.000Z'
      );
      INSERT INTO chapters VALUES (
        'legacy_chapter', 'legacy_book', 'chapter-url', '第1集', 0, 60, '{}', '2026-07-15T00:00:00.000Z'
      );
    `);
    legacy.close();

    const db = new AppDatabase(filename);
    const added = db.ensureGuoweiSource('https://api.example.com/', true);

    expect(db.getSource('legacy_source')).toMatchObject({ name: '旧音频源', successCount: 3, failureCount: 1 });
    expect(db.getBook('legacy_book')).toMatchObject({ title: '旧书', chapterCount: 1 });
    expect(db.getChapter('legacy_chapter')).toMatchObject({ title: '第1集', duration: 60 });
    expect(added).toMatchObject({ kind: 'guowei', name: '免费听书王', enabled: true, testKeyword: '万古天帝' });
    const schema = db.db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sources'")
      .get() as { sql: string };
    expect(schema.sql).toContain("'guowei'");
    expect(db.db.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    db.close();
  });
});
