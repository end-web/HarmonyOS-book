import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { CatalogService } from '../src/catalog-service.js';
import type { AppConfig } from '../src/config.js';
import { AppDatabase } from '../src/database.js';
import type { ReaderClient } from '../src/providers/reader-client.js';

const directories: string[] = [];

afterEach(() => {
  for (const directory of directories.splice(0)) fs.rmSync(directory, { recursive: true, force: true });
});

function createConfig(): AppConfig {
  return { NODE_ENV: 'test', SOURCE_CONCURRENCY: 1, SOURCE_TIMEOUT_MS: 1000 } as AppConfig;
}

function createSource(db: AppDatabase) {
  return db.upsertLegadoSource({
    bookSourceName: 'Validation source',
    bookSourceUrl: 'https://source.example.com',
    bookSourceType: 1
  }, false, 'demo');
}

describe('catalog source validation', () => {
  it('requires a searchable result, chapters, and a resolved first audio URL', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-validation-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const post = vi.fn(async (pathname: string) => {
      if (pathname === '/reader3/searchBook') {
        return [{ bookUrl: 'https://source.example.com/book', name: 'Demo book' }];
      }
      if (pathname === '/reader3/getBookInfo') {
        return { bookUrl: 'https://source.example.com/book', name: 'Demo book' };
      }
      if (pathname === '/reader3/getChapterList') {
        return [{ url: 'https://source.example.com/chapter/1', title: 'Chapter 1' }];
      }
      if (pathname === '/reader3/getBookContent') return 'https://audio.example.com/chapter-1.mp3';
      throw new Error(`Unexpected reader path: ${pathname}`);
    });
    const catalog = new CatalogService(db, createConfig(), { post } as unknown as ReaderClient);

    const outcome = await catalog.validateSource(createSource(db), 'demo');

    expect(outcome).toMatchObject({ ok: true, stage: 'resolve' });
    expect(post).toHaveBeenCalledWith('/reader3/getBookContent', expect.objectContaining({ index: 0 }));
    db.close();
  }, 15000);

  it('rejects a source that searches successfully but has no chapters', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-validation-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const post = vi.fn(async (pathname: string) => {
      if (pathname === '/reader3/searchBook') {
        return [{ bookUrl: 'https://source.example.com/book', name: 'Demo book' }];
      }
      if (pathname === '/reader3/getBookInfo') {
        return { bookUrl: 'https://source.example.com/book', name: 'Demo book' };
      }
      if (pathname === '/reader3/getChapterList') return [];
      throw new Error(`Unexpected reader path: ${pathname}`);
    });
    const catalog = new CatalogService(db, createConfig(), { post } as unknown as ReaderClient);

    const outcome = await catalog.validateSource(createSource(db), 'demo');

    expect(outcome).toMatchObject({ ok: false, stage: 'chapters', errorCode: 'SOURCE_EMPTY' });
    expect(post).not.toHaveBeenCalledWith('/reader3/getBookContent', expect.anything());
    db.close();
  }, 15000);
});
