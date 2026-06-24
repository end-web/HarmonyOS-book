/**
 * SourceEngine - 通用源解析器
 *
 * 读取 JSON 配置 → 执行抓取 → 返回标准数据结构
 * 替代现有的每个源写一个 TS 类的模式
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { HttpClient } from '../http/HttpClient';
import { jsonPath } from '../rule/JSONPath';
import { SimpleCSSSelector } from '../rule/SimpleCSSSelector';
import type { HTMLElement } from '../rule/SimpleCSSSelector';
import { getWebViewAudioExtractor } from '../builtin/WebViewAudioExtractor';
import { CryptoUtils } from '../../utils/CryptoUtils';
import type { SourceDefinition, RequestRule } from './SourceDefinition';
import {
  BuiltInBook, BuiltInEpisode, BuiltInBookDetail, BuiltInSearchResult,
  BuiltInCategory, BuiltInCategoryMenu, BuiltInCategoryTab, HomeBlock
} from '../builtin/IBuiltInSource';

const TAG = 'SourceEngine';

class CategoryUrlParts {
  endpoint: string;
  params: string;

  constructor(endpoint: string, params: string) {
    this.endpoint = endpoint;
    this.params = params;
  }
}

export class SourceEngine {
  private def: SourceDefinition;

  constructor(definition: SourceDefinition) {
    this.def = definition;
  }

  getDefinition(): SourceDefinition {
    return this.def;
  }

  // ────────────── 搜索 ──────────────

  async search(keyword: string, page: number): Promise<BuiltInSearchResult> {
    if (!this.def.search) {
      hilog.warn(0, TAG, 'search not defined for source: %{public}s', this.def.id);
      return new BuiltInSearchResult([], 1);
    }

    try {
      const rule = this.def.search;
      const vars: Record<string, string> = this.createVars();
      vars['key'] = keyword;
      vars['page'] = page.toString();
      const body = await this.executeRequest(rule.request, vars);
      const data = this.parseResponseBody(body, rule.request.responseType === 'html');

      // 提取列表
      const items = this.extractList(data, rule.list, rule.request.responseType === 'html');
      const books: BuiltInBook[] = [];

      for (const item of items) {
        const name = this.extractField(item, rule.item.name, rule.request.responseType === 'html');
        const author = this.extractField(item, rule.item.author, rule.request.responseType === 'html');
        const cover = this.normalizeAssetUrl(this.extractField(item, rule.item.cover, rule.request.responseType === 'html'));
        let bookId = this.extractField(item, rule.item.bookId, rule.request.responseType === 'html');
        const intro = rule.item.intro ? this.extractField(item, rule.item.intro, rule.request.responseType === 'html') : '';
        const status = rule.item.status ? this.extractField(item, rule.item.status, rule.request.responseType === 'html') : '';

        bookId = this.normalizeBookId(bookId);

        if (!name || !bookId) continue;
        const book = new BuiltInBook(cover, bookId, name, author, '');
        book.intro = intro;
        book.status = status;
        books.push(book);
      }

      return new BuiltInSearchResult(books, 1);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'search failed: %{public}s', msg);
      return new BuiltInSearchResult([], 1);
    }
  }

  // ────────────── 详情 ──────────────

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _fullPages: boolean): Promise<BuiltInBookDetail> {
    try {
      const vars: Record<string, string> = this.createVars();
      vars['bookId'] = bookUrl;
      const body = await this.executeRequest(this.def.detail.request, vars);
      const isHtml = this.def.detail.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);

      const intro = this.extractField(data, this.def.detail.fields.intro, isHtml);

      if (!loadEpisodes) {
        return new BuiltInBookDetail([], intro);
      }

      // 获取 tocUrl
      let tocUrl = this.extractField(data, this.def.detail.fields.tocUrl, isHtml);
      if (!tocUrl) tocUrl = bookUrl; // 兜底：tocUrl 和 bookUrl 相同

      // 执行目录抓取
      const episodes = await this.getTocEpisodes(tocUrl, vars);
      return new BuiltInBookDetail(episodes, intro);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getBookDetail failed: %{public}s', msg);
      return new BuiltInBookDetail([], '');
    }
  }

  // ────────────── 目录 ──────────────

  private async getTocEpisodes(tocUrl: string, vars: Record<string, string>): Promise<BuiltInEpisode[]> {
    try {
      vars['tocUrl'] = tocUrl;
      const body = await this.executeRequest(this.def.toc.request, vars);
      const isHtml = this.def.toc.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);

      const items = this.extractList(data, this.def.toc.list, isHtml);
      const episodes: BuiltInEpisode[] = [];

      for (const item of items) {
        const name = this.extractField(item, this.def.toc.item.name, isHtml);
        let chapterUrl = this.def.toc.item.chapterUrl
          ? this.extractField(item, this.def.toc.item.chapterUrl, isHtml)
          : '';

        if (!chapterUrl && this.def.toc.item.chapterId) {
          const chapterId = this.extractField(item, this.def.toc.item.chapterId, isHtml);
          const chapterVars: Record<string, string> = this.createVars();
          chapterVars['chapterId'] = chapterId;
          chapterUrl = this.renderTemplate(this.def.audio?.request.url || this.def.content?.request.url || '', chapterVars);
        }

        if (!chapterUrl) continue;
        if (!chapterUrl.startsWith('http') && !chapterUrl.startsWith('data:')) {
          chapterUrl = this.resolveUrl(chapterUrl);
        }

        const isVip = this.def.toc.item.isVip
          ? this.extractField(item, this.def.toc.item.isVip, isHtml) === 'true'
          : false;

        episodes.push(new BuiltInEpisode(name || `第${episodes.length + 1}集`, chapterUrl, !isVip));
      }

      return episodes;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getTocEpisodes failed: %{public}s', msg);
      return [];
    }
  }

  // ────────────── 文本正文 ──────────────

  async getTextContent(chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    if (!this.def.content) {
      hilog.warn(0, TAG, 'content rule not defined');
      return '';
    }

    try {
      const vars = this.buildChapterVars(chapterUrl, nextChapterUrl || '');
      const body = await this.executeRequest(this.def.content.request, vars);
      const isHtml = this.def.content.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);
      const content = this.extractField(data, this.def.content.extract, isHtml);
      return content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getTextContent failed: %{public}s', msg);
      return '';
    }
  }

  // ────────────── 音频 URL ──────────────

  async getAudioUrl(chapterUrl: string): Promise<string> {
    if (!this.def.audio) {
      hilog.warn(0, TAG, 'audio rule not defined');
      return chapterUrl;
    }

    try {
      // WebView 嗅探优先
      if (this.def.audio.webView?.enabled) {
        const jsExpr = this.def.audio.webView.jsExpr || '';
        const audioUrl = await getWebViewAudioExtractor().extract(chapterUrl, jsExpr, 5000);
        if (audioUrl && !audioUrl.startsWith('DEBUG:')) {
          return audioUrl.replace(/['"]/g, '');
        }
      }

      // 普通 HTTP 请求提取
      const vars: Record<string, string> = this.createVars();
      vars['chapterUrl'] = chapterUrl;
      const body = await this.executeRequest(this.def.audio.request, vars);
      const isHtml = this.def.audio.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);

      let audioUrl = this.extractField(data, this.def.audio.extract, isHtml);
      if (!audioUrl) return chapterUrl;

      if (!audioUrl.startsWith('http')) {
        audioUrl = this.resolveUrl(audioUrl);
      }

      return audioUrl;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getAudioUrl failed: %{public}s', msg);
      return chapterUrl;
    }
  }

  // ────────────── 分类 ──────────────

  getCategoryMenus(): BuiltInCategoryMenu[] {
    if (!this.def.category) return [];

    const menus: BuiltInCategoryMenu[] = [];
    for (const menu of this.def.category.menus) {
      const tabs: BuiltInCategoryTab[] = [];
      for (const tab of menu.tabs) {
        tabs.push(new BuiltInCategoryTab(tab.title, tab.url));
      }
      menus.push(new BuiltInCategoryMenu(menu.title, tabs));
    }
    return menus;
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    if (!this.def.category) {
      return new BuiltInCategory([], 1, 1, url, '');
    }

    try {
      const fullUrl = this.normalizeCategoryUrl(url);
      const parts = this.splitCategoryUrl(fullUrl);
      const currentPage = this.extractPage(fullUrl);
      const vars: Record<string, string> = this.createVars();
      vars['categoryUrl'] = fullUrl;
      vars['categoryEndpoint'] = parts.endpoint;
      vars['categoryParams'] = parts.params;
      vars['page'] = currentPage.toString();
      const body = await this.executeRequest(this.def.category.list.request, vars);
      const isHtml = this.def.category.list.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);

      const items = this.extractList(data, this.def.category.list.list, isHtml);
      const books: BuiltInBook[] = [];

      for (const item of items) {
        const name = this.extractField(item, this.def.category.list.item.name, isHtml);
        const author = this.extractField(item, this.def.category.list.item.author, isHtml);
        const cover = this.normalizeAssetUrl(this.extractField(item, this.def.category.list.item.cover, isHtml));
        let bookId = this.extractField(item, this.def.category.list.item.bookId, isHtml);
        const intro = this.def.category.list.item.intro
          ? this.extractField(item, this.def.category.list.item.intro, isHtml)
          : '';
        const status = this.def.category.list.item.status
          ? this.extractField(item, this.def.category.list.item.status, isHtml)
          : '';

        bookId = this.normalizeBookId(bookId);

        if (!name || !bookId) continue;
        const book = new BuiltInBook(cover, bookId, name, author, '');
        book.intro = intro;
        book.status = status;
        books.push(book);
      }

      let nextUrl = this.nextCategoryUrl(fullUrl, currentPage, books.length);
      const totalPage = nextUrl ? currentPage + 1 : currentPage;

      return new BuiltInCategory(books, currentPage, totalPage, url, nextUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getCategoryList failed: %{public}s', msg);
      return new BuiltInCategory([], 1, 1, url, '');
    }
  }

  // ────────────── 首页推荐 ──────────────

  async getHomeBlocks(): Promise<HomeBlock[]> {
    if (!this.def.home) return [];

    try {
      const body = await this.executeRequest(this.def.home.request, this.createVars());
      const isHtml = this.def.home.request.responseType === 'html';
      const data = this.parseResponseBody(body, isHtml);

      const blockElements = this.extractList(data, this.def.home.blocks, isHtml);
      const blocks: HomeBlock[] = [];

      for (const blockEl of blockElements) {
        const title = this.extractField(blockEl, this.def.home.blockItem.title, isHtml);
        if (!title) continue;

        const moreUrl = this.def.home.blockItem.moreUrl
          ? this.extractField(blockEl, this.def.home.blockItem.moreUrl, isHtml)
          : '';

        const bookElements = this.extractList(blockEl, this.def.home.blockItem.books, isHtml);
        const books: BuiltInBook[] = [];

        for (const bookEl of bookElements) {
          const name = this.extractField(bookEl, this.def.home.blockItem.bookItem.name, isHtml);
          const author = this.extractField(bookEl, this.def.home.blockItem.bookItem.author, isHtml);
          const cover = this.normalizeAssetUrl(this.extractField(bookEl, this.def.home.blockItem.bookItem.cover, isHtml));
          let bookId = this.extractField(bookEl, this.def.home.blockItem.bookItem.bookId, isHtml);
          const intro = this.def.home.blockItem.bookItem.intro
            ? this.extractField(bookEl, this.def.home.blockItem.bookItem.intro, isHtml)
            : '';

          bookId = this.normalizeBookId(bookId);

          if (!name || !bookId) continue;
          const book = new BuiltInBook(cover, bookId, name, author, '');
          book.intro = intro;
          books.push(book);
        }

        if (books.length === 0) continue;

        // layout 自动判断：如果 books 规则包含 book-ol 则是 grid，list-ul 则是 horizontal
        let layout = this.def.home.blockItem.layout || 'horizontal';
        if (layout === 'auto') {
          layout = this.def.home.blockItem.books.includes('book-ol') ? 'grid' : 'horizontal';
        }

        blocks.push(new HomeBlock(title, books, moreUrl, layout));
      }

      return blocks;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getHomeBlocks failed: %{public}s', msg);
      return [];
    }
  }

  // ────────────── 工具方法 ──────────────

  private async executeRequest(rule: RequestRule, vars: Record<string, string>): Promise<string> {
    this.ensureRequestAuthVars(vars);
    const url = this.renderTemplate(rule.url, vars);
    const method = rule.method || 'GET';
    const headers = this.mergeHeaders(rule);

    if (method === 'POST') {
      const body = rule.body ? this.renderTemplate(rule.body, vars) : '';
      return await HttpClient.post(url, body, headers, rule.charset);
    } else {
      return await HttpClient.get(url, headers, rule.charset);
    }
  }

  private createVars(): Record<string, string> {
    const vars: Record<string, string> = {};
    return vars;
  }

  private ensureRequestAuthVars(vars: Record<string, string>): void {
    if (!vars['timestamp']) {
      vars['timestamp'] = Math.floor(Date.now() / 1000).toString();
    }
    if (!vars['token']) {
      vars['token'] = CryptoUtils.md5Encode('chuanshuo_09_03' + vars['timestamp']);
    }
  }

  private parseResponseBody(body: string, isHtml: boolean): Object | string {
    if (isHtml) return body;
    return JSON.parse(body) as Object;
  }

  private mergeHeaders(rule: RequestRule): Record<string, string> {
    const headers: Record<string, string> = {};
    if (this.def.headers) {
      const globalKeys = Object.keys(this.def.headers);
      for (const key of globalKeys) {
        headers[key] = this.def.headers[key];
      }
    }
    if (rule.headers) {
      const ruleKeys = Object.keys(rule.headers);
      for (const key of ruleKeys) {
        headers[key] = rule.headers[key];
      }
    }
    return headers;
  }

  private renderTemplate(template: string, vars: Record<string, string>): string {
    return template.replace(/\{\{([^}]+)\}\}/g, (_match: string, rawKey: string): string => {
      const key = rawKey.trim();
      if (key === 'timestamp') {
        return vars['timestamp'] || Math.floor(Date.now() / 1000).toString();
      }
      if (key === 'token') {
        return vars['token'] || '';
      }
      if (key.startsWith('raw:')) {
        const rawVal = vars[key.substring(4)] || '';
        return rawVal;
      }
      const val = vars[key];
      return val ? encodeURIComponent(val) : '';
    });
  }

  private resolveUrl(relativeUrl: string): string {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    if (relativeUrl.startsWith('//')) return 'https:' + relativeUrl;
    if (relativeUrl.startsWith('/')) return this.def.baseUrl + relativeUrl;
    return this.def.baseUrl + '/' + relativeUrl;
  }

  private normalizeBookId(bookId: string): string {
    const id = (bookId || '').trim();
    if (!id) return '';
    if (id.startsWith('http') || id.startsWith('data:') || id.includes('://')) return id;
    if (id.startsWith('//')) return 'https:' + id;
    if (id.startsWith('/') || id.includes('/') || id.includes('?') || id.includes('.html')) {
      return this.resolveUrl(id);
    }
    return id;
  }

  private normalizeAssetUrl(url: string): string {
    const raw = (url || '').trim();
    if (!raw) return '';
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('//')) return 'https:' + raw;
    return this.resolveUrl(raw);
  }

  private normalizeCategoryUrl(url: string): string {
    const raw = (url || '').trim();
    if (!raw) return '';
    if (raw.startsWith('http') || raw.startsWith('data:')) return raw;
    if (raw.startsWith('//')) return 'https:' + raw;
    if (raw.includes('=') && !raw.includes('/')) return raw;
    return this.resolveUrl(raw);
  }

  private splitCategoryUrl(url: string): CategoryUrlParts {
    const idx = url.indexOf('?');
    if (idx < 0) {
      return new CategoryUrlParts(url, '');
    }
    return new CategoryUrlParts(url.substring(0, idx), url.substring(idx + 1));
  }

  private extractPage(url: string): number {
    const queryMatch = url.match(/[?&]page=(\d+)/i);
    if (queryMatch) return Math.max(1, parseInt(queryMatch[1], 10));
    const htmlMatch = url.match(/-(\d+)\.html/i);
    if (htmlMatch) return Math.max(1, parseInt(htmlMatch[1], 10));
    const pathMatch = url.match(/\/p(\d+)(?:\D|$)/i);
    if (pathMatch) return Math.max(1, parseInt(pathMatch[1], 10));
    return 1;
  }

  private nextCategoryUrl(url: string, currentPage: number, bookCount: number): string {
    if (bookCount <= 0) return '';
    if (/[?&]page=\d+/i.test(url)) {
      return url.replace(/([?&]page=)(\d+)/i, `$1${currentPage + 1}`);
    }
    if (/-(\d+)\.html/i.test(url) && bookCount >= 10) {
      return url.replace(/-(\d+)\.html/i, `-${currentPage + 1}.html`);
    }
    if (/\/p\d+(?:\D|$)/i.test(url) && bookCount >= 10) {
      return url.replace(/\/p\d+/i, `/p${currentPage + 1}`);
    }
    return '';
  }

  private buildChapterVars(chapterUrl: string, nextChapterUrl: string): Record<string, string> {
    const vars: Record<string, string> = this.createVars();
    vars['chapterUrl'] = chapterUrl;
    vars['nextChapterUrl'] = nextChapterUrl;
    const readMatch = chapterUrl.match(/\/read\/(\d+)\/(\d+)/);
    if (readMatch) {
      vars['aid'] = readMatch[1];
      vars['cid'] = readMatch[2];
    }
    const queryPairs = chapterUrl.match(/[?&][^=&#]+=[^&#]*/g) || [];
    for (const pair of queryPairs) {
      const eq = pair.indexOf('=');
      if (eq <= 1) continue;
      const key = pair.substring(1, eq);
      const value = pair.substring(eq + 1);
      vars[key] = decodeURIComponent(value);
    }
    return vars;
  }

  private extractList(data: Object | string, rule: string, isHtml: boolean): Array<Object | string> {
    if (isHtml && typeof data === 'string') {
      return this.extractCssList(data, rule);
    } else {
      return this.extractJsonList(data, rule);
    }
  }

  private extractField(item: Object | string, rule: string, isHtml: boolean): string {
    if (isHtml && typeof item === 'string') {
      return this.extractCssField(item, rule);
    } else {
      return this.extractJsonField(item, rule);
    }
  }

  private extractCssList(html: string, rule: string): string[] {
    // rule 可能是 "css:ul.book-ol > li.book-li" 或直接 "ul.book-ol > li.book-li"
    const cssRule = rule.replace(/^css:\s*/, '');

    // 支持 || 多规则尝试
    const rules = cssRule.split('||').map((r: string): string => r.trim());
    const doc = SimpleCSSSelector.parseHTML(html);

    for (const r of rules) {
      try {
        const elements = SimpleCSSSelector.querySelectorAll(doc, r);
        if (elements.length > 0) {
          return elements.map((el: HTMLElement): string => SimpleCSSSelector.outerHTML(el));
        }
      } catch (e) {
        continue;
      }
    }

    return [];
  }

  private extractCssField(html: string, rule: string): string {
    // rule: "css:h4@text || css:a@text" 或 "@text" 或 "@href"
    const cssRule = rule.replace(/^css:\s*/, '');
    const rules = cssRule.split('||').map((r: string): string => r.trim());
    const doc = SimpleCSSSelector.parseHTML(html);

    for (const r of rules) {
      try {
        // 特殊处理：如果规则只是 @attr，则直接从根元素提取
        if (r.startsWith('@')) {
          const attr = r.substring(1);
          if (attr === 'text') return SimpleCSSSelector.getText(doc);
          if (attr === 'html') return SimpleCSSSelector.innerHTML(doc);
          const rootAttr = SimpleCSSSelector.getAttribute(doc, attr);
          return rootAttr || '';
        }

        // 正常的 selector@attr 形式
        const atIdx = r.indexOf('@');
        if (atIdx < 0) {
          // 没有 @，默认取 text
          const elements = SimpleCSSSelector.querySelectorAll(doc, r);
          if (elements.length > 0) return SimpleCSSSelector.getText(elements[0]);
        } else {
          const selector = r.substring(0, atIdx).trim();
          const attr = r.substring(atIdx + 1).trim();
          const elements = SimpleCSSSelector.querySelectorAll(doc, selector);
          if (elements.length > 0) {
            const el = elements[0];
            if (attr === 'text') return SimpleCSSSelector.getText(el);
            if (attr === 'html') return SimpleCSSSelector.innerHTML(el);
            const value = SimpleCSSSelector.getAttribute(el, attr);
            if (value) return value;
          }
        }
      } catch (e) {
        continue;
      }
    }

    return '';
  }

  private extractJsonList(data: Object, rule: string): Object[] {
    // rule: "$.data.list[*]"
    try {
      const result: Object[] = jsonPath(data, rule);
      return result;
    } catch {
      return [];
    }
  }

  private extractJsonField(item: Object, rule: string): string {
    // rule: "$.title" 或 "$.data.book_name"
    const rules = rule.split('||')
      .map((r: string): string => r.trim())
      .filter((r: string): boolean => r.length > 0);
    if (rules.length > 1) {
      for (const r of rules) {
        const value = this.extractJsonField(item, r);
        if (value) return value;
      }
      return '';
    }
    try {
      const result: Object[] = jsonPath(item, rule);
      if (result.length > 0) {
        return result.map((v: Object): string => String(v || '').trim())
          .filter((v: string): boolean => v.length > 0)
          .join('\n');
      }
      return '';
    } catch {
      return '';
    }
  }
}
