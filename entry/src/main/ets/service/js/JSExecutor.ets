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
import { SimpleCSSSelector, HTMLElement } from '../rule/SimpleCSSSelector';
import { getJavaBridge } from '../rule/JavaBridge';
import { getCookieManager } from '../rule/CookieManager';
import { getSourceContext } from '../rule/SourceContext';
import { getJsoup } from '../rule/JsoupBridge';
import { getWebViewJSEngine } from './WebViewJSEngine';

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

    // 解开 IIFE 包装：(function(){...})()  →  函数体
    code = this.unwrapIIFE(code);

    // 检测是否需要 java 桥（书源 JS 规则常用 java.connect/ajax/log）
    const needsJava = code.includes('java.connect') ||
                      code.includes('java.ajax') ||
                      code.includes('java.log') ||
                      code.includes('java.get') ||
                      code.includes('java.put') ||
                      code.includes('java.webView');

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

    // 优先：本地脚本求值（async，原生支持 await java.ajax / java.connect 与多行赋值）
    // 这是 Legado 书源最常见的"拼 URL → ajax → 取新页面"模式
    if (needsJava && (code.includes('java.ajax') || code.includes('java.connect'))) {
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
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 显式 return
      if (/^return\b/.test(line)) {
        const expr = line.replace(/^return\s*/, '').trim() || '""';
        const v = await this.evalExprAsync(expr, localVars);
        if (v === undefined) {
          const r1: ScriptStmtResult = { value: undefined, returned: true };
          return r1;
        }
        const r2: ScriptStmtResult = { value: v, returned: true };
        return r2;
      }
      // if (cond) stmt
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
        continue;
      }
      // var/let/const X = expr
      const declMatch = line.match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      if (declMatch) {
        const v = await this.evalExprAsync(declMatch[2], localVars);
        if (v === undefined) {
          const r: ScriptStmtResult = { value: undefined, returned: false };
          return r;
        }
        localVars[declMatch[1]] = v;
        lastValue = v;
        continue;
      }
      // X = expr
      const assignMatch = line.match(/^(\w+)\s*=\s*(.+)$/);
      if (assignMatch) {
        const v = await this.evalExprAsync(assignMatch[2], localVars);
        if (v === undefined) {
          const r: ScriptStmtResult = { value: undefined, returned: false };
          return r;
        }
        localVars[assignMatch[1]] = v;
        lastValue = v;
        continue;
      }
      // 单纯表达式
      const v = await this.evalExprAsync(line, localVars);
      if (v === undefined) {
        const r: ScriptStmtResult = { value: undefined, returned: false };
        return r;
      }
      lastValue = v;
    }
    const r: ScriptStmtResult = { value: lastValue, returned: false };
    return r;
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

  /** 把脚本切成顶层语句（按 ;/\n，但忽略字符串/正则中的分号） */
  private splitStatements(code: string): string[] {
    const out: string[] = [];
    let buf = '';
    let inStr: string | null = null;
    for (let i = 0; i < code.length; i++) {
      const c = code[i];
      if (inStr) {
        buf += c;
        if (c === '\\' && i + 1 < code.length) { buf += code[i + 1]; i++; continue; }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === "'" || c === '"' || c === '`') { inStr = c; buf += c; continue; }
      if (c === ';' || c === '\n') {
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

    // 处理 var 声明
    const localVars: Record<string, Object> = {};
    const ctxKeys = Object.keys(ctx);
    for (const ck of ctxKeys) localVars[ck] = ctx[ck];
    for (let i = 0; i < lines.length - 1; i++) {
      const varMatch = lines[i].match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      if (varMatch) {
        const val = this.tryLocalEval(varMatch[2], localVars);
        if (val !== undefined) {
          localVars[varMatch[1]] = val;
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
    const lines = code.split(/[;\n]/).map((l) => l.trim()).filter((l) => l.length > 0);
    if (lines.length < 2) return undefined;

    const localVars: Record<string, Object> = {};
    const ctxKeys = Object.keys(ctx);
    for (const ck of ctxKeys) localVars[ck] = ctx[ck];
    for (let i = 0; i < lines.length - 1; i++) {
      const varMatch = lines[i].match(/^(?:var|let|const)\s+(\w+)\s*=\s*(.+)$/);
      if (varMatch) {
        const val = this.tryLocalEval(varMatch[2], localVars);
        if (val !== undefined) {
          localVars[varMatch[1]] = val;
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
