/**
 * JSExecutor - JavaScript 执行器
 *
 * 策略：
 * 1. 简单表达式本地求值（不依赖 eval，手写解释器处理常见书源模式）
 * 2. 复杂 JS 通过 HTTP 代理执行（Node.js 服务）
 * 3. 代理不可用时降级为本地模式（尽力而为）
 *
 * 本地可处理的模式：
 *  - 字符串拼接：'a' + 'b'
 *  - 属性访问：result.split('/')[2]
 *  - 简单方法调用：result.replace('a','b'), result.trim()
 *  - 三元表达式：a ? b : c
 *  - 变量引用：baseUrl, result, key, page
 *  - 模板字面量：`${var}/path`
 *  - DOM 操作（书源 JS 规则）：document.querySelector/querySelectorAll/cloneNode/innerText/remove
 */

import { HttpClient } from '../http/HttpClient';
import { JsvmEngine } from './JsvmEngine';
import { SimpleCSSSelector, HTMLElement } from '../rule/SimpleCSSSelector';
import { getJavaBridge } from '../rule/JavaBridge';
import { getCookieManager } from '../rule/CookieManager';
import { getSourceContext } from '../rule/SourceContext';
import { getJsoup } from '../rule/JsoupBridge';
import { getWebViewJSEngine } from './WebViewJSEngine';
import { BuiltInSourceRegistry } from '../builtin/BuiltInSourceRegistry';

export interface JSExecutorConfig {
  host?: string;
  port?: number;
  timeout?: number;
}

interface JSEvalRequest {
  code: string;
  context?: Record<string, Object>;
  timeout?: number;
}

interface JSEvalResponse {
  success: boolean;
  result?: Object;
  error?: string;
}

interface ScriptStmtResult {
  value: Object | undefined;
  returned: boolean;
}

interface IfStmtMatch {
  cond: string;
  thenStmt: string;
  elseStmt?: string;
}

interface BlockResult {
  bodyLines: string[];
  endIndex: number;
}

interface IfBlockResult {
  result: ScriptStmtResult;
  endIndex: number;
}

export class JSExecutor {
  private baseUrl: string;
  private timeout: number;
  private proxyAvailable: boolean | null = null;

  constructor(config: JSExecutorConfig = {}) {
    const host = config.host || 'localhost';
    const port = config.port || 3737;
    this.baseUrl = `http://${host}:${port}`;
    this.timeout = config.timeout || 5000;
  }

  async eval(code: string, context: Record<string, Object> = {}): Promise<Object | null> {
    if (!code || !code.trim()) return null;

    // jsLib 注入：光遇聚合等重度书源的 jsLib 函数通过 this.source / this.java 互相调用，
    // 必须用 .call() 绑定 this 到共享上下文对象
    const jsLib = context['_jsLib'] as string;
    const hasJsLib = !!(jsLib && jsLib.trim());

    // 通用 JSVM 引擎优先：真 JS 引擎(闭包/箭头/解构/eval) + 同步 java.ajax(net_http)
    // 在 code 被改写前用原始 code + 原始 jsLib；失败/不支持(undefined)或空结果则回落现有引擎
    const jsvmNeedsDOM = code.includes('document.');
    const jsvmNeedsJava = code.includes('java.');
    if (!jsvmNeedsDOM && (jsvmNeedsJava || hasJsLib)) {
      try {
        const jsvmCode = hasJsLib ? (jsLib + '\n' + code) : code;
        const jr = await JsvmEngine.eval(jsvmCode, context);
        if (jr !== undefined && jr !== null && jr !== '') return jr;
      } catch (e) {
        console.warn(`[JSExecutor] JSVM path failed, fallback: ${e}`);
      }
    }

    if (hasJsLib) {
      // 不使用 IIFE 包装！
      // 原因：patchJsLibThis 将 function getVariable() {} 转为 this.getVariable = function() {}
      //       并注入 var getVariable = this.getVariable; 局部别名
      //       如果用 IIFE 包装，这些局部别名无法被 IIFE 内部的其他函数访问
      // 策略：直接拼接 jsLib + code，让 jsLib 函数作为局部变量可用
      const patchedJsLib = JSExecutor.patchJsLibThis(jsLib);
      code = patchedJsLib + '\n' + code;
    } else {
      // 解开 IIFE 包装：(function(){...})()  →  函数体
      code = this.unwrapIIFE(code);
    }

    // 检测是否需要 java 桥（书源 JS 规则常用 java.connect/ajax/log）
    const needsJava = code.includes('java.connect') ||
                      code.includes('java.ajax') ||
                      code.includes('java.log') ||
                      code.includes('java.get') ||
                      code.includes('java.put') ||
                      code.includes('java.webView') ||
                      code.includes('java.builtin');

    // 检测是否需要 DOM shim（书源 JS 规则常用 document.querySelector）
    const needsDOM = code.includes('document.querySelector') ||
                     code.includes('document.querySelectorAll') ||
                     code.includes('.cloneNode') ||
                     code.includes('.innerText') ||
                     code.includes('.remove()');

    if (needsDOM) {
      const shimResult = this.tryDOMShim(code, context);
      if (shimResult !== undefined) return shimResult;
    }

    // jsLib 代码（含箭头函数、解构赋值、复杂函数声明等）无法被本地求值器正确处理，
    // 直接使用 WebView JS 引擎（完整 ES6+ 支持）
    if (hasJsLib) {
      try {
        const webViewEngine = getWebViewJSEngine();
        const result = await webViewEngine.eval(code, context);
        return result;
      } catch (e) {
        console.error(`[JSExecutor] jsLib WebView eval failed: ${e}`);
        return null;
      }
    }

    // 优先：本地脚本求值（async，原生支持 await java.ajax / java.connect 与多行赋值）
    // 这是 Legado 书源最常见的"拼 URL → ajax → 取新页面"模式
    if (needsJava && (code.includes('java.ajax') || code.includes('java.connect') || code.includes('java.builtin'))) {
      const asyncResult = await this.tryAsyncScript(code.trim(), context);
      if (asyncResult !== undefined) return asyncResult;
    }

    // 如果需要 java 桥且有 HTTP 代理，使用代理（支持其它复杂 java 方法）
    if (needsJava && this.proxyAvailable !== false) {
      try {
        const javaBridge = getJavaBridge();
        const enrichedContext: Record<string, Object> = {};
        for (const k of Object.keys(context)) enrichedContext[k] = context[k];
        // 注入 java 桥变量到上下文
        enrichedContext['_javaVars'] = javaBridge.getVariables();
        const result = await this.evalViaProxy(code, enrichedContext);
        this.proxyAvailable = true;
        return result;
      } catch {
        this.proxyAvailable = false;
      }
    }

    // 尝试本地求值（覆盖大部分书源常见模式）
    const localResult = this.tryLocalEval(code.trim(), context);
    if (localResult !== undefined) {
      return localResult;
    }

    // 尝试 HTTP 代理
    if (this.proxyAvailable !== false) {
      try {
        const result = await this.evalViaProxy(code, context);
        this.proxyAvailable = true;
        return result;
      } catch {
        this.proxyAvailable = false;
      }
    }

    // 降级：尝试更宽松的本地解析
    const relaxedResult = this.tryLocalEvalRelaxed(code.trim(), context);
    if (relaxedResult !== null) {
      return relaxedResult;
    }

    // 最终降级：使用 WebView JS 引擎（完整 ES6+ 支持）
    try {
      const webViewEngine = getWebViewJSEngine();
      const result = await webViewEngine.eval(code, context);
      return result;
    } catch {
      return null;
    }
  }

  /**
   * 解开 IIFE 包装：(function(){...})() 或 (()=>{...})()
   * 返回函数体（内部的多行语句），或原 code（如果不是 IIFE）
   */
  /**
   * 修正 jsLib 中的函数声明和 this 引用
   *
   * 光遇聚合等书源的 jsLib 有两个关键问题：
   * 1. 函数互相调用用 this.BaseUrl() / this.getVariable()，但函数是局部声明不是 this 的属性
   * 2. 函数内部用 const { source } = this 访问上下文
   *
   * 修复策略：
   * - 将 function xxx() {} 声明转为 this.xxx = function() {}（成为 this 的属性）
   * - 将 const { x } = this; 转为局部变量引用
   * - this.source/java/cookie/cache 引用保持不变（由 .call(__this) 绑定）
   */
  static patchJsLibThis(jsLib: string): string {
    let patched = jsLib;

    // 1. 将顶层函数声明转为 this 属性赋值
    //    function getVariable(k) {  →  this.getVariable = function(k) {
    //    function BaseUrl() {  →  this.BaseUrl = function() {
    //    function request(url, method, ...) {  →  this.request = function(url, method, ...) {
    // 同时收集所有被转换的函数名，后续注入局部变量别名
    const patchedNames: string[] = [];
    patched = patched.replace(
      /^function\s+(\w+)\s*\(/gm,
      (_match: string, name: string): string => {
        patchedNames.push(name);
        return 'this.' + name + ' = function(';
      }
    );

    // 2. 将 const { source } = this; / const { source, java } = this; 转为局部变量
    //    因为 this.source 已经由 .call(__this) 提供
    patched = patched.replace(
      /const\s*\{([^}]+)\}\s*=\s*this\s*;/g,
      (_match: string, names: string): string => {
        const parts = names.split(',').map((n: string) => n.trim()).filter((n: string) => n.length > 0);
        return parts.map((name: string) => `var ${name} = this.${name};`).join('\n');
      }
    );

    // 3. 在 jsLib 开头注入局部变量别名
    //    问题：function getVariable(k) {} 被转为 this.getVariable = function(k) {}
    //    但代码中用 getVariable(...)（不带 this.）调用，需要局部变量引用
    //    解决：在 jsLib 开头注入 var getVariable = this.getVariable;
    if (patchedNames.length > 0) {
      const aliases = patchedNames.map((name: string) =>
        `var ${name} = this.${name};`
      ).join('\n');
      patched = aliases + '\n' + patched;
    }

    return patched;
  }

  private unwrapIIFE(code: string): string {
    const trimmed = code.trim();
    // (function(){ ... })()  / (function () { ... })()
    let m = trimmed.match(/^\(\s*function\s*\([^)]*\)\s*\{([\s\S]*)\}\s*\)\s*\(\s*\)\s*;?\s*$/);
    if (m) return m[1].trim();
    // (() => { ... })()
    m = trimmed.match(/^\(\s*\([^)]*\)\s*=>\s*\{([\s\S]*)\}\s*\)\s*\(\s*\)\s*;?\s*$/);
    if (m) return m[1].trim();
    return code;
  }

  private async evalViaProxy(code: string, context: Record<string, Object>): Promise<Object | null> {
    const request: JSEvalRequest = { code, context, timeout: this.timeout };
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    const responseBody = await HttpClient.post(
      `${this.baseUrl}/eval`, request, headers,
    );
    const response: JSEvalResponse = JSON.parse(responseBody) as JSEvalResponse;
    if (!response.success) {
      throw new Error(response.error || 'JS 执行失败');
    }
    return response.result !== undefined ? response.result : null;
  }

  /**
   * 本地求值：处理书源中最常见的 JS 模式
   * 返回 undefined 表示无法本地处理
   */
  private tryLocalEval(code: string, ctx: Record<string, Object>): Object | undefined {
    // 纯字符串字面量：必须首尾同引号，且中间无未转义同引号
    // 否则像 "http://..." + result.split('/')[2]+'/true/1/200' 会被误判为字面量
    if (/^"(?:[^"\\]|\\.)*"$/.test(code) || /^'(?:[^'\\]|\\.)*'$/.test(code)) {
      return code.substring(1, code.length - 1).replace(/\\(.)/g, '$1');
    }

    // 纯数字
    if (/^-?\d+(\.\d+)?$/.test(code)) {
      return parseFloat(code);
    }

    // 纯变量引用
    if (/^[a-zA-Z_]\w*$/.test(code)) {
      return ctx[code] !== undefined ? ctx[code] : undefined;
    }

    // result / baseUrl / key / page 等直接引用
    if (code === 'result') return ctx['result'];
    if (code === 'baseUrl') return ctx['baseUrl'];
    if (code === 'key') return ctx['key'];
    if (code === 'page') return ctx['page'];
    if (code === 'src') return ctx['src'];

    // java.log(msg) - 简单日志输出
    const javaLogMatch = code.match(/^java\.log\(['"](.+)['"]\)$/);
    if (javaLogMatch) {
      const javaBridge = getJavaBridge();
      javaBridge.log(javaLogMatch[1]);
      return '';
    }

    // java.put(key, value) - 存储变量
    const javaPutMatch = code.match(/^java\.put\(['"](.+?)['"]\s*,\s*['"](.+?)['"]\)$/);
    if (javaPutMatch) {
      const javaBridge = getJavaBridge();
      javaBridge.put(javaPutMatch[1], javaPutMatch[2]);
      return '';
    }

    // java.get(key) - 获取变量
    const javaGetMatch = code.match(/^java\.get\(['"](.+)['"]\)$/);
    if (javaGetMatch) {
      const javaBridge = getJavaBridge();
      return javaBridge.get(javaGetMatch[1]);
    }

    // source.key / source.name / source.type - 书源信息访问
    if (code === 'source.key') {
      const sourceContext = getSourceContext();
      return sourceContext.key;
    }
    if (code === 'source.name') {
      const sourceContext = getSourceContext();
      return sourceContext.name;
    }
    if (code === 'source.type') {
      const sourceContext = getSourceContext();
      return sourceContext.type;
    }

    // 内置：Date.now() / new Date().getTime() / Math.random()
    if (code === 'Date.now()' || code === 'new Date().getTime()' || code === 'new Date().valueOf()') {
      return Date.now();
    }
    if (code === 'Math.random()') {
      return Math.random();
    }
    // Math.floor(...) / Math.ceil(...) / Math.round(...)
    const mathMatch = code.match(/^Math\.(floor|ceil|round|abs)\((.+)\)$/);
    if (mathMatch) {
      const inner = this.tryLocalEval(mathMatch[2], ctx);
      if (inner === undefined) return undefined;
      const n = Number(inner);
      if (Number.isNaN(n)) return 0;
      switch (mathMatch[1]) {
        case 'floor': return Math.floor(n);
        case 'ceil': return Math.ceil(n);
        case 'round': return Math.round(n);
        case 'abs': return Math.abs(n);
      }
    }
    // JSON.parse('...') / JSON.parse(varName)
    const jsonParseMatch = code.match(/^JSON\.parse\((.+)\)$/);
    if (jsonParseMatch) {
      const inner = this.tryLocalEval(jsonParseMatch[1], ctx);
      if (inner === undefined) return undefined;
      try {
        return JSON.parse(String(inner)) as Object;
      } catch { return undefined; }
    }
    // JSON.stringify(varName)
    const jsonStrMatch = code.match(/^JSON\.stringify\((.+)\)$/);
    if (jsonStrMatch) {
      const inner = this.tryLocalEval(jsonStrMatch[1], ctx);
      if (inner === undefined) return undefined;
      try {
        return JSON.stringify(inner);
      } catch { return undefined; }
    }
    // java.base64Encode/Decode/randomUUID/timeFormat — 通过 javaBridge
    const javaB64Enc = code.match(/^java\.base64Encode(?:r)?\((.+)\)$/);
    if (javaB64Enc) {
      const inner = this.tryLocalEval(javaB64Enc[1], ctx);
      if (inner === undefined) return undefined;
      return getJavaBridge().base64Encode(String(inner));
    }
    const javaB64Dec = code.match(/^java\.base64Decode(?:r)?\((.+)\)$/);
    if (javaB64Dec) {
      const inner = this.tryLocalEval(javaB64Dec[1], ctx);
      if (inner === undefined) return undefined;
      return getJavaBridge().base64Decode(String(inner));
    }
    if (code === 'java.randomUUID()') {
      return getJavaBridge().randomUUID();
    }
    const javaTime = code.match(/^java\.timeFormat\((.+)\)$/);
    if (javaTime) {
      const inner = this.tryLocalEval(javaTime[1], ctx);
      if (inner === undefined) return undefined;
      return getJavaBridge().timeFormat(Number(inner));
    }

    // cookie.removeCookie(url) - 移除 Cookie
    const cookieRemoveMatch = code.match(/^cookie\.removeCookie\(['"](.+)['"]\)$/);
    if (cookieRemoveMatch) {
      const cookieManager = getCookieManager();
      cookieManager.removeCookie(cookieRemoveMatch[1]);
      return '';
    }

    // cookie.getCookie(url) - 获取 Cookie
    const cookieGetMatch = code.match(/^cookie\.getCookie\(['"](.+)['"]\)$/);
    if (cookieGetMatch) {
      const cookieManager = getCookieManager();
      return cookieManager.getCookie(cookieGetMatch[1]);
    }

    // java.getCookie(url) - 获取 Cookie（jsLib 兼容）
    const javaCookieGetMatch = code.match(/^java\.getCookie\(['"](.+)['"]\)$/);
    if (javaCookieGetMatch) {
      return getJavaBridge().getCookie(javaCookieGetMatch[1]);
    }

    // cookie.setCookie(url, value) - 设置 Cookie
    const cookieSetMatch = code.match(/^cookie\.setCookie\(['"](.+?)['"]\s*,\s*['"](.+?)['"]\)$/);
    if (cookieSetMatch) {
      const cookieManager = getCookieManager();
      cookieManager.setCookie(cookieSetMatch[1], cookieSetMatch[2]);
      return '';
    }

    // cookie.replaceCookie(url, value) - 合并 Cookie
    const cookieReplaceMatch = code.match(/^cookie\.replaceCookie\(['"](.+?)['"]\s*,\s*['"](.+?)['"]\)$/);
    if (cookieReplaceMatch) {
      const cookieManager = getCookieManager();
      cookieManager.replaceCookie(cookieReplaceMatch[1], cookieReplaceMatch[2]);
      return '';
    }

    // cookie.cookieToMap(cookie) - Cookie 字符串转 Map 对象
    const cookieToMapMatch = code.match(/^cookie\.cookieToMap\((.+)\)$/);
    if (cookieToMapMatch) {
      const inner = this.tryLocalEval(cookieToMapMatch[1], ctx);
      if (inner === undefined) return undefined;
      const map: Record<string, string> = {};
      const parts = String(inner).split(';');
      for (const part of parts) {
        const eq = part.indexOf('=');
        if (eq > 0) map[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
      }
      return map as Object;
    }

    // cookie.mapToCookie(map) - Map 对象转 Cookie 字符串
    const mapToCookieMatch = code.match(/^cookie\.mapToCookie\((.+)\)$/);
    if (mapToCookieMatch) {
      const inner = this.tryLocalEval(mapToCookieMatch[1], ctx);
      if (inner === undefined) return undefined;
      if (typeof inner === 'object' && inner !== null) {
        const map = inner as Record<string, string>;
        return Object.keys(map).map((k) => `${k}=${map[k]}`).join('; ');
      }
      return String(inner);
    }

    // java.getStrResponse() - 获取最后一次请求的响应
    if (code === 'java.getStrResponse()') {
      return getJavaBridge().getStrResponse();
    }

    // java.toast(msg) / java.longToast(msg)
    const toastMatch = code.match(/^java\.(toast|longToast)\((.+)\)$/);
    if (toastMatch) {
      const inner = this.tryLocalEval(toastMatch[2], ctx);
      if (inner !== undefined) {
        const javaBridge = getJavaBridge();
        if (toastMatch[1] === 'longToast') {
          javaBridge.longToast(String(inner));
        } else {
          javaBridge.toast(String(inner));
        }
      }
      return '';
    }

    // java.hexDecodeToString(hex) — 兼容 base64 输入
    const hexDecodeMatch = code.match(/^java\.hexDecodeToString\((.+)\)$/);
    if (hexDecodeMatch) {
      const inner = this.tryLocalEval(hexDecodeMatch[1], ctx);
      if (inner === undefined) return undefined;
      return getJavaBridge().hexDecodeToString(String(inner));
    }

    // java.androidId() / java.deviceID()
    if (code === 'java.androidId()' || code === 'java.deviceID()') {
      return getJavaBridge().androidId();
    }

    // java.getWebViewUA()
    if (code === 'java.getWebViewUA()') {
      return getJavaBridge().getWebViewUA();
    }

    // java.getAppVariant()
    if (code === 'java.getAppVariant()') {
      return getJavaBridge().getAppVariant();
    }

    // java.md5(arg) / java.md5Encode(arg) / java.md5Encode16(arg)
    const md5Match = code.match(/^java\.(md5|md5Encode|md5Encode16)\((.+)\)$/);
    if (md5Match) {
      const inner = this.tryLocalEval(md5Match[2], ctx);
      if (inner === undefined) return undefined;
      const jb = getJavaBridge();
      return md5Match[1] === 'md5Encode16' ? jb.md5Encode16(String(inner)) : jb.md5(String(inner));
    }

    // java.encodeURI(arg)
    const encodeURIMatch = code.match(/^java\.encodeURI\((.+)\)$/);
    if (encodeURIMatch) {
      const inner = this.tryLocalEval(encodeURIMatch[1], ctx);
      if (inner === undefined) return undefined;
      return getJavaBridge().encodeURI(String(inner));
    }

    // java.HMacHex(data, algo, key)
    const hmacMatch = code.match(/^java\.(HMacHex|HMacBase64)\((.+)\)$/);
    if (hmacMatch) {
      const args = this.parseArgs(hmacMatch[2]);
      if (args.length < 3) return undefined;
      const jb = getJavaBridge();
      return hmacMatch[1] === 'HMacHex'
        ? jb.HMacHex(String(args[0]), String(args[1]), String(args[2]))
        : jb.HMacBase64(String(args[0]), String(args[1]), String(args[2]));
    }

    // java.digestHex(data, algo)
    const digestMatch = code.match(/^java\.(digestHex|digestBase64Str)\((.+)\)$/);
    if (digestMatch) {
      const args = this.parseArgs(digestMatch[2]);
      if (args.length < 2) return undefined;
      const jb = getJavaBridge();
      return digestMatch[1] === 'digestHex'
        ? jb.digestHex(String(args[0]), String(args[1]))
        : jb.digestBase64Str(String(args[0]), String(args[1]));
    }

    // java.startBrowser(url, title) / java.startBrowserDp(url, title)
    const startBrowserMatch = code.match(/^java\.startBrowser(?:Dp)?\((.+)\)$/);
    if (startBrowserMatch) {
      const args = this.parseArgs(startBrowserMatch[1]);
      const javaBridge = getJavaBridge();
      javaBridge.startBrowser(String(args[0] || ''), args.length > 1 ? String(args[1]) : '');
      return '';
    }

    // Jsoup.parse(var).select('selector').text/attr/html()  / org.jsoup.Jsoup.parse(...)
    const jsoupMatch = code.match(/^(?:org\.jsoup\.)?Jsoup\.parse\((\w+(?:\.body\(\))?)\)\.select\(['"](.+?)['"]\)\.(text|attr|html|outerHtml)\(([^)]*)\)$/);
    if (jsoupMatch) {
      const varExpr = jsoupMatch[1].replace(/\.body\(\)$/, '');
      const htmlVar = ctx[varExpr];
      if (htmlVar && typeof htmlVar === 'string') {
        const jsoup = getJsoup();
        const doc = jsoup.parse(htmlVar as string);
        const elements = doc.select(jsoupMatch[2]);
        if (jsoupMatch[3] === 'text') {
          return elements.text();
        } else if (jsoupMatch[3] === 'attr') {
          const attrName = jsoupMatch[4].replace(/['"]/g, '');
          return elements.attr(attrName);
        } else if (jsoupMatch[3] === 'html') {
          return elements.html();
        } else if (jsoupMatch[3] === 'outerHtml') {
          const first = elements.first();
          return first ? first.outerHtml() : '';
        }
      }
      return '';
    }

    // 字符串拼接：'a' + variable + 'b'
    const concatResult = this.tryEvalConcat(code, ctx);
    if (concatResult !== undefined) return concatResult;

    // result.xxx 属性链
    const propResult = this.tryEvalPropertyChain(code, ctx);
    if (propResult !== undefined) return propResult;

    // 简单赋值后返回：var x = expr; x
    const assignResult = this.tryEvalAssignment(code, ctx);
    if (assignResult !== undefined) return assignResult;

    // 单行裸赋值：result = result.replace(...)（Legado <js> 改写 result 的常见写法，
    // 赋值表达式求值为被赋的值）。排除 == / >= / <= / != 等比较。
    if (!code.includes('\n') && !code.includes(';')) {
      const bareAssign = code.match(/^(\w+)\s*=(?!=)\s*(.+)$/);
      if (bareAssign && !/[<>!]$/.test(bareAssign[1])) {
        const rhs = this.tryLocalEval(bareAssign[2].trim(), ctx);
        if (rhs !== undefined) return rhs;
      }
    }

    return undefined;
  }

  /**
   * Async 脚本求值：处理 Legado 书源中含 java.ajax / java.connect 的命令式 JS。
   *
   * 支持的语法：
   *  - var/let/const X = expr;     声明赋值
   *  - X = expr;                    重新赋值（含已有变量如 result）
   *  - if (cond) stmt; [else stmt;] 单语句条件
   *  - return expr;                 显式返回
   *  - java.ajax(arg) / java.connect(arg) / java.get(arg) / java.put(k,v) / java.log(arg)
   *  - 表达式：字符串字面量、数字、变量引用、a + b 拼接、obj.prop、obj.method(...)
   *  - 最后一行作为返回值
   *
   * 不支持的复杂语法（return undefined 让上层降级）：
   *  - for/while、try/catch、对象/数组字面量、箭头函数、嵌套块
   */
  private async tryAsyncScript(code: string, ctx: Record<string, Object>): Promise<Object | undefined> {
    // jsLib 包装的 IIFE 代码不能被语句拆分执行，跳过让上层降级到 proxy / WebView
    // jsLib 中的函数声明、箭头函数、解构赋值等复杂语法无法被 splitStatements 正确拆分
    if (code.includes('.call(') && code.includes('(function')) {
      return undefined;
    }
    const lines = this.splitStatements(code);
    if (lines.length === 0) return undefined;

    const localVars: Record<string, Object> = {};
    for (const k of Object.keys(ctx)) localVars[k] = ctx[k];

    const result = await this.runStatements(lines, localVars);
    if (result.returned) return result.value;
    return result.value;
  }

  /** 顺序执行语句序列，返回 { value, returned }。returned=true 表示遇到 return。 */
  private async runStatements(
    lines: string[], localVars: Record<string, Object>
  ): Promise<ScriptStmtResult> {
    let lastValue: Object | undefined = undefined;
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      // 显式 return
      if (/^return\b/.test(line)) {
        const expr = line.replace(/^return\s*/, '').trim() || '""';
        const v = await this.evalExprAsync(expr, localVars);
        const r: ScriptStmtResult = { value: v, returned: true };
        return r;
      }
      // for (init; cond; update) { body }
      const forMatch = line.match(/^for\s*\((.+);(.+);(.+)\)\s*\{?$/);
      if (forMatch) {
        // 执行 init
        const initStmt = forMatch[1].trim();
        if (initStmt) await this.runStatements([initStmt], localVars);
        // 循环
        const condExpr = forMatch[2].trim();
        const updateExpr = forMatch[3].trim();
        // 收集循环体
        const body = this.collectBlock(lines, i);
        const bodyLines = body.bodyLines;
        i = body.endIndex;
        // 执行循环
        let maxIter = 10000; // 防死循环
        while (maxIter-- > 0) {
          const condVal = await this.evalExprAsync(condExpr, localVars);
          if (!condVal || condVal === '0' || condVal === 'false') break;
          const sub = await this.runStatements(bodyLines, localVars);
          if (sub.returned) return sub;
          if (sub.value !== undefined) lastValue = sub.value;
          // 执行 update
          await this.runStatements([updateExpr], localVars);
        }
        continue;
      }
      // while (cond) { body }
      const whileMatch = line.match(/^while\s*\((.+)\)\s*\{?$/);
      if (whileMatch) {
        const condExpr = whileMatch[1].trim();
        const body = this.collectBlock(lines, i);
        const bodyLines = body.bodyLines;
        i = body.endIndex;
        let maxIter = 10000;
        while (maxIter-- > 0) {
          const condVal = await this.evalExprAsync(condExpr, localVars);
          if (!condVal || condVal === '0' || condVal === 'false') break;
          const sub = await this.runStatements(bodyLines, localVars);
          if (sub.returned) return sub;
          if (sub.value !== undefined) lastValue = sub.value;
        }
        continue;
      }
      // try { body } catch (e) { handler } [finally { cleanup }]
      if (/^try\s*\{?$/.test(line)) {
        const tryBody = this.collectBlock(lines, i);
        i = tryBody.endIndex;
        let catchBody: string[] | null = null;
        let catchVar = 'e';
        let finallyBody: string[] | null = null;
        // catch
        if (i < lines.length && /^catch/.test(lines[i])) {
          const catchMatch = lines[i].match(/^catch\s*(?:\((\w+)\))?\s*\{?$/);
          if (catchMatch) catchVar = catchMatch[1] || 'e';
          const cb = this.collectBlock(lines, i);
          catchBody = cb.bodyLines;
          i = cb.endIndex;
        }
        // finally
        if (i < lines.length && /^finally\s*\{?$/.test(lines[i])) {
          const fb = this.collectBlock(lines, i);
          finallyBody = fb.bodyLines;
          i = fb.endIndex;
        }
        // 执行
        try {
          const sub = await this.runStatements(tryBody.bodyLines, localVars);
          if (sub.returned) return sub;
          if (sub.value !== undefined) lastValue = sub.value;
        } catch (err) {
          if (catchBody) {
            localVars[catchVar] = err instanceof Error ? err.message : String(err);
            const sub = await this.runStatements(catchBody, localVars);
            if (sub.returned) return sub;
            if (sub.value !== undefined) lastValue = sub.value;
          }
        } finally {
          if (finallyBody) {
            const sub = await this.runStatements(finallyBody, localVars);
            if (sub.returned) return sub;
            if (sub.value !== undefined) lastValue = sub.value;
          }
        }
        continue;
      }
      // if (cond) { ... } else { ... } — 多语句块版本
      if (/^if\s*\(/.test(line)) {
        const ifResult = await this.runIfBlock(line, lines, i, localVars);
        if (ifResult.result.returned) return ifResult.result;
        if (ifResult.result.value !== undefined) lastValue = ifResult.result.value;
        i = ifResult.endIndex;
        continue;
      }
      // 跳过孤立的 } （块结束标记）
      if (line === '}') { i++; continue; }
      // if (cond) stmt — 单行版本
      const ifMatch = this.matchIfStatement(line);
      if (ifMatch) {
        const condVal = await this.evalExprAsync(ifMatch.cond, localVars);
        const truthy = !!condVal && condVal !== '0' && condVal !== 'false';
        const branch = truthy ? ifMatch.thenStmt : ifMatch.elseStmt;
        if (branch) {
          const sub = await this.runStatements([branch], localVars);
          if (sub.returned) return sub;
          if (sub.value !== undefined) lastValue = sub.value;
        }
        i++;
        continue;
      }
      // var/let/const X = expr
      const declMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      if (declMatch) {
        const v = await this.evalExprAsync(declMatch[2], localVars);
        if (v !== undefined) {
          localVars[declMatch[1]] = v;
          lastValue = v;
        }
        i++;
        continue;
      }
      // X = expr (含 obj.prop = val)
      const assignMatch = line.match(/^(\w+(?:\.\w+)*)\s*=\s*(.+)$/);
      if (assignMatch) {
        const v = await this.evalExprAsync(assignMatch[2], localVars);
        if (v !== undefined) {
          const target = assignMatch[1];
          if (target.includes('.')) {
            // obj.prop = val — 暂不支持深层赋值，存到根变量
            const dotIdx = target.indexOf('.');
            const root = target.substring(0, dotIdx);
            if (localVars[root] !== undefined) {
              (localVars[root] as Record<string, Object>)[target.substring(dotIdx + 1)] = v;
            }
          } else {
            localVars[target] = v;
          }
          lastValue = v;
        }
        i++;
        continue;
      }
      // 单纯表达式
      const v = await this.evalExprAsync(line, localVars);
      if (v !== undefined) lastValue = v;
      i++;
    }
    const r: ScriptStmtResult = { value: lastValue, returned: false };
    return r;
  }

  /** 收集块语句体（从当前行的 { 开始到匹配的 } 结束） */
  private collectBlock(lines: string[], startIdx: number): BlockResult {
    // 找到开始的 {
    let i = startIdx;
    let line = lines[i];
    // 如果当前行以 { 结尾，从下一行开始
    if (line.endsWith('{')) {
      i++;
    } else if (line.includes('{')) {
      // { 在行中间（如 for (...) {）
      const afterBrace = line.substring(line.indexOf('{') + 1).trim();
      i++;
      // 如果 } 在同一行
      if (afterBrace.includes('}')) {
        const body = afterBrace.substring(0, afterBrace.indexOf('}')).trim();
        const r: BlockResult = { bodyLines: body ? [body] : [], endIndex: i };
        return r;
      }
    } else {
      // 没有 { — 单语句体
      i++;
      if (i < lines.length) {
        const r: BlockResult = { bodyLines: [lines[i]], endIndex: i + 1 };
        return r;
      }
      const r: BlockResult = { bodyLines: [], endIndex: i };
      return r;
    }
    // 收集直到匹配的 }
    const body: string[] = [];
    let depth = 1;
    while (i < lines.length && depth > 0) {
      const l = lines[i];
      // 计算 { 和 } 的深度（忽略字符串内的）
      let inStr: string | null = null;
      for (let j = 0; j < l.length; j++) {
        const c = l[j];
        if (inStr) {
          if (c === '\\' && j + 1 < l.length) { j++; continue; }
          if (c === inStr) inStr = null;
          continue;
        }
        if (c === '"' || c === "'" || c === '`') { inStr = c; continue; }
        if (c === '{') depth++;
        else if (c === '}') { depth--; if (depth === 0) break; }
      }
      if (depth === 0) {
        // 最后一行可能包含 } 之前的代码
        const beforeBrace = l.substring(0, l.lastIndexOf('}')).trim();
        if (beforeBrace) body.push(beforeBrace);
      } else {
        body.push(l);
      }
      i++;
    }
    const result: BlockResult = { bodyLines: body, endIndex: i };
    return result;
  }

  /** 执行 if 块（支持多语句 { } else { }） */
  private async runIfBlock(
    line: string, lines: string[], startIdx: number, localVars: Record<string, Object>
  ): Promise<IfBlockResult> {
    // 提取条件
    const condMatch = line.match(/^if\s*\((.+)\)\s*\{?$/);
    if (!condMatch) {
      // 降级到单行 if
      const ifMatch = this.matchIfStatement(line);
      if (ifMatch) {
        const condVal = await this.evalExprAsync(ifMatch.cond, localVars);
        const truthy = !!condVal && condVal !== '0' && condVal !== 'false';
        const branch = truthy ? ifMatch.thenStmt : ifMatch.elseStmt;
        if (branch) {
          const sub = await this.runStatements([branch], localVars);
          const r1: IfBlockResult = { result: sub, endIndex: startIdx + 1 };
          return r1;
        }
      }
      const defaultResult: ScriptStmtResult = { value: undefined, returned: false };
      const r2: IfBlockResult = { result: defaultResult, endIndex: startIdx + 1 };
      return r2;
    }
    const condVal = await this.evalExprAsync(condMatch[1], localVars);
    const truthy = !!condVal && condVal !== '0' && condVal !== 'false';
    // 收集 then 块
    const thenBlock = this.collectBlock(lines, startIdx);
    let endIndex = thenBlock.endIndex;
    let stmtResult: ScriptStmtResult = { value: undefined, returned: false };
    if (truthy) {
      stmtResult = await this.runStatements(thenBlock.bodyLines, localVars);
    }
    // 检查 else
    if (endIndex < lines.length && /^else\s*\{?$/.test(lines[endIndex])) {
      const elseBlock = this.collectBlock(lines, endIndex);
      endIndex = elseBlock.endIndex;
      if (!truthy) {
        stmtResult = await this.runStatements(elseBlock.bodyLines, localVars);
      }
    }
    const r3: IfBlockResult = { result: stmtResult, endIndex };
    return r3;
  }

  /** 匹配 if (cond) thenStmt; else elseStmt; 单行/单语句版本 */
  private matchIfStatement(line: string): IfStmtMatch | null {
    if (!/^if\s*\(/.test(line)) return null;
    let i = 2;
    while (i < line.length && line[i] !== '(') i++;
    if (line[i] !== '(') return null;
    let depth = 1;
    let j = i + 1;
    while (j < line.length && depth > 0) {
      if (line[j] === '(') depth++;
      else if (line[j] === ')') depth--;
      if (depth === 0) break;
      j++;
    }
    if (depth !== 0) return null;
    const cond = line.substring(i + 1, j).trim();
    const rest = line.substring(j + 1).trim();
    const elseIdx = this.findTopLevelElse(rest);
    let thenStmt: string;
    let elseStmt: string | undefined = undefined;
    if (elseIdx >= 0) {
      thenStmt = rest.substring(0, elseIdx).replace(/;\s*$/, '').trim();
      elseStmt = rest.substring(elseIdx + 4).replace(/^\s*/, '').replace(/;\s*$/, '').trim();
    } else {
      thenStmt = rest.replace(/;\s*$/, '').trim();
    }
    if (thenStmt.startsWith('{') && thenStmt.endsWith('}')) thenStmt = thenStmt.substring(1, thenStmt.length - 1).trim();
    if (elseStmt && elseStmt.startsWith('{') && elseStmt.endsWith('}')) elseStmt = elseStmt.substring(1, elseStmt.length - 1).trim();
    const result: IfStmtMatch = { cond, thenStmt, elseStmt };
    return result;
  }

  private findTopLevelElse(s: string): number {
    let depth = 0;
    let inStr: string | null = null;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (inStr) {
        if (c === '\\' && i + 1 < s.length) { i++; continue; }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === '"' || c === "'") { inStr = c; continue; }
      if (c === '(' || c === '{' || c === '[') depth++;
      else if (c === ')' || c === '}' || c === ']') depth--;
      else if (depth === 0 && c === 'e' && s.substring(i, i + 4) === 'else'
               && (i === 0 || /\s|\}|\)/.test(s[i - 1]))
               && (i + 4 >= s.length || /\s|\{|\(/.test(s[i + 4]))) {
        return i;
      }
    }
    return -1;
  }

  /** 把脚本切成顶层语句（按 ;/\n，但忽略字符串/正则/括号内的分号，正确处理 for/while/try 块） */
  private splitStatements(code: string): string[] {
    const out: string[] = [];
    let buf = '';
    let inStr: string | null = null;
    let parenDepth = 0; // for (init;cond;update) 中的括号深度
    let braceDepth = 0; // { } 块深度
    let isForHeader = false; // 是否在 for (...) 头部

    for (let i = 0; i < code.length; i++) {
      const c = code[i];
      if (inStr) {
        buf += c;
        if (c === '\\' && i + 1 < code.length) { buf += code[i + 1]; i++; continue; }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === "'" || c === '"' || c === '`') { inStr = c; buf += c; continue; }
      if (c === '(') {
        parenDepth++;
        buf += c;
        // 检测是否是 for ( 开始
        const trimmed = buf.trimStart();
        if (trimmed.startsWith('for') || trimmed.startsWith('while')) isForHeader = true;
        continue;
      }
      if (c === ')') {
        parenDepth--;
        buf += c;
        if (parenDepth === 0) isForHeader = false;
        continue;
      }
      if (c === '{') { braceDepth++; buf += c; continue; }
      if (c === '}') {
        braceDepth--;
        buf += c;
        // 块结束时输出整个块
        if (braceDepth === 0) {
          const t = buf.trim();
          if (t) out.push(t);
          buf = '';
        }
        continue;
      }
      // 分号：在 for 头部或括号内时不切分
      if (c === ';' && parenDepth === 0 && braceDepth === 0) {
        const t = buf.trim();
        if (t) out.push(t);
        buf = '';
        continue;
      }
      // 换行：在块内或 for 头部时不切分
      if (c === '\n' && braceDepth === 0 && parenDepth === 0) {
        const t = buf.trim();
        if (t) out.push(t);
        buf = '';
        continue;
      }
      buf += c;
    }
    const tail = buf.trim();
    if (tail) out.push(tail);
    return out;
  }

  /** 异步表达式求值：识别 java.xxx(...) 调用，否则交给同步本地求值器 */
  private async evalExprAsync(expr: string, vars: Record<string, Object>): Promise<Object | undefined> {
    const e = expr.trim().replace(/;$/, '').trim();
    if (!e) return '';

    // java.ajax(arg) / java.connect(arg) / java.getString(arg)
    const ajaxMatch = e.match(/^java\.(ajax|connect|getString)\(([^)]*)\)$/);
    if (ajaxMatch) {
      const argExpr = ajaxMatch[2].trim();
      const urlVal = argExpr ? await this.evalExprAsync(argExpr, vars) : '';
      const url = urlVal === undefined ? '' : String(urlVal);
      if (!url) return '';
      const javaBridge = getJavaBridge();
      try {
        return await javaBridge.ajax(url);
      } catch {
        return '';
      }
    }

    // java.put(k, v)
    const putMatch = e.match(/^java\.put\(([^,]+),\s*(.+)\)$/);
    if (putMatch) {
      const keyVal = await this.evalExprAsync(putMatch[1], vars);
      const valVal = await this.evalExprAsync(putMatch[2], vars);
      if (keyVal === undefined || valVal === undefined) return undefined;
      const javaBridge = getJavaBridge();
      javaBridge.put(String(keyVal), String(valVal));
      return String(valVal);
    }

    // java.get(k)
    const getMatch = e.match(/^java\.get\((.+)\)$/);
    if (getMatch) {
      const keyVal = await this.evalExprAsync(getMatch[1], vars);
      if (keyVal === undefined) return undefined;
      const javaBridge = getJavaBridge();
      return javaBridge.get(String(keyVal));
    }

    // java.log(arg)
    const logMatch = e.match(/^java\.log\((.+)\)$/);
    if (logMatch) {
      const v = await this.evalExprAsync(logMatch[1], vars);
      if (v !== undefined) {
        const javaBridge = getJavaBridge();
        javaBridge.log(String(v));
      }
      return '';
    }

    // java.toast(arg) / java.longToast(arg)
    const toastMatch = e.match(/^java\.(toast|longToast)\((.+)\)$/);
    if (toastMatch) {
      const v = await this.evalExprAsync(toastMatch[2], vars);
      if (v !== undefined) {
        const javaBridge = getJavaBridge();
        if (toastMatch[1] === 'longToast') {
          javaBridge.longToast(String(v));
        } else {
          javaBridge.toast(String(v));
        }
      }
      return '';
    }

    // java.hexDecodeToString(arg)
    const hexMatch = e.match(/^java\.hexDecodeToString\((.+)\)$/);
    if (hexMatch) {
      const v = await this.evalExprAsync(hexMatch[1], vars);
      if (v === undefined) return undefined;
      return getJavaBridge().hexDecodeToString(String(v));
    }

    // java.startBrowser(url, title) / java.startBrowserDp(url, title)
    const startBrowserMatch = e.match(/^java\.startBrowser(?:Dp)?\((.+)\)$/);
    if (startBrowserMatch) {
      const args = this.parseArgs(startBrowserMatch[1]);
      const javaBridge = getJavaBridge();
      javaBridge.startBrowser(String(args[0] || ''), args.length > 1 ? String(args[1]) : '');
      return '';
    }

    // java.md5(arg) / java.md5Encode(arg) / java.md5Encode16(arg)
    const md5Match = e.match(/^java\.(md5|md5Encode|md5Encode16)\((.+)\)$/);
    if (md5Match) {
      const v = await this.evalExprAsync(md5Match[2], vars);
      if (v === undefined) return undefined;
      const javaBridge = getJavaBridge();
      if (md5Match[1] === 'md5Encode16') return javaBridge.md5Encode16(String(v));
      return javaBridge.md5(String(v));
    }

    // java.encodeURI(arg)
    const encodeURIMatch = e.match(/^java\.encodeURI\((.+)\)$/);
    if (encodeURIMatch) {
      const v = await this.evalExprAsync(encodeURIMatch[1], vars);
      if (v === undefined) return undefined;
      return getJavaBridge().encodeURI(String(v));
    }

    // java.base64Encode(arg) / java.base64Decode(arg)
    const b64Match = e.match(/^java\.(base64Encode|base64Decode)\((.+)\)$/);
    if (b64Match) {
      const v = await this.evalExprAsync(b64Match[2], vars);
      if (v === undefined) return undefined;
      const jb = getJavaBridge();
      return b64Match[1] === 'base64Encode' ? jb.base64Encode(String(v)) : jb.base64Decode(String(v));
    }

    // java.HMacHex(data, algorithm, key) / java.HMacBase64(data, algorithm, key)
    const hmacMatch = e.match(/^java\.(HMacHex|HMacBase64)\((.+)\)$/);
    if (hmacMatch) {
      const args = this.parseArgs(hmacMatch[2]);
      if (args.length < 3) return undefined;
      const jb = getJavaBridge();
      const data = String(await this.evalExprAsync(String(args[0]), vars) ?? args[0]);
      const algo = String(await this.evalExprAsync(String(args[1]), vars) ?? args[1]);
      const key = String(await this.evalExprAsync(String(args[2]), vars) ?? args[2]);
      return hmacMatch[1] === 'HMacHex' ? jb.HMacHex(data, algo, key) : jb.HMacBase64(data, algo, key);
    }

    // java.digestHex(data, algorithm) / java.digestBase64Str(data, algorithm)
    const digestMatch = e.match(/^java\.(digestHex|digestBase64Str)\((.+)\)$/);
    if (digestMatch) {
      const args = this.parseArgs(digestMatch[2]);
      if (args.length < 2) return undefined;
      const jb = getJavaBridge();
      const data = String(await this.evalExprAsync(String(args[0]), vars) ?? args[0]);
      const algo = String(await this.evalExprAsync(String(args[1]), vars) ?? args[1]);
      return digestMatch[1] === 'digestHex' ? jb.digestHex(data, algo) : jb.digestBase64Str(data, algo);
    }

    // java.strToBytes(arg) / java.bytesToStr(arg)
    const bytesMatch = e.match(/^java\.(strToBytes|bytesToStr)\((.+)\)$/);
    if (bytesMatch) {
      const v = await this.evalExprAsync(bytesMatch[2], vars);
      if (v === undefined) return undefined;
      const jb = getJavaBridge();
      if (bytesMatch[1] === 'strToBytes') {
        return jb.strToBytes(String(v)) as Object;
      } else {
        // bytesToStr expects number[]
        if (Array.isArray(v)) return jb.bytesToStr(v as number[]);
        return String(v);
      }
    }

    // java.hexEncodeToString(arg)
    const hexEncMatch = e.match(/^java\.hexEncodeToString\((.+)\)$/);
    if (hexEncMatch) {
      const v = await this.evalExprAsync(hexEncMatch[1], vars);
      if (v === undefined) return undefined;
      return getJavaBridge().hexEncodeToString(String(v));
    }

    // java.createSymmetricCrypto(transformation, key, iv)
    const cryptoMatch = e.match(/^java\.createSymmetricCrypto\((.+)\)$/);
    if (cryptoMatch) {
      const args = this.parseArgs(cryptoMatch[2]);
      if (args.length < 2) return undefined;
      const transformation = String(await this.evalExprAsync(String(args[0]), vars) ?? args[0]);
      const key = String(await this.evalExprAsync(String(args[1]), vars) ?? args[1]);
      const iv = args.length > 2 ? String(await this.evalExprAsync(String(args[2]), vars) ?? args[2]) : undefined;
      return getJavaBridge().createSymmetricCrypto(transformation, key, iv);
    }

    // java.builtin('id').method(args) — 调用内置源的方法
    // 支持: getAudioUrl(url) / search(keyword, page) / getHomeBlocks()
    const builtinMatch = e.match(/^java\.builtin\((['"]?)([^'"]+)\1\)\.([\w]+)\((.*)\)$/);
    if (builtinMatch) {
      const sourceId = builtinMatch[2].trim();
      const methodName = builtinMatch[3].trim();
      const argsExpr = builtinMatch[4].trim();
      const plugin = BuiltInSourceRegistry.get(sourceId);
      if (!plugin) return `[builtin '${sourceId}' not found]`;
      try {
        if (methodName === 'getAudioUrl') {
          const urlVal = argsExpr ? await this.evalExprAsync(argsExpr, vars) : '';
          return await plugin.getAudioUrl(String(urlVal || ''));
        }
        if (methodName === 'search') {
          const argsList = this.parseArgs(argsExpr);
          const a0 = argsList.length > 0 ? String(argsList[0]) : '';
          const a1 = argsList.length > 1 ? String(argsList[1]) : '1';
          const kw = a0 ? String(await this.evalExprAsync(a0, vars) ?? a0) : '';
          const pgVal = await this.evalExprAsync(a1, vars);
          const pg = pgVal !== undefined ? Number(pgVal) : 1;
          const result = await plugin.search(kw, pg);
          return JSON.stringify(result);
        }
        if (methodName === 'getHomeBlocks') {
          const result = await plugin.getHomeBlocks();
          return JSON.stringify(result);
        }
        return `[builtin method '${methodName}' not supported]`;
      } catch (e2) {
        return `[builtin error: ${e2 instanceof Error ? e2.message : String(e2)}]`;
      }
    }

    // a + b + c 拼接：先尝试 async 处理，因为单段可能也是 java.ajax 调用
    if (e.includes('+') && !/^['"`]/.test(e)) {
      const parts = this.splitTopLevelPlus(e);
      if (parts.length > 1) {
        let acc = '';
        for (const p of parts) {
          const v = await this.evalExprAsync(p.trim(), vars);
          if (v === undefined) return undefined;
          acc += String(v);
        }
        return acc;
      }
    }

    // jsLib 包装的 IIFE：(function(){...}).call(this)
    // 不能被 splitStatements 拆分执行，需要通过完整 JS 引擎执行
    if (e.startsWith('(function') && e.includes('.call(')) {
      return undefined; // 返回 undefined 让上层降级到 proxy / WebView
    }

    // 普通同步表达式
    const sync = this.tryLocalEval(e, vars);
    return sync;
  }

  /** 按顶层 + 切分（忽略字符串、括号内的 +） */
  private splitTopLevelPlus(expr: string): string[] {
    const out: string[] = [];
    let buf = '';
    let depth = 0;
    let inStr: string | null = null;
    for (let i = 0; i < expr.length; i++) {
      const c = expr[i];
      if (inStr) {
        buf += c;
        if (c === '\\' && i + 1 < expr.length) { buf += expr[i + 1]; i++; continue; }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === "'" || c === '"' || c === '`') { inStr = c; buf += c; continue; }
      if (c === '(' || c === '[') { depth++; buf += c; continue; }
      if (c === ')' || c === ']') { depth--; buf += c; continue; }
      if (c === '+' && depth === 0) {
        out.push(buf);
        buf = '';
        continue;
      }
      buf += c;
    }
    if (buf.trim()) out.push(buf);
    return out;
  }

  private tryLocalEvalRelaxed(code: string, ctx: Record<string, Object>): Object | null {
    // 尝试提取最后一个表达式作为返回值
    const lines = code.split(/[;\n]/).map((l) => l.trim()).filter((l) => l.length > 0);
    if (lines.length === 0) return null;

    // 处理 var 声明 + 裸赋值（result = ... 改写）
    const localVars: Record<string, Object> = {};
    const ctxKeys = Object.keys(ctx);
    for (const ck of ctxKeys) localVars[ck] = ctx[ck];
    for (let i = 0; i < lines.length - 1; i++) {
      const declMatch = lines[i].match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      const assignMatch = declMatch ? null : lines[i].match(/^(\w+)\s*=(?!=)\s*(.+)$/);
      const m = declMatch ?? assignMatch;
      if (m) {
        const val = this.tryLocalEval(m[2], localVars);
        if (val !== undefined) {
          localVars[m[1]] = val;
        }
      }
    }

    // 最后一行作为返回值
    const lastLine = lines[lines.length - 1];
    const result = this.tryLocalEval(lastLine, localVars);
    return result !== undefined ? result : null;
  }

  private tryEvalConcat(code: string, ctx: Record<string, Object>): Object | undefined {
    // 简单字符串拼接：'a' + b + 'c' + obj.prop
    // 用 splitTopLevelPlus 切分，忽略字符串/括号内的 +，避免把 result.split('/')[2] 之类切坏
    if (!code.includes('+')) return undefined;

    const parts = this.splitTopLevelPlus(code).map((p) => p.trim());
    if (parts.length < 2) return undefined;
    let result = '';
    for (const part of parts) {
      // 字符串字面量：必须首尾同引号且中间无未转义同引号
      if (/^"(?:[^"\\]|\\.)*"$/.test(part) || /^'(?:[^'\\]|\\.)*'$/.test(part)) {
        result += part.substring(1, part.length - 1).replace(/\\(.)/g, '$1');
      } else if (/^[a-zA-Z_]\w*$/.test(part)) {
        const val = ctx[part];
        if (val === undefined) return undefined;
        result += String(val);
      } else if (/^-?\d+(?:\.\d+)?$/.test(part)) {
        result += part;
      } else if (part.includes('.') || part.includes('[')) {
        const chainVal = this.tryEvalPropertyChain(part, ctx);
        if (chainVal === undefined) return undefined;
        result += String(chainVal);
      } else {
        return undefined;
      }
    }
    return result;
  }

  private tryEvalPropertyChain(code: string, ctx: Record<string, Object>): Object | undefined {
    // result.split('x')[0], result.replace('a','b'), result.trim()
    const chainMatch = code.match(/^(\w+)((?:\.\w+(?:\([^)]*\))?|\[\d+\])+)$/);
    if (!chainMatch) return undefined;

    const rootVar = chainMatch[1];
    let current: Object | undefined = ctx[rootVar];
    if (current === undefined) return undefined;

    const chainStr = chainMatch[2];
    // 解析链式调用
    const chainRegex = /\.(\w+)(?:\(([^)]*)\))?|\[(\d+)\]/g;
    let match = chainRegex.exec(chainStr);
    while (match !== null) {
      if (match[3] !== undefined) {
        // 数组索引 [N]
        if (typeof current === 'string') {
          current = (current as string)[parseInt(match[3], 10)];
        } else if (Array.isArray(current)) {
          current = (current as Object[])[parseInt(match[3], 10)];
        } else {
          return undefined;
        }
      } else if (match[1]) {
        const method = match[1];
        const argsStr = match[2];

        if (typeof current === 'string') {
          const str = current as string;
          current = this.evalStringMethod(str, method, argsStr);
          if (current === undefined) return undefined;
        } else if (Array.isArray(current)) {
          const arr = current as Object[];
          current = this.evalArrayMethod(arr, method, argsStr);
          if (current === undefined) return undefined;
        } else {
          // 对象属性访问
          if (typeof current === 'object' && current !== null && !argsStr) {
            current = (current as Record<string, Object>)[method];
          } else {
            return undefined;
          }
        }
      }
      if (current === undefined || current === null) return current as Object;
      match = chainRegex.exec(chainStr);
    }
    return current;
  }

  private evalStringMethod(str: string, method: string, argsStr?: string): Object | undefined {
    const args = argsStr ? this.parseArgs(argsStr) : [];
    const toRegex = (v: Object): RegExp | null => {
      if (typeof v !== 'string') return null;
      const m = (v as string).match(/^\/(.+)\/([gimsuy]*)$/);
      if (!m) return null;
      try { return new RegExp(m[1], m[2]); } catch { return null; }
    };
    switch (method) {
      case 'trim': return str.trim();
      case 'trimStart': case 'trimLeft': return str.trimStart();
      case 'trimEnd': case 'trimRight': return str.trimEnd();
      case 'toLowerCase': return str.toLowerCase();
      case 'toUpperCase': return str.toUpperCase();
      case 'length': return str.length;
      case 'split': {
        if (args.length === 0) return [str];
        const re = toRegex(args[0]);
        return re ? str.split(re) : str.split(String(args[0]));
      }
      case 'replace': {
        if (args.length < 2) return str;
        const re = toRegex(args[0]);
        return re ? str.replace(re, String(args[1])) : str.replace(String(args[0]), String(args[1]));
      }
      case 'replaceAll': {
        if (args.length < 2) return str;
        const re = toRegex(args[0]);
        if (re) {
          // 强制 g 标志
          const flags = re.flags.includes('g') ? re.flags : (re.flags + 'g');
          return str.replace(new RegExp(re.source, flags), String(args[1]));
        }
        return str.split(String(args[0])).join(String(args[1]));
      }
      case 'substring': case 'slice': {
        const start = args.length > 0 ? Number(args[0]) : 0;
        const end = args.length > 1 ? Number(args[1]) : undefined;
        return end !== undefined ? str.substring(start, end) : str.substring(start);
      }
      case 'indexOf': return args.length > 0 ? str.indexOf(String(args[0])) : -1;
      case 'lastIndexOf': return args.length > 0 ? str.lastIndexOf(String(args[0])) : -1;
      case 'includes': return args.length > 0 ? str.includes(String(args[0])) : false;
      case 'startsWith': return args.length > 0 ? str.startsWith(String(args[0])) : false;
      case 'endsWith': return args.length > 0 ? str.endsWith(String(args[0])) : false;
      case 'match': {
        if (args.length === 0) return undefined;
        try {
          const re = toRegex(args[0]) ?? new RegExp(String(args[0]));
          const m = str.match(re);
          if (!m) return undefined;
          // 全局匹配返回数组，非全局返回首个匹配
          return re.flags.includes('g') ? Array.from(m) as Object[] : m[0];
        } catch { return undefined; }
      }
      case 'charAt': return args.length > 0 ? str.charAt(Number(args[0])) : '';
      default: return undefined;
    }
  }

  private evalArrayMethod(arr: Object[], method: string, argsStr?: string): Object | undefined {
    const args = argsStr ? this.parseArgs(argsStr) : [];
    switch (method) {
      case 'length': return arr.length;
      case 'join': return arr.join(args.length > 0 ? String(args[0]) : ',');
      case 'reverse': {
        const copy: Object[] = arr.slice();
        copy.reverse();
        return copy;
      }
      case 'slice': {
        const start = args.length > 0 ? Number(args[0]) : 0;
        const end = args.length > 1 ? Number(args[1]) : undefined;
        return end !== undefined ? arr.slice(start, end) : arr.slice(start);
      }
      default: return undefined;
    }
  }

  private parseArgs(argsStr: string): Object[] {
    if (!argsStr.trim()) return [];
    const args: Object[] = [];
    let current = '';
    let inStr: string | null = null;
    let inRegex = false;
    let depth = 0;

    for (let i = 0; i < argsStr.length; i++) {
      const c = argsStr[i];
      const prev = i > 0 ? argsStr[i - 1] : '';
      if (inStr) {
        if (c === inStr && argsStr[i - 1] !== '\\') {
          current += c;
          inStr = null;
        } else {
          current += c;
        }
      } else if (inRegex) {
        current += c;
        if (c === '\\' && i + 1 < argsStr.length) { current += argsStr[i + 1]; i++; continue; }
        if (c === '/') {
          // 吃掉 flags
          let k = i + 1;
          while (k < argsStr.length && /[gimsuy]/.test(argsStr[k])) {
            current += argsStr[k];
            k++;
          }
          i = k - 1;
          inRegex = false;
        }
      } else if (c === '"' || c === "'") {
        current += c;
        inStr = c;
      } else if (c === '/' && (current.trim() === '' || prev === ',' || prev === '(')) {
        // 正则字面量起点：在 arg 起始位置
        current += c;
        inRegex = true;
      } else if (c === '(' || c === '[') {
        current += c;
        depth++;
      } else if (c === ')' || c === ']') {
        current += c;
        depth--;
      } else if (c === ',' && depth === 0) {
        args.push(this.parseArgValue(current.trim()));
        current = '';
      } else {
        current += c;
      }
    }
    if (current.trim()) {
      args.push(this.parseArgValue(current.trim()));
    }
    return args;
  }

  private parseArgValue(val: string): Object {
    if ((val.startsWith("'") && val.endsWith("'")) ||
        (val.startsWith('"') && val.endsWith('"'))) {
      return val.substring(1, val.length - 1);
    }
    // 保留 /regex/flags 字面量原样（evalStringMethod 会识别）
    if (/^\/.+\/[gimsuy]*$/.test(val)) return val;
    if (val === 'true') return true;
    if (val === 'false') return false;
    if (val === 'null' || val === 'undefined') return '';
    const num = parseFloat(val);
    if (!Number.isNaN(num)) return num;
    return val;
  }

  private tryEvalAssignment(code: string, ctx: Record<string, Object>): Object | undefined {
    // var url = baseUrl + '/path'; url
    // 也支持对已有变量的裸赋值：result = "..." + result.replace(...) ; result
    // （Legado 书源 chapterUrl/audioUrl 规则常用 result=... 改写后再返回 result）
    const lines = code.split(/[;\n]/).map((l) => l.trim()).filter((l) => l.length > 0);
    if (lines.length < 2) return undefined;

    const localVars: Record<string, Object> = {};
    const ctxKeys = Object.keys(ctx);
    for (const ck of ctxKeys) localVars[ck] = ctx[ck];
    for (let i = 0; i < lines.length - 1; i++) {
      // 优先匹配声明；否则匹配裸赋值 X = expr（用 (?!=) 排除 == 比较）
      const declMatch = lines[i].match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      const assignMatch = declMatch ? null : lines[i].match(/^(\w+)\s*=(?!=)\s*(.+)$/);
      const m = declMatch ?? assignMatch;
      if (m) {
        const val = this.tryLocalEval(m[2], localVars);
        if (val !== undefined) {
          localVars[m[1]] = val;
        }
      }
    }

    const lastLine = lines[lines.length - 1];
    if (/^[a-zA-Z_]\w*$/.test(lastLine)) {
      return localVars[lastLine];
    }
    return this.tryLocalEval(lastLine, localVars);
  }

  /**
   * DOM shim：处理书源 JS 规则中的 document.querySelector 等 DOM 操作
   * 搬山人书源的 content 规则使用 document.querySelector + cloneNode + querySelectorAll + innerText + remove
   */
  private tryDOMShim(code: string, ctx: Record<string, Object>): Object | undefined {
    // 仅处理简单的 DOM 操作模式，复杂的交给 HTTP 代理
    // 模式：document.querySelector(...).cloneNode(true); el.querySelectorAll(...); el.remove(); el.innerText

    const html = ctx['result'] ? String(ctx['result']) : '';
    if (!html) return undefined;

    try {
      const root = SimpleCSSSelector.parseHTML(html);

      // 创建简化的 DOM 环境
      const domDocument: DOMShimDocument = new DOMShimDocument(root);
      const mergedCtx: Record<string, Object> = {};
      for (const k of Object.keys(ctx)) mergedCtx[k] = ctx[k];
      mergedCtx['document'] = domDocument;

      // 尝试执行（简单模式：变量赋值 + 方法调用）
      return this.tryDOMEval(code, mergedCtx);
    } catch {
      return undefined;
    }
  }

  private tryDOMEval(code: string, ctx: Record<string, Object>): Object | undefined {
    // 处理常见 DOM 操作序列（如 IIFE 解开后的函数体）
    // 支持：var/let/const 赋值；querySelector/querySelectorAll；cloneNode；
    //   forEach(x => x.remove())；if(...) return ...；最终 return X.method().method()
    const lines = code.split(/[;\n]/).map((l) => l.trim()).filter((l) => l.length > 0);
    const localVars: Record<string, Object> = {};
    for (const k of Object.keys(ctx)) localVars[k] = ctx[k];

    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];

      // 去掉行首 return（最终返回值在循环外捕获，单 return X 用最后一行处理）
      const isReturn = /^return\s+/.test(line) || /^return\s*$/.test(line);
      if (isReturn) {
        line = line.replace(/^return\s*/, '').trim();
        if (!line) return '';
      }

      // if (cond) return ''  /  if (cond) return X
      const ifReturnMatch = line.match(/^if\s*\(\s*(!?)(\w+)\s*\)\s*return\s*(.*)$/);
      if (ifReturnMatch) {
        const negate = ifReturnMatch[1] === '!';
        const cond = localVars[ifReturnMatch[2]];
        const truthy = !!cond;
        if (negate ? !truthy : truthy) {
          let retExpr = ifReturnMatch[3].trim();
          if (!retExpr || retExpr === ';') return '';
          retExpr = retExpr.replace(/;$/, '').trim();
          // return '' 或 return X
          if (/^['"].*['"]$/.test(retExpr)) return retExpr.substring(1, retExpr.length - 1);
          if (/^[a-zA-Z_]\w*$/.test(retExpr)) return localVars[retExpr];
        }
        continue;
      }

      // var/let/const X = document.querySelector(...)
      const docQueryMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*document\.querySelector(?:All)?\(['"]([^'"]+)['"]\)$/);
      if (docQueryMatch) {
        const varName = docQueryMatch[1];
        const selector = docQueryMatch[2];
        const isAll = line.includes('querySelectorAll');
        const doc = localVars['document'];
        if (doc && doc instanceof DOMShimDocument) {
          const result: Object | null = isAll ? doc.querySelectorAll(selector) : doc.querySelector(selector);
          localVars[varName] = result !== null ? result : '';
          continue;
        }
      }

      // var/let/const X = Y.querySelector(...)
      const elQueryMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(\w+)\.querySelector(?:All)?\(['"]([^'"]+)['"]\)$/);
      if (elQueryMatch) {
        const varName = elQueryMatch[1];
        const sourceVar = elQueryMatch[2];
        const selector = elQueryMatch[3];
        const isAll = line.includes('querySelectorAll');
        const source = localVars[sourceVar];
        if (source && source instanceof DOMShimElement) {
          const shimEl = source as DOMShimElement;
          localVars[varName] = isAll ? shimEl.querySelectorAll(selector) : (shimEl.querySelector(selector) || '');
          continue;
        }
      }

      // var/let/const clone = el.cloneNode(true)
      const cloneMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(\w+)\.cloneNode\((true|false)\)$/);
      if (cloneMatch) {
        const varName = cloneMatch[1];
        const sourceVar = cloneMatch[2];
        const source = localVars[sourceVar];
        if (source && source instanceof DOMShimElement) {
          const shimEl = source as DOMShimElement;
          localVars[varName] = shimEl.cloneNode(cloneMatch[3] === 'true');
          continue;
        }
      }

      // var/let/const text = el.innerText / el.innerHTML
      const innerAssignMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(\w+)\.(innerText|innerHTML|outerHTML)$/);
      if (innerAssignMatch) {
        const varName = innerAssignMatch[1];
        const sourceVar = innerAssignMatch[2];
        const prop = innerAssignMatch[3];
        const source = localVars[sourceVar];
        if (source && source instanceof DOMShimElement) {
          const shimEl = source as DOMShimElement;
          localVars[varName] = prop === 'innerText' ? shimEl.innerText
            : prop === 'innerHTML' ? shimEl.innerHTML : shimEl.outerHTML;
          continue;
        }
      }

      // X.querySelectorAll(sel).forEach(name => name.remove())
      const forEachRemoveMatch = line.match(/^(\w+)\.querySelectorAll\(['"]([^'"]+)['"]\)\.forEach\(\s*(\w+)\s*=>\s*\3\.remove\(\)\s*\)$/);
      if (forEachRemoveMatch) {
        const sourceVar = forEachRemoveMatch[1];
        const selector = forEachRemoveMatch[2];
        const source = localVars[sourceVar];
        if (source && source instanceof DOMShimElement) {
          const shimEl = source as DOMShimElement;
          const matched = shimEl.querySelectorAll(selector);
          for (const m of matched) m.remove();
          continue;
        }
      }

      // X.remove()
      const removeMatch = line.match(/^(\w+)\.remove\(\)$/);
      if (removeMatch) {
        const varName = removeMatch[1];
        const el = localVars[varName];
        if (el && el instanceof DOMShimElement) {
          (el as DOMShimElement).remove();
        }
        continue;
      }

      // 最后一行 / 显式 return：返回值
      if (i === lines.length - 1 || isReturn) {
        // X.innerText
        const innerTextMatch = line.match(/^(\w+)\.(innerText|innerHTML|outerHTML)$/);
        if (innerTextMatch) {
          const el = localVars[innerTextMatch[1]];
          if (el && el instanceof DOMShimElement) {
            const shimEl = el as DOMShimElement;
            return innerTextMatch[2] === 'innerText' ? shimEl.innerText
              : innerTextMatch[2] === 'innerHTML' ? shimEl.innerHTML : shimEl.outerHTML;
          }
        }
        // document.querySelector(...).innerText 直接链式
        const directQueryMatch = line.match(/^document\.querySelector\(['"]([^'"]+)['"]\)\.innerText$/);
        if (directQueryMatch) {
          const doc = localVars['document'];
          if (doc && doc instanceof DOMShimDocument) {
            const el = doc.querySelector(directQueryMatch[1]);
            if (el) return (el as DOMShimElement).innerText;
          }
        }
        // X.replace(/regex/g, repl).trim()
        const replaceTrimChain = this.tryEvalStringChain(line, localVars);
        if (replaceTrimChain !== undefined) return replaceTrimChain;
        // 单变量
        if (/^[a-zA-Z_]\w*$/.test(line)) {
          return localVars[line];
        }
      }
    }

    return undefined;
  }

  /**
   * 尝试 X.method(...).method(...) 链式调用（含正则字面量参数）
   *  - X.replace(/regex/g, 'repl')
   *  - X.replace('a', 'b')
   *  - X.trim() / X.toUpperCase() / X.toLowerCase()
   */
  private tryEvalStringChain(code: string, vars: Record<string, Object>): Object | undefined {
    // 提取根变量
    const rootMatch = code.match(/^(\w+)((?:\.\w+\([^)]*\))+)$/);
    if (!rootMatch) return undefined;
    const root = vars[rootMatch[1]];
    if (typeof root !== 'string') return undefined;
    let cur: string = root as string;
    const chain = rootMatch[2];
    // 逐步解析方法调用，支持正则字面量
    let i = 0;
    while (i < chain.length) {
      if (chain[i] !== '.') return undefined;
      const dot = i;
      const openParen = chain.indexOf('(', dot);
      if (openParen < 0) return undefined;
      const method = chain.substring(dot + 1, openParen);
      // 找匹配的右括号（考虑字符串、正则字面量）
      let depth = 1;
      let j = openParen + 1;
      let inStr: string | null = null;
      let inRegex = false;
      while (j < chain.length && depth > 0) {
        const c = chain[j];
        if (inStr) {
          if (c === '\\') { j += 2; continue; }
          if (c === inStr) inStr = null;
        } else if (inRegex) {
          if (c === '\\') { j += 2; continue; }
          if (c === '/') inRegex = false;
        } else {
          if (c === "'" || c === '"') inStr = c;
          else if (c === '/' && chain[j - 1] === '(' || (c === '/' && chain[j - 1] === ',')) inRegex = true;
          else if (c === '(') depth++;
          else if (c === ')') depth--;
        }
        if (depth === 0) break;
        j++;
      }
      if (depth !== 0) return undefined;
      const argsStr = chain.substring(openParen + 1, j).trim();
      // 解析参数
      const args = this.parseChainArgs(argsStr);
      switch (method) {
        case 'trim': cur = cur.trim(); break;
        case 'toLowerCase': cur = cur.toLowerCase(); break;
        case 'toUpperCase': cur = cur.toUpperCase(); break;
        case 'replace': {
          if (args.length < 2) return undefined;
          const a0 = args[0];
          const a1 = String(args[1]);
          if (typeof a0 === 'string') {
            // /pattern/flags -> RegExp
            const re = a0.match(/^\/(.+)\/([gimsuy]*)$/);
            if (re) {
              try { cur = cur.replace(new RegExp(re[1], re[2]), a1); }
              catch { return undefined; }
            } else {
              cur = cur.replace(a0, a1);
            }
          }
          break;
        }
        default: return undefined;
      }
      i = j + 1;
    }
    return cur;
  }

  private parseChainArgs(argsStr: string): Object[] {
    const args: Object[] = [];
    if (!argsStr.trim()) return args;
    let cur = '';
    let inStr: string | null = null;
    let inRegex = false;
    let depth = 0;
    for (let i = 0; i < argsStr.length; i++) {
      const c = argsStr[i];
      const prev = i > 0 ? argsStr[i - 1] : '';
      if (inStr) {
        cur += c;
        if (c === '\\') { cur += argsStr[i + 1] || ''; i++; continue; }
        if (c === inStr) inStr = null;
      } else if (inRegex) {
        cur += c;
        if (c === '\\') { cur += argsStr[i + 1] || ''; i++; continue; }
        if (c === '/') {
          // 吃掉 flags
          let k = i + 1;
          while (k < argsStr.length && /[gimsuy]/.test(argsStr[k])) {
            cur += argsStr[k];
            k++;
          }
          i = k - 1;
          inRegex = false;
        }
      } else {
        if (c === "'" || c === '"') { inStr = c; cur += c; }
        else if (c === '/' && (cur.trim() === '' || prev === ',')) { inRegex = true; cur += c; }
        else if (c === '(') { depth++; cur += c; }
        else if (c === ')') { depth--; cur += c; }
        else if (c === ',' && depth === 0) {
          args.push(this.parseChainArgValue(cur.trim()));
          cur = '';
        } else cur += c;
      }
    }
    if (cur.trim()) args.push(this.parseChainArgValue(cur.trim()));
    return args;
  }

  private parseChainArgValue(val: string): Object {
    if ((val.startsWith("'") && val.endsWith("'")) ||
        (val.startsWith('"') && val.endsWith('"'))) {
      return val.substring(1, val.length - 1);
    }
    // 保留 /regex/flags 字面量原样
    if (/^\/.+\/[gimsuy]*$/.test(val)) return val;
    if (val === 'true') return true;
    if (val === 'false') return false;
    const num = parseFloat(val);
    if (!Number.isNaN(num)) return num;
    return val;
  }

  async health(): Promise<boolean> {
    try {
      await HttpClient.get(`${this.baseUrl}/health`);
      this.proxyAvailable = true;
      return true;
    } catch {
      this.proxyAvailable = false;
      return false;
    }
  }
}

let globalExecutor: JSExecutor | null = null;

export function getJSExecutor(config?: JSExecutorConfig): JSExecutor {
  if (!globalExecutor) {
    globalExecutor = new JSExecutor(config);
  }
  return globalExecutor;
}

/**
 * DOM Shim Document - 简化的 document 对象
 */
class DOMShimDocument {
  private root: HTMLElement;

  constructor(root: HTMLElement) {
    this.root = root;
  }

  querySelector(selector: string): DOMShimElement | null {
    const elements = SimpleCSSSelector.querySelectorAll(this.root, selector);
    return elements.length > 0 ? new DOMShimElement(elements[0]) : null;
  }

  querySelectorAll(selector: string): DOMShimElement[] {
    const elements = SimpleCSSSelector.querySelectorAll(this.root, selector);
    return elements.map((el) => new DOMShimElement(el));
  }
}

/**
 * DOM Shim Element - 简化的 DOM 元素包装
 * 用于书源 JS 规则中的 document.querySelector 等操作
 */
class DOMShimElement {
  private element: HTMLElement;

  constructor(element: HTMLElement) {
    this.element = element;
  }

  querySelector(selector: string): DOMShimElement | null {
    const elements = SimpleCSSSelector.querySelectorAll(this.element, selector);
    return elements.length > 0 ? new DOMShimElement(elements[0]) : null;
  }

  querySelectorAll(selector: string): DOMShimElement[] {
    const elements = SimpleCSSSelector.querySelectorAll(this.element, selector);
    return elements.map((el) => new DOMShimElement(el));
  }

  cloneNode(deep: boolean): DOMShimElement {
    // 简化：直接返回新实例（HTML 已解析，不需要深拷贝）
    return new DOMShimElement(this.element);
  }

  remove(): void {
    // 从父节点移除（修改原始 HTMLElement）
    if (this.element.parent) {
      const parent = this.element.parent;
      const idx = parent.children.indexOf(this.element);
      if (idx >= 0) {
        parent.children.splice(idx, 1);
      }
    }
  }

  get innerText(): string {
    return SimpleCSSSelector.getText(this.element);
  }

  get innerHTML(): string {
    return SimpleCSSSelector.innerHTML(this.element);
  }

  get outerHTML(): string {
    return SimpleCSSSelector.outerHTML(this.element);
  }
}
