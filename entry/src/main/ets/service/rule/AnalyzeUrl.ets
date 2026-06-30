/**
 * AnalyzeUrl - URL 模板解析器（对齐 Legado AnalyzeUrl.kt）
 *
 * 支持：
 *  - {{key}} / {{page}} / {{searchPage}} 模板变量
 *  - <page1,page2,page3> 分页语法
 *  - @js: / <js>...</js> 内嵌 JS 执行
 *  - URL 后跟 ,{method,body,headers,charset} 配置
 *  - GET 查询参数 / POST body 编码
 *  - 相对 URL 解析
 *  - JS 中 java.get(key) / java.put(key, value) 读写变量
 */

import { getJSExecutor } from '../js/JSExecutor';
import { getJavaBridge } from './JavaBridge';
import { getSourceContext } from './SourceContext';
import { CharsetCodec } from '../../utils/CharsetCodec';

export interface UrlOption {
  method: string;
  charset?: string;
  headers?: Record<string, string>;
  body?: string;
  webView?: boolean;
  webJs?: string;
  retry?: number;
  type?: string;
  js?: string;
}

export interface AnalyzedUrl {
  url: string;
  method: string;
  body?: string;
  charset?: string;
  headers: Record<string, string>;
  webView?: boolean;
  webJs?: string;
  retry: number;
}

interface UrlSplit {
  baseUrl: string;
  option: UrlOption;
}

export interface SplitUrlResult {
  url: string;
  config: UrlOption;
}

interface TemplateContext {
  key?: string;
  page?: number;
  speakText?: string;
  speakSpeed?: number;
  book?: Object;
  chapter?: Object;
  baseUrl?: string;
  result?: Object;
  _jsLib?: string;
  _sourceVar?: string;
}

interface LooseParseState {
  text: string;
  pos: number;
}

export class AnalyzeUrl {
  private ruleUrl: string;
  private context: TemplateContext;
  private sourceHeader: string;

  constructor(ruleUrl: string, context: TemplateContext = {}, sourceHeader?: string, variables?: Record<string, string>) {
    this.ruleUrl = ruleUrl;
    this.context = context;
    this.sourceHeader = sourceHeader || '';
    // JavaBridge 使用全局单例
    if (variables) {
      const javaBridge = getJavaBridge();
      javaBridge.setVariables(variables);
    }
  }

  async getUrl(): Promise<AnalyzedUrl> {
    // 1. 拆出 ,{...} 配置，先拿到 charset/method 等
    const split = this.splitConfig(this.ruleUrl);
    let baseUrl = split.baseUrl;
    const option = split.option;
    const charset = option.charset || '';

    // 2. 在 baseUrl 上执行 @js: / <js>...</js>
    baseUrl = await this.analyzeJs(baseUrl);

    // 3. 替换模板变量（按 charset percent-encode）
    baseUrl = await this.replaceTemplateVars(baseUrl, charset);

    // 3.5 GET：URL 中已有的非 ASCII 字符按 charset percent-encode（保留已编码的 %XX）
    baseUrl = AnalyzeUrl.reencodeUrlQuery(baseUrl, charset);

    // 3.6 POST：body 先替换模板变量（{{key}}/{{page}}/{{js}}，按 charset percent-encode），
    //     再按 charset 重编码剩余非 ASCII value（encodeIfNeeded 会保留已编码的 %XX，不会双重编码）
    let bodyOut = option.body;
    const bodyLooksJson = bodyOut ? AnalyzeUrl.isJsonBody(bodyOut, option.headers) : false;
    if (bodyOut) {
      bodyOut = await this.replaceTemplateVars(bodyOut, charset, !bodyLooksJson);
      if (!bodyLooksJson && (option.method || 'GET').toUpperCase() === 'POST' && bodyOut.indexOf('=') > 0) {
        bodyOut = AnalyzeUrl.reencodeFormBody(bodyOut, charset);
      }
    }

    // 4. 合并 headers
    const headers: Record<string, string> = {};
    const sourceHeaders = await this.parseHeaderRule(this.sourceHeader);
    const srcKeys = Object.keys(sourceHeaders);
    for (const sk of srcKeys) {
      headers[sk] = sourceHeaders[sk];
    }
    if (option.headers) {
      const keys = Object.keys(option.headers);
      for (const k of keys) {
        headers[k] = option.headers[k];
      }
    }
    if ((option.method || 'GET').toUpperCase() === 'POST' && bodyOut && bodyLooksJson
      && !AnalyzeUrl.hasHeader(headers, 'content-type')) {
      headers['Content-Type'] = 'application/json';
    }

    // 5. 剥离 ## 源分组标记
    baseUrl = AnalyzeUrl.stripSourceGroup(baseUrl);

    return {
      url: baseUrl,
      method: option.method || 'GET',
      body: bodyOut,
      charset: option.charset,
      headers,
      webView: option.webView,
      webJs: option.webJs,
      retry: option.retry || 0,
    };
  }

  private splitConfig(url: string): UrlSplit {
    const split = AnalyzeUrl.splitUrlConfig(url);
    const result: UrlSplit = { baseUrl: split.url, option: split.config };
    return result;
  }

  private async analyzeJs(url: string): Promise<string> {
    // <js>...</js> 块
    const jsTagRegex = /<js>([\s\S]+?)<\/js>/gi;
    let result = url;
    let match = jsTagRegex.exec(result);
    while (match !== null) {
      const code = match[1];
      const jsResult = await this.evalJs(code);
      result = result.replace(match[0], jsResult);
      jsTagRegex.lastIndex = 0;
      match = jsTagRegex.exec(result);
    }

    // @js:code（整个 URL 是 JS）
    if (/^@?js:/i.test(result.trim())) {
      const code = result.replace(/^@?js:/i, '');
      result = await this.evalJs(code);
    }

    return result;
  }

  private async replaceTemplateVars(url: string, charset?: string, encodeVars: boolean = true): Promise<string> {
    let result = url;
    const page = this.context.page || 1;
    const key = this.context.key || '';
    const enc = (s: string): string => encodeVars ? CharsetCodec.encodeUriForCharset(s, charset) : s;

    // <page1,page2,page3> 分页语法
    result = result.replace(/<([^>]+)>/g, (_match: string, inner: string): string => {
      if (inner.includes(',')) {
        const pages = inner.split(',');
        const idx = Math.min(page - 1, pages.length - 1);
        return pages[Math.max(0, idx)].trim();
      }
      return inner;
    });

    // {{key}} / {{keyword}} / {{searchKey}}
    result = result.replace(/\{\{key\}\}/g, enc(key));
    result = result.replace(/\{\{keyword\}\}/g, enc(key));
    result = result.replace(/\{\{searchKey\}\}/g, enc(key));

    // {{page}} / {{searchPage}}
    result = result.replace(/\{\{page\}\}/g, String(page));
    result = result.replace(/\{\{searchPage\}\}/g, String(page));
    result = result.replace(/\{\{pageSize\}\}/g, '20');

    // {{js_expression}} 内嵌 JS
    const evalPattern = /\{\{([\s\S]+?)\}\}/g;
    let evalMatch = evalPattern.exec(result);
    while (evalMatch !== null) {
      const expr = evalMatch[1].trim();
      // 跳过已替换的纯数字/已编码内容
      if (!/^(key|keyword|searchKey|page|searchPage|pageSize)$/.test(expr)) {
        const jsResult = await this.evalJs(expr);
        result = result.replace(evalMatch[0], jsResult);
        evalPattern.lastIndex = 0;
      }
      evalMatch = evalPattern.exec(result);
    }

    return result;
  }

  private findConfigStart(url: string): number {
    return AnalyzeUrl.findConfigIdx(url);
  }

  private async evalJs(code: string): Promise<string> {
    try {
      const executor = getJSExecutor();
      const javaBridge = getJavaBridge();
      const ctx: Record<string, Object> = {};
      ctx['java'] = javaBridge;
      ctx['source'] = getSourceContext();
      if (this.context.key !== undefined) ctx['key'] = this.context.key;
      if (this.context.page !== undefined) ctx['page'] = this.context.page;
      if (this.context.baseUrl !== undefined) ctx['baseUrl'] = this.context.baseUrl;
      if (this.context.result !== undefined) ctx['result'] = this.context.result;
      if (this.context.book !== undefined) ctx['book'] = this.context.book;
      if (this.context.chapter !== undefined) ctx['chapter'] = this.context.chapter;
      if (this.context.speakText !== undefined) ctx['speakText'] = this.context.speakText;
      // 注入 jsLib（如果有）
      if (this.context._jsLib !== undefined) ctx['_jsLib'] = this.context._jsLib;
      // 注入源变量 JSON（供 source.getVariable() 返回）
      if (this.context._sourceVar !== undefined) ctx['_sourceVar'] = this.context._sourceVar;
      const result = await executor.eval(code, ctx);
      return result !== null && result !== undefined ? String(result) : '';
    } catch {
      return '';
    }
  }

  private async parseHeaderRule(header: string): Promise<Record<string, string>> {
    const trimmed = (header || '').trim();
    if (!trimmed) return {};
    let analyzed = trimmed;
    if (/^@?js:/i.test(analyzed) || /<js>[\s\S]+?<\/js>/i.test(analyzed)) {
      const directHeaders = this.parseHeaderJsLocally(analyzed);
      if (directHeaders) return directHeaders;
      analyzed = await this.analyzeJs(analyzed);
    }
    analyzed = await this.replaceTemplateVars(analyzed, undefined, false);
    return AnalyzeUrl.parseHeaderStr(analyzed);
  }

  private parseHeaderJsLocally(header: string): Record<string, string> | null {
    const code = header.trim()
      .replace(/^@?js:/i, '')
      .replace(/^<js>/i, '')
      .replace(/<\/js>$/i, '')
      .trim();
    const match = code.match(/^JSON\.stringify\(([\s\S]+)\)\s*;?$/);
    if (!match) return null;
    const obj = AnalyzeUrl.parseLooseObject(match[1]);
    if (!obj) return null;
    const headers: Record<string, string> = {};
    for (const key of Object.keys(obj)) {
      const raw = obj[key];
      if (raw === undefined || raw === null) continue;
      const text = String(raw);
      headers[key] = this.replaceSimpleContextVars(text);
    }
    return headers;
  }

  private replaceSimpleContextVars(text: string): string {
    if (text === 'baseUrl') return this.context.baseUrl || '';
    if (text === 'key') return this.context.key || '';
    if (text === 'page') return String(this.context.page || 1);
    return text
      .replace(/\bbaseUrl\b/g, this.context.baseUrl || '')
      .replace(/\bkey\b/g, this.context.key || '')
      .replace(/\bpage\b/g, String(this.context.page || 1));
  }

  // ──────────── 静态工具方法 ────────────

  static parseHeaderStr(header: string): Record<string, string> {
    if (!header) return {};
    try {
      return JSON.parse(header) as Record<string, string>;
    } catch {
      const loose = AnalyzeUrl.parseLooseObject(header);
      return loose ? (AnalyzeUrl.normalizeHeaders(loose) || {}) : {};
    }
  }

  /** 把 URL 中 query 段（? 之后）的非 ASCII 字符按 charset 重编码，跳过已 percent-encoded */
  static reencodeUrlQuery(url: string, charset?: string): string {
    if (!url) return url;
    const qIdx = url.indexOf('?');
    if (qIdx < 0) return url;
    const beforeQ = url.substring(0, qIdx + 1);
    const afterQ = url.substring(qIdx + 1);
    // 拆 fragment（#...）
    let frag = '';
    let q = afterQ;
    const hashIdx = afterQ.indexOf('#');
    if (hashIdx >= 0) {
      frag = afterQ.substring(hashIdx);
      q = afterQ.substring(0, hashIdx);
    }
    // 按 & 切对，再按 = 切 key/value，分别重编码
    const pairs = q.split('&');
    const out: string[] = [];
    for (const pair of pairs) {
      if (!pair) { out.push(pair); continue; }
      const eq = pair.indexOf('=');
      if (eq < 0) {
        out.push(AnalyzeUrl.encodeIfNeeded(pair, charset));
      } else {
        const k = pair.substring(0, eq);
        const v = pair.substring(eq + 1);
        out.push(AnalyzeUrl.encodeIfNeeded(k, charset) + '=' + AnalyzeUrl.encodeIfNeeded(v, charset));
      }
    }
    return beforeQ + out.join('&') + frag;
  }

  /** 把 form-urlencoded body 按 charset 重编码 */
  static reencodeFormBody(body: string, charset?: string): string {
    return AnalyzeUrl.reencodeUrlQuery('?' + body, charset).substring(1);
  }

  /** 含未编码非 ASCII 字符时按 charset percent-encode；保留已存在的 %XX */
  private static encodeIfNeeded(s: string, charset?: string): string {
    if (!s) return s;
    // 全是 ASCII（含 %XX）就不动
    let allAscii = true;
    for (let i = 0; i < s.length; i++) {
      if (s.charCodeAt(i) > 127) { allAscii = false; break; }
    }
    if (allAscii) return s;
    // 拼回去：把 %XX 段保留原样，其它按 charset 编码
    let out = '';
    let i = 0;
    while (i < s.length) {
      const ch = s.charAt(i);
      if (ch === '%' && i + 2 < s.length && /[0-9A-Fa-f]{2}/.test(s.substring(i + 1, i + 3))) {
        out += s.substring(i, i + 3);
        i += 3;
        continue;
      }
      // 收集到连续非 % 的子串，整段 encode
      let j = i;
      while (j < s.length) {
        const cj = s.charAt(j);
        if (cj === '%' && j + 2 < s.length && /[0-9A-Fa-f]{2}/.test(s.substring(j + 1, j + 3))) break;
        j++;
      }
      out += CharsetCodec.encodeUriForCharset(s.substring(i, j), charset);
      i = j;
    }
    return out;
  }

  /** 剥离 Legado 书源 URL 中的 ##分组标记（如 ##@曦灵） */
  static stripSourceGroup(url: string): string {
    const idx = url.indexOf('##');
    if (idx < 0) return url;
    const afterHash = url.substring(idx + 2);
    const slashPos = afterHash.indexOf('/');
    if (slashPos >= 0) {
      return url.substring(0, idx) + afterHash.substring(slashPos);
    }
    return url.substring(0, idx);
  }

  static resolveUrl(base: string, relative: string): string {
    if (!relative) return '';
    const trimmed = relative.replace(/[\r\n\t]/g, '').trim();
    if (!trimmed) return '';
    const split = AnalyzeUrl.splitUrlConfig(trimmed);
    if (split.url !== trimmed) {
      const resolved = AnalyzeUrl.resolveUrl(base, split.url);
      return resolved ? resolved + trimmed.substring(split.url.length) : '';
    }
    // Legado: javascript: 协议直接返回空（NetworkUtils.getAbsoluteURL）
    if (trimmed.toLowerCase().startsWith('javascript:')) return '';
    // data: URL 直接透传（代理书源的中间路由机制）
    if (trimmed.startsWith('data:')) return trimmed;
    const cleanRelative = AnalyzeUrl.stripSourceGroup(trimmed);
    if (cleanRelative.startsWith('http://') || cleanRelative.startsWith('https://') || cleanRelative.startsWith('//')) {
      return cleanRelative;
    }
    let cleanBase = AnalyzeUrl.stripSourceGroup(base.replace(/[\r\n\t]/g, '').trim());
    // 去掉 bookSourceUrl 里的 #注释/fragment（如 "https://www.fushucun.com#改进"），否则会被拼进 host
    const baseHashIdx = cleanBase.indexOf('#');
    if (baseHashIdx >= 0) cleanBase = cleanBase.substring(0, baseHashIdx);
    const match = cleanBase.match(/^(https?:\/\/[^/]+)/);
    if (!match) return cleanRelative;
    const origin = match[1];
    if (cleanRelative.startsWith('/')) {
      return origin + cleanRelative;
    }
    const basePath = cleanBase.substring(0, cleanBase.lastIndexOf('/') + 1);
    return basePath + cleanRelative;
  }

  /**
   * 静态版 splitConfig：拆分 Legado "URL,{配置JSON}" 语法
   * 供 JavaBridge.ajax 等外部调用
   */
  static splitUrlConfig(urlWithConfig: string): SplitUrlResult {
    const idx = AnalyzeUrl.findConfigIdx(urlWithConfig);
    if (idx <= 0) {
      const defaultConfig: UrlOption = { method: 'GET' };
      const result: SplitUrlResult = { url: urlWithConfig.trim(), config: defaultConfig };
      return result;
    }
    const baseUrl = urlWithConfig.substring(0, idx).trim();
    const configStr = urlWithConfig.substring(idx + 1).trim();
    const config = AnalyzeUrl.parseOptionConfig(configStr);
    if (config) {
      const result: SplitUrlResult = { url: baseUrl, config };
      return result;
    }
    const fallbackConfig: UrlOption = { method: 'GET' };
    const result: SplitUrlResult = { url: urlWithConfig.trim(), config: fallbackConfig };
    return result;
  }

  /** 静态版 findConfigStart，找到不在引号内的 ,{ 位置 */
  private static findConfigIdx(url: string): number {
    let inStr: string | null = null;
    for (let i = 0; i < url.length - 1; i++) {
      const c = url[i];
      if (inStr) {
        if (c === '\\' && i + 1 < url.length) {
          i++;
          continue;
        }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === '"' || c === "'") {
        inStr = c;
        continue;
      }
      if (c === ',') {
        let j = i + 1;
        while (j < url.length && /\s/.test(url[j])) j++;
        if (j < url.length && url[j] === '{') {
          return i;
        }
      }
    }
    return -1;
  }

  private static parseOptionConfig(configStr: string): UrlOption | null {
    let text = (configStr || '').trim()
      .replace(/[“”]/g, '"')
      .replace(/[‘’]/g, "'");
    if (!text) return null;
    try {
      const parsed = JSON.parse(text) as Record<string, Object>;
      return AnalyzeUrl.normalizeOption(parsed);
    } catch { /* try loose object literal */ }

    const loose = AnalyzeUrl.parseLooseObject(text);
    return loose ? AnalyzeUrl.normalizeOption(loose) : null;
  }

  private static normalizeOption(parsed: Record<string, Object>): UrlOption {
    const method = AnalyzeUrl.valueToString(parsed['method']) || 'GET';
    const option: UrlOption = {
      method: method.toUpperCase(),
      charset: AnalyzeUrl.valueToString(parsed['charset']) || undefined,
      headers: AnalyzeUrl.normalizeHeaders(parsed['headers']),
      body: AnalyzeUrl.normalizeBody(parsed['body']),
      webView: AnalyzeUrl.valueToBool(parsed['webView']),
      webJs: AnalyzeUrl.valueToString(parsed['webJs']) || undefined,
      retry: AnalyzeUrl.valueToNumber(parsed['retry']),
      type: AnalyzeUrl.valueToString(parsed['type']) || undefined,
      js: AnalyzeUrl.valueToString(parsed['js']) || undefined,
    };
    return option;
  }

  private static normalizeBody(value: Object | undefined): string | undefined {
    if (value === undefined || value === null) return undefined;
    if (typeof value === 'string') return value as string;
    return JSON.stringify(value);
  }

  private static normalizeHeaders(value: Object | undefined): Record<string, string> | undefined {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
    const input = value as Record<string, Object>;
    const headers: Record<string, string> = {};
    for (const k of Object.keys(input)) {
      const v = input[k];
      if (v !== undefined && v !== null) headers[k] = String(v);
    }
    return headers;
  }

  private static valueToString(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    return String(value);
  }

  private static valueToBool(value: Object | undefined): boolean | undefined {
    if (value === undefined || value === null) return undefined;
    if (typeof value === 'boolean') return value as boolean;
    const s = String(value).toLowerCase().trim();
    if (s === 'true') return true;
    if (s === 'false') return false;
    return undefined;
  }

  private static valueToNumber(value: Object | undefined): number {
    if (value === undefined || value === null) return 0;
    const n = Number(value);
    return Number.isNaN(n) ? 0 : n;
  }

  private static isJsonBody(body: string, headers?: Record<string, string>): boolean {
    const trimmed = (body || '').trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return true;
    if (!headers) return false;
    for (const k of Object.keys(headers)) {
      if (k.toLowerCase() === 'content-type') {
        return (headers[k] || '').toLowerCase().includes('application/json');
      }
    }
    return false;
  }

  private static hasHeader(headers: Record<string, string>, name: string): boolean {
    const lower = name.toLowerCase();
    for (const k of Object.keys(headers)) {
      if (k.toLowerCase() === lower) return true;
    }
    return false;
  }

  private static parseLooseObject(text: string): Record<string, Object> | null {
    const state: LooseParseState = { text: text.trim(), pos: 0 };
    try {
      AnalyzeUrl.skipWs(state);
      const value = AnalyzeUrl.readLooseValue(state);
      if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
      return value as Record<string, Object>;
    } catch {
      return null;
    }
  }

  private static readLooseValue(state: LooseParseState): Object {
    AnalyzeUrl.skipWs(state);
    const c = state.text[state.pos];
    if (c === '{') return AnalyzeUrl.readLooseObject(state) as Object;
    if (c === '[') return AnalyzeUrl.readLooseArray(state) as Object;
    if (c === '"' || c === "'") return AnalyzeUrl.readLooseString(state) as Object;
    return AnalyzeUrl.readLooseBare(state) as Object;
  }

  private static readLooseObject(state: LooseParseState): Record<string, Object> {
    const out: Record<string, Object> = {};
    state.pos++;
    while (state.pos < state.text.length) {
      AnalyzeUrl.skipWs(state);
      if (state.text[state.pos] === '}') {
        state.pos++;
        break;
      }
      const key = AnalyzeUrl.readLooseKey(state);
      AnalyzeUrl.skipWs(state);
      if (state.text[state.pos] !== ':') throw new Error('Expected colon');
      state.pos++;
      const value = AnalyzeUrl.readLooseValue(state);
      out[key] = value;
      AnalyzeUrl.skipWs(state);
      if (state.text[state.pos] === ',') {
        state.pos++;
        continue;
      }
      if (state.text[state.pos] === '}') {
        state.pos++;
        break;
      }
    }
    return out;
  }

  private static readLooseArray(state: LooseParseState): Object[] {
    const out: Object[] = [];
    state.pos++;
    while (state.pos < state.text.length) {
      AnalyzeUrl.skipWs(state);
      if (state.text[state.pos] === ']') {
        state.pos++;
        break;
      }
      out.push(AnalyzeUrl.readLooseValue(state));
      AnalyzeUrl.skipWs(state);
      if (state.text[state.pos] === ',') {
        state.pos++;
        continue;
      }
      if (state.text[state.pos] === ']') {
        state.pos++;
        break;
      }
    }
    return out;
  }

  private static readLooseKey(state: LooseParseState): string {
    AnalyzeUrl.skipWs(state);
    const c = state.text[state.pos];
    if (c === '"' || c === "'") return AnalyzeUrl.readLooseString(state);
    const start = state.pos;
    while (state.pos < state.text.length) {
      const ch = state.text[state.pos];
      if (ch === ':' || /\s/.test(ch)) break;
      state.pos++;
    }
    return state.text.substring(start, state.pos).trim();
  }

  private static readLooseString(state: LooseParseState): string {
    const quote = state.text[state.pos];
    state.pos++;
    let out = '';
    while (state.pos < state.text.length) {
      const c = state.text[state.pos];
      if (c === '\\' && state.pos + 1 < state.text.length) {
        const n = state.text[state.pos + 1];
        if (n === 'n') out += '\n';
        else if (n === 'r') out += '\r';
        else if (n === 't') out += '\t';
        else out += n;
        state.pos += 2;
        continue;
      }
      if (c === quote) {
        state.pos++;
        break;
      }
      out += c;
      state.pos++;
    }
    return out;
  }

  private static readLooseBare(state: LooseParseState): Object {
    const start = state.pos;
    while (state.pos < state.text.length) {
      const c = state.text[state.pos];
      if (c === ',' || c === '}' || c === ']') break;
      state.pos++;
    }
    const raw = state.text.substring(start, state.pos).trim();
    if (raw === 'true') return true as Object;
    if (raw === 'false') return false as Object;
    if (raw === 'null') return '';
    const n = Number(raw);
    if (raw.length > 0 && !Number.isNaN(n)) return n as Object;
    return raw as Object;
  }

  private static skipWs(state: LooseParseState): void {
    while (state.pos < state.text.length && /\s/.test(state.text[state.pos])) {
      state.pos++;
    }
  }

  static mergeHeaders(sourceHeader: string | undefined, extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = sourceHeader ? AnalyzeUrl.parseHeaderStr(sourceHeader) : {};
    if (extra) {
      const keys = Object.keys(extra);
      for (const k of keys) {
        headers[k] = extra[k];
      }
    }
    return headers;
  }
}
