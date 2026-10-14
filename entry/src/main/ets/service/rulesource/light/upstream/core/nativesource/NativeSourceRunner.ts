/**
 * 原生书源执行器：按定义依次完成请求、取列表、取字段，全程不经过任何脚本引擎。
 *
 * 网络与选择器通过 NativeRunnerHost 注入，本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { NativeExpr, NativeScope } from './NativeExpr';
import type { NativeExprHost, NativeValue } from './NativeExpr';
import type {
  NativeCommentsSpec, NativeContentSpec, NativeFetchSpec, NativeRequestSpec, NativeSourceDefinition, NativeStageSpec
} from './NativeSourceSpec';

export interface NativeRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
  webView: boolean;
}

export interface NativeLoginState {
  ok: boolean;
  name: string;
  message: string;
}

export interface NativeResponse {
  ok: boolean;
  status: number;
  body: string;
  url: string;
  error: string;
}

export interface NativeRunnerHost extends NativeExprHost {
  fetch(request: NativeRequest): Promise<NativeResponse>;
  /** 按列表规则取出元素：JSON 元素返回对象，HTML 元素返回外层 HTML 文本。 */
  selectItems(content: string, rule: string, baseUrl: string): NativeValue[];
}

export interface NativeBookRecord {
  name: string;
  author: string;
  kind: string;
  intro: string;
  coverUrl: string;
  wordCount: string;
  lastChapter: string;
  updateTime: string;
  status: string;
  bookUrl: string;
  tocUrl: string;
  /** text | audio | comic | video，空串表示沿用书源类型。 */
  type: string;
  keep: Record<string, string>;
}

export interface NativeBookInput {
  bookUrl: string;
  tocUrl: string;
  name: string;
  author: string;
  kind: string;
  type: string;
  vars: Record<string, NativeValue>;
}

export interface NativeChapterInput {
  url: string;
  title: string;
  index: number;
}

export interface NativeChapterRecord {
  title: string;
  url: string;
  isVip: boolean;
  isPay: boolean;
  isVolume: boolean;
  tag: string;
}

export interface NativeMenuEntry {
  title: string;
  /** 空串表示分组标题。 */
  target: string;
}

export interface NativeParagraphComment {
  /** 正文行号（按换行切分后的下标）。 */
  line: number;
  count: number;
  url: string;
}

export interface NativeContentResult {
  /** text | images | audio | video */
  kind: string;
  text: string;
  baseUrl: string;
  paragraphComments: NativeParagraphComment[];
  /** 整章评论页地址，空串表示没有。 */
  chapterCommentUrl: string;
  /** 正文末尾的链接按钮。 */
  links: NativeContentLink[];
}

export interface NativeContentLink {
  label: string;
  url: string;
}

export class NativeSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NativeSourceError';
  }
}

interface StagePage {
  scope: NativeScope;
  baseUrl: string;
}

const MENU_STATIC = 'native:menu:';
const MENU_ITEM = 'native:item:';
const MAX_TOC_PAGES = 100;
const MAX_CONTENT_PAGES = 30;
const MAX_LIST_ITEMS = 20000;
const DEFAULT_COMMENT_BUBBLES = 60;
const MAX_COMMENT_BUBBLES = 300;

export class NativeSourceRunner {
  private definition: NativeSourceDefinition;
  private host: NativeRunnerHost;
  private expr: NativeExpr;
  private varValues: Record<string, string>;
  private cancelled: () => boolean = (): boolean => false;

  constructor(definition: NativeSourceDefinition, host: NativeRunnerHost, storedVars: Record<string, NativeValue> = {}) {
    this.definition = definition;
    this.host = host;
    this.expr = new NativeExpr(host).loadLibrary(definition.lib);
    this.varValues = NativeSourceRunner.resolveVars(definition, storedVars);
  }

  setCancelCheck(check: () => boolean): NativeSourceRunner {
    this.cancelled = check;
    return this;
  }

  /** 合并默认值与已保存的值；已保存的值不在选项内时回退到默认值。 */
  static resolveVars(definition: NativeSourceDefinition, stored: Record<string, NativeValue>): Record<string, string> {
    const values: Record<string, string> = {};
    for (const item of definition.vars || []) {
      const options = Array.isArray(item.options) ? item.options.map((option: string): string => String(option)) : [];
      const fallback = item.default !== undefined ? String(item.default) : (options.length > 0 ? options[0] : '');
      const saved = stored && stored[item.key] !== undefined && stored[item.key] !== null ? String(stored[item.key]) : '';
      values[item.key] = saved && (options.length === 0 || options.indexOf(saved) >= 0) ? saved : fallback;
    }
    return values;
  }

  async search(key: string, page: number = 1): Promise<NativeBookRecord[]> {
    const stage = this.requireStage(this.definition.search, '搜索');
    const scope = this.baseScope().set('key', key).set('page', page);
    const loaded = await this.loadStage(stage, scope, '', '搜索');
    return this.readBooks(stage, loaded);
  }

  /** 用书源声明的检查接口确认登录状态。 */
  async checkLogin(): Promise<NativeLoginState> {
    const check = this.definition.login ? this.definition.login.check : undefined;
    if (!check) return { ok: false, name: '', message: '该书源没有配置登录检查' };
    const scope = this.baseScope();
    const request = this.buildRequest(check, scope, '');
    const response = await this.host.fetch(request);
    if (!response.ok || !response.body) {
      return { ok: false, name: '', message: this.describeFailure('登录检查', response) };
    }
    const pageScope = this.responseScope(scope, response.body, response.url || request.url);
    const ok = NativeExpr.isTruthy(this.value(check.ok, pageScope));
    return {
      ok: ok,
      name: ok && check.name ? NativeExpr.toText(this.value(check.name, pageScope)).trim() : '',
      message: ok ? '' : '未登录或登录已失效'
    };
  }

  async exploreMenus(): Promise<NativeMenuEntry[]> {
    const explore = this.requireStage(this.definition.explore, '发现');
    const scope = this.baseScope();
    const entries: NativeMenuEntry[] = [];
    const menus = explore.menus || [];
    for (let i = 0; i < menus.length; i++) {
      const menu = menus[i];
      if (menu.when && !NativeExpr.isTruthy(this.value(menu.when, scope))) continue;
      const title = NativeExpr.toText(this.template(menu.title || '', scope));
      if (!title) continue;
      entries.push({ title: title, target: menu.url ? `${MENU_STATIC}${i}` : '' });
    }
    const dynamic = explore.dynamicMenus;
    if (dynamic) {
      const request = this.buildRequest(dynamic, scope, '');
      if (request.url) {
        const response = await this.host.fetch(request);
        if (!response.ok || !response.body) {
          if (entries.length === 0) throw new NativeSourceError(this.describeFailure('发现分类', response));
        } else {
          const baseUrl = response.url || request.url;
          const pageScope = this.responseScope(scope, response.body, baseUrl);
          const items = this.listItems(dynamic.list, pageScope, baseUrl);
          for (const item of items) {
            const itemScope = pageScope.child().set('item', item);
            const title = NativeExpr.toText(this.value(dynamic.title, itemScope)).trim();
            if (!title) continue;
            // 目标地址里通常带页码，到真正打开分类时再渲染，这里只记下条目本身。
            const hasTarget = NativeExpr.isTruthy(this.value(dynamic.target, itemScope.child().set('page', 1)));
            entries.push({ title: title, target: hasTarget ? MENU_ITEM + JSON.stringify(item) : '' });
          }
        }
      }
    }
    return entries;
  }

  async explore(target: string, page: number = 1): Promise<NativeBookRecord[]> {
    const explore = this.requireStage(this.definition.explore, '发现');
    const scope = this.baseScope().set('page', page);
    let url = '';
    let menuHeaders: Record<string, string> = {};
    if (target.startsWith(MENU_STATIC)) {
      const menu = (explore.menus || [])[Number(target.substring(MENU_STATIC.length))];
      url = menu && menu.url ? NativeExpr.toText(this.template(menu.url, scope)) : '';
      if (menu && menu.headers) menuHeaders = menu.headers;
    } else if (target.startsWith(MENU_ITEM) && explore.dynamicMenus) {
      let item: NativeValue = null;
      try {
        item = JSON.parse(target.substring(MENU_ITEM.length));
      } catch (e) {
        item = null;
      }
      url = NativeExpr.toText(this.value(explore.dynamicMenus.target, scope.child().set('item', item)));
    }
    if (!url) throw new NativeSourceError('发现分类没有可用的地址');
    const stage: NativeStageSpec = Object.assign({}, explore, {
      url: '= __url', headers: Object.assign({}, explore.headers || {}, menuHeaders)
    });
    const loaded = await this.loadStage(stage, scope.child().set('__url', url), '', '发现');
    return this.readBooks(explore, loaded);
  }

  async detail(book: NativeBookInput): Promise<NativeBookRecord> {
    const stage = this.definition.detail || {};
    const scope = this.baseScope().set('book', book);
    const loaded = await this.loadStage(stage, scope, book.bookUrl, '详情');
    const record = this.readBook(stage.fields || {}, loaded.scope, loaded.baseUrl);
    if (!record.bookUrl) record.bookUrl = book.bookUrl;
    const keep = this.definition.detail ? this.definition.detail.keep : undefined;
    if (keep) {
      for (const key of Object.keys(keep)) {
        record.keep[key] = NativeExpr.toText(this.value(keep[key], loaded.scope));
      }
    }
    return record;
  }

  async toc(book: NativeBookInput, limit: number = 0): Promise<NativeChapterRecord[]> {
    const stage = this.requireStage(this.definition.toc, '目录');
    const chapters: NativeChapterRecord[] = [];
    const visited: Set<string> = new Set();
    let nextUrl = '';
    for (let page = 1; page <= MAX_TOC_PAGES; page++) {
      if (this.cancelled()) return [];
      const scope = this.baseScope().set('book', book).set('page', page);
      const pageStage: NativeStageSpec = page === 1 ? stage : Object.assign({}, stage, { url: '= __url' });
      const loaded = await this.loadStage(pageStage, scope.child().set('__url', nextUrl),
        book.tocUrl || book.bookUrl, '目录');
      const fields = stage.fields || {};
      for (const item of this.listItems(stage.list || '', loaded.scope, loaded.baseUrl)) {
        const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);
        const title = NativeExpr.toText(this.value(fields['title'], itemScope)).trim();
        if (!title) continue;
        const isVolume = NativeExpr.isTruthy(this.value(fields['isVolume'], itemScope));
        const url = NativeExpr.resolveUrl(NativeExpr.toText(this.value(fields['url'], itemScope)), loaded.baseUrl);
        if (!url && !isVolume) continue;
        chapters.push({
          title: title,
          url: url,
          isVip: NativeExpr.isTruthy(this.value(fields['isVip'], itemScope)),
          isPay: NativeExpr.isTruthy(this.value(fields['isPay'], itemScope)),
          isVolume: isVolume,
          tag: NativeExpr.toText(this.value(fields['tag'] || fields['updateTime'], itemScope)).trim()
        });
        if (chapters.length >= MAX_LIST_ITEMS || (limit > 0 && chapters.length >= limit)) break;
      }
      if (limit > 0 && chapters.length >= limit) break;
      if (!stage.nextUrl) break;
      nextUrl = NativeExpr.resolveUrl(NativeExpr.toText(this.value(stage.nextUrl, loaded.scope)), loaded.baseUrl);
      if (!nextUrl || visited.has(nextUrl)) break;
      visited.add(nextUrl);
    }
    return stage.reverse === true ? chapters.reverse() : chapters;
  }

  async content(book: NativeBookInput, chapter: NativeChapterInput): Promise<NativeContentResult> {
    const stage = this.requireStage(this.definition.content, '正文');
    const bookType = String(book.type || this.definition.type || 'text').toLowerCase();
    const kind = bookType === 'video' && stage.video ? 'video' : (bookType === 'audio' && stage.audio ? 'audio' :
      ((bookType === 'comic' || bookType === 'image') && stage.images ? 'images' :
        (stage.text ? 'text' : (stage.images ? 'images' : (stage.audio ? 'audio' : 'video')))));
    const parts: string[] = [];
    const visited: Set<string> = new Set();
    let nextUrl = '';
    let firstBase = '';
    let firstPage: StagePage | null = null;
    for (let page = 1; page <= MAX_CONTENT_PAGES; page++) {
      if (this.cancelled()) {
        return { kind: kind, text: '', baseUrl: firstBase, paragraphComments: [], chapterCommentUrl: '', links: [] };
      }
      const scope = this.baseScope().set('book', book).set('chapter', chapter).set('page', page);
      const pageStage: NativeStageSpec = page === 1 ? stage : Object.assign({}, stage, { url: '= __url' });
      const loaded = await this.loadStage(pageStage, scope.child().set('__url', nextUrl), chapter.url, '正文');
      if (!firstBase) firstBase = loaded.baseUrl;
      if (!firstPage) firstPage = loaded;
      await this.runExtraFetches(stage, loaded);
      if (kind === 'audio' || kind === 'video') {
        const audio = NativeExpr.toText(this.first(this.value(kind === 'audio' ? stage.audio : stage.video,
          loaded.scope))).trim();
        return {
          kind: kind, text: NativeExpr.resolveUrl(audio, loaded.baseUrl), baseUrl: loaded.baseUrl,
          paragraphComments: [], chapterCommentUrl: '', links: []
        };
      }
      if (kind === 'images') {
        const images = this.value(stage.images, loaded.scope, true);
        for (const image of Array.isArray(images) ? images : [images]) {
          const url = NativeExpr.resolveUrl(NativeExpr.toText(image).trim(), loaded.baseUrl);
          if (url) parts.push(`<img src="${url.replace(/"/g, '%22')}">`);
        }
      } else {
        const text = this.value(stage.text, loaded.scope);
        parts.push(Array.isArray(text) ?
          text.map((line: NativeValue): string => NativeExpr.toText(line)).join('\n') : NativeExpr.toText(text));
      }
      if (!stage.nextUrl) break;
      nextUrl = NativeExpr.resolveUrl(NativeExpr.toText(this.value(stage.nextUrl, loaded.scope)), loaded.baseUrl);
      if (!nextUrl || visited.has(nextUrl)) break;
      visited.add(nextUrl);
    }
    let text = parts.join('\n');
    if (kind === 'text') {
      for (const rule of stage.replace || []) {
        if (!rule || !rule.pattern) continue;
        text = text.replace(new RegExp(rule.pattern, rule.flags === undefined ? 'g' : rule.flags), rule.with || '');
      }
    }
    const result: NativeContentResult = {
      kind: kind, text: text, baseUrl: firstBase, paragraphComments: [], chapterCommentUrl: '', links: []
    };
    if (kind === 'text' && firstPage) {
      for (const link of stage.links || []) {
        if (link.when && !NativeExpr.isTruthy(this.value(link.when, firstPage.scope))) continue;
        const label = NativeExpr.toText(this.template(link.label, firstPage.scope)).trim();
        const url = NativeExpr.resolveUrl(NativeExpr.toText(this.template(link.url, firstPage.scope)).trim(),
          firstPage.baseUrl);
        if (label && /^https?:\/\//i.test(url)) result.links.push({ label: label, url: url });
      }
    }
    if (kind === 'text' && stage.comments && firstPage && text.trim()) {
      // 评论只是附加信息，任何一步失败都不影响正文。
      try {
        await this.collectComments(stage.comments, firstPage, text, result);
      } catch (e) {
        result.paragraphComments = [];
        result.chapterCommentUrl = '';
      }
    }
    return result;
  }

  private async collectComments(spec: NativeCommentsSpec, page: StagePage, text: string,
    result: NativeContentResult): Promise<void> {
    if (spec.when && !NativeExpr.isTruthy(this.value(spec.when, page.scope))) return;
    const scope = page.scope.child();
    scope.set('stats', spec.stats ? await this.fetchValue(spec.stats, scope) : null);
    let total = 0;
    if (spec.paragraphUrl && spec.counts) {
      const counts = this.value(spec.counts, scope);
      const lines = text.split('\n');
      const limit = Math.max(1, Math.min(Number(spec.max) || DEFAULT_COMMENT_BUBBLES, MAX_COMMENT_BUBBLES));
      const keys = counts && typeof counts === 'object' ? Object.keys(counts) : [];
      keys.sort((a: string, b: string): number => Number(a) - Number(b));
      for (const key of keys) {
        const line = Number(key);
        const count = Math.floor(NativeExpr.toNumber(counts[key]));
        if (!Number.isInteger(line) || count <= 0) continue;
        total += count;
        if (line < 0 || line >= lines.length || result.paragraphComments.length >= limit) continue;
        const plain = lines[line].replace(/<[^>]+>/g, '').trim();
        if (!plain) continue;
        const para = { index: line, count: count, text: plain.length > 90 ? plain.substring(0, 90) : plain };
        const url = NativeExpr.resolveUrl(
          NativeExpr.toText(this.template(spec.paragraphUrl, scope.child().set('para', para))).trim(), page.baseUrl);
        if (/^https?:\/\//i.test(url)) result.paragraphComments.push({ line: line, count: count, url: url });
      }
    }
    if (spec.chapterUrl) {
      const url = NativeExpr.resolveUrl(
        NativeExpr.toText(this.template(spec.chapterUrl, scope.child().set('total', total))).trim(), page.baseUrl);
      if (/^https?:\/\//i.test(url)) result.chapterCommentUrl = url;
    }
  }

  /** 发一个附加请求：响应是 JSON 时返回解析后的对象，否则返回文本；失败返回 null。 */
  private async fetchValue(spec: NativeRequestSpec, scope: NativeScope): Promise<NativeValue> {
    const request = this.buildRequest(spec, scope, '');
    if (!request.url) return null;
    try {
      const response = await this.host.fetch(request);
      if (!response.ok || !response.body) return null;
      try {
        return JSON.parse(response.body);
      } catch (e) {
        return response.body;
      }
    } catch (e) {
      return null;
    }
  }

  private requireStage<T>(stage: T | undefined, label: string): T {
    if (!stage) throw new NativeSourceError(`该书源没有配置${label}`);
    return stage;
  }

  private baseScope(): NativeScope {
    const scope = new NativeScope()
      .set('vars', this.varValues)
      .set('source', { url: this.definition.url, name: this.definition.name })
      .set('key', '')
      .set('page', 1)
      .set('book', null)
      .set('chapter', null)
      .set('item', null)
      .set('index', 0)
      .set('body', '')
      .set('data', null)
      .set('baseUrl', this.definition.url);
    this.applyLets(this.definition.let, scope);
    return scope.child();
  }

  private applyLets(lets: Record<string, NativeValue> | undefined, scope: NativeScope): void {
    if (!lets) return;
    for (const name of Object.keys(lets)) scope.set(name, this.value(lets[name], scope));
  }

  /** 请求一个阶段的页面并准备好求值环境；地址渲染为空时不发请求。 */
  private async loadStage(stage: NativeStageSpec, scope: NativeScope, defaultUrl: string, label: string): Promise<StagePage> {
    const request = this.buildRequest(stage, scope, defaultUrl);
    let body = '';
    let baseUrl = request.url || NativeExpr.toText(scope.get('baseUrl'));
    if (request.url) {
      const response = await this.host.fetch(request);
      if (!response.ok || !response.body) throw new NativeSourceError(this.describeFailure(label, response));
      body = response.body;
      baseUrl = response.url || request.url;
    }
    const pageScope = this.responseScope(scope, body, baseUrl);
    this.applyLets(stage.let, pageScope);
    if (stage.fail) {
      const failure = NativeExpr.toText(this.value(stage.fail, pageScope)).trim();
      if (failure && failure !== 'false') throw new NativeSourceError(`${label}接口返回失败：${failure}`);
    }
    return { scope: pageScope, baseUrl: baseUrl };
  }

  private responseScope(scope: NativeScope, body: string, baseUrl: string): NativeScope {
    let data: NativeValue = null;
    const trimmed = body.trim();
    if (trimmed && (trimmed[0] === '{' || trimmed[0] === '[')) {
      try {
        data = JSON.parse(trimmed);
      } catch (e) {
        data = null;
      }
    }
    return scope.child().set('body', body).set('data', data).set('item', data === null ? body : data)
      .set('baseUrl', baseUrl);
  }

  private describeFailure(label: string, response: NativeResponse): string {
    if (!response.ok) {
      return response.status > 0 ? `${label}请求失败（HTTP ${response.status}）` :
        `${label}请求失败：${response.error || '网络异常'}`;
    }
    return `${label}接口返回空响应`;
  }

  private buildRequest(spec: NativeRequestSpec, scope: NativeScope, defaultUrl: string): NativeRequest {
    const rawUrl = spec.url === undefined ? defaultUrl : NativeExpr.toText(this.template(spec.url, scope));
    const url = NativeExpr.resolveUrl(rawUrl.trim(), this.definition.url);
    const headers: Record<string, string> = {};
    for (const name of Object.keys(spec.headers || {})) {
      const value = NativeExpr.toText(this.template((spec.headers as Record<string, string>)[name], scope));
      if (value) headers[name] = value;
    }
    let body = '';
    if (spec.body !== undefined && spec.body !== null) {
      body = typeof spec.body === 'string' ? NativeExpr.toText(this.template(spec.body, scope)) :
        JSON.stringify(this.renderDeep(spec.body, scope));
    }
    const method = String(spec.method || (body ? 'POST' : 'GET')).toUpperCase();
    return { url: url, method: method, headers: headers, body: body, webView: spec.webView === true };
  }

  private renderDeep(value: NativeValue, scope: NativeScope): NativeValue {
    if (typeof value === 'string') return this.template(value, scope);
    if (Array.isArray(value)) return value.map((item: NativeValue): NativeValue => this.renderDeep(item, scope));
    if (value && typeof value === 'object') {
      const out: Record<string, NativeValue> = {};
      for (const key of Object.keys(value)) out[key] = this.renderDeep(value[key], scope);
      return out;
    }
    return value;
  }

  private async runExtraFetches(stage: NativeContentSpec, loaded: StagePage): Promise<void> {
    const fetches = stage.fetch;
    if (!fetches) return;
    for (const name of Object.keys(fetches)) {
      const spec: NativeFetchSpec = fetches[name];
      let result: NativeValue = null;
      // 附加请求只是补充数据，失败时变量为 null，由规则自行决定如何降级。
      if (!spec.when || NativeExpr.isTruthy(this.value(spec.when, loaded.scope))) {
        result = await this.fetchValue(spec, loaded.scope);
      }
      loaded.scope.set(name, result);
    }
  }

  private readBooks(stage: NativeStageSpec, loaded: StagePage): NativeBookRecord[] {
    const books: NativeBookRecord[] = [];
    const items = this.listItems(stage.list || '', loaded.scope, loaded.baseUrl);
    for (let i = 0; i < items.length; i++) {
      const itemScope = loaded.scope.child().set('item', items[i]).set('index', i);
      const book = this.readBook(stage.fields || {}, itemScope, loaded.baseUrl);
      if (book.name && book.bookUrl) books.push(book);
    }
    return books;
  }

  private readBook(fields: Record<string, NativeValue>, scope: NativeScope, baseUrl: string): NativeBookRecord {
    const text = (name: string): string => {
      const value = this.value(fields[name], scope);
      return (Array.isArray(value) ? value.map((part: NativeValue): string => NativeExpr.toText(part).trim())
        .filter((part: string): boolean => !!part).join(',') : NativeExpr.toText(value)).trim();
    };
    const url = (name: string): string => NativeExpr.resolveUrl(NativeExpr.toText(this.first(
      this.value(fields[name], scope))).trim(), baseUrl);
    const typeSpec = fields['type'];
    const literalType = typeof typeSpec === 'string' && /^(text|audio|comic|image|video)$/i.test(typeSpec.trim());
    return {
      name: text('name'),
      author: text('author'),
      kind: text('kind'),
      intro: text('intro'),
      coverUrl: url('coverUrl'),
      wordCount: text('wordCount'),
      lastChapter: text('lastChapter'),
      updateTime: text('updateTime'),
      status: text('status'),
      bookUrl: url('bookUrl'),
      tocUrl: url('tocUrl'),
      type: (literalType ? String(typeSpec).trim() : text('type')).toLowerCase(),
      keep: {}
    };
  }

  private first(value: NativeValue): NativeValue {
    return Array.isArray(value) ? (value.length > 0 ? value[0] : '') : value;
  }

  private listItems(rule: string, scope: NativeScope, baseUrl: string): NativeValue[] {
    const spec = (rule || '').trim();
    if (!spec) return [];
    let items: NativeValue[];
    if (spec.startsWith('=')) {
      const value = this.expr.evaluate(spec.substring(1), scope);
      items = Array.isArray(value) ? value : (value === null || value === undefined || value === '' ? [] : [value]);
    } else {
      const current = scope.get('item');
      const jsonItems = this.jsonRule(spec, current, true);
      items = jsonItems !== null ? (jsonItems as NativeValue[]) :
        this.host.selectItems(typeof current === 'string' ? current : NativeExpr.toText(current), spec, baseUrl);
    }
    return items.length > MAX_LIST_ITEMS ? items.slice(0, MAX_LIST_ITEMS) : items;
  }

  /** 模板位置（地址、请求头、标题）：= 开头按表达式，其余按 {{ }} 模板。 */
  private template(spec: NativeValue, scope: NativeScope): NativeValue {
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return this.expr.evaluate(text.substring(1), scope);
    return this.expr.render(spec, scope);
  }

  /** 字段位置：= 开头按表达式，含 {{ }} 按模板，其余按选择器规则在当前元素上取值。 */
  private value(spec: NativeValue, scope: NativeScope, list: boolean = false): NativeValue {
    if (spec === undefined || spec === null || spec === '') return list ? [] : '';
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return this.expr.evaluate(text.substring(1), scope);
    if (text.indexOf('{{') >= 0) return this.expr.render(spec, scope);
    const current = scope.get('item');
    const jsonValue = this.jsonRule(text, current, list);
    if (jsonValue !== null) return jsonValue;
    const content = typeof current === 'string' ? current : NativeExpr.toText(current);
    const found = this.host.select(content, text, NativeExpr.toText(scope.get('baseUrl')), list);
    return list ? found : (found.length > 0 ? found[0] : '');
  }

  /**
   * 纯 JSONPath 规则（可用 || 写备选）直接在对象上取值，免去把每个元素反复序列化再解析。
   * 不是这种写法时返回 null，交给完整的选择器引擎。
   */
  private jsonRule(rule: string, current: NativeValue, list: boolean): NativeValue {
    if (current === null || typeof current !== 'object') return null;
    if (!/^\$[.\[]/.test(rule) || /##|&&|%%|@|<|\{/.test(rule)) return null;
    for (const path of rule.split('||')) {
      const matches = this.host.jsonPath(current, path.trim());
      if (matches.length === 0) continue;
      if (list) return matches;
      const texts = matches.map((item: NativeValue): string => NativeExpr.toText(item));
      if (texts.some((item: string): boolean => !!item)) return matches.length === 1 ? matches[0] : texts.join('\n');
    }
    return list ? [] : '';
  }
}
