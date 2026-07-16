import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
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
});
