import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleJsonPath } from './LocalRuleJsonPath';
import { LocalRuleScriptRuntime } from './LocalRuleScriptRuntime';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';
import { LocalRuleTemplate } from './LocalRuleTemplate';
import {
  LocalRuleDocument,
  LocalRuleDocumentKind,
  LocalRuleExecutionLimits
} from './LocalRuleRuntimeTypes';
import { LocalRuleUrlAnalyzer } from './LocalRuleUrlAnalyzer';
import { LocalRuleWebExtractMode, LocalRuleWebRuntime } from './LocalRuleWebRuntime';

class LocalRuleRegexProcessor {
  baseRule: string = '';
  pattern: string = '';
  replacement: string = '';
  enabled: boolean = false;
}

class LocalRuleSelectorSpec {
  selector: string = '';
  xpath: boolean = false;
  mode: string = LocalRuleWebExtractMode.TEXT;
  attribute: string = '';
}

class LocalRuleScriptChain {
  baseRule: string = '';
  code: string = '';
  trailingRule: string = '';
}

/** 结构化规则的阶段提取器；不持有源状态，因此单次失败不会污染下一次执行。 */
export class LocalRuleStageExtractor {
  static createDocument(body: string, baseUrl: string): LocalRuleDocument {
    const trimmed = body.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
      (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        JSON.parse(trimmed) as Object;
        return LocalRuleDocument.of(LocalRuleDocumentKind.JSON, trimmed, baseUrl);
      } catch (_error) {
        // 非法 JSON 继续按 HTML/文本处理。
      }
    }
    if (new RegExp('<[A-Za-z!/][\\s\\S]*>', 'i').test(trimmed)) {
      return LocalRuleDocument.of(LocalRuleDocumentKind.HTML, body, baseUrl);
    }
    return LocalRuleDocument.of(LocalRuleDocumentKind.TEXT, body, baseUrl);
  }

  static async selectList(document: LocalRuleDocument, rule: string,
    source: LocalRuleSource, variables: Record<string, string> = {}): Promise<LocalRuleDocument[]> {
    const cleanRule = await LocalRuleStageExtractor.prepareContextRule(document, rule, source, variables);
    if (!cleanRule) return [];
    const alternatives = LocalRuleStageExtractor.splitTopLevel(cleanRule, '||');
    if (alternatives.length > 1) {
      for (const alternative of alternatives) {
        const selected = await LocalRuleStageExtractor.selectList(document, alternative, source, variables);
        if (selected.length > 0) return selected;
      }
      return [];
    }
    const concatenated = LocalRuleStageExtractor.splitTopLevel(cleanRule, '&&');
    if (concatenated.length > 1) {
      const output: LocalRuleDocument[] = [];
      for (const part of concatenated) {
        const selected = await LocalRuleStageExtractor.selectList(document, part, source, variables);
        output.push(...selected);
      }
      return output;
    }
    const interleaved = LocalRuleStageExtractor.splitTopLevel(cleanRule, '%%');
    if (interleaved.length > 1) {
      const groups: LocalRuleDocument[][] = [];
      let maxLength = 0;
      for (const part of interleaved) {
        const selected = await LocalRuleStageExtractor.selectList(document, part, source, variables);
        groups.push(selected);
        maxLength = Math.max(maxLength, selected.length);
      }
      const output: LocalRuleDocument[] = [];
      for (let index = 0; index < maxLength; index++) {
        for (const group of groups) {
          if (index < group.length) output.push(group[index]);
        }
      }
      return output;
    }

    if (LocalRuleScriptRuntime.hasScript(cleanRule)) {
      const values = await LocalRuleStageExtractor.extractValues(document, cleanRule, source, variables);
      return LocalRuleStageExtractor.documentsFromScriptValues(values, document.baseUrl);
    }
    if (document.kind === LocalRuleDocumentKind.JSON) {
      const values = LocalRuleJsonPath.queryPayload(document.payload,
        LocalRuleStageExtractor.normalizeJsonRule(cleanRule));
      const output: LocalRuleDocument[] = [];
      for (const value of values) {
        if (Array.isArray(value)) {
          const items = value as Object[];
          for (const item of items) {
            if (item === undefined || item === null) continue;
            LocalRuleStageExtractor.appendJsonListDocument(output, item, document.baseUrl);
            if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
          }
        } else {
          LocalRuleStageExtractor.appendJsonListDocument(output, value, document.baseUrl);
        }
        if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      return output;
    }
    if (document.kind === LocalRuleDocumentKind.HTML) {
      const spec = LocalRuleStageExtractor.selectorSpec(cleanRule, true);
      const values = await LocalRuleWebRuntime.instance.select(document.payload, spec.selector,
        spec.xpath, LocalRuleWebExtractMode.OUTER_HTML);
      const output: LocalRuleDocument[] = [];
      for (const value of values) {
        const kind = value.trim().startsWith('<') ? LocalRuleDocumentKind.HTML : LocalRuleDocumentKind.TEXT;
        output.push(LocalRuleDocument.of(kind, value, document.baseUrl));
      }
      return output;
    }
    return LocalRuleStageExtractor.regexDocuments(document, cleanRule);
  }

  static async extract(document: LocalRuleDocument, rule: string, source: LocalRuleSource,
    variables: Record<string, string> = {}, resolveUrl: boolean = false): Promise<string> {
    LocalRuleDiagnostics.check(variables);
    const values = await LocalRuleStageExtractor.extractValues(document, rule, source, variables);
    if (rule) LocalRuleDiagnostics.record(variables, 'info', `规则返回 ${values.length} 项`, rule);
    if (resolveUrl) {
      for (const value of values) {
        const resolved = LocalRuleUrlAnalyzer.resolveUrl(document.baseUrl || source.bookSourceUrl, value);
        if (resolved) return resolved;
      }
      return '';
    }
    const nonEmpty: string[] = [];
    for (const value of values) {
      const clean = value.trim();
      if (clean) nonEmpty.push(clean);
    }
    return nonEmpty.join('\n').trim();
  }

  static async extractFirst(document: LocalRuleDocument, rule: string, source: LocalRuleSource,
    variables: Record<string, string> = {}, resolveUrl: boolean = false): Promise<string> {
    const values = await LocalRuleStageExtractor.extractValues(document, rule, source, variables);
    for (const value of values) {
      const clean = value.trim();
      if (!clean) continue;
      if (!resolveUrl) return clean;
      const resolved = LocalRuleUrlAnalyzer.resolveUrl(document.baseUrl || source.bookSourceUrl, clean);
      if (resolved) return resolved;
    }
    return '';
  }

  static async extractValues(document: LocalRuleDocument, rule: string,
    source: LocalRuleSource, variables: Record<string, string> = {}): Promise<string[]> {
    const directVariable = LocalRuleStageExtractor.directGetValue(rule, variables);
    if (directVariable !== undefined) return directVariable.length > 0 ? [directVariable] : [];
    const cleanRule = await LocalRuleStageExtractor.prepareContextRule(document, rule, source, variables);
    if (!cleanRule) return [];
    const standaloneCode = LocalRuleScriptRuntime.standaloneCode(cleanRule);
    if (standaloneCode.length > 0) {
      const value = await LocalRuleScriptRuntime.evaluate(document.payload, document.baseUrl,
        standaloneCode, source, variables, '');
      return LocalRuleStageExtractor.expandScriptValue(value);
    }
    const scriptChain = LocalRuleStageExtractor.scriptChain(cleanRule);
    if (scriptChain !== undefined) {
      return LocalRuleStageExtractor.executeScriptChain(document, scriptChain, source, variables);
    }
    const regex = LocalRuleStageExtractor.regexProcessor(cleanRule);
    let values = await LocalRuleStageExtractor.extractBaseValues(document, regex.baseRule, source, variables);
    if (regex.enabled) values = LocalRuleStageExtractor.applyRegex(values, regex.pattern, regex.replacement);
    return values;
  }

  static parseBoolean(value: string): boolean {
    const clean = value.trim().toLowerCase();
    return clean === 'true' || clean === '1' || clean === 'yes' || clean === 'vip' ||
      clean === 'pay' || clean === 'paid' || clean === '付费' || clean === '收费' || clean === '完结';
  }

  static parseDuration(value: string): number {
    const clean = value.trim();
    if (!clean) return 0;
    if (clean.includes(':')) {
      const parts = clean.split(':');
      let seconds = 0;
      for (const part of parts) {
        const current = Number(part);
        if (!Number.isFinite(current)) return 0;
        seconds = seconds * 60 + current;
      }
      return Math.max(0, Math.trunc(seconds));
    }
    const number = Number(clean);
    return Number.isFinite(number) ? Math.max(0, Math.trunc(number)) : 0;
  }

  static applyCleanup(value: string, pattern: string): string {
    const cleanPattern = pattern.trim();
    if (!cleanPattern) return value;
    try {
      const parts = LocalRuleStageExtractor.splitEscapedRegex(cleanPattern);
      const regexText = parts[0];
      const replacement = parts.length > 1 ? parts[1] : '';
      if (!regexText) return value;
      return value.replace(new RegExp(regexText, 'g'), replacement);
    } catch (_error) {
      throw new Error('正文净化正则无效');
    }
  }

  static stripHtml(value: string): string {
    return value.replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
      .replace(new RegExp('<(?:br|hr)\\s*/?>', 'gi'), '\n')
      .replace(new RegExp('</?(?:p|div|section|article|li|h[1-6])\\b[^>]*>', 'gi'), '\n')
      .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), '')
      .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), '')
      .replace(new RegExp('<[^>]+>', 'g'), '')
      .replace(new RegExp('&nbsp;|&#160;', 'gi'), ' ')
      .replace(new RegExp('&amp;', 'gi'), '&')
      .replace(new RegExp('&lt;', 'gi'), '<')
      .replace(new RegExp('&gt;', 'gi'), '>')
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'")
      .replace(new RegExp('[\\t ]+', 'g'), ' ')
      .replace(new RegExp(' *\\n *', 'g'), '\n')
      .replace(new RegExp('\\n{3,}', 'g'), '\n\n')
      .trim();
  }

  static limit(value: string, maximum: number = LocalRuleExecutionLimits.MAX_FIELD_CHARS): string {
    return value.length > maximum ? value.substring(0, maximum) : value;
  }

  private static async extractBaseValues(document: LocalRuleDocument, rule: string,
    source: LocalRuleSource, variables: Record<string, string>): Promise<string[]> {
    const cleanRule = rule.trim();
    if (!cleanRule) return [document.payload];
    if (cleanRule.includes('{{')) {
      return [await LocalRuleStageExtractor.expandElementTemplate(document, cleanRule, source, variables)];
    }
    if (new RegExp('^(https?://|data:)', 'i').test(cleanRule)) return [cleanRule];

    const alternatives = LocalRuleStageExtractor.splitTopLevel(cleanRule, '||');
    if (alternatives.length > 1) {
      for (const alternative of alternatives) {
        const values = await LocalRuleStageExtractor.extractValues(document, alternative, source, variables);
        if (LocalRuleStageExtractor.hasNonEmpty(values)) return values;
      }
      return [];
    }
    const concatenated = LocalRuleStageExtractor.splitTopLevel(cleanRule, '&&');
    if (concatenated.length > 1) {
      const output: string[] = [];
      for (const part of concatenated) {
        output.push(...await LocalRuleStageExtractor.extractValues(document, part, source, variables));
      }
      return output;
    }
    const interleaved = LocalRuleStageExtractor.splitTopLevel(cleanRule, '%%');
    if (interleaved.length > 1) {
      const groups: string[][] = [];
      let maxLength = 0;
      for (const part of interleaved) {
        const values = await LocalRuleStageExtractor.extractValues(document, part, source, variables);
        groups.push(values);
        maxLength = Math.max(maxLength, values.length);
      }
      const output: string[] = [];
      for (let index = 0; index < maxLength; index++) {
        for (const group of groups) {
          if (index < group.length) output.push(group[index]);
        }
      }
      return output;
    }

    if (cleanRule.startsWith('%') || cleanRule.startsWith(':') ||
      cleanRule.toLowerCase().startsWith('@regex:')) {
      return LocalRuleStageExtractor.directRegex(document.payload, cleanRule);
    }
    if (document.kind === LocalRuleDocumentKind.JSON) {
      return LocalRuleStageExtractor.extractJson(document.payload, cleanRule);
    }
    if (document.kind === LocalRuleDocumentKind.HTML) {
      const spec = LocalRuleStageExtractor.selectorSpec(cleanRule, false);
      return LocalRuleWebRuntime.instance.select(document.payload, spec.selector,
        spec.xpath, spec.mode, spec.attribute);
    }
    if (cleanRule === 'text' || cleanRule === '@text' || cleanRule === 'html' || cleanRule === '@html') {
      return [document.payload];
    }
    return [cleanRule];
  }

  private static extractJson(payload: string, rule: string): string[] {
    let jsonRule = LocalRuleStageExtractor.normalizeJsonRule(rule);
    if (!LocalRuleJsonPath.isJsonPath(jsonRule)) {
      if (new RegExp('^[A-Za-z_$][A-Za-z0-9_$-]*$').test(jsonRule)) {
        jsonRule = `$[${JSON.stringify(jsonRule)}]`;
      } else if (LocalRuleStageExtractor.isDomSelectorRule(jsonRule)) {
        return [];
      } else {
        return [jsonRule];
      }
    }
    const values = LocalRuleJsonPath.queryPayload(payload, jsonRule);
    const output: string[] = [];
    for (const value of values) output.push(LocalRuleJsonPath.valueToString(value));
    return output;
  }

  private static isDomSelectorRule(rule: string): boolean {
    const clean = rule.trim();
    if (!clean) return false;
    const lower = clean.toLowerCase();
    if (lower.startsWith('@css:') || lower.startsWith('@xpath:') ||
      clean.startsWith('//') || clean.startsWith('/html') || clean.startsWith('./') ||
      clean.startsWith('.') || clean.startsWith('#') || clean.startsWith('[')) {
      return true;
    }
    if (new RegExp('^(?:class|id|tag|text)\\.', 'i').test(clean)) return true;
    if (new RegExp('^[A-Za-z][A-Za-z0-9_-]*(?:[.#\\[]|\\s*[>+~])').test(clean)) return true;
    const htmlSelector = new RegExp(
      '^(?:a|article|aside|body|div|dl|dt|dd|h[1-6]|html|img|li|link|main|meta|nav|ol|option|p|section|span|table|tbody|td|th|thead|tr|ul)\\b',
      'i');
    if (htmlSelector.test(clean) &&
      (new RegExp('\\s').test(clean) || LocalRuleStageExtractor.lastTopLevelAt(clean) > 0)) {
      return true;
    }
    return false;
  }

  private static normalizeJsonRule(rule: string): string {
    if (LocalRuleJsonPath.isJsonPath(rule)) return rule;
    if (new RegExp('^[A-Za-z_$][A-Za-z0-9_$-]*(?:\\.[A-Za-z_$][A-Za-z0-9_$-]*|\\[[\\s\\S]+\\])+$').test(rule)) {
      return `$.${rule}`;
    }
    if (new RegExp('^[A-Za-z_$][A-Za-z0-9_$-]*$').test(rule)) {
      return `$[${JSON.stringify(rule)}]`;
    }
    return rule;
  }

  private static selectorSpec(rule: string, listMode: boolean): LocalRuleSelectorSpec {
    const spec = new LocalRuleSelectorSpec();
    let clean = rule.trim();
    if (clean.toLowerCase().startsWith('@xpath:')) {
      spec.xpath = true;
      clean = clean.substring(7).trim();
      LocalRuleStageExtractor.applyXpathSelectorSpec(spec, clean, listMode);
      return spec;
    }
    if (clean.startsWith('//') || clean.startsWith('/html') || clean.startsWith('./')) {
      spec.xpath = true;
      LocalRuleStageExtractor.applyXpathSelectorSpec(spec, clean, listMode);
      return spec;
    }
    if (clean.toLowerCase().startsWith('@css:')) clean = clean.substring(5).trim();
    if (listMode) {
      spec.selector = LocalRuleStageExtractor.cssChain(clean);
      spec.mode = LocalRuleWebExtractMode.OUTER_HTML;
      return spec;
    }

    const currentModes: string[] = ['text', '@text', 'html', '@html', 'ownText', '@ownText',
      'textNodes', '@textNodes'];
    if (currentModes.includes(clean)) {
      spec.selector = '';
      spec.mode = LocalRuleStageExtractor.extractMode(clean.replace('@', ''));
      return spec;
    }
    if (LocalRuleStageExtractor.isCurrentAttribute(clean)) {
      spec.selector = '';
      spec.mode = LocalRuleWebExtractMode.ATTRIBUTE;
      spec.attribute = clean.startsWith('@') ? clean.substring(1) : clean;
      return spec;
    }

    const separator = LocalRuleStageExtractor.lastTopLevelAt(clean);
    if (separator >= 0) {
      const suffix = clean.substring(separator + 1).trim();
      if (LocalRuleStageExtractor.isExtractionSuffix(suffix)) {
        spec.selector = LocalRuleStageExtractor.cssChain(clean.substring(0, separator).trim());
        spec.mode = LocalRuleStageExtractor.extractMode(suffix);
        if (spec.mode === LocalRuleWebExtractMode.ATTRIBUTE) spec.attribute = suffix;
        return spec;
      }
    }
    spec.selector = LocalRuleStageExtractor.cssChain(clean);
    return spec;
  }

  private static applyXpathSelectorSpec(spec: LocalRuleSelectorSpec, rule: string, listMode: boolean): void {
    let selector = rule.trim();
    const separator = LocalRuleStageExtractor.lastTopLevelAt(selector);
    if (separator > 0 && selector.charAt(separator - 1) !== '/') {
      const suffix = selector.substring(separator + 1).trim();
      if (LocalRuleStageExtractor.isExtractionSuffix(suffix)) {
        selector = selector.substring(0, separator).trim();
        if (!listMode) {
          spec.mode = LocalRuleStageExtractor.extractMode(suffix);
          if (spec.mode === LocalRuleWebExtractMode.ATTRIBUTE) spec.attribute = suffix;
        }
      }
    }
    spec.selector = selector;
    if (listMode) spec.mode = LocalRuleWebExtractMode.OUTER_HTML;
  }

  private static extractMode(suffix: string): string {
    const clean = suffix.toLowerCase();
    if (clean === 'html') return LocalRuleWebExtractMode.HTML;
    if (clean === 'owntext') return LocalRuleWebExtractMode.OWN_TEXT;
    if (clean === 'textnodes') return LocalRuleWebExtractMode.TEXT_NODES;
    if (clean === 'text') return LocalRuleWebExtractMode.TEXT;
    return LocalRuleWebExtractMode.ATTRIBUTE;
  }

  private static isExtractionSuffix(value: string): boolean {
    const clean = value.trim();
    return clean === 'text' || clean === 'html' || clean === 'ownText' || clean === 'textNodes' ||
      LocalRuleStageExtractor.isLegalAttributeName(clean);
  }

  private static isCurrentAttribute(value: string): boolean {
    let clean = value.trim();
    const explicit = clean.startsWith('@');
    if (explicit) clean = clean.substring(1);
    if (clean === 'text' || clean === 'html' || clean === 'ownText' || clean === 'textNodes') return false;
    if (explicit) return LocalRuleStageExtractor.isLegalAttributeName(clean);
    const common: string[] = ['href', 'src', 'value', 'data-src', 'data-url'];
    if (common.includes(clean)) return true;
    return clean.startsWith('data-') && new RegExp('^[A-Za-z_:][A-Za-z0-9_:.\\-]*$').test(clean);
  }

  private static isLegalAttributeName(value: string): boolean {
    return new RegExp('^[A-Za-z_:][A-Za-z0-9_:.\\-]*$').test(value.trim());
  }

  private static cssChain(value: string): string {
    const parts = LocalRuleStageExtractor.splitTopLevel(value, '@');
    if (parts.length <= 1) return LocalRuleStageExtractor.normalizeLegacyCssSelector(value);
    let output = '';
    for (const part of parts) {
      const clean = part.trim();
      if (!clean) continue;
      const childrenMatch = new RegExp('^children((?:\\.!|!)-?\\d+(?::-?\\d+)*)?$', 'i').exec(clean);
      if (childrenMatch !== null) {
        const exclusion = childrenMatch[1] ?? '';
        output += `${output ? ' ' : ''}> *${exclusion}`;
        continue;
      }
      const normalized = LocalRuleStageExtractor.normalizeLegacyCssSelector(clean);
      if (normalized) output += `${output ? ' ' : ''}${normalized}`;
    }
    return output.trim();
  }

  /** 将阅读书源的 class.foo / tag.a / a.0 语法转换为受控 DOM 宿主支持的 CSS。 */
  static normalizeLegacyCssSelector(value: string): string {
    let output = value.trim();
    output = output.replace(
      new RegExp('(\\[[A-Za-z_:][A-Za-z0-9_:.\\-]*\\s*(?:[~|^$*]?=)\\s*)([^\\s"\'\\]]*:[^\\s"\'\\]]*)(\\s*(?:[iIsS]\\s*)?\\])', 'g'),
      '$1"$2"$3');
    output = output.replace(
      new RegExp('(^|[\\s>+~,])class\\.([A-Za-z_][A-Za-z0-9_-]*)', 'g'), '$1.$2');
    output = output.replace(
      new RegExp('(^|[\\s>+~,])id\\.([A-Za-z_][A-Za-z0-9_-]*)', 'g'), '$1#$2');
    output = output.replace(
      new RegExp('(^|[\\s>+~,])tag\\.([A-Za-z][A-Za-z0-9_-]*)', 'g'), '$1$2');
    output = output.replace(
      new RegExp('((?:^|[\\s>+~,])(?:[A-Za-z][A-Za-z0-9_-]*|[.#][A-Za-z_][A-Za-z0-9_-]*))\\.(-?\\d+)(?=$|[\\s>+~,])', 'g'),
      '$1:eq($2)');
    return output;
  }

  private static appendJsonListDocument(output: LocalRuleDocument[], value: Object,
    baseUrl: string): void {
    const payload = LocalRuleJsonPath.valueToString(value);
    output.push(LocalRuleDocument.of(LocalRuleDocumentKind.JSON,
      typeof value === 'string' ? JSON.stringify(value) : payload, baseUrl));
  }

  private static async expandElementTemplate(document: LocalRuleDocument, template: string,
    source: LocalRuleSource, variables: Record<string, string>): Promise<string> {
    let output = '';
    let position = 0;
    while (position < template.length) {
      const start = template.indexOf('{{', position);
      if (start < 0) {
        output += template.substring(position);
        break;
      }
      output += template.substring(position, start);
      const end = LocalRuleTemplate.end(template, start + 2);
      if (end < 0) {
        output += template.substring(start);
        break;
      }
      const expression = template.substring(start + 2, end).trim();
      output += await LocalRuleStageExtractor.templateValue(document, expression, source, variables);
      position = end + 2;
    }
    return output;
  }

  private static async templateValue(document: LocalRuleDocument, expression: string,
    source: LocalRuleSource, variables: Record<string, string>): Promise<string> {
    if (expression === 'source.bookSourceUrl') return source.bookSourceUrl;
    if (expression === 'source.bookSourceName') return source.bookSourceName;
    if (expression === 'source.bookSourceGroup') return source.bookSourceGroup;
    if (expression === 'source.bookSourceComment') return source.bookSourceComment;
    if (expression === 'source.getKey()') return source.bookSourceUrl;
    if (expression === 'source.getTag()') return source.bookSourceName;
    if (expression === 'source.getVariable()') {
      return LocalRuleScriptRuntime.evaluate(document.payload, document.baseUrl, expression, source, variables);
    }
    const variable = variables[expression];
    if (variable !== undefined) return variable;
    if (!new RegExp('^(\\$[.\\[]|@@|@json:|@css:|@xpath:|//)', 'i').test(expression) &&
      !new RegExp('^[A-Za-z_$][\\w$-]*$').test(expression)) {
      return LocalRuleScriptRuntime.evaluate(document.payload, document.baseUrl, expression, source, variables);
    }
    let rule = expression;
    if (rule.startsWith('@@')) rule = rule.substring(2);
    const values = await LocalRuleStageExtractor.extractValues(document, rule, source, variables);
    return values.length > 0 ? values[0] : '';
  }

  private static async prepareContextRule(document: LocalRuleDocument, rawRule: string,
    source: LocalRuleSource, variables: Record<string, string>): Promise<string> {
    let rule = rawRule.trim();
    if (LocalRuleScriptRuntime.standaloneCode(rule)) return rule;
    let guard = 0;
    while (guard < 16) {
      const sections = LocalRuleStageExtractor.splitTopLevel(rule, '@put:');
      if (sections.length < 2 || !sections[1].startsWith('{') || LocalRuleScriptRuntime.hasScript(sections[0])) break;
      const putStart = sections[0].length;
      const open = putStart + 5;
      const close = LocalRuleStageExtractor.findMatchingBrace(rule, open);
      if (close < 0) throw new Error('@put 变量规则缺少右花括号');
      const body = rule.substring(open + 1, close);
      await LocalRuleStageExtractor.applyPutBody(document, body, source, variables);
      rule = (rule.substring(0, putStart) + rule.substring(close + 1)).trim();
      guard++;
    }
    return LocalRuleStageExtractor.replaceGetReferences(rule, variables);
  }

  private static async applyPutBody(document: LocalRuleDocument, body: string,
    source: LocalRuleSource, variables: Record<string, string>): Promise<void> {
    const commaParts = LocalRuleStageExtractor.splitTopLevel(body, ',');
    const entries: string[] = [];
    for (const commaPart of commaParts) {
      const semicolonParts = LocalRuleStageExtractor.splitTopLevel(commaPart, ';');
      for (const semicolonPart of semicolonParts) {
        if (semicolonPart.trim()) entries.push(semicolonPart.trim());
      }
    }
    for (const entry of entries) {
      const separator = LocalRuleStageExtractor.firstTopLevelCharacter(entry, ':');
      if (separator <= 0) continue;
      let key = entry.substring(0, separator).trim();
      if ((key.startsWith('"') && key.endsWith('"')) ||
        (key.startsWith("'") && key.endsWith("'"))) {
        key = key.substring(1, key.length - 1);
      }
      if (!new RegExp('^[A-Za-z_$][A-Za-z0-9_.$-]*$').test(key)) continue;
      const valueRule = LocalRuleStageExtractor.unwrapPutValue(entry.substring(separator + 1));
      const values = await LocalRuleStageExtractor.extractValues(document, valueRule, source, variables);
      variables[key] = values.join('\n').trim();
    }
  }

  private static unwrapPutValue(value: string): string {
    const clean = value.trim();
    if (clean.length < 2) return clean;
    const quote = clean.charAt(0);
    if ((quote !== '"' && quote !== "'") || clean.charAt(clean.length - 1) !== quote) return clean;
    let output = '';
    let index = 1;
    while (index < clean.length - 1) {
      const character = clean.charAt(index);
      if (character !== '\\' || index + 1 >= clean.length - 1) {
        output += character;
        index++;
        continue;
      }
      const escaped = clean.charAt(index + 1);
      if (escaped === quote || escaped === '"' || escaped === "'" || escaped === '\\') {
        output += escaped;
        index += 2;
        continue;
      }
      if (escaped === 'n') output += '\n';
      else if (escaped === 'r') output += '\r';
      else if (escaped === 't') output += '\t';
      else if (escaped === 'b') output += '\b';
      else if (escaped === 'f') output += '\f';
      else {
        // CSS/正则常用的 \s、\d 等不是字符串转义，原样保留反斜杠。
        output += `\\${escaped}`;
      }
      index += 2;
    }
    return output;
  }

  private static replaceGetReferences(value: string, variables: Record<string, string>): string {
    let output = value;
    let position = 0;
    let guard = 0;
    while (position < output.length && guard < 64) {
      const lower = output.toLowerCase();
      const start = lower.indexOf('@get:{', position);
      if (start < 0) break;
      const end = output.indexOf('}', start + 6);
      if (end < 0) break;
      const key = output.substring(start + 6, end).trim();
      const replacement = variables[key] ?? '';
      output = output.substring(0, start) + replacement + output.substring(end + 1);
      position = start + replacement.length;
      guard++;
    }
    return output;
  }

  private static directGetValue(rule: string,
    variables: Record<string, string>): string | undefined {
    const value = rule.trim();
    const lower = value.toLowerCase();
    if (!lower.startsWith('@get:{') || !value.endsWith('}')) return undefined;
    const closing = value.indexOf('}', 6);
    if (closing !== value.length - 1) return undefined;
    const key = value.substring(6, closing).trim();
    return variables[key] ?? '';
  }

  private static scriptChain(rule: string): LocalRuleScriptChain | undefined {
    const lower = rule.toLowerCase();
    const open = lower.indexOf('<js>');
    if (open >= 0) {
      const close = lower.indexOf('</js>', open + 4);
      if (close < 0) throw new Error('书源脚本缺少 </js>');
      const chain = new LocalRuleScriptChain();
      chain.baseRule = rule.substring(0, open).trim();
      chain.code = rule.substring(open + 4, close).trim();
      chain.trailingRule = rule.substring(close + 5).trim();
      return chain;
    }
    const postIndex = LocalRuleStageExtractor.findTopLevelMarker(rule, '@js:');
    if (postIndex > 0) {
      const chain = new LocalRuleScriptChain();
      chain.baseRule = rule.substring(0, postIndex).trim();
      chain.code = rule.substring(postIndex + 4).trim();
      return chain;
    }
    return undefined;
  }

  private static async executeScriptChain(document: LocalRuleDocument, chain: LocalRuleScriptChain,
    source: LocalRuleSource, variables: Record<string, string>): Promise<string[]> {
    const baseValues = chain.baseRule.length > 0
      ? await LocalRuleStageExtractor.extractValues(document, chain.baseRule, source, variables)
      : [document.payload];
    const output: string[] = [];
    for (const baseValue of baseValues) {
      const scripted = await LocalRuleScriptRuntime.evaluate(document.payload, document.baseUrl,
        chain.code, source, variables, baseValue);
      if (chain.trailingRule.length > 0) {
        const scriptedDocument = LocalRuleStageExtractor.createDocument(scripted, document.baseUrl);
        const values = await LocalRuleStageExtractor.extractValues(
          scriptedDocument, chain.trailingRule, source, variables);
        output.push(...values);
      } else {
        output.push(...LocalRuleStageExtractor.expandScriptValue(scripted));
      }
    }
    return output;
  }

  private static expandScriptValue(value: string): string[] {
    const clean = value.trim();
    if (!clean) return [];
    try {
      const parsed = JSON.parse(clean) as Object;
      if (!Array.isArray(parsed)) return [LocalRuleJsonPath.valueToString(parsed)];
      const values = parsed as Object[];
      const output: string[] = [];
      for (const item of values) output.push(LocalRuleJsonPath.valueToString(item));
      return output;
    } catch (_error) {
      return [value];
    }
  }

  private static documentsFromScriptValues(values: string[], baseUrl: string): LocalRuleDocument[] {
    const output: LocalRuleDocument[] = [];
    for (const value of values) {
      const document = LocalRuleStageExtractor.createDocument(value, baseUrl);
      output.push(document);
      if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
    }
    return output;
  }

  private static findMatchingBrace(value: string, openIndex: number): number {
    if (openIndex < 0 || value.charAt(openIndex) !== '{') return -1;
    let depth = 0;
    let quote = '';
    let escaped = false;
    for (let index = openIndex; index < value.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '{') depth++;
      if (character === '}') {
        depth--;
        if (depth === 0) return index;
      }
    }
    return -1;
  }

  private static firstTopLevelCharacter(value: string, target: string): number {
    let quote = '';
    let escaped = false;
    let parentheses = 0;
    let brackets = 0;
    let braces = 0;
    for (let index = 0; index < value.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '(') parentheses++;
      else if (character === ')') parentheses = Math.max(0, parentheses - 1);
      else if (character === '[') brackets++;
      else if (character === ']') brackets = Math.max(0, brackets - 1);
      else if (character === '{') braces++;
      else if (character === '}') braces = Math.max(0, braces - 1);
      else if (character === target && parentheses === 0 && brackets === 0 && braces === 0) return index;
    }
    return -1;
  }

  private static findTopLevelMarker(value: string, marker: string): number {
    let quote = '';
    let escaped = false;
    let parentheses = 0;
    let brackets = 0;
    let braces = 0;
    for (let index = 0; index <= value.length - marker.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '(') parentheses++;
      else if (character === ')') parentheses = Math.max(0, parentheses - 1);
      else if (character === '[') brackets++;
      else if (character === ']') brackets = Math.max(0, brackets - 1);
      else if (character === '{') braces++;
      else if (character === '}') braces = Math.max(0, braces - 1);
      if (parentheses === 0 && brackets === 0 && braces === 0 &&
        value.substring(index, index + marker.length).toLowerCase() === marker) return index;
    }
    return -1;
  }

  private static regexProcessor(rule: string): LocalRuleRegexProcessor {
    const result = new LocalRuleRegexProcessor();
    const parts = LocalRuleStageExtractor.splitEscapedRegex(rule);
    if (parts.length < 2) {
      result.baseRule = rule;
      return result;
    }
    result.enabled = true;
    result.baseRule = parts[0];
    result.pattern = parts[1];
    result.replacement = parts.length >= 3 ? parts[2] : '';
    return result;
  }

  private static splitEscapedRegex(value: string): string[] {
    const output: string[] = [];
    let current = '';
    let index = 0;
    while (index < value.length) {
      if (value.charAt(index) === '\\' && index + 2 < value.length &&
        value.charAt(index + 1) === '#' && value.charAt(index + 2) === '#') {
        current += '##';
        index += 3;
        continue;
      }
      if (value.charAt(index) === '#' && index + 1 < value.length && value.charAt(index + 1) === '#') {
        output.push(current);
        current = '';
        index += 2;
        continue;
      }
      current += value.charAt(index);
      index++;
    }
    output.push(current);
    return output;
  }

  private static applyRegex(values: string[], pattern: string, replacement: string): string[] {
    if (!pattern) return values;
    let regex: RegExp;
    try {
      regex = new RegExp(pattern, 'g');
    } catch (_error) {
      throw new Error('字段正则无效');
    }
    const output: string[] = [];
    for (const value of values) output.push(value.replace(regex, replacement));
    return output;
  }

  private static directRegex(content: string, rule: string): string[] {
    let pattern = rule;
    let firstOnly = false;
    if (pattern.toLowerCase().startsWith('@regex:')) pattern = pattern.substring(7);
    else if (pattern.startsWith('%')) {
      pattern = pattern.substring(1);
      firstOnly = true;
    } else if (pattern.startsWith(':')) {
      pattern = pattern.substring(1);
    }
    let regex: RegExp;
    try {
      regex = new RegExp(pattern, firstOnly ? '' : 'g');
    } catch (_error) {
      throw new Error('直接正则无效');
    }
    const output: string[] = [];
    let match: RegExpExecArray | null = regex.exec(content);
    while (match !== null && output.length < LocalRuleExecutionLimits.MAX_JSON_NODES) {
      if (match.length <= 1) output.push(match[0] ?? '');
      else {
        for (let index = 1; index < match.length; index++) output.push(match[index] ?? '');
      }
      if (firstOnly || match[0] === '') break;
      match = regex.exec(content);
    }
    return output;
  }

  private static regexDocuments(document: LocalRuleDocument, rule: string): LocalRuleDocument[] {
    if (!rule.startsWith('%') && !rule.startsWith(':') && !rule.toLowerCase().startsWith('@regex:')) return [];
    const values = LocalRuleStageExtractor.directRegex(document.payload, rule);
    const output: LocalRuleDocument[] = [];
    for (const value of values) output.push(LocalRuleDocument.of(LocalRuleDocumentKind.TEXT, value, document.baseUrl));
    return output;
  }

  private static splitTopLevel(value: string, operator: string): string[] {
    const output: string[] = [];
    let current = '';
    let quote = '';
    let escaped = false;
    let parentheses = 0;
    let brackets = 0;
    let braces = 0;
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      if (escaped) {
        current += character;
        escaped = false;
        index++;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        index++;
        continue;
      }
      if (quote) {
        current += character;
        if (character === quote) quote = '';
        index++;
        continue;
      }
      if (character === '"' || character === "'") {
        current += character;
        quote = character;
        index++;
        continue;
      }
      if (character === '(') parentheses++;
      else if (character === ')') parentheses = Math.max(0, parentheses - 1);
      else if (character === '[') brackets++;
      else if (character === ']') brackets = Math.max(0, brackets - 1);
      else if (character === '{') braces++;
      else if (character === '}') braces = Math.max(0, braces - 1);
      if (parentheses === 0 && brackets === 0 && braces === 0 &&
        value.substring(index, index + operator.length) === operator) {
        output.push(current.trim());
        current = '';
        index += operator.length;
        continue;
      }
      current += character;
      index++;
    }
    output.push(current.trim());
    return output;
  }

  private static lastTopLevelAt(value: string): number {
    const parts = LocalRuleStageExtractor.splitTopLevel(value, '@');
    if (parts.length <= 1) return -1;
    const suffix = parts[parts.length - 1];
    return value.length - suffix.length - 1;
  }

  private static hasNonEmpty(values: string[]): boolean {
    for (const value of values) {
      if (value.trim()) return true;
    }
    return false;
  }
}
