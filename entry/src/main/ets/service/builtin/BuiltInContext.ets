/**
 * BuiltInContext - 内置源公共依赖（HTTP / Jsoup / URL 工具）
 */

import { HttpClient } from '../http/HttpClient';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { SimpleCSSSelector, HTMLElement } from '../rule/SimpleCSSSelector';

export const MOBILE_UA =
  'Mozilla/5.0 (Linux; U; Android 11; zh-cn; MI 8 Build/RKQ1.200826.002) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/77.0.3865.120 MQQBrowser/13.7 Mobile Safari/537.36';

export const DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/* ─────────────────────── Jsoup-like wrapper ─────────────────────── */

export class JElement {
  el: HTMLElement;
  baseUrl: string;

  constructor(el: HTMLElement, baseUrl: string) {
    this.el = el;
    this.baseUrl = baseUrl;
  }

  text(): string {
    return SimpleCSSSelector.getText(this.el).trim();
  }

  ownText(): string {
    let out = '';
    for (const cn of this.el.childNodes) {
      if (cn.type === 'text' && cn.text) out += cn.text;
    }
    return out.trim();
  }

  attr(name: string): string {
    return SimpleCSSSelector.getAttribute(this.el, name) || '';
  }

  absUrl(name: string): string {
    const v = this.attr(name);
    if (!v) return '';
    return JsoupUtil.resolveUrl(this.baseUrl, v);
  }

  hasClass(cls: string): boolean {
    const c = (SimpleCSSSelector.getAttribute(this.el, 'class') || '').split(/\s+/);
    return c.indexOf(cls) >= 0;
  }

  outerHtml(): string {
    return SimpleCSSSelector.outerHTML(this.el);
  }

  innerHtml(): string {
    return SimpleCSSSelector.innerHTML(this.el);
  }

  selectFirst(selector: string): JElement | null {
    const arr = SimpleCSSSelector.querySelectorAll(this.el, selector);
    return arr.length > 0 ? new JElement(arr[0], this.baseUrl) : null;
  }

  select(selector: string): JElement[] {
    const arr = SimpleCSSSelector.querySelectorAll(this.el, selector);
    const out: JElement[] = [];
    for (const e of arr) out.push(new JElement(e, this.baseUrl));
    return out;
  }

  children(): JElement[] {
    const out: JElement[] = [];
    for (const e of this.el.children) out.push(new JElement(e, this.baseUrl));
    return out;
  }
}

export class JsoupUtil {
  static parse(html: string, baseUrl: string = ''): JElement {
    const root = SimpleCSSSelector.parseHTML(html);
    return new JElement(root, baseUrl);
  }

  /** 相对路径转绝对路径（仿 Jsoup absUrl） */
  static resolveUrl(base: string, ref: string): string {
    if (!ref) return '';
    const trimmed = ref.trim();
    if (!trimmed) return '';
    if (/^[a-z][a-z0-9+\-.]*:/i.test(trimmed)) return trimmed;
    if (trimmed.startsWith('//')) {
      const m = base.match(/^([a-z]+):/i);
      return (m ? m[1] : 'http') + ':' + trimmed;
    }
    if (!base) return trimmed;
    try {
      const m = base.match(/^([a-z]+:\/\/[^/]+)(\/[^?#]*)?/i);
      if (!m) return trimmed;
      const origin = m[1];
      const path = m[2] || '/';
      if (trimmed.startsWith('/')) return origin + trimmed;
      const dirEnd = path.lastIndexOf('/');
      const dir = dirEnd >= 0 ? path.substring(0, dirEnd + 1) : '/';
      return origin + dir + trimmed;
    } catch {
      return trimmed;
    }
  }
}

/* ─────────────────────── HTTP helpers ─────────────────────── */

export class FetchOptions {
  headers: Record<string, string> = {};
  charset: string = '';
  desktop: boolean = false;
  body: string = '';
  method: string = 'GET';
}

function buildHeaders(opts?: FetchOptions): Record<string, string> {
  const h: Record<string, string> = {};
  h['User-Agent'] = (opts && opts.desktop) ? DESKTOP_UA : MOBILE_UA;
  if (opts && opts.headers) {
    const keys = Object.keys(opts.headers);
    for (const k of keys) h[k] = opts.headers[k];
  }
  return h;
}

export async function fetchText(url: string, opts?: FetchOptions): Promise<string> {
  const headers = buildHeaders(opts);
  const method = (opts && opts.method ? opts.method : 'GET').toUpperCase();
  const charset = opts ? opts.charset : '';
  if (method === 'POST') {
    return HttpClient.post(url, opts ? opts.body : '', headers, charset);
  }
  return HttpClient.get(url, headers, charset);
}

export async function fetchJson(url: string, opts?: FetchOptions): Promise<JsonObj> {
  const text = await fetchText(url, opts);
  const parsed: Object = JSON.parse(text) as Object;
  return new JsonObj(parsed);
}

export async function fetchDoc(url: string, opts?: FetchOptions): Promise<JElement> {
  const html = await fetchText(url, opts);
  return JsoupUtil.parse(html, url);
}

/** 构造 FetchOptions（避免 obj-literal） */
export class Opts {
  static of(): FetchOptions {
    return new FetchOptions();
  }
  static desktop(): FetchOptions {
    const o = new FetchOptions();
    o.desktop = true;
    return o;
  }
  static charset(cs: string): FetchOptions {
    const o = new FetchOptions();
    o.charset = cs;
    return o;
  }
  static withHeaders(h: Record<string, string>, desktop: boolean = false): FetchOptions {
    const o = new FetchOptions();
    o.headers = h;
    o.desktop = desktop;
    return o;
  }
  static post(body: string): FetchOptions {
    const o = new FetchOptions();
    o.method = 'POST';
    o.body = body;
    return o;
  }
}

/* ─────────────────────── URL 编码 ─────────────────────── */

export function encodeUri(str: string, charset?: string): string {
  return CharsetCodec.encodeUriForCharset(str, charset || 'utf-8');
}

/* ─────────────────────── 简易 JSON 工具 ─────────────────────── */

export class JsonObj {
  raw: Record<string, Object>;

  constructor(obj: Object | null | undefined) {
    if (obj === undefined || obj === null) {
      this.raw = {} as Record<string, Object>;
    } else {
      this.raw = obj as Record<string, Object>;
    }
  }

  has(key: string): boolean {
    const v = this.raw[key];
    return v !== undefined && v !== null;
  }

  isNull(key: string): boolean {
    const v = this.raw[key];
    return v === undefined || v === null;
  }

  getString(key: string, fallback: string = ''): string {
    const v = this.raw[key];
    if (v === undefined || v === null) return fallback;
    return String(v);
  }

  optString(key: string, fallback: string = ''): string {
    return this.getString(key, fallback);
  }

  getInt(key: string, fallback: number = 0): number {
    const v = this.raw[key];
    if (v === undefined || v === null) return fallback;
    const n = Number(v);
    return isNaN(n) ? fallback : Math.trunc(n);
  }

  optInt(key: string, fallback: number = 0): number {
    return this.getInt(key, fallback);
  }

  getLong(key: string, fallback: number = 0): number {
    return this.getInt(key, fallback);
  }

  getObj(key: string): JsonObj {
    return new JsonObj(this.raw[key]);
  }

  getArr(key: string): JsonArr {
    return new JsonArr(this.raw[key]);
  }
}

export class JsonArr {
  raw: Object[];

  constructor(arr: Object | null | undefined) {
    if (Array.isArray(arr)) {
      this.raw = arr as Object[];
    } else {
      this.raw = [];
    }
  }

  length(): number {
    return this.raw.length;
  }

  getObj(i: number): JsonObj {
    return new JsonObj(this.raw[i]);
  }

  getString(i: number, fallback: string = ''): string {
    const v = this.raw[i];
    if (v === undefined || v === null) return fallback;
    return String(v);
  }

  getLong(i: number, fallback: number = 0): number {
    const v = this.raw[i];
    if (v === undefined || v === null) return fallback;
    const n = Number(v);
    return isNaN(n) ? fallback : Math.trunc(n);
  }
}

/** 直接把 JS 值包成 JsonObj */
export function jo(v: Object): JsonObj {
  return new JsonObj(v);
}
