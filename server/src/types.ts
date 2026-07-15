export type SourceKind = 'archive' | 'podcast' | 'legado';
export type SourceState = 'healthy' | 'degraded' | 'down' | 'unknown';

export interface SourceRecord {
  id: string;
  kind: SourceKind;
  name: string;
  sourceUrl: string;
  enabled: boolean;
  priority: number;
  state: SourceState;
  testKeyword: string;
  config: Record<string, unknown>;
  consecutiveFailures: number;
  successCount: number;
  failureCount: number;
  lastLatencyMs: number | null;
  lastSuccessAt: string | null;
  lastFailureAt: string | null;
  lastErrorCode: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AudioBookCandidate {
  sourceId: string;
  sourceName: string;
  externalId: string;
  title: string;
  author: string;
  narrator: string;
  cover: string;
  intro: string;
  category: string;
  latestChapter: string;
  language: string;
  raw: Record<string, unknown>;
}

export interface AudioBook extends AudioBookCandidate {
  id: string;
  chapterCount: number;
  totalDuration: number;
}

export interface AudioChapterCandidate {
  externalId: string;
  title: string;
  index: number;
  duration: number;
  raw: Record<string, unknown>;
}

export interface AudioChapter extends AudioChapterCandidate {
  id: string;
  bookId: string;
}

export interface AudioResolution {
  url: string;
  headers: Record<string, string>;
  format: string;
  expiresAt: number | null;
}

export interface SearchOutcome {
  sourceId: string;
  sourceName: string;
  ok: boolean;
  latencyMs: number;
  items: AudioBookCandidate[];
  errorCode?: string;
}

export interface SourceProvider {
  search(source: SourceRecord, keyword: string, page: number): Promise<AudioBookCandidate[]>;
  getBook(source: SourceRecord, externalId: string, raw: Record<string, unknown>): Promise<AudioBookCandidate>;
  getChapters(source: SourceRecord, book: AudioBook): Promise<AudioChapterCandidate[]>;
  resolve(source: SourceRecord, book: AudioBook, chapter: AudioChapter): Promise<AudioResolution>;
}

export interface ApiEnvelope<T> {
  code: string;
  data: T;
  requestId: string;
  serverTime: number;
}
