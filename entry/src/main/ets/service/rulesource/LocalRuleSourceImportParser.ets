import {
  LocalRuleBookInfoRule,
  LocalRuleContentRule,
  LocalRuleSearchRule,
  LocalRuleSource,
  LocalRuleSourceImportReport,
  LocalRuleSourceStatus,
  LocalRuleTocRule
} from '../../model/LocalRuleSource';

const MAX_SOURCE_COUNT: number = 1000;

export class LocalRuleSourceImportParser {
  static parse(content: string): LocalRuleSourceImportReport {
    const report = new LocalRuleSourceImportReport();
    const text = (content || '').trim();
    if (!text) {
      report.message = '书源内容为空';
      return report;
    }

    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (error) {
      report.message = `JSON 格式错误：${LocalRuleSourceImportParser.errorMessage(error as Object)}`;
      return report;
    }

    const items = LocalRuleSourceImportParser.extractItems(parsed);
    const parseCount = Math.min(items.length, MAX_SOURCE_COUNT);
    for (let index = 0; index < parseCount; index++) {
      const item = items[index];
      const source = LocalRuleSourceImportParser.parseSource(item);
      if (source === undefined) {
        report.rejectedCount++;
        continue;
      }
      if (source.validationStatus === LocalRuleSourceStatus.UNSUPPORTED) {
        report.unsupportedCount++;
      }
      report.sources.push(source);
    }
    if (items.length > MAX_SOURCE_COUNT) {
      report.rejectedCount += items.length - MAX_SOURCE_COUNT;
      report.message = `单次最多导入 ${MAX_SOURCE_COUNT} 个书源`;
    }
    if (report.sources.length === 0) {
      report.message = report.rejectedCount > 0 ? '没有包含有效名称和地址的书源' : '没有找到书源';
    }
    return report;
  }

  private static extractItems(value: Object): Record<string, Object>[] {
    if (Array.isArray(value)) return LocalRuleSourceImportParser.toRecordList(value as Object[]);
    const root = LocalRuleSourceImportParser.asRecord(value);
    if (root === undefined) return [];
    const candidates: string[] = ['value', 'data', 'sources', 'bookSources', 'bookSourceList', 'list'];
    for (const key of candidates) {
      const child = root[key];
      if (Array.isArray(child)) return LocalRuleSourceImportParser.toRecordList(child as Object[]);
    }
    return [root];
  }

  private static toRecordList(values: Object[]): Record<string, Object>[] {
    const records: Record<string, Object>[] = [];
    for (const value of values) {
      const record = LocalRuleSourceImportParser.asRecord(value);
      if (record !== undefined) records.push(record);
    }
    return records;
  }

  private static parseSource(record: Record<string, Object>): LocalRuleSource | undefined {
    const sourceUrl = LocalRuleSourceImportParser.readString(record, 'bookSourceUrl');
    const sourceName = LocalRuleSourceImportParser.readString(record, 'bookSourceName');
    if (!sourceUrl || !sourceName) return undefined;

    const source = new LocalRuleSource();
    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = LocalRuleSourceImportParser.readNumber(record, 'bookSourceType', 0);
    source.bookSourceGroup = LocalRuleSourceImportParser.readGroupString(record, 'bookSourceGroup');
    source.bookSourceComment = LocalRuleSourceImportParser.readString(record, 'bookSourceComment');
    source.enabled = LocalRuleSourceImportParser.readBoolean(record, 'enabled', true);
    source.enabledExplore = LocalRuleSourceImportParser.readBoolean(record, 'enabledExplore', false);
    source.enabledCookieJar = LocalRuleSourceImportParser.readBoolean(record, 'enabledCookieJar', true);
    source.searchUrl = LocalRuleSourceImportParser.readString(record, 'searchUrl');
    source.exploreUrl = LocalRuleSourceImportParser.readString(record, 'exploreUrl');
    source.header = LocalRuleSourceImportParser.readJsonString(record, 'header');
    source.loginUrl = LocalRuleSourceImportParser.readString(record, 'loginUrl');
    source.loginUi = LocalRuleSourceImportParser.readJsonString(record, 'loginUi');
    source.loginCheckJs = LocalRuleSourceImportParser.readString(record, 'loginCheckJs');
    source.jsLib = LocalRuleSourceImportParser.readString(record, 'jsLib');
    source.variable = LocalRuleSourceImportParser.readJsonString(record, 'variable');
    source.respondTime = LocalRuleSourceImportParser.readNumber(record, 'respondTime', 18000);
    source.concurrentRate = LocalRuleSourceImportParser.readString(record, 'concurrentRate');
    source.lastUpdateTime = LocalRuleSourceImportParser.readNumber(record, 'lastUpdateTime', Date.now());
    source.rawSourceJson = JSON.stringify(record);

    const compactRuleNames: string[] = [];
    source.ruleSearch = LocalRuleSourceImportParser.parseSearchRule(
      LocalRuleSourceImportParser.ruleRecord(record, 'ruleSearch', 'searchRule', compactRuleNames));
    source.ruleBookInfo = LocalRuleSourceImportParser.parseBookInfoRule(
      LocalRuleSourceImportParser.ruleRecord(record, 'ruleBookInfo', 'bookInfoRule', compactRuleNames));
    source.ruleToc = LocalRuleSourceImportParser.parseTocRule(
      LocalRuleSourceImportParser.ruleRecord(record, 'ruleToc', 'tocRule', compactRuleNames));
    source.ruleContent = LocalRuleSourceImportParser.parseContentRule(
      LocalRuleSourceImportParser.ruleRecord(record, 'ruleContent', 'contentRule', compactRuleNames));

    source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
    source.validationMessage = LocalRuleSourceImportParser.capabilityMessage(source, compactRuleNames);
    return source;
  }

  private static parseSearchRule(record: Record<string, Object>): LocalRuleSearchRule {
    const rule = new LocalRuleSearchRule();
    rule.bookList = LocalRuleSourceImportParser.readString(record, 'bookList');
    rule.name = LocalRuleSourceImportParser.readString(record, 'name');
    rule.author = LocalRuleSourceImportParser.readString(record, 'author');
    rule.coverUrl = LocalRuleSourceImportParser.readString(record, 'coverUrl');
    rule.bookUrl = LocalRuleSourceImportParser.readString(record, 'bookUrl');
    rule.intro = LocalRuleSourceImportParser.readString(record, 'intro');
    rule.kind = LocalRuleSourceImportParser.readString(record, 'kind');
    rule.status = LocalRuleSourceImportParser.readString(record, 'status');
    rule.lastChapter = LocalRuleSourceImportParser.readString(record, 'lastChapter');
    rule.wordCount = LocalRuleSourceImportParser.readString(record, 'wordCount');
    rule.updateTime = LocalRuleSourceImportParser.readString(record, 'updateTime');
    return rule;
  }

  private static parseBookInfoRule(record: Record<string, Object>): LocalRuleBookInfoRule {
    const rule = new LocalRuleBookInfoRule();
    rule.init = LocalRuleSourceImportParser.readString(record, 'init');
    rule.name = LocalRuleSourceImportParser.readString(record, 'name');
    rule.author = LocalRuleSourceImportParser.readString(record, 'author');
    rule.coverUrl = LocalRuleSourceImportParser.readString(record, 'coverUrl');
    rule.intro = LocalRuleSourceImportParser.readString(record, 'intro');
    rule.kind = LocalRuleSourceImportParser.readString(record, 'kind');
    rule.status = LocalRuleSourceImportParser.readString(record, 'status');
    rule.lastChapter = LocalRuleSourceImportParser.readString(record, 'lastChapter');
    rule.wordCount = LocalRuleSourceImportParser.readString(record, 'wordCount');
    rule.updateTime = LocalRuleSourceImportParser.readString(record, 'updateTime');
    rule.tocUrl = LocalRuleSourceImportParser.readString(record, 'tocUrl');
    return rule;
  }

  private static parseTocRule(record: Record<string, Object>): LocalRuleTocRule {
    const rule = new LocalRuleTocRule();
    rule.chapterList = LocalRuleSourceImportParser.readString(record, 'chapterList');
    rule.chapterName = LocalRuleSourceImportParser.readString(record, 'chapterName');
    rule.chapterUrl = LocalRuleSourceImportParser.readString(record, 'chapterUrl');
    rule.nextTocUrl = LocalRuleSourceImportParser.readString(record, 'nextTocUrl');
    rule.isVip = LocalRuleSourceImportParser.readString(record, 'isVip');
    rule.isPay = LocalRuleSourceImportParser.readString(record, 'isPay');
    rule.isVolume = LocalRuleSourceImportParser.readString(record, 'isVolume');
    rule.updateTime = LocalRuleSourceImportParser.readString(record, 'updateTime');
    rule.duration = LocalRuleSourceImportParser.readString(record, 'duration');
    return rule;
  }

  private static parseContentRule(record: Record<string, Object>): LocalRuleContentRule {
    const rule = new LocalRuleContentRule();
    rule.content = LocalRuleSourceImportParser.readString(record, 'content');
    rule.title = LocalRuleSourceImportParser.readString(record, 'title');
    rule.audioUrl = LocalRuleSourceImportParser.readString(record, 'audioUrl');
    rule.nextContentUrl = LocalRuleSourceImportParser.readString(record, 'nextContentUrl');
    rule.replaceRegex = LocalRuleSourceImportParser.readString(record, 'replaceRegex');
    rule.sourceRegex = LocalRuleSourceImportParser.readString(record, 'sourceRegex');
    return rule;
  }

  private static ruleRecord(root: Record<string, Object>, primary: string, fallback: string,
    compactRules: string[]): Record<string, Object> {
    const primaryValue = root[primary];
    const fallbackValue = root[fallback];
    const primaryRecord = LocalRuleSourceImportParser.asRecord(primaryValue);
    if (primaryRecord !== undefined) return primaryRecord;
    const fallbackRecord = LocalRuleSourceImportParser.asRecord(fallbackValue);
    if (fallbackRecord !== undefined) return fallbackRecord;

    if (typeof primaryValue === 'string' && primaryValue.trim().length > 0) {
      const compact = LocalRuleSourceImportParser.parseCompactRule(primaryValue);
      if (compact !== undefined) return compact;
      compactRules.push(primary);
    }
    if (typeof fallbackValue === 'string' && fallbackValue.trim().length > 0) {
      const compact = LocalRuleSourceImportParser.parseCompactRule(fallbackValue);
      if (compact !== undefined) return compact;
      compactRules.push(fallback);
    }
    const empty: Record<string, Object> = {};
    return empty;
  }

  /** 兼容阅读常见的 @{name=rule;bookUrl=rule} 规则组，分隔符只在顶层生效。 */
  private static parseCompactRule(value: string): Record<string, Object> | undefined {
    let text = value.trim();
    if (text.startsWith('@{') && text.endsWith('}')) {
      text = text.substring(2, text.length - 1);
    } else if (text.startsWith('{') && text.endsWith('}')) {
      try {
        const parsed = JSON.parse(text) as Object;
        return LocalRuleSourceImportParser.asRecord(parsed);
      } catch (_error) {
        text = text.substring(1, text.length - 1);
      }
    }
    if (!text.includes('=')) return undefined;

    const record: Record<string, Object> = {};
    const fields = LocalRuleSourceImportParser.splitCompactFields(text);
    let count = 0;
    for (const field of fields) {
      const separator = LocalRuleSourceImportParser.topLevelEquals(field);
      if (separator <= 0) continue;
      const name = field.substring(0, separator).trim();
      if (!new RegExp('^[A-Za-z_$][A-Za-z0-9_$-]*$').test(name)) continue;
      record[name] = field.substring(separator + 1).trim();
      count++;
    }
    return count > 0 ? record : undefined;
  }

  private static splitCompactFields(value: string): string[] {
    const output: string[] = [];
    let current = '';
    let quote = '';
    let escaped = false;
    let roundDepth = 0;
    let squareDepth = 0;
    let curlyDepth = 0;
    for (let index = 0; index < value.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        continue;
      }
      if (character === '(') roundDepth++;
      else if (character === ')') roundDepth = Math.max(0, roundDepth - 1);
      else if (character === '[') squareDepth++;
      else if (character === ']') squareDepth = Math.max(0, squareDepth - 1);
      else if (character === '{') curlyDepth++;
      else if (character === '}') curlyDepth = Math.max(0, curlyDepth - 1);
      if (character === ';' && roundDepth === 0 && squareDepth === 0 && curlyDepth === 0) {
        if (current.trim().length > 0) output.push(current.trim());
        current = '';
      } else {
        current += character;
      }
    }
    if (current.trim().length > 0) output.push(current.trim());
    return output;
  }

  private static topLevelEquals(value: string): number {
    let quote = '';
    let escaped = false;
    let roundDepth = 0;
    let squareDepth = 0;
    let curlyDepth = 0;
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
      if (quote.length > 0) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '(') roundDepth++;
      else if (character === ')') roundDepth = Math.max(0, roundDepth - 1);
      else if (character === '[') squareDepth++;
      else if (character === ']') squareDepth = Math.max(0, squareDepth - 1);
      else if (character === '{') curlyDepth++;
      else if (character === '}') curlyDepth = Math.max(0, curlyDepth - 1);
      else if (character === '=' && roundDepth === 0 && squareDepth === 0 && curlyDepth === 0) {
        return index;
      }
    }
    return -1;
  }

  private static capabilityMessage(source: LocalRuleSource, compactRules: string[]): string {
    const notes: string[] = [];
    if (!source.hasSearchCapability()) notes.push('未配置完整搜索规则');
    if (compactRules.length > 0) notes.push(`保留未识别规则组：${compactRules.join(', ')}`);
    if (!source.bookSourceUrl.startsWith('http://') && !source.bookSourceUrl.startsWith('https://')) {
      notes.push('非 HTTP(S) 地址将在实际请求阶段校验');
    }
    return notes.length > 0 ? `${notes.join('；')}；其他能力仍可使用` : '等待测试';
  }

  private static asRecord(value: Object | undefined): Record<string, Object> | undefined {
    if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
      return undefined;
    }
    return value as Record<string, Object>;
  }

  private static readString(record: Record<string, Object>, key: string): string {
    const value = record[key];
    if (value === undefined || value === null) return '';
    if (typeof value === 'object') return '';
    return String(value).trim();
  }

  private static readGroupString(record: Record<string, Object>, key: string): string {
    const groups: string[] = [];
    LocalRuleSourceImportParser.collectGroupValues(record[key], groups);
    return groups.join(' · ');
  }

  private static collectGroupValues(value: Object | undefined, groups: string[]): void {
    if (value === undefined || value === null) return;
    if (typeof value === 'string') {
      LocalRuleSourceImportParser.appendGroupValue(value, groups);
      return;
    }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (const item of items) {
        LocalRuleSourceImportParser.collectGroupValues(item, groups);
      }
      return;
    }
    if (typeof value !== 'object') return;

    const groupRecord = value as Record<string, Object>;
    const preferredKeys: string[] = ['name', 'title', 'label', 'group'];
    let foundPreferred = false;
    for (const preferredKey of preferredKeys) {
      const preferredValue = groupRecord[preferredKey];
      if (typeof preferredValue === 'string' && preferredValue.trim().length > 0) {
        LocalRuleSourceImportParser.appendGroupValue(preferredValue, groups);
        foundPreferred = true;
      }
    }
    if (foundPreferred) return;

    const keys = Object.keys(groupRecord);
    for (const groupKey of keys) {
      const groupValue = groupRecord[groupKey];
      if (typeof groupValue === 'string') {
        LocalRuleSourceImportParser.appendGroupValue(groupValue, groups);
      }
    }
  }

  private static appendGroupValue(value: string, groups: string[]): void {
    const group = value.trim();
    if (group.length === 0 || group.toLowerCase() === '[object object]' || groups.includes(group)) return;
    groups.push(group);
  }

  private static readJsonString(record: Record<string, Object>, key: string): string {
    const value = record[key];
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value.trim();
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return '';
    }
  }

  private static readBoolean(record: Record<string, Object>, key: string, fallback: boolean): boolean {
    const value = record[key];
    if (value === undefined || value === null) return fallback;
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    const normalized = String(value).trim().toLowerCase();
    if (normalized.length === 0) return fallback;
    return normalized !== 'false' && normalized !== '0' && normalized !== 'off' && normalized !== 'no';
  }

  private static readNumber(record: Record<string, Object>, key: string, fallback: number): number {
    const value = record[key];
    if (value === undefined || value === null) return fallback;
    if (typeof value === 'string' && value.trim().length === 0) return fallback;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error || '未知错误');
  }
}
