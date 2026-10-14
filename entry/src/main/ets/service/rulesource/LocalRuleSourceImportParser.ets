import {
  LocalRuleBookInfoRule,
  LocalRuleContentRule,
  LocalRuleSearchRule,
  LocalRuleSource,
  LocalRuleSourceImportReport,
  LocalRuleSourceStatus,
  LocalRuleTocRule
} from '../../model/LocalRuleSource';
import { LightSourceDefinition } from './light/LightSourceDefinition';

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
    const parseCount = items.length;
    for (let index = 0; index < parseCount; index++) {
      const item = items[index];
      let source: LocalRuleSource | undefined;
      try {
        source = LocalRuleSourceImportParser.parseSource(item);
      } catch (error) {
        report.rejectedCount++;
        report.message = `第 ${index + 1} 个书源：${error}`;
        continue;
      }
      if (source === undefined) {
        report.rejectedCount++;
        continue;
      }
      if (source.validationStatus === LocalRuleSourceStatus.UNSUPPORTED) {
        report.unsupportedCount++;
      }
      report.sources.push(source);
    }
    if (report.sources.length === 0 && !report.message) {
      report.message = report.rejectedCount > 0 ? '没有包含有效名称和地址的书源' : '没有找到书源';
    }
    return report;
  }

  private static extractItems(value: Object): Record<string, Object>[] {
    if (Array.isArray(value)) return LocalRuleSourceImportParser.toRecordList(value as Object[]);
    const root = LocalRuleSourceImportParser.asRecord(value);
    if (root === undefined) return [];
    if (Object.keys(root).includes('format')) return [root];
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
    const parsed: LocalRuleSource = JSON.parse(LightSourceDefinition.appDefinition(JSON.stringify(record)));
    const source = new LocalRuleSource();
    source.bookSourceUrl = parsed.bookSourceUrl;
    source.bookSourceName = parsed.bookSourceName;
    source.bookSourceType = parsed.bookSourceType;
    source.bookSourceGroup = parsed.bookSourceGroup;
    source.bookSourceComment = parsed.bookSourceComment;
    source.enabled = parsed.enabled;
    source.isLocked = parsed.isLocked;
    source.isPinned = parsed.isPinned;
    source.customOrder = parsed.customOrder;
    source.enabledCookieJar = parsed.enabledCookieJar;
    source.searchUrl = parsed.searchUrl;
    source.exploreUrl = parsed.exploreUrl;
    source.enabledExplore = parsed.enabledExplore;
    source.header = parsed.header;
    source.loginUrl = parsed.loginUrl;
    source.loginUi = parsed.loginUi;
    source.loginCheckJs = parsed.loginCheckJs;
    source.jsLib = parsed.jsLib;
    source.variable = parsed.variable;
    source.respondTime = parsed.respondTime;
    source.concurrentRate = parsed.concurrentRate;
    source.lastUpdateTime = parsed.lastUpdateTime;
    source.rawSourceJson = parsed.rawSourceJson;
    source.engine = parsed.engine;
    source.nativeSearch = parsed.nativeSearch;
    source.ruleSearch = LocalRuleSourceImportParser.parseSearchRule(LocalRuleSourceImportParser.asRecord(JSON.parse(JSON.stringify(parsed.ruleSearch))) ?? {});
    source.ruleExplore = LocalRuleSourceImportParser.parseSearchRule(LocalRuleSourceImportParser.asRecord(JSON.parse(JSON.stringify(parsed.ruleExplore))) ?? {});
    source.ruleBookInfo = LocalRuleSourceImportParser.parseBookInfoRule(LocalRuleSourceImportParser.asRecord(JSON.parse(JSON.stringify(parsed.ruleBookInfo))) ?? {});
    source.ruleToc = LocalRuleSourceImportParser.parseTocRule(LocalRuleSourceImportParser.asRecord(JSON.parse(JSON.stringify(parsed.ruleToc))) ?? {});
    source.ruleContent = LocalRuleSourceImportParser.parseContentRule(LocalRuleSourceImportParser.asRecord(JSON.parse(JSON.stringify(parsed.ruleContent))) ?? {});
    source.validationMessage = '等待测试';
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
    rule.nextPageUrl = LocalRuleSourceImportParser.readString(record, 'nextPageUrl');
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

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error || '未知错误');
  }
}
