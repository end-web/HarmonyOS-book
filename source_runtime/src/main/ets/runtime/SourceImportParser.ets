import {
  BookInfoRule,
  BookSource,
  ContentRule,
  ExploreRule,
  ReviewRule,
  SearchRule,
  SourceSubscription,
  TocRule,
} from '../model/BookSource';

export interface SourceImportResult {
  sources: BookSource[];
  invalidCount: number;
  normalizedCount: number;
}

export class SourceImportParser {
  static parseSources(content: string): SourceImportResult {
    const jsonText = SourceImportParser.extractJsonText(content);
    const parsed = SourceImportParser.parseJson(jsonText);
    if (parsed) {
      const rawList: Object[] = SourceImportParser.extractSourceList(parsed);
      return SourceImportParser.normalizeSourceList(rawList);
    }

    const xmlList = SourceImportParser.parseXmlSources(content);
    if (xmlList.length > 0) {
      return SourceImportParser.normalizeSourceList(xmlList);
    }

    return { sources: [], invalidCount: 0, normalizedCount: 0 };
  }

  static convertToHarmonySources(content: string): string {
    try {
      return JSON.stringify(SourceImportParser.parseSources(content).sources);
    } catch {
      return '[]';
    }
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    const firstName = sources.length > 0 ? sources[0].bookSourceGroup || '未命名' : '未命名';
    return { url, name: firstName, count: sources.length, lastUpdate: Date.now() };
  }

  private static normalizeSourceList(rawList: Object[]): SourceImportResult {
    const sources: BookSource[] = [];
    let invalidCount = 0;
    let normalizedCount = 0;

    for (const item of rawList) {
      const source = SourceImportParser.asBookSource(item);
      if (source) {
        normalizedCount++;
        sources.push(source);
      } else {
        invalidCount++;
      }
    }

    return { sources, invalidCount, normalizedCount };
  }

  private static extractSourceList(value: Object): Object[] {
    if (Array.isArray(value)) return value as Object[];
    if (!value || typeof value !== 'object') return [];
    const record = value as Record<string, Object>;
    const candidates: string[] = [
      'data',
      'list',
      'sources',
      'bookSources',
      'bookSourceList',
      'bookSource',
      'items',
      'result',
      'records',
      'content',
    ];
    for (const key of candidates) {
      const child = record[key];
      if (Array.isArray(child)) return child as Object[];
      if (child && typeof child === 'object') {
        const nested = SourceImportParser.extractSourceList(child);
        if (nested.length > 0) return nested;
      }
    }
    return [value];
  }

  static normalizeSource(value: Object): BookSource | null {
    return SourceImportParser.asBookSource(value);
  }

  private static parseJson(text: string): Object | null {
    const candidates: string[] = [];
    const trimmed = text.trim();
    if (trimmed) candidates.push(trimmed);
    const loose = SourceImportParser.normalizeLooseJson(trimmed);
    if (loose && !candidates.includes(loose)) candidates.push(loose);

    for (const candidate of candidates) {
      try {
        return JSON.parse(candidate) as Object;
      } catch {
        continue;
      }
    }
    return null;
  }

  private static extractJsonText(content: string): string {
    const trimmed = (content || '').trim();
    if (!trimmed) return '';
    const direct = SourceImportParser.extractJsonCandidate(trimmed);
    if (direct) return direct;
    const xml = SourceImportParser.extractJsonFromXml(trimmed);
    if (xml) return xml;
    return trimmed;
  }

  private static extractJsonCandidate(text: string): string {
    const trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return SourceImportParser.trimJsonBoundary(trimmed);
    }

    const exportDefaultMatch = /^export\s+default\s+([\s\S]+)$/i.exec(trimmed);
    if (exportDefaultMatch && exportDefaultMatch[1]) {
      const normalized = SourceImportParser.trimJsonBoundary(exportDefaultMatch[1].trim());
      if (normalized.startsWith('{') || normalized.startsWith('[')) return normalized;
    }

    const moduleMatch = /^module\.exports\s*=\s*([\s\S]+)$/i.exec(trimmed);
    if (moduleMatch && moduleMatch[1]) {
      const normalized = SourceImportParser.trimJsonBoundary(moduleMatch[1].trim());
      if (normalized.startsWith('{') || normalized.startsWith('[')) return normalized;
    }

    const assignmentMatch = /(?:bookSources?|sources?|data|result)\s*=\s*([\s\S]+)/i.exec(trimmed);
    if (assignmentMatch && assignmentMatch[1]) {
      const assigned = SourceImportParser.trimStatementEnd(assignmentMatch[1].trim());
      const normalized = SourceImportParser.trimJsonBoundary(assigned);
      if (normalized.startsWith('{') || normalized.startsWith('[')) return normalized;
    }

    const jsonpMatch = /^[\w$.]+\s*\(([\s\S]*)\)\s*;?\s*$/.exec(trimmed);
    if (jsonpMatch && jsonpMatch[1]) {
      const normalized = SourceImportParser.trimJsonBoundary(jsonpMatch[1].trim());
      if (normalized.startsWith('{') || normalized.startsWith('[')) return normalized;
    }

    return '';
  }

  private static extractJsonFromXml(text: string): string {
    const cdataMatch = /<!\[CDATA\[([\s\S]*?)\]\]>/.exec(text);
    if (cdataMatch && cdataMatch[1]) {
      const normalized = SourceImportParser.extractJsonCandidate(cdataMatch[1]);
      if (normalized) return normalized;
    }

    const decoded = SourceImportParser.decodeXmlEntities(text);
    const normalized = SourceImportParser.extractJsonByBoundary(decoded);
    return normalized;
  }

  private static parseXmlSources(content: string): Object[] {
    const decoded = SourceImportParser.decodeXmlEntities(content || '');
    const list: Object[] = [];
    const itemRegex = /<(?:bookSource|source|item)\b[^>]*>([\s\S]*?)<\/(?:bookSource|source|item)>/gi;
    let match: RegExpExecArray | null = itemRegex.exec(decoded);
    while (match) {
      const record = SourceImportParser.xmlBlockToRecord(match[1]);
      if (Object.keys(record).length > 0) list.push(record as Object);
      match = itemRegex.exec(decoded);
    }
    if (list.length > 0) return list;
    const single = SourceImportParser.xmlBlockToRecord(decoded);
    return Object.keys(single).length > 0 ? [single as Object] : [];
  }

  private static xmlBlockToRecord(block: string): Record<string, Object> {
    const record: Record<string, Object> = {};
    const tagRegex = /<([A-Za-z][\w.-]*)\b[^>]*>([\s\S]*?)<\/\1>/g;
    let match: RegExpExecArray | null = tagRegex.exec(block);
    while (match) {
      const key = match[1];
      const rawValue = match[2].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim();
      if (!key || rawValue.length === 0) {
        match = tagRegex.exec(block);
        continue;
      }
      const jsonValue = SourceImportParser.parseJson(SourceImportParser.extractJsonText(rawValue));
      record[key] = jsonValue || SourceImportParser.decodeXmlEntities(rawValue);
      match = tagRegex.exec(block);
    }
    return record;
  }

  private static normalizeLooseJson(text: string): string {
    if (!text) return '';
    let out = SourceImportParser.stripJsComments(text);
    out = out
      .replace(/[\u201C\u201D]/g, '"')
      .replace(/[\u2018\u2019]/g, "'");
    out = out.replace(/([{,]\s*)([A-Za-z_$][\w$-]*)\s*:/g, '$1"$2":');
    out = out.replace(/,\s*([}\]])/g, '$1');
    return out;
  }

  private static stripJsComments(text: string): string {
    let out = '';
    let quote = '';
    let escaped = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      const next = i + 1 < text.length ? text.charAt(i + 1) : '';
      if (quote) {
        out += ch;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        out += ch;
        continue;
      }
      if (ch === '/' && next === '/') {
        while (i < text.length && text.charAt(i) !== '\n') i++;
        out += '\n';
        continue;
      }
      if (ch === '/' && next === '*') {
        i += 2;
        while (i + 1 < text.length && !(text.charAt(i) === '*' && text.charAt(i + 1) === '/')) i++;
        i++;
        continue;
      }
      out += ch;
    }
    return out;
  }

  private static extractJsonByBoundary(text: string): string {
    const arrayStart = text.indexOf('[');
    const objectStart = text.indexOf('{');
    let start = -1;
    if (arrayStart >= 0 && objectStart >= 0) {
      start = Math.min(arrayStart, objectStart);
    } else {
      start = Math.max(arrayStart, objectStart);
    }
    if (start < 0) return '';

    const endArray = text.lastIndexOf(']');
    const endObject = text.lastIndexOf('}');
    const end = Math.max(endArray, endObject);
    if (end <= start) return '';
    return text.substring(start, end + 1).trim();
  }

  private static trimJsonBoundary(text: string): string {
    return SourceImportParser.extractJsonByBoundary(text) || SourceImportParser.trimStatementEnd(text);
  }

  private static trimStatementEnd(text: string): string {
    let out = text.trim();
    while (out.endsWith(';')) {
      out = out.substring(0, out.length - 1).trim();
    }
    return out;
  }

  private static decodeXmlEntities(text: string): string {
    return text
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  private static asBookSource(value: Object): BookSource | null {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const record = value as Record<string, Object>;
    const sourceUrl = SourceImportParser.readStringAny(record, ['bookSourceUrl', 'sourceUrl', 'url']);
    const sourceName = SourceImportParser.readStringAny(record, ['bookSourceName', 'sourceName', 'name']);
    if (!sourceUrl || !sourceName) {
      return null;
    }
    const source = value as BookSource;
    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = SourceImportParser.readNumber(record, 'bookSourceType', 0);
    source.bookSourceGroup = SourceImportParser.readStringAny(record, ['bookSourceGroup', 'sourceGroup', 'group']);
    source.bookSourceComment = SourceImportParser.readOptionalString(record, 'bookSourceComment');
    source.enabled = SourceImportParser.readBoolean(record, 'enabled', true);
    source.enabledExplore = SourceImportParser.readBoolean(record, 'enabledExplore', false);
    source.enabledCookieJar = SourceImportParser.readBoolean(record, 'enabledCookieJar', false);
    source.searchUrl = SourceImportParser.readString(record, 'searchUrl');
    source.exploreUrl = SourceImportParser.readString(record, 'exploreUrl');
    source.header = SourceImportParser.normalizeHeader(record['header']);
    source.loginUrl = SourceImportParser.readOptionalString(record, 'loginUrl');
    source.loginUi = SourceImportParser.readOptionalString(record, 'loginUi');
    source.loginCheckJs = SourceImportParser.readOptionalString(record, 'loginCheckJs');
    source.bookUrlPattern = SourceImportParser.readOptionalString(record, 'bookUrlPattern');
    source.variableComment = SourceImportParser.readOptionalString(record, 'variableComment');
    source.jsLib = SourceImportParser.readOptionalString(record, 'jsLib');
    source.customButton = SourceImportParser.readBoolean(record, 'customButton', false);
    source.eventListener = SourceImportParser.readBoolean(record, 'eventListener', false);
    source.exploreScreen = SourceImportParser.readOptionalString(record, 'exploreScreen');
    source.coverDecodeJs = SourceImportParser.readOptionalString(record, 'coverDecodeJs');
    source.respondTime = SourceImportParser.readNumber(record, 'respondTime', 0);
    source.customOrder = SourceImportParser.readNumber(record, 'customOrder', 0);
    source.weight = SourceImportParser.readNumber(record, 'weight', 0);
    source.concurrentRate = SourceImportParser.readOptionalString(record, 'concurrentRate');
    source.ruleSearch = SourceImportParser.normalizeSearchRule(record['ruleSearch'], record['ruleBookList']);
    source.ruleToc = SourceImportParser.normalizeTocRule(record['ruleToc'], record['ruleChapter']);
    source.ruleContent = SourceImportParser.normalizeContentRule(record['ruleContent']);
    source.ruleBookInfo = SourceImportParser.normalizeBookInfoRule(record['ruleBookInfo'], record['ruleBookInfoInit']);
    source.ruleExplore = SourceImportParser.normalizeExploreRule(record['ruleExplore']);
    source.ruleReview = SourceImportParser.normalizeReviewRule(record['ruleReview']);
    source.lastUpdateTime = SourceImportParser.readOptionalNumber(record, 'lastUpdateTime');
    source.subscriptionUrl = SourceImportParser.readOptionalString(record, 'subscriptionUrl');
    return source;
  }

  private static asRecord(value: Object | undefined): Record<string, Object> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {} as Record<string, Object>;
    return value as Record<string, Object>;
  }

  private static readString(record: Record<string, Object>, key: string, fallback: string = ''): string {
    const value = record[key];
    if (value === undefined || value === null) return fallback;
    return String(value);
  }

  private static readStringAny(record: Record<string, Object>, keys: string[], fallback: string = ''): string {
    for (const key of keys) {
      const value = record[key];
      if (value !== undefined && value !== null && String(value).length > 0) return String(value);
    }
    return fallback;
  }

  private static readStringAnyFromRecords(
    records: Record<string, Object>[], keys: string[], fallback: string = ''
  ): string {
    for (const record of records) {
      const value = SourceImportParser.readStringAny(record, keys);
      if (value.length > 0) return value;
    }
    return fallback;
  }

  private static readOptionalString(record: Record<string, Object>, key: string): string | undefined {
    const value = record[key];
    if (value === undefined || value === null) return undefined;
    return String(value);
  }

  private static readOptionalStringAny(record: Record<string, Object>, keys: string[]): string | undefined {
    for (const key of keys) {
      const value = record[key];
      if (value !== undefined && value !== null && String(value).length > 0) return String(value);
    }
    return undefined;
  }

  private static readNumber(record: Record<string, Object>, key: string, fallback: number): number {
    const value = record[key];
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const parsed = Number(value);
      return isNaN(parsed) ? fallback : parsed;
    }
    return fallback;
  }

  private static readOptionalNumber(record: Record<string, Object>, key: string): number | undefined {
    const value = record[key];
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const parsed = Number(value);
      return isNaN(parsed) ? undefined : parsed;
    }
    return undefined;
  }

  private static readBoolean(record: Record<string, Object>, key: string, fallback: boolean): boolean {
    const value = record[key];
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      const lower = value.toLowerCase();
      if (lower === 'true') return true;
      if (lower === 'false') return false;
    }
    return fallback;
  }

  private static normalizeHeader(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value;
    try {
      return JSON.stringify(value);
    } catch {
      return '';
    }
  }

  private static normalizeSearchRule(value: Object | undefined, fallbackValue?: Object): SearchRule {
    const record = SourceImportParser.asRecord(value);
    const fallbackRecord = SourceImportParser.asRecord(fallbackValue);
    const records: Record<string, Object>[] = [record, fallbackRecord];
    return {
      bookList: SourceImportParser.readStringAnyFromRecords(records, ['bookList']),
      name: SourceImportParser.readStringAnyFromRecords(records, ['name', 'bookName']),
      author: SourceImportParser.readStringAnyFromRecords(records, ['author', 'bookAuthor']),
      coverUrl: SourceImportParser.readStringAnyFromRecords(records, ['coverUrl', 'bookCover']),
      bookUrl: SourceImportParser.readStringAnyFromRecords(records, ['bookUrl']),
      intro: SourceImportParser.readStringAnyFromRecords(records, ['intro', 'bookIntro']),
      kind: SourceImportParser.readStringAnyFromRecords(records, ['kind', 'bookCategory']),
      lastChapter: SourceImportParser.readStringAnyFromRecords(records, ['lastChapter', 'bookStatus']),
      wordCount: SourceImportParser.readOptionalString(record, 'wordCount') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'wordCount'),
      checkKeyWord: SourceImportParser.readOptionalString(record, 'checkKeyWord') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'checkKeyWord'),
      updateTime: SourceImportParser.readOptionalString(record, 'updateTime') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'updateTime'),
    };
  }

  private static normalizeTocRule(value: Object | undefined, fallbackValue?: Object): TocRule {
    const record = SourceImportParser.asRecord(value);
    const fallbackRecord = SourceImportParser.asRecord(fallbackValue);
    const records: Record<string, Object>[] = [record, fallbackRecord];
    return {
      chapterList: SourceImportParser.readStringAnyFromRecords(records, ['chapterList', 'tocList']),
      chapterName: SourceImportParser.readStringAnyFromRecords(records, ['chapterName', 'name', 'title']),
      chapterUrl: SourceImportParser.readStringAnyFromRecords(records, ['chapterUrl', 'url']),
      nextTocUrl: SourceImportParser.readOptionalString(record, 'nextTocUrl') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'nextTocUrl'),
      isVip: SourceImportParser.readOptionalString(record, 'isVip') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'isVip'),
      isPay: SourceImportParser.readOptionalString(record, 'isPay') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'isPay'),
      isVolume: SourceImportParser.readOptionalString(record, 'isVolume') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'isVolume'),
      updateTime: SourceImportParser.readOptionalString(record, 'updateTime') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'updateTime'),
      duration: SourceImportParser.readOptionalString(record, 'duration') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'duration'),
      preUpdateJs: SourceImportParser.readOptionalString(record, 'preUpdateJs') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'preUpdateJs'),
      formatJs: SourceImportParser.readOptionalString(record, 'formatJs') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'formatJs'),
    };
  }

  private static normalizeContentRule(value: Object | undefined): ContentRule {
    const record = SourceImportParser.asRecord(value);
    return {
      content: SourceImportParser.readStringAny(record, ['content', 'textContent']),
      title: SourceImportParser.readOptionalString(record, 'title'),
      audioUrl: SourceImportParser.readOptionalStringAny(record, ['audioUrl', 'audio', 'playUrl']),
      nextContentUrl: SourceImportParser.readOptionalString(record, 'nextContentUrl'),
      replaceRegex: SourceImportParser.readOptionalString(record, 'replaceRegex'),
      sourceRegex: SourceImportParser.readOptionalString(record, 'sourceRegex'),
      webJs: SourceImportParser.readOptionalString(record, 'webJs'),
    };
  }

  private static normalizeBookInfoRule(value: Object | undefined, fallbackValue?: Object): BookInfoRule {
    const record = SourceImportParser.asRecord(value);
    const fallbackRecord = SourceImportParser.asRecord(fallbackValue);
    const records: Record<string, Object>[] = [record, fallbackRecord];
    return {
      init: SourceImportParser.readOptionalString(record, 'init') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'init'),
      name: SourceImportParser.readStringAnyFromRecords(records, ['name', 'bookName']),
      author: SourceImportParser.readStringAnyFromRecords(records, ['author', 'bookAuthor']),
      coverUrl: SourceImportParser.readStringAnyFromRecords(records, ['coverUrl', 'bookCover']),
      intro: SourceImportParser.readStringAnyFromRecords(records, ['intro', 'bookIntro']),
      kind: SourceImportParser.readOptionalStringAny(record, ['kind', 'bookCategory']),
      wordCount: SourceImportParser.readOptionalString(record, 'wordCount') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'wordCount'),
      lastChapter: SourceImportParser.readOptionalStringAny(record, ['lastChapter', 'bookStatus']),
      updateTime: SourceImportParser.readOptionalString(record, 'updateTime') ||
        SourceImportParser.readOptionalString(fallbackRecord, 'updateTime'),
      tocUrl: SourceImportParser.readStringAnyFromRecords(records, ['tocUrl', 'chapterUrl']),
      canReName: SourceImportParser.readOptionalString(record, 'canReName'),
      downloadUrls: SourceImportParser.readOptionalString(record, 'downloadUrls'),
    };
  }

  private static normalizeExploreRule(value: Object | undefined): ExploreRule {
    const record = SourceImportParser.asRecord(value);
    return {
      bookList: SourceImportParser.readString(record, 'bookList'),
      name: SourceImportParser.readStringAny(record, ['name', 'bookName']),
      author: SourceImportParser.readStringAny(record, ['author', 'bookAuthor']),
      coverUrl: SourceImportParser.readStringAny(record, ['coverUrl', 'bookCover']),
      bookUrl: SourceImportParser.readString(record, 'bookUrl'),
      intro: SourceImportParser.readStringAny(record, ['intro', 'bookIntro']),
      kind: SourceImportParser.readStringAny(record, ['kind', 'bookCategory']),
      lastChapter: SourceImportParser.readStringAny(record, ['lastChapter', 'bookStatus']),
      updateTime: SourceImportParser.readOptionalString(record, 'updateTime'),
      wordCount: SourceImportParser.readOptionalString(record, 'wordCount'),
    };
  }

  private static normalizeReviewRule(value: Object | undefined): ReviewRule | undefined {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
    const record = SourceImportParser.asRecord(value);
    return {
      reviewList: SourceImportParser.readOptionalString(record, 'reviewList'),
      avatar: SourceImportParser.readOptionalString(record, 'avatar'),
      name: SourceImportParser.readOptionalString(record, 'name'),
      time: SourceImportParser.readOptionalString(record, 'time'),
      title: SourceImportParser.readOptionalString(record, 'title'),
      content: SourceImportParser.readOptionalString(record, 'content'),
      reviewUrl: SourceImportParser.readOptionalString(record, 'reviewUrl'),
    };
  }
}
