import { buffer, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalRuleSourceSession } from '../../../model/LocalRuleSource';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../http/HttpClient';
import { LocalRuleHttpClient } from '../LocalRuleHttpClient';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import {
  GUANG_YU_SOURCE_URL,
  GUANG_YU_SOURCE_VERSION,
  GuangYuRoute
} from './GuangYuSourceIdentity';

const REQUEST_TIMEOUT_MS: number = 8000;
const MAX_RESPONSE_BYTES: number = 8 * 1024 * 1024;
const GUANG_YU_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 ' +
  'Chrome/126.0.0.0 Mobile Safari/537.36';
const NOVEL_TAB: string = '小说';
const CONTENT_REVIEW_SOURCES: string[] = [
  '番茄', '七猫', '塔读', 'QQ阅读', 'svip_QQ阅读', '书旗', 'svip_书旗'
];
const CONTENT_GOD_SOURCES: string[] = ['番茄', '七猫', 'svip_书旗'];

class GuangYuResponseKind {
  static readonly SEARCH: number = 1;
  static readonly DETAIL: number = 2;
  static readonly CATALOG: number = 3;
  static readonly CONTENT: number = 4;
}

class GuangYuInvalidResponseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GuangYuInvalidResponseError';
  }
}

export class GuangYuApiBusinessError extends Error {
  code: number = -1;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'GuangYuApiBusinessError';
    this.code = code;
  }
}

class GuangYuJsonObject {
  private raw: Record<string, Object> = {};

  constructor(raw: Record<string, Object>) {
    this.raw = raw;
  }

  static parse(payload: string): GuangYuJsonObject {
    let parsed: Object;
    try {
      parsed = JSON.parse(payload) as Object;
    } catch (_error) {
      throw new GuangYuInvalidResponseError('响应不是有效 JSON');
    }
    const value = GuangYuJsonObject.fromValue(parsed);
    if (value === undefined) throw new GuangYuInvalidResponseError('响应根节点不是对象');
    return value;
  }

  static fromValue(value: Object | null | undefined): GuangYuJsonObject | undefined {
    if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
      return undefined;
    }
    return new GuangYuJsonObject(value as Record<string, Object>);
  }

  has(key: string): boolean {
    const value = this.raw[key];
    return value !== undefined && value !== null;
  }

  getString(key: string, fallback: string = ''): string {
    const value = this.raw[key];
    if (value === undefined || value === null) return fallback;
    if (typeof value === 'object') return fallback;
    return String(value);
  }

  getNumber(key: string, fallback: number = 0): number {
    const value = this.raw[key];
    if (value === undefined || value === null || typeof value === 'object') return fallback;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  getBoolean(key: string, fallback: boolean = false): boolean {
    const value = this.raw[key];
    if (typeof value === 'boolean') return value as boolean;
    if (value === undefined || value === null || typeof value === 'object') return fallback;
    const normalized = String(value).trim().toLowerCase();
    if (normalized === 'true' || normalized === '1') return true;
    if (normalized === 'false' || normalized === '0') return false;
    return fallback;
  }

  getObject(key: string): GuangYuJsonObject | undefined {
    return GuangYuJsonObject.fromValue(this.raw[key]);
  }

  getArray(key: string): Object[] | undefined {
    const value = this.raw[key];
    return Array.isArray(value) ? value as Object[] : undefined;
  }

  getStringArray(key: string): string[] {
    const value = this.getArray(key);
    const output: string[] = [];
    if (value === undefined) return output;
    for (const item of value) {
      if (item !== undefined && item !== null && typeof item !== 'object') output.push(String(item));
    }
    return output;
  }

  getStringRecord(key: string): Record<string, string> {
    const output: Record<string, string> = {};
    const value = this.getObject(key);
    if (value === undefined) return output;
    const keys = Object.keys(value.raw);
    for (const itemKey of keys) {
      const item = value.raw[itemKey];
      if (item !== undefined && item !== null && typeof item !== 'object') {
        output[itemKey] = String(item);
      }
    }
    return output;
  }
}

class GuangYuHtmlRequestBody {
  html: string = '';
}

class GuangYuVariableValue {
  custom: string = '';
}

export class GuangYuContentRequestBody {
  html: string = '';
  item_id: string = '';
  source: string = '';
  tab: string = '';
  tone_id: string = '4';
  variable: string = '';
  version: string = GUANG_YU_SOURCE_VERSION;
  god: boolean = false;
}

export class GuangYuContentRequestPlan {
  path: string = '/content';
  body: GuangYuContentRequestBody = new GuangYuContentRequestBody();
}

export class GuangYuSourceTimingDto {
  source: string = '';
  cacheData: boolean = false;
  timeCost: number = 0;
  resultCount: number = 0;
}

export class GuangYuSearchItemDto {
  bookName: string = '';
  bookId: string = '';
  author: string = '';
  score: string = '';
  status: string = '';
  wordNumber: string = '';
  lastChapterUpdateTime: string = '';
  lastChapterTitle: string = '';
  category: string = '';
  tags: string = '';
  abstract: string = '';
  readCount: string = '';
  readCountAll: string = '';
  thumbUrl: string = '';
  role: string = '';
  tab: string = '';
  source: string = '';
  bookUrl: string = '';
  tocUrl: string = '';
  detailUrl: string = '';
}

export class GuangYuSearchResponseDto {
  code: number = 0;
  message: string = '';
  cache: boolean = false;
  timeMs: number = 0;
  disabledSources: string[] = [];
  sourceTimings: GuangYuSourceTimingDto[] = [];
  items: GuangYuSearchItemDto[] = [];
}

export class GuangYuDetailDto {
  bookName: string = '';
  aliasName: string = '';
  bookId: string = '';
  relatedNovelBookId: string = '';
  author: string = '';
  score: string = '';
  status: string = '';
  wordNumber: string = '';
  lastChapterUpdateTime: string = '';
  category: string = '';
  tags: string = '';
  abstract: string = '';
  readCount: string = '';
  readCountAll: string = '';
  thumbUrl: string = '';
  tab: string = '';
  source: string = '';
  role: string = '';
  media: string = '';
  lastChapterTitle: string = '';
  copyrightInfo: string = '';
  bookReview: string = '';
  bookTts: string = '';
  toneOptions: Record<string, string> = {};
  bookUrl: string = '';
  tocUrl: string = '';
  catalogUrl: string = '';
}

export class GuangYuDetailResponseDto {
  code: number = 0;
  message: string = '';
  cache: boolean = false;
  timeMs: number = 0;
  detail: GuangYuDetailDto = new GuangYuDetailDto();
}

export class GuangYuCatalogItemDto {
  title: string = '';
  itemId: string = '';
  firstPassTime: string = '';
  chapterWordNumber: string = '';
  source: string = '';
  tab: string = '';
  url: string = '';
  isPay: boolean = false;
  isVolume: boolean = false;
  tocUrl: string = '';
  contentUrl: string = '';
}

export class GuangYuCatalogResponseDto {
  code: number = 0;
  message: string = '';
  cache: boolean = false;
  timeMs: number = 0;
  items: GuangYuCatalogItemDto[] = [];
}

export class GuangYuContentResponseDto {
  code: number = 0;
  message: string = '';
  cache: boolean = false;
  timeMs: number = 0;
  title: string = '';
  content: string = '';
}

/** 光遇聚合服务器模式客户端。只访问内置的七条 HTTPS 线路。 */
export class GuangYuApiClient {
  private static readonly HOSTS: string[] = [
    'https://v1.gyks.cf',
    'https://v2.gyks.cf',
    'https://v3.gyks.cf',
    'https://v4.gyks.cf',
    'https://v5.gyks.cf',
    'https://v6.gyks.cf',
    'https://v7.gyks.cf'
  ];
  private static preferredHostIndex: number = 0;
  private static runtimeDeviceId: string = '';

  static hosts(): string[] {
    return GuangYuApiClient.HOSTS.slice();
  }

  static preferredHost(): string {
    return GuangYuApiClient.HOSTS[GuangYuApiClient.preferredHostIndex];
  }

  static async getOrCreateDeviceId(): Promise<string> {
    const cached = GuangYuApiClient.safeCookiePart(GuangYuApiClient.runtimeDeviceId);
    if (cached.length > 0) return cached;

    let session: LocalRuleSourceSession | undefined = undefined;
    let sessionReadSucceeded = false;
    try {
      session = await LocalRuleSourceRepository.getSession(GUANG_YU_SOURCE_URL);
      sessionReadSucceeded = true;
    } catch (_error) {
      session = undefined;
    }
    if (session !== undefined) {
      const stored = GuangYuApiClient.safeCookiePart(session.deviceId);
      if (stored.length > 0) {
        GuangYuApiClient.runtimeDeviceId = stored;
        return stored;
      }
    }

    const concurrentValue = GuangYuApiClient.safeCookiePart(GuangYuApiClient.runtimeDeviceId);
    if (concurrentValue.length > 0) return concurrentValue;
    const generated = util.generateRandomUUID();
    GuangYuApiClient.runtimeDeviceId = generated;
    if (sessionReadSucceeded) {
      const token = session !== undefined ? GuangYuApiClient.safeCookiePart(session.token) : '';
      const accountLabel = session !== undefined ? session.accountLabel : '';
      const anonymousSession = LocalRuleSourceSession.of(
        GUANG_YU_SOURCE_URL, token, generated, accountLabel);
      try {
        await LocalRuleSourceRepository.saveSession(anonymousSession);
      } catch (_error) {
        // 仓库不可用时保留进程内标识，不能阻断匿名内容请求。
      }
    }
    return generated;
  }

  static async search(tab: string, keyword: string, page: number = 1): Promise<GuangYuSearchResponseDto> {
    const safePage = Math.max(1, Math.min(1000, Math.trunc(page)));
    const path = `/search?title=${encodeURIComponent(keyword.trim())}` +
      `&tab=${encodeURIComponent(tab)}&source=${encodeURIComponent('全部')}` +
      `&page=${safePage}&disabled_sources=0`;
    const root = await GuangYuApiClient.requestJson(path, 'GET', undefined, GuangYuResponseKind.SEARCH);
    const response = GuangYuApiClient.parseSearchRoot(root);
    for (const item of response.items) {
      if (item.tab.length === 0) item.tab = tab;
    }
    return response;
  }

  static async detail(route: GuangYuRoute): Promise<GuangYuDetailResponseDto> {
    const variable = GuangYuApiClient.variableJson(route.toneId);
    const path = `/detail?book_id=${encodeURIComponent(route.bookId)}` +
      `&source=${encodeURIComponent(route.provider)}&tab=${encodeURIComponent(route.tab)}` +
      `&variable=${encodeURIComponent(variable)}`;
    const body = new GuangYuHtmlRequestBody();
    const root = await GuangYuApiClient.requestJson(path, 'POST', body, GuangYuResponseKind.DETAIL);
    return GuangYuApiClient.parseDetailRoot(root);
  }

  static async catalog(route: GuangYuRoute): Promise<GuangYuCatalogResponseDto> {
    const variable = GuangYuApiClient.variableJson(route.toneId);
    const path = `/catalog?book_id=${encodeURIComponent(route.bookId)}` +
      `&source=${encodeURIComponent(route.provider)}&tab=${encodeURIComponent(route.tab)}` +
      `&variable=${encodeURIComponent(variable)}`;
    const body = new GuangYuHtmlRequestBody();
    const root = await GuangYuApiClient.requestJson(path, 'POST', body, GuangYuResponseKind.CATALOG);
    return GuangYuApiClient.parseCatalogRoot(root);
  }

  static async content(route: GuangYuRoute): Promise<GuangYuContentResponseDto> {
    const request = GuangYuApiClient.createContentRequest(route);
    const root = await GuangYuApiClient.requestJson(
      request.path, 'POST', request.body, GuangYuResponseKind.CONTENT);
    return GuangYuApiClient.parseContentRoot(root);
  }

  static createContentRequest(route: GuangYuRoute): GuangYuContentRequestPlan {
    const request = new GuangYuContentRequestPlan();
    const provider = route.provider.trim();
    const tab = route.tab.trim();
    const isNovel = tab === NOVEL_TAB;
    request.path = isNovel && CONTENT_REVIEW_SOURCES.includes(provider)
      ? '/content?review=1' : '/content';
    request.body.item_id = route.itemId;
    request.body.source = route.provider;
    request.body.tab = route.tab;
    request.body.tone_id = GuangYuApiClient.normalizedToneId(route.toneId);
    request.body.variable = GuangYuApiClient.variableJson(route.toneId);
    request.body.god = isNovel && CONTENT_GOD_SOURCES.includes(provider);
    return request;
  }

  static parseSearchResponse(payload: string): GuangYuSearchResponseDto {
    const root = GuangYuApiClient.parseSuccessfulRoot(payload, GuangYuResponseKind.SEARCH);
    return GuangYuApiClient.parseSearchRoot(root);
  }

  static parseDetailResponse(payload: string): GuangYuDetailResponseDto {
    const root = GuangYuApiClient.parseSuccessfulRoot(payload, GuangYuResponseKind.DETAIL);
    return GuangYuApiClient.parseDetailRoot(root);
  }

  static parseCatalogResponse(payload: string): GuangYuCatalogResponseDto {
    const root = GuangYuApiClient.parseSuccessfulRoot(payload, GuangYuResponseKind.CATALOG);
    return GuangYuApiClient.parseCatalogRoot(root);
  }

  static parseContentResponse(payload: string): GuangYuContentResponseDto {
    const root = GuangYuApiClient.parseSuccessfulRoot(payload, GuangYuResponseKind.CONTENT);
    return GuangYuApiClient.parseContentRoot(root);
  }

  static isBusinessError(error: Object): boolean {
    return error instanceof GuangYuApiBusinessError;
  }

  static businessErrorMessage(code: number, value: string): string {
    const clean = GuangYuApiClient.safeDiagnosticMessage(value);
    if (clean.includes('访问速度过快')) {
      return '光遇聚合访问过快，请等待 30 秒后再试';
    }
    if (clean.includes('暂时封禁')) {
      return '光遇聚合访问过快，账号已被临时限流，请稍后再试';
    }
    return clean.length > 0 ? clean : `服务返回错误 ${code}`;
  }

  static isHttpMediaUrl(value: string): boolean {
    const clean = value.trim();
    const lower = clean.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) return false;
    if (clean.includes('\r') || clean.includes('\n') || clean.includes('\t') || clean.includes(' ')) return false;
    const schemeEnd = clean.indexOf('://');
    if (schemeEnd < 0) return false;
    const authorityStart = schemeEnd + 3;
    let authorityEnd = clean.indexOf('/', authorityStart);
    if (authorityEnd < 0) authorityEnd = clean.length;
    const queryStart = clean.indexOf('?', authorityStart);
    if (queryStart >= 0) authorityEnd = Math.min(authorityEnd, queryStart);
    return authorityEnd > authorityStart;
  }

  private static async requestJson(path: string, method: string, body: Object | undefined,
    responseKind: number): Promise<GuangYuJsonObject> {
    let lastFailure = '无可用线路';
    const hostCount = GuangYuApiClient.HOSTS.length;
    const initialHostIndex = GuangYuApiClient.preferredHostIndex;
    for (let offset = 0; offset < hostCount; offset++) {
      const hostIndex = (initialHostIndex + offset) % hostCount;
      const host = GuangYuApiClient.HOSTS[hostIndex];
      const headers = await GuangYuApiClient.createHeaders(host);
      const options: HttpRequestOptions = {
        method: method,
        headers: headers,
        body: body,
        timeout: REQUEST_TIMEOUT_MS,
        charset: 'utf-8',
        retry: 0
      };
      let response: HttpResponse | undefined = undefined;
      try {
        response = await HttpClient.request(host + path, options);
      } catch (error) {
        lastFailure = GuangYuApiClient.errorMessage(error as Object);
        hilog.warn(0x11, 'GuangYuApi', 'request %{public}s%{public}s failed: %{public}s',
          host, path, GuangYuApiClient.safeDiagnosticMessage(lastFailure));
        GuangYuApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      if (response.statusCode >= 500 && response.statusCode <= 599) {
        lastFailure = `HTTP ${response.statusCode}`;
        GuangYuApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new Error(`光遇聚合请求失败：HTTP ${response.statusCode}`);
      }
      if (buffer.byteLength(response.body, 'utf-8') > MAX_RESPONSE_BYTES) {
        lastFailure = `响应超过 ${MAX_RESPONSE_BYTES} 字节`;
        GuangYuApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      try {
        const root = GuangYuApiClient.parseSuccessfulRoot(response.body, responseKind);
        GuangYuApiClient.preferredHostIndex = hostIndex;
        return root;
      } catch (error) {
        if (error instanceof GuangYuApiBusinessError) {
          hilog.warn(0x11, 'GuangYuApi',
            'business error host=%{public}s path=%{public}s code=%{public}d msg=%{public}s',
            host, path, error.code, GuangYuApiClient.safeDiagnosticMessage(error.message));
          GuangYuApiClient.preferredHostIndex = hostIndex;
          throw error;
        }
        lastFailure = GuangYuApiClient.errorMessage(error as Object);
        GuangYuApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
      }
    }
    throw new Error(`光遇聚合 HTTPS 线路均不可用：${lastFailure}`);
  }

  private static async createHeaders(host: string): Promise<Record<string, string>> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json,text/plain;q=0.9,*/*;q=0.8';
    headers['User-Agent'] = GUANG_YU_USER_AGENT;
    const stableDeviceId = await GuangYuApiClient.getOrCreateDeviceId();
    let session: LocalRuleSourceSession | undefined = undefined;
    try {
      session = await LocalRuleSourceRepository.getSession(GUANG_YU_SOURCE_URL);
    } catch (_error) {
      session = undefined;
    }
    let token = '';
    let deviceId = stableDeviceId;
    if (session !== undefined) {
      token = GuangYuApiClient.safeCookiePart(session.token);
      const storedDeviceId = GuangYuApiClient.safeCookiePart(session.deviceId);
      if (storedDeviceId.length > 0) deviceId = storedDeviceId;
    }
    let webCookieHeader = '';
    try {
      webCookieHeader = await LocalRuleHttpClient.getStoredCookieHeader(
        GUANG_YU_SOURCE_URL, host);
      if (webCookieHeader.length === 0 && host !== GuangYuApiClient.HOSTS[0]) {
        webCookieHeader = await LocalRuleHttpClient.getStoredCookieHeader(
          GUANG_YU_SOURCE_URL, GuangYuApiClient.HOSTS[0]);
      }
    } catch (_error) {
      webCookieHeader = '';
    }
    headers['Cookie'] = GuangYuApiClient.mergeWebCookies(webCookieHeader, token, deviceId);
    return headers;
  }

  private static mergeWebCookies(webCookieHeader: string, token: string, deviceId: string): string {
    const output: string[] = [];
    output.push(`qttoken=${token}`);
    output.push(`deviceId=${deviceId}`);
    if (webCookieHeader.length === 0 || webCookieHeader.includes('\r') ||
      webCookieHeader.includes('\n')) {
      return output.join('; ');
    }
    const namePattern = new RegExp('^[A-Za-z0-9_\\-]+$');
    const pairs = webCookieHeader.split(';');
    for (const rawPair of pairs) {
      const pair = rawPair.trim();
      const separator = pair.indexOf('=');
      if (separator <= 0) continue;
      const name = pair.substring(0, separator).trim();
      const lowerName = name.toLowerCase();
      const value = pair.substring(separator + 1).trim();
      if (lowerName === 'qttoken' || lowerName === 'deviceid') continue;
      if (!namePattern.test(name) || name.length > 128 || value.length === 0 || value.length > 4096) continue;
      output.push(`${name}=${value}`);
      if (output.length >= 50) break;
    }
    return output.join('; ');
  }

  private static safeCookiePart(value: string): string {
    if (value.includes('\r') || value.includes('\n') || value.includes('\t') || value.includes(';')) return '';
    return value;
  }

  private static safeDiagnosticMessage(value: string): string {
    let output = '';
    for (let index = 0; index < value.length && output.length < 160; index++) {
      const character = value.charAt(index);
      output += character === '\r' || character === '\n' ? ' ' : character;
    }
    return output.trim();
  }

  private static variableJson(toneId: string): string {
    const variable = new GuangYuVariableValue();
    const normalized = GuangYuApiClient.normalizedToneId(toneId);
    variable.custom = normalized === '4' ? '' : normalized;
    return JSON.stringify(variable);
  }

  private static normalizedToneId(toneId: string): string {
    const clean = toneId.trim();
    return clean.length > 0 ? clean : '4';
  }

  private static parseSuccessfulRoot(payload: string, responseKind: number): GuangYuJsonObject {
    const root = GuangYuJsonObject.parse(payload);
    if (!root.has('code')) throw new GuangYuInvalidResponseError('响应缺少 code');
    const code = root.getNumber('code', Number.NaN);
    if (!Number.isFinite(code)) throw new GuangYuInvalidResponseError('响应 code 无效');
    if (code !== 0) {
      const message = GuangYuApiClient.businessErrorMessage(code, root.getString('msg'));
      throw new GuangYuApiBusinessError(code, message);
    }
    if (responseKind === GuangYuResponseKind.SEARCH || responseKind === GuangYuResponseKind.CATALOG) {
      if (root.getArray('data') === undefined) {
        throw new GuangYuInvalidResponseError('响应 data 不是数组');
      }
    } else if (responseKind === GuangYuResponseKind.DETAIL) {
      if (root.getObject('data') === undefined) {
        throw new GuangYuInvalidResponseError('响应 data 不是对象');
      }
    } else if (responseKind === GuangYuResponseKind.CONTENT && !root.has('content')) {
      throw new GuangYuInvalidResponseError('响应缺少 content');
    }
    return root;
  }

  private static parseSearchRoot(root: GuangYuJsonObject): GuangYuSearchResponseDto {
    const response = new GuangYuSearchResponseDto();
    GuangYuApiClient.readMeta(root, response);
    response.disabledSources = root.getStringArray('disabled_sources');
    const timings = root.getArray('source_time_cost');
    if (timings !== undefined) {
      for (const value of timings) {
        const itemRoot = GuangYuJsonObject.fromValue(value);
        if (itemRoot === undefined) continue;
        const timing = new GuangYuSourceTimingDto();
        timing.source = itemRoot.getString('source');
        timing.cacheData = itemRoot.getBoolean('cacheData');
        timing.timeCost = itemRoot.getNumber('timeCost');
        timing.resultCount = itemRoot.getNumber('resultCount');
        response.sourceTimings.push(timing);
      }
    }
    const data = root.getArray('data');
    if (data === undefined) return response;
    for (const value of data) {
      const itemRoot = GuangYuJsonObject.fromValue(value);
      if (itemRoot === undefined) continue;
      const item = new GuangYuSearchItemDto();
      item.bookName = itemRoot.getString('book_name');
      item.bookId = itemRoot.getString('book_id');
      item.author = itemRoot.getString('author');
      item.score = itemRoot.getString('score');
      item.status = itemRoot.getString('status');
      item.wordNumber = itemRoot.getString('word_number');
      item.lastChapterUpdateTime = itemRoot.getString('last_chapter_update_time');
      item.lastChapterTitle = itemRoot.getString('last_chapter_title');
      item.category = itemRoot.getString('category');
      item.tags = itemRoot.getString('tags');
      item.abstract = itemRoot.getString('abstract');
      item.readCount = itemRoot.getString('read_count');
      item.readCountAll = itemRoot.getString('read_count_all');
      item.thumbUrl = itemRoot.getString('thumb_url');
      item.role = itemRoot.getString('role');
      item.tab = itemRoot.getString('tab');
      item.source = itemRoot.getString('source');
      item.bookUrl = itemRoot.getString('book_url');
      item.tocUrl = itemRoot.getString('toc_url');
      item.detailUrl = itemRoot.getString('detail_url');
      response.items.push(item);
    }
    return response;
  }

  private static parseDetailRoot(root: GuangYuJsonObject): GuangYuDetailResponseDto {
    const response = new GuangYuDetailResponseDto();
    GuangYuApiClient.readMeta(root, response);
    const data = root.getObject('data');
    if (data === undefined) throw new GuangYuInvalidResponseError('详情响应缺少 data');
    const detail = response.detail;
    detail.bookName = data.getString('book_name');
    detail.aliasName = data.getString('alias_name');
    detail.bookId = data.getString('book_id');
    detail.relatedNovelBookId = data.getString('relate_novel_book_id');
    detail.author = data.getString('author');
    detail.score = data.getString('score');
    detail.status = data.getString('status');
    detail.wordNumber = data.getString('word_number');
    detail.lastChapterUpdateTime = data.getString('last_chapter_update_time');
    detail.category = data.getString('category');
    detail.tags = data.getString('tags');
    detail.abstract = data.getString('abstract');
    detail.readCount = data.getString('read_count');
    detail.readCountAll = data.getString('read_count_all');
    detail.thumbUrl = data.getString('thumb_url');
    detail.tab = data.getString('tab');
    detail.source = data.getString('source');
    detail.role = data.getString('role');
    detail.media = data.getString('media');
    detail.lastChapterTitle = data.getString('last_chapter_title');
    detail.copyrightInfo = data.getString('copyright_info');
    detail.bookReview = data.getString('book_review');
    detail.bookTts = data.getString('book_tts');
    detail.toneOptions = data.getStringRecord('book_tts_dice');
    detail.bookUrl = data.getString('book_url');
    detail.tocUrl = data.getString('toc_url');
    detail.catalogUrl = data.getString('catalog_url');
    return response;
  }

  private static parseCatalogRoot(root: GuangYuJsonObject): GuangYuCatalogResponseDto {
    const response = new GuangYuCatalogResponseDto();
    GuangYuApiClient.readMeta(root, response);
    const data = root.getArray('data');
    if (data === undefined) return response;
    for (const value of data) {
      const itemRoot = GuangYuJsonObject.fromValue(value);
      if (itemRoot === undefined) continue;
      const item = new GuangYuCatalogItemDto();
      item.title = itemRoot.getString('title');
      item.itemId = itemRoot.getString('item_id');
      item.firstPassTime = itemRoot.getString('first_pass_time');
      item.chapterWordNumber = itemRoot.getString('chapter_word_number');
      item.source = itemRoot.getString('source');
      item.tab = itemRoot.getString('tab');
      item.url = itemRoot.getString('url');
      item.isPay = itemRoot.getBoolean('is_pay');
      item.isVolume = itemRoot.getBoolean('is_volume');
      item.tocUrl = itemRoot.getString('toc_url');
      item.contentUrl = itemRoot.getString('content_url');
      response.items.push(item);
    }
    return response;
  }

  private static parseContentRoot(root: GuangYuJsonObject): GuangYuContentResponseDto {
    const response = new GuangYuContentResponseDto();
    GuangYuApiClient.readMeta(root, response);
    response.title = root.getString('title');
    response.content = root.getString('content');
    return response;
  }

  private static readMeta(root: GuangYuJsonObject,
    response: GuangYuSearchResponseDto | GuangYuDetailResponseDto |
      GuangYuCatalogResponseDto | GuangYuContentResponseDto): void {
    response.code = root.getNumber('code');
    response.message = root.getString('msg');
    response.cache = root.getBoolean('cache');
    response.timeMs = root.getNumber('time');
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '请求失败';
    return String(error || '请求失败');
  }
}
