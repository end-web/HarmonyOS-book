import type {
  AudioBook, AudioBookCandidate, AudioChapter, AudioChapterCandidate, AudioResolution, SourceProvider, SourceRecord
} from '../types.js';
import { assertAudioUrl, audioFormat, cleanText, firstString } from '../utils.js';
import { ReaderClient } from './reader-client.js';

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function candidateFromReader(source: SourceRecord, value: Record<string, unknown>, fallback?: AudioBook): AudioBookCandidate | null {
  const externalId = firstString(value.bookUrl) || fallback?.externalId || '';
  const title = cleanText(value.name ?? fallback?.title, 300);
  if (!externalId || !title) return null;
  return {
    sourceId: source.id,
    sourceName: source.name,
    externalId,
    title,
    author: cleanText(value.author ?? fallback?.author, 200) || '未知作者',
    narrator: cleanText(value.narrator ?? value.tocHtml ?? fallback?.narrator, 200) || source.name,
    cover: firstString(value.coverUrl) || fallback?.cover || '',
    intro: cleanText(value.intro ?? fallback?.intro),
    category: cleanText(value.kind ?? fallback?.category, 500) || '有声书',
    latestChapter: cleanText(value.latestChapterTitle ?? value.lastChapter ?? fallback?.latestChapter, 300),
    language: cleanText(value.language ?? fallback?.language, 80),
    raw: value
  };
}

function staticHeaders(config: Record<string, unknown>): Record<string, string> {
  const raw = config.header;
  let parsed: Record<string, unknown> = {};
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) parsed = raw as Record<string, unknown>;
  if (typeof raw === 'string' && raw.trim().startsWith('{')) {
    try { parsed = JSON.parse(raw) as Record<string, unknown>; } catch { parsed = {}; }
  }
  const allowed = new Set(['referer', 'origin', 'user-agent', 'accept']);
  const output: Record<string, string> = {};
  for (const [key, value] of Object.entries(parsed)) {
    if (allowed.has(key.toLowerCase()) && typeof value === 'string' && value.length <= 1000) output[key] = value;
  }
  return output;
}

function parseResolvedAudio(value: unknown): { url: string; headers: Record<string, string> } {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const object = value as Record<string, unknown>;
    const url = firstString(object.url);
    const headers = asRecord(object.headers);
    const cleanHeaders: Record<string, string> = {};
    for (const [key, headerValue] of Object.entries(headers)) {
      if (typeof headerValue === 'string' && !['cookie', 'authorization'].includes(key.toLowerCase())) {
        cleanHeaders[key] = headerValue;
      }
    }
    return { url: assertAudioUrl(url), headers: cleanHeaders };
  }
  const text = String(value ?? '').trim();
  if (text.startsWith('{')) {
    try { return parseResolvedAudio(JSON.parse(text) as unknown); } catch { /* use URL extraction */ }
  }
  const match = text.match(/https?:\/\/[^\s"'<>]+/i);
  if (!match?.[0]) throw new Error('EMPTY_AUDIO_URL');
  return { url: assertAudioUrl(match[0].replace(/[),.;]+$/, '')), headers: {} };
}

export class LegadoProvider implements SourceProvider {
  constructor(private readonly reader: ReaderClient) {}

  async search(source: SourceRecord, keyword: string, page: number): Promise<AudioBookCandidate[]> {
    const data = await this.reader.post<unknown[]>('/reader3/searchBook', {
      key: keyword,
      page,
      bookSource: source.config
    });
    const output: AudioBookCandidate[] = [];
    for (const raw of Array.isArray(data) ? data : []) {
      const value = asRecord(raw);
      const candidate = candidateFromReader(source, value);
      if (candidate) output.push(candidate);
    }
    return output;
  }

  async getBook(source: SourceRecord, externalId: string, raw: Record<string, unknown>): Promise<AudioBookCandidate> {
    const value = await this.reader.post<Record<string, unknown>>('/reader3/getBookInfo', {
      url: externalId,
      bookSource: source.config
    });
    const fallbackCandidate = candidateFromReader(source, raw);
    const fallback = fallbackCandidate ? { ...fallbackCandidate, id: '', chapterCount: 0, totalDuration: 0 } : undefined;
    const candidate = candidateFromReader(source, value, fallback);
    if (!candidate) throw new Error('EMPTY_BOOK_DETAIL');
    return candidate;
  }

  async getChapters(source: SourceRecord, book: AudioBook): Promise<AudioChapterCandidate[]> {
    await this.reader.post<Record<string, unknown>>('/reader3/getBookInfo', {
      url: book.externalId,
      bookSource: source.config
    });
    const data = await this.reader.post<unknown[]>('/reader3/getChapterList', {
      url: book.externalId,
      refresh: 0,
      bookSource: source.config
    });
    const output: AudioChapterCandidate[] = [];
    const seen = new Set<string>();
    for (const raw of Array.isArray(data) ? data : []) {
      const value = asRecord(raw);
      const externalId = firstString(value.url);
      if (!externalId || seen.has(externalId) || value.isVolume === true) continue;
      seen.add(externalId);
      output.push({
        externalId,
        title: cleanText(value.title ?? value.name, 300) || `第${output.length + 1}集`,
        index: output.length,
        duration: Math.max(0, Math.round(Number(value.duration ?? 0) || 0)),
        raw: value
      });
    }
    if (output.length === 0) throw new Error('EMPTY_CHAPTERS');
    return output;
  }

  async resolve(source: SourceRecord, book: AudioBook, chapter: AudioChapter): Promise<AudioResolution> {
    const data = await this.reader.post<unknown>('/reader3/getBookContent', {
      url: book.externalId,
      chapterUrl: chapter.externalId,
      index: chapter.index,
      refresh: 1,
      bookSource: source.config
    });
    const resolved = parseResolvedAudio(data);
    return {
      url: resolved.url,
      headers: { ...staticHeaders(source.config), ...resolved.headers },
      format: audioFormat(resolved.url),
      expiresAt: Date.now() + 5 * 60 * 1000
    };
  }
}
