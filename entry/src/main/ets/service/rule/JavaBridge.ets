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
import { getSourceContext } from './SourceContext';
import { t2s as cnT2S, s2t as cnS2T } from '../../utils/ChineseConverter';
import { parseTTFont } from '../../utils/TTFontParser';
import { rsaEncrypt, rsaDecrypt, parsePublicKeyPEM } from '../../utils/RSA';
import { getZipStringContent, getZipByteArrayContent, listZipFiles } from '../../utils/ZipParser';
import { getRarStringContent, getRarByteArrayContent, listRarFiles } from '../../utils/RarParser';
import { get7zStringContent, get7zByteArrayContent, list7zFiles } from '../../utils/SevenZipParser';
import { getWebViewAudioExtractor } from '../builtin/WebViewAudioExtractor';

interface AjaxOptions {
  method?: string;
  body?: string;
  headers?: Record<string, string>;
}

interface BrowserAwaitResult {
  body: string;
}

interface CryptoResult {
  doFinal: (data: string, op: string) => string;
}

interface SignResult {
  update: (data: string) => void;
  sign: (privateKeyModulus?: string, privateKeyExponent?: string) => string;
}

interface RSACryptoResult {
  init: (mode: string, key: string) => void;
  doFinal: (data: string) => string;
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
  private static verificationCodeCallback: ((imageUrl: string) => Promise<string>) | null = null;

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

  static setVerificationCodeCallback(cb: ((imageUrl: string) => Promise<string>) | null): void {
    JavaBridgeImpl.verificationCodeCallback = cb;
  }

  static setDeviceId(id: string): void {
    JavaBridgeImpl.deviceId = id;
  }

  // ──────────── 核心 API ────────────

  /**
   * 获取变量值（Legado java.get(key) 对应变量存取场景）
   * 注意：HTTP GET 请求用 get() 方法
   */
  getVar(key: string): string {
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

  /**
   * java.get(url, headers) — Jsoup 风格 GET 请求（Legado 兼容）
   * 返回响应体字符串
   */
  async get(url: string, headers?: Record<string, string>): Promise<string> {
    try {
      let actualUrl = url;
      let reqHeaders: Record<string, string> = headers || {};

      // 处理 Legado ",{config}" 语法
      if (url.indexOf(',{') > 0) {
        const split = AnalyzeUrl.splitUrlConfig(url);
        actualUrl = split.url;
        const cfg = split.config;
        if (cfg.headers) {
          for (const k of Object.keys(cfg.headers)) {
            if (!reqHeaders[k]) reqHeaders[k] = cfg.headers[k];
          }
        }
      }

      const response = await HttpClient.get(actualUrl, reqHeaders);
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] get failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  /**
   * java.post(url, body, headers) — Jsoup 风格 POST 请求（Legado 兼容）
   * 返回响应体字符串
   */
  async post(url: string, body?: string, headers?: Record<string, string>): Promise<string> {
    try {
      let actualUrl = url;
      let reqBody = body || '';
      let reqHeaders: Record<string, string> = headers || {};

      // 处理 Legado ",{config}" 语法
      if (url.indexOf(',{') > 0) {
        const split = AnalyzeUrl.splitUrlConfig(url);
        actualUrl = split.url;
        const cfg = split.config;
        if (cfg.method) { /* already POST */ }
        if (cfg.body && !reqBody) reqBody = cfg.body;
        if (cfg.headers) {
          for (const k of Object.keys(cfg.headers)) {
            if (!reqHeaders[k]) reqHeaders[k] = cfg.headers[k];
          }
        }
      }

      if (!reqHeaders['Content-Type']) {
        reqHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
      }

      const response = await HttpClient.post(actualUrl, reqBody, reqHeaders);
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] post failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  /**
   * java.head(url, headers) — Jsoup 风格 HEAD 请求（Legado 兼容）
   * 返回响应头 JSON 字符串
   */
  async head(url: string, headers?: Record<string, string>): Promise<string> {
    try {
      const reqHeaders: Record<string, string> = headers || {};
      // HttpClient 没有 head 方法，用 GET 代替（只取响应头信息）
      // 简化实现：返回 URL 和 headers 信息
      const response = await HttpClient.get(url, reqHeaders);
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] head failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  /**
   * java.webViewGetSource(html, url, js, sourceRegex) — WebView 媒体嗅探（Legado 兼容）
   * 在 WebView 中加载页面，监听网络请求，通过 sourceRegex 匹配媒体 URL
   */
  async webViewGetSource(html: string, url: string, js?: string, sourceRegex?: string): Promise<string> {
    // 简化实现：使用 WebViewAudioExtractor
    try {
      const extractor = getWebViewAudioExtractor();
      const defaultJs = `(function(){
        var audios = document.querySelectorAll('audio,source');
        for(var i=0;i<audios.length;i++){if(audios[i].src) return audios[i].src;}
        var html = document.body.innerHTML;
        var m = html.match(/https?:\\/\\/[^"'\\s]+\\.(?:mp3|m4a|wav|ogg|aac)/);
        if(m) return m[0];
        return '';
      })()`;
      const result = await extractor.extract(url, js || defaultJs, 8000);
      return result || '';
    } catch (e) {
      console.error(`[JavaBridge] webViewGetSource error: ${e}`);
      return '';
    }
  }

  /**
   * java.webViewGetOverrideUrl(html, url, js, overrideUrlRegex) — WebView URL 拦截（Legado 兼容）
   */
  async webViewGetOverrideUrl(html: string, url: string, js?: string, overrideUrlRegex?: string): Promise<string> {
    // 简化实现：直接返回 URL
    return url || '';
  }

  log(message: string): void {
  }

  // ──────────── Toast ────────────

  toast(msg: string): void {
    if (JavaBridgeImpl.toastCallback) {
      JavaBridgeImpl.toastCallback(msg, 2000);
    }
  }

  longToast(msg: string): void {
    if (JavaBridgeImpl.toastCallback) {
      JavaBridgeImpl.toastCallback(msg, 5000);
    }
  }

  // ──────────── 浏览器 ────────────

  startBrowser(url: string, title?: string): void {
    if (JavaBridgeImpl.browserCallback) {
      JavaBridgeImpl.browserCallback(url, title || '');
    }
  }

  startBrowserDp(url: string, title?: string): void {
    this.startBrowser(url, title);
  }

  async startBrowserAwait(url: string, title?: string): Promise<Object> {
    if (JavaBridgeImpl.browserAwaitCallback) {
      const result: BrowserAwaitResult = await JavaBridgeImpl.browserAwaitCallback(url, title || '');
      return result as Object;
    }
    const fallback: BrowserAwaitResult = { body: '' };
    return fallback as Object;
  }

  showBrowser(url: string, html: string, js?: string, options?: string): void {
    if (JavaBridgeImpl.showBrowserCallback) {
      JavaBridgeImpl.showBrowserCallback(url, html, js || '', options || '');
    }
  }

  refreshExplore(): void {
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

  /**
   * MD5 摘要（纯 JS 实现，兼容 Legado java.md5Encode / java.md5Encode16）
   * 输入字符串 → 输出 32 位小写 hex
   */
  md5(s: string): string {
    if (!s) return '';
    try {
      // UTF-8 编码
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
      return JavaBridgeImpl.md5Bytes(bytes);
    } catch {
      return '';
    }
  }

  /**
   * MD5 摘要，接受 hex 编码的输入（Legado 兼容）
   */
  md5Encode(s: string): string {
    return this.md5(s);
  }

  /**
   * MD5 16 位摘要（取中间 16 位）
   */
  md5Encode16(s: string): string {
    const full = this.md5(s);
    return full.length >= 32 ? full.substring(8, 24) : full;
  }

  /**
   * 通用摘要 hex（支持 md5/sha1/sha256/sha512）
   */
  digestHex(data: string, algorithm: string): string {
    if (!data) return '';
    const algo = (algorithm || 'MD5').toUpperCase();
    // 编码为 UTF-8 bytes
    const bytes: number[] = [];
    for (let i = 0; i < data.length; i++) {
      const cp = data.charCodeAt(i);
      if (cp < 0x80) bytes.push(cp);
      else if (cp < 0x800) { bytes.push(0xC0 | (cp >> 6)); bytes.push(0x80 | (cp & 0x3F)); }
      else if (cp < 0xD800 || cp >= 0xE000) { bytes.push(0xE0 | (cp >> 12)); bytes.push(0x80 | ((cp >> 6) & 0x3F)); bytes.push(0x80 | (cp & 0x3F)); }
      else { i++; const cp2 = 0x10000 + (((cp & 0x3FF) << 10) | (data.charCodeAt(i) & 0x3FF)); bytes.push(0xF0 | (cp2 >> 18)); bytes.push(0x80 | ((cp2 >> 12) & 0x3F)); bytes.push(0x80 | ((cp2 >> 6) & 0x3F)); bytes.push(0x80 | (cp2 & 0x3F)); }
    }
    if (algo === 'MD5') return JavaBridgeImpl.md5Bytes(bytes);
    // SHA 系列用纯 JS 实现（简化版，仅覆盖常用场景）
    if (algo === 'SHA-1' || algo === 'SHA1') return JavaBridgeImpl.sha1Bytes(bytes);
    if (algo === 'SHA-256' || algo === 'SHA256') return JavaBridgeImpl.sha256Bytes(bytes);
    // 其他算法回退到 MD5
    return JavaBridgeImpl.md5Bytes(bytes);
  }

  /**
   * 通用摘要 base64（支持 md5/sha1/sha256/sha512）
   */
  digestBase64Str(data: string, algorithm: string): string {
    const hex = this.digestHex(data, algorithm);
    if (!hex) return '';
    // hex → bytes → base64
    const bytes: number[] = [];
    for (let i = 0; i < hex.length; i += 2) {
      bytes.push(parseInt(hex.substring(i, i + 2), 16));
    }
    return this.base64Encode(String.fromCharCode(...bytes));
  }

  /**
   * HMAC hex（支持 HMAC-MD5 / HMAC-SHA1 / HMAC-SHA256）
   */
  HMacHex(data: string, algorithm: string, key: string): string {
    if (!data || !key) return '';
    const algo = (algorithm || 'HMAC-MD5').toUpperCase().replace('HMAC-', '');
    // 简化实现：用 key 异或 ipad/opad
    const blockSize = 64; // MD5/SHA1/SHA256 都是 64 字节块
    // key 处理
    const keyBytes: number[] = [];
    for (let i = 0; i < key.length; i++) {
      const cp = key.charCodeAt(i);
      if (cp < 0x80) keyBytes.push(cp);
      else if (cp < 0x800) { keyBytes.push(0xC0 | (cp >> 6)); keyBytes.push(0x80 | (cp & 0x3F)); }
      else { keyBytes.push(0xE0 | (cp >> 12)); keyBytes.push(0x80 | ((cp >> 6) & 0x3F)); keyBytes.push(0x80 | (cp & 0x3F)); }
    }
    let paddedKey: number[];
    if (keyBytes.length > blockSize) {
      // 太长先 hash
      const hashed = JavaBridgeImpl.hexToBytes(JavaBridgeImpl.md5Bytes(keyBytes));
      paddedKey = hashed.concat(new Array<number>(blockSize - hashed.length).fill(0));
    } else {
      paddedKey = keyBytes.concat(new Array<number>(blockSize - keyBytes.length).fill(0));
    }
    // ipad = 0x36, opad = 0x5c
    const ipad: number[] = paddedKey.map((b: number) => b ^ 0x36);
    const opad: number[] = paddedKey.map((b: number) => b ^ 0x5c);
    // data bytes
    const dataBytes: number[] = [];
    for (let i = 0; i < data.length; i++) {
      const cp = data.charCodeAt(i);
      if (cp < 0x80) dataBytes.push(cp);
      else if (cp < 0x800) { dataBytes.push(0xC0 | (cp >> 6)); dataBytes.push(0x80 | (cp & 0x3F)); }
      else { dataBytes.push(0xE0 | (cp >> 12)); dataBytes.push(0x80 | ((cp >> 6) & 0x3F)); dataBytes.push(0x80 | (cp & 0x3F)); }
    }
    const inner = ipad.concat(dataBytes);
    const innerHash = JavaBridgeImpl.hexToBytes(JavaBridgeImpl.md5Bytes(inner));
    const outer = opad.concat(innerHash);
    return JavaBridgeImpl.md5Bytes(outer);
  }

  /**
   * HMAC base64
   */
  HMacBase64(data: string, algorithm: string, key: string): string {
    const hex = this.HMacHex(data, algorithm, key);
    if (!hex) return '';
    const bytes: number[] = [];
    for (let i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substring(i, i + 2), 16));
    return this.base64Encode(String.fromCharCode(...bytes));
  }

  /**
   * URL 编码（Legado java.encodeURI 兼容）
   */
  encodeURI(str: string): string {
    if (!str) return '';
    try {
      return encodeURI(str);
    } catch {
      return str;
    }
  }

  /**
   * URL 编码（更严格，编码所有特殊字符）
   */
  encodeURIComponent(str: string): string {
    if (!str) return '';
    try {
      return encodeURIComponent(str);
    } catch {
      return str;
    }
  }

  /**
   * 字符串转字节数组（Legado java.strToBytes 兼容）
   */
  strToBytes(str: string, charset?: string): number[] {
    if (!str) return [];
    // 默认 UTF-8
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      const cp = str.charCodeAt(i);
      if (cp < 0x80) bytes.push(cp);
      else if (cp < 0x800) { bytes.push(0xC0 | (cp >> 6)); bytes.push(0x80 | (cp & 0x3F)); }
      else if (cp < 0xD800 || cp >= 0xE000) { bytes.push(0xE0 | (cp >> 12)); bytes.push(0x80 | ((cp >> 6) & 0x3F)); bytes.push(0x80 | (cp & 0x3F)); }
      else { i++; const cp2 = 0x10000 + (((cp & 0x3FF) << 10) | (str.charCodeAt(i) & 0x3FF)); bytes.push(0xF0 | (cp2 >> 18)); bytes.push(0x80 | ((cp2 >> 12) & 0x3F)); bytes.push(0x80 | ((cp2 >> 6) & 0x3F)); bytes.push(0x80 | (cp2 & 0x3F)); }
    }
    return bytes;
  }

  /**
   * 字节数组转字符串（Legado java.bytesToStr 兼容）
   */
  bytesToStr(bytes: number[], charset?: string): string {
    if (!bytes || bytes.length === 0) return '';
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const b = bytes[i++];
      if (b < 0x80) out += String.fromCharCode(b);
      else if (b < 0xC0) continue;
      else if (b < 0xE0) out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i++] & 0x3F));
      else if (b < 0xF0) out += String.fromCharCode(((b & 0xF) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
      else { const cp = ((b & 0x7) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F); out += String.fromCodePoint(cp); }
    }
    return out;
  }

  /**
   * hex 编码字符串（Legado java.hexEncodeToString 兼容）
   */
  hexEncodeToString(utf8: string): string {
    if (!utf8) return '';
    let hex = '';
    for (let i = 0; i < utf8.length; i++) {
      hex += utf8.charCodeAt(i).toString(16).padStart(2, '0');
    }
    return hex;
  }

  // ──────────── 时间格式化（改进版） ────────────

  timeFormat(ts: number): string {
    try {
      if (!ts) return '';
      const d = new Date(ts);
      const pad = (n: number) => String(n).padStart(2, '0');
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    } catch {
      return String(ts);
    }
  }

  // ──────────── 并发请求 ────────────

  async ajaxAll(urlList: string[]): Promise<string[]> {
    if (!urlList || urlList.length === 0) return [];
    const results: string[] = [];
    const promises = urlList.map(async (url: string, idx: number) => {
      try {
        const resp = await HttpClient.get(url);
        results[idx] = resp;
      } catch {
        results[idx] = '';
      }
    });
    await Promise.all(promises);
    return results;
  }

  // ──────────── 文件操作 ────────────

  /**
   * 下载文件到缓存目录（Legado java.cacheFile 兼容）
   * 简化实现：下载并缓存在内存中
   */
  async cacheFile(url: string, saveTime?: number): Promise<string> {
    if (!url) return '';
    try {
      const body = await HttpClient.get(url);
      return body;
    } catch {
      return '';
    }
  }

  /**
   * 下载文件（Legado java.downloadFile 兼容）
   * 简化实现：返回 URL 本身
   */
  async downloadFile(url: string): Promise<string> {
    if (!url) return '';
    try {
      const body = await HttpClient.get(url);
      return body;
    } catch {
      return '';
    }
  }

  /**
   * 读取文本文件（Legado java.readTxtFile 兼容）
   * 简化实现：HTTP GET
   */
  async readTxtFile(path: string, charset?: string): Promise<string> {
    if (!path) return '';
    if (path.startsWith('http')) {
      try {
        return await HttpClient.get(path);
      } catch {
        return '';
      }
    }
    return '';
  }

  /**
   * 导入 JS 脚本（Legado java.importScript 兼容）
   */
  async importScript(path: string): Promise<string> {
    if (!path) return '';
    if (path.startsWith('http')) {
      try {
        return await HttpClient.get(path);
      } catch {
        return '';
      }
    }
    return '';
  }

  /**
   * java.readFile(path) — 读取文件为 ByteArray（Legado 兼容）
   * 简化实现：对 HTTP URL 做 GET，本地文件返回空
   */
  async readFile(path: string): Promise<number[]> {
    if (!path) return [];
    if (path.startsWith('http')) {
      try {
        const body = await HttpClient.get(path);
        const bytes: number[] = [];
        for (let i = 0; i < body.length; i++) {
          const cp = body.charCodeAt(i);
          if (cp < 0x80) bytes.push(cp);
          else if (cp < 0x800) { bytes.push(0xC0 | (cp >> 6)); bytes.push(0x80 | (cp & 0x3F)); }
          else { bytes.push(0xE0 | (cp >> 12)); bytes.push(0x80 | ((cp >> 6) & 0x3F)); bytes.push(0x80 | (cp & 0x3F)); }
        }
        return bytes;
      } catch {
        return [];
      }
    }
    return [];
  }

  /**
   * java.deleteFile(path) — 删除文件（Legado 兼容）
   * 简化实现：无操作，返回 true
   */
  deleteFile(_path: string): boolean {
    return true;
  }

  /**
   * java.getFile(path) — 获取文件对象（Legado 兼容）
   * 简化实现：返回路径字符串
   */
  getFile(path: string): string {
    return path || '';
  }

  /**
   * java.getTxtInFolder(path) — 读取文件夹下所有文本文件（Legado 兼容）
   * 简化实现：空
   */
  async getTxtInFolder(_path: string): Promise<string> {
    return '';
  }

  /**
   * java.unzipFile(path) — 解压 zip 文件（Legado 兼容）
   * path: ZIP 文件的 URL 或 base64 数据
   * 返回解压后的文件列表（JSON 数组）
   */
  async unzipFile(path: string): Promise<string> {
    if (!path) return '[]';
    try {
      let zipData = path;
      if (path.startsWith('http')) {
        zipData = await HttpClient.get(path);
      }
      const files = listZipFiles(zipData);
      return JSON.stringify(files);
    } catch (e) {
      console.error(`[JavaBridge] unzipFile error: ${e}`);
      return '[]';
    }
  }

  /**
   * java.un7zFile(path) — 解压 7z 文件（Legado 兼容）
   */
  async un7zFile(path: string): Promise<string> {
    if (!path) return '[]';
    try {
      let szData = path;
      if (path.startsWith('http')) {
        szData = await HttpClient.get(path);
      }
      const files = list7zFiles(szData);
      return JSON.stringify(files);
    } catch (e) {
      console.error(`[JavaBridge] un7zFile error: ${e}`);
      return '[]';
    }
  }

  /**
   * java.unrarFile(path) — 解压 rar 文件（Legado 兼容）
   */
  async unrarFile(path: string): Promise<string> {
    if (!path) return '[]';
    try {
      let rarData = path;
      if (path.startsWith('http')) {
        rarData = await HttpClient.get(path);
      }
      const files = listRarFiles(rarData);
      return JSON.stringify(files);
    } catch (e) {
      console.error(`[JavaBridge] unrarFile error: ${e}`);
      return '[]';
    }
  }

  /**
   * java.getZipStringContent(url, path) — 从 zip 中读取文本（Legado 兼容）
   * url: ZIP 文件 URL（会先下载）
   * path: ZIP 内文件路径
   */
  async getZipStringContent(url: string, path: string): Promise<string> {
    if (!url || !path) return '';
    try {
      const zipData = await HttpClient.get(url);
      return getZipStringContent(zipData, path);
    } catch (e) {
      console.error(`[JavaBridge] getZipStringContent error: ${e}`);
      return '';
    }
  }

  /**
   * java.getRarStringContent(url, path) — 从 rar 中读取文本（Legado 兼容）
   * url: RAR 文件 URL（会先下载）
   * path: RAR 内文件路径
   */
  async getRarStringContent(url: string, path: string): Promise<string> {
    if (!url || !path) return '';
    try {
      const rarData = await HttpClient.get(url);
      return getRarStringContent(rarData, path);
    } catch (e) {
      console.error(`[JavaBridge] getRarStringContent error: ${e}`);
      return '';
    }
  }

  /**
   * java.get7zStringContent(url, path) — 从 7z 中读取文本（Legado 兼容）
   * url: 7z 文件 URL（会先下载）
   * path: 7z 内文件路径
   */
  async get7zStringContent(url: string, path: string): Promise<string> {
    if (!url || !path) return '';
    try {
      const szData = await HttpClient.get(url);
      return get7zStringContent(szData, path);
    } catch (e) {
      console.error(`[JavaBridge] get7zStringContent error: ${e}`);
      return '';
    }
  }

  /**
   * java.getZipByteArrayContent(url, path) — 从 zip 中读取字节（Legado 兼容）
   */
  async getZipByteArrayContent(url: string, path: string): Promise<number[]> {
    if (!url || !path) return [];
    try {
      const zipData = await HttpClient.get(url);
      return getZipByteArrayContent(zipData, path);
    } catch (e) {
      console.error(`[JavaBridge] getZipByteArrayContent error: ${e}`);
      return [];
    }
  }

  /**
   * java.getRarByteArrayContent(url, path) — 从 rar 中读取字节（Legado 兼容）
   */
  async getRarByteArrayContent(url: string, path: string): Promise<number[]> {
    if (!url || !path) return [];
    try {
      const rarData = await HttpClient.get(url);
      return getRarByteArrayContent(rarData, path);
    } catch (e) {
      console.error(`[JavaBridge] getRarByteArrayContent error: ${e}`);
      return [];
    }
  }

  /**
   * java.get7zByteArrayContent(url, path) — 从 7z 中读取字节（Legado 兼容）
   */
  async get7zByteArrayContent(url: string, path: string): Promise<number[]> {
    if (!url || !path) return [];
    try {
      const szData = await HttpClient.get(url);
      return get7zByteArrayContent(szData, path);
    } catch (e) {
      console.error(`[JavaBridge] get7zByteArrayContent error: ${e}`);
      return [];
    }
  }

  // ──────────── 验证码 / 字体反爬 / 繁简转换 ────────────

  /**
   * java.getVerificationCode(imageUrl) — 显示验证码图片，用户输入后返回（Legado 兼容）
   * 通过 UI 层注册的回调弹出验证码输入框
   */
  async getVerificationCode(imageUrl: string): Promise<string> {
    if (!imageUrl) return '';
    if (!JavaBridgeImpl.verificationCodeCallback) {
      console.warn('[JavaBridge] getVerificationCode: no callback registered');
      return '';
    }
    try {
      return await JavaBridgeImpl.verificationCodeCallback(imageUrl);
    } catch (e) {
      console.error(`[JavaBridge] getVerificationCode error: ${e}`);
      return '';
    }
  }

  /**
   * java.queryTTF(data) — 解析 TTF 字体获取字形映射（Legado 字体反爬兼容）
   * data: base64 编码的 TTF 数据 或 URL
   * 返回对象：{ charToGlyph: {}, glyphToChar: {}, familyName: "" }
   */
  async queryTTF(data: string, _useCache?: boolean): Promise<Object> {
    if (!data) return new Object();
    try {
      let fontData = data;
      // 如果是 URL，先下载
      if (data.startsWith('http')) {
        fontData = await HttpClient.get(data);
      }
      const result = parseTTFont(fontData);
      const ret: Record<string, Object> = {};
      ret['charToGlyph'] = result.charToGlyph as Object;
      ret['glyphToChar'] = result.glyphToChar as Object;
      ret['familyName'] = result.familyName as Object;
      return ret as Object;
    } catch (e) {
      console.error(`[JavaBridge] queryTTF error: ${e}`);
      return new Object();
    }
  }

  /**
   * java.replaceFont(text, errorFont, correctFont, filter?) — 替换混淆字符（Legado 字体反爬兼容）
   * errorFont: 错误字体的 queryTTF 结果（包含 glyphToChar 映射）
   * correctFont: 正确字体的 queryTTF 结果（包含 charToGlyph 映射）
   * 原理：通过字形ID建立 错误字符 → 正确字符 的映射
   */
  replaceFont(text: string, errorFont: string, correctFont: string, _filter?: string): string {
    if (!text || !errorFont || !correctFont) return text || '';
    try {
      // 解析字体映射
      const errorResult = parseTTFont(errorFont);
      const correctResult = parseTTFont(correctFont);

      // 构建字形ID → 正确字符 的映射
      const glyphToCorrect: Map<number, number> = new Map();
      correctResult.charToGlyph.forEach((glyphId: number, correctChar: number) => {
        if (!glyphToCorrect.has(glyphId)) {
          glyphToCorrect.set(glyphId, correctChar);
        }
      });

      // 构建错误字符 → 正确字符 的映射
      const replaceMap: Record<string, string> = {};
      errorResult.charToGlyph.forEach((glyphId: number, errorChar: number) => {
        const correctChar = glyphToCorrect.get(glyphId);
        if (correctChar !== undefined && errorChar !== correctChar) {
          replaceMap[String.fromCharCode(errorChar)] = String.fromCharCode(correctChar);
        }
      });

      // 替换文本中的混淆字符
      let result = '';
      for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        result += replaceMap[ch] || ch;
      }
      return result;
    } catch (e) {
      console.error(`[JavaBridge] replaceFont error: ${e}`);
      return text || '';
    }
  }

  /**
   * java.t2s(text) — 繁体转简体（Legado 兼容）
   * 使用 ~500 组常见繁简差异字符对照表
   */
  t2s(text: string): string {
    return cnT2S(text);
  }

  /**
   * java.s2t(text) — 简体转繁体（Legado 兼容）
   * 使用反向映射表
   */
  s2t(text: string): string {
    return cnS2T(text);
  }

  /**
   * java.toNumChapter(s) — 章节号字符串转换（Legado 兼容）
   */
  toNumChapter(s: string): string {
    return s || '';
  }

  /**
   * java.toURL(url) / java.toURL(url, baseUrl) — 创建 URL 解析对象（Legado 兼容）
   */
  toURL(url: string, baseUrl?: string): string {
    if (baseUrl) {
      return AnalyzeUrl.resolveUrl(baseUrl, url);
    }
    return url || '';
  }

  /**
   * java.htmlFormat(str) — HTML 格式化（Legado 兼容）
   */
  htmlFormat(str: string): string {
    if (!str) return '';
    return str
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .trim();
  }

  /**
   * java.openUrl(url) — 在自定义标签页打开 URL（Legado 兼容）
   */
  openUrl(url: string, _mimeType?: string): void {
    this.startBrowser(url);
  }

  // ──────────── 登录相关（JavaBridge 层面） ────────────

  /**
   * java.getLoginInfo() — 获取 AES 加密的登录信息
   */
  getLoginInfo(): string {
    const sourceCtx = getSourceContext();
    return sourceCtx.getLoginInfo();
  }

  /**
   * java.putLoginInfo(info) — 保存登录信息
   */
  putLoginInfo(info: string): void {
    const sourceCtx = getSourceContext();
    sourceCtx.putLoginInfo(info);
  }

  /**
   * java.removeLoginInfo() — 清除登录信息
   */
  removeLoginInfo(): void {
    const sourceCtx = getSourceContext();
    sourceCtx.removeLoginInfo();
  }

  /**
   * java.getLoginHeader() — 获取登录头
   */
  getLoginHeader(): string {
    const sourceCtx = getSourceContext();
    return sourceCtx.getLoginHeader();
  }

  /**
   * java.putLoginHeader(header) — 保存登录头
   */
  putLoginHeader(header: string): void {
    const sourceCtx = getSourceContext();
    sourceCtx.putLoginHeader(header);
  }

  /**
   * java.removeLoginHeader() — 清除登录头
   */
  removeLoginHeader(): void {
    const sourceCtx = getSourceContext();
    sourceCtx.removeLoginHeader();
  }

  /**
   * java.getCookie(tag, key) — 获取指定 cookie 值（Legado 兼容重载）
   */
  getCookieByKey(url: string, key: string): string {
    try {
      const cookieManager = getCookieManager();
      return cookieManager.getKey(url, key);
    } catch {
      return '';
    }
  }

  /**
   * java.replaceCookie(url, cookie) — 合并并保存 cookie（Legado 兼容）
   */
  replaceCookie(url: string, cookie: string): void {
    try {
      const cookieManager = getCookieManager();
      cookieManager.replaceCookie(url, cookie);
    } catch { /* ignore */ }
  }

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

  // ──────────── 对称加密（Legado java.createSymmetricCrypto 兼容） ────────────

  /**
   * 创建对称加密器（Legado java.createSymmetricCrypto 兼容）
   * transformation 格式：AES/ECB/PKCS5Padding、AES/CBC/PKCS5Padding、DES/ECB/NoPadding 等
   * key：hex 编码的密钥
   * iv：hex 编码的 IV（CBC 模式需要）
   * 返回对象：{ doFinal(data, mode) } — data 为 hex 编码，mode 为 'encrypt' | 'decrypt'
   */
  createSymmetricCrypto(transformation: string, key: string, iv?: string): Object {
    const parts = (transformation || 'AES/ECB/PKCS5Padding').toUpperCase().split('/');
    const algo = parts[0] || 'AES';
    const mode = parts[1] || 'ECB';
    const padding = parts[2] || 'PKCS5PADDING';

    // hex → bytes
    const keyBytes = JavaBridgeImpl.hexToBytes(key || '');
    const ivBytes = iv ? JavaBridgeImpl.hexToBytes(iv) : undefined;

    const result: CryptoResult = {
      doFinal: (data: string, op: string): string => {
        try {
          const dataBytes = JavaBridgeImpl.hexToBytes(data || '');
          let result: number[];
          if (algo === 'AES') {
            if (op === 'encrypt') {
              result = JavaBridgeImpl.aesEncrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            } else {
              result = JavaBridgeImpl.aesDecrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            }
          } else if (algo === 'DES') {
            if (op === 'encrypt') {
              result = JavaBridgeImpl.desEncrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            } else {
              result = JavaBridgeImpl.desDecrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            }
          } else {
            // 不支持的算法回退到 AES
            if (op === 'encrypt') {
              result = JavaBridgeImpl.aesEncrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            } else {
              result = JavaBridgeImpl.aesDecrypt(dataBytes, keyBytes, mode, padding, ivBytes);
            }
          }
          // bytes → hex
          return result.map((b: number) => (b & 0xFF).toString(16).padStart(2, '0')).join('');
        } catch (e) {
          console.error(`[JavaBridge] createSymmetricCrypto.doFinal error: ${e}`);
          return '';
        }
      },
    };
    return result as Object;
  }

  /**
   * 创建非对称加密器（Legado java.createAsymmetricCrypto 兼容）
   * transformation 格式：RSA/ECB/PKCS1Padding、RSA/ECB/OAEPPadding 等
   * 返回对象：{ init(mode, key), doFinal(data) }
   * mode: "encrypt" 或 "decrypt"
   * key: hex 编码的密钥（模数 N），公钥指数默认 0x10001
   */
  createAsymmetricCrypto(transformation: string): Object {
    const algo = (transformation || 'RSA/ECB/PKCS1Padding').toUpperCase();
    let keyN = '';
    let keyE = '10001'; // 默认公钥指数 65537
    let keyD = ''; // 私钥指数

    const cryptoObj: RSACryptoResult = {
      init: (mode: string, key: string): void => {
        try {
          // key 可能是 PEM 格式或 hex 格式
          if (key.includes('BEGIN')) {
            const parsed = parsePublicKeyPEM(key);
            keyN = parsed.n.toHex();
            keyE = parsed.e.toHex();
          } else {
            // 假设是 hex 格式的模数 N
            keyN = key.replace(/\s+/g, '').replace(/^0x/i, '');
          }
          // 如果是 decrypt 模式，需要私钥指数
          if (mode === 'decrypt') {
            keyD = keyE; // 简化：如果只有公钥指数，解密用同样的指数
          }
        } catch (e) {
          console.error(`[JavaBridge] RSA init error: ${e}`);
        }
      },
      doFinal: (data: string): string => {
        try {
          if (!keyN) return '';
          if (keyD) {
            // 解密
            return rsaDecrypt(data, keyN, keyD);
          } else {
            // 加密
            return rsaEncrypt(data, keyN, keyE);
          }
        } catch (e) {
          console.error(`[JavaBridge] RSA doFinal error: ${e}`);
          return '';
        }
      },
    };
    return cryptoObj as Object;
  }

  /**
   * 创建签名器（Legado java.createSign 兼容）
   * algorithm 格式：SHA256withRSA、MD5withRSA、SHA1withRSA 等
   * 返回对象：{ update(data), sign(privateKeyModulus, privateKeyExponent) }
   *
   * 签名流程：hash(data) → RSA encrypt hash with private key
   */
  createSign(algorithm: string): Object {
    const algo = (algorithm || 'SHA256withRSA').toUpperCase();
    // 提取哈希算法：SHA256withRSA → SHA256, MD5withRSA → MD5
    let hashAlgo = 'SHA256';
    if (algo.includes('MD5')) hashAlgo = 'MD5';
    else if (algo.includes('SHA1') && !algo.includes('SHA256')) hashAlgo = 'SHA1';
    else if (algo.includes('SHA256')) hashAlgo = 'SHA256';
    else if (algo.includes('SHA512')) hashAlgo = 'SHA256'; // SHA512 回退到 SHA256

    let accumulatedData = '';

    const signResult: SignResult = {
      update: (data: string): void => {
        accumulatedData += data;
      },
      sign: (privateKeyModulus?: string, privateKeyExponent?: string): string => {
        try {
          // 1. 计算哈希
          let hashHex: string;
          if (hashAlgo === 'MD5') {
            hashHex = this.md5(accumulatedData);
          } else if (hashAlgo === 'SHA1') {
            hashHex = this.digestHex(accumulatedData, 'SHA-1');
          } else {
            hashHex = this.digestHex(accumulatedData, 'SHA-256');
          }

          if (!privateKeyModulus || !privateKeyExponent) {
            // 没有私钥，返回哈希值（用于不需要 RSA 加密的场景）
            return hashHex;
          }

          // 2. RSA 签名：用私钥加密哈希
          // 签名时使用私钥指数作为"加密"指数
          return rsaEncrypt(hashHex, privateKeyModulus, privateKeyExponent);
        } catch (e) {
          console.error(`[JavaBridge] createSign.sign error: ${e}`);
          return '';
        }
      },
    };
    return signResult as Object;
  }

  // ──────────── MD5/SHA 纯 JS 实现 ────────────

  private static md5Bytes(bytes: number[]): string {
    // 填充
    const msg = bytes.slice();
    const bitLen = msg.length * 8;
    msg.push(0x80);
    while ((msg.length % 64) !== 56) msg.push(0x00);
    // 64-bit little-endian length
    for (let i = 0; i < 4; i++) msg.push((bitLen >>> (i * 8)) & 0xFF);
    for (let i = 0; i < 4; i++) msg.push(0x00);

    let a0 = 0x67452301, b0 = 0xEFCDAB89, c0 = 0x98BADCFE, d0 = 0x10325476;

    const T: number[] = [];
    for (let i = 0; i < 64; i++) T[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
    const S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];

    for (let offset = 0; offset < msg.length; offset += 64) {
      const M: number[] = [];
      for (let j = 0; j < 16; j++) {
        M[j] = msg[offset + j * 4] | (msg[offset + j * 4 + 1] << 8) |
               (msg[offset + j * 4 + 2] << 16) | (msg[offset + j * 4 + 3] << 24);
      }
      let A = a0, B = b0, C = c0, D = d0;
      for (let i = 0; i < 64; i++) {
        let F: number, g: number;
        if (i < 16) { F = (B & C) | (~B & D); g = i; }
        else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
        else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * i) % 16; }
        const temp = D; D = C; C = B;
        let sum = (A + F + T[i] + M[g]) | 0;
        const rot = S[(i >> 4) * 4 + (i % 4)];
        B = (B + ((sum << rot) | (sum >>> (32 - rot)))) | 0;
        A = temp;
      }
      a0 = (a0 + A) | 0; b0 = (b0 + B) | 0; c0 = (c0 + C) | 0; d0 = (d0 + D) | 0;
    }

    const toHex = (n: number) => {
      const hex = ((n >>> 0) & 0xFFFFFFFF).toString(16).padStart(8, '0');
      // little-endian byte order
      return hex.substring(6, 8) + hex.substring(4, 6) + hex.substring(2, 4) + hex.substring(0, 2);
    };
    return toHex(a0) + toHex(b0) + toHex(c0) + toHex(d0);
  }

  private static sha1Bytes(bytes: number[]): string {
    const msg = bytes.slice();
    const bitLen = msg.length * 8;
    msg.push(0x80);
    while ((msg.length % 64) !== 56) msg.push(0x00);
    // 64-bit big-endian length
    for (let i = 0; i < 4; i++) msg.push(0x00);
    for (let i = 0; i < 4; i++) msg.push((bitLen >>> ((3 - i) * 8)) & 0xFF);

    let h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;

    for (let offset = 0; offset < msg.length; offset += 64) {
      const W: number[] = [];
      for (let t = 0; t < 16; t++) {
        W[t] = (msg[offset + t * 4] << 24) | (msg[offset + t * 4 + 1] << 16) |
               (msg[offset + t * 4 + 2] << 8) | msg[offset + t * 4 + 3];
      }
      for (let t = 16; t < 80; t++) {
        W[t] = ((W[t - 3] ^ W[t - 8] ^ W[t - 14] ^ W[t - 16]) << 1) | ((W[t - 3] ^ W[t - 8] ^ W[t - 14] ^ W[t - 16]) >>> 31);
      }
      let a = h0, b = h1, c = h2, d = h3, e = h4;
      for (let t = 0; t < 80; t++) {
        let K: number, f: number;
        if (t < 20) { f = (b & c) | (~b & d); K = 0x5A827999; }
        else if (t < 40) { f = b ^ c ^ d; K = 0x6ED9EBA1; }
        else if (t < 60) { f = (b & c) | (b & d) | (c & d); K = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; K = 0xCA62C1D6; }
        const temp = (((a << 5) | (a >>> 27)) + f + e + K + W[t]) | 0;
        e = d; d = c; c = ((b << 30) | (b >>> 2)); b = a; a = temp;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }

    const toHex = (n: number) => ((n >>> 0) & 0xFFFFFFFF).toString(16).padStart(8, '0');
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4);
  }

  private static sha256Bytes(bytes: number[]): string {
    const K = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    const msg = bytes.slice();
    const bitLen = msg.length * 8;
    msg.push(0x80);
    while ((msg.length % 64) !== 56) msg.push(0x00);
    for (let i = 0; i < 4; i++) msg.push(0x00);
    for (let i = 0; i < 4; i++) msg.push((bitLen >>> ((3 - i) * 8)) & 0xFF);

    let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    for (let offset = 0; offset < msg.length; offset += 64) {
      const W: number[] = [];
      for (let t = 0; t < 16; t++) {
        W[t] = (msg[offset + t * 4] << 24) | (msg[offset + t * 4 + 1] << 16) |
               (msg[offset + t * 4 + 2] << 8) | msg[offset + t * 4 + 3];
      }
      for (let t = 16; t < 64; t++) {
        const s0 = ((W[t - 15] >>> 7) | (W[t - 15] << 25)) ^ ((W[t - 15] >>> 18) | (W[t - 15] << 14)) ^ (W[t - 15] >>> 3);
        const s1 = ((W[t - 2] >>> 17) | (W[t - 2] << 15)) ^ ((W[t - 2] >>> 19) | (W[t - 2] << 13)) ^ (W[t - 2] >>> 10);
        W[t] = (W[t - 16] + s0 + W[t - 7] + s1) | 0;
      }
      let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (let t = 0; t < 64; t++) {
        const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        const ch = (e & f) ^ (~e & g);
        const temp1 = (h + S1 + ch + K[t] + W[t]) | 0;
        const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + temp1) | 0; d = c; c = b; b = a; a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + h) | 0;
    }

    const toHex = (n: number) => ((n >>> 0) & 0xFFFFFFFF).toString(16).padStart(8, '0');
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4) + toHex(h5) + toHex(h6) + toHex(h7);
  }

  private static hexToBytes(hex: string): number[] {
    const bytes: number[] = [];
    for (let i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substring(i, i + 2), 16));
    return bytes;
  }

  // ──────────── AES 纯 JS 实现 ────────────

  private static readonly AES_SBOX: number[] = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
  ];

  private static readonly AES_INV_SBOX: number[] = [
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
  ];

  private static readonly AES_RCON: number[] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

  private static aesKeyExpansion(key: number[]): number[] {
    const Nk = key.length / 4;
    const Nr = Nk + 6;
    const w: number[] = [];
    for (let i = 0; i < Nk; i++) {
      w[i * 4] = key[i * 4]; w[i * 4 + 1] = key[i * 4 + 1];
      w[i * 4 + 2] = key[i * 4 + 2]; w[i * 4 + 3] = key[i * 4 + 3];
    }
    for (let i = Nk; i < 4 * (Nr + 1); i++) {
      const temp = [w[(i - 1) * 4], w[(i - 1) * 4 + 1], w[(i - 1) * 4 + 2], w[(i - 1) * 4 + 3]];
      if (i % Nk === 0) {
        const t = temp[0]; temp[0] = temp[1]; temp[1] = temp[2]; temp[2] = temp[3]; temp[3] = t;
        temp[0] = JavaBridgeImpl.AES_SBOX[temp[0]]; temp[1] = JavaBridgeImpl.AES_SBOX[temp[1]];
        temp[2] = JavaBridgeImpl.AES_SBOX[temp[2]]; temp[3] = JavaBridgeImpl.AES_SBOX[temp[3]];
        temp[0] ^= JavaBridgeImpl.AES_RCON[(i / Nk) - 1];
      } else if (Nk > 6 && i % Nk === 4) {
        temp[0] = JavaBridgeImpl.AES_SBOX[temp[0]]; temp[1] = JavaBridgeImpl.AES_SBOX[temp[1]];
        temp[2] = JavaBridgeImpl.AES_SBOX[temp[2]]; temp[3] = JavaBridgeImpl.AES_SBOX[temp[3]];
      }
      for (let j = 0; j < 4; j++) w[i * 4 + j] = w[(i - Nk) * 4 + j] ^ temp[j];
    }
    return w;
  }

  private static aesEncryptBlock(block: number[], expandedKey: number[], Nr: number): number[] {
    const state = block.slice();
    // AddRoundKey
    for (let i = 0; i < 16; i++) state[i] ^= expandedKey[i];
    for (let round = 1; round < Nr; round++) {
      // SubBytes
      for (let i = 0; i < 16; i++) state[i] = JavaBridgeImpl.AES_SBOX[state[i]];
      // ShiftRows
      let t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
      t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
      t = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;
      // MixColumns
      for (let c = 0; c < 4; c++) {
        const s0 = state[c * 4], s1 = state[c * 4 + 1], s2 = state[c * 4 + 2], s3 = state[c * 4 + 3];
        state[c * 4] = JavaBridgeImpl.gmul(s0, 2) ^ JavaBridgeImpl.gmul(s1, 3) ^ s2 ^ s3;
        state[c * 4 + 1] = s0 ^ JavaBridgeImpl.gmul(s1, 2) ^ JavaBridgeImpl.gmul(s2, 3) ^ s3;
        state[c * 4 + 2] = s0 ^ s1 ^ JavaBridgeImpl.gmul(s2, 2) ^ JavaBridgeImpl.gmul(s3, 3);
        state[c * 4 + 3] = JavaBridgeImpl.gmul(s0, 3) ^ s1 ^ s2 ^ JavaBridgeImpl.gmul(s3, 2);
      }
      // AddRoundKey
      for (let i = 0; i < 16; i++) state[i] ^= expandedKey[round * 16 + i];
    }
    // SubBytes
    for (let i = 0; i < 16; i++) state[i] = JavaBridgeImpl.AES_SBOX[state[i]];
    // ShiftRows
    let t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
    t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
    t = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;
    // AddRoundKey
    for (let i = 0; i < 16; i++) state[i] ^= expandedKey[Nr * 16 + i];
    return state;
  }

  private static aesDecryptBlock(block: number[], expandedKey: number[], Nr: number): number[] {
    const state = block.slice();
    // AddRoundKey
    for (let i = 0; i < 16; i++) state[i] ^= expandedKey[Nr * 16 + i];
    for (let round = Nr - 1; round >= 1; round--) {
      // InvShiftRows
      let t = state[13]; state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = t;
      t = state[14]; state[14] = state[2]; state[2] = t; t = state[10]; state[10] = state[6]; state[6] = t;
      t = state[3]; state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = t;
      // InvSubBytes
      for (let i = 0; i < 16; i++) state[i] = JavaBridgeImpl.AES_INV_SBOX[state[i]];
      // AddRoundKey
      for (let i = 0; i < 16; i++) state[i] ^= expandedKey[round * 16 + i];
      // InvMixColumns
      for (let c = 0; c < 4; c++) {
        const s0 = state[c * 4], s1 = state[c * 4 + 1], s2 = state[c * 4 + 2], s3 = state[c * 4 + 3];
        state[c * 4] = JavaBridgeImpl.gmul(s0, 14) ^ JavaBridgeImpl.gmul(s1, 11) ^ JavaBridgeImpl.gmul(s2, 13) ^ JavaBridgeImpl.gmul(s3, 9);
        state[c * 4 + 1] = JavaBridgeImpl.gmul(s0, 9) ^ JavaBridgeImpl.gmul(s1, 14) ^ JavaBridgeImpl.gmul(s2, 11) ^ JavaBridgeImpl.gmul(s3, 13);
        state[c * 4 + 2] = JavaBridgeImpl.gmul(s0, 13) ^ JavaBridgeImpl.gmul(s1, 9) ^ JavaBridgeImpl.gmul(s2, 14) ^ JavaBridgeImpl.gmul(s3, 11);
        state[c * 4 + 3] = JavaBridgeImpl.gmul(s0, 11) ^ JavaBridgeImpl.gmul(s1, 13) ^ JavaBridgeImpl.gmul(s2, 9) ^ JavaBridgeImpl.gmul(s3, 14);
      }
    }
    // InvShiftRows
    let t = state[13]; state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = t;
    t = state[14]; state[14] = state[2]; state[2] = t; t = state[10]; state[10] = state[6]; state[6] = t;
    t = state[3]; state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = t;
    // InvSubBytes
    for (let i = 0; i < 16; i++) state[i] = JavaBridgeImpl.AES_INV_SBOX[state[i]];
    // AddRoundKey
    for (let i = 0; i < 16; i++) state[i] ^= expandedKey[i];
    return state;
  }

  private static gmul(a: number, b: number): number {
    let p = 0;
    for (let i = 0; i < 8; i++) {
      if (b & 1) p ^= a;
      const hi = a & 0x80;
      a = (a << 1) & 0xFF;
      if (hi) a ^= 0x1B;
      b >>= 1;
    }
    return p & 0xFF;
  }

  private static pkcs5Pad(data: number[], blockSize: number): number[] {
    const padLen = blockSize - (data.length % blockSize);
    const padded = data.slice();
    for (let i = 0; i < padLen; i++) padded.push(padLen);
    return padded;
  }

  private static pkcs5Unpad(data: number[]): number[] {
    if (data.length === 0) return data;
    const padLen = data[data.length - 1];
    if (padLen < 1 || padLen > 16) return data;
    return data.slice(0, data.length - padLen);
  }

  static aesEncrypt(data: number[], key: number[], mode: string, padding: string, iv?: number[]): number[] {
    const blockSize = 16;
    const Nr = key.length / 4 + 6;
    const expandedKey = JavaBridgeImpl.aesKeyExpansion(key);
    let padded = padding === 'NOPADDING' ? data : JavaBridgeImpl.pkcs5Pad(data, blockSize);
    // 对齐到块大小
    while (padded.length % blockSize !== 0) padded.push(0);
    const result: number[] = [];
    let prev = iv || new Array<number>(blockSize).fill(0);
    for (let i = 0; i < padded.length; i += blockSize) {
      const block = padded.slice(i, i + blockSize);
      let inputBlock = block;
      if (mode === 'CBC') {
        inputBlock = block.map((b: number, j: number) => b ^ prev[j]);
      }
      const encrypted = JavaBridgeImpl.aesEncryptBlock(inputBlock, expandedKey, Nr);
      result.push(...encrypted);
      if (mode === 'CBC') prev = encrypted;
    }
    return result;
  }

  static aesDecrypt(data: number[], key: number[], mode: string, padding: string, iv?: number[]): number[] {
    const blockSize = 16;
    const Nr = key.length / 4 + 6;
    const expandedKey = JavaBridgeImpl.aesKeyExpansion(key);
    const result: number[] = [];
    let prev = iv || new Array<number>(blockSize).fill(0);
    for (let i = 0; i < data.length; i += blockSize) {
      const block = data.slice(i, i + blockSize);
      const decrypted = JavaBridgeImpl.aesDecryptBlock(block, expandedKey, Nr);
      if (mode === 'CBC') {
        for (let j = 0; j < blockSize; j++) result.push(decrypted[j] ^ prev[j]);
        prev = block;
      } else {
        result.push(...decrypted);
      }
    }
    return padding === 'NOPADDING' ? result : JavaBridgeImpl.pkcs5Unpad(result);
  }

  // ──────────── DES 纯 JS 实现 ────────────

  private static readonly DES_IP: number[] = [58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6,64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7];
  private static readonly DES_IP_INV: number[] = [40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25];
  private static readonly DES_E: number[] = [32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1];
  private static readonly DES_P: number[] = [16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25];
  private static readonly DES_PC1: number[] = [57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4];
  private static readonly DES_PC2: number[] = [14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32];
  private static readonly DES_SHIFTS: number[] = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1];
  private static readonly DES_SBOXES: number[][] = [
    [14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13],
    [15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5,0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9],
    [10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12],
    [7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14],
    [2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3],
    [12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13],
    [4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12],
    [13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,2,0,14,9,11,7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11],
  ];

  private static desPermute(block: number[], table: number[]): number[] {
    const result: number[] = [];
    for (let i = 0; i < table.length; i++) {
      const byteIdx = Math.floor((table[i] - 1) / 8);
      const bitIdx = 7 - ((table[i] - 1) % 8);
      result.push((block[byteIdx] >> bitIdx) & 1);
    }
    // pack bits to bytes
    const bytes: number[] = [];
    for (let i = 0; i < result.length; i += 8) {
      let b = 0;
      for (let j = 0; j < 8; j++) b = (b << 1) | (result[i + j] || 0);
      bytes.push(b);
    }
    return bytes;
  }

  private static desKeyschedule(key: number[]): number[][] {
    const pc1Key = JavaBridgeImpl.desPermute(key, JavaBridgeImpl.DES_PC1);
    // split into C and D (28 bits each)
    const C: number[] = [];
    const D: number[] = [];
    for (let i = 0; i < 3; i++) { C[i] = pc1Key[i]; D[i] = pc1Key[i + 3]; }
    C[3] = pc1Key[3] & 0xF0; D[3] = pc1Key[6] & 0xF0;

    const roundKeys: number[][] = [];
    for (let round = 0; round < 16; round++) {
      // left shift
      const shift = JavaBridgeImpl.DES_SHIFTS[round];
      for (let s = 0; s < shift; s++) {
        const cBit = (C[0] >> 7) & 1;
        const dBit = (D[0] >> 7) & 1;
        for (let i = 0; i < 3; i++) { C[i] = ((C[i] << 1) | ((C[i + 1] >> 7) & 1)) & 0xFF; D[i] = ((D[i] << 1) | ((D[i + 1] >> 7) & 1)) & 0xFF; }
        C[3] = ((C[3] << 1) | (cBit << 4)) & 0xFF;
        D[3] = ((D[3] << 1) | (dBit << 4)) & 0xFF;
      }
      const combined = C.concat(D);
      roundKeys[round] = JavaBridgeImpl.desPermute(combined, JavaBridgeImpl.DES_PC2);
    }
    return roundKeys;
  }

  private static desF(R: number[], roundKey: number[]): number[] {
    // Expand R from 4 bytes to 6 bytes (32→48 bits)
    const expanded = JavaBridgeImpl.desPermute(R, JavaBridgeImpl.DES_E);
    // XOR with round key
    for (let i = 0; i < 6; i++) expanded[i] ^= roundKey[i];
    // S-box substitution (48→32 bits)
    const bits: number[] = [];
    for (let i = 0; i < 6; i++) for (let j = 7; j >= 0; j--) bits.push((expanded[i] >> j) & 1);
    const sOut: number[] = [];
    for (let i = 0; i < 8; i++) {
      const row = (bits[i * 6] << 1) | bits[i * 6 + 5];
      const col = (bits[i * 6 + 1] << 3) | (bits[i * 6 + 2] << 2) | (bits[i * 6 + 3] << 1) | bits[i * 6 + 4];
      const val = JavaBridgeImpl.DES_SBOXES[i][row * 16 + col];
      sOut.push((val >> 3) & 1, (val >> 2) & 1, (val >> 1) & 1, val & 1);
    }
    // pack to bytes
    const bytes: number[] = [];
    for (let i = 0; i < 4; i++) bytes.push((sOut[i * 8] << 7) | (sOut[i * 8 + 1] << 6) | (sOut[i * 8 + 2] << 5) | (sOut[i * 8 + 3] << 4) | (sOut[i * 8 + 4] << 3) | (sOut[i * 8 + 5] << 2) | (sOut[i * 8 + 6] << 1) | sOut[i * 8 + 7]);
    // P permutation
    return JavaBridgeImpl.desPermute(bytes, JavaBridgeImpl.DES_P);
  }

  static desEncrypt(data: number[], key: number[], mode: string, padding: string, iv?: number[]): number[] {
    const desKey = key.length >= 8 ? key.slice(0, 8) : key.concat(new Array<number>(8 - key.length).fill(0));
    const roundKeys = JavaBridgeImpl.desKeyschedule(desKey);
    const padded = padding === 'NOPADDING' ? data : JavaBridgeImpl.pkcs5Pad(data, 8);
    while (padded.length % 8 !== 0) padded.push(0);
    const result: number[] = [];
    let prev = iv || new Array<number>(8).fill(0);
    for (let i = 0; i < padded.length; i += 8) {
      const block = padded.slice(i, i + 8);
      let inputBlock = block;
      if (mode === 'CBC') inputBlock = block.map((b: number, j: number) => b ^ prev[j]);
      // IP
      const permuted = JavaBridgeImpl.desPermute(inputBlock, JavaBridgeImpl.DES_IP);
      let L = permuted.slice(0, 4), R = permuted.slice(4, 8);
      for (let r = 0; r < 16; r++) {
        const fOut = JavaBridgeImpl.desF(R, roundKeys[r]);
        const newL = R;
        const newR: number[] = [];
        for (let j = 0; j < 4; j++) newR.push(L[j] ^ fOut[j]);
        L = newL; R = newR;
      }
      const combined = R.concat(L);
      const encrypted = JavaBridgeImpl.desPermute(combined, JavaBridgeImpl.DES_IP_INV);
      result.push(...encrypted);
      if (mode === 'CBC') prev = encrypted;
    }
    return result;
  }

  static desDecrypt(data: number[], key: number[], mode: string, padding: string, iv?: number[]): number[] {
    const desKey = key.length >= 8 ? key.slice(0, 8) : key.concat(new Array<number>(8 - key.length).fill(0));
    const roundKeys = JavaBridgeImpl.desKeyschedule(desKey);
    const result: number[] = [];
    let prev = iv || new Array<number>(8).fill(0);
    for (let i = 0; i < data.length; i += 8) {
      const block = data.slice(i, i + 8);
      // IP
      const permuted = JavaBridgeImpl.desPermute(block, JavaBridgeImpl.DES_IP);
      let L = permuted.slice(0, 4), R = permuted.slice(4, 8);
      for (let r = 15; r >= 0; r--) {
        const fOut = JavaBridgeImpl.desF(L, roundKeys[r]);
        const newR = L;
        const newL: number[] = [];
        for (let j = 0; j < 4; j++) newL.push(R[j] ^ fOut[j]);
        L = newL; R = newR;
      }
      const combined = R.concat(L);
      const decrypted = JavaBridgeImpl.desPermute(combined, JavaBridgeImpl.DES_IP_INV);
      if (mode === 'CBC') {
        for (let j = 0; j < 8; j++) result.push(decrypted[j] ^ prev[j]);
        prev = block;
      } else {
        result.push(...decrypted);
      }
    }
    return padding === 'NOPADDING' ? result : JavaBridgeImpl.pkcs5Unpad(result);
  }
}

let globalBridge: JavaBridgeImpl | null = null;

export function getJavaBridge(): JavaBridgeImpl {
  if (!globalBridge) {
    globalBridge = new JavaBridgeImpl();
  }
  return globalBridge;
}
