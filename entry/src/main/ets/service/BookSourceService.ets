import { BookSource, SearchResult, TocItem, SourceSubscription, BookInfo, HomeBlockSection, SearchRule, BookInfoRule, TocRule, ContentRule } from '../model/BookSource';
import { AnalyzeRule, AnalyzeContext, BookContext } from './rule/AnalyzeRule';
import { AnalyzeUrl, AnalyzedUrl } from './rule/AnalyzeUrl';
import { HttpClient } from './http/HttpClient';
import { HttpResult } from './http/HttpResult';
import { SourceDataService } from './SourceDataService';
import { getJSExecutor } from './js/JSExecutor';
import { getSourceContext } from './rule/SourceContext';
import { getJsoup } from './rule/JsoupBridge';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';
import { BuiltInDispatcher } from './builtin/BuiltInDispatcher';
import { getWebViewAudioExtractor } from './builtin/WebViewAudioExtractor';
import { DataUrlHandler } from './DataUrlHandler';
import { getJavaBridge } from './rule/JavaBridge';
import { getCookieManager } from './rule/CookieManager';
import { SourceVariableStore } from './SourceVariableStore';
import { getCacheService } from './CacheService';
import { getRateLimiter } from './ConcurrentRateLimiter';

const TAG = 'BookSourceService';

interface PostInfo {
  url: string;
  body: string;
}

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

class HomeBlockImpl implements HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;

  constructor(title: string, books: SearchResult[], moreUrl: string, layout: string,
              sourceName: string, sourceUrl: string) {
    this.title = title;
    this.books = books;
    this.moreUrl = moreUrl;
    this.layout = layout;
    this.sourceName = sourceName;
    this.sourceUrl = sourceUrl;
  }
}

export class BookSourceService {
  // ──────────────────── 辅助方法 ────────────────────

  /**
   * 构建 JS 执行上下文，注入 jsLib、源变量、cache 等
   */
  private static buildJsContext(source: BookSource, extra?: Record<string, Object>): Record<string, Object> {
    const ctx: Record<string, Object> = {};
    // 注入 jsLib
    if (source.jsLib) {
      ctx['_jsLib'] = source.jsLib;
    }
    // 注入源变量
    try {
      const sourceVars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
      const javaVars: Record<string, string> = {};
      for (const k of Object.keys(sourceVars)) {
        javaVars[k] = String(sourceVars[k]);
      }
      ctx['_javaVars'] = javaVars;
      // 注入完整的源变量 JSON（供 source.getVariable() 返回）
      ctx['_sourceVar'] = JSON.stringify(sourceVars);
    } catch (e) {
      console.warn(`[${TAG}] buildJsContext: sourceVars error: ${e}`);
    }
    // 合并额外上下文
    if (extra) {
      for (const k of Object.keys(extra)) {
        ctx[k] = extra[k];
      }
    }
    return ctx;
  }

  /**
   * 处理 data: URL — 解码 base64 数据并存入 JavaBridge 变量
   * 返回 true 表示是 data: URL 并已处理，false 表示不是
   */
  private static handleDataUrl(url: string): boolean {
    if (!DataUrlHandler.isDataUrl(url)) return false;
    const parsed = DataUrlHandler.parse(url);
    if (!parsed) return false;
    // 将解码的数据存入 JavaBridge 变量
    const javaBridge = getJavaBridge();
    const dataKeys = Object.keys(parsed.data);
    for (const k of dataKeys) {
      javaBridge.put(k, String(parsed.data[k]));
    }
    return true;
  }

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

  /**
   * 展开聚合源：为每个听书子源创建独立的书源条目
   * 光遇聚合等聚合源内部集合了多个平台（番茄、七猫、喜马拉雅等），
   * 每个子源共用同一台服务器和 jsLib，但各自只搜指定平台。
   *
   * @param sources 原始导入的书源列表
   * @returns 展开后的书源列表（包含原始源 + 子源）
   */
  static async expandAggregateSources(sources: BookSource[]): Promise<BookSource[]> {
    const result: BookSource[] = [];
    for (const source of sources) {
      result.push(source);
      // 检测聚合源：bookSourceType=0 且有 jsLib（含 getCloudSettings/getVariable）
      if (source.bookSourceType === 0 && source.jsLib && source.jsLib.includes('getCloudSettings')) {
        try {
          const subSources = await BookSourceService.fetchSubSources(source);
          result.push(...subSources);
          console.info(`[${TAG}] expandAggregate: ${source.bookSourceName} -> ${subSources.length} audio sub-sources`);
        } catch (e) {
          console.warn(`[${TAG}] expandAggregate failed for ${source.bookSourceName}: ${e}`);
        }
      }
    }
    return result;
  }

  /**
   * 从聚合源服务器获取听书子源列表，为每个子源创建独立书源
   */
  private static async fetchSubSources(parentSource: BookSource): Promise<BookSource[]> {
    // 从 jsLib 中提取默认 hosts 列表
    const hostsMatch = parentSource.jsLib!.match(/let\s+hosts\s*=\s*\[([\s\S]*?)\]/);
    let hosts: string[] = ['https://v1.gyks.cf'];
    if (hostsMatch) {
      const hostLines = hostsMatch[1].split('\n');
      hosts = hostLines
        .map((line: string) => {
          const m = line.match(/'(https?:\/\/[^']+)'/);
          return m ? m[1] : '';
        })
        .filter((h: string) => h.length > 0);
    }

    // 尝试从服务器获取云端配置（听书子源列表）
    let audioSourceNames: string[] = [];
    for (const host of hosts) {
      try {
        const configUrl = `${host}/static/source_config/config.json`;
        const configBody = await HttpClient.get(configUrl);
        const config: Record<string, Object> = JSON.parse(configBody) as Record<string, Object>;
        const audioSources = config['听书'];
        if (Array.isArray(audioSources) && audioSources.length > 0) {
          audioSourceNames = audioSources as string[];
          break;
        }
      } catch {
        continue; // 尝试下一个 host
      }
    }

    // 如果无法获取云端配置，使用硬编码的默认列表
    if (audioSourceNames.length === 0) {
      audioSourceNames = ['番茄', '七猫', '喜马拉雅', '酷我'];
    }

    // 预获取完整的云端配置（用于缓存到子源变量，避免 jsLib 发 HTTP 请求）
    let cloudConfig: Record<string, Object> | null = null;
    for (const host of hosts) {
      try {
        const configUrl = `${host}/static/source_config/config.json`;
        const configBody = await HttpClient.get(configUrl);
        cloudConfig = JSON.parse(configBody) as Record<string, Object>;
        break;
      } catch { continue; }
    }

    // 默认服务器地址
    const defaultHost = hosts.length > 0 ? hosts[0] : 'https://v1.gyks.cf';

    // 为每个听书子源创建独立书源
    // 关键：使用直接 HTTP URL + 简单 JSONPath 规则，完全绕过 jsLib/WebView 执行
    const subSources: BookSource[] = [];
    for (const sourceName of audioSourceNames) {
      const subUrl = `${parentSource.bookSourceUrl}#听书-${sourceName}`;
      const encSrc = encodeURIComponent(sourceName);
      // 直接构造搜索 URL，不需要 jsLib 执行
      const directSearchUrl = `${defaultHost}/search?title={{key}}&tab=%E5%90%AC%E4%B9%A6&source=${encSrc}&page={{page}}&disabled_sources=0`;

      // bookUrl 直接用服务器详情 URL（book_id 会被替换）
      const detailUrlTemplate = `${defaultHost}/detail?book_id={{book_id}}&source=${encSrc}&tab=%E5%90%AC%E4%B9%A6`;
      // tocUrl 用服务器目录 URL
      const catalogUrlTemplate = `${defaultHost}/catalog?book_id={{book_id}}&source=${encSrc}&tab=%E5%90%AC%E4%B9%A6`;

      const subSource: BookSource = {
        bookSourceUrl: `聚合听书-${sourceName}-${defaultHost}`, // 唯一标识
        bookSourceName: `${parentSource.bookSourceName}·${sourceName}`,
        bookSourceType: 1, // 音频类型
        bookSourceGroup: `聚合听书,${sourceName}`,
        bookSourceComment: `从 ${parentSource.bookSourceName} 提取的听书子源`,
        enabled: true,
        enabledExplore: false,
        enabledCookieJar: parentSource.enabledCookieJar,
        searchUrl: directSearchUrl,
        exploreUrl: '', // 子源不需要发现页
        header: parentSource.header,
        jsLib: '', // 不需要 jsLib，直接 HTTP 请求
        respondTime: parentSource.respondTime,
        customOrder: parentSource.customOrder + 1,
        weight: parentSource.weight,
        // 搜索规则：直接 JSONPath 解析
        ruleSearch: {
          bookList: '$.data[*]',
          name: '$.book_name',
          author: '$.author',
          coverUrl: '$.thumb_url',
          bookUrl: '$.book_id',
          intro: '$.abstract',
          kind: '{{$.status}},{{$.score}},{{$.tags}}',
          lastChapter: '{{$.source}} {{$.last_chapter_title}}',
          wordCount: '$.word_number',
        } as SearchRule,
        // 详情规则：从详情 API 提取字段
        ruleBookInfo: {
          name: '$.data.book_name',
          author: '$.data.author',
          coverUrl: '$.data.thumb_url',
          intro: '$.data.abstract',
          kind: '{{$.data.status}},{{$.data.score}},{{$.data.tags}}',
          lastChapter: '$.data.last_chapter_title',
          wordCount: '$.data.word_number',
          tocUrl: '$.data.catalog_url',
        } as BookInfoRule,
        // 目录规则：从目录 API 提取章节列表
        ruleToc: {
          chapterList: '$.data[*]',
          chapterName: '$.title',
          chapterUrl: '$.content_url',
        } as TocRule,
        // 内容规则：从内容 API 提取音频 URL
        ruleContent: {
          content: '$.data.url',
        } as ContentRule,
        ruleExplore: { bookList: '', name: '', author: '', coverUrl: '', bookUrl: '', intro: '', kind: '', lastChapter: '' },
        subscriptionUrl: parentSource.subscriptionUrl,
      };
      subSources.push(subSource);
    }

    return subSources;
  }

  static buildSubscription(url: string, sources: BookSource[]): SourceSubscription {
    const firstName = sources.length > 0 ? sources[0].bookSourceGroup || '未命名' : '未命名';
    return { url, name: firstName, count: sources.length, lastUpdate: Date.now() };
  }

  // ──────────────────── 搜索 ────────────────────

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.search(source, keyword, page);
    }

    // 聚合源（bookSourceType=0）搜索时临时设置搜索模式为"听书"
    // 这样服务端只搜听书后端（喜马拉雅、懒人听书等），不搜小说/漫画
    // 搜索完成后恢复原设置，不影响用户配置
    const isAggregate = source.bookSourceType === 0;
    let savedSearchMode = '';
    if (isAggregate) {
      try {
        const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
        const moreSettings: Record<string, Object> = (vars['更多设置'] as Record<string, Object>) || {} as Record<string, Object>;
        savedSearchMode = (moreSettings['搜索模式'] as string) || '';
        moreSettings['搜索模式'] = '听书';
        SourceVariableStore.setSourceVariable(source.bookSourceUrl, '更多设置', moreSettings);
      } catch { /* ignore */ }
    }

    try {
      if (!source.searchUrl) return [];

      // 设置书源上下文（供 source.key 访问）
      const sourceContext = getSourceContext();
      sourceContext.setSource({
        bookSourceUrl: source.bookSourceUrl,
        bookSourceName: source.bookSourceName,
        bookSourceType: source.bookSourceType
      });

      // 子源（无 jsLib 且 searchUrl 是完整 HTTP URL）：直接替换模板变量，跳过 AnalyzeUrl
      // 避免并发时 SourceVariableStore / AnalyzeUrl 卡住
      let analyzedUrl: string;
      let analyzedMethod = 'GET';
      let analyzedBody: string | undefined;
      const analyzedHeaders: Record<string, string> = {};
      if (!source.jsLib && source.searchUrl.startsWith('http')) {
        analyzedUrl = source.searchUrl
          .replace(/\{\{key\}\}/g, encodeURIComponent(keyword))
          .replace(/\{\{keyword\}\}/g, encodeURIComponent(keyword))
          .replace(/\{\{page\}\}/g, String(page));
        // 子源：自动带上 qttoken cookie
        try {
          const cookieManager = getCookieManager();
          const hostMatch = analyzedUrl.match(/^(https?:\/\/[^/]+)/);
          if (hostMatch) {
            const cookie = cookieManager.getCookie(hostMatch[1]);
            if (cookie && cookie.includes('qttoken')) {
              analyzedHeaders['Cookie'] = cookie;
            }
          }
        } catch { /* ignore */ }
      } else {
        // 原始路径：通过 AnalyzeUrl 处理 jsLib/模板/JS 表达式
        const searchUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, source.searchUrl);
        let sourceVarJson = '';
        try {
          const sourceVars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
          sourceVarJson = JSON.stringify(sourceVars);
        } catch { /* ignore */ }
        const analyzeUrl = new AnalyzeUrl(searchUrl, {
          key: keyword, page, baseUrl: source.bookSourceUrl,
          _jsLib: source.jsLib || '',
          _sourceVar: sourceVarJson,
        }, source.header);
        const analyzed = await analyzeUrl.getUrl();
        analyzedUrl = analyzed.url;
        analyzedMethod = analyzed.method;
        analyzedBody = analyzed.body;
        const hdrKeys = Object.keys(analyzed.headers);
        for (const hk of hdrKeys) analyzedHeaders[hk] = analyzed.headers[hk];
      }
      console.info(`[${TAG}] search: ${source.bookSourceName} -> ${analyzedUrl.substring(0, 150)}`);

      // 处理 data: URL — 搜索 URL 返回 data: 编码的参数
      // data: URL 的 base64 内容需要作为 result 传给 bookList 规则
      let body: string;
      if (DataUrlHandler.isDataUrl(analyzedUrl)) {
        BookSourceService.handleDataUrl(analyzedUrl);
        // 提取 base64 部分作为 result（bookList JS 规则需要）
        const base64Idx = analyzedUrl.indexOf('base64,');
        if (base64Idx >= 0) {
          const afterBase64 = analyzedUrl.substring(base64Idx + 7);
          // 去掉末尾的 ,{config} 部分，只保留 base64 数据
          const lastComma = afterBase64.lastIndexOf(',{');
          body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
        } else {
          body = '';
        }
      } else {
        const tmpAnalyzed: AnalyzedUrl = { url: analyzedUrl, method: analyzedMethod, body: analyzedBody, headers: analyzedHeaders, retry: 0 };
        body = await BookSourceService.fetch(tmpAnalyzed);
      }

      // 执行 loginCheckJs（搜索前验证）
      // 仅当响应看起来不是正常数据时才执行（如 HTML 跳转页、空数据等）
      // 正常 JSON/XML 响应直接跳过，避免引擎不支持的 JS API 导致卡死
      if (source.loginCheckJs && BookSourceService.needsLoginCheck(body)) {
        body = await BookSourceService.executeLoginCheck(source, body, keyword);
        // loginCheck 返回重试标记 → POST 已建立搜索会话，重新 GET 原始 URL
        if (body === '__RETRY_SEARCH__') {
          console.info(`[${TAG}] loginCheck: retrying search after session established`);
          const tmpAnalyzed: AnalyzedUrl = { url: analyzedUrl, method: analyzedMethod, body: analyzedBody, headers: analyzedHeaders, retry: 0 };
          body = await BookSourceService.fetch(tmpAnalyzed);
        }
      }

      // 检查 checkKeyWord（反爬检测，软警告）
      // 原意：响应被反爬拦截（如跳转到验证页）时会缺少这个关键词
      // 不强制要求响应必须包含它，缺失只记录警告，继续解析
      if (source.ruleSearch?.checkKeyWord) {
        if (!body.includes(source.ruleSearch.checkKeyWord)) {
          console.warn(`[${TAG}] [AntiCrawl?] Response missing checkKeyWord "${source.ruleSearch.checkKeyWord}", may be blocked. Continue parsing anyway.`);
        }
      }

      const rule = source.ruleSearch;
      // 子源：从搜索 URL 提取服务器地址（用于构造详情/目录 URL）
      const serverHostMatch = analyzedUrl.match(/^(https?:\/\/[^/]+)/);
      const serverHost = serverHostMatch ? serverHostMatch[1] : '';
      const ctx = new AnalyzeContext(analyzedUrl);
      ctx.jsLib = source.jsLib || '';
      const analyzer = new AnalyzeRule(body, ctx);
      console.info(`[${TAG}] search parse: bodyLen=${body.length}, first200=${body.substring(0, 200)}`);
      const items: Object[] = await analyzer.getElements(rule.bookList);
      console.info(`[${TAG}] search parse: bookList="${rule.bookList}" -> items=${items.length}`);
      if (items.length === 0) return [];

      // 子源标识：bookSourceGroup 以 '聚合听书,' 开头
      const isSubSource = (source.bookSourceGroup || '').startsWith('聚合听书,');

      const results: SearchResult[] = [];
      for (let idx = 0; idx < items.length; idx++) {
        const item: Object = items[idx];
        const itemCtx = new AnalyzeContext(analyzedUrl);
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
        // updateTime（Legado 对齐）
        if (rule.updateTime) {
          const ut = await a.getString(rule.updateTime) || '';
          if (ut) itemCtx.variables['updateTime'] = ut;
        }

        let finalBookUrl: string;
        if (isSubSource && !source.jsLib && serverHost) {
          // 子源：根据 item 字段构造完整的详情 URL
          const itemRec = item as Record<string, Object>;
          const bookId = String(itemRec['book_id'] || bookUrlRaw || '');
          const srcName = String(itemRec['source'] || '');
          const tab = String(itemRec['tab'] || '听书');
          finalBookUrl = `${serverHost}/detail?book_id=${encodeURIComponent(bookId)}&source=${encodeURIComponent(srcName)}&tab=${encodeURIComponent(tab)}`;
        } else {
          finalBookUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, bookUrlRaw);
        }

        results.push({
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, coverUrlRaw),
          bookUrl: finalBookUrl,
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
    } finally {
      // 恢复聚合源的搜索模式设置
      if (isAggregate && savedSearchMode) {
        try {
          const vars = SourceVariableStore.getSourceVariables(source.bookSourceUrl);
          const moreSettings: Record<string, Object> = (vars['更多设置'] as Record<string, Object>) || {} as Record<string, Object>;
          moreSettings['搜索模式'] = savedSearchMode;
          SourceVariableStore.setSourceVariable(source.bookSourceUrl, '更多设置', moreSettings);
        } catch { /* ignore */ }
      }
    }
  }

  // ──────────────────── 书籍详情 ────────────────────

  static async getBookInfo(source: BookSource, bookUrl: string, variables?: Record<string, string>): Promise<BookInfo | null> {
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getBookInfo(source, bookUrl);
    }
    try {
      const rule = source.ruleBookInfo;
      if (!rule) return null;

      // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
      let processedUrl = bookUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
        return `{{java.get('${key}')}}`;
      });

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(processedUrl)) {
        BookSourceService.handleDataUrl(processedUrl);
        // data: URL 本身不需要 HTTP 请求，直接用空 body 继续解析规则
        // 规则中的 JS 会通过 java.get() 获取已解码的数据
      }

      // 使用 AnalyzeUrl 解析 URL 模板（支持 {{key}} / <js>...</js> / @js:）
      try {
        const analyzeUrl = new AnalyzeUrl(processedUrl, {
          baseUrl: source.bookSourceUrl,
          _jsLib: source.jsLib || '',
        }, source.header, variables);
        const analyzed = await analyzeUrl.getUrl();
        processedUrl = analyzed.url;
      } catch (e) {
        console.error(`[${TAG}] getBookInfo AnalyzeUrl failed: ${e}, fallback to raw URL`);
      }

      // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
      let body: string;
      if (DataUrlHandler.isDataUrl(processedUrl)) {
        BookSourceService.handleDataUrl(processedUrl);
        const base64Idx = processedUrl.indexOf('base64,');
        if (base64Idx >= 0) {
          const afterBase64 = processedUrl.substring(base64Idx + 7);
          const lastComma = afterBase64.lastIndexOf(',{');
          body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
        } else {
          body = '';
        }
      } else {
        body = await BookSourceService.fetchWithSource(processedUrl, source);
      }
      const ctx = new AnalyzeContext(processedUrl);
      ctx.jsLib = source.jsLib || '';
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
      // updateTime（Legado 对齐）
      if (rule.updateTime) {
        const ut = await analyzer.getString(rule.updateTime) || '';
        if (ut) ctx.variables['updateTime'] = ut;
      }
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
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getBookToc(source, tocUrl);
    }
    const rule = source.ruleToc;
    const allItems: TocItem[] = [];
    let currentUrl: string = tocUrl.replace(/[\r\n\t]/g, '').trim();

    // preUpdateJs：TOC 抓取前执行 JS（Legado 对齐）
    // 可用于刷新 tocUrl、重新获取 bookInfo 等
    if (rule.preUpdateJs) {
      try {
        const bookCtx: BookContext = { origin: source.bookSourceUrl, bookUrl: tocUrl, name: '' };
        const bookExtra: Record<string, Object> = {};
        bookExtra['book'] = bookCtx as Object;
        const jsCtx = BookSourceService.buildJsContext(source, bookExtra);
        const executor = getJSExecutor();
        const evalCtx: Record<string, Object> = {};
        evalCtx['result'] = currentUrl as Object;
        evalCtx['baseUrl'] = source.bookSourceUrl as Object;
        evalCtx['book'] = bookCtx as Object;
        const jsCtxKeys = Object.keys(jsCtx);
        for (const k of jsCtxKeys) evalCtx[k] = jsCtx[k];
        const preResult = await executor.eval(rule.preUpdateJs, evalCtx);
        if (preResult && typeof preResult === 'string' && preResult.startsWith('http')) {
          console.info(`[${TAG}] preUpdateJs returned new tocUrl: ${preResult.substring(0, 100)}`);
          currentUrl = preResult;
        }
      } catch (e) {
        console.warn(`[${TAG}] preUpdateJs error: ${e}`);
      }
    }

    // 兜底：将单花括号 {key} 转换为 Legado 标准语法 {{java.get('key')}}
    // 某些书源（如猫眼看书）的 bookUrl 包含 {aQnGo9} 占位符，需要手动转换
    currentUrl = currentUrl.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match: string, key: string): string => {
      return `{{java.get('${key}')}}`;
    });

    // 处理 data: URL（代理书源的中间路由机制）
    if (DataUrlHandler.isDataUrl(currentUrl)) {
      BookSourceService.handleDataUrl(currentUrl);
    }

    // Legado 对齐：使用 AnalyzeUrl 解析 URL 模板（支持 {{key}} / <js>...</js> / @js:）
    // 将 variables 注入到 JavaBridge，让 AnalyzeUrl 的 evalJS 能通过 java.get(key) 读取
    try {
      const analyzeUrl = new AnalyzeUrl(currentUrl, {
        baseUrl: source.bookSourceUrl,
        _jsLib: source.jsLib || '',
      }, source.header, variables);
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
        // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
        let body: string;
        if (DataUrlHandler.isDataUrl(currentUrl)) {
          BookSourceService.handleDataUrl(currentUrl);
          const base64Idx = currentUrl.indexOf('base64,');
          if (base64Idx >= 0) {
            const afterBase64 = currentUrl.substring(base64Idx + 7);
            const lastComma = afterBase64.lastIndexOf(',{');
            body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
          } else {
            body = '';
          }
        } else {
          body = await BookSourceService.fetchWithSource(currentUrl, source);
        }

        // 检测 JS 反爬页面（如水山听书：base64 混淆重定向，bodyLen 很小且含 atob）
        // 用 WebView 渲染获取真实 HTML
        if (body.length < 3000 && (body.includes('atob') || body.includes('base64')) && body.includes('Loading')) {
          console.info(`[${TAG}] getBookToc: detected JS anti-crawl page, using WebView to render`);
          try {
            const extractor = getWebViewAudioExtractor();
            body = await extractor.extract(currentUrl, 'document.documentElement.outerHTML', 3000);
          } catch (e) {
            console.warn(`[${TAG}] getBookToc: WebView render failed: ${e}`);
          }
        }

        const ctx = new AnalyzeContext(currentUrl);
        ctx.jsLib = source.jsLib || '';
        ctx.book = { origin: source.bookSourceUrl, bookUrl: tocUrl, name: '' } as BookContext;
        const analyzer = new AnalyzeRule(body, ctx);
        // Legado 对齐：chapterList 支持 -/+ 前缀
        // - 前缀：反转列表（旧章节在前）
        // + 前缀：默认顺序（新章节在前，等同于无前缀）
        let chapterListRule = rule.chapterList;
        let reverseList = false;
        if (chapterListRule.startsWith('-')) {
          reverseList = true;
          chapterListRule = chapterListRule.substring(1);
        } else if (chapterListRule.startsWith('+')) {
          chapterListRule = chapterListRule.substring(1);
        }
        const items: Object[] = await analyzer.getElements(chapterListRule);
        if (reverseList) items.reverse();
        console.info(`[${TAG}] getBookToc: rule=${rule.chapterList}, items=${items.length}, reverse=${reverseList}, bodyLen=${body.length}`);

        for (let idx = 0; idx < items.length; idx++) {
          const item: Object = items[idx];
          const a = new AnalyzeRule(item, ctx);
          let name = await a.getString(rule.chapterName) || '';
          let url = await a.getString(rule.chapterUrl) || '';
          if (!name) continue;

          // formatJs：章节标题后处理 JS（Legado 对齐）
          // 变量：index（1-based）、title（章节标题）、gInt（全局计数器）
          if (rule.formatJs) {
            try {
              const chapterInfo: Record<string, Object> = {};
              chapterInfo['title'] = name as Object;
              chapterInfo['url'] = url as Object;
              chapterInfo['index'] = allItems.length as Object;
              const extraCtx: Record<string, Object> = {};
              extraCtx['index'] = (allItems.length + 1) as Object;
              extraCtx['title'] = name as Object;
              extraCtx['gInt'] = allItems.length as Object;
              extraCtx['chapter'] = chapterInfo as Object;
              const jsCtx = BookSourceService.buildJsContext(source, extraCtx);
              const executor = getJSExecutor();
              const fmtCtx: Record<string, Object> = {};
              fmtCtx['result'] = name as Object;
              fmtCtx['baseUrl'] = currentUrl as Object;
              fmtCtx['index'] = (allItems.length + 1) as Object;
              fmtCtx['title'] = name as Object;
              fmtCtx['gInt'] = allItems.length as Object;
              const jsCtxKeys = Object.keys(jsCtx);
              for (const k of jsCtxKeys) fmtCtx[k] = jsCtx[k];
              const fmtResult = await executor.eval(rule.formatJs, fmtCtx);
              if (fmtResult && typeof fmtResult === 'string') {
                name = fmtResult;
              }
            } catch (e) {
              console.warn(`[${TAG}] formatJs error: ${e}`);
            }
          }

          // 修复 @js:result+',{...}' 未正确执行的情况
          // 如果 URL 包含字面量 "result+" 说明 JS 拼接失败，手动处理
          if (url.includes("result+'") || url.includes('result+"')) {
            const hrefVal = await a.getString('a@href') || '';
            if (hrefVal) {
              const configMatch = url.match(/result\+['"](.*)['"]/);
              url = configMatch ? hrefVal + configMatch[1] : hrefVal;
            }
          }

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
    console.info(`[${TAG}] getAudioUrl called: ${chapterUrl.substring(0, 150)}`);
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getAudioUrl(source, chapterUrl);
    }
    try {
      const rule = source.ruleContent;
      const contentRule = rule.audioUrl || rule.content;

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(chapterUrl)) {
        BookSourceService.handleDataUrl(chapterUrl);
      }

      // 拆分 Legado ",{...}" 配置语法（如 url,{webView:"true"}）
      const split = AnalyzeUrl.splitUrlConfig(chapterUrl);
      const realUrl = split.url;
      const webViewVal = split.config.webView;
      const useWebView = webViewVal === true || String(webViewVal) === 'true';

      if (!contentRule || contentRule.trim().length === 0) {
        return realUrl;
      }

      const trimmed = contentRule.trim();
      if (trimmed === '@js:baseUrl' || trimmed === 'baseUrl') {
        return realUrl;
      }

      // WebView 模式：用 WebView 加载页面，提取音频 URL
      if (useWebView) {
        console.info(`[${TAG}] getAudioUrl: WebView mode for ${realUrl}`);
        try {
          const extractor = getWebViewAudioExtractor();
          // 优先使用书源自定义 webJs，否则用内置通用提取逻辑
          const defaultJsExpr = `(function(){
            var result = '';
            // 1. 尝试 audio 标签
            var audios = document.querySelectorAll('audio');
            for(var i=0;i<audios.length;i++){
              if(audios[i].src) return audios[i].src;
            }
            // 2. 尝试 source 标签
            var sources = document.querySelectorAll('source');
            for(var i=0;i<sources.length;i++){
              if(sources[i].src) return sources[i].src;
            }
            // 3. 从页面 HTML 中用正则提取音频 URL
            var html = document.body.innerHTML;
            var patterns = [
              /https?:\\/\\/[^"'\\s<>]+\\.mp3[^"'\\s<>]*/gi,
              /https?:\\/\\/[^"'\\s<>]+\\.m4a[^"'\\s<>]*/gi,
              /"(https?:\\/\\/[^"]+\\.(?:mp3|m4a|wav|ogg|aac)[^"]*)"/gi,
              /'(https?:\\/\\/[^']+\\.(?:mp3|m4a|wav|ogg|aac)[^']*)'/gi
            ];
            for(var p=0;p<patterns.length;p++){
              var m = html.match(patterns[p]);
              if(m && m[0]) return m[0].replace(/['"]/g,'');
            }
            // 4. 尝试从 window 对象中查找音频 URL 变量
            var commonVars = ['audioUrl', 'audio_url', 'mp3Url', 'mp3_url', 'mediaUrl', 'media_url', 'playUrl', 'play_url', 'src', 'url'];
            for(var v=0;v<commonVars.length;v++){
              if(window[commonVars[v]] && typeof window[commonVars[v]] === 'string' && window[commonVars[v]].match(/\\.mp3|\\.m4a/)){
                return window[commonVars[v]];
              }
            }
            // 5. 尝试从 script 标签中提取 URL
            var scripts = document.querySelectorAll('script');
            for(var s=0;s<scripts.length;s++){
              var scriptText = scripts[s].textContent || scripts[s].innerText || '';
              var urlMatch = scriptText.match(/https?:\\/\\/[^"'\\s]+\\.(?:mp3|m4a)/);
              if(urlMatch) return urlMatch[0];
            }
            // 6. 返回页面标题和前 500 字符的 HTML 作为调试信息
            return 'DEBUG:title=' + document.title + ',bodyLen=' + html.length + ',html=' + html.substring(0, 500);
          })()`;
          // 如果书源定义了 webJs，使用它；否则用内置默认提取逻辑
          const jsExpr = rule.webJs ? rule.webJs : defaultJsExpr;
          const audioUrl = await extractor.extract(realUrl, jsExpr, 8000);
          console.info(`[${TAG}] getAudioUrl WebView result: ${audioUrl.substring(0, 200)}`);
          if (audioUrl && !audioUrl.startsWith('DEBUG:')) return audioUrl;
          if (audioUrl.startsWith('DEBUG:')) {
            console.warn(`[${TAG}] getAudioUrl WebView debug: ${audioUrl}`);
          }
          // WebView 提取失败，抛出错误让上层处理
          throw new Error(`书源 ${source.bookSourceName} 无法提取音频 URL，可能需要更新书源规则`);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          console.error(`[${TAG}] getAudioUrl WebView failed: ${msg}`);
          throw e instanceof Error ? e : new Error(msg);
        }
      }

      const body = await BookSourceService.fetchWithSource(realUrl, source);
      const ctx = new AnalyzeContext(realUrl);
      ctx.jsLib = source.jsLib || '';
      ctx.book = { origin: source.bookSourceUrl, bookUrl: realUrl, name: '' } as BookContext;
      const analyzer = new AnalyzeRule(body, ctx);
      const audioUrl = await analyzer.getString(contentRule);
      if (!audioUrl) return realUrl;

      return AnalyzeUrl.resolveUrl(realUrl, audioUrl);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`[${TAG}] getAudioUrl error: ${msg}, url=${chapterUrl.substring(0, 100)}`);
      return chapterUrl;
    }
  }

  // ──────────────────── 文本内容（支持多页） ────────────────────

  static async getTextContent(source: BookSource, chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    try {
      const rule = source.ruleContent;
      const allContent: string[] = [];
      let currentUrl: string = chapterUrl;

      // 处理 data: URL（代理书源的中间路由机制）
      if (DataUrlHandler.isDataUrl(currentUrl)) {
        BookSourceService.handleDataUrl(currentUrl);
      }
      let hasMore: boolean = true;
      const visitedUrls = new Set<string>();
      const maxPages = 20;

      while (hasMore && !visitedUrls.has(currentUrl) && visitedUrls.size < maxPages) {
        visitedUrls.add(currentUrl);

        // 防止循环到下一章
        if (nextChapterUrl && currentUrl === nextChapterUrl) break;

        // data: URL 不需要 HTTP 请求，但要把 base64 内容作为 result 传给规则
        let body: string;
        if (DataUrlHandler.isDataUrl(currentUrl)) {
          BookSourceService.handleDataUrl(currentUrl);
          const base64Idx = currentUrl.indexOf('base64,');
          if (base64Idx >= 0) {
            const afterBase64 = currentUrl.substring(base64Idx + 7);
            const lastComma = afterBase64.lastIndexOf(',{');
            body = lastComma > 0 ? afterBase64.substring(0, lastComma) : afterBase64;
          } else {
            body = '';
          }
        } else {
          body = await BookSourceService.fetchWithSource(currentUrl, source);
        }
        const ctx = new AnalyzeContext(currentUrl);
        ctx.jsLib = source.jsLib || '';
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

      // title 规则：从内容页提取章节标题（部分书源标题只在正文页中）
      // 返回格式：title\ncontent
      if (rule.title && result) {
        try {
          // 用第一页的 body 提取标题
          const firstPageCtx = new AnalyzeContext(chapterUrl);
          firstPageCtx.jsLib = source.jsLib || '';
          firstPageCtx.book = { origin: source.bookSourceUrl, bookUrl: chapterUrl, name: '' } as BookContext;
          // 需要重新解析第一页（因为 analyzer 已经迭代完了）
          // 简化处理：从 result 中尝试提取标题（如果有 HTML 结构）
          const titleAnalyzer = new AnalyzeRule(result, firstPageCtx);
          const extractedTitle = await titleAnalyzer.getString(rule.title);
          if (extractedTitle) {
            result = extractedTitle + '\n' + result;
          }
        } catch (e) {
          console.warn(`[${TAG}] title rule error: ${e}`);
        }
      }

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
    if (BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) {
      return BuiltInDispatcher.getExploreBooks(source);
    }
    try {
      if (!source.exploreUrl || !source.ruleExplore) return [];

      const analyzeUrl = new AnalyzeUrl(source.exploreUrl, {
        page: 1, baseUrl: source.bookSourceUrl,
      }, source.header);
      const analyzed = await analyzeUrl.getUrl();
      const body = await BookSourceService.fetch(analyzed);

      const rule = source.ruleExplore;
      const ctx = new AnalyzeContext(analyzed.url);
      ctx.jsLib = source.jsLib || '';
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
        const updateTime = rule.updateTime ? await a.getString(rule.updateTime) || '' : '';
        const wordCount = rule.wordCount ? await a.getString(rule.wordCount) || '' : '';

        results.push({
          name, author,
          coverUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, coverUrlRaw),
          bookUrl: AnalyzeUrl.resolveUrl(source.bookSourceUrl, bookUrlRaw),
          intro, kind, lastChapter, wordCount,
          sourceName: source.bookSourceName,
          sourceUrl: source.bookSourceUrl,
        });
      }
      return results;
    } catch (e) {
      console.error(`[${TAG}] getExploreBooks error: ${e}`);
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

  /** 内置源首页推荐板块（一个源多个板块） */
  static async getHomeBlocks(source: BookSource): Promise<HomeBlockSection[]> {
    if (!BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl)) return [];
    return BuiltInDispatcher.getHomeBlocks(source);
  }

  /**
   * 聚合所有启用源的首页推荐板块：
   * - 内置源：每个源可能产出多个板块（精品多人 / 最新作品 / 热播 ...）
   * - 订阅源：每个源用 getExploreBooks 取前 N 本，包成一个"发现"板块
   * 顺序：保持 SourceDataService.getSources() 的原顺序（用户订阅在前、内置在后）。
   * 单源 8s 超时，超时/失败该源直接跳过，不影响其他源。
   */
  static async getAllHomeBlocks(): Promise<HomeBlockSection[]> {
    const all: HomeBlockSection[] = [];
    await BookSourceService.streamAllHomeBlocks((blocks) => {
      for (const b of blocks) all.push(b);
    });
    return all;
  }

  /**
   * 渐进式聚合所有启用源的首页推荐板块。每完成一个源立即回调，便于 UI 边来边渲染。
   * 单源 8s 超时，超时/失败该源直接跳过。
   * 内置源优先（天下书音等先跑），订阅源限制并发数避免把网络打饱和。
   */
  static async streamAllHomeBlocks(onSource: (blocks: HomeBlockSection[], source: BookSource) => void): Promise<void> {
    const sources = await SourceDataService.getSources();
    const enabled = sources.filter((s: BookSource) => s.enabled !== false);
    console.info(`[${TAG}] streamAllHomeBlocks: total=${sources.length} enabled=${enabled.length}`);
    const PER_SOURCE_TIMEOUT_MS = 8000;
    const MAX_CONCURRENCY = 6;

    // 内置源优先（一定有 home blocks），订阅源在后（多数没 ruleExplore，会立刻返回空）
    const ordered: BookSource[] = [];
    for (const s of enabled) {
      if (BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) ordered.push(s);
    }
    for (const s of enabled) {
      if (!BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) ordered.push(s);
    }

    const runOne = async (source: BookSource): Promise<void> => {
      const work: Promise<HomeBlockSection[]> = (async () => {
        const isBuiltin = BuiltInSourceRegistry.isBuiltIn(source.bookSourceUrl);
        if (isBuiltin) {
          const r = await BookSourceService.getHomeBlocks(source);
          console.info(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} -> ${r.length} sections`);
          return r;
        }
        if (!source.exploreUrl || source.exploreUrl.length === 0 || !source.ruleExplore) {
          return [] as HomeBlockSection[];
        }
        const books = await BookSourceService.getExploreBooks(source);
        if (books.length === 0) return [] as HomeBlockSection[];
        const limit = Math.min(20, books.length);
        const section = new HomeBlockImpl(
          '发现',
          books.slice(0, limit),
          '',
          'horizontal',
          source.bookSourceName,
          source.bookSourceUrl,
        );
        return [section];
      })();

      const timeout = new Promise<HomeBlockSection[]>((resolve) => {
        setTimeout(() => {
          console.warn(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} TIMEOUT`);
          resolve([] as HomeBlockSection[]);
        }, PER_SOURCE_TIMEOUT_MS);
      });

      try {
        const blocks = await Promise.race([work, timeout]);
        if (blocks.length > 0) onSource(blocks, source);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`[${TAG}] streamAllHomeBlocks: ${source.bookSourceName} error ${msg}`);
      }
    };

    // 简单的固定并发池：每个 worker 串行从队列取任务
    let cursor = 0;
    const workers: Promise<void>[] = [];
    for (let i = 0; i < MAX_CONCURRENCY; i++) {
      workers.push((async () => {
        while (cursor < ordered.length) {
          const idx = cursor++;
          await runOne(ordered[idx]);
        }
      })());
    }
    await Promise.all(workers);
    console.info(`[${TAG}] streamAllHomeBlocks: all done`);
  }

  // ──────────────────── HTTP 工具 ────────────────────

  private static async fetch(analyzed: AnalyzedUrl): Promise<string> {
    if (analyzed.method === 'POST') {
      return HttpClient.post(analyzed.url, analyzed.body || '', analyzed.headers, analyzed.charset);
    }
    return HttpClient.get(analyzed.url, analyzed.headers, analyzed.charset);
  }

  /**
   * 判断是否需要执行 loginCheckJs
   * 仅当响应是有效 JSON 且包含实际数据时才跳过
   * "data":null 等空数据响应仍需 loginCheck 处理
   */
  private static needsLoginCheck(body: string): boolean {
    const trimmed = body.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        const parsed: Object = JSON.parse(trimmed);
        // JSON 数组且有数据 → 跳过
        if (Array.isArray(parsed) && parsed.length > 0) return false;
        // JSON 对象：检查 data 字段是否有实际数据
        if (typeof parsed === 'object' && parsed !== null) {
          const data = (parsed as Record<string, Object>)['data'];
          if (data !== null && data !== undefined) return false;
        }
        // data 为 null 或空 → 仍需 loginCheck
        return true;
      } catch {
        return true;
      }
    }
    return true;
  }

  /**
   * 执行 loginCheckJs（搜索前验证）
   * 原生实现 Legado loginCheckJs 的常见模式，不依赖 JS 引擎
   * 支持：HTML 跳转页面处理、"data":null 时从 loginCheckJs 提取 POST 配置建立会话
   */
  private static async executeLoginCheck(source: BookSource, body: string, keyword: string): Promise<string> {
    try {
      if (!source.loginCheckJs) return body;
      console.info(`[${TAG}] executeLoginCheck: ${source.bookSourceName}`);

      // 模式 1：HTML 跳转页面（含"即将跳转"）
      if (body.includes('即将跳转')) {
        console.info(`[${TAG}] loginCheck: detected redirect page, following link`);
        try {
          const hrefMatch = body.match(/class="notfoud-container"[^>]*>[\s\S]*?<a[^>]+href="([^"]+)"/);
          if (hrefMatch) {
            const redirectUrl = AnalyzeUrl.resolveUrl(source.bookSourceUrl, hrefMatch[1]);
            const newBody = await HttpClient.get(redirectUrl);
            return newBody;
          }
        } catch (e) {
          console.warn(`[${TAG}] loginCheck redirect failed: ${e}`);
        }
      }

      // 模式 2："data":null → 从 loginCheckJs 提取 POST URL 建立搜索会话
      if (body.includes('"data":null')) {
        const postInfo = BookSourceService.extractPostFromLoginCheckJs(source.loginCheckJs, source.bookSourceUrl, keyword);
        if (postInfo) {
          console.info(`[${TAG}] loginCheck: data is null, POST ${postInfo.url} to establish session`);
          try {
            const headers: Record<string, string> = {
              'Content-Type': 'application/x-www-form-urlencoded',
            };
            if (source.header) {
              try {
                const h = JSON.parse(source.header) as Record<string, string>;
                if (h['User-Agent']) headers['User-Agent'] = h['User-Agent'];
                if (h['Referer']) headers['Referer'] = h['Referer'];
              } catch { /* ignore */ }
            }
            await HttpClient.post(postInfo.url, postInfo.body, headers);
            return '__RETRY_SEARCH__';
          } catch (e) {
            console.warn(`[${TAG}] loginCheck POST session failed: ${e}`);
          }
        }
      }

      return body;
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      console.error(`[${TAG}] executeLoginCheck error: ${msg}`);
      return body;
    }
  }

  /**
   * 从 loginCheckJs 代码中提取 POST URL 和 body 参数（通用）
   * 支持 Legado 常见模式：source.key + `/path,{"body":"searchword=${key}","method":"POST"}`
   */
  private static extractPostFromLoginCheckJs(js: string, baseUrl: string, keyword: string): PostInfo | null {
    // 匹配 URL 路径（可能在模板字面量或字符串拼接中）
    const urlMatch = js.match(/["'`]([^"'`]*?\.html)/);
    if (!urlMatch) return null;
    const path = urlMatch[1];
    const fullUrl = AnalyzeUrl.resolveUrl(baseUrl, path);

    // 匹配 body 参数（如 "searchword=${key}" 或 "searchword=xxx"）
    const bodyMatch = js.match(/"body"\s*:\s*"([^"]+)"/);
    let postBody = '';
    if (bodyMatch) {
      postBody = bodyMatch[1]
        .replace(/\$\{key\}/g, encodeURIComponent(keyword))
        .replace(/\$\{searchKey\}/g, encodeURIComponent(keyword));
    } else {
      postBody = `searchword=${encodeURIComponent(keyword)}`;
    }

    const result: PostInfo = { url: fullUrl, body: postBody };
    return result;
  }

  private static async fetchWithSource(url: string, source: BookSource): Promise<string> {
    // 并发限速（Legado concurrentRate 对齐）
    if (source.concurrentRate) {
      const limiter = getRateLimiter(source.concurrentRate);
      if (limiter) await limiter.acquire();
    }
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
