/**
 * JavaBridge - Legado Java 桥接（书源 JS 规则中的 java.xxx 方法）
 *
 * 支持：
 *  - java.get(key) / java.put(key, value) - 变量存取
 *  - java.connect(url) - HTTP GET 请求
 *  - java.ajax(url, options) - HTTP 请求（支持 POST）
 *  - java.getStrResponse() - 获取最后一次请求的响应
 *  - java.log(msg) - 日志输出
 */

import { HttpClient } from '../http/HttpClient';

interface AjaxOptions {
  method?: string;
  body?: string;
  headers?: Record<string, string>;
}

export class JavaBridgeImpl {
  private variables: Record<string, string> = {};
  private lastResponse: string = '';

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
      const method = options?.method?.toUpperCase() || 'GET';
      let response: string;
      if (method === 'POST') {
        const headers = options?.headers || { 'Content-Type': 'application/x-www-form-urlencoded' };
        response = await HttpClient.post(url, options?.body || '', headers);
      } else {
        response = await HttpClient.get(url);
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

  /**
   * java.webView(html, url, js) - Legado: 通过 webview 渲染并执行 js
   * 当前实现：暂不渲染 webview，直接返回输入 html（书源依赖动态渲染时可能不工作）
   */
  async webView(html: string, _url?: string, _js?: string): Promise<string> {
    return html || '';
  }

  /**
   * java.timeFormat(timestamp) - 时间戳格式化（当前简单返回 ISO）
   */
  timeFormat(ts: number): string {
    try {
      return new Date(ts).toISOString();
    } catch {
      return String(ts);
    }
  }

  /** java.base64Encode(str) - Base64 编码（UTF-8） */
  base64Encode(s: string): string {
    if (!s) return '';
    try {
      // ArkTS 全局有 util.Base64.encodeSync，但简单起见用 btoa-like 实现
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
          // surrogate pair
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

  /** java.base64Decode(str) - Base64 解码（UTF-8） */
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
      // UTF-8 字节 → 字符串
      let out = '';
      let i = 0;
      while (i < bytes.length) {
        const b = bytes[i++];
        if (b < 0x80) out += String.fromCharCode(b);
        else if (b < 0xC0) continue; // 非法
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

  /** java.md5(str) - 摘要（不实现，返回空，避免硬塞算法。书源极少强依赖） */
  md5(_s: string): string { return ''; }

  /** java.randomUUID() - 随机 UUID v4 */
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
