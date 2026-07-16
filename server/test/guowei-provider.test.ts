import { createHash } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { GuoweiProvider } from '../src/providers/guowei-provider.js';
import type { AudioBook, AudioChapter, SourceRecord } from '../src/types.js';

const signingKey = 'unit-test-signing-key';

function source(): SourceRecord {
  return {
    id: 'guowei_free_listen',
    kind: 'guowei',
    name: '免费听书王',
    sourceUrl: 'https://api.example.com/',
    enabled: true,
    priority: 10,
    state: 'unknown',
    testKeyword: '万古天帝',
    config: { deviceId: '0123456789abcdef0123456789abcdef' },
    consecutiveFailures: 0,
    successCount: 0,
    failureCount: 0,
    lastLatencyMs: null,
    lastSuccessAt: null,
    lastFailureAt: null,
    lastErrorCode: null,
    createdAt: '2026-07-16T00:00:00.000Z',
    updatedAt: '2026-07-16T00:00:00.000Z'
  };
}

function json(data: unknown): Response {
  return new Response(JSON.stringify(data), { status: 200, headers: { 'content-type': 'application/json' } });
}

function signature(body: Record<string, string>, unsigned: string[]): string {
  const canonical = Object.keys(body)
    .filter((key) => key !== 'signature' && !unsigned.includes(key))
    .sort()
    .map((key) => `${key}=${body[key] ?? ''}`)
    .join('&');
  return createHash('sha256').update(`${canonical}&key=${signingKey}`).digest('hex').toUpperCase();
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('GuoweiProvider', () => {
  it('maps search, detail, chapters and audio while preserving the protocol signing order', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-16T08:00:00.000Z'));
    const requests: Array<{ path: string; body: Record<string, string>; authorization: string | null }> = [];
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, string>;
      const headers = new Headers(init?.headers);
      requests.push({ path: url.pathname, body, authorization: headers.get('authorization') });
      if (url.pathname === '/User/Reg') return json({ code: 200, data: { token: 'token-1', userid: 'user-1' } });
      if (url.pathname === '/Yss/SearchNovel') return json({ code: 200, data: [{
        novel_id: '100', novel_name: '万古天帝', author_name: '第一神', announcer_name: ['播音员'],
        novel_cover: 'https://img.example.com/cover.jpg', class_name: ['玄幻']
      }] });
      if (url.pathname === '/Yss/GetYssInfo') return json({ code: 200, data: {
        novel_id: '100', novel_name: '万古天帝', novel_intro: '简介', author_name: '第一神',
        announcer_name: ['播音员'], novel_cover: 'https://img.example.com/cover.jpg',
        class_name: ['玄幻'], mp3_basepath: 'https://audio.example.com/books/100/'
      } });
      if (url.pathname === '/Yss/GetNovelChapterList') return json({ code: 200, data: [{
        chapter_id: 'chapter-1', chapter_title: '第1集', chapter_several: 1, duration_second: 95
      }] });
      if (url.pathname === '/Yss/GetChapterByCid') return json({ code: 200, data: {
        chapter_id: 'chapter-1', mp3_src: '001.mp3'
      } });
      throw new Error(`Unexpected URL: ${url}`);
    }));
    const provider = new GuoweiProvider({ baseUrl: 'https://api.example.com/', signingKey, timeoutMs: 1000 });
    const bookSource = source();

    const [candidate] = await provider.search(bookSource, '万古天帝', 1);
    expect(candidate).toMatchObject({ externalId: '100', title: '万古天帝', narrator: '播音员', category: '玄幻' });
    const detail = await provider.getBook(bookSource, candidate!.externalId, candidate!.raw);
    const book: AudioBook = { ...detail, id: 'book-1', chapterCount: 0, totalDuration: 0 };
    const [chapterCandidate] = await provider.getChapters(bookSource, book);
    expect(chapterCandidate).toMatchObject({ externalId: 'chapter-1', title: '第1集', duration: 95 });
    const chapter: AudioChapter = { ...chapterCandidate!, id: 'chapter-id', bookId: book.id };
    const resolved = await provider.resolve(bookSource, book, chapter);

    expect(resolved).toMatchObject({ url: 'https://audio.example.com/books/100/001.mp3', format: 'mp3' });
    expect(requests).toHaveLength(5);
    expect(requests[0]!.authorization).toBeNull();
    expect(requests.slice(1).every((request) => request.authorization === 'Bearer token-1')).toBe(true);
    expect(requests[0]!.body.signature).toBe(signature(requests[0]!.body, ['dv_androidid']));
    expect(requests[1]!.body.signature).toBe(signature(requests[1]!.body, ['words', 'page_fr']));
    expect(requests[3]!.body).toMatchObject({ sort: 'asc', startchapter: '1', page: '1', pagenum: '5000' });
  });

  it('registers a fresh anonymous session and retries once after code 402', async () => {
    let registrations = 0;
    let searches = 0;
    vi.stubGlobal('fetch', vi.fn(async (input: string | URL | Request) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      if (url.pathname === '/User/Reg') {
        registrations += 1;
        return json({ code: 200, data: { token: `token-${registrations}`, userid: `user-${registrations}` } });
      }
      if (url.pathname === '/Yss/SearchNovel') {
        searches += 1;
        return searches === 1 ? json({ code: 402, msg: 'expired' }) : json({ code: 200, data: [] });
      }
      throw new Error(`Unexpected URL: ${url}`);
    }));
    const provider = new GuoweiProvider({ baseUrl: 'https://api.example.com/', signingKey, timeoutMs: 1000 });

    await expect(provider.search(source(), '万古天帝', 1)).resolves.toEqual([]);
    expect(registrations).toBe(2);
    expect(searches).toBe(2);
  });
});
