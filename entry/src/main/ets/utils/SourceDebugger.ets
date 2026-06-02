/**
 * 书源调试工具 - 用于诊断书源解析问题
 */

import { BookSource, SearchResult } from '../model/BookSource';
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
