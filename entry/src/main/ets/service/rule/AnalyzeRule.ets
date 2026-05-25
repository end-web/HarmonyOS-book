/**
 * AnalyzeRule - 统一规则分析器
 *
 * 参考 Legado 的 AnalyzeRule.kt 实现
 * 当前版本：支持 JSONPath + JavaScript
 * 后续扩展：CSS 选择器、XPath
 */

import { RuleAnalyzer } from './RuleAnalyzer';
import { jsonPath } from './JSONPath';
import { getJSExecutor } from '../js/JSExecutor';
import { SimpleCSSSelector, HTMLElement } from './SimpleCSSSelector';

export enum RuleMode {
  Json = 'Json',
  Default = 'Default', // CSS/JSoup（待实现）
  XPath = 'XPath',     // 待实现
  Regex = 'Regex',     // 待实现
  Js = 'Js',
}

export interface AnalyzeContext {
  variables?: Record<string, Object>; // 变量存储（@put/@get）
  regexGroups?: string[]; // 正则分组（$1-$99）
}

export class AnalyzeRule {
  private content: Object;
  private context: AnalyzeContext;
  private mode: RuleMode = RuleMode.Default;

  constructor(content: Object, context: AnalyzeContext = {}) {
    this.content = content;
    this.context = context;
  }

  /**
   * 获取单个字符串结果
   */
  async getString(rule: string): Promise<string | null> {
    if (!rule) return null;

    // 检测并设置模式
    this.detectMode(rule);

    // 处理运算符
    const analyzer = new RuleAnalyzer(rule);
    const rules = analyzer.splitRule('||', '&&');

    if (rules.length === 1) {
      const single = await this.executeSingle(rule);
      if (single === null || single === undefined) return null;
      if (Array.isArray(single)) {
        return single.length > 0 ? String(single[0]) : null;
      }
      return String(single);
    }

    // 处理 || 和 &&
    if (analyzer.elementsType === '||') {
      // 回退：返回第一个非空结果
      for (const r of rules) {
        const result = await this.getString(r);
        if (result) return result;
      }
      return null;
    } else {
      // 链式：依次执行
      let result: Object = this.content;
      for (const r of rules) {
        const subAnalyzer = new AnalyzeRule(result, this.context);
        const temp = await subAnalyzer.getString(r);
        if (!temp) return null;
        result = temp;
      }
      return result as string;
    }
  }

  /**
   * 获取字符串列表
   */
  async getStringList(rule: string): Promise<string[]> {
    if (!rule) return [];

    this.detectMode(rule);

    const analyzer = new RuleAnalyzer(rule);
    const rules = analyzer.splitRule('||', '&&', '%%');

    if (rules.length === 1) {
      const result = await this.executeSingle(rule);
      if (Array.isArray(result)) {
        return result.map(String);
      }
      return result ? [String(result)] : [];
    }

    const results: string[][] = [];

    for (const r of rules) {
      const subAnalyzer = new AnalyzeRule(this.content, this.context);
      const temp = await subAnalyzer.getStringList(r);
      if (temp.length > 0) {
        results.push(temp);
        if (analyzer.elementsType === '||') {
          break;
        }
      }
    }

    if (results.length === 0) return [];

    // 处理 %% 交错合并
    if (analyzer.elementsType === '%%') {
      const merged: string[] = [];
      const maxLen = Math.max(...results.map(r => r.length));
      for (let i = 0; i < maxLen; i++) {
        for (const temp of results) {
          if (i < temp.length) {
            merged.push(temp[i]);
          }
        }
      }
      return merged;
    }

    // 处理 && 链式
    if (analyzer.elementsType === '&&') {
      let result: Object = this.content;
      for (const r of rules) {
        const subAnalyzer = new AnalyzeRule(result, this.context);
        const temp = await subAnalyzer.getStringList(r);
        if (!temp || temp.length === 0) return [];
        result = temp;
      }
      return result as string[];
    }

    // 默认顺序合并
    return results.flat();
  }

  /**
   * 获取元素列表（用于书源 bookList / chapterList 等迭代场景）
   * - JSON 模式：返回 JSON 数组节点
   * - CSS 模式：返回每个匹配元素的 outer HTML 片段
   */
  async getElements(rule: string): Promise<Object[]> {
    if (!rule) return [];
    this.detectMode(rule);

    if (this.mode === RuleMode.Json) {
      const cleanRule = rule.startsWith('@') ? rule.substring(1) : rule;
      const data: Object = typeof this.content === 'string' ? JSON.parse(this.content) as Object : this.content;
      const finalRule = cleanRule.toLowerCase().startsWith('json:') ? cleanRule.substring(5) : cleanRule;
      return jsonPath(data, finalRule);
    }

    if (this.mode === RuleMode.Default) {
      const html = typeof this.content === 'string' ? this.content : JSON.stringify(this.content);
      const root = SimpleCSSSelector.parseHTML(html);
      const cleanRule = rule.toLowerCase().startsWith('@css:') ? rule.substring(5) : rule;
      const elements = SimpleCSSSelector.querySelectorAll(root, cleanRule);
      return elements.map(el => SimpleCSSSelector.outerHTML(el));
    }

    if (this.mode === RuleMode.Js) {
      const result = await this.executeJs(rule);
      if (Array.isArray(result)) return result;
      return result ? [result] : [];
    }

    return [];
  }

  /**
   * 执行单个规则
   */
  private async executeSingle(rule: string): Promise<Object | null> {
    // 去除前缀
    let cleanRule = rule;
    if (cleanRule.startsWith('@')) {
      cleanRule = cleanRule.substring(1);
    }

    // 处理模板变量 {{key}}
    if (cleanRule.includes('{{') && cleanRule.includes('}}')) {
      return this.replaceTemplate(cleanRule);
    }

    // 处理替换 ##match##replace
    if (cleanRule.includes('##')) {
      return this.replaceRegex(cleanRule);
    }

    // 根据模式执行
    switch (this.mode) {
      case RuleMode.Json:
        return this.executeJson(cleanRule);
      case RuleMode.Js:
        return await this.executeJs(cleanRule);
      case RuleMode.Default:
        return this.executeDefault(cleanRule);
      case RuleMode.XPath:
        console.warn('[AnalyzeRule] XPath 暂未实现');
        return null;
      case RuleMode.Regex:
        return this.executeRegex(cleanRule);
      default:
        return null;
    }
  }

  /**
   * 检测规则模式
   */
  private detectMode(rule: string): void {
    const lower = rule.toLowerCase();

    if (lower.startsWith('@json:') || lower.startsWith('$.') || lower.startsWith('$[')) {
      this.mode = RuleMode.Json;
    } else if (lower.startsWith('@js:') || rule.includes('<js>')) {
      this.mode = RuleMode.Js;
    } else if (lower.startsWith('@xpath:') || rule.startsWith('//')) {
      this.mode = RuleMode.XPath;
    } else if (lower.startsWith('@css:') || lower.startsWith('@@')) {
      this.mode = RuleMode.Default;
    } else if (this.isJson(this.content)) {
      this.mode = RuleMode.Json;
    } else {
      this.mode = RuleMode.Default;
    }
  }

  /**
   * 执行 JSON 模式
   */
  private executeJson(rule: string): Object | null {
    let cleanRule = rule;
    if (cleanRule.toLowerCase().startsWith('json:')) {
      cleanRule = cleanRule.substring(5);
    }

    const data: Object = typeof this.content === 'string' ? JSON.parse(this.content) as Object : this.content;
    return jsonPath(data, cleanRule);
  }

  /**
   * 执行 JavaScript 模式
   */
  private async executeJs(rule: string): Promise<Object | null> {
    let code = rule;

    // 提取 @js: 或 <js>...</js>
    if (code.toLowerCase().startsWith('js:')) {
      code = code.substring(3);
    } else if (code.includes('<js>')) {
      const start = code.indexOf('<js>') + 4;
      const end = code.indexOf('</js>');
      if (end > start) {
        code = code.substring(start, end);
      }
    }

    // 执行 JavaScript
    const executor = getJSExecutor();
    const context: Record<string, Object> = {};
    context['result'] = this.content;
    if (this.context.variables) {
      const vars = this.context.variables;
      for (const k of Object.keys(vars)) {
        context[k] = vars[k];
      }
    }

    try {
      return await executor.eval(code, context);
    } catch (error) {
      console.error('[AnalyzeRule] JS 执行失败:', error);
      return null;
    }
  }

  /**
   * 执行默认模式（CSS 选择器）
   */
  private executeDefault(rule: string): Object | null {
    const html = typeof this.content === 'string' ? this.content : JSON.stringify(this.content);

    // 解析 HTML
    const root = SimpleCSSSelector.parseHTML(html);

    // 处理链式选择器 div.title@text
    const analyzer = new RuleAnalyzer(rule);
    const parts = analyzer.splitRule('@');

    if (parts.length === 1) {
      // 只有选择器，返回元素
      const elements = SimpleCSSSelector.querySelectorAll(root, parts[0]);
      return elements.map(el => SimpleCSSSelector.getText(el));
    }

    // 链式：先选择元素，再提取属性
    let elements = SimpleCSSSelector.querySelectorAll(root, parts[0]);

    for (let i = 1; i < parts.length - 1; i++) {
      const newElements: HTMLElement[] = [];
      for (const el of elements) {
        newElements.push(...SimpleCSSSelector.querySelectorAll(el, parts[i]));
      }
      elements = newElements;
    }

    // 最后一部分是属性提取
    const lastPart = parts[parts.length - 1];
    const results: string[] = [];

    for (const el of elements) {
      let value: string | null = null;

      switch (lastPart) {
        case 'text':
          value = SimpleCSSSelector.getText(el);
          break;
        case 'html':
          value = SimpleCSSSelector.getText(el); // 简化：返回文本
          break;
        case 'ownText':
          value = el.textContent;
          break;
        default:
          // 属性提取
          value = SimpleCSSSelector.getAttribute(el, lastPart);
          break;
      }

      if (value) {
        results.push(value);
      }
    }

    return results.length === 1 ? results[0] : results;
  }

  /**
   * 执行正则模式
   */
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

  /**
   * 替换模板变量 {{key}}
   */
  private replaceTemplate(rule: string): string {
    const analyzer = new RuleAnalyzer(rule);
    return analyzer.innerRule('{{', '}}', (key) => {
      const vars = this.context.variables;
      if (vars && vars[key] !== undefined) {
        return String(vars[key]);
      }
      return `{{${key}}}`;
    });
  }

  /**
   * 替换正则 ##match##replace
   */
  private replaceRegex(rule: string): string {
    const content = String(this.content);
    const parts = rule.split('##');

    if (parts.length < 3) {
      return content;
    }

    const pattern = parts[1];
    const replacement = parts[2];
    const replaceAll = parts.length === 3;

    try {
      const regex = new RegExp(pattern, replaceAll ? 'g' : '');
      return content.replace(regex, replacement);
    } catch {
      return content;
    }
  }

  /**
   * 判断是否为 JSON
   */
  private isJson(content: Object): boolean {
    if (typeof content === 'object') return true;
    if (typeof content !== 'string') return false;
    const trimmed = (content as string).trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }
}
