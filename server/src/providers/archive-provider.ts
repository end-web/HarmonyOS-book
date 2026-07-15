import type {
  AudioBook, AudioBookCandidate, AudioChapter, AudioChapterCandidate, AudioResolution, SourceProvider, SourceRecord
} from '../types.js';
import { assertAudioUrl, cleanText, firstString } from '../utils.js';

interface ArchiveSearchDocument {
  identifier?: unknown;
  title?: unknown;
  creator?: unknown;
  description?: unknown;
  language?: unknown;
  subject?: unknown;
}

interface ArchiveMetadataResponse {
  metadata?: Record<string, unknown>;
  files?: Array<Record<string, unknown>>;
}

async function fetchJson<T>(url: URL, timeoutMs = 10000): Promise<T> {
  const response = await fetch(url, {
    headers: { Accept: 'application/json', 'User-Agent': 'JianHuanAudio/1.0 (+public-domain-catalog)' },
    signal: AbortSignal.timeout(timeoutMs)
  });
  if (!response.ok) throw new Error(`HTTP_${response.status}`);
  return await response.json() as T;
}

function authorName(value: unknown): string {
  return cleanText(value) || '未知作者';
}

function archiveCandidate(source: SourceRecord, document: ArchiveSearchDocument): AudioBookCandidate | null {
  const identifier = firstString(document.identifier);
  const title = cleanText(document.title, 300);
  if (!identifier || !title) return null;
  return {
    sourceId: source.id,
    sourceName: source.name,
    externalId: identifier,
    title,
    author: authorName(document.creator),
    narrator: 'LibriVox 志愿者',
    cover: `https://archive.org/services/img/${encodeURIComponent(identifier)}`,
    intro: cleanText(document.description),
    category: cleanText(document.subject, 500) || '公版有声书',
    latestChapter: '',
    language: cleanText(document.language, 80),
    raw: { identifier }
  };
}

function trackNumber(file: Record<string, unknown>): number {
  const track = firstString(file.track);
  const match = track.match(/^\s*(\d+)/);
  if (match?.[1]) return Number(match[1]);
  const name = firstString(file.name);
  const nameMatch = name.match(/(?:^|[_ -])(\d{1,4})(?:[_ .-]|$)/);
  return nameMatch?.[1] ? Number(nameMatch[1]) : Number.MAX_SAFE_INTEGER;
}

function compareNatural(a: string, b: string): number {
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
}

export class ArchiveProvider implements SourceProvider {
  async search(source: SourceRecord, keyword: string, page: number): Promise<AudioBookCandidate[]> {
    const safeKeyword = keyword.replace(/[+\-!(){}\[\]^"~*?:\\/]/g, ' ').replace(/\s+/g, ' ').trim();
    if (!safeKeyword) return [];
    const query = `collection:(librivoxaudio) AND mediatype:(audio) AND (title:(${safeKeyword}) OR creator:(${safeKeyword}))`;
    const url = new URL('https://archive.org/advancedsearch.php');
    url.searchParams.set('q', query);
    for (const field of ['identifier', 'title', 'creator', 'description', 'language', 'subject']) {
      url.searchParams.append('fl[]', field);
    }
    url.searchParams.append('sort[]', 'downloads desc');
    url.searchParams.set('rows', '20');
    url.searchParams.set('page', String(Math.max(1, page)));
    url.searchParams.set('output', 'json');
    const payload = await fetchJson<{ response?: { docs?: ArchiveSearchDocument[] } }>(url);
    const output: AudioBookCandidate[] = [];
    for (const document of payload.response?.docs ?? []) {
      const item = archiveCandidate(source, document);
      if (item) output.push(item);
    }
    return output;
  }

  async getBook(source: SourceRecord, externalId: string, raw: Record<string, unknown>): Promise<AudioBookCandidate> {
    const url = new URL(`https://archive.org/metadata/${encodeURIComponent(externalId)}`);
    const payload = await fetchJson<ArchiveMetadataResponse>(url);
    const metadata = payload.metadata ?? {};
    const candidate = archiveCandidate(source, {
      identifier: metadata.identifier ?? externalId,
      title: metadata.title,
      creator: metadata.creator,
      description: metadata.description,
      language: metadata.language,
      subject: metadata.subject
    });
    if (!candidate) throw new Error('EMPTY_BOOK_DETAIL');
    return { ...candidate, raw: { ...raw, identifier: externalId } };
  }

  async getChapters(_source: SourceRecord, book: AudioBook): Promise<AudioChapterCandidate[]> {
    const url = new URL(`https://archive.org/metadata/${encodeURIComponent(book.externalId)}`);
    const payload = await fetchJson<ArchiveMetadataResponse>(url, 15000);
    const mp3Files = (payload.files ?? []).filter((file) => {
      const name = firstString(file.name).toLowerCase();
      const format = firstString(file.format).toLowerCase();
      return name.endsWith('.mp3') && !name.endsWith('.zip') &&
        (firstString(file.source) === 'original' || format.includes('vbr mp3'));
    });
    const fallback = mp3Files.length > 0 ? mp3Files : (payload.files ?? []).filter((file) => {
      const name = firstString(file.name).toLowerCase();
      const format = firstString(file.format).toLowerCase();
      return name.endsWith('.mp3') && (format.includes('64kbps mp3') || format.includes('mp3'));
    });
    fallback.sort((left, right) => {
      const trackDelta = trackNumber(left) - trackNumber(right);
      return trackDelta !== 0 ? trackDelta : compareNatural(firstString(left.name), firstString(right.name));
    });
    const seen = new Set<string>();
    const chapters: AudioChapterCandidate[] = [];
    for (const file of fallback) {
      const name = firstString(file.name);
      if (!name || seen.has(name)) continue;
      seen.add(name);
      chapters.push({
        externalId: name,
        title: cleanText(file.title, 300) || name.replace(/\.mp3$/i, ''),
        index: chapters.length,
        duration: Math.max(0, Math.round(Number(file.length ?? 0) || 0)),
        raw: { name }
      });
    }
    if (chapters.length === 0) throw new Error('EMPTY_CHAPTERS');
    return chapters;
  }

  async resolve(_source: SourceRecord, book: AudioBook, chapter: AudioChapter): Promise<AudioResolution> {
    const fileName = firstString(chapter.raw.name) || chapter.externalId;
    const encodedName = fileName.split('/').map((part) => encodeURIComponent(part)).join('/');
    const url = assertAudioUrl(`https://archive.org/download/${encodeURIComponent(book.externalId)}/${encodedName}`);
    return { url, headers: {}, format: 'mp3', expiresAt: null };
  }
}
