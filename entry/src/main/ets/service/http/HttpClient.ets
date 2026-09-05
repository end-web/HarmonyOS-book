/**
 * HttpClient - HTTP 请求封装（基于 Remote Communication Kit / rcp）
 *
 * 迁移自旧的 @ohos.net.http：
 * - 用共享的 rcp.Session 替代手写的 HttpRequest 连接池（rcp Session 内部即连接复用）
 * - 始终取原始字节（response.body: ArrayBuffer），按显式 charset 或自动探测解码，兼容 GBK/GB2312 书源
 * - 保持公开 API 完全不变：request / get / post / clearPool / HttpRequestOptions / HttpResponse
 */

import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CharsetCodec } from '../../utils/CharsetCodec';

const DEFAULT_UA = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const DEFAULT_TIMEOUT = 30000;

export interface HttpRequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | Object;
  timeout?: number;
  /** 响应字符集，默认 utf-8。GBK/GB2312 站点必须显式传入。 */
  charset?: string;
  /** 最大重试次数（仅对网络错误/5xx/429 重试），默认 0（不重试） */
  retry?: number;
  autoRedirect?: boolean;
}

export interface HttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  url?: string;
}

// 共享会话：rcp.Session 内部维护连接池，并发请求复用底层连接。
// 超时按请求级 configuration 设置，因此一个会话即可服务所有请求。
let sharedSession: rcp.Session | null = null;

function getSession(): rcp.Session {
  if (!sharedSession) {
    sharedSession = rcp.createSession();
  }
  return sharedSession;
}

export class HttpClient {
  /**
   * 预建链：与目标域名的连接与业务逻辑并行建立，此后再用同一 session 访问同域
   * 可跳过 DNS/TCP/TLS 握手。仅建立连接，不发送请求体、不接收响应。
   *
   * 复用条件（官方约束）：同一 session + 同一域名 + 网络状态未变化。
   * 这里使用共享 sharedSession，保证与 request() 的连接池一致，天然可复用。
   */
  static preconnect(origin: string): void {
    try {
      const session = getSession();
      const request = new rcp.Request(origin, 'GET');
      request.connectOnly = true;
      session.fetch(request).then((): void => {
        // 仅表示连接已缓存，无业务响应
      }).catch((err: Error) => {
        const e = err as Error;
        hilog.warn(0x11, 'HttpPreconnect', 'preconnect %{public}s failed: %{public}s',
          origin, e?.message ?? JSON.stringify(err));
      });
    } catch (err) {
      const e = err as Error;
      hilog.warn(0x11, 'HttpPreconnect', 'preconnect %{public}s threw: %{public}s',
        origin, e?.message ?? JSON.stringify(err));
    }
  }

  static async request(url: string, options: HttpRequestOptions = {}): Promise<HttpResponse> {
    const session = getSession();

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
    const charset = (options.charset || '').toLowerCase();
    const isNonUtf8 = charset !== '' && charset !== 'utf-8' && charset !== 'utf8';

    const method = (options.method || 'GET').toUpperCase();
    let content: string | undefined = undefined;
    if (options.body && method !== 'GET') {
      if (typeof options.body === 'string') {
        content = options.body;
        // body 是 query 形式 (a=1&b=2) 自动补 Content-Type
        if (!accum.has('content-type') && /^[\w\-]+=[^=]/.test(options.body as string)) {
          accum.set('content-type', 'application/x-www-form-urlencoded'
            + (isNonUtf8 ? `; charset=${charset}` : ''));
        }
      } else {
        content = JSON.stringify(options.body);
        if (!accum.has('content-type')) accum.set('content-type', 'application/json');
      }
    }

    // Map → Record（首字母大写更友好）
    const finalHeaders: Record<string, string> = {};
    accum.forEach((v: string, k: string) => {
      finalHeaders[HttpClient.titleCaseHeader(k)] = v;
    });

    const timeout = options.timeout || DEFAULT_TIMEOUT;
    const req = new rcp.Request(url, method, finalHeaders, content);
    req.configuration = {
      transfer: {
        autoRedirect: options.autoRedirect ?? true,
        maxAutoRedirects: 5,
        timeout: {
          connectMs: timeout,
          transferMs: timeout,
        },
      },
    };

    const maxRetry = options.retry ?? 0;
    let response: rcp.Response | null = null;
    let lastErr: Error | null = null;
    for (let attempt = 0; attempt <= maxRetry; attempt++) {
      try {
        response = await session.fetch(req);
        // 5xx 和 429 可重试
        if (response.statusCode >= 500 || response.statusCode === 429) {
          lastErr = new Error(`HTTP ${response.statusCode}`);
          if (attempt < maxRetry) {
            await HttpClient.delay(attempt);
            continue;
          }
        }
        break; // 2xx/3xx/4xx(非429) 直接到结果
      } catch (err) {
        lastErr = err as Error;
        if (attempt < maxRetry) {
          await HttpClient.delay(attempt);
          continue;
        }
        throw new Error(lastErr?.message ?? 'HTTP request failed');
      }
    }
    if (!response) {
      throw new Error(lastErr?.message ?? 'HTTP request failed with no response');
    }

    // 始终按原始字节解码：显式 charset 优先，否则按 Content-Type / HTML meta 自动探测，默认 UTF-8
    const respHeaders = HttpClient.toHeaderRecord(response.headers);
    let body: string;
    const buf = response.body;
    if (buf && buf.byteLength > 0) {
      let cs = charset;
      if (!cs || cs === 'utf-8' || cs === 'utf8') {
        cs = HttpClient.detectCharset(respHeaders, buf);
      }
      body = CharsetCodec.decodeBuffer(buf, cs);
    } else {
      body = '';
    }

    const result: HttpResponse = {
      statusCode: response.statusCode,
      headers: respHeaders,
      body,
      url: response.effectiveUrl?.toString() ?? url,
    };
    return result;
  }

  /** 把 rcp.ResponseHeaders 规整成普通 Record（保留原始 key，值统一为 string） */
  private static toHeaderRecord(headers: rcp.ResponseHeaders | undefined): Record<string, string> {
    const out: Record<string, string> = {};
    if (!headers) return out;
    const keys = Object.keys(headers);
    for (const k of keys) {
      const v = (headers as Record<string, string>)[k];
      if (v !== undefined && v !== null) out[k] = String(v);
    }
    return out;
  }

  private static titleCaseHeader(name: string): string {
    return name.split('-').map((p) => {
      if (!p) return p;
      return p.charAt(0).toUpperCase() + p.substring(1);
    }).join('-');
  }

  /** 自动探测响应编码：Content-Type 头 → HTML meta(前2KB) → 默认 utf-8 */
  private static detectCharset(headers: Record<string, string>, buf: ArrayBuffer): string {
    try {
      const keys = headers ? Object.keys(headers) : [];
      for (const k of keys) {
        if (k.toLowerCase() === 'content-type') {
          const m = (headers[k] || '').toLowerCase().match(/charset\s*=\s*([\w-]+)/);
          if (m) return m[1];
        }
      }
    } catch { /* ignore */ }
    try {
      const n = Math.min(buf.byteLength, 2048);
      const bytes = new Uint8Array(buf, 0, n);
      let head = '';
      for (let i = 0; i < n; i++) head += String.fromCharCode(bytes[i]);
      const m = head.toLowerCase().match(/charset\s*=\s*["']?\s*([\w-]+)/);
      if (m) return m[1];
    } catch { /* ignore */ }
    return 'utf-8';
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
    if (sharedSession) {
      sharedSession.close();
      sharedSession = null;
    }
  }

  /** 指数退避延迟：attempt=0→500ms, 1→1000ms, 2→2000ms, 加 ±20% 随机抖动 */
  private static delay(attempt: number): Promise<void> {
    const base = 500 * Math.pow(2, attempt);
    const jitter = base * 0.2 * (Math.random() * 2 - 1);
    const ms = Math.max(100, base + jitter);
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }
}
