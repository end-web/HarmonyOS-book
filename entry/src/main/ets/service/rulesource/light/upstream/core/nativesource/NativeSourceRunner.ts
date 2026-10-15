/**
 * 原生书源执行器：按定义依次完成请求、取列表、取字段，全程不经过任何脚本引擎。
 *
 * 网络与选择器通过 NativeRunnerHost 注入，本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { NativeExpr, NativeScope } from './NativeExpr';
import type { NativeExprHost, NativeValue } from './NativeExpr';
import type {
  NativeActionSpec, NativeCommentsSpec, NativeContentSpec, NativeFetchSpec, NativeRequestSpec, NativeSourceDefinition,
  NativeStageSpec
} from './NativeSourceSpec';

export interface NativeRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
  webView: boolean;
  /** 网页渲染时要等待出现的元素（CSS 选择器），空串表示不等待。 */
  webWaitFor: string;
  /** 网页渲染的最长等待秒数。 */
  webTimeout: number;
  charset: string;
  retry: number;
  /** 主请求：遇到验证页时应提示用户去验证。附加请求不触发。 */
  primary: boolean;
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

/** 一条规则的求值记录，供调试页显示。 */
export interface NativeRuleTrace {
  field: string;
  rule: string;
  /** expression | template | selector */
  type: string;
  count: number;
  preview: string;
  error: string;
}

/** 已保存的登录凭据（表单登录得到的）。 */
export interface NativeLoginCredential {
  token: string;
  user: string;
}

export interface NativeLoginResult {
  ok: boolean;
  token: string;
  user: string;
  message: string;
}

/** 一个动作按钮：open 有值时打开网页，否则点击后执行对应序号的请求。 */
export interface NativeActionEntry {
  index: number;
  label: string;
  open: string;
}

export interface NativeRunnerHost extends NativeExprHost {
  fetch(request: NativeRequest): Promise<NativeResponse>;
  /** 调试时记录规则求值；不调试时不提供。 */
  trace?(entry: NativeRuleTrace): void;
  /** 读取声明式缓存；没有或已过期时返回 undefined。 */
  cacheGet?(key: string): NativeValue;
  cachePut?(key: string, value: NativeValue, ttlSeconds: number): void;
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
  /** 漫画的图片地址（kind 为 images 时）。 */
  images: string[];
  /** 取图片、音频时附带的请求头。 */
  mediaHeaders: Record<string, string>;
  imageDecode: NativeImageDecode | null;
}

export interface NativeContentLink {
  label: string;
  /** 要打开的网页；为空时表示这是一个请求动作。 */
  url: string;
  /** 请求动作：已经渲染好的请求，以及请求完成后求提示文字的规则。 */
  request: NativeRequest | null;
  message: string;
}

/** 图片解密参数，密钥与 IV 为十六进制。 */
export interface NativeImageDecode {
  algorithm: string;
  key: string;
  iv: string;
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
  private credential: NativeLoginCredential = { token: '', user: '' };

  constructor(definition: NativeSourceDefinition, host: NativeRunnerHost, storedVars: Record<string, NativeValue> = {}) {
    this.definition = definition;
    this.host = host;
    this.expr = new NativeExpr(host).loadLibrary(definition.lib);
    this.varValues = NativeSourceRunner.resolveVars(definition, storedVars);
  }

  /** 表单登录保存下来的凭据，规则里通过 login.token / login.user 读取。 */
  setCredential(credential: NativeLoginCredential): NativeSourceRunner {
    this.credential = { token: credential.token || '', user: credential.user || '' };
    return this;
  }

  /** 表单登录：用用户填写的值发登录请求。 */
  async submitLogin(form: Record<string, string>): Promise<NativeLoginResult> {
    const submit = this.definition.login ? this.definition.login.submit : undefined;
    if (!submit) return { ok: false, token: '', user: '', message: '该书源没有配置表单登录' };
    const scope = (await this.baseScope()).set('form', form);
    const response = await this.host.fetch(this.buildRequest(submit, scope, ''));
    if (!response.ok || !response.body) {
      return { ok: false, token: '', user: '', message: this.describeFailure('登录', response) };
    }
    const page = this.responseScope(scope, response.body, response.url);
    const ok = NativeExpr.isTruthy(this.value(submit.ok, page, false, 'login.submit.ok'));
    const message = submit.message ?
      NativeExpr.toText(this.value(submit.message, page, false, 'login.submit.message')).trim() : '';
    if (!ok) return { ok: false, token: '', user: '', message: message || '登录失败' };
    return {
      ok: true,
      token: submit.token ? NativeExpr.toText(this.value(submit.token, page, false, 'login.submit.token')).trim() : '',
      user: submit.user ? NativeExpr.toText(this.value(submit.user, page, false, 'login.submit.user')).trim() : '',
      message: message
    };
  }

  /** 表单登录的辅助请求（发送验证码等），返回提示文字。 */
  async sendLoginCode(form: Record<string, string>): Promise<string> {
    const spec = this.definition.login ? this.definition.login.sendCode : undefined;
    if (!spec) return '该书源没有配置这个操作';
    return await this.performAction(spec, (await this.baseScope()).set('form', form), 'login.sendCode');
  }

  /** 书源设置页里可用的动作按钮。 */
  async actions(): Promise<NativeActionEntry[]> {
    const specs = this.definition.actions || [];
    if (specs.length === 0) return [];
    const scope = await this.baseScope();
    const entries: NativeActionEntry[] = [];
    for (let i = 0; i < specs.length; i++) {
      const spec = specs[i];
      if (spec.when && !NativeExpr.isTruthy(this.value(spec.when, scope, false, `actions[${i}].when`))) continue;
      const label = NativeExpr.toText(this.template(spec.label, scope)).trim();
      if (!label) continue;
      const open = spec.open ? NativeExpr.resolveUrl(NativeExpr.toText(this.template(spec.open, scope)).trim(),
        this.definition.url) : '';
      entries.push({ index: i, label: label, open: /^https?:\/\//i.test(open) ? open : '' });
    }
    return entries;
  }

  /** 执行一个动作按钮，返回提示文字。 */
  async runAction(index: number): Promise<string> {
    const spec = (this.definition.actions || [])[index];
    if (!spec) return '没有这个操作';
    return await this.performAction(spec, await this.baseScope(), `actions[${index}]`);
  }

  /** 执行正文里的请求按钮：请求在取正文时已经渲染好，这里只发出并求提示文字。 */
  async runLinkAction(request: NativeRequest, messageSpec: string): Promise<string> {
    const scope = await this.baseScope();
    const response = await this.host.fetch(request);
    if (!response.ok) return this.describeFailure('操作', response);
    if (!messageSpec) return '已完成';
    const page = this.responseScope(scope, response.body || '', response.url || request.url);
    return NativeExpr.toText(this.value(messageSpec, page, false, 'content.links.message')).trim() || '已完成';
  }

  private async performAction(spec: NativeActionSpec, scope: NativeScope, field: string): Promise<string> {
    const request = this.buildRequest(spec, scope, '');
    if (!request.url) return '操作没有可用的地址';
    const response = await this.host.fetch(request);
    if (!response.ok) return this.describeFailure('操作', response);
    if (!spec.message) return '已完成';
    const page = this.responseScope(scope, response.body || '', response.url || request.url);
    return NativeExpr.toText(this.value(spec.message, page, false, `${field}.message`)).trim() || '已完成';
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
    const scope = (await this.baseScope()).set('key', key).set('page', page);
    const loaded = await this.loadStage(stage, scope, '', '搜索');
    return this.readBooks(stage, loaded, 'search');
  }

  /** 用书源声明的检查接口确认登录状态。 */
  async checkLogin(): Promise<NativeLoginState> {
    const check = this.definition.login ? this.definition.login.check : undefined;
    if (!check) return { ok: false, name: '', message: '该书源没有配置登录检查' };
    const scope = (await this.baseScope());
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
    const scope = (await this.baseScope());
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
    const scope = (await this.baseScope()).set('page', page);
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
    return this.readBooks(explore, loaded, 'explore');
  }

  async detail(book: NativeBookInput): Promise<NativeBookRecord> {
    const stage = this.definition.detail || {};
    const scope = (await this.baseScope()).set('book', book);
    const loaded = await this.loadStage(stage, scope, book.bookUrl, '详情');
    const record = this.readBook(stage.fields || {}, loaded.scope, loaded.baseUrl, 'detail');
    if (!record.bookUrl) record.bookUrl = book.bookUrl;
    const keep = this.definition.detail ? this.definition.detail.keep : undefined;
    if (keep) {
      for (const key of Object.keys(keep)) {
        record.keep[key] = NativeExpr.toText(this.value(keep[key], loaded.scope, false, `detail.keep.${key}`));
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
      const scope = (await this.baseScope()).set('book', book).set('page', page);
      const pageStage: NativeStageSpec = page === 1 ? stage : Object.assign({}, stage, { url: '= __url' });
      const loaded = await this.loadStage(pageStage, scope.child().set('__url', nextUrl),
        book.tocUrl || book.bookUrl, '目录');
      const fields = stage.fields || {};
      for (const item of this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, 'toc.list')) {
        const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);
        const title = NativeExpr.toText(this.value(fields['title'], itemScope, false, 'toc.fields.title')).trim();
        if (!title) continue;
        const isVolume = NativeExpr.isTruthy(this.value(fields['isVolume'], itemScope, false, 'toc.fields.isVolume'));
        const url = NativeExpr.resolveUrl(
          NativeExpr.toText(this.value(fields['url'], itemScope, false, 'toc.fields.url')), loaded.baseUrl);
        if (!url && !isVolume) continue;
        chapters.push({
          title: title,
          url: url,
          isVip: NativeExpr.isTruthy(this.value(fields['isVip'], itemScope, false, 'toc.fields.isVip')),
          isPay: NativeExpr.isTruthy(this.value(fields['isPay'], itemScope, false, 'toc.fields.isPay')),
          isVolume: isVolume,
          tag: NativeExpr.toText(this.value(fields['tag'] || fields['updateTime'], itemScope, false,
            'toc.fields.tag')).trim()
        });
        if (chapters.length >= MAX_LIST_ITEMS || (limit > 0 && chapters.length >= limit)) break;
      }
      if (limit > 0 && chapters.length >= limit) break;
      if (!stage.nextUrl) break;
      nextUrl = NativeExpr.resolveUrl(
        NativeExpr.toText(this.value(stage.nextUrl, loaded.scope, false, 'toc.nextUrl')), loaded.baseUrl);
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
    const imageUrls: string[] = [];
    const visited: Set<string> = new Set();
    let nextUrl = '';
    let firstBase = '';
    let firstPage: StagePage | null = null;
    for (let page = 1; page <= MAX_CONTENT_PAGES; page++) {
      if (this.cancelled()) {
        return {
          kind: kind, text: '', baseUrl: firstBase, paragraphComments: [], chapterCommentUrl: '', links: [],
          images: [], mediaHeaders: {}, imageDecode: null
        };
      }
      const scope = (await this.baseScope()).set('book', book).set('chapter', chapter).set('page', page);
      const pageStage: NativeStageSpec = page === 1 ? stage : Object.assign({}, stage, { url: '= __url' });
      const loaded = await this.loadStage(pageStage, scope.child().set('__url', nextUrl), chapter.url, '正文');
      if (!firstBase) firstBase = loaded.baseUrl;
      if (!firstPage) firstPage = loaded;
      await this.runExtraFetches(stage, loaded);
      if (kind === 'audio' || kind === 'video') {
        const audio = NativeExpr.toText(this.first(this.value(kind === 'audio' ? stage.audio : stage.video,
          loaded.scope, false, `content.${kind}`))).trim();
        return {
          kind: kind, text: NativeExpr.resolveUrl(audio, loaded.baseUrl), baseUrl: loaded.baseUrl,
          paragraphComments: [], chapterCommentUrl: '', links: [], images: [],
          mediaHeaders: this.renderHeaders(stage.mediaHeaders, loaded.scope), imageDecode: null
        };
      }
      if (kind === 'images') {
        const images = this.value(stage.images, loaded.scope, true, 'content.images');
        for (const image of Array.isArray(images) ? images : [images]) {
          const url = NativeExpr.resolveUrl(NativeExpr.toText(image).trim(), loaded.baseUrl);
          if (url) {
            imageUrls.push(url);
            parts.push(`<img src="${url.replace(/"/g, '%22')}">`);
          }
        }
      } else {
        const text = this.value(stage.text, loaded.scope, false, 'content.text');
        parts.push(Array.isArray(text) ?
          text.map((line: NativeValue): string => NativeExpr.toText(line)).join('\n') : NativeExpr.toText(text));
      }
      if (!stage.nextUrl) break;
      nextUrl = NativeExpr.resolveUrl(
        NativeExpr.toText(this.value(stage.nextUrl, loaded.scope, false, 'content.nextUrl')), loaded.baseUrl);
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
      kind: kind, text: text, baseUrl: firstBase, paragraphComments: [], chapterCommentUrl: '', links: [],
      images: imageUrls, mediaHeaders: firstPage ? this.renderHeaders(stage.mediaHeaders, firstPage.scope) : {},
      imageDecode: null
    };
    if (kind === 'images' && stage.imageDecode && firstPage) {
      const decode = stage.imageDecode;
      const toHex = (value: NativeValue): string => {
        const bytes: number[] = Array.isArray(value) ? value : this.expr.evaluate('bytes(__text)',
          new NativeScope().set('__text', NativeExpr.toText(value)));
        return bytes.map((byte: number): string => ((byte & 255) < 16 ? '0' : '') + (byte & 255).toString(16)).join('');
      };
      result.imageDecode = {
        algorithm: NativeExpr.toText(this.template(decode.algorithm, firstPage.scope)).trim(),
        key: toHex(this.value(decode.key, firstPage.scope, false, 'content.imageDecode.key')),
        iv: decode.iv ? toHex(this.value(decode.iv, firstPage.scope, false, 'content.imageDecode.iv')) : ''
      };
    }
    if (kind === 'text' && firstPage) {
      const links = stage.links || [];
      for (let i = 0; i < links.length; i++) {
        const link = links[i];
        if (link.when && !NativeExpr.isTruthy(this.value(link.when, firstPage.scope, false,
          `content.links[${i}].when`))) {
          continue;
        }
        const label = NativeExpr.toText(this.template(link.label, firstPage.scope)).trim();
        if (!label) continue;
        if (link.request && link.request.url) {
          const request = this.buildRequest(link.request, firstPage.scope, '');
          if (/^https?:\/\//i.test(request.url)) {
            result.links.push({ label: label, url: '', request: request, message: link.message || '' });
          }
          continue;
        }
        const url = NativeExpr.resolveUrl(NativeExpr.toText(this.template(link.url || '', firstPage.scope)).trim(),
          firstPage.baseUrl);
        if (/^https?:\/\//i.test(url)) result.links.push({ label: label, url: url, request: null, message: '' });
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

  private renderHeaders(headers: Record<string, string> | undefined, scope: NativeScope): Record<string, string> {
    const rendered: Record<string, string> = {};
    for (const name of Object.keys(headers || {})) {
      const value = NativeExpr.toText(this.template((headers as Record<string, string>)[name], scope));
      if (value) rendered[name] = value;
    }
    return rendered;
  }

  /** 声明式缓存：有效期内直接复用，否则发请求取值并保存。结果按名称绑定到求值环境。 */
  private async applyCaches(scope: NativeScope): Promise<void> {
    const caches = this.definition.cache;
    if (!caches) return;
    for (const name of Object.keys(caches)) {
      const spec = caches[name];
      let value: NativeValue = null;
      if (!spec.when || NativeExpr.isTruthy(this.value(spec.when, scope))) {
        // 变量变了（换服务器、换账号）缓存就不该再用，所以把变量值算进键里。
        const key = `${name}\n${JSON.stringify(this.varValues)}`;
        const cached = this.host.cacheGet ? this.host.cacheGet(key) : undefined;
        if (cached !== undefined && cached !== null) {
          value = cached;
        } else {
          const request = this.buildRequest(spec, scope, '');
          if (request.url) {
            try {
              const response = await this.host.fetch(request);
              if (response.ok && response.body) {
                value = this.value(spec.value, this.responseScope(scope, response.body, response.url || request.url));
              }
            } catch (e) {
              value = null;
            }
            if (value !== null && value !== undefined && value !== '' && this.host.cachePut) {
              const ttl = Math.max(1, Math.min(Number(spec.ttl) || 600, 7 * 24 * 3600));
              this.host.cachePut(key, value, ttl);
            }
          }
        }
      }
      scope.set(name, value === undefined ? null : value);
    }
  }

  private async baseScope(): Promise<NativeScope> {
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
      .set('baseUrl', this.definition.url)
      .set('login', this.credential)
      .set('form', {});
    await this.applyCaches(scope);
    this.applyLets(this.definition.let, scope);
    return scope.child();
  }

  private applyLets(lets: Record<string, NativeValue> | undefined, scope: NativeScope): void {
    if (!lets) return;
    for (const name of Object.keys(lets)) scope.set(name, this.value(lets[name], scope, false, `let.${name}`));
  }

  /** 请求一个阶段的页面并准备好求值环境；地址渲染为空时不发请求。 */
  private async loadStage(stage: NativeStageSpec, scope: NativeScope, defaultUrl: string, label: string): Promise<StagePage> {
    const request = this.buildRequest(stage, scope, defaultUrl, true);
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
      const failure = NativeExpr.toText(this.value(stage.fail, pageScope, false, 'fail')).trim();
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
      // 状态码正常却被判为失败（例如拿到的是验证页）时，以给出的原因为准。
      const succeededStatus = response.status >= 200 && response.status < 300;
      return response.status > 0 && !(succeededStatus && response.error) ?
        `${label}请求失败（HTTP ${response.status}）` : `${label}请求失败：${response.error || '网络异常'}`;
    }
    return `${label}接口返回空响应`;
  }

  private buildRequest(spec: NativeRequestSpec, scope: NativeScope, defaultUrl: string,
    primary: boolean = false): NativeRequest {
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
    const web = spec.webView && typeof spec.webView === 'object' ? spec.webView : null;
    return {
      url: url, method: method, headers: headers, body: body, webView: spec.webView === true || !!web,
      webWaitFor: web && web.waitFor ? String(web.waitFor).trim() : '',
      webTimeout: Math.max(3, Math.min(Number(web && web.timeout) || 15, 60)),
      charset: String(spec.charset || '').trim(),
      retry: Math.max(0, Math.min(Math.floor(Number(spec.retry) || 0), 3)),
      primary: primary
    };
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

  private readBooks(stage: NativeStageSpec, loaded: StagePage, prefix: string): NativeBookRecord[] {
    const books: NativeBookRecord[] = [];
    const items = this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, `${prefix}.list`);
    for (let i = 0; i < items.length; i++) {
      const itemScope = loaded.scope.child().set('item', items[i]).set('index', i);
      const book = this.readBook(stage.fields || {}, itemScope, loaded.baseUrl, prefix);
      if (book.name && book.bookUrl) books.push(book);
    }
    return books;
  }

  private readBook(fields: Record<string, NativeValue>, scope: NativeScope, baseUrl: string,
    prefix: string): NativeBookRecord {
    const text = (name: string): string => {
      const value = this.value(fields[name], scope, false, `${prefix}.fields.${name}`);
      return (Array.isArray(value) ? value.map((part: NativeValue): string => NativeExpr.toText(part).trim())
        .filter((part: string): boolean => !!part).join(',') : NativeExpr.toText(value)).trim();
    };
    const url = (name: string): string => NativeExpr.resolveUrl(NativeExpr.toText(this.first(
      this.value(fields[name], scope, false, `${prefix}.fields.${name}`))).trim(), baseUrl);
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

  private listItems(rule: string, scope: NativeScope, baseUrl: string, field: string = ''): NativeValue[] {
    const spec = (rule || '').trim();
    if (!spec) return [];
    let items: NativeValue[];
    try {
      if (spec.startsWith('=')) {
        const value = this.expr.evaluate(spec.substring(1), scope);
        items = Array.isArray(value) ? value : (value === null || value === undefined || value === '' ? [] : [value]);
      } else {
        const current = scope.get('item');
        const jsonItems = this.jsonRule(spec, current, true);
        items = jsonItems !== null ? (jsonItems as NativeValue[]) :
          this.host.selectItems(typeof current === 'string' ? current : NativeExpr.toText(current), spec, baseUrl);
      }
    } catch (e) {
      throw this.fieldError(field, spec, e);
    }
    this.traceRule(field, spec, items, true);
    return items.length > MAX_LIST_ITEMS ? items.slice(0, MAX_LIST_ITEMS) : items;
  }

  /** 给求值错误补上是哪条规则出的错，并记入调试信息。 */
  private fieldError(field: string, spec: NativeValue, error: NativeValue): Error {
    const message = error instanceof Error ? error.message : String(error);
    if (!field) return error instanceof Error ? error : new NativeSourceError(message);
    if (this.host.trace) {
      this.host.trace({
        field: field, rule: typeof spec === 'string' ? spec : NativeExpr.toText(spec),
        type: this.ruleType(spec), count: 0, preview: '', error: message
      });
    }
    return new NativeSourceError(`规则 ${field} 出错：${message}`);
  }

  private ruleType(spec: NativeValue): string {
    if (typeof spec !== 'string') return 'literal';
    const text = spec.trim();
    return text.startsWith('=') ? 'expression' : (text.indexOf('{{') >= 0 ? 'template' : 'selector');
  }

  /** 调试时记录一条规则的结果。列表里只记第一个元素的字段，避免上千条重复记录。 */
  private traceRule(field: string, spec: NativeValue, result: NativeValue, isList: boolean, scope?: NativeScope): void {
    if (!field || !this.host.trace || spec === undefined || spec === null || spec === '') return;
    if (scope && Number(scope.get('index')) > 0) return;
    const text = NativeExpr.toText(Array.isArray(result) && isList ? result[0] : result);
    this.host.trace({
      field: field, rule: typeof spec === 'string' ? spec : NativeExpr.toText(spec), type: this.ruleType(spec),
      count: Array.isArray(result) ? result.length : (text ? 1 : 0),
      preview: text.length > 300 ? `${text.substring(0, 300)}…` : text, error: ''
    });
  }

  /** 模板位置（地址、请求头、标题）：= 开头按表达式，其余按 {{ }} 模板。 */
  private template(spec: NativeValue, scope: NativeScope): NativeValue {
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return this.expr.evaluate(text.substring(1), scope);
    return this.expr.render(spec, scope);
  }

  /** 字段位置的求值。field 给出规则在定义里的位置，出错时用来定位，调试时用来记录。 */
  private value(spec: NativeValue, scope: NativeScope, list: boolean = false, field: string = ''): NativeValue {
    let result: NativeValue;
    try {
      result = this.rawValue(spec, scope, list);
    } catch (e) {
      throw this.fieldError(field, spec, e);
    }
    this.traceRule(field, spec, result, list, scope);
    return result;
  }

  /** 字段位置：= 开头按表达式，含 {{ }} 按模板，其余按选择器规则在当前元素上取值。 */
  private rawValue(spec: NativeValue, scope: NativeScope, list: boolean = false): NativeValue {
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
