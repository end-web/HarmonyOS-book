import { TingYouCrypto } from '../../builtin/TingYouCrypto';
import { JsonObj } from '../../builtin/JsonValue';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../http/HttpClient';
import { AsyncSingleFlight } from '../../../utils/AsyncSingleFlight';
import { TingYouDeviceFingerprint } from './TingYouDeviceFingerprint';
import { TingYouChapterAddress } from './TingYouSourceIdentity';

const TINGYOU_SITE: string = 'https://tingyou.fm';
const TINGYOU_API: string = `${TINGYOU_SITE}/api`;
const TINGYOU_CDN_BASES: string[] = [
  'https://json.tingyou8.vip/tyfm/json_v1',
  'https://json.hgeuz.cn/tyfm/json_v1',
  'https://json.fmfm.pro/tyfm/json_v1'
];
const TINGYOU_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'Chrome/120.0.0.0 Mobile Safari/537.36';
const PLAY_TOKEN_MIN_INTERVAL_MS: number = 800;

/** 听友访客鉴权及 play_token 的最小原生客户端。 */
export class TingYouApiClient {
  private static token: string = '';
  private static tokenFlight: AsyncSingleFlight<string> = new AsyncSingleFlight<string>();
  private static playTokenChain: Promise<void> = Promise.resolve();

  static async resolvePlayUrl(address: TingYouChapterAddress): Promise<string> {
    if (address.albumId <= 0 || address.chapterIndex <= 0) {
      throw new Error('听友章节地址无效');
    }
    const run: Promise<string> = TingYouApiClient.playTokenChain.then(
      async (): Promise<string> => TingYouApiClient.requestPlayUrl(address));
    TingYouApiClient.playTokenChain = run.then((): Promise<void> =>
      TingYouApiClient.delay(PLAY_TOKEN_MIN_INTERVAL_MS)
    ).catch((): Promise<void> => TingYouApiClient.delay(PLAY_TOKEN_MIN_INTERVAL_MS));
    return await run;
  }

  /** 首页和分类使用的公开加密 JSON；仅允许固定 CDN 下的相对数据路径。 */
  static async getPublicData(path: string): Promise<JsonObj | undefined> {
    const cleanPath = path.trim().replace(new RegExp('^/+', 'g'), '');
    if (cleanPath.length === 0 || cleanPath.length > 256 || cleanPath.includes('..') ||
      !new RegExp('^[A-Za-z0-9_?=&./-]+$').test(cleanPath)) {
      throw new Error('听友公开数据路径无效');
    }
    for (const base of TINGYOU_CDN_BASES) {
      const options: HttpRequestOptions = {
        method: 'GET',
        headers: TingYouApiClient.baseHeaders(),
        timeout: 15000,
        retry: 0
      };
      try {
        const response = await HttpClient.request(`${base}/${cleanPath}`, options);
        if (response.statusCode === 200 && response.body.length > 0) {
          return TingYouApiClient.decryptResponse(response.body);
        }
      } catch (_error) {
        // 当前镜像失败后继续下一个固定镜像。
      }
    }
    return undefined;
  }

  private static async requestPlayUrl(address: TingYouChapterAddress): Promise<string> {
    const body = `{"album_id":${address.albumId},"chapter_idx":${address.chapterIndex}}`;
    const response = await TingYouApiClient.postAuthorized('play_token', body);
    const playUrl = response.getString('play_url', '').trim();
    if (!playUrl.startsWith('https://') && !playUrl.startsWith('http://')) {
      throw new Error('听友接口未返回可播放音频');
    }
    return playUrl;
  }

  private static async postAuthorized(endpoint: string, body: string): Promise<JsonObj> {
    let token = await TingYouApiClient.ensureToken(false);
    for (let attempt = 0; attempt < 2; attempt++) {
      const encryptedBody = await TingYouCrypto.encryptRequest(body);
      const headers = TingYouApiClient.baseHeaders();
      headers['Authorization'] = `Bearer ${token}`;
      headers['Content-Type'] = 'text/plain';
      const options: HttpRequestOptions = {
        method: 'POST',
        headers: headers,
        body: encryptedBody,
        timeout: 12000,
        retry: 0
      };
      let response: HttpResponse;
      try {
        response = await HttpClient.request(`${TINGYOU_API}/${endpoint}`, options);
      } catch (error) {
        if (attempt === 0) continue;
        throw new Error(`听友接口请求失败：${TingYouApiClient.errorMessage(error as Object)}`);
      }
      if (response.statusCode === 200) {
        return TingYouApiClient.decryptResponse(response.body);
      }
      if (response.statusCode === 401 && attempt === 0) {
        token = await TingYouApiClient.ensureToken(true);
        continue;
      }
      if (response.statusCode >= 500 && response.statusCode < 600 && attempt === 0) continue;
      throw new Error(`听友接口请求失败：HTTP ${response.statusCode}`);
    }
    throw new Error('听友接口重试后仍未返回有效数据');
  }

  private static async ensureToken(force: boolean): Promise<string> {
    if (TingYouApiClient.token.length > 0 && !force) return TingYouApiClient.token;
    return TingYouApiClient.tokenFlight.run(async (): Promise<string> => {
      if (TingYouApiClient.token.length > 0 && !force) return TingYouApiClient.token;
      if (force) TingYouApiClient.token = '';
      TingYouApiClient.token = await TingYouApiClient.acquireToken();
      return TingYouApiClient.token;
    });
  }

  private static async acquireToken(): Promise<string> {
    const headers = TingYouApiClient.baseHeaders();
    headers['Cookie'] = await TingYouDeviceFingerprint.buildCookie();
    const options: HttpRequestOptions = {
      method: 'POST',
      headers: headers,
      timeout: 12000,
      retry: 1
    };
    const response = await HttpClient.request(`${TINGYOU_API}/me`, options);
    if (response.statusCode !== 200) {
      throw new Error(`听友访客鉴权失败：HTTP ${response.statusCode}`);
    }
    const data = TingYouApiClient.decryptResponse(response.body);
    const token = data.getString('auth_token', '')
      .replace(new RegExp('^Bearer\\s+', 'i'), '').trim();
    if (token.length === 0) throw new Error('听友访客鉴权未返回令牌');
    return token;
  }

  private static decryptResponse(body: string): JsonObj {
    try {
      const root = new JsonObj(JSON.parse(body) as Object);
      const payload = root.getString('payload', '');
      if (payload.length === 0) return root;
      return new JsonObj(JSON.parse(TingYouCrypto.decryptResponse(payload)) as Object);
    } catch (error) {
      throw new Error(`听友响应解密失败：${TingYouApiClient.errorMessage(error as Object)}`);
    }
  }

  private static baseHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = TINGYOU_USER_AGENT;
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
    headers['Referer'] = `${TINGYOU_SITE}/`;
    headers['Origin'] = TINGYOU_SITE;
    headers['X-Payload-Version'] = '1';
    return headers;
  }

  private static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '未知错误';
    return String(error || '未知错误');
  }
}
