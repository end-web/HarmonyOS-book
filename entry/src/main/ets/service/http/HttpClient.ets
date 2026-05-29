/**
 * HttpClient - HTTP 请求封装（ArkTS 兼容）
 */

import http from '@ohos.net.http';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { getCookieManager } from '../rule/CookieManager';

const DEFAULT_UA = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

export interface HttpRequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | Object;
  timeout?: number;
  /** 响应字符集，默认 utf-8。GBK/GB2312 站点必须显式传入。 */
  charset?: string;
}

export interface HttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

const POOL: http.HttpRequest[] = [];
const MAX_POOL_SIZE = 5;
const DEFAULT_TIMEOUT = 30000;

function getRequestMethod(method: string): http.RequestMethod {
  const m = method.toUpperCase();
  if (m === 'POST') return http.RequestMethod.POST;
  if (m === 'PUT') return http.RequestMethod.PUT;
  if (m === 'DELETE') return http.RequestMethod.DELETE;
  return http.RequestMethod.GET;
}

function getHttpRequest(): http.HttpRequest {
  const r = POOL.pop();
  if (r) return r;
  return http.createHttp();
}

function returnHttpRequest(request: http.HttpRequest): void {
  if (POOL.length < MAX_POOL_SIZE) {
    POOL.push(request);
  } else {
    request.destroy();
  }
}

export class HttpClient {
  static async request(url: string, options: HttpRequestOptions = {}): Promise<HttpResponse> {
    const httpRequest = getHttpRequest();
    const cookieJar = getCookieManager();

    try {
      // 用大小写不敏感的累积器收集 header（最终发送时再转成 Record）
      const accum: Map<string, string> = new Map();
      if (options.headers) {
        const keys = Object.keys(options.headers);
        for (const k of keys) accum.set(k.toLowerCase(), options.headers[k]);
      }
      // 默认 UA / Accept
      if (!accum.has('user-agent')) accum.set('user-agent', DEFAULT_UA);
      if (!accum.has('accept')) {
        accum.set('accept', 'text/html,application/xhtml+xml,application/json,application/xml;q=0.9,*/*;q=0.8');
      }
      // 注入 cookie jar 中匹配的 cookie（合并已有 Cookie header）
      const jarCookie = cookieJar.getCookieHeader(url);
      if (jarCookie) {
        const existing = accum.get('cookie') || '';
        accum.set('cookie', existing ? existing + '; ' + jarCookie : jarCookie);
      }

      const charset = (options.charset || '').toLowerCase();
      const isNonUtf8 = charset !== '' && charset !== 'utf-8' && charset !== 'utf8';

      let extraData: string | undefined = undefined;
      if (options.body && options.method !== 'GET') {
        if (typeof options.body === 'string') {
          extraData = options.body;
          // body 是 query 形式 (a=1&b=2) 自动补 Content-Type
          if (!accum.has('content-type') && /^[\w\-]+=[^=]/.test(options.body as string)) {
            accum.set('content-type', 'application/x-www-form-urlencoded'
              + (isNonUtf8 ? `; charset=${charset}` : ''));
          }
        } else {
          extraData = JSON.stringify(options.body);
          if (!accum.has('content-type')) accum.set('content-type', 'application/json');
        }
      }

      // Map → Record（首字母大写更友好），保留多个值用 \n 拼（不应用，但谨慎）
      const finalHeaders: Record<string, string> = {};
      accum.forEach((v: string, k: string) => {
        finalHeaders[HttpClient.titleCaseHeader(k)] = v;
      });

      const requestOptions: http.HttpRequestOptions = {
        method: getRequestMethod(options.method || 'GET'),
        header: finalHeaders,
        readTimeout: options.timeout || DEFAULT_TIMEOUT,
        connectTimeout: options.timeout || DEFAULT_TIMEOUT,
      };
      // 非 UTF-8 站点：拿原始字节，自己解码
      if (isNonUtf8) {
        requestOptions.expectDataType = http.HttpDataType.ARRAY_BUFFER;
      }
      if (extraData !== undefined) {
        requestOptions.extraData = extraData;
      }

      const response = await httpRequest.request(url, requestOptions);

      let body: string;
      if (isNonUtf8 && response.result instanceof ArrayBuffer) {
        body = CharsetCodec.decodeBuffer(response.result as ArrayBuffer, charset);
      } else {
        body = response.result as string;
      }

      const respHeaders = response.header as Record<string, string>;
      cookieJar.acceptResponseCookies(url, respHeaders);

      const result: HttpResponse = {
        statusCode: response.responseCode,
        headers: respHeaders,
        body,
      };
      return result;
    } finally {
      returnHttpRequest(httpRequest);
    }
  }

  private static titleCaseHeader(name: string): string {
    return name.split('-').map((p) => {
      if (!p) return p;
      return p.charAt(0).toUpperCase() + p.substring(1);
    }).join('-');
  }

  static async get(url: string, headers?: Record<string, string>, charset?: string): Promise<string> {
    const response = await HttpClient.request(url, { method: 'GET', headers, charset });
    return response.body;
  }

  static async post(url: string, body?: string | Object, headers?: Record<string, string>, charset?: string): Promise<string> {
    const response = await HttpClient.request(url, { method: 'POST', body, headers, charset });
    return response.body;
  }

  static clearPool(): void {
    for (const r of POOL) {
      r.destroy();
    }
    POOL.length = 0;
  }
}
