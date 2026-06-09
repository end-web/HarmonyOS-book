/**
 * 书源调试工具 - 用于诊断书源解析问题
 */

import { BookSource, SearchResult, TocItem } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { HttpClient } from '../service/http/HttpClient';
import { AnalyzeRule, AnalyzeContext } from '../service/rule/AnalyzeRule';
import { AnalyzeUrl } from '../service/rule/AnalyzeUrl';

export interface DebugStep {
  step: string;
  success: boolean;
  data?: string;
  error?: string;
  time?: number;
}

export class SourceDebugger {
  /**
   * 调试单个书源的搜索功能
   */
  static async debugSearch(source: BookSource, keyword: string): Promise<DebugStep[]> {
    const steps: DebugStep[] = [];
    const startTime = Date.now();

    try {
      // Step 1: 检查书源配置
      steps.push({
        step: '1. 检查书源配置',
        success: !!source.searchUrl && !!source.ruleSearch,
        data: `searchUrl: ${source.searchUrl}\nruleSearch.bookList: ${source.ruleSearch?.bookList}`,
      });

      if (!source.searchUrl || !source.ruleSearch) {
        return steps;
      }

      // Step 2: 解析搜索 URL
      let searchUrl = '';
      try {
        const analyzeUrl = new AnalyzeUrl(source.searchUrl, {
          key: keyword,
          page: 1,
          baseUrl: source.bookSourceUrl,
        }, source.header);
        const analyzed = await analyzeUrl.getUrl();
        searchUrl = analyzed.url;
        steps.push({
          step: '2. 解析搜索URL',
          success: true,
          data: `URL: ${searchUrl}\nMethod: ${analyzed.method}\nCharset: ${analyzed.charset || 'utf-8'}`,
          time: Date.now() - startTime,
        });
      } catch (e) {
        steps.push({
          step: '2. 解析搜索URL',
          success: false,
          error: e instanceof Error ? e.message : String(e),
          time: Date.now() - startTime,
        });
        return steps;
      }

      // Step 3: 发送 HTTP 请求
      let responseBody = '';
      try {
        const analyzeUrl = new AnalyzeUrl(source.searchUrl, {
          key: keyword,
          page: 1,
          baseUrl: source.bookSourceUrl,
        }, source.header);
        const analyzed = await analyzeUrl.getUrl();

        if (analyzed.method === 'POST') {
          responseBody = await HttpClient.post(analyzed.url, analyzed.body || '', analyzed.headers, analyzed.charset);
        } else {
          responseBody = await HttpClient.get(analyzed.url, analyzed.headers, analyzed.charset);
        }

        steps.push({
          step: '3. 发送HTTP请求',
          success: true,
          data: `响应长度: ${responseBody.length} 字符\n前200字符: ${responseBody.substring(0, 200)}`,
          time: Date.now() - startTime,
        });
      } catch (e) {
        steps.push({
          step: '3. 发送HTTP请求',
          success: false,
          error: e instanceof Error ? e.message : String(e),
          time: Date.now() - startTime,
        });
        return steps;
      }

      // Step 4: 解析书籍列表
      let items: Object[] = [];
      try {
        const ctx = new AnalyzeContext(searchUrl);
        const analyzer = new AnalyzeRule(responseBody, ctx);
        items = await analyzer.getElements(source.ruleSearch.bookList);
        steps.push({
          step: '4. 解析书籍列表',
          success: items.length > 0,
          data: `规则: ${source.ruleSearch.bookList}\n找到 ${items.length} 个结果`,
          time: Date.now() - startTime,
        });
      } catch (e) {
        steps.push({
          step: '4. 解析书籍列表',
          success: false,
          error: e instanceof Error ? e.message : String(e),
          time: Date.now() - startTime,
        });
        return steps;
      }

      // Step 5: 解析第一本书的详细信息
      if (items.length > 0) {
        try {
          const item = items[0];
          const itemCtx = new AnalyzeContext(searchUrl);
          const a = new AnalyzeRule(item, itemCtx);

          const name = await a.getString(source.ruleSearch.name) || '';
          const author = await a.getString(source.ruleSearch.author) || '';
          const bookUrl = await a.getString(source.ruleSearch.bookUrl) || '';

          steps.push({
            step: '5. 解析第一本书',
            success: !!name,
            data: `书名: ${name}\n作者: ${author}\n链接: ${bookUrl}`,
            time: Date.now() - startTime,
          });
        } catch (e) {
          steps.push({
            step: '5. 解析第一本书',
            success: false,
            error: e instanceof Error ? e.message : String(e),
            time: Date.now() - startTime,
          });
        }
      }

      return steps;
    } catch (e) {
      steps.push({
        step: '未知错误',
        success: false,
        error: e instanceof Error ? e.message : String(e),
        time: Date.now() - startTime,
      });
      return steps;
    }
  }

  /**
   * 测试所有已启用的书源
   */
  static async testAllSources(keyword: string): Promise<Map<string, DebugStep[]>> {
    const results = new Map<string, DebugStep[]>();

    try {
      const sources = await SourceDataService.getSources();
      const enabledSources = sources.filter(s => s.enabled !== false);

      for (const source of enabledSources) {
        const steps = await SourceDebugger.debugSearch(source, keyword);
        results.set(source.bookSourceName, steps);
      }
    } catch (e) {
      console.error('testAllSources error:', e);
    }

    return results;
  }

  /**
   * 调试搜索 → 详情 → 目录 → 取第一章音频 URL 全链路。
   * 用于诊断"安卓书源解到章节但播不出"这一类问题。
   */
  static async debugFullChain(source: BookSource, keyword: string): Promise<DebugStep[]> {
    const steps: DebugStep[] = [];
    const t0 = Date.now();

    try {
      // 1. 搜索
      let firstResult: SearchResult | null = null;
      try {
        const list = await BookSourceService.searchBooks(source, keyword, 1);
        firstResult = list.length > 0 ? list[0] : null;
        steps.push({
          step: '1. 搜索',
          success: !!firstResult,
          data: firstResult
            ? `找到 ${list.length} 本，取第一本：\n  书名: ${firstResult.name}\n  作者: ${firstResult.author}\n  bookUrl: ${firstResult.bookUrl}`
            : '搜索结果为空',
          time: Date.now() - t0,
        });
      } catch (e) {
        steps.push({ step: '1. 搜索', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t0 });
        return steps;
      }
      if (!firstResult) return steps;

      // 2. 详情（取 tocUrl）
      const t1 = Date.now();
      let tocUrl = firstResult.bookUrl;
      try {
        const info = await BookSourceService.getBookInfo(source, firstResult.bookUrl, firstResult.variables);
        if (info && info.tocUrl) tocUrl = info.tocUrl;
        steps.push({
          step: '2. 详情',
          success: !!info,
          data: info
            ? `name: ${info.name}\n  author: ${info.author}\n  tocUrl: ${info.tocUrl}\n  intro: ${(info.intro || '').substring(0, 100)}`
            : '详情返回 null',
          time: Date.now() - t1,
        });
      } catch (e) {
        steps.push({ step: '2. 详情', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t1 });
      }

      // 3. 目录
      const t2 = Date.now();
      let firstChapter: TocItem | null = null;
      try {
        const toc = await BookSourceService.getBookToc(source, tocUrl, firstResult.variables, firstResult.name);
        firstChapter = toc.length > 0 ? toc[0] : null;
        steps.push({
          step: '3. 目录',
          success: toc.length > 0,
          data: toc.length > 0
            ? `共 ${toc.length} 章，前 3 章：\n  ${toc.slice(0, 3).map((c, i) => `${i + 1}. ${c.name} → ${c.url}`).join('\n  ')}`
            : '目录为空',
          time: Date.now() - t2,
        });
      } catch (e) {
        steps.push({ step: '3. 目录', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t2 });
        return steps;
      }
      if (!firstChapter) return steps;

      // 4. 章节 → 音频 URL
      const t3 = Date.now();
      try {
        const audioUrl = await BookSourceService.getAudioUrl(source, firstChapter.url);
        // 剥掉 chapterUrl 的 ,{...} 配置后缀再比较，避免"去掉后缀≠原URL"的误判
        const cleanChapterUrl = AnalyzeUrl.splitUrlConfig(firstChapter.url).url;
        const isRealAudio = audioUrl.startsWith('http')
          && audioUrl !== cleanChapterUrl
          && !/text\/html/i.test(audioUrl)
          && (audioUrl.match(/\.(mp3|m4a|ogg|aac|wav|flac|m3u8)/) !== null
            || !audioUrl.includes(cleanChapterUrl.split('/').slice(0, 3).join('/')));
        steps.push({
          step: '4. 章节→音频URL',
          success: isRealAudio,
          data: `chapterUrl: ${firstChapter.url}\n  audioUrl: ${audioUrl}\n  ${isRealAudio
            ? '（与 chapterUrl 不同，看起来是真实音频直链）'
            : '⚠ 等于 chapterUrl 或为空，规则未提取出新 URL（若书源用 WebView 嗅探，调试时可能还未等到嗅探结果）'}`,
          time: Date.now() - t3,
        });

        // 5. 音频可达性 HEAD
        if (isRealAudio) {
          const t4 = Date.now();
          try {
            const headers: Record<string, string> = {};
            if (source.header) {
              try {
                const h = JSON.parse(source.header) as Record<string, string>;
                for (const k of Object.keys(h)) headers[k] = String(h[k]);
              } catch (_e) { /* ignore */ }
            }
            // 用 GET 但 Range: bytes=0-0 比 HEAD 更稳（部分 CDN 不支持 HEAD）
            headers['Range'] = 'bytes=0-0';
            const res = await HttpClient.request(audioUrl, { method: 'GET', headers });
            const ok = res.statusCode >= 200 && res.statusCode < 400;
            const ctype = (res.headers['content-type'] || res.headers['Content-Type'] || '') as string;
            const clen = (res.headers['content-length'] || res.headers['Content-Length'] || '') as string;
            const isAudioCt = ctype.startsWith('audio/') || /(mp3|m4a|aac|mpeg)/i.test(ctype);
            steps.push({
              step: '5. 音频URL可达性',
              success: ok && isAudioCt,
              data: `HTTP ${res.statusCode}\n  Content-Type: ${ctype}\n  Content-Length: ${clen}\n  ${ok
                ? (isAudioCt ? '看起来是音频流，可播' : '⚠ 200 但 Content-Type 不是音频，可能被反爬转成 HTML')
                : '⚠ 非 2xx/3xx，目标服务器拒绝（多半防盗链：缺 Referer/Cookie/UA）'}`,
              time: Date.now() - t4,
            });
          } catch (e) {
            steps.push({
              step: '5. 音频URL可达性',
              success: false,
              error: SourceDebugger.errMsg(e),
              time: Date.now() - t4,
            });
          }
        }
      } catch (e) {
        steps.push({ step: '4. 章节→音频URL', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t3 });
      }

      return steps;
    } catch (e) {
      steps.push({ step: '未知错误', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t0 });
      return steps;
    }
  }

  /**
   * 直接给定章节 URL 调试音频提取（跳过搜索/详情/目录）。
   * 适用：用户已经在播放页看到具体章节但播不出。
   */
  static async debugAudio(source: BookSource, chapterUrl: string): Promise<DebugStep[]> {
    const steps: DebugStep[] = [];
    const t0 = Date.now();
    steps.push({
      step: '0. 输入',
      success: true,
      data: `书源: ${source.bookSourceName}\n  chapterUrl: ${chapterUrl}\n  contentRule.audioUrl: ${source.ruleContent?.audioUrl || '(空)'}\n  contentRule.content: ${source.ruleContent?.content || '(空)'}\n  contentRule.sourceRegex: ${source.ruleContent?.sourceRegex || '(空)'}\n  contentRule.webJs: ${source.ruleContent?.webJs ? '(存在)' : '(空)'}`,
    });

    try {
      const audioUrl = await BookSourceService.getAudioUrl(source, chapterUrl);
      const cleanInput = AnalyzeUrl.splitUrlConfig(chapterUrl).url;
      const isRealAudio = audioUrl.startsWith('http') && audioUrl !== cleanInput;
      steps.push({
        step: '1. getAudioUrl',
        success: isRealAudio,
        data: `audioUrl: ${audioUrl}\n  ${isRealAudio ? '✓ 与输入不同' : '⚠ 等于输入（去配置后缀后）或非 http，WebView 嗅探可能尚未完成'}`,
        time: Date.now() - t0,
      });

      if (isRealAudio) {
        const t1 = Date.now();
        const headers: Record<string, string> = {};
        if (source.header) {
          try {
            const h = JSON.parse(source.header) as Record<string, string>;
            for (const k of Object.keys(h)) headers[k] = String(h[k]);
          } catch (_e) { /* ignore */ }
        }
        headers['Range'] = 'bytes=0-0';
        try {
          const res = await HttpClient.request(audioUrl, { method: 'GET', headers });
          const ctype = (res.headers['content-type'] || res.headers['Content-Type'] || '') as string;
          const ok = res.statusCode >= 200 && res.statusCode < 400;
          steps.push({
            step: '2. HTTP HEAD',
            success: ok,
            data: `HTTP ${res.statusCode}\n  Content-Type: ${ctype}\n  Headers: ${JSON.stringify(headers)}`,
            time: Date.now() - t1,
          });
        } catch (e) {
          steps.push({ step: '2. HTTP HEAD', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t1 });
        }
      }
      return steps;
    } catch (e) {
      steps.push({ step: '调用 getAudioUrl 失败', success: false, error: SourceDebugger.errMsg(e), time: Date.now() - t0 });
      return steps;
    }
  }

  private static errMsg(e: Object | Error): string {
    if (e instanceof Error) return e.message;
    return String(e);
  }

  /**
   * 格式化调试结果为可读文本
   */
  static formatDebugSteps(steps: DebugStep[]): string {
    let output = '';
    for (const step of steps) {
      const icon = step.success ? '✓' : '✗';
      const time = step.time !== undefined ? ` (${step.time}ms)` : '';
      output += `${icon} ${step.step}${time}\n`;
      if (step.data) {
        output += `  ${step.data.replace(/\n/g, '\n  ')}\n`;
      }
      if (step.error) {
        output += `  错误: ${step.error}\n`;
      }
      output += '\n';
    }
    return output;
  }
}
