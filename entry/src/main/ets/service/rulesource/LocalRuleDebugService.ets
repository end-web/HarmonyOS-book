import { BookInfo, SearchResult, TocItem } from '../../model/BookSource';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleDispatcher } from './LocalRuleDispatcher';
import { NativeRuleSourceDispatcher } from './NativeRuleSourceDispatcher';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';
import { LocalRulePanelService } from './LocalRulePanelService';

export class LocalRuleDebugResult {
  success: boolean = false;
  data: string = '';
  error: string = '';
}

export class LocalRuleDebugService {
  static async run(source: LocalRuleSource, stage: string, keyword: string, address: string,
    variables: Record<string, string>): Promise<LocalRuleDebugResult> {
    const result = new LocalRuleDebugResult();
    try {
      if (stage === 'explore') {
        variables['__debugStage'] = 'explore';
        const panel = await LocalRulePanelService.load(source, false, variables);
        const category = panel.entries.find(entry => entry.url.length > 0);
        if (category === undefined) throw new Error('发现没有可请求的分类');
        const explored = await LocalRuleDispatcher.explore(source, category.url, 1, variables);
        if (explored.books.length === 0) throw new Error('发现请求完成，但未提取到书籍');
        result.data = LocalRuleDebugService.searchPreview(explored.books);
      } else if (stage === 'search' || stage === 'full') {
        const books = await LocalRuleDebugService.search(source, keyword, variables);
        result.data = LocalRuleDebugService.searchPreview(books);
        if (stage === 'full') {
          const book = books[0];
          LocalRuleDebugService.merge(variables, book.variables);
          const info = await LocalRuleDebugService.detail(source, book.bookUrl, variables);
          const chapters = await LocalRuleDebugService.toc(source, info.tocUrl || book.bookUrl, variables);
          const chapter = chapters.find(item => !item.isVolume && item.url.length > 0);
          if (chapter === undefined) throw new Error('目录没有可读取的章节');
          LocalRuleDebugService.merge(variables, chapter.variables);
          result.data = await LocalRuleDebugService.content(source, chapter.url, variables,
            book.contentType === undefined ? source.isAudio() : book.contentType === 'audio');
        }
      } else {
        if (!address.trim()) throw new Error('请输入测试地址');
        if (stage === 'content') {
          result.data = await LocalRuleDebugService.content(source, address, variables, source.isAudio());
        } else {
          const info = await LocalRuleDebugService.detail(source, address, variables);
          const preview: Record<string, string> = {
            'name': info.name, 'author': info.author, 'intro': info.intro, 'tocUrl': info.tocUrl
          };
          result.data = JSON.stringify(preview, null, 2);
          if (stage === 'toc') {
            const chapters = await LocalRuleDebugService.toc(source, info.tocUrl || address, variables);
            const previews: Record<string, string>[] = [];
            for (const item of chapters.slice(0, 10)) {
              previews.push({ 'name': item.name, 'url': item.url });
            }
            result.data = JSON.stringify(previews, null, 2);
          }
        }
      }
      LocalRuleDiagnostics.check(variables);
      result.success = true;
      LocalRuleDiagnostics.record(variables, 'success', '调试完成');
    } catch (error) {
      result.error = error instanceof Error ? error.message : String(error);
      LocalRuleDiagnostics.record(variables, 'error', '调试失败', result.error);
    }
    result.data = LocalRuleDiagnostics.redact(result.data).substring(0, 16000);
    result.error = LocalRuleDiagnostics.redact(result.error);
    return result;
  }

  private static async search(source: LocalRuleSource, keyword: string,
    variables: Record<string, string>): Promise<SearchResult[]> {
    if (!keyword.trim()) throw new Error('请输入搜索关键词');
    variables['__debugStage'] = 'search';
    LocalRuleDiagnostics.check(variables);
    const books = NativeRuleSourceDispatcher.isSource(source)
      ? await NativeRuleSourceDispatcher.searchForHealthCheck(source, keyword)
      : await LocalRuleDispatcher.searchForHealthCheck(source, keyword, 1, variables);
    if (books.length === 0) throw new Error('搜索请求完成，但未提取到书籍');
    LocalRuleDiagnostics.record(variables, 'success', `搜索解析出 ${books.length} 本书`);
    return books;
  }

  private static async detail(source: LocalRuleSource, address: string,
    variables: Record<string, string>): Promise<BookInfo> {
    variables['__debugStage'] = 'detail';
    LocalRuleDiagnostics.check(variables);
    const info = NativeRuleSourceDispatcher.isSource(source)
      ? await NativeRuleSourceDispatcher.getBookInfo(source.bookSourceUrl, address)
      : await LocalRuleDispatcher.getBookInfo(source, address, variables);
    if (info === null || (!info.name && !info.tocUrl)) throw new Error('详情没有解析出有效数据');
    LocalRuleDebugService.merge(variables, info.variables);
    LocalRuleDiagnostics.record(variables, 'success', '详情解析完成', info.name);
    return info;
  }

  private static async toc(source: LocalRuleSource, address: string,
    variables: Record<string, string>): Promise<TocItem[]> {
    variables['__debugStage'] = 'toc';
    LocalRuleDiagnostics.check(variables);
    const chapters = NativeRuleSourceDispatcher.isSource(source)
      ? await NativeRuleSourceDispatcher.getBookToc(source.bookSourceUrl, address)
      : await LocalRuleDispatcher.getBookToc(source, address, variables);
    if (chapters.length === 0) throw new Error('目录没有解析出章节');
    LocalRuleDiagnostics.record(variables, 'success', `目录解析出 ${chapters.length} 章`);
    return chapters;
  }

  private static async content(source: LocalRuleSource, address: string,
    variables: Record<string, string>, audio: boolean): Promise<string> {
    variables['__debugStage'] = 'content';
    LocalRuleDiagnostics.check(variables);
    const content = NativeRuleSourceDispatcher.isSource(source)
      ? await NativeRuleSourceDispatcher.resolveContent(source.bookSourceUrl, address)
      : await LocalRuleDispatcher.resolveContent(source, address, variables);
    if (audio ? !content.audioUrl : !content.content.trim()) {
      throw new Error(audio ? '未解析出音频地址' : '未解析出正文');
    }
    LocalRuleDiagnostics.record(variables, 'success', audio ? '音频地址解析完成' :
      `正文解析完成，共 ${content.content.length} 字符`);
    const preview: Record<string, string> = { 'title': content.title,
      'content': content.content.substring(0, 8000), 'audioUrl': content.audioUrl };
    return JSON.stringify(preview, null, 2);
  }

  private static merge(target: Record<string, string>, input: Record<string, string> | undefined): void {
    if (input === undefined) return;
    for (const key of Object.keys(input)) {
      if (key !== '__debugStage' && key !== '__traceId') target[key] = input[key];
    }
  }

  private static searchPreview(books: SearchResult[]): string {
    const previews: Record<string, string>[] = [];
    for (const book of books.slice(0, 10)) {
      previews.push({ 'name': book.name, 'author': book.author, 'bookUrl': book.bookUrl });
    }
    return JSON.stringify(previews, null, 2);
  }
}
