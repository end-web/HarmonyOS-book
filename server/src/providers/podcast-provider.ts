import { XMLParser } from 'fast-xml-parser';
import type {
  AudioBook, AudioBookCandidate, AudioChapter, AudioChapterCandidate, AudioResolution, SourceProvider, SourceRecord
} from '../types.js';
import { assertAudioUrl, audioFormat, cleanText, firstString } from '../utils.js';

interface PodcastSearchItem {
  collectionId?: number;
  collectionName?: string;
  artistName?: string;
  artworkUrl600?: string;
  artworkUrl100?: string;
  feedUrl?: string;
  genres?: string[];
  primaryGenreName?: string;
  trackCount?: number;
  releaseDate?: string;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function asArray(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  return value === undefined || value === null ? [] : [value];
}

async function fetchText(urlValue: string, accept: string, timeoutMs = 12000): Promise<string> {
  const url = new URL(urlValue);
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('UNSUPPORTED_FEED_PROTOCOL');
  const response = await fetch(url, {
    headers: { Accept: accept, 'User-Agent': 'JianHuanAudio/1.0' },
    signal: AbortSignal.timeout(timeoutMs)
  });
  if (!response.ok) throw new Error(`HTTP_${response.status}`);
  const declared = Number(response.headers.get('content-length') ?? 0);
  if (declared > 6_000_000) throw new Error('FEED_TOO_LARGE');
  const text = await response.text();
  if (text.length > 6_000_000) throw new Error('FEED_TOO_LARGE');
  return text;
}

function durationSeconds(value: unknown): number {
  const text = firstString(value);
  if (!text) return 0;
  if (/^\d+(?:\.\d+)?$/.test(text)) return Math.max(0, Math.round(Number(text)));
  const parts = text.split(':').map(Number);
  if (parts.some((part) => !Number.isFinite(part))) return 0;
  return Math.max(0, Math.round(parts.reduce((sum, part) => sum * 60 + part, 0)));
}

function podcastCandidate(source: SourceRecord, item: PodcastSearchItem): AudioBookCandidate | null {
  const externalId = String(item.collectionId ?? '').trim();
  const title = cleanText(item.collectionName, 300);
  const feedUrl = String(item.feedUrl ?? '').trim();
  if (!externalId || !title || !feedUrl) return null;
  return {
    sourceId: source.id,
    sourceName: source.name,
    externalId,
    title,
    author: cleanText(item.artistName, 200) || '未知作者',
    narrator: cleanText(item.artistName, 200),
    cover: String(item.artworkUrl600 || item.artworkUrl100 || ''),
    intro: '',
    category: cleanText(item.genres ?? item.primaryGenreName, 500) || '播客',
    latestChapter: '',
    language: '',
    raw: { ...item, feedUrl }
  };
}

function parseFeed(xml: string): { channel: Record<string, unknown>; items: Record<string, unknown>[] } {
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
    trimValues: true,
    processEntities: false,
    allowBooleanAttributes: false
  });
  const root = asRecord(parser.parse(xml));
  const channel = asRecord(asRecord(root.rss).channel || asRecord(root.feed));
  const items = asArray(channel.item ?? channel.entry).map(asRecord);
  return { channel, items };
}

function feedImage(channel: Record<string, unknown>): string {
  const itunesImage = asRecord(channel['itunes:image']);
  const image = asRecord(channel.image);
  return firstString(itunesImage['@_href']) || firstString(image.url);
}

function episodeUrl(item: Record<string, unknown>): string {
  const enclosure = asRecord(item.enclosure);
  if (enclosure['@_url']) return firstString(enclosure['@_url']).replaceAll('&amp;', '&');
  for (const link of asArray(item.link)) {
    const record = asRecord(link);
    if (firstString(record['@_rel']) === 'enclosure') return firstString(record['@_href']);
  }
  return '';
}

function episodeOrder(item: Record<string, unknown>, fallback: number): number {
  const explicit = Number(firstString(item['itunes:episode']) || firstString(item.episode));
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  const title = cleanText(item['itunes:title'] ?? item.title, 300);
  const match = title.match(/^\D*(\d{1,5})/);
  if (match?.[1]) return Number(match[1]);
  const published = Date.parse(firstString(item.pubDate) || firstString(item.published));
  return Number.isFinite(published) ? published : fallback;
}

export class PodcastProvider implements SourceProvider {
  async search(source: SourceRecord, keyword: string, page: number): Promise<AudioBookCandidate[]> {
    const url = new URL('https://itunes.apple.com/search');
    url.searchParams.set('term', keyword);
    url.searchParams.set('media', 'podcast');
    url.searchParams.set('entity', 'podcast');
    url.searchParams.set('country', 'CN');
    url.searchParams.set('lang', 'zh_cn');
    url.searchParams.set('limit', '20');
    url.searchParams.set('offset', String((Math.max(1, page) - 1) * 20));
    const text = await fetchText(url.toString(), 'application/json', 8000);
    const payload = JSON.parse(text) as { results?: PodcastSearchItem[] };
    const output: AudioBookCandidate[] = [];
    for (const item of payload.results ?? []) {
      const candidate = podcastCandidate(source, item);
      if (candidate) output.push(candidate);
    }
    return output;
  }

  async getBook(source: SourceRecord, externalId: string, raw: Record<string, unknown>): Promise<AudioBookCandidate> {
    const base = podcastCandidate(source, raw as PodcastSearchItem);
    if (!base) throw new Error('EMPTY_BOOK_DETAIL');
    const feedUrl = firstString(raw.feedUrl);
    const { channel, items } = parseFeed(await fetchText(feedUrl, 'application/rss+xml, application/xml, text/xml'));
    return {
      ...base,
      externalId,
      title: cleanText(channel.title, 300) || base.title,
      author: cleanText(channel['itunes:author'] ?? channel.author, 200) || base.author,
      narrator: cleanText(channel['itunes:author'] ?? channel.author, 200) || base.narrator,
      cover: feedImage(channel) || base.cover,
      intro: cleanText(channel.description ?? channel.subtitle),
      latestChapter: items.length > 0 ? cleanText(items[items.length - 1]?.title, 300) : '',
      language: cleanText(channel.language, 80),
      raw: { ...raw, feedUrl }
    };
  }

  async getChapters(_source: SourceRecord, book: AudioBook): Promise<AudioChapterCandidate[]> {
    const feedUrl = firstString(book.raw.feedUrl);
    if (!feedUrl) throw new Error('EMPTY_FEED_URL');
    const { items } = parseFeed(await fetchText(feedUrl, 'application/rss+xml, application/xml, text/xml', 20000));
    const episodes = items.map((item, index) => ({ item, index, order: episodeOrder(item, index) }))
      .filter(({ item }) => Boolean(episodeUrl(item)));
    episodes.sort((left, right) => left.order - right.order || left.index - right.index);
    const output: AudioChapterCandidate[] = [];
    const seen = new Set<string>();
    for (const { item } of episodes) {
      const url = episodeUrl(item);
      if (!url || seen.has(url)) continue;
      seen.add(url);
      const guidRecord = asRecord(item.guid);
      const guid = firstString(guidRecord['#text'] ?? item.guid) || url;
      output.push({
        externalId: guid,
        title: cleanText(item['itunes:title'] ?? item.title, 300) || `第${output.length + 1}集`,
        index: output.length,
        duration: durationSeconds(item['itunes:duration'] ?? item.duration),
        raw: { audioUrl: url, mimeType: firstString(asRecord(item.enclosure)['@_type']) }
      });
    }
    if (output.length === 0) throw new Error('EMPTY_CHAPTERS');
    return output;
  }

  async resolve(_source: SourceRecord, _book: AudioBook, chapter: AudioChapter): Promise<AudioResolution> {
    const url = assertAudioUrl(firstString(chapter.raw.audioUrl));
    return { url, headers: {}, format: audioFormat(url), expiresAt: null };
  }
}
