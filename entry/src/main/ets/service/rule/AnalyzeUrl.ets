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
}

export class AnalyzeUrl {
  private ruleUrl: string;
  private context: TemplateContext;
  private sourceHeaders: Record<string, string>;

  constructor(ruleUrl: string, context: TemplateContext = {}, sourceHeader?: string, variables?: Record<string, string>) {
    this.ruleUrl = ruleUrl;
    this.context = context;
    this.sourceHeaders = sourceHeader ? AnalyzeUrl.parseHeaderStr(sourceHeader) : {};
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

    // 3.6 POST：body 是 a=1&b=2 形式时，按 charset 重编码 value
    let bodyOut = option.body;
    if ((option.method || 'GET').toUpperCase() === 'POST' && bodyOut && bodyOut.indexOf('=') > 0) {
      bodyOut = AnalyzeUrl.reencodeFormBody(bodyOut, charset);
    }

    // 4. 合并 headers
    const headers: Record<string, string> = {};
    const srcKeys = Object.keys(this.sourceHeaders);
    for (const sk of srcKeys) {
      headers[sk] = this.sourceHeaders[sk];
    }
    if (option.headers) {
      const keys = Object.keys(option.headers);
      for (const k of keys) {
        headers[k] = option.headers[k];
      }
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
    const configIdx = this.findConfigStart(url);
    let baseUrl: string;
    let option: UrlOption = { method: 'GET' };

    if (configIdx > 0) {
      baseUrl = url.substring(0, configIdx).trim();
      const configStr = url.substring(configIdx + 1).trim();
      try {
        const parsed = JSON.parse(configStr) as Record<string, Object>;
        option = {
          method: ((parsed['method'] as string) || 'GET').toUpperCase(),
          charset: parsed['charset'] as string,
          headers: parsed['headers'] as Record<string, string>,
          body: typeof parsed['body'] === 'string' ? parsed['body'] as string
            : parsed['body'] ? JSON.stringify(parsed['body']) : undefined,
          webView: parsed['webView'] as boolean,
          webJs: parsed['webJs'] as string,
          retry: (parsed['retry'] as number) || 0,
          type: parsed['type'] as string,
          js: parsed['js'] as string,
        };
      } catch {
        baseUrl = url;
      }
    } else {
      baseUrl = url.trim();
    }
    const result: UrlSplit = { baseUrl, option };
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

  private async replaceTemplateVars(url: string, charset?: string): Promise<string> {
    let result = url;
    const page = this.context.page || 1;
    const key = this.context.key || '';
    const enc = (s: string): string => CharsetCodec.encodeUriForCharset(s, charset);

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
    // 找到不在引号内的 ,{ 位置
    let inStr: string | null = null;
    for (let i = 0; i < url.length - 1; i++) {
      const c = url[i];
      if (inStr) {
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === '"' || c === "'") {
        inStr = c;
        continue;
      }
      if (c === ',' && url[i + 1] === '{') {
        return i;
      }
    }
    return -1;
  }

  private async evalJs(code: string): Promise<string> {
    try {
      const executor = getJSExecutor();
      const javaBridge = getJavaBridge();
      const ctx: Record<string, Object> = {};
      ctx['java'] = javaBridge;
      if (this.context.key !== undefined) ctx['key'] = this.context.key;
      if (this.context.page !== undefined) ctx['page'] = this.context.page;
      if (this.context.baseUrl !== undefined) ctx['baseUrl'] = this.context.baseUrl;
      if (this.context.result !== undefined) ctx['result'] = this.context.result;
      if (this.context.book !== undefined) ctx['book'] = this.context.book;
      if (this.context.chapter !== undefined) ctx['chapter'] = this.context.chapter;
      if (this.context.speakText !== undefined) ctx['speakText'] = this.context.speakText;
      const result = await executor.eval(code, ctx);
      return result !== null && result !== undefined ? String(result) : '';
    } catch {
      return '';
    }
  }

  // ──────────── 静态工具方法 ────────────

  static parseHeaderStr(header: string): Record<string, string> {
    if (!header) return {};
    try {
      return JSON.parse(header) as Record<string, string>;
    } catch {
      return {};
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
    // Legado: javascript: 协议直接返回空（NetworkUtils.getAbsoluteURL）
    if (trimmed.toLowerCase().startsWith('javascript:')) return '';
    const cleanRelative = AnalyzeUrl.stripSourceGroup(trimmed);
    if (cleanRelative.startsWith('http://') || cleanRelative.startsWith('https://') || cleanRelative.startsWith('//')) {
      return cleanRelative;
    }
    const cleanBase = AnalyzeUrl.stripSourceGroup(base.replace(/[\r\n\t]/g, '').trim());
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
    try {
      // 尝试标准 JSON 解析，失败则修复非标准格式（Legado 允许无引号 key + 中文引号）
      let jsonStr = configStr;
      // 先把中文引号 U+201C/U+201D 替换成英文引号
      jsonStr = jsonStr.replace(/[“”]/g, '"');
      // 中文单引号 U+2018/U+2019 也替换
      jsonStr = jsonStr.replace(/[‘’]/g, "'");
      try {
        JSON.parse(jsonStr);
      } catch {
        // 给无引号的 key 加双引号: {webView:"true"} → {"webView":"true"}
        jsonStr = jsonStr.replace(/([{,]\s*)([a-zA-Z_]\w*)\s*:/g, '$1"$2":');
      }
      const parsed = JSON.parse(jsonStr) as Record<string, Object>;
      const config: UrlOption = {
        method: ((parsed['method'] as string) || 'GET').toUpperCase(),
        charset: parsed['charset'] as string,
        headers: parsed['headers'] as Record<string, string>,
        body: typeof parsed['body'] === 'string' ? parsed['body'] as string
          : parsed['body'] ? JSON.stringify(parsed['body']) : undefined,
        webView: parsed['webView'] as boolean,
        webJs: parsed['webJs'] as string,
        retry: (parsed['retry'] as number) || 0,
        type: parsed['type'] as string,
        js: parsed['js'] as string,
      };
      const result: SplitUrlResult = { url: baseUrl, config };
      return result;
    } catch {
      const fallbackConfig: UrlOption = { method: 'GET' };
      const result: SplitUrlResult = { url: urlWithConfig.trim(), config: fallbackConfig };
      return result;
    }
  }

  /** 静态版 findConfigStart，找到不在引号内的 ,{ 位置 */
  private static findConfigIdx(url: string): number {
    let inStr: string | null = null;
    for (let i = 0; i < url.length - 1; i++) {
      const c = url[i];
      if (inStr) {
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === '"' || c === "'") {
        inStr = c;
        continue;
      }
      if (c === ',' && url[i + 1] === '{') {
        return i;
      }
    }
    return -1;
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
