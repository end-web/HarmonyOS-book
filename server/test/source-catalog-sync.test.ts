import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { CatalogService } from '../src/catalog-service.js';
import type { AppConfig } from '../src/config.js';
import { AppDatabase } from '../src/database.js';
import { SourceCatalogSyncService } from '../src/source-catalog-sync.js';

const directories: string[] = [];

afterEach(() => {
  vi.unstubAllGlobals();
  for (const directory of directories.splice(0)) fs.rmSync(directory, { recursive: true, force: true });
});

describe('source catalog sync', () => {
  it('strictly retests and enables a healthy source left disabled by an earlier sync', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-catalog-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const source = db.upsertLegadoSource({
      bookSourceName: 'Healthy disabled source',
      bookSourceUrl: 'https://healthy.example.com',
      bookSourceType: 1
    }, false, '三国演义');
    db.recordHealth(source.id, true, 12);
    const healthySource = db.getSource(source.id)!;
    const validateSource = vi.fn(async () => ({ ok: true, stage: 'resolve' as const, latencyMs: 1 }));
    const config = {
      SOURCE_SYNC_TEST_LIMIT: 10,
      SOURCE_SYNC_MAX_ENABLED: 16,
      SOURCE_SYNC_TEST_KEYWORD: '三国演义',
      SOURCE_CONCURRENCY: 4,
      SOURCE_SYNC_FETCH_TIMEOUT_MS: 120000
    } as AppConfig;
    const service = new SourceCatalogSyncService(
      db,
      config,
      { validateSource } as unknown as CatalogService
    );
    const internals = service as unknown as {
      remainingTestBudget: number;
      testAndEnable(results: Array<{
        source: typeof healthySource;
        created: boolean;
        changed: boolean;
      }>): Promise<number>;
    };
    internals.remainingTestBudget = config.SOURCE_SYNC_TEST_LIMIT;

    const enabled = await internals.testAndEnable([{
      source: healthySource,
      created: false,
      changed: false
    }]);

    expect(enabled).toBe(1);
    expect(validateSource).toHaveBeenCalledWith(healthySource, '三国演义', true);
    expect(db.getSource(source.id)?.enabled).toBe(true);
    db.close();
  });

  it('merges every AOAOSTAR audio collection instead of stopping at the first match', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jianhu-catalog-'));
    directories.push(directory);
    const db = new AppDatabase(path.join(directory, 'test.db'));
    const urls = [
      'https://legado.aoaostar.com/sources/11111111.json',
      'https://legado.aoaostar.com/sources/22222222.json',
      'https://legado.aoaostar.com/sources/33333333.json'
    ];
    const html = `${urls.join('\n')}<h2 id="id_1">文本源</h2>`;
    const first = [{ bookSourceName: 'Audio A', bookSourceUrl: 'https://audio-a.example.com', bookSourceType: 1 }];
    const second = [
      ...first,
      { bookSourceName: 'Audio B', bookSourceUrl: 'https://audio-b.example.com', bookSourceType: 1 }
    ];
    const third = [{ bookSourceName: 'Text', bookSourceUrl: 'https://text.example.com', bookSourceType: 0 }];
    const bodies = new Map<string, string>([
      ['https://legado.aoaostar.com/', html],
      [urls[0]!, JSON.stringify(first)],
      [urls[1]!, JSON.stringify(second)],
      [urls[2]!, JSON.stringify(third)]
    ]);
    const fetchMock = vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      const body = bodies.get(url);
      if (body === undefined) return new Response('', { status: 404 });
      return new Response(body, { status: 200 });
    });
    vi.stubGlobal('fetch', fetchMock);

    const config = { SOURCE_CONCURRENCY: 4, SOURCE_SYNC_FETCH_TIMEOUT_MS: 120000 } as AppConfig;
    const catalog = {} as CatalogService;
    const service = new SourceCatalogSyncService(db, config, catalog);
    const result = await (service as unknown as { fetchAoaoStar(): Promise<{
      sources: Record<string, unknown>[];
      total: number;
      rejected: number;
    }> }).fetchAoaoStar();

    expect(result.sources.map((source) => source.bookSourceName)).toEqual(['Audio A', 'Audio B']);
    expect(result.total).toBe(4);
    expect(result.rejected).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(4);
    for (const url of urls) expect(fetchMock).toHaveBeenCalledWith(url, expect.any(Object));
    db.close();
  }, 15000);
});
