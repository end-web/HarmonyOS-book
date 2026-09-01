import { buffer, util } from '@kit.ArkTS';
import { LocalRuleSourceSession } from '../../../model/LocalRuleSource';
import { JsonArr, JsonObj } from '../../builtin/JsonValue';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../http/HttpClient';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { ShuShanContentCrypto } from './ShuShanContentCrypto';
import {
  SHU_SHAN_SOURCE_URL,
  ShuShanRoute
} from './ShuShanSourceIdentity';

const REQUEST_TIMEOUT_MS: number = 20000;
const MAX_RESPONSE_BYTES: number = 8 * 1024 * 1024;
const MAX_SEARCH_ITEMS: number = 50;
const MAX_CATALOG_ITEMS: number = 20000;
const SOURCE_ACCESS_TOKEN: string = 'SHUSAN_READ_2025';
const CONTENT_PROTOCOL_VERSION: string = '12';
const NOVEL_MODE: string = '小说';
const AUDIO_MODE: string = '听书';

class ShuShanResponseKind {
  static readonly SEARCH: number = 1;
  static readonly DETAIL: number = 2;
  static readonly CATALOG: number = 3;
  static readonly CONTENT: number = 4;
  static readonly AUDIO: number = 5;
}

class ShuShanInvalidResponseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShuShanInvalidResponseError';
  }
}

export class ShuShanApiBusinessError extends Error {
  code: number = -1;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'ShuShanApiBusinessError';
    this.code = code;
  }
}

class ShuShanDetailRequestBody {
  source: string = '';
  url: string = '';
  cover: string = '';
  desc: string = '';
  name: string = '';
}

class ShuShanCatalogRequestBody {
  source: string = '';
  url: string = '';
  name: string = '';
  tab: string = 'novel';
  bookid: string = '';
}

export class ShuShanContentRequestPlan {
  path: string = '/content';
  method: string = 'POST';
  body: Record<string, Object> | undefined = undefined;
  audio: boolean = false;
}

export class ShuShanSearchItemDto {
  title: string = '';
  author: string = '';
  tags: string = '';
  cover: string = '';
  desc: string = '';
  wordCount: string = '';
  latestChapterTitle: string = '';
  bookUrl: string = '';
  source: string = '';
  tab: string = '';
}

export class ShuShanSearchResponseDto {
  success: boolean = false;
  message: string = '';
  items: ShuShanSearchItemDto[] = [];
}

export class ShuShanDetailDto {
  bookUrl: string = '';
  title: string = '';
  author: string = '';
  tags: string = '';
  cover: string = '';
  desc: string = '';
  wordCount: string = '';
  latestChapterTitle: string = '';
  source: string = '';
  tab: string = '';
  bookId: string = '';
}

export class ShuShanDetailResponseDto {
  code: number = 0;
  message: string = '';
  detail: ShuShanDetailDto = new ShuShanDetailDto();
}

export class ShuShanCatalogItemDto {
  url: string = '';
  title: string = '';
  chapterId: string = '';
  tag: string = '';
  isVolume: boolean = false;
  isVip: boolean = false;
  isPay: boolean = false;
}

export class ShuShanCatalogResponseDto {
  code: number = 0;
  message: string = '';
  items: ShuShanCatalogItemDto[] = [];
}

export class ShuShanContentResponseDto {
  code: number = 0;
  message: string = '';
  title: string = '';
  content: string = '';
  audioUrl: string = '';
  tab: string = '';
  notice: string = '';
  sayBody: string = '';
}

/** 书山聚合原生客户端，只访问白名单 HTTPS 主机，不执行书源脚本。 */
export class ShuShanApiClient {
  private static readonly HOSTS: string[] = [
    'https://v1.vossc.com',
    'https://v2.vossc.com',
    'https://v3.vossc.com',
    'https://v4.vossc.com'
  ];
  private static preferredHostIndex: number = 0;
  private static runtimeDeviceId: string = '';

  static hosts(): string[] {
    return ShuShanApiClient.HOSTS.slice();
  }

  static async getOrCreateDeviceId(): Promise<string> {
    const cached = ShuShanApiClient.safeHeaderValue(ShuShanApiClient.runtimeDeviceId);
    if (cached.length > 0) return cached;

    let session: LocalRuleSourceSession | undefined = undefined;
    let sessionReadSucceeded = false;
    try {
      session = await LocalRuleSourceRepository.getSession(SHU_SHAN_SOURCE_URL);
      sessionReadSucceeded = true;
    } catch (_error) {
      session = undefined;
    }
    if (session !== undefined) {
      const stored = ShuShanApiClient.safeHeaderValue(session.deviceId);
      if (stored.length > 0) {
        ShuShanApiClient.runtimeDeviceId = stored;
        return stored;
      }
    }

    const concurrentValue = ShuShanApiClient.safeHeaderValue(ShuShanApiClient.runtimeDeviceId);
    if (concurrentValue.length > 0) return concurrentValue;
    const generated = util.generateRandomUUID();
    ShuShanApiClient.runtimeDeviceId = generated;
    if (sessionReadSucceeded) {
      const token = session !== undefined ? session.token : '';
      const accountLabel = session !== undefined ? session.accountLabel : '';
      const anonymousSession = LocalRuleSourceSession.of(
        SHU_SHAN_SOURCE_URL, token, generated, accountLabel);
      try {
        await LocalRuleSourceRepository.saveSession(anonymousSession);
      } catch (_error) {
        // 书源尚未落库时保留进程内设备标识，匿名搜索仍可使用。
      }
    }
    return generated;
  }

  static async search(mode: string, keyword: string, page: number = 1): Promise<ShuShanSearchResponseDto> {
    const cleanKeyword = ShuShanApiClient.boundedKeyword(keyword);
    if (cleanKeyword.length === 0) return new ShuShanSearchResponseDto();
    let searchKey = cleanKeyword;
    if (!cleanKeyword.includes('@')) {
      const normalizedMode = mode.trim().toLowerCase();
      if (normalizedMode === 'audio' || normalizedMode === AUDIO_MODE) {
        searchKey = `${cleanKeyword}@${AUDIO_MODE}`;
      } else if (normalizedMode.length > 0) {
        searchKey = `${cleanKeyword}@${NOVEL_MODE}`;
      }
    }
    const safePage = Math.max(1, Math.min(1000, Math.trunc(page)));
    const path = `/search?login=search&key=${encodeURIComponent(searchKey)}&page=${safePage}`;
    const root = await ShuShanApiClient.requestJson(
      path, 'GET', undefined, ShuShanResponseKind.SEARCH, false);
    return ShuShanApiClient.parseSearchRoot(root);
  }

  static async detail(route: ShuShanRoute): Promise<ShuShanDetailResponseDto> {
    const body = new ShuShanDetailRequestBody();
    body.source = route.provider;
    body.url = route.bookUrl;
    body.name = route.title;
    const root = await ShuShanApiClient.requestJson(
      '/details', 'POST', body, ShuShanResponseKind.DETAIL, false);
    return ShuShanApiClient.parseDetailRoot(root);
  }

  static async catalog(route: ShuShanRoute): Promise<ShuShanCatalogResponseDto> {
    const body = new ShuShanCatalogRequestBody();
    body.source = route.provider;
    body.url = route.bookUrl;
    body.name = route.title;
    body.tab = route.tab || 'novel';
    body.bookid = route.bookId;
    const root = await ShuShanApiClient.requestJson(
      '/catalog', 'POST', body, ShuShanResponseKind.CATALOG, false);
    return ShuShanApiClient.parseCatalogRoot(root);
  }

  static async content(route: ShuShanRoute): Promise<ShuShanContentResponseDto> {
    const request = ShuShanApiClient.createContentRequest(route);
    const kind = request.audio ? ShuShanResponseKind.AUDIO : ShuShanResponseKind.CONTENT;
    const root = await ShuShanApiClient.requestJson(
      request.path, request.method, request.body, kind, true);
    if (request.audio) return ShuShanApiClient.parseAudioRoot(root);
    return await ShuShanApiClient.parseContentRoot(root);
  }

  static createContentRequest(route: ShuShanRoute): ShuShanContentRequestPlan {
    const request = new ShuShanContentRequestPlan();
    const provider = route.provider.trim();
    if (provider === '番茄听书' || provider === '番茄畅听') {
      const itemId = ShuShanApiClient.requiredChapterParam(route, 'item_id');
      const toneId = route.toneId.trim() || '1';
      request.path = `/audio?tone_id=${encodeURIComponent(toneId)}` +
        `&item_ids=${encodeURIComponent(itemId)}`;
      request.method = 'GET';
      request.audio = true;
      return request;
    }
    if (provider === '书旗听书') {
      const itemId = ShuShanApiClient.requiredChapterParam(route, 'item_ids');
      const toneId = route.toneId.trim() || 'yifei';
      request.path = `/audio?bookid=${encodeURIComponent(route.bookId)}` +
        `&item_ids=${encodeURIComponent(itemId)}&tone_id=${encodeURIComponent(toneId)}`;
      request.method = 'GET';
      request.audio = true;
      return request;
    }

    const body: Record<string, Object> = {};
    body['cid'] = route.chapterId;
    body['source'] = provider;
    body['version'] = CONTENT_PROTOCOL_VERSION;
    const fanqieProviders: string[] = ['番茄小说', '番茄短剧', '番茄听书', '番茄畅听'];
    if (fanqieProviders.includes(provider)) {
      body['book_id'] = route.bookId;
      body['item_id'] = ShuShanApiClient.chapterParam(route.chapterUrl, 'item_id');
    } else {
      body['url'] = route.bookUrl;
    }
    ShuShanApiClient.applyProviderChapterParams(body, route);
    request.body = body;
    return request;
  }

  static parseSearchResponse(payload: string): ShuShanSearchResponseDto {
    const root = ShuShanApiClient.parseSuccessfulRoot(payload, ShuShanResponseKind.SEARCH);
    return ShuShanApiClient.parseSearchRoot(root);
  }

  static parseDetailResponse(payload: string): ShuShanDetailResponseDto {
    const root = ShuShanApiClient.parseSuccessfulRoot(payload, ShuShanResponseKind.DETAIL);
    return ShuShanApiClient.parseDetailRoot(root);
  }

  static parseCatalogResponse(payload: string): ShuShanCatalogResponseDto {
    const root = ShuShanApiClient.parseSuccessfulRoot(payload, ShuShanResponseKind.CATALOG);
    return ShuShanApiClient.parseCatalogRoot(root);
  }

  static async parseContentResponse(payload: string): Promise<ShuShanContentResponseDto> {
    const root = ShuShanApiClient.parseSuccessfulRoot(payload, ShuShanResponseKind.CONTENT);
    return await ShuShanApiClient.parseContentRoot(root);
  }

  static parseAudioResponse(payload: string): ShuShanContentResponseDto {
    const root = ShuShanApiClient.parseSuccessfulRoot(payload, ShuShanResponseKind.AUDIO);
    return ShuShanApiClient.parseAudioRoot(root);
  }

  static async normalizeContent(value: string): Promise<string> {
    const clean = value.trim();
    if (clean.length === 0) return '';
    const lower = clean.toLowerCase();
    if (lower.includes('api密钥') || lower.includes('密钥格式无效') ||
      lower.includes('用户不存在') || lower.includes('请先登录')) {
      throw new ShuShanApiBusinessError(401, '书山聚合登录已失效，请重新登录');
    }

    if (ShuShanApiClient.isStandardBase64(clean)) {
      try {
        const decoded = buffer.from(clean, 'base64').toString('utf-8').trim();
        if (decoded.length > 0 && ShuShanApiClient.isReadableText(decoded)) return decoded;
      } catch (_error) {
        // 继续尝试书山 5.42 的旧版正文协议。
      }
      const decrypted = await ShuShanContentCrypto.decryptLegacyBase64(clean);
      if (decrypted.length > 0 && ShuShanApiClient.isReadableText(decrypted)) return decrypted;
      throw new ShuShanInvalidResponseError(
        '书山聚合返回了当前版本无法安全解码的加密正文');
    }
    if (ShuShanApiClient.looksObfuscated(clean)) {
      throw new ShuShanApiBusinessError(401,
        '书山聚合正文是无效加密数据，请确认账号已登录');
    }
    if (!ShuShanApiClient.isReadableText(clean)) {
      throw new ShuShanInvalidResponseError('书山聚合返回了不可读的正文数据');
    }
    return clean;
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
    responseKind: number, requireLogin: boolean): Promise<JsonObj> {
    const headers = await ShuShanApiClient.createHeaders(
      requireLogin, responseKind === ShuShanResponseKind.CONTENT, method !== 'GET');
    let lastFailure = '无可用线路';
    const hostCount = ShuShanApiClient.HOSTS.length;
    const initialHostIndex = ShuShanApiClient.preferredHostIndex;
    for (let offset = 0; offset < hostCount; offset++) {
      const hostIndex = (initialHostIndex + offset) % hostCount;
      const host = ShuShanApiClient.HOSTS[hostIndex];
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
        lastFailure = ShuShanApiClient.errorMessage(error as Object);
        ShuShanApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      if (response.statusCode === 401 || response.statusCode === 403) {
        throw new ShuShanApiBusinessError(response.statusCode,
          '书山聚合需要登录或登录已失效');
      }
      if (response.statusCode >= 500 && response.statusCode <= 599) {
        lastFailure = `HTTP ${response.statusCode}`;
        ShuShanApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new Error(`书山聚合请求失败：HTTP ${response.statusCode}`);
      }
      if (buffer.byteLength(response.body, 'utf-8') > MAX_RESPONSE_BYTES) {
        lastFailure = `响应超过 ${MAX_RESPONSE_BYTES} 字节`;
        ShuShanApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
        continue;
      }
      try {
        const root = ShuShanApiClient.parseSuccessfulRoot(response.body, responseKind);
        ShuShanApiClient.preferredHostIndex = hostIndex;
        return root;
      } catch (error) {
        if (error instanceof ShuShanApiBusinessError) {
          ShuShanApiClient.preferredHostIndex = hostIndex;
          throw error;
        }
        lastFailure = ShuShanApiClient.errorMessage(error as Object);
        ShuShanApiClient.preferredHostIndex = (hostIndex + 1) % hostCount;
      }
    }
    throw new Error(`书山聚合 HTTPS 线路均不可用：${lastFailure}`);
  }

  private static async createHeaders(requireLogin: boolean, includeDeviceHeaders: boolean,
    includeJsonContentType: boolean): Promise<Record<string, string>> {
    const headers: Record<string, string> = {};
    headers['Accept'] = 'application/json,text/plain;q=0.9,*/*;q=0.8';
    if (includeJsonContentType) headers['Content-Type'] = 'application/json';
    headers['User-Agent'] = 'Mozilla/5.0 (Linux; HarmonyOS; Mobile) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36';
    headers['X-Novel-Token'] = SOURCE_ACCESS_TOKEN;
    const rawApiKey = await ShuShanApiClient.readRawApiKey();
    if (requireLogin && rawApiKey.length === 0) {
      throw new ShuShanApiBusinessError(401, '书山聚合需要先登录才能获取正文或音频');
    }
    if (rawApiKey.length > 0) {
      headers['X-Api-Key'] = buffer.from(rawApiKey, 'utf-8').toString('base64');
    }
    if (includeDeviceHeaders) {
      headers['X-Device-Type'] = 'android';
      headers['X-Device-Id'] = await ShuShanApiClient.getOrCreateDeviceId();
    }
    return headers;
  }

  private static async readRawApiKey(): Promise<string> {
    try {
      const session = await LocalRuleSourceRepository.getSession(SHU_SHAN_SOURCE_URL);
      if (session === undefined) return '';
      return ShuShanApiClient.safeHeaderValue(session.token);
    } catch (_error) {
      return '';
    }
  }

  private static parseSuccessfulRoot(payload: string, responseKind: number): JsonObj {
    let parsed: Object;
    try {
      parsed = JSON.parse(payload) as Object;
    } catch (_error) {
      throw new ShuShanInvalidResponseError('响应不是有效 JSON');
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new ShuShanInvalidResponseError('响应根节点不是对象');
    }
    const root = new JsonObj(parsed);
    ShuShanApiClient.assertBusinessSuccess(root, responseKind);
    const data = root.raw['data'];
    if (responseKind === ShuShanResponseKind.SEARCH || responseKind === ShuShanResponseKind.CATALOG ||
      responseKind === ShuShanResponseKind.AUDIO) {
      if (!Array.isArray(data)) throw new ShuShanInvalidResponseError('响应 data 不是数组');
    } else if (data === undefined || data === null || typeof data !== 'object' || Array.isArray(data)) {
      throw new ShuShanInvalidResponseError('响应 data 不是对象');
    }
    return root;
  }

  private static assertBusinessSuccess(root: JsonObj, responseKind: number): void {
    if (responseKind === ShuShanResponseKind.SEARCH) {
      if (!ShuShanApiClient.getBoolean(root, 'isSuccess', false)) {
        throw new ShuShanApiBusinessError(-1,
          ShuShanApiClient.serverMessage(root, '搜索失败'));
      }
      return;
    }
    if (root.has('status')) {
      const status = root.getInt('status', -1);
      const success = responseKind === ShuShanResponseKind.AUDIO
        ? status === 0 || status === 200 : status === 200;
      if (!success) {
        throw new ShuShanApiBusinessError(status,
          ShuShanApiClient.serverMessage(root, `服务返回错误 ${status}`));
      }
    }
    if (root.has('code')) {
      const code = root.getInt('code', -1);
      const success = responseKind === ShuShanResponseKind.AUDIO
        ? code === 0 || code === 200 : code === 200;
      if (!success) {
        throw new ShuShanApiBusinessError(code,
          ShuShanApiClient.serverMessage(root, `服务返回错误 ${code}`));
      }
    }
  }

  private static parseSearchRoot(root: JsonObj): ShuShanSearchResponseDto {
    const response = new ShuShanSearchResponseDto();
    response.success = true;
    response.message = root.getString('error');
    const data = root.getArr('data');
    const count = Math.min(data.length(), MAX_SEARCH_ITEMS);
    for (let index = 0; index < count; index++) {
      const itemRoot = data.getObj(index);
      const item = new ShuShanSearchItemDto();
      item.title = itemRoot.getString('title');
      item.author = itemRoot.getString('author');
      item.tags = itemRoot.getString('tags');
      item.cover = itemRoot.getString('cover');
      item.desc = itemRoot.getString('desc');
      item.wordCount = itemRoot.getString('wordCount');
      item.latestChapterTitle = itemRoot.getString('latestChapterTitle');
      item.bookUrl = itemRoot.getString('book_url');
      item.source = itemRoot.getString('source');
      item.tab = itemRoot.getString('tab');
      if (item.title.trim().length > 0 && item.bookUrl.trim().length > 0 &&
        item.source.trim().length > 0) {
        response.items.push(item);
      }
    }
    return response;
  }

  private static parseDetailRoot(root: JsonObj): ShuShanDetailResponseDto {
    const response = new ShuShanDetailResponseDto();
    response.code = root.getInt('code', 200);
    response.message = ShuShanApiClient.serverMessage(root, '');
    const data = root.getObj('data');
    const detail = response.detail;
    detail.bookUrl = data.getString('book_url');
    detail.title = data.getString('title');
    detail.author = data.getString('author');
    detail.tags = data.getString('tags');
    detail.cover = data.getString('cover');
    detail.desc = data.getString('desc');
    detail.wordCount = data.getString('wordCount');
    detail.latestChapterTitle = ShuShanApiClient.firstNonEmpty(
      data.getString('latestChapterTitle'), data.getString('lastChapterTitle'));
    detail.source = data.getString('source');
    detail.tab = data.getString('tab');
    detail.bookId = data.getString('bookid');
    if (detail.title.trim().length === 0 || detail.bookUrl.trim().length === 0 ||
      detail.source.trim().length === 0) {
      throw new ShuShanInvalidResponseError('详情响应缺少书籍定位字段');
    }
    return response;
  }

  private static parseCatalogRoot(root: JsonObj): ShuShanCatalogResponseDto {
    const response = new ShuShanCatalogResponseDto();
    response.code = root.getInt('code', 200);
    response.message = ShuShanApiClient.serverMessage(root, '');
    const data = root.getArr('data');
    const count = Math.min(data.length(), MAX_CATALOG_ITEMS);
    for (let index = 0; index < count; index++) {
      const itemRoot = data.getObj(index);
      const item = new ShuShanCatalogItemDto();
      item.url = itemRoot.getString('url');
      item.title = itemRoot.getString('title');
      item.chapterId = itemRoot.getString('cid');
      item.tag = itemRoot.getString('tag');
      item.isVolume = ShuShanApiClient.getBoolean(itemRoot, 'isVolume', false);
      item.isVip = ShuShanApiClient.getBoolean(itemRoot, 'isVip', false);
      item.isPay = ShuShanApiClient.getBoolean(itemRoot, 'isPay', false);
      response.items.push(item);
    }
    return response;
  }

  private static async parseContentRoot(root: JsonObj): Promise<ShuShanContentResponseDto> {
    const response = new ShuShanContentResponseDto();
    response.code = root.getInt('code', 200);
    response.message = ShuShanApiClient.serverMessage(root, '');
    const data = root.getObj('data');
    response.title = data.getString('title');
    response.tab = data.getString('tab');
    response.notice = data.getString('notice');
    response.sayBody = data.getString('sayBody');
    response.content = await ShuShanApiClient.normalizeContent(data.getString('content'));
    if (response.content.length === 0) {
      throw new ShuShanInvalidResponseError('正文响应缺少 content');
    }
    return response;
  }

  private static parseAudioRoot(root: JsonObj): ShuShanContentResponseDto {
    const response = new ShuShanContentResponseDto();
    response.code = root.getInt('code', 200);
    response.message = ShuShanApiClient.serverMessage(root, '');
    const data: JsonArr = root.getArr('data');
    for (let index = 0; index < data.length(); index++) {
      const mainUrl = data.getObj(index).getString('main_url').trim();
      if (ShuShanApiClient.isHttpMediaUrl(mainUrl)) {
        response.audioUrl = mainUrl;
        response.tab = 'audio';
        return response;
      }
    }
    throw new ShuShanInvalidResponseError(
      ShuShanApiClient.serverMessage(root, '听书响应没有真实音频地址'));
  }

  private static applyProviderChapterParams(body: Record<string, Object>, route: ShuShanRoute): void {
    const provider = route.provider.trim();
    if (provider === '书旗听书') {
      body['bookid'] = route.bookId;
      body['item_ids'] = ShuShanApiClient.chapterParam(route.chapterUrl, 'item_ids');
    }
    if (provider === '企鹅看书' || provider === 'QQ阅读' || provider === '起点') {
      body['bookid'] = route.bookId;
      body['chapterid'] = ShuShanApiClient.chapterParam(route.chapterUrl, 'chapterid');
    }
    if (provider === '晋江') {
      body['novelId'] = route.bookId;
      body['chapterId'] = ShuShanApiClient.chapterParam(route.chapterUrl, 'chapterId');
      body['token'] = '';
    }
    if (provider === '半夏') {
      ShuShanApiClient.putIfPresent(body, 'bookid',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'bookid'));
      ShuShanApiClient.putIfPresent(body, 'chapterid',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'chapterid'));
      ShuShanApiClient.putIfPresent(body, 'novelId',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'novelId'));
      ShuShanApiClient.putIfPresent(body, 'chapterId',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'chapterId'));
    }
    if (provider === '七猫') {
      body['qm_url'] = route.chapterUrl;
      ShuShanApiClient.putIfPresent(body, 'book_id',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'book_id'));
      ShuShanApiClient.putIfPresent(body, 'item_id',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'item_id'));
      ShuShanApiClient.putIfPresent(body, 'content_md5',
        ShuShanApiClient.chapterParam(route.chapterUrl, 'content_md5'));
    }
    if (provider === '七猫短剧') body['qm_id'] = route.bookId;
  }

  private static chapterParam(value: string, name: string): string {
    const pattern = new RegExp(`(?:^|[?&])${name}=([^&#]*)`, 'i');
    const match = pattern.exec(value);
    if (match === null || match.length < 2) return '';
    try {
      return decodeURIComponent(match[1]);
    } catch (_error) {
      return match[1];
    }
  }

  private static requiredChapterParam(route: ShuShanRoute, name: string): string {
    const value = ShuShanApiClient.chapterParam(route.chapterUrl, name);
    if (value.length === 0) throw new Error(`书山聚合章节缺少 ${name}`);
    return value;
  }

  private static putIfPresent(body: Record<string, Object>, key: string, value: string): void {
    if (value.length > 0) body[key] = value;
  }

  private static serverMessage(root: JsonObj, fallback: string): string {
    let message = root.getString('message').trim();
    if (message.length === 0) message = root.getString('msg').trim();
    if (message.length === 0) message = root.getString('error').trim();
    const data = root.raw['data'];
    if (message.length === 0 && data !== undefined && data !== null &&
      typeof data === 'object' && !Array.isArray(data)) {
      const dataRoot = new JsonObj(data);
      message = dataRoot.getString('message').trim();
      if (message.length === 0) message = dataRoot.getString('content').trim();
    }
    if (message.length === 0 || message.toLowerCase() === 'success') return fallback;
    return message.length > 180 ? message.substring(0, 180) : message;
  }

  private static getBoolean(root: JsonObj, key: string, fallback: boolean): boolean {
    const value = root.raw[key];
    if (typeof value === 'boolean') return value as boolean;
    if (value === undefined || value === null || typeof value === 'object') return fallback;
    const normalized = String(value).trim().toLowerCase();
    if (normalized === 'true' || normalized === '1') return true;
    if (normalized === 'false' || normalized === '0') return false;
    return fallback;
  }

  private static isStandardBase64(value: string): boolean {
    if (value.length < 16 || value.length % 4 !== 0) return false;
    return new RegExp('^[A-Za-z0-9+/]+={0,2}$').test(value);
  }

  private static looksObfuscated(value: string): boolean {
    if (value.length < 128) return false;
    let base64Characters = 0;
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) || code === 43 || code === 47 || code === 61) {
        base64Characters++;
      }
    }
    return base64Characters / value.length >= 0.97;
  }

  private static isReadableText(value: string): boolean {
    if (value.length === 0) return false;
    let invalid = 0;
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code === 65533 || (code < 32 && code !== 9 && code !== 10 && code !== 13)) invalid++;
    }
    return invalid === 0 || invalid / value.length < 0.005;
  }

  private static boundedKeyword(value: string): string {
    const clean = value.trim();
    return clean.length > 200 ? clean.substring(0, 200) : clean;
  }

  private static safeHeaderValue(value: string): string {
    if (value.length > 4096 || value.includes('\r') || value.includes('\n') || value.includes('\t')) return '';
    return value.trim();
  }

  private static firstNonEmpty(primary: string, secondary: string): string {
    return primary.trim().length > 0 ? primary : secondary;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '请求失败';
    return String(error || '请求失败');
  }
}
