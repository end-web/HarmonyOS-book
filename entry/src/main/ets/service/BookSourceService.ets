import { BookSource, SearchResult, TocItem, SourceSubscription, BookInfo } from '../model/BookSource';
import { AnalyzeRule, AnalyzeContext, BookContext } from './rule/AnalyzeRule';
import { AnalyzeUrl, AnalyzedUrl } from './rule/AnalyzeUrl';
import { HttpClient } from './http/HttpClient';
import { HttpResult } from './http/HttpResult';
import { SourceDataService } from './SourceDataService';
import { getJSExecutor } from './js/JSExecutor';
import { getSourceContext } from './rule/SourceContext';
import { getJsoup } from './rule/JsoupBridge';

const TAG = 'BookSourceService';

interface TemplateContext {
  key?: string;
  page?: number;
  speakText?: string;
  speakSpeed?: number;
  book?: Object;
  chapter?: Object;
  baseUrl?: string;
  result?: Object;
}

interface ExploreSection {
  source: BookSource;
  books: SearchResult[];
}

export class BookSourceService {
  // ──────────────────── 书源管理 ────────────────────

  static async fetchSourcesFromUrl(subscriptionUrl: string): Promise<BookSource[]> {
    try {
      const body = await HttpClient.get(subscriptionUrl);
      return BookSourceService.parseSourcesFromJson(body);
    } catch {
      return [];
    }
  }

  static parseSourcesFromJson(jsonText: string): BookSource[] {
    try {
      const data: Object = JSON.parse(jsonText) as Object;
      return Array.isArray(data) ? data as BookSource[] : [data as BookSource];
    } catch {
      return [];
    }
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    const firstName = sources.length > 0 ? sources[0].bookSourceGroup || '未命名' : '未命名';
    return { url, name: firstName, count: sources.length, lastUpdate: Date.now() };
  }

  // ──────────────────── 搜索 ────────────────────

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    try {
      if (!source.searchUrl) return [];

      // 设置书源上下文（供 source.key 访问）
      const sourceContext = getSourceContext();
      sourceContext.setSource({
        bookSourceUrl: source.bookSourceUrl,
        bookSourceName: source.bookSourceName,
        bookSourceType: source.bookSourceType
      });

      const analyzeUrl = new AnalyzeUrl(source.searchUrl, {
        key: keyword, page, baseUrl: source.bookSourceUrl,
      }, source.header);
      const analyzed = await analyzeUrl.getUrl();
      console.info(`[${TAG}] search: ${source.bookSourceName} -> ${analyzed.url}`);
      let body = await BookSourceService.fetch(analyzed);

      // 执行 loginCheckJs（搜索前验证）
      if (source.loginCheckJs) {
        body = await BookSourceService.executeLoginCheck(source, body, keyword);
      }

      // 检查 checkKeyWord（搜索结果验证）
      if (source.ruleSearch?.checkKeyWord) {
        if (!body.includes(source.ruleSearch.checkKeyWord)) {
          console.warn(`[${TAG}] checkKeyWord failed: ${source.ruleSearch.checkKeyWord}`);
          return [];
        }
      }

      const rule = source.ruleSearch;
      const ctx = new AnalyzeContext(analyzed.url);
      const analyzer = new AnalyzeRule(body, ctx);
      const items: Object[] = await analyzer.getElements(rule.bookList);
      if (items.length === 0) return [];

      const results: SearchResult[] = [];
      for (let idx = 0; idx < items.length; idx++) {
        const item: Object = items[idx];
        const itemCtx = new AnalyzeContext(analyzed.url);
        const a = new AnalyzeRule(item, itemCtx);
        const name = await a.getString(rule.name) || '';
        if (!name) continue;
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';
        const wordCount = rule.wordCount ? await a.getString(rule.wordCount) || '' : '';

        results.push({
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, coverUrlRaw),
          bookUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, bookUrlRaw),
          intro, kind, lastChapter, wordCount,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
          variables: itemCtx.variables,
        });
      }
      return results;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] searchBooks error: ${msg}`);
      return [];
    }
  }

  // ──────────────────── 书籍详情 ────────────────────

  static async getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    try {
      const rule = source.ruleBookInfo;
      if (!rule) return null;

      // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
      let processedUrl = bookUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
        return `{{java.get('${key}')}}`;
      });

      // 使用 AnalyzeUrl 解析 URL 模板（支持 {{key}} / <js>...</js> / @js:）
      try {
        const analyzeUrl = new AnalyzeUrl(processedUrl, { baseUrl: source.bookSourceUrl }, source.header, variables);
        const analyzed = await analyzeUrl.getUrl();
        processedUrl = analyzed.url;
      } catch (e) {
        console.error(`[${TAG}] getBookInfo AnalyzeUrl failed: ${e}, fallback to raw URL`);
      }

      const body = await BookSourceService.fetchWithSource(processedUrl, source);
      const ctx = new AnalyzeContext(processedUrl);
      ctx.book = { origin: source.bookSourceUrl, bookUrl: bookUrl, name: '' } as BookContext;
      const analyzer = new AnalyzeRule(body, ctx);

      // init 规则：预处理内容
      if (rule.init) {
        const initContent = await analyzer.getString(rule.init);
        if (initContent) {
          analyzer.setContent(initContent);
        }
      }

      const name = await analyzer.getString(rule.name) || '';
      const author = await analyzer.getString(rule.author) || '';
      const coverUrlRaw = await analyzer.getString(rule.coverUrl) || '';
      const intro = await analyzer.getString(rule.intro) || '';
      const kind = rule.kind ? await analyzer.getString(rule.kind) || '' : '';
      const wordCount = rule.wordCount ? await analyzer.getString(rule.wordCount) || '' : '';
      const lastChapter = rule.lastChapter ? await analyzer.getString(rule.lastChapter) || '' : '';
      const tocUrlRaw = await analyzer.getString(rule.tocUrl) || '';
      // tocUrl 可能包含多行（多个匹配结果用 \n 连接），只取第一个有效 URL
      const tocUrlFirst = tocUrlRaw.split('\n').map((s: string) => s.trim())
        .find((s: string) => s.length > 0 && !s.toLowerCase().startsWith('javascript:')) || '';
      const tocUrlResolved = tocUrlFirst ? AnalyzeUrl.resolveUrl(bookUrl, tocUrlFirst) : '';

      return {
        name, author,
        coverUrl: AnalyzeUrl.resolveUrl(bookUrl, coverUrlRaw),
        intro, kind, wordCount, lastChapter,
        tocUrl: tocUrlResolved || bookUrl,
        variables: ctx.variables,
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] getBookInfo error: ${msg}, bookUrl=${bookUrl}`);
      return null;
    }
  }

  // ──────────────────── 目录（支持分页） ────────────────────

  static async getBookToc(source: BookSource, tocUrl: string, variables?: Record<string, string>): Promise<TocItem[]> {
    const rule = source.ruleToc;
    const allItems: TocItem[] = [];
    let currentUrl: string = tocUrl.replace(/[\r\n\t]/g, '').trim();

    // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
    // 某些书源（如猫眼看书）的 bookUrl 包含 {aQnGo9} 占位符，需要手动转换
    currentUrl = currentUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
      return `{{java.get('${key}')}}`;
    });

    // Legado 对齐：使用 AnalyzeUrl 解析 URL 模板（支持 {{key}} / <js>...</js> / @js:）
    // 将 variables 注入到 JavaBridge，让 AnalyzeUrl 的 evalJS 能通过 java.get(key) 读取
    try {
      const analyzeUrl = new AnalyzeUrl(currentUrl, { baseUrl: source.bookSourceUrl }, source.header, variables);
      const analyzed = await analyzeUrl.getUrl();
      currentUrl = analyzed.url;
    } catch (e) {
      console.error(`[${TAG}] getBookToc AnalyzeUrl failed: ${e}, fallback to raw URL`);
    }
    let hasMore: boolean = true;
    const visitedUrls = new Set<string>();
    const maxPages = 50;

    while (hasMore && !visitedUrls.has(currentUrl) && visitedUrls.size < maxPages) {
      visitedUrls.add(currentUrl);
      try {
        const body = await BookSourceService.fetchWithSource(currentUrl, source);
        const ctx = new AnalyzeContext(currentUrl);
        ctx.book = { origin: source.bookSourceUrl, bookUrl: tocUrl, name: '' } as BookContext;
        const analyzer = new AnalyzeRule(body, ctx);
        const items: Object[] = await analyzer.getElements(rule.chapterList);
        console.info(`[${TAG}] getBookToc: rule=${rule.chapterList}, items=${items.length}, bodyLen=${body.length}`);

        for (let idx = 0; idx < items.length; idx++) {
          const item: Object = items[idx];
          const a = new AnalyzeRule(item, ctx);
          const name = await a.getString(rule.chapterName) || '';
          let url = await a.getString(rule.chapterUrl) || '';
          if (!name) continue;

          url = url ? AnalyzeUrl.resolveUrl(currentUrl, url) : '';
          if (!url) url = currentUrl;

          const tocItem: TocItem = { name, url };
          if (rule.isVip) {
            const vip = await a.getString(rule.isVip);
            tocItem.isVip = vip === 'true' || vip === '1';
          }
          if (rule.isVolume) {
            const vol = await a.getString(rule.isVolume);
            tocItem.isVolume = vol === 'true' || vol === '1';
          }
          if (rule.updateTime) {
            tocItem.updateTime = await a.getString(rule.updateTime) || undefined;
          }
          allItems.push(tocItem);
        }

        // 下一页
        if (rule.nextTocUrl) {
          const nextUrlRaw = await analyzer.getString(rule.nextTocUrl);
          const nextUrl = nextUrlRaw ? AnalyzeUrl.resolveUrl(currentUrl, nextUrlRaw) : '';
          if (nextUrl) {
            currentUrl = nextUrl;
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : JSON.stringify(e);
        console.error(`[${TAG}] getBookToc page error: ${msg}, url=${currentUrl}`);
        hasMore = false;
      }
    }

    return allItems;
  }

  // ──────────────────── 音频 URL ────────────────────

  static async getAudioUrl(source: BookSource, chapterUrl: string): Promise<string> {
    try {
      const rule = source.ruleContent;
      const contentRule = rule.audioUrl || rule.content;

      if (!contentRule || contentRule.trim().length === 0) {
        return chapterUrl;
      }

      const trimmed = contentRule.trim();
      if (trimmed === '@js:baseUrl' || trimmed === 'baseUrl') {
        return chapterUrl;
      }

      const body = await BookSourceService.fetchWithSource(chapterUrl, source);
      const ctx = new AnalyzeContext(chapterUrl);
      ctx.book = { origin: source.bookSourceUrl, bookUrl: chapterUrl, name: '' } as BookContext;
      const analyzer = new AnalyzeRule(body, ctx);
      const audioUrl = await analyzer.getString(contentRule);
      if (!audioUrl) return chapterUrl;

      return AnalyzeUrl.resolveUrl(chapterUrl, audioUrl);
    } catch {
      return chapterUrl;
    }
  }

  // ──────────────────── 文本内容（支持多页） ────────────────────

  static async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    try {
      const rule = source.ruleContent;
      const allContent: string[] = [];
      let currentUrl: string = chapterUrl;
      let hasMore: boolean = true;
      const visitedUrls = new Set<string>();
      const maxPages = 20;

      while (hasMore && !visitedUrls.has(currentUrl) && visitedUrls.size < maxPages) {
        visitedUrls.add(currentUrl);

        // 防止循环到下一章
        if (nextChapterUrl && currentUrl === nextChapterUrl) break;

        const body = await BookSourceService.fetchWithSource(currentUrl, source);
        const ctx = new AnalyzeContext(currentUrl);
        ctx.book = { origin: source.bookSourceUrl, bookUrl: currentUrl, name: '' } as BookContext;
        const analyzer = new AnalyzeRule(body, ctx);
        const content = await analyzer.getString(rule.content);
        if (content) {
          allContent.push(content);
        }

        // 下一页
        if (rule.nextContentUrl) {
          const nextUrl = await analyzer.getString(rule.nextContentUrl);
          if (nextUrl) {
            const resolved = AnalyzeUrl.resolveUrl(currentUrl, nextUrl);
            if (resolved !== nextChapterUrl) {
              currentUrl = resolved;
            } else {
              hasMore = false;
            }
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      }

      let result = allContent.join('\n');

      // sourceRegex：提取音频 URL（bookSourceType=1 时使用）
      if (rule.sourceRegex && result) {
        try {
          const regex = new RegExp(rule.sourceRegex);
          const match = result.match(regex);
          if (match && match[0]) {
            result = match[0];
            console.info(`[${TAG}] sourceRegex matched: ${result.substring(0, 100)}`);
          } else {
            console.warn(`[${TAG}] sourceRegex no match: ${rule.sourceRegex}`);
          }
        } catch (e) {
          console.error(`[${TAG}] sourceRegex error: ${e}`);
        }
      }

      // 应用全局替换规则
      if (rule.replaceRegex && result) {
        try {
          const replaceRules = rule.replaceRegex.split('&&');
          for (const rr of replaceRules) {
            const parts = rr.split('##');
            if (parts.length >= 1) {
              const pattern = parts[0];
              const replacement = parts.length > 1 ? parts[1] : '';
              const regex = new RegExp(pattern, 'g');
              result = result.replace(regex, replacement);
            }
          }
        } catch { /* ignore replace errors */ }
      }

      return result;
    } catch (e) {
      console.error(`[${TAG}] getTextContent error:`, e);
      return '';
    }
  }

  // ──────────────────── 发现/推荐 ────────────────────

  static async getExploreBooks(source: BookSource): Promise<SearchResult[]> {
    try {
      if (!source.exploreUrl || !source.ruleExplore) return [];

      const analyzeUrl = new AnalyzeUrl(source.exploreUrl, {
        page: 1, baseUrl: source.bookSourceUrl,
      }, source.header);
      const analyzed = await analyzeUrl.getUrl();
      const body = await BookSourceService.fetch(analyzed);

      const rule = source.ruleExplore;
      const ctx = new AnalyzeContext(analyzed.url);
      const analyzer = new AnalyzeRule(body, ctx);
      const items: Object[] = await analyzer.getElements(rule.bookList);
      if (items.length === 0) return [];

      const results: SearchResult[] = [];
      for (let idx = 0; idx < items.length; idx++) {
        const item: Object = items[idx];
        const a = new AnalyzeRule(item, ctx);
        const name = await a.getString(rule.name) || '';
        if (!name) continue;
        const author = await a.getString(rule.author) || '';
        const coverUrlRaw = await a.getString(rule.coverUrl) || '';
        const bookUrlRaw = await a.getString(rule.bookUrl) || '';
        const intro = await a.getString(rule.intro) || '';
        const kind = await a.getString(rule.kind) || '';
        const lastChapter = await a.getString(rule.lastChapter) || '';

        results.push({
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, coverUrlRaw),
          bookUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, bookUrlRaw),
          intro, kind, lastChapter,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
        });
      }
      return results;
    } catch {
      return [];
    }
  }

  static async getAllExploreBooks(): Promise<ExploreSection[]> {
    const sources = await SourceDataService.getSources();
    const enabledSources = sources.filter((s: BookSource) =>
      s.enabled !== false && s.exploreUrl && s.exploreUrl.length > 0 && s.ruleExplore
    );

    const results: ExploreSection[] = [];
    const tasks = enabledSources.map(async (source: BookSource) => {
      try {
        const books = await BookSourceService.getExploreBooks(source);
        if (books.length > 0) {
          results.push({ source, books });
        }
      } catch { /* ignore */ }
    });

    await Promise.all(tasks);
    return results;
  }

  // ──────────────────── HTTP 工具 ────────────────────

  private static async fetch(analyzed: AnalyzedUrl): Promise<string> {
    if (analyzed.method === 'POST') {
      return HttpClient.post(analyzed.url, analyzed.body || '', analyzed.headers, analyzed.charset);
    }
    return HttpClient.get(analyzed.url, analyzed.headers, analyzed.charset);
  }

  /**
   * 执行 loginCheckJs（搜索前验证）
   * 用于处理反爬虫、跳转、Cookie 验证等场景
   */
  private static async executeLoginCheck(source: BookSource, body: string, keyword: string): Promise<string> {
    try {
      if (!source.loginCheckJs) return body;

      console.info(`[${TAG}] executeLoginCheck: ${source.bookSourceName}`);
      const executor = getJSExecutor();
      const jsoup = getJsoup();

      // 创建 result 对象（模拟 Legado 的 Response）
      const result = new HttpResult(body);

      // 准备上下文
      const ctx: Record<string, Object> = {};
      ctx['result'] = result;
      ctx['source'] = getSourceContext();
      ctx['key'] = keyword;
      ctx['baseUrl'] = source.bookSourceUrl;

      // 注入 org.jsoup.Jsoup（简化：通过全局访问）
      // loginCheckJs 中的 org.jsoup.Jsoup.parse 会通过 JSExecutor 处理

      // 执行 loginCheckJs
      const newResult = await executor.eval(source.loginCheckJs, ctx);

      // 如果返回新的 result，提取 body
      if (newResult && typeof newResult === 'object') {
        // 尝试调用 body() 方法
        const resultObj = newResult as Record<string, Function>;
        const bodyMethod = resultObj['body'];
        if (bodyMethod && typeof bodyMethod === 'function') {
          return String(bodyMethod());
        }
      }

      // 如果返回字符串，直接使用
      if (typeof newResult === 'string') {
        return newResult;
      }

      // 否则返回原始 body
      return body;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] executeLoginCheck error: ${msg}`);
      return body;
    }
  }

  private static async fetchWithSource(url: string, source: BookSource): Promise<string> {
    const cleanUrl = url.replace(/[\r\n\t]/g, '').trim();
    const analyzeUrl = new AnalyzeUrl(cleanUrl, { baseUrl: source.bookSourceUrl }, source.header);
    const analyzed = await analyzeUrl.getUrl();
    // 若详情/章节 URL 自身没声明 charset，复用 search/explore 的 charset 推断
    if (!analyzed.charset) {
      const inferred = BookSourceService.inferCharset(source);
      if (inferred) analyzed.charset = inferred;
    }
    console.info(`[${TAG}] fetchWithSource: ${analyzed.url} charset=${analyzed.charset || 'utf-8'}`);
    return BookSourceService.fetch(analyzed);
  }

  /** 从 source.searchUrl / exploreUrl 中提取 ,{ "charset": "..." } 作为该源默认编码 */
  private static inferCharset(source: BookSource): string {
    const candidates: string[] = [];
    if (source.searchUrl) candidates.push(source.searchUrl);
    if (source.exploreUrl) candidates.push(source.exploreUrl);
    for (const c of candidates) {
      const m = c.match(/,\s*\{[^}]*"charset"\s*:\s*"([^"]+)"/i);
      if (m) return m[1];
    }
    return '';
  }
}
