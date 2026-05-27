/**
 * AnalyzeRule - 统一规则分析器（对齐 Legado AnalyzeRule.kt）
 *
 * 支持：
 *  - JSON 模式（$. / @Json:）
 *  - CSS/JSoup 模式（Default）
 *  - JavaScript 模式（@js: / <js>...</js>）
 *  - XPath 模式（占位，待实现）
 *  - 正则模式（Regex）
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
import hilog from '@ohos.hilog';

const DOMAIN = 0xFF00;
const TAG = 'AnalyzeRule';

export enum RuleMode {
  Json = 'Json',
  Default = 'Default',
  XPath = 'XPath',
  Regex = 'Regex',
  Js = 'Js',
}

export class AnalyzeContext {
  variables: Record<string, string> = {};
  baseUrl: string = '';

  constructor(baseUrl: string = '', variables?: Record<string, string>) {
    this.baseUrl = baseUrl;
    if (variables) {
      this.variables = variables;
    }
  }
}

// 内部：单段解析结果
interface SourceRule {
  rule: string;
  mode: RuleMode;
  replaceRegex: string;
  replacement: string;
  replaceFirst: boolean;
  putMap: Record<string, string>;
}

// @put:{...} 模式
const PUT_PATTERN = /@put:\{([^}]+)\}/g;
// @get:{key}
const GET_PATTERN = /@get:\{([^}]+)\}/g;
// {{...}} 内嵌表达式
const EVAL_PATTERN = /\{\{([\s\S]+?)\}\}/g;
// {$.path} 内嵌 JSONPath
const JSON_EVAL_PATTERN = /\{\$\.([^}]+)\}/g;

interface JsTagPart {
  start: number;
  end: number;
  code: string;
}

export class AnalyzeRule {
  private content: Object;
  private context: AnalyzeContext;
  private mode: RuleMode = RuleMode.Default;

  constructor(content: Object, context?: AnalyzeContext) {
    this.content = content;
    this.context = context ?? new AnalyzeContext();
  }

  // ──────────────────── 公开 API ────────────────────

  async getString(rule: string): Promise<string | null> {
    if (!rule) return null;

    // 顶层 || 回退：依次尝试，第一个非空即返回
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
    hilog.info(DOMAIN, TAG, `getStringSingle: rule="${rule}", split into ${ruleList.length} parts`);
    if (ruleList.length === 0) return null;

    let result: Object = this.content;
    for (let i = 0; i < ruleList.length; i++) {
      const sr = ruleList[i];
      hilog.info(DOMAIN, TAG, `Step ${i + 1}/${ruleList.length}: rule="${sr.rule}", mode=${sr.mode}`);
      await this.applyPut(sr.putMap, result);
      const effective = await this.makeUpRule(sr.rule, result);
      hilog.info(DOMAIN, TAG, `Step ${i + 1}: effective="${effective}"`);
      if (!effective) continue;
      // 纯模板规则（@get/{{}}/{$.}）：makeUpRule 替换后没有选择器内容，直接作为字面量返回
      if (this.isPureTemplate(sr.rule)) {
        result = effective;
        hilog.info(DOMAIN, TAG, `Step ${i + 1}: pure template, result="${result}"`);
        continue;
      }
      const raw = await this.executeByMode(effective, sr.mode, result);
      hilog.info(DOMAIN, TAG, `Step ${i + 1}: raw result=${JSON.stringify(raw)?.substring(0, 100)}`);
      if (raw === null || raw === undefined) return null;
      let str: string;
      if (Array.isArray(raw)) {
        str = (raw as Object[]).map(String).join('\n');
      } else {
        str = String(raw);
      }
      result = this.applyReplace(str, sr);
      hilog.info(DOMAIN, TAG, `Step ${i + 1}: final result="${String(result).substring(0, 100)}"`);
    }
    const resultStr = String(result);
    hilog.info(DOMAIN, TAG, `getStringSingle final: "${resultStr.substring(0, 100)}"`);
    return resultStr || null;
  }

  /** 判断规则是否仅由 @get/@put/{{}}/{$.} 模板组成（无选择器语法） */
  private isPureTemplate(rule: string): boolean {
    // 剥离 @get:{...} / @put:{...} / {{...}} / {$.path}
    const stripped = rule
      .replace(/@get:\{[^}]+\}/g, '')
      .replace(/@put:\{[^}]+\}/g, '')
      .replace(/\{\{[\s\S]+?\}\}/g, '')
      .replace(/\{\$\.[^}]+\}/g, '');
    // 剩余部分若不含选择器/路径关键字符,则是纯模板
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
      const temp = await sub.getStringList(r);
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
        const temp = await sub.getStringList(r);
        if (!temp || temp.length === 0) return [];
        result = temp;
      }
      return result as string[];
    }

    return results.flat();
  }

  /**
   * 获取元素列表（用于 bookList / chapterList 迭代）
   */
  async getElements(rule: string): Promise<Object[]> {
    if (!rule) return [];
    this.detectMode(rule);

    if (this.mode === RuleMode.Json) {
      const cleanRule = rule.startsWith('@') ? rule.substring(1) : rule;
      const data: Object = typeof this.content === 'string'
        ? JSON.parse(this.content) as Object
        : this.content;
      const finalRule = cleanRule.toLowerCase().startsWith('json:')
        ? cleanRule.substring(5) : cleanRule;
      const list = jsonPath(data, finalRule);
      return Array.isArray(list) ? list : (list ? [list] : []);
    }

    if (this.mode === RuleMode.Default) {
      const html = typeof this.content === 'string'
        ? this.content : JSON.stringify(this.content);
      const root = SimpleCSSSelector.parseHTML(html);
      let cleanRule = rule;
      if (cleanRule.toLowerCase().startsWith('@css:')) cleanRule = cleanRule.substring(5);
      else if (cleanRule.startsWith('@@')) cleanRule = cleanRule.substring(2);
      const elements = SimpleCSSSelector.querySelectorAll(root, cleanRule);
      return elements.map((el) => SimpleCSSSelector.outerHTML(el));
    }

    if (this.mode === RuleMode.Js) {
      const result = await this.executeJs(rule);
      if (Array.isArray(result)) return result;
      return result ? [result] : [];
    }

    return [];
  }

  // ──────────────────── 规则分解 ────────────────────

  /**
   * 将完整 rule 字符串分解成 SourceRule 链（按 && 切分，每段独立执行）
   */
  private splitSourceRule(ruleStr: string): SourceRule[] {
    if (!ruleStr) return [];

    // 先把 <js>...</js> 和 @js: 块整体提取为 Js 段
    const list: SourceRule[] = [];
    const jsTagRegex = /<js>([\s\S]+?)<\/js>/gi;
    const atJsRegex = /^@?js:/i;

    // 整体是 JS?
    if (atJsRegex.test(ruleStr.trim())) {
      list.push(this.buildSourceRule(ruleStr, RuleMode.Js));
      return list;
    }

    // 有 <js> 块 → 拆分前后
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
      return list;
    }

    // 链式规则：按 @js: / @css: / @json: / @xpath: 等模式前缀拆分
    // Legado 用 @ 作为链式分隔符，如 $.url@js:result.split('/')[2]
    const chainParts = this.splitChainRule(ruleStr);
    if (chainParts.length > 1) {
      for (let i = 0; i < chainParts.length; i++) {
        const cp = chainParts[i].trim();
        // 第一个部分用 Default，后续部分让 buildSourceRule 自动检测模式
        const mode = (i === 0) ? RuleMode.Default : RuleMode.Default;
        const sr = this.buildSourceRule(cp, mode);
        // buildSourceRule 会根据规则前缀（@js:/@css: 等）自动设置正确的 mode
        list.push(sr);
      }
      return list;
    }

    // 普通规则
    list.push(this.buildSourceRule(ruleStr, RuleMode.Default));
    return list;
  }

  /**
   * 按 @mode: 链式分隔符拆分规则
   * 如 "http://api.com/@js:result" → ["http://api.com/", "@js:result"]
   * 注意：只在不在括号/引号内的 @ 才作为分隔符
   */
  private splitChainRule(ruleStr: string): string[] {
    // 匹配 @js: / @css: / @json: / @xpath: / @put: / @get: 模式前缀
    const modePattern = /@(js|css|json|xpath|put|get):/gi;
    const parts: string[] = [];
    let lastEnd = 0;
    let match: RegExpExecArray | null = modePattern.exec(ruleStr);
    hilog.info(DOMAIN, TAG, `splitChainRule: input="${ruleStr}"`);
    while (match !== null) {
      hilog.info(DOMAIN, TAG, `splitChainRule: found match="${match[0]}" at index=${match.index}`);
      // 检查 @ 前面是否有内容（不是开头才算链式）
      if (match.index > 0) {
        const before = ruleStr.substring(lastEnd, match.index);
        if (before.trim()) {
          parts.push(before);
          hilog.info(DOMAIN, TAG, `splitChainRule: added before="${before}"`);
        }
        lastEnd = match.index;
      }
      match = modePattern.exec(ruleStr);
    }
    if (lastEnd < ruleStr.length) {
      const remaining = ruleStr.substring(lastEnd);
      if (remaining.trim()) {
        parts.push(remaining);
        hilog.info(DOMAIN, TAG, `splitChainRule: added remaining="${remaining}"`);
      }
    }
    hilog.info(DOMAIN, TAG, `splitChainRule: result: ${parts.length} parts: ${JSON.stringify(parts)}`);
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

    // 1. 分离 @put:{...}
    let rule = ruleStr.replace(PUT_PATTERN, (_match: string, json: string): string => {
      try {
        const obj = JSON.parse(`{${json}}`) as Record<string, string>;
        const keys = Object.keys(obj);
        for (const k of keys) sr.putMap[k] = obj[k];
      } catch (e) {
        // 忽略解析失败
      }
      return '';
    }).trim();

    // 2. 检测模式前缀
    const lower = rule.toLowerCase();
    if (lower.startsWith('@json:') || lower.startsWith('json:')) {
      sr.mode = RuleMode.Json;
      rule = rule.substring(rule.toLowerCase().startsWith('@json:') ? 6 : 5);
    } else if (lower.startsWith('@xpath:') || lower.startsWith('xpath:')) {
      sr.mode = RuleMode.XPath;
      rule = rule.substring(rule.toLowerCase().startsWith('@xpath:') ? 7 : 6);
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
    } else if (defaultMode !== RuleMode.Js) {
      // 内容是 JSON → Json 模式
      if (this.isJson(this.content)) {
        sr.mode = RuleMode.Json;
      } else {
        sr.mode = RuleMode.Default;
      }
    }

    // 3. 分离 ##pattern##replacement（###表示取首条）
    const hashIdx = rule.indexOf('##');
    if (hashIdx > 0) {
      const afterHash = rule.substring(hashIdx + 2);
      rule = rule.substring(0, hashIdx);
      const parts = afterHash.split('##');
      sr.replaceRegex = parts[0] || '';
      sr.replacement = parts.length > 1 ? parts[1] : '';
      sr.replaceFirst = parts.length > 2; // ### 存在第三段
    }

    sr.rule = rule.trim();
    return sr;
  }

  // ──────────────────── makeUpRule（替换 @get / {{expr}} / {$.path}）────────────────────

  private async makeUpRule(rule: string, result: Object): Promise<string> {
    if (!rule) return rule;
    let out = rule;

    // 1. @get:{key} → 取变量
    out = out.replace(GET_PATTERN, (_match: string, key: string): string => {
      const vars = this.context.variables;
      return (vars && vars[key] !== undefined) ? vars[key] : '';
    });

    // 2. {$.path} → JSONPath 对当前 result 求值
    out = out.replace(JSON_EVAL_PATTERN, (_match: string, path: string): string => {
      try {
        const data: Object = typeof result === 'string'
          ? JSON.parse(result as string) as Object : result;
        const val = jsonPath(data, '$.' + path);
        if (val === null || val === undefined) return '';
        return Array.isArray(val) ? (val as Object[]).map((x: Object) => String(x)).join('') : String(val);
      } catch (e) {
        return '';
      }
    });

    // 3. {{expr}} → 先处理可同步求值的，再异步处理 JS 表达式
    const evalMatches: Array<[string, string]> = [];
    out = out.replace(EVAL_PATTERN, (whole: string, inner: string): string => {
      const trimmed = inner.trim();
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
        } catch (e) {
          return whole;
        }
      }
      evalMatches.push([whole, trimmed]);
      return whole;
    });

    // 异步求值剩余的 JS 表达式
    if (evalMatches.length > 0) {
      const executor = getJSExecutor();
      const ctx: Record<string, Object> = {};
      ctx['result'] = result;
      ctx['baseUrl'] = this.context.baseUrl || '';
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
        } catch (e) { /* 求值失败保留原样 */ }
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
      if (valRule && (valRule.startsWith('$.') || valRule.startsWith('@css:')
        || valRule.startsWith('@@') || valRule.startsWith('@json:'))) {
        try {
          const sub = new AnalyzeRule(result, this.context);
          const v = await sub.getString(valRule);
          if (v && this.context.variables) {
            this.context.variables[key] = v;
          }
        } catch (e) {
          this.context.variables[key] = valRule;
        }
      } else {
        this.context.variables[key] = valRule;
      }
    }
  }

  // ──────────────────── ## 替换 ────────────────────

  private applyReplace(str: string, sr: SourceRule): string {
    if (!sr.replaceRegex) return str;
    try {
      const regex = new RegExp(sr.replaceRegex, 'g');
      if (sr.replaceFirst) {
        // 取第一个匹配到的组，然后替换
        const firstMatch = str.match(new RegExp(sr.replaceRegex));
        if (!firstMatch) return '';
        return firstMatch[0].replace(regex, sr.replacement);
      }
      return str.replace(regex, sr.replacement);
    } catch {
      return str;
    }
  }

  // ──────────────────── 执行分发 ────────────────────

  private async executeByMode(rule: string, mode: RuleMode, result: Object): Promise<Object | null> {
    switch (mode) {
      case RuleMode.Json:
        return this.executeJson(rule);
      case RuleMode.Js:
        return this.executeJs(rule, result);
      case RuleMode.Default:
        return this.executeDefault(rule);
      case RuleMode.XPath:
        return this.executeXPath(rule);
      case RuleMode.Regex:
        return this.executeRegex(rule);
      default:
        return null;
    }
  }

  private executeJson(rule: string): Object | null {
    let cleanRule = rule;
    const lower = cleanRule.toLowerCase();
    if (lower.startsWith('json:')) cleanRule = cleanRule.substring(5);
    if (lower.startsWith('@json:')) cleanRule = cleanRule.substring(6);

    try {
      const data: Object = typeof this.content === 'string'
        ? JSON.parse(this.content) as Object : this.content;
      return jsonPath(data, cleanRule);
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

    // 包装代码以捕获有声书常用的副作用变量（yp_url / url）
    // Legado Rhino 引擎会返回 if/else 最后一条语句的值，标准 JS 不会
    // 所以需要显式声明变量 + 末尾返回
    const needsWrap = code.includes('yp_url') || /(?:^|[\s;])url\s*=/.test(code);
    if (needsWrap) {
      code = 'var yp_url, url;\n' + code + '\n' +
        'if(typeof yp_url !== "undefined" && yp_url) yp_url;\n' +
        'else if(typeof url !== "undefined" && url) url;\n';
    }

    const executor = getJSExecutor();
    const ctx: Record<string, Object> = {};
    // 链式规则时，result 是前一步的输出；否则是原始内容
    ctx['result'] = chainResult !== undefined ? chainResult : this.content;
    ctx['baseUrl'] = this.context.baseUrl || '';
    ctx['src'] = this.content;
    if (this.context.variables) {
      const vars = this.context.variables;
      for (const k of Object.keys(vars)) ctx[k] = vars[k];
    }
    try {
      return await executor.eval(code, ctx);
    } catch (error) {
      console.error('[AnalyzeRule] JS 执行失败:', error);
      return null;
    }
  }

  /**
   * CSS 默认模式：支持链式 @ 分隔符
   * 末尾支持：text / textNodes / html / outerHtml / ownText / src / href / @attr(name)
   */
  private executeDefault(rule: string): Object | null {
    const html = typeof this.content === 'string'
      ? this.content : JSON.stringify(this.content);

    const root = SimpleCSSSelector.parseHTML(html);

    // 处理 @CSS: 前缀
    let cleanRule = rule;
    if (cleanRule.toLowerCase().startsWith('@css:')) cleanRule = cleanRule.substring(5);
    if (cleanRule.startsWith('@@')) cleanRule = cleanRule.substring(2);

    // 用 @ 切分链式规则（@ 作为分隔，RuleAnalyzer 已实现）
    const analyzer = new RuleAnalyzer(cleanRule);
    const parts = analyzer.splitRule('@');

    if (parts.length === 1) {
      const elements = SimpleCSSSelector.querySelectorAll(root, parts[0]);
      if (elements.length === 0) return null;
      const texts = elements.map((el) => SimpleCSSSelector.getText(el)).filter((t) => t.length > 0);
      return texts.length === 1 ? texts[0] : texts;
    }

    // 多段链式
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

    for (const el of elements) {
      const value = this.extractByAttr(el, lastPart);
      if (value !== null && value.length > 0) results.push(value);
    }

    if (results.length === 0) return null;
    return results.length === 1 ? results[0] : results;
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
        // @attr(name) 形式
        const attrMatch = attr.match(/^attr\(([^)]+)\)$/i);
        if (attrMatch) {
          return SimpleCSSSelector.getAttribute(el, attrMatch[1]);
        }
        // 直接属性名
        return SimpleCSSSelector.getAttribute(el, attr);
      }
    }
  }

  private executeRegex(rule: string): string | null {
    const content = String(this.content);
    try {
      const regex = new RegExp(rule);
      const match = content.match(regex);
      return match ? match[0] : null;
    } catch {
      return null;
    }
  }

  private executeXPath(rule: string): Object | null {
    const html = typeof this.content === 'string'
      ? this.content : JSON.stringify(this.content);
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

      // 应用 ## 替换
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
    const lower = rule.toLowerCase();
    if (lower.startsWith('@json:') || lower.startsWith('json:')
      || rule.startsWith('$.') || rule.startsWith('$[')) {
      this.mode = RuleMode.Json;
    } else if (lower.startsWith('@js:') || lower.startsWith('js:') || rule.includes('<js>')) {
      this.mode = RuleMode.Js;
    } else if (lower.startsWith('@xpath:') || rule.startsWith('//')) {
      this.mode = RuleMode.XPath;
    } else if (lower.startsWith('@css:') || rule.startsWith('@@')) {
      this.mode = RuleMode.Default;
    } else if (this.isJson(this.content)) {
      this.mode = RuleMode.Json;
    } else {
      this.mode = RuleMode.Default;
    }
  }

  private isJson(content: Object): boolean {
    if (typeof content === 'object') return true;
    if (typeof content !== 'string') return false;
    const trimmed = (content as string).trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}'))
      || (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }
}
