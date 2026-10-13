import { url } from '@kit.ArkTS';
import { BookInfo, SearchResult, TocItem } from '../../../model/BookSource';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleExploreResult } from '../../../model/LocalRulePanel';
import { LocalRuleContentResult, LocalRuleExecutionLimits, LocalRuleRequestPlan } from '../LocalRuleRuntimeTypes';
import { LocalRuleHttpClient } from '../LocalRuleHttpClient';
import { LocalRuleDiagnostics } from '../LocalRuleDiagnostics';
import { LocalRuleJsonPath } from '../LocalRuleJsonPath';
import { LocalRuleMetadataText } from '../LocalRuleMetadataText';
import { NativeRuleDefinition, NativeNamedValue, NativeStage } from './NativeRuleSchema';
import { NativeRuleValues, NativeValueContext } from './NativeRuleValues';
import { NativeSourceDefinition } from './NativeSourceDefinition';
import { NativeRuleDocumentRuntime } from './NativeRuleDocumentRuntime';
import { CoverPrefetcher } from '../../CoverPrefetcher';

class NativeSearchResult implements SearchResult {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  contentType: 'audio' | 'text' = 'text';
  completed: boolean | undefined = undefined;
  lastChapter: string = '';
  wordCount: string = '';
  updateTime: string = '';
  sourceName: string = '';
  sourceUrl: string = '';
}

class NativeBookInfo implements BookInfo {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  completed: boolean | undefined = undefined;
  wordCount: string = '';
  lastChapter: string = '';
  tocUrl: string = '';
  updateTime: string = '';
}

class NativeTocItem implements TocItem {
  name: string = '';
  url: string = '';
  isVip: boolean = false;
  isPay: boolean = false;
  isVolume: boolean = false;
  duration: number = 0;
  updateTime: string = '';
  variables: Record<string, string> = {};
}

class NativeStageResult {
  context: NativeValueContext = new NativeValueContext();
  fields: Map<string, string> = new Map();
  responseCharacters: number = 0;
  nextUrl: string = '';
}

/** The native-v1 path consumes typed data only; it never calls the legacy extraction or script engines. */
export class NativeRuleDispatcher {
  private static warmedOrigins: Map<string, number> = new Map();

  private static warmAudioRequest(source: LocalRuleSource, rules: NativeRuleDefinition): void {
    if (!source.isAudio()) return;
    const value = rules.content.request.url;
    if (value.kind !== 'literal' && value.kind !== 'template') return;
    // Only a fixed origin is safe to warm. Never evaluate bindings or short-lived signatures here.
    const match = new RegExp('^(https?://[^/?#{}\\s]+)(?:[/?#]|$)', 'i').exec(value.value);
    if (match === null) return;
    try {
      const address = url.URL.parseURL(match[1]);
      if (!address.hostname || address.username || address.password) return;
      const now = Date.now();
      const previous = NativeRuleDispatcher.warmedOrigins.get(address.origin);
      if (previous !== undefined && now - previous >= 0 && now - previous < 30000) return;
      if (NativeRuleDispatcher.warmedOrigins.size >= 32) NativeRuleDispatcher.warmedOrigins.clear();
      NativeRuleDispatcher.warmedOrigins.set(address.origin, now);
      LocalRuleHttpClient.preconnectNative(address.origin);
    } catch (_error) { /* Connection warming must never block detail or catalog requests. */ }
  }
  static async search(source: LocalRuleSource, keyword: string, page: number,
    diagnostics: Record<string, string> = {}): Promise<SearchResult[]> {
    const rules = NativeSourceDefinition.rules(source);
    if (!source.hasSearchCapability()) throw new Error('原生书源没有搜索规则');
    const context = NativeRuleDispatcher.context(NativeRuleDispatcher.networkBase(source), keyword, page);
    const result = await NativeRuleDispatcher.run(source, rules, rules.search, context, diagnostics);
    return NativeRuleDispatcher.books(source, rules.search, result, LocalRuleExecutionLimits.MAX_SEARCH_RESULTS, diagnostics);
  }

  static async explore(source: LocalRuleSource, address: string, page: number,
    diagnostics: Record<string, string>, limit: number): Promise<LocalRuleExploreResult> {
    const rules = NativeSourceDefinition.rules(source);
    const stage = rules.explore.fields.length > 0 ? rules.explore : rules.search;
    const context = NativeRuleDispatcher.context(NativeRuleDispatcher.networkBase(source), '', page);
    const expanded = NativeRuleValues.expand(address, context.variables);
    context.variables.set('url', NativeRuleDispatcher.resolve(context.baseUrl, expanded));
    const result = await NativeRuleDispatcher.run(source, rules, stage, context, diagnostics,
      context.variables.get('url') ?? '', false, rules.explore.fields.length === 0);
    const output = new LocalRuleExploreResult();
    output.books = await NativeRuleDispatcher.books(source, stage, result,
      Math.max(1, Math.min(LocalRuleExecutionLimits.MAX_SEARCH_RESULTS, limit)), diagnostics);
    output.nextUrl = result.nextUrl;
    if (!output.nextUrl && output.books.length > 0 &&
      (address.includes('{{page}}') || address.includes('{{page0}}'))) output.nextUrl = address;
    return output;
  }

  static async detail(source: LocalRuleSource, bookUrl: string,
    diagnostics: Record<string, string>): Promise<BookInfo> {
    const rules = NativeSourceDefinition.rules(source);
    NativeRuleDispatcher.warmAudioRequest(source, rules);
    const context = NativeRuleDispatcher.context(bookUrl);
    context.variables.set('bookUrl', bookUrl);
    const result = await NativeRuleDispatcher.run(source, rules, rules.detail, context, diagnostics);
    const fields = result.fields;
    const book = new NativeBookInfo();
    book.name = NativeRuleDispatcher.short(fields, 'name', 120);
    book.author = NativeRuleDispatcher.short(fields, 'author', 120);
    book.intro = LocalRuleMetadataText.intro(NativeRuleDispatcher.short(fields, 'intro', 4000));
    book.kind = NativeRuleDispatcher.short(fields, 'kind', 256);
    book.lastChapter = NativeRuleDispatcher.short(fields, 'lastChapter', 256);
    book.wordCount = NativeRuleDispatcher.short(fields, 'wordCount', 80);
    book.updateTime = NativeRuleDispatcher.short(fields, 'updateTime', 120);
    book.coverUrl = NativeRuleDispatcher.resolve(result.context.baseUrl, fields.get('coverUrl') ?? '');
    await NativeRuleDispatcher.cover(source, rules, result.context, book.coverUrl);
    book.tocUrl = NativeRuleDispatcher.resolve(result.context.baseUrl, fields.get('tocUrl') ?? '') || result.context.baseUrl;
    book.completed = NativeRuleDispatcher.status(fields.get('status') ?? '');
    return book;
  }

  static async toc(source: LocalRuleSource, tocUrl: string, diagnostics: Record<string, string>,
    onBatch?: (items: TocItem[]) => void): Promise<TocItem[]> {
    const rules = NativeSourceDefinition.rules(source);
    NativeRuleDispatcher.warmAudioRequest(source, rules);
    const output: TocItem[] = [];
    const seenPages: Set<string> = new Set();
    const seenChapters: Set<string> = new Set();
    let current = tocUrl;
    let responseCharacters = 0;
    for (let page = 1; current && page <= rules.toc.maxPages; page++) {
      if (seenPages.has(current)) throw new Error('原生目录分页形成循环');
      seenPages.add(current);
      const context = NativeRuleDispatcher.context(current, '', page);
      context.variables.set('bookUrl', diagnostics['bookUrl'] || tocUrl);
      const result = await NativeRuleDispatcher.run(source, rules, rules.toc, context, diagnostics,
        page > 1 ? current : '');
      responseCharacters += result.responseCharacters;
      if (responseCharacters > LocalRuleExecutionLimits.MAX_STAGE_RESPONSE_CHARS) throw new Error('原生目录响应超过预算');
      const rows = NativeRuleDispatcher.rows(rules.toc, result.context);
      const batch: TocItem[] = [];
      for (const row of rows) {
        LocalRuleDiagnostics.check(diagnostics);
        const fields = await NativeRuleDispatcher.fields(rules.toc.fields, row);
        const item = new NativeTocItem();
        item.name = NativeRuleDispatcher.short(fields, 'chapterName', 256);
        item.url = NativeRuleDispatcher.resolve(result.context.baseUrl, fields.get('chapterUrl') ?? '');
        item.isVolume = NativeRuleDispatcher.flag(fields.get('isVolume'));
        if (!item.name || (!item.url && !item.isVolume)) throw new Error('原生目录缺少章节名称或地址');
        if (item.url && seenChapters.has(item.url)) continue;
        if (output.length >= LocalRuleExecutionLimits.MAX_TOC_ITEMS) throw new Error('原生目录章节数量超过预算');
        if (item.url) seenChapters.add(item.url);
        item.isVip = NativeRuleDispatcher.flag(fields.get('isVip'));
        item.isPay = NativeRuleDispatcher.flag(fields.get('isPay'));
        item.updateTime = NativeRuleDispatcher.short(fields, 'updateTime', 120);
        const duration = Number(fields.get('duration') ?? '0');
        item.duration = Number.isFinite(duration) && duration > 0 ? duration : 0;
        item.variables['bookUrl'] = context.variables.get('bookUrl') ?? tocUrl;
        output.push(item);
        batch.push(item);
      }
      if (onBatch !== undefined && batch.length > 0) onBatch(batch);
      current = result.nextUrl;
      if (current && page === rules.toc.maxPages) throw new Error('原生目录分页超过声明的 maxPages');
    }
    return output;
  }

  static async content(source: LocalRuleSource, chapterUrl: string,
    diagnostics: Record<string, string>): Promise<LocalRuleContentResult> {
    const rules = NativeSourceDefinition.rules(source);
    const output = new LocalRuleContentResult();
    const seen: Set<string> = new Set();
    let current = chapterUrl;
    let total = 0;
    for (let page = 1; current && page <= rules.content.maxPages; page++) {
      if (seen.has(current)) throw new Error('原生正文分页形成循环');
      seen.add(current);
      const context = NativeRuleDispatcher.context(current, '', page);
      context.variables.set('chapterUrl', chapterUrl);
      context.variables.set('bookUrl', diagnostics['bookUrl'] || '');
      // The timestamp is bound once per actual resolution, including after resuming or downloading.
      const result = await NativeRuleDispatcher.run(source, rules, rules.content, context, diagnostics,
        page > 1 ? current : '', source.isAudio() && !rules.content.request.url.value);
      total += result.responseCharacters;
      if (total > LocalRuleExecutionLimits.MAX_STAGE_RESPONSE_CHARS) throw new Error('原生正文响应超过预算');
      if (!output.title) output.title = NativeRuleDispatcher.short(result.fields, 'title', 256);
      if (source.isAudio()) {
        output.audioUrl = NativeRuleValues.resolveUrl(
          result.fields.get('audioUrl') || result.fields.get('content') || '', result.context.baseUrl);
        if (!output.audioUrl || output.audioUrl.length > LocalRuleExecutionLimits.MAX_URL_CHARS) {
          throw new Error('原生音频规则没有返回有效地址或地址超过长度预算');
        }
        const headers = await NativeRuleDispatcher.sourceHeaders(source, rules.headers, context, output.audioUrl);
        if (source.enabledCookieJar) {
          await LocalRuleHttpClient.hydrateCookies(source.bookSourceUrl);
          const cookie = LocalRuleHttpClient.getCookieHeader(source, output.audioUrl);
          if (cookie) headers.set('cookie', cookie);
        }
        output.requestHeaders = NativeRuleDispatcher.record(headers);
        return output;
      }
      const text = result.fields.get('content') ?? '';
      if (!text.trim()) throw new Error('原生正文规则没有返回内容');
      output.content += `${output.content ? '\n' : ''}${text}`;
      if (output.content.length > LocalRuleExecutionLimits.MAX_CONTENT_CHARS) throw new Error('原生正文内容超过预算');
      current = result.nextUrl;
      if (current && page === rules.content.maxPages) throw new Error('原生正文分页超过声明的 maxPages');
    }
    return output;
  }

  private static context(address: string, keyword: string = '', page: number = 1): NativeValueContext {
    if (!Number.isInteger(page) || page < 1 || page > 100000) throw new Error('原生规则页码无效');
    const context = new NativeValueContext();
    context.baseUrl = address;
    context.variables.set('url', address);
    context.variables.set('key', keyword);
    context.variables.set('page', String(page));
    context.variables.set('page0', String(page - 1));
    context.variables.set('timestamp', String(Math.floor(Date.now() / 1000)));
    context.variables.set('bookUrl', '');
    context.variables.set('chapterUrl', '');
    return context;
  }

  private static async run(source: LocalRuleSource, rules: NativeRuleDefinition, stage: NativeStage,
    context: NativeValueContext, diagnostics: Record<string, string>, override: string = '',
    direct: boolean = false, overrideGet: boolean = true): Promise<NativeStageResult> {
    LocalRuleDiagnostics.check(diagnostics);
    for (const binding of stage.bindings) {
      context.variables.set(binding.name, await NativeRuleValues.evaluate(binding.value, context));
    }
    const result = new NativeStageResult();
    result.context = context;
    if (!direct) {
      const address = override || await NativeRuleValues.evaluate(stage.request.url, context) ||
        context.variables.get('url') || '';
      const plan = new LocalRuleRequestPlan();
      plan.url = NativeRuleDispatcher.resolve(context.baseUrl, address);
      const forceGet = override.length > 0 && overrideGet;
      plan.method = forceGet ? 'GET' : stage.request.method;
      const headers = await NativeRuleDispatcher.sourceHeaders(source, rules.headers, context, plan.url);
      const requestHeaders = await NativeRuleDispatcher.headers(stage.request.headers, context);
      requestHeaders.forEach((value: string, key: string): void => { headers.set(key, value); });
      if (!forceGet && stage.request.form.length > 0) {
        const parts: string[] = [];
        for (const item of stage.request.form) {
          const value = await NativeRuleValues.evaluate(item.value, context);
          parts.push(`${encodeURIComponent(item.name)}=${encodeURIComponent(value)}`);
        }
        plan.body = parts.join('&');
        if (!headers.has('content-type')) headers.set('content-type', 'application/x-www-form-urlencoded; charset=utf-8');
      } else if (!forceGet && stage.request.body.value) {
        plan.body = await NativeRuleValues.evaluate(stage.request.body, context);
      }
      plan.headers = NativeRuleDispatcher.record(headers);
      const response = await LocalRuleHttpClient.fetchNativePlan(source, plan, diagnostics);
      if (!response.ok) throw new Error(response.errorMessage || `HTTP ${response.statusCode}`);
      context.baseUrl = response.requestUrl;
      context.variables.set('responseUrl', response.requestUrl);
      context.variables.set('response', response.body);
      result.responseCharacters = response.body.length;
      if (stage.format === 'html') context.html = await NativeRuleDocumentRuntime.parseHtml(response.body);
      if (stage.format === 'json') {
        JSON.parse(response.body);
        context.json = response.body;
      }
    }
    if (!stage.list.value) result.fields = await NativeRuleDispatcher.fields(stage.fields, context);
    result.nextUrl = NativeRuleDispatcher.resolve(context.baseUrl,
      await NativeRuleValues.evaluate(stage.next, context) || result.fields.get('nextContentUrl') || '');
    return result;
  }

  private static rows(stage: NativeStage, context: NativeValueContext): NativeValueContext[] {
    const output: NativeValueContext[] = [];
    if (stage.list.kind === 'css' && context.html !== undefined) {
      for (const node of context.html.select(stage.list.value)) {
        const row = NativeRuleDispatcher.rowContext(context);
        row.node = node;
        output.push(row);
      }
    } else if (stage.list.kind === 'json') {
      for (const match of LocalRuleJsonPath.queryPayload(context.json, stage.list.value)) {
        const row = NativeRuleDispatcher.rowContext(context);
        row.json = JSON.stringify(match);
        output.push(row);
      }
    } else throw new Error('原生列表规则必须为 CSS 或 JSON 路径');
    return output;
  }

  private static rowContext(context: NativeValueContext): NativeValueContext {
    const row = new NativeValueContext();
    row.variables = new Map(context.variables);
    row.baseUrl = context.baseUrl;
    row.html = context.html;
    row.json = context.json;
    return row;
  }

  private static async books(source: LocalRuleSource, stage: NativeStage, result: NativeStageResult,
    limit: number, diagnostics: Record<string, string>): Promise<SearchResult[]> {
    const rules = NativeSourceDefinition.rules(source);
    const output: SearchResult[] = [];
    const seen: Set<string> = new Set();
    const rows = NativeRuleDispatcher.rows(stage, result.context);
    for (const row of rows) {
      if (output.length >= limit) break;
      LocalRuleDiagnostics.check(diagnostics);
      const fields = await NativeRuleDispatcher.fields(stage.fields, row);
      const book = new NativeSearchResult();
      book.name = NativeRuleDispatcher.short(fields, 'name', 120);
      book.bookUrl = NativeRuleDispatcher.resolve(row.baseUrl, fields.get('bookUrl') ?? '');
      if (!book.name || !book.bookUrl || seen.has(book.bookUrl)) continue;
      seen.add(book.bookUrl);
      book.author = NativeRuleDispatcher.short(fields, 'author', 120);
      book.coverUrl = NativeRuleDispatcher.resolve(row.baseUrl, fields.get('coverUrl') ?? '');
      await NativeRuleDispatcher.cover(source, rules, row, book.coverUrl);
      book.intro = LocalRuleMetadataText.intro(NativeRuleDispatcher.short(fields, 'intro', 4000));
      book.kind = NativeRuleDispatcher.short(fields, 'kind', 256);
      book.lastChapter = NativeRuleDispatcher.short(fields, 'lastChapter', 256);
      book.wordCount = NativeRuleDispatcher.short(fields, 'wordCount', 80);
      book.updateTime = NativeRuleDispatcher.short(fields, 'updateTime', 120);
      book.completed = NativeRuleDispatcher.status(fields.get('status') ?? '');
      book.sourceUrl = source.bookSourceUrl;
      book.sourceName = source.bookSourceName;
      book.contentType = source.isAudio() ? 'audio' : 'text';
      output.push(book);
    }
    return output;
  }

  private static async fields(fields: NativeNamedValue[], context: NativeValueContext): Promise<Map<string, string>> {
    const result: Map<string, string> = new Map();
    for (const field of fields) result.set(field.name, await NativeRuleValues.evaluate(field.value, context));
    return result;
  }

  private static async headers(fields: NativeNamedValue[], context: NativeValueContext): Promise<Map<string, string>> {
    const result: Map<string, string> = new Map();
    for (const field of fields) {
      const value = await NativeRuleValues.evaluate(field.value, context);
      if (new RegExp('[\\r\\n]').test(value)) throw new Error('请求头包含换行');
      result.set(field.name.toLowerCase(), value);
    }
    return result;
  }

  private static record(values: Map<string, string>): Record<string, string> {
    const fields: string[] = [];
    values.forEach((value: string, key: string): void => {
      fields.push(`${JSON.stringify(key)}:${JSON.stringify(value)}`);
    });
    const record: Record<string, string> = JSON.parse(`{${fields.join(',')}}`);
    return record;
  }

  private static networkBase(source: LocalRuleSource): string {
    return source.nativeBaseUrl || source.bookSourceUrl;
  }

  /** Source-wide credentials belong to the declared network origin. Stage headers are explicit per-request values. */
  private static async sourceHeaders(source: LocalRuleSource, fields: NativeNamedValue[],
    context: NativeValueContext, address: string): Promise<Map<string, string>> {
    const headers = await NativeRuleDispatcher.headers(fields, context);
    if (url.URL.parseURL(address).origin !== url.URL.parseURL(NativeRuleDispatcher.networkBase(source)).origin) {
      headers.delete('cookie');
      headers.delete('authorization');
      headers.delete('proxy-authorization');
      headers.delete('host');
    }
    return headers;
  }

  private static resolve(base: string, value: string): string {
    if (!value.trim()) return '';
    const resolved = url.URL.parseURL(value.trim(), base).href;
    if (!new RegExp('^https?://', 'i').test(resolved) || resolved.length > LocalRuleExecutionLimits.MAX_URL_CHARS) {
      throw new Error('原生书源只接受 HTTP(S) 地址');
    }
    return resolved;
  }

  private static short(fields: Map<string, string>, name: string, length: number): string {
    return (fields.get(name) ?? '').trim().substring(0, length);
  }

  private static flag(value: string | undefined): boolean {
    return value !== undefined && ['true', '1', 'yes'].includes(value.trim().toLowerCase());
  }

  private static status(value: string): boolean | undefined {
    if (!value.trim()) return undefined;
    return NativeRuleDispatcher.flag(value) || new RegExp('完结|完本|completed', 'i').test(value);
  }

  private static async cover(source: LocalRuleSource, rules: NativeRuleDefinition,
    context: NativeValueContext, address: string): Promise<void> {
    if (!address) return;
    const headers = await NativeRuleDispatcher.sourceHeaders(source, rules.headers, context, address);
    if (!headers.has('referer')) headers.set('referer', context.baseUrl);
    CoverPrefetcher.registerHeaders(address, NativeRuleDispatcher.record(headers));
  }
}
