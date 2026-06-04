/**
 * JavaBridge - Legado Java 桥接（书源 JS 规则中的 java.xxx 方法）
 *
 * 支持：
 *  - java.get(key) / java.put(key, value) - 变量存取
 *  - java.connect(url) - HTTP GET 请求
 *  - java.ajax(url, options) - HTTP 请求（支持 POST）
 *  - java.getStrResponse() - 获取最后一次请求的响应
 *  - java.log(msg) - 日志输出
 *  - java.toast(msg) / java.longToast(msg) - Toast 提示
 *  - java.base64Encode/Decode - Base64 编解码
 *  - java.hexDecodeToString(hex) - Hex 解码
 *  - java.androidId() / java.deviceID() - 设备标识
 *  - java.getWebViewUA() - WebView User-Agent
 *  - java.getAppVariant() - 应用变体
 *  - java.startBrowser(url, title) - 打开外部浏览器
 *  - java.showBrowser(url, html, js, options) - 内嵌浏览器弹窗
 *  - java.refreshExplore() - 刷新发现页
 */

import { HttpClient } from '../http/HttpClient';
import { AnalyzeUrl } from './AnalyzeUrl';
import { getCookieManager } from './CookieManager';

interface AjaxOptions {
  method?: string;
  body?: string;
  headers?: Record<string, string>;
}

interface BrowserAwaitResult {
  body: string;
}

export class JavaBridgeImpl {
  private variables: Record<string, string> = {};
  private lastResponse: string = '';

  // 回调（由 UI 层注册）
  private static toastCallback: ((msg: string, duration: number) => void) | null = null;
  private static browserCallback: ((url: string, title: string) => void) | null = null;
  private static browserAwaitCallback: ((url: string, title: string) => Promise<BrowserAwaitResult>) | null = null;
  private static showBrowserCallback: ((url: string, html: string, js: string, options: string) => void) | null = null;
  private static refreshExploreCallback: (() => void) | null = null;

  // 设备标识缓存
  private static deviceId: string = '';

  // ──────────── 回调注册（UI 层调用） ────────────

  static setToastCallback(cb: ((msg: string, duration: number) => void) | null): void {
    JavaBridgeImpl.toastCallback = cb;
  }

  static setBrowserCallback(cb: ((url: string, title: string) => void) | null): void {
    JavaBridgeImpl.browserCallback = cb;
  }

  static setBrowserAwaitCallback(cb: ((url: string, title: string) => Promise<BrowserAwaitResult>) | null): void {
    JavaBridgeImpl.browserAwaitCallback = cb;
  }

  static setShowBrowserCallback(cb: ((url: string, html: string, js: string, options: string) => void) | null): void {
    JavaBridgeImpl.showBrowserCallback = cb;
  }

  static setRefreshExploreCallback(cb: (() => void) | null): void {
    JavaBridgeImpl.refreshExploreCallback = cb;
  }

  static setDeviceId(id: string): void {
    JavaBridgeImpl.deviceId = id;
  }

  // ──────────── 核心 API ────────────

  get(key: string): string {
    return this.variables[key] || '';
  }

  put(key: string, value: string): void {
    this.variables[key] = value;
  }

  async connect(url: string): Promise<string> {
    try {
      const response = await HttpClient.get(url);
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] connect failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  async ajax(url: string, options?: AjaxOptions): Promise<string> {
    try {
      let actualUrl = url;
      let method = options?.method?.toUpperCase() || 'GET';
      let body = options?.body || '';
      let headers: Record<string, string> = options?.headers || {};

      if (url.indexOf(',{') > 0) {
        const split = AnalyzeUrl.splitUrlConfig(url);
        actualUrl = split.url;
        const cfg = split.config;
        if (cfg.method && cfg.method !== 'GET') method = cfg.method;
        if (cfg.body && !body) body = cfg.body;
        if (cfg.headers) {
          const keys = Object.keys(cfg.headers);
          for (const k of keys) {
            if (!headers[k]) headers[k] = cfg.headers[k];
          }
        }
      }

      let response: string;
      if (method === 'POST') {
        if (!headers['Content-Type']) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
        response = await HttpClient.post(actualUrl, body, headers);
      } else {
        response = await HttpClient.get(actualUrl);
      }
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] ajax failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  getStrResponse(): string {
    return this.lastResponse;
  }

  log(message: string): void {
    console.info(`[JavaBridge] ${message}`);
  }

  // ──────────── Toast ────────────

  toast(msg: string): void {
    console.info(`[JavaBridge] toast: ${msg}`);
    if (JavaBridgeImpl.toastCallback) {
      JavaBridgeImpl.toastCallback(msg, 2000);
    }
  }

  longToast(msg: string): void {
    console.info(`[JavaBridge] longToast: ${msg}`);
    if (JavaBridgeImpl.toastCallback) {
      JavaBridgeImpl.toastCallback(msg, 5000);
    }
  }

  // ──────────── 浏览器 ────────────

  startBrowser(url: string, title?: string): void {
    console.info(`[JavaBridge] startBrowser: ${url}`);
    if (JavaBridgeImpl.browserCallback) {
      JavaBridgeImpl.browserCallback(url, title || '');
    }
  }

  startBrowserDp(url: string, title?: string): void {
    this.startBrowser(url, title);
  }

  async startBrowserAwait(url: string, title?: string): Promise<Object> {
    console.info(`[JavaBridge] startBrowserAwait: ${url}`);
    if (JavaBridgeImpl.browserAwaitCallback) {
      const result: BrowserAwaitResult = await JavaBridgeImpl.browserAwaitCallback(url, title || '');
      return result as Object;
    }
    const fallback: BrowserAwaitResult = { body: '' };
    return fallback as Object;
  }

  showBrowser(url: string, html: string, js?: string, options?: string): void {
    console.info(`[JavaBridge] showBrowser: ${url}`);
    if (JavaBridgeImpl.showBrowserCallback) {
      JavaBridgeImpl.showBrowserCallback(url, html, js || '', options || '');
    }
  }

  refreshExplore(): void {
    console.info(`[JavaBridge] refreshExplore`);
    if (JavaBridgeImpl.refreshExploreCallback) {
      JavaBridgeImpl.refreshExploreCallback();
    }
  }

  // ──────────── Cookie ────────────

  getCookie(url: string): string {
    try {
      const cookieManager = getCookieManager();
      return cookieManager.getCookie(url);
    } catch {
      return '';
    }
  }

  // ──────────── 设备标识 ────────────

  androidId(): string {
    return JavaBridgeImpl.deviceId || '';
  }

  deviceID(): string {
    return this.androidId();
  }

  getWebViewUA(): string {
    return 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  }

  getAppVariant(): string {
    return '';
  }

  // ──────────── 编码工具 ────────────

  hexDecodeToString(hex: string): string {
    if (!hex) return '';
    try {
      // 检测是否为合法 hex 字符串（偶数长度，仅含 0-9a-fA-F）
      const isHex = hex.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(hex);
      if (isHex) {
        const bytes: number[] = [];
        for (let i = 0; i < hex.length; i += 2) {
          bytes.push(parseInt(hex.substring(i, i + 2), 16));
        }
        let out = '';
        let i = 0;
        while (i < bytes.length) {
          const b = bytes[i++];
          if (b < 0x80) {
            out += String.fromCharCode(b);
          } else if (b < 0xC0) {
            continue;
          } else if (b < 0xE0) {
            out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i++] & 0x3F));
          } else if (b < 0xF0) {
            out += String.fromCharCode(((b & 0xF) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
          } else {
            const cp = ((b & 0x7) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F);
            out += String.fromCodePoint(cp);
          }
        }
        return out;
      }
      // 非 hex 字符串，尝试 base64 解码（兼容光遇聚合等书源误用 hexDecodeToString 解码 base64）
      return this.base64Decode(hex);
    } catch {
      return '';
    }
  }

  // ──────────── WebView 渲染 ────────────

  async webView(html: string, _url?: string, _js?: string): Promise<string> {
    return html || '';
  }

  // ──────────── 时间格式化 ────────────

  timeFormat(ts: number): string {
    try {
      return new Date(ts).toISOString();
    } catch {
      return String(ts);
    }
  }

  // ──────────── Base64 编解码 ────────────

  base64Encode(s: string): string {
    if (!s) return '';
    try {
      const bytes: number[] = [];
      for (let i = 0; i < s.length; i++) {
        const cp = s.charCodeAt(i);
        if (cp < 0x80) {
          bytes.push(cp);
        } else if (cp < 0x800) {
          bytes.push(0xC0 | (cp >> 6));
          bytes.push(0x80 | (cp & 0x3F));
        } else if (cp < 0xD800 || cp >= 0xE000) {
          bytes.push(0xE0 | (cp >> 12));
          bytes.push(0x80 | ((cp >> 6) & 0x3F));
          bytes.push(0x80 | (cp & 0x3F));
        } else {
          i++;
          const cp2 = 0x10000 + (((cp & 0x3FF) << 10) | (s.charCodeAt(i) & 0x3FF));
          bytes.push(0xF0 | (cp2 >> 18));
          bytes.push(0x80 | ((cp2 >> 12) & 0x3F));
          bytes.push(0x80 | ((cp2 >> 6) & 0x3F));
          bytes.push(0x80 | (cp2 & 0x3F));
        }
      }
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      let out = '';
      for (let i = 0; i < bytes.length; i += 3) {
        const b1 = bytes[i];
        const b2 = i + 1 < bytes.length ? bytes[i + 1] : -1;
        const b3 = i + 2 < bytes.length ? bytes[i + 2] : -1;
        out += alphabet.charAt((b1 >> 2) & 0x3F);
        out += alphabet.charAt(((b1 & 0x3) << 4) | (((b2 < 0 ? 0 : b2) >> 4) & 0x3F));
        out += b2 < 0 ? '=' : alphabet.charAt(((b2 & 0xF) << 2) | (((b3 < 0 ? 0 : b3) >> 6) & 0x3F));
        out += b3 < 0 ? '=' : alphabet.charAt(b3 & 0x3F);
      }
      return out;
    } catch {
      return '';
    }
  }

  base64Decode(s: string): string {
    if (!s) return '';
    try {
      const map: Map<string, number> = new Map();
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      for (let i = 0; i < alphabet.length; i++) map.set(alphabet.charAt(i), i);
      const bytes: number[] = [];
      const clean = s.replace(/[^A-Za-z0-9+/=]/g, '');
      for (let i = 0; i < clean.length; i += 4) {
        const c1 = map.get(clean.charAt(i)) ?? 0;
        const c2 = map.get(clean.charAt(i + 1)) ?? 0;
        const c3 = map.get(clean.charAt(i + 2)) ?? 0;
        const c4 = map.get(clean.charAt(i + 3)) ?? 0;
        bytes.push(((c1 << 2) | (c2 >> 4)) & 0xFF);
        if (clean.charAt(i + 2) !== '=') bytes.push(((c2 << 4) | (c3 >> 2)) & 0xFF);
        if (clean.charAt(i + 3) !== '=') bytes.push(((c3 << 6) | c4) & 0xFF);
      }
      let out = '';
      let i = 0;
      while (i < bytes.length) {
        const b = bytes[i++];
        if (b < 0x80) out += String.fromCharCode(b);
        else if (b < 0xC0) continue;
        else if (b < 0xE0) {
          out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i++] & 0x3F));
        } else if (b < 0xF0) {
          out += String.fromCharCode(((b & 0xF) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
        } else {
          const cp = ((b & 0x7) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F);
          out += String.fromCodePoint(cp);
        }
      }
      return out;
    } catch {
      return '';
    }
  }

  // ──────────── 杂项 ────────────

  md5(_s: string): string { return ''; }

  randomUUID(): string {
    const bytes: number[] = [];
    for (let i = 0; i < 16; i++) bytes.push(Math.floor(Math.random() * 256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    const hex = bytes.map((b) => b.toString(16).padStart(2, '0')).join('');
    return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}`;
  }

  setVariables(vars: Record<string, string>): void {
    this.variables = vars;
  }

  getVariables(): Record<string, string> {
    return this.variables;
  }
}

let globalBridge: JavaBridgeImpl | null = null;

export function getJavaBridge(): JavaBridgeImpl {
  if (!globalBridge) {
    globalBridge = new JavaBridgeImpl();
  }
  return globalBridge;
}
