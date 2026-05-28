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
    let url = this.ruleUrl;

    // 1. 执行 @js: 和 <js>...</js> 块
    url = await this.analyzeJs(url);

    // 2. 替换模板变量 {{key}}, {{page}}, <page1,page2>
    url = await this.replaceTemplateVars(url);

    // 3. 解析 URL 配置（,{...}）
    return this.parseUrlWithOptions(url);
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

  private async replaceTemplateVars(url: string): Promise<string> {
    let result = url;
    const page = this.context.page || 1;
    const key = this.context.key || '';

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
    result = result.replace(/\{\{key\}\}/g, encodeURIComponent(key));
    result = result.replace(/\{\{keyword\}\}/g, encodeURIComponent(key));
    result = result.replace(/\{\{searchKey\}\}/g, encodeURIComponent(key));

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

  private parseUrlWithOptions(url: string): AnalyzedUrl {
    // 查找 ,{ 配置部分
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

    // 合并 headers
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

    // Legado 书源 URL 中 ## 后跟源分组标记（如 ##@曦灵），需要剥离
    baseUrl = AnalyzeUrl.stripSourceGroup(baseUrl);

    return {
      url: baseUrl,
      method: option.method || 'GET',
      body: option.body,
      charset: option.charset,
      headers,
      webView: option.webView,
      webJs: option.webJs,
      retry: option.retry || 0,
    };
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
