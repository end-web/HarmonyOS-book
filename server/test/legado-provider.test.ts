import { describe, expect, it, vi } from 'vitest';
import type { AudioBook, AudioChapter, SourceRecord } from '../src/types.js';
import { LegadoProvider } from '../src/providers/legado-provider.js';
import type { ReaderClient } from '../src/providers/reader-client.js';

describe('Legado audio resolution', () => {
  it('lets Reader select the chapter by index for uncached books', async () => {
    const post = vi.fn().mockResolvedValue('https://audio.example.com/book/one.m3u8');
    const provider = new LegadoProvider({ post } as unknown as ReaderClient);
    const source = {
      id: 'source', kind: 'legado', name: 'Audio source', sourceUrl: 'https://source.example.com',
      enabled: true, priority: 100, state: 'healthy', testKeyword: '', config: { bookSourceType: 1 },
      consecutiveFailures: 0, successCount: 0, failureCount: 0, lastLatencyMs: null,
      lastSuccessAt: null, lastFailureAt: null, lastErrorCode: null, createdAt: '', updatedAt: ''
    } satisfies SourceRecord;
    const book = {
      id: 'book', sourceId: source.id, sourceName: source.name, externalId: 'https://source.example.com/book',
      title: 'Book', author: 'Author', narrator: 'Narrator', cover: '', intro: '', category: 'Audio',
      latestChapter: '', language: '', chapterCount: 1, totalDuration: 0, raw: {}
    } satisfies AudioBook;
    const chapter = {
      id: 'chapter', bookId: book.id, externalId: 'https://source.example.com/chapter/one',
      title: 'One', index: 0, duration: 0, raw: {}
    } satisfies AudioChapter;

    const result = await provider.resolve(source, book, chapter);

    expect(post).toHaveBeenCalledWith('/reader3/getBookContent', {
      url: book.externalId,
      index: 0,
      refresh: 1,
      bookSource: source.config
    });
    expect(result.url).toBe('https://audio.example.com/book/one.m3u8');
    expect(result.format).toBe('hls');
  });
});
