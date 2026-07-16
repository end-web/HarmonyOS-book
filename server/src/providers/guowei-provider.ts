import { createHash } from 'node:crypto';
import type {
  AudioBook, AudioBookCandidate, AudioChapter, AudioChapterCandidate, AudioResolution, SourceProvider, SourceRecord
} from '../types.js';
import { assertAudioUrl, audioFormat, cleanText, firstString } from '../utils.js';

type StringParams = Record<string, string>;

interface GuoweiEnvelope {
  code?: number | string;
  msg?: string;
  data?: unknown;
}

interface GuoweiSession {
  token: string;
  userId: string;
}

export interface GuoweiProviderOptions {
  baseUrl: string;
  signingKey: string;
  timeoutMs: number;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function numberValue(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function deviceId(source: SourceRecord): string {
  const configured = firstString(source.config.deviceId);
  if (configured) return configured;
  return createHash('sha256').update(source.id).digest('hex').slice(0, 32);
}

function candidateFromApi(
  source: SourceRecord,
  value: Record<string, unknown>,
  fallback?: AudioBookCandidate
): AudioBookCandidate | null {
  const externalId = firstString(value.novel_id) || fallback?.externalId || '';
  const title = cleanText(value.novel_name ?? fallback?.title, 300);
  if (!externalId || !title) return null;
  return {
    sourceId: source.id,
    sourceName: source.name,
    externalId,
    title,
    author: cleanText(value.author_name ?? fallback?.author, 200) || '未知作者',
    narrator: cleanText(value.announcer_name ?? fallback?.narrator, 200) || source.name,
    cover: firstString(value.novel_cover) || firstString(value.banner_image) || fallback?.cover || '',
    intro: cleanText(value.novel_intro ?? fallback?.intro),
    category: cleanText(value.class_name ?? fallback?.category, 500) || '有声书',
    latestChapter: cleanText(value.user_history_cname ?? fallback?.latestChapter, 300),
    language: fallback?.language || '中文',
    raw: value
  };
}

function resolveAudioUrl(rawUrl: string, basePath: string): string {
  if (/^https?:\/\//i.test(rawUrl)) return assertAudioUrl(rawUrl);
  if (!basePath) throw new Error('EMPTY_AUDIO_URL');
  const normalizedBase = basePath.endsWith('/') ? basePath : `${basePath}/`;
  return assertAudioUrl(new URL(rawUrl.replace(/^\/+/, ''), normalizedBase).toString());
}

export class GuoweiProvider implements SourceProvider {
  private readonly baseUrl: URL;
  private readonly sessions = new Map<string, GuoweiSession>();
  private readonly sessionRequests = new Map<string, Promise<GuoweiSession>>();

  constructor(private readonly options: GuoweiProviderOptions) {
    this.baseUrl = new URL(options.baseUrl);
  }

  async search(source: SourceRecord, keyword: string, page: number): Promise<AudioBookCandidate[]> {
    const data = await this.request(source, '/Yss/SearchNovel', (common) => {
      const signed = this.withSignature({ ...common, page: String(page) });
      return { ...signed, words: keyword, page_fr: 'index' };
    });
    const output: AudioBookCandidate[] = [];
    for (const raw of asArray(data)) {
      const candidate = candidateFromApi(source, asRecord(raw));
      if (candidate) output.push(candidate);
    }
    return output;
  }

  async getBook(source: SourceRecord, externalId: string, raw: Record<string, unknown>): Promise<AudioBookCandidate> {
    const data = asRecord(await this.request(source, '/Yss/GetYssInfo', (common) =>
      this.withSignature({ ...common, novelid: externalId })));
    const fallback = candidateFromApi(source, raw) ?? undefined;
    const candidate = candidateFromApi(source, data, fallback);
    if (!candidate) throw new Error('EMPTY_BOOK_DETAIL');
    return candidate;
  }

  async getChapters(source: SourceRecord, book: AudioBook): Promise<AudioChapterCandidate[]> {
    const data = await this.request(source, '/Yss/GetNovelChapterList', (common) => this.withSignature({
      ...common,
      novelid: book.externalId,
      sort: 'asc',
      startchapter: '1',
      page: '1',
      pagenum: '5000'
    }));
    const output: AudioChapterCandidate[] = [];
    const seen = new Set<string>();
    for (const raw of asArray(data)) {
      const value = asRecord(raw);
      const externalId = firstString(value.chapter_id);
      if (!externalId || seen.has(externalId)) continue;
      seen.add(externalId);
      output.push({
        externalId,
        title: cleanText(value.chapter_title, 300) || `第${output.length + 1}集`,
        index: output.length,
        duration: Math.max(0, Math.round(numberValue(value.duration_second))),
        raw: value
      });
    }
    if (output.length === 0) throw new Error('EMPTY_CHAPTERS');
    return output;
  }

  async resolve(source: SourceRecord, book: AudioBook, chapter: AudioChapter): Promise<AudioResolution> {
    const data = asRecord(await this.request(source, '/Yss/GetChapterByCid', (common) => this.withSignature({
      ...common,
      novelid: book.externalId,
      cid: chapter.externalId
    })));
    const rawUrl = firstString(data.mp3_src) || firstString(data.mp3_url_cuttime) ||
      firstString(chapter.raw.mp3_src) || firstString(chapter.raw.mp3_url_cuttime);
    if (!rawUrl) throw new Error('EMPTY_AUDIO_URL');
    const basePath = firstString(data.mp3_basepath) || firstString(book.raw.mp3_basepath);
    const url = resolveAudioUrl(rawUrl, basePath);
    return { url, headers: {}, format: audioFormat(url), expiresAt: null };
  }

  private commonParams(source: SourceRecord, userId: string): StringParams {
    const id = deviceId(source);
    return {
      auid: createHash('md5').update(id).digest('hex'),
      ver: '3.4.4',
      dv_brand: 'HUAWEI',
      dv_model: 'HarmonyOS',
      nt: String(Date.now() | 0),
      dv_oaid: '',
      dv_net: 'WiFi',
      channel: 'huawei',
      userid: userId,
      platform: 'android'
    };
  }

  private withSignature(params: StringParams): StringParams {
    if (!this.options.signingKey) throw new Error('GUOWEI_NOT_CONFIGURED');
    const canonical = Object.keys(params).sort().map((key) => `${key}=${params[key] ?? ''}`).join('&');
    const signature = createHash('sha256')
      .update(`${canonical}&key=${this.options.signingKey}`)
      .digest('hex')
      .toUpperCase();
    return { ...params, signature };
  }

  private async request(
    source: SourceRecord,
    pathname: string,
    buildBody: (common: StringParams) => StringParams
  ): Promise<unknown> {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const session = await this.ensureSession(source);
      const envelope = await this.post(pathname, buildBody(this.commonParams(source, session.userId)), session.token);
      const code = Number(envelope.code ?? 0);
      if (code === 402 && attempt === 0) {
        this.sessions.delete(source.id);
        continue;
      }
      if (code !== 200) throw new Error(`GUOWEI_API_${code || 'UNKNOWN'}`);
      return envelope.data;
    }
    throw new Error('GUOWEI_AUTH_EXPIRED');
  }

  private async ensureSession(source: SourceRecord): Promise<GuoweiSession> {
    const cached = this.sessions.get(source.id);
    if (cached) return cached;
    const pending = this.sessionRequests.get(source.id);
    if (pending) return await pending;
    const request = this.register(source);
    this.sessionRequests.set(source.id, request);
    try {
      const session = await request;
      this.sessions.set(source.id, session);
      return session;
    } finally {
      this.sessionRequests.delete(source.id);
    }
  }

  private async register(source: SourceRecord): Promise<GuoweiSession> {
    const body = {
      ...this.withSignature(this.commonParams(source, '')),
      dv_androidid: deviceId(source)
    };
    const envelope = await this.post('/User/Reg', body);
    const code = Number(envelope.code ?? 0);
    if (code !== 200) throw new Error(`GUOWEI_REGISTER_${code || 'UNKNOWN'}`);
    const data = asRecord(envelope.data);
    const token = firstString(data.token);
    const userId = firstString(data.userid);
    if (!token || !userId) throw new Error('GUOWEI_REGISTER_EMPTY');
    return { token, userId };
  }

  private async post(pathname: string, body: StringParams, token?: string): Promise<GuoweiEnvelope> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
      'Content-Type': 'application/json;charset=UTF-8'
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(new URL(pathname, this.baseUrl), {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(this.options.timeoutMs)
    });
    if (!response.ok) throw new Error(`GUOWEI_HTTP_${response.status}`);
    return await response.json() as GuoweiEnvelope;
  }
}
