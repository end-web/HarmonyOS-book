/**
 * AnalyzeRule - 统一规则分析器（对齐 Legado AnalyzeRule.kt）
 *
 * 支持：
 *  - JSON 模式（$. / @Json:）
 *  - CSS/JSoup 模式（Default）
 *  - JavaScript 模式（@js: / <js>...</js>）
 *  - XPath 模式（@xpath: / //）
 *  - 正则模式（Regex / :regex:）
 *  - 操作符：|| && %%
 *  - ##pattern##replacement（全替换）/ ##pattern##replacement### 取首条
 *  - @put:{key:value} 存变量 / @get:{key} 取变量
 *  - {{expr}} 内嵌 JS / {$.path} 内嵌 JSONPath
 *  - 属性后缀：@text / @textNodes / @html / @outerHtml / @ownText / @src / @href / @attr(xxx)
 */

import { RuleAnalyzer } from './RuleAnalyzer';
import { jsonPath } from './JSONPath';
import { getJSExecutor } from '../js/JSExecutor';
import { SimpleCSSSelector, HTMLElement } from './SimpleCSSSelector';
import { SimpleXPath } from './SimpleXPath';
import { AnalyzeByRegex } from './AnalyzeByRegex';

export enum RuleMode {
  Json = 'Json',
  Default = 'Default',
  XPath = 'XPath',
  Regex = 'Regex',
  Js = 'Js',
}

export interface BookContext {
  origin: string;
  bookUrl: string;
  name: string;
  author?: string;
}

export class AnalyzeContext {
  variables: Record<string, string> = {};
  baseUrl: string = '';
  redirectUrl: string = '';
  book: BookContext | null = null;
  chapter: Record<string, Object> | null = null;

  constructor(baseUrl: string = '', variables?: Record<string, string>) {
    this.baseUrl = baseUrl;
    this.redirectUrl = baseUrl;
    if (variables) {
      this.variables = variables;
    }
  }
}

interface SourceRule {
  rule: string;
  mode: RuleMode;
  replaceRegex: string;
  replacement: string;
  replaceFirst: boolean;
  putMap: Record<string, string>;
}

const PUT_PATTERN = /@put:\{([^}]+)\}/g;
const GET_PATTERN = /@get:\{([^}]+)\}/g;
const EVAL_PATTERN = /\{\{([\s\S]+?)\}\}/g;
const JSON_EVAL_PATTERN = /\{\$\.([^}]+)\}/g;
const CSS_EVAL_PATTERN = /\{\{@@([^}]+)\}\}/g;

// 规则缓存（LRU 16 条）
const ruleCache = new Map<string, SourceRule[]>();
const CACHE_LIMIT = 16;

function cacheRule(key: string, rules: SourceRule[]): void {
  if (ruleCache.size >= CACHE_LIMIT) {
    const iter = ruleCache.keys();
    const first = iter.next();
    if (!first.done) {
      const firstKey: string = first.value as string;
      ruleCache.delete(firstKey);
    }
  }
  ruleCache.set(key, rules);
}

interface JsTagPart {
  start: number;
  end: number;
  code: string;
}

export class AnalyzeRule {
  private content: Object;
  private context: AnalyzeContext;
  private mode: RuleMode = RuleMode.Default;
  private isJSON: boolean = false;

  constructor(content: Object, context?: AnalyzeContext) {
    this.content = content;
    this.context = context ?? new AnalyzeContext();
    this.isJSON = this.detectIsJson(content);
  }

  setContent(content: Object): void {
    this.content = content;
    this.isJSON = this.detectIsJson(content);
  }

  setBaseUrl(url: string): void {
    this.context.baseUrl = url;
  }

  getVariables(): Record<string, string> {
    return this.context.variables;
  }

  // ──────────────────── 公开 API ────────────────────

  async getString(rule: string): Promise<string | null> {
    if (!rule) return null;

    const orAnalyzer = new RuleAnalyzer(rule);
    const orParts = orAnalyzer.splitRule('||');
    if (orParts.length > 1 && orAnalyzer.elementsType === '||') {
      for (const part of orParts) {
        const sub = new AnalyzeRule(this.content, this.context);
        const v = await sub.getStringSingle(part);
        if (v && v.length > 0) return v;
      }
      return null;
    }

    return this.getStringSingle(rule);
  }

  private async getStringSingle(rule: string): Promise<string | null> {
    if (!rule) return null;
    const ruleList = this.splitSourceRule(rule);
    if (ruleList.length === 0) return null;

    let result: Object = this.content;
    for (let i = 0; i < ruleList.length; i++) {
      const sr = ruleList[i];
      await this.applyPut(sr.putMap, result);
      const effective = await this.makeUpRule(sr.rule, result);
      if (!effective) continue;
      if (this.isPureTemplate(sr.rule)) {
        result = effective;
        continue;
      }
      const raw = await this.executeByMode(effective, sr.mode, result);
      if (raw === null || raw === undefined) return null;
      let str: string;
      if (Array.isArray(raw)) {
        str = (raw as Object[]).map((x: Object): string => AnalyzeRule.safeStringify(x)).join('\n');
      } else {
        str = AnalyzeRule.safeStringify(raw);
      }
      result = this.applyReplace(str, sr);
    }
    const resultStr = AnalyzeRule.safeStringify(result);
    if (!resultStr && ruleList.some((sr) => sr.replaceRegex)) return '';
    if (!resultStr) return null;
    return AnalyzeRule.unescapeHtml(resultStr);
  }

  /** HTML 实体解转义：&amp; &lt; &gt; &quot; &apos; &nbsp; &#39; &#x2F; 等 */
  static unescapeHtml(s: string): string {
    if (!s || s.indexOf('&') < 0) return s;
    return s
      .replace(/&#x([0-9a-fA-F]+);/g, (_m: string, hex: string): string => {
        try { return String.fromCodePoint(parseInt(hex, 16)); } catch { return _m; }
      })
      .replace(/&#(\d+);/g, (_m: string, dec: string): string => {
        try { return String.fromCodePoint(parseInt(dec, 10)); } catch { return _m; }
      })
      .replace(/&nbsp;/g, ' ')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  /** 安全地把任意值转成字符串：原始类型直接转，普通对象走 JSON.stringify,
   *  避免 String({}) 产出 "[object Object]" 后被当作变量值/URL 片段使用 */
  private static safeStringify(v: Object | string | number | boolean | null | undefined): string {
    if (v === null || v === undefined) return '';
    const t = typeof v;
    if (t === 'string') return v as string;
    if (t === 'number' || t === 'boolean') return String(v);
    // Array / Object：避免 [object Object]
    try {
      const s = String(v);
      if (s !== '[object Object]') return s;
      return JSON.stringify(v);
    } catch {
      return '';
    }
  }

  private isPureTemplate(rule: string): boolean {
    const stripped = rule
      .replace(/@get:\{[^}]+\}/g, '')
      .replace(/@put:\{[^}]+\}/g, '')
      .replace(/\{\{[\s\S]+?\}\}/g, '')
      .replace(/\{\$\.[^}]+\}/g, '');
    return !/[\.\$\[@]|\/\//.test(stripped);
  }

  async getStringList(rule: string): Promise<string[]> {
    if (!rule) return [];

    const analyzer = new RuleAnalyzer(rule);
    const rules = analyzer.splitRule('||', '&&', '%%');

    if (rules.length === 1) {
      return this.getStringListSingle(rule);
    }

    const results: string[][] = [];
    for (const r of rules) {
      const sub = new AnalyzeRule(this.content, this.context);
      const temp = await sub.getStringListSingle(r);
      if (temp.length > 0) {
        results.push(temp);
        if (analyzer.elementsType === '||') break;
      }
    }

    if (results.length === 0) return [];

    if (analyzer.elementsType === '%%') {
      const merged: string[] = [];
      const maxLen = Math.max(...results.map((r) => r.length));
      for (let i = 0; i < maxLen; i++) {
        for (const tmp of results) {
          if (i < tmp.length) merged.push(tmp[i]);
        }
      }
      return merged;
    }

    if (analyzer.elementsType === '&&') {
      let result: Object = this.content;
      for (const r of rules) {
        const sub = new AnalyzeRule(result, this.context);
        const temp = await sub.getStringListSingle(r);
        if (!temp || temp.length === 0) return [];
        result = temp;
      }
      return result as string[];
    }

    return results.flat();
  }

  async getElements(rule: string): Promise<Object[]> {
    if (!rule) return [];

    const analyzer = new RuleAnalyzer(rule);
    const parts = analyzer.splitRule('||', '&&');

    if (parts.length > 1 && analyzer.elementsType === '||') {
      for (const part of parts) {
        const result = await this.getElementsSingle(part);
        if (result.length > 0) return result;
      }
      return [];
    }

    if (parts.length > 1 && analyzer.elementsType === '&&') {
      let elements: Object[] = [this.content];
      for (const part of parts) {
        const nextElements: Object[] = [];
        for (const el of elements) {
          const sub = new AnalyzeRule(el, this.context);
          const found = await sub.getElementsSingle(part);
          for (const f of found) nextElements.push(f);
        }
        if (nextElements.length === 0) return [];
        elements = nextElements;
      }
      return elements;
    }

    return this.getElementsSingle(rule);
  }

  private async getElementsSingle(rule: string): Promise<Object[]> {
    this.detectMode(rule);

    // 处理反转标记
    let actualRule = rule;
    let reverse = false;
    if (actualRule.startsWith('-')) {
      reverse = true;
      actualRule = actualRule.substring(1);
    } else if (actualRule.startsWith('+')) {
      actualRule = actualRule.substring(1);
    }

    let result: Object[];

    if (this.mode === RuleMode.Json) {
      const cleanRule = this.stripModePrefix(actualRule);
      const data: Object = typeof this.content === 'string'
        ? JSON.parse(this.content) as Object : this.content;
      const list = jsonPath(data, cleanRule);
      result = Array.isArray(list) ? list : (list ? [list] : []);
    } else if (this.mode === RuleMode.Default) {
      const html = typeof this.content === 'string'
        ? this.content : JSON.stringify(this.content);
      const root = SimpleCSSSelector.parseHTML(html);
      const cleanRule = this.stripModePrefix(actualRule);
      // Legado 对齐：单段内用 @ 拆分多级 select（如 #list@li 表示 #list 下面再 select li）
      // 没有 @ 时退化为整段 querySelectorAll
      const segments = AnalyzeRule.splitTopLevelAt(cleanRule);
      let elements: HTMLElement[] = [root];
      for (const seg of segments) {
        const segTrim = seg.trim();
        if (!segTrim) continue;
        const next: HTMLElement[] = [];
        for (const el of elements) {
          const found = SimpleCSSSelector.querySelectorAll(el, segTrim);
          for (const f of found) next.push(f);
        }
        elements = next;
        if (elements.length === 0) break;
      }
      // 保留原始节点引用（outerHTML 序列化），方便子级 AnalyzeRule 重新解析
      result = elements.map((el) => SimpleCSSSelector.outerHTML(el));
    } else if (this.mode === RuleMode.XPath) {
      const html = typeof this.content === 'string'
        ? this.content : JSON.stringify(this.content);
      const root = SimpleCSSSelector.parseHTML(html);
      const cleanRule = this.stripModePrefix(actualRule);
      const elements = SimpleXPath.evaluateNodes(root, cleanRule);
      result = elements.map((el) => SimpleCSSSelector.outerHTML(el));
    } else if (this.mode === RuleMode.Js) {
      const jsResult = await this.executeJs(actualRule);
      if (Array.isArray(jsResult)) {
        result = jsResult as Object[];
      } else {
        result = jsResult ? [jsResult] : [];
      }
    } else if (this.mode === RuleMode.Regex) {
      const content = String(this.content);
      const cleanRule = this.stripModePrefix(actualRule);
      const elements = AnalyzeByRegex.getElements(content, [cleanRule]);
      result = elements.map((groups) => groups[0]);
    } else {
      result = [];
    }

    if (reverse) result.reverse();
    return result;
  }

  /**
   * 按顶层 @ 切分（忽略 [..] / (..) 内的 @），用于 CSS 模式的多级 select。
   * 例：#list@li / div.item@a@text 切成 ['#list','li'] / ['div.item','a','text']
   */
  private static splitTopLevelAt(rule: string): string[] {
    const out: string[] = [];
    let buf = '';
    let depth = 0;
    let inStr: string | null = null;
    for (let i = 0; i < rule.length; i++) {
      const c = rule[i];
      if (inStr) {
        buf += c;
        if (c === '\\' && i + 1 < rule.length) { buf += rule[i + 1]; i++; continue; }
        if (c === inStr) inStr = null;
        continue;
      }
      if (c === '"' || c === "'") { inStr = c; buf += c; continue; }
      if (c === '(' || c === '[') { depth++; buf += c; continue; }
      if (c === ')' || c === ']') { depth--; buf += c; continue; }
      if (c === '@' && depth === 0) {
        out.push(buf);
        buf = '';
        continue;
      }
      buf += c;
    }
    out.push(buf);
    return out;
  }

  private stripModePrefix(rule: string): string {
    const lower = rule.toLowerCase();
    if (lower.startsWith('@json:')) return rule.substring(6);
    if (lower.startsWith('json:')) return rule.substring(5);
    if (lower.startsWith('@xpath:')) return rule.substring(7);
    if (lower.startsWith('xpath:')) return rule.substring(6);
    if (lower.startsWith('@css:')) return rule.substring(5);
    if (rule.startsWith('@@')) return rule.substring(2);
    if (lower.startsWith('@js:')) return rule.substring(4);
    if (lower.startsWith('js:')) return rule.substring(3);
    return rule;
  }

  // ──────────────────── 规则分解 ────────────────────

  private splitSourceRule(ruleStr: string): SourceRule[] {
    if (!ruleStr) return [];

    // 缓存查找
    const cached = ruleCache.get(ruleStr);
    if (cached) return cached;

    const list: SourceRule[] = [];
    const jsTagRegex = /<js>([\s\S]+?)<\/js>/gi;
    const atJsRegex = /^@?js:/i;

    if (atJsRegex.test(ruleStr.trim())) {
      list.push(this.buildSourceRule(ruleStr, RuleMode.Js));
      cacheRule(ruleStr, list);
      return list;
    }

    const jsParts: JsTagPart[] = [];
    let m: RegExpExecArray | null = jsTagRegex.exec(ruleStr);
    while (m !== null) {
      const part: JsTagPart = { start: m.index, end: jsTagRegex.lastIndex, code: m[1] };
      jsParts.push(part);
      m = jsTagRegex.exec(ruleStr);
    }

    if (jsParts.length > 0) {
      let pos = 0;
      for (const part of jsParts) {
        if (part.start > pos) {
          const before = ruleStr.substring(pos, part.start).trim();
          if (before) list.push(this.buildSourceRule(before, RuleMode.Default));
        }
        list.push(this.buildSourceRule(part.code, RuleMode.Js));
        pos = part.end;
      }
      if (pos < ruleStr.length) {
        const after = ruleStr.substring(pos).trim();
        if (after) list.push(this.buildSourceRule(after, RuleMode.Default));
      }
      cacheRule(ruleStr, list);
      return list;
    }

    const chainParts = this.splitChainRule(ruleStr);
    if (chainParts.length > 1) {
      for (const cp of chainParts) {
        const sr = this.buildSourceRule(cp.trim(), RuleMode.Default);
        list.push(sr);
      }
      cacheRule(ruleStr, list);
      return list;
    }

    list.push(this.buildSourceRule(ruleStr, RuleMode.Default));
    cacheRule(ruleStr, list);
    return list;
  }

  private splitChainRule(ruleStr: string): string[] {
    const modePattern = /@(js|css|json|xpath):/gi;
    const parts: string[] = [];
    let lastEnd = 0;
    let match: RegExpExecArray | null = modePattern.exec(ruleStr);
    while (match !== null) {
      if (match.index > 0) {
        const before = ruleStr.substring(lastEnd, match.index);
        if (before.trim()) {
          parts.push(before);
        }
        lastEnd = match.index;
      }
      match = modePattern.exec(ruleStr);
    }
    if (lastEnd < ruleStr.length) {
      const remaining = ruleStr.substring(lastEnd);
      if (remaining.trim()) {
        parts.push(remaining);
      }
    }
    return parts;
  }

  private buildSourceRule(ruleStr: string, defaultMode: RuleMode): SourceRule {
    const sr: SourceRule = {
      rule: ruleStr,
      mode: defaultMode,
      replaceRegex: '',
      replacement: '',
      replaceFirst: false,
      putMap: {},
    };

    let rule = ruleStr.replace(PUT_PATTERN, (_match: string, json: string): string => {
      try {
        const obj = JSON.parse(`{${json}}`) as Record<string, string>;
        const keys = Object.keys(obj);
        for (const k of keys) sr.putMap[k] = obj[k];
      } catch { /* ignore */ }
      return '';
    }).trim();

    const lower = rule.toLowerCase();
    if (lower.startsWith('@json:') || lower.startsWith('json:')) {
      sr.mode = RuleMode.Json;
      rule = rule.substring(lower.startsWith('@json:') ? 6 : 5);
    } else if (lower.startsWith('@xpath:') || lower.startsWith('xpath:')) {
      sr.mode = RuleMode.XPath;
      rule = rule.substring(lower.startsWith('@xpath:') ? 7 : 6);
    } else if (lower.startsWith('@css:') || lower.startsWith('@@')) {
      sr.mode = RuleMode.Default;
      rule = lower.startsWith('@@') ? rule.substring(2) : rule.substring(5);
    } else if (lower.startsWith('@js:') || lower.startsWith('js:')) {
      sr.mode = RuleMode.Js;
      rule = rule.substring(lower.startsWith('@js:') ? 4 : 3);
    } else if (rule.startsWith('$.') || rule.startsWith('$[')) {
      sr.mode = RuleMode.Json;
    } else if (rule.startsWith('//')) {
      sr.mode = RuleMode.XPath;
    } else if (lower.startsWith(':regex:')) {
      sr.mode = RuleMode.Regex;
      rule = rule.substring(7);
    } else if (defaultMode !== RuleMode.Js) {
      if (this.isJSON) {
        sr.mode = RuleMode.Json;
      } else {
        sr.mode = RuleMode.Default;
      }
    }

    // 分离 ##pattern##replacement
    const hashIdx = rule.indexOf('##');
    if (hashIdx > 0) {
      const afterHash = rule.substring(hashIdx + 2);
      rule = rule.substring(0, hashIdx);
      const parts = afterHash.split('##');
      sr.replaceRegex = parts[0] || '';
      sr.replacement = parts.length > 1 ? parts[1] : '';
      sr.replaceFirst = parts.length > 2;
    }

    sr.rule = rule.trim();
    return sr;
  }

  // ──────────────────── makeUpRule ────────────────────

  private async makeUpRule(rule: string, result: Object): Promise<string> {
    if (!rule) return rule;
    let out = rule;

    out = out.replace(GET_PATTERN, (_match: string, key: string): string => {
      const vars = this.context.variables;
      return (vars && vars[key] !== undefined) ? vars[key] : '';
    });

    out = out.replace(JSON_EVAL_PATTERN, (_match: string, path: string): string => {
      try {
        const data: Object = typeof result === 'string'
          ? JSON.parse(result as string) as Object : result;
        const val = jsonPath(data, '$.' + path);
        if (val === null || val === undefined) return '';
        return Array.isArray(val) ? (val as Object[]).map((x: Object) => String(x)).join('') : String(val);
      } catch {
        return '';
      }
    });

    // 处理 {{@@...}} CSS 规则内嵌求值
    const cssEvalMatches: Array<[string, string]> = [];
    out = out.replace(CSS_EVAL_PATTERN, (whole: string, cssRule: string): string => {
      cssEvalMatches.push([whole, cssRule]);
      return whole;
    });

    if (cssEvalMatches.length > 0) {
      for (const pair of cssEvalMatches) {
        try {
          const sub = new AnalyzeRule(result, this.context);
          const v = await sub.getString(pair[1]);
          if (v !== null && v.length > 0) {
            out = out.replace(pair[0], v);
          }
        } catch { /* keep original */ }
      }
    }

    const evalMatches: Array<[string, string]> = [];
    out = out.replace(EVAL_PATTERN, (whole: string, inner: string): string => {
      const trimmed = inner.trim();
      // 跳过已处理的 {{@@...}}
      if (trimmed.startsWith('@@')) return whole;
      const getMatch = trimmed.match(/^@get:\{([^}]+)\}$/);
      if (getMatch) {
        const vars = this.context.variables;
        return (vars && vars[getMatch[1]] !== undefined) ? vars[getMatch[1]] : '';
      }
      if (trimmed.startsWith('$.') || trimmed.startsWith('$[')) {
        try {
          const data: Object = typeof result === 'string'
            ? JSON.parse(result as string) as Object : result;
          const val = jsonPath(data, trimmed);
          if (val === null || val === undefined) return whole;
          return Array.isArray(val) ? (val as Object[]).map((x: Object) => String(x)).join('') : String(val);
        } catch {
          return whole;
        }
      }
      evalMatches.push([whole, trimmed]);
      return whole;
    });

    if (evalMatches.length > 0) {
      const executor = getJSExecutor();
      const ctx: Record<string, Object> = {};
      ctx['result'] = result;
      ctx['baseUrl'] = this.context.baseUrl || '';
      ctx['src'] = this.content;
      if (this.context.book) ctx['book'] = this.context.book;
      if (this.context.chapter) ctx['chapter'] = this.context.chapter;
      if (this.context.variables) {
        const vars = this.context.variables;
        for (const k of Object.keys(vars)) ctx[k] = vars[k];
      }
      for (const pair of evalMatches) {
        try {
          const v = await executor.eval(pair[1], ctx);
          if (v !== null && v !== undefined) {
            out = out.replace(pair[0], String(v));
          }
        } catch { /* keep original */ }
      }
    }

    return out;
  }

  // ──────────────────── @put 执行 ────────────────────

  private async applyPut(putMap: Record<string, string>, result: Object): Promise<void> {
    const keys = Object.keys(putMap);
    if (keys.length === 0) return;
    if (!this.context.variables) {
      this.context.variables = {};
    }
    for (const key of keys) {
      const valRule = putMap[key];
      let stored: string = '';
      if (valRule && (valRule.startsWith('$.') || valRule.startsWith('@css:')
        || valRule.startsWith('@@') || valRule.startsWith('@json:')
        || valRule.startsWith('@xpath:') || valRule.startsWith('//'))) {
        try {
          const sub = new AnalyzeRule(result, this.context);
          const v = await sub.getString(valRule);
          stored = v ?? '';
        } catch {
          stored = valRule;
        }
      } else {
        stored = valRule ?? '';
      }
      stored = AnalyzeRule.safeStringify(stored);
      if (stored && stored !== '[object Object]' && this.context.variables) {
        this.context.variables[key] = stored;
      }
    }
  }

  // ──────────────────── ## 替换 ────────────────────

  private applyReplace(str: string, sr: SourceRule): string {
    if (!sr.replaceRegex) return str;
    // 处理 replacement 中的 \n / \r / \t / \\ 转义
    const replacement = AnalyzeRule.unescapeReplacement(sr.replacement);
    try {
      if (sr.replaceFirst) {
        const regex = new RegExp(sr.replaceRegex);
        return str.replace(regex, replacement);
      }
      const regex = new RegExp(sr.replaceRegex, 'g');
      return str.replace(regex, replacement);
    } catch {
      return str;
    }
  }

  private static unescapeReplacement(s: string): string {
    if (!s || s.indexOf('\\') < 0) return s;
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      if (c === '\\' && i + 1 < s.length) {
        const n = s.charAt(i + 1);
        if (n === 'n') { out += '\n'; i++; continue; }
        if (n === 'r') { out += '\r'; i++; continue; }
        if (n === 't') { out += '\t'; i++; continue; }
        if (n === '\\') { out += '\\'; i++; continue; }
      }
      out += c;
    }
    return out;
  }

  // ──────────────────── 执行分发 ────────────────────

  private async executeByMode(rule: string, mode: RuleMode, result: Object): Promise<Object | null> {
    switch (mode) {
      case RuleMode.Json:
        return this.executeJson(rule, result);
      case RuleMode.Js:
        return this.executeJs(rule, result);
      case RuleMode.Default:
        return this.executeDefault(rule, result);
      case RuleMode.XPath:
        return this.executeXPath(rule, result);
      case RuleMode.Regex:
        return this.executeRegex(rule, result);
      default:
        return null;
    }
  }

  /** 链式规则中，每段的输入可能是上一段产出的字符串/数组/对象，按各 mode 期望统一成可消费形式 */
  private resolveChainSource(chainResult: Object): Object {
    // 链未启动（result === this.content）或为空对象，回落到原始 content
    if (chainResult === this.content) return this.content;
    if (chainResult === null || chainResult === undefined) return this.content;
    // 数组多结果时，让 CSS/XPath/JSON 等针对每个元素取值——这里先取首元素或拼接
    if (Array.isArray(chainResult)) {
      const arr = chainResult as Object[];
      if (arr.length === 0) return this.content;
      // 全字符串数组按换行拼接（兼容 HTML 片段连续解析）
      if (arr.every((x: Object) => typeof x === 'string')) {
        return (arr as string[]).join('\n');
      }
      return arr[0];
    }
    return chainResult;
  }

  private executeJson(rule: string, chainResult: Object): Object | null {
    let cleanRule = rule;
    const lower = cleanRule.toLowerCase();
    if (lower.startsWith('json:')) cleanRule = cleanRule.substring(5);
    if (lower.startsWith('@json:')) cleanRule = cleanRule.substring(6);

    try {
      const source = this.resolveChainSource(chainResult);
      const data: Object = typeof source === 'string'
        ? JSON.parse(source) as Object : source;
      const result = jsonPath(data, cleanRule);
      if (!result || (Array.isArray(result) && result.length === 0)) return null;
      if (Array.isArray(result) && result.length === 1) return result[0];
      return result;
    } catch {
      return null;
    }
  }

  private async executeJs(rule: string, chainResult?: Object): Promise<Object | null> {
    let code = rule;
    const lower = code.toLowerCase();
    if (lower.startsWith('@js:')) code = code.substring(4);
    else if (lower.startsWith('js:')) code = code.substring(3);
    else if (code.includes('<js>')) {
      const start = code.indexOf('<js>') + 4;
      const end = code.indexOf('</js>');
      if (end > start) code = code.substring(start, end);
    }

    const needsWrap = code.includes('yp_url') || /(?:^|[\s;])url\s*=/.test(code);
    if (needsWrap) {
      code = 'var yp_url, url;\n' + code + '\n' +
        'if(typeof yp_url !== "undefined" && yp_url) yp_url;\n' +
        'else if(typeof url !== "undefined" && url) url;\n';
    }

    const executor = getJSExecutor();
    const ctx: Record<string, Object> = {};
    const raw = chainResult !== undefined ? chainResult : this.content;
    // Legado 兼容：result 传给 JS 时确保是 string（书源规则常用 result.split 等字符串方法）
    ctx['result'] = typeof raw === 'string' ? raw : JSON.stringify(raw);
    ctx['baseUrl'] = this.context.baseUrl || '';
    ctx['src'] = typeof this.content === 'string' ? this.content : JSON.stringify(this.content);
    if (this.context.book) ctx['book'] = this.context.book;
    if (this.context.chapter) ctx['chapter'] = this.context.chapter;
    if (this.context.variables) {
      const vars = this.context.variables;
      for (const k of Object.keys(vars)) ctx[k] = vars[k];
    }
    try {
      return await executor.eval(code, ctx);
    } catch {
      return null;
    }
  }

  private executeDefault(rule: string, chainResult: Object): Object | null {
    const source = this.resolveChainSource(chainResult);
    const html = typeof source === 'string'
      ? source : JSON.stringify(source);

    const root = SimpleCSSSelector.parseHTML(html);

    let cleanRule = rule;
    if (cleanRule.toLowerCase().startsWith('@css:')) cleanRule = cleanRule.substring(5);
    if (cleanRule.startsWith('@@')) cleanRule = cleanRule.substring(2);

    // Legado 对齐：用 @ 切分多级 select / 末尾 attr name
    const parts = AnalyzeRule.splitTopLevelAt(cleanRule).map((s) => s.trim()).filter((s) => s.length > 0);

    if (parts.length === 0) return null;

    if (parts.length === 1) {
      const elements = SimpleCSSSelector.querySelectorAll(root, parts[0]);
      if (elements.length === 0) return null;
      // 单段：先取 text，没有时 fallback 到把规则末尾段当 attr name。
      // 例：'a' 规则若没文本，尝试当 a 标签直接取（保持现状行为）
      const texts = elements.map((el) => SimpleCSSSelector.getText(el)).filter((t) => t.length > 0);
      if (texts.length > 0) return texts.length === 1 ? texts[0] : texts;
      return null;
    }

    let elements = SimpleCSSSelector.querySelectorAll(root, parts[0]);

    for (let i = 1; i < parts.length - 1; i++) {
      const sub: HTMLElement[] = [];
      for (const el of elements) {
        const found = SimpleCSSSelector.querySelectorAll(el, parts[i]);
        for (const f of found) sub.push(f);
      }
      elements = sub;
    }

    const lastPart = parts[parts.length - 1];
    const results: string[] = [];

    // Legado: 末段若不是 text/html/attr 关键字，则尝试当 CSS 子选择器再 select 一层
    // 否则直接当 attr name 提取
    const isAttrKeyword = AnalyzeRule.isAttrKeyword(lastPart);
    if (!isAttrKeyword) {
      const sub: HTMLElement[] = [];
      for (const el of elements) {
        const found = SimpleCSSSelector.querySelectorAll(el, lastPart);
        for (const f of found) sub.push(f);
      }
      if (sub.length > 0) {
        // 末段是子选择器：取 text
        const texts = sub.map((el) => SimpleCSSSelector.getText(el)).filter((t) => t.length > 0);
        if (texts.length > 0) return texts.length === 1 ? texts[0] : texts;
      }
      // fallback：当 attr name 处理
    }

    for (const el of elements) {
      const value = this.extractByAttr(el, lastPart);
      if (value !== null && value.length > 0) results.push(value);
    }

    if (results.length === 0) return null;
    return results.length === 1 ? results[0] : results;
  }

  /** 末段是否是 Legado 内置 attr 关键字（text/textNodes/html/outerHtml/ownText/all/src/href/...） */
  private static isAttrKeyword(s: string): boolean {
    const lower = s.toLowerCase().trim();
    if (/^attr\(.+\)$/i.test(lower)) return true;
    // 单一标识符（无空格、无 . # [ : >）当作 attr name 候选
    // text/html/owntext 等命中关键字；普通 attribute 名（href/src/data-xxx）也命中
    return /^[a-zA-Z][\w-]*$/.test(lower);
  }

  private extractByAttr(el: HTMLElement, attr: string): string | null {
    switch (attr.toLowerCase()) {
      case 'text':
        return SimpleCSSSelector.getText(el);
      case 'textnodes':
        return SimpleCSSSelector.getTextNodes(el).join('\n');
      case 'html':
        return SimpleCSSSelector.innerHTML(el);
      case 'outerhtml':
        return SimpleCSSSelector.outerHTML(el);
      case 'owntext':
        return SimpleCSSSelector.getOwnText(el);
      case 'src':
        return SimpleCSSSelector.getAttribute(el, 'src');
      case 'href':
        return SimpleCSSSelector.getAttribute(el, 'href');
      case 'all':
        return SimpleCSSSelector.outerHTML(el);
      default: {
        const attrMatch = attr.match(/^attr\(([^)]+)\)$/i);
        if (attrMatch) {
          return SimpleCSSSelector.getAttribute(el, attrMatch[1]);
        }
        return SimpleCSSSelector.getAttribute(el, attr);
      }
    }
  }

  private executeRegex(rule: string, chainResult: Object): Object | null {
    const source = this.resolveChainSource(chainResult);
    const content = typeof source === 'string' ? source : JSON.stringify(source);
    const results = AnalyzeByRegex.getStringList(content, rule);
    if (results.length === 0) return null;
    return results.length === 1 ? results[0] : results;
  }

  private executeXPath(rule: string, chainResult: Object): Object | null {
    const source = this.resolveChainSource(chainResult);
    const html = typeof source === 'string'
      ? source : JSON.stringify(source);
    const root = SimpleCSSSelector.parseHTML(html);
    const list = SimpleXPath.evaluateStringList(root, rule);
    if (list.length === 0) return null;
    return list.length === 1 ? list[0] : list;
  }

  // ──────────────────── getStringList 单段 ────────────────────

  private async getStringListSingle(rule: string): Promise<string[]> {
    const ruleList = this.splitSourceRule(rule);
    if (ruleList.length === 0) return [];

    let result: Object = this.content;
    for (const sr of ruleList) {
      await this.applyPut(sr.putMap, result);
      const effective = await this.makeUpRule(sr.rule, result);
      if (!effective) continue;
      const raw = await this.executeByMode(effective, sr.mode, result);
      if (raw === null || raw === undefined) return [];

      let arr: string[];
      if (Array.isArray(raw)) {
        arr = (raw as Object[]).map(String);
      } else {
        const str = String(raw);
        arr = str ? str.split('\n').filter((s) => s.trim().length > 0) : [];
      }

      if (sr.replaceRegex) {
        arr = arr.map((s) => this.applyReplace(s, sr)).filter((s) => s.length > 0);
      }
      result = arr;
    }

    if (Array.isArray(result)) return result as string[];
    const s = String(result);
    return s ? [s] : [];
  }

  // ──────────────────── 工具 ────────────────────

  private detectMode(rule: string): void {
    const cleanRule = rule.startsWith('-') || rule.startsWith('+') ? rule.substring(1) : rule;
    const cleanLower = cleanRule.toLowerCase();

    if (cleanLower.startsWith('@json:') || cleanLower.startsWith('json:')
      || cleanRule.startsWith('$.') || cleanRule.startsWith('$[')) {
      this.mode = RuleMode.Json;
    } else if (cleanLower.startsWith('@js:') || cleanLower.startsWith('js:') || cleanRule.includes('<js>')) {
      this.mode = RuleMode.Js;
    } else if (cleanLower.startsWith('@xpath:') || cleanRule.startsWith('//')) {
      this.mode = RuleMode.XPath;
    } else if (cleanLower.startsWith('@css:') || cleanRule.startsWith('@@')) {
      this.mode = RuleMode.Default;
    } else if (cleanLower.startsWith(':regex:')) {
      this.mode = RuleMode.Regex;
    } else if (this.isJSON) {
      this.mode = RuleMode.Json;
    } else {
      this.mode = RuleMode.Default;
    }
  }

  private detectIsJson(content: Object): boolean {
    if (typeof content === 'object') return true;
    if (typeof content !== 'string') return false;
    const trimmed = (content as string).trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}'))
      || (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }
}
