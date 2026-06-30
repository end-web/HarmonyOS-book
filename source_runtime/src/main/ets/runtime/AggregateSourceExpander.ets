import { BookInfoRule, BookSource, ContentRule, SearchRule, TocRule } from '../model/BookSource';
import { SourceFetchAdapter } from './SourceAdapters';

export class AggregateSourceExpander {
  static async expand(sources: BookSource[], fetcher: SourceFetchAdapter): Promise<BookSource[]> {
    const result: BookSource[] = [];
    for (const source of sources) {
      result.push(source);
      if (AggregateSourceExpander.isAggregateSource(source)) {
        try {
          const subSources = await AggregateSourceExpander.fetchSubSources(source, fetcher);
          result.push(...subSources);
        } catch {
          // 展开失败不影响原始书源导入。
        }
      }
    }
    return result;
  }

  private static isAggregateSource(source: BookSource): boolean {
    return source.bookSourceType === 0 && !!source.jsLib && source.jsLib.includes('getCloudSettings');
  }

  private static async fetchSubSources(parentSource: BookSource, fetcher: SourceFetchAdapter): Promise<BookSource[]> {
    const hosts = AggregateSourceExpander.extractHosts(parentSource.jsLib || '');
    if (hosts.length === 0) return [];
    const audioSourceNames = await AggregateSourceExpander.fetchAudioSourceNames(hosts, fetcher);
    if (audioSourceNames.length === 0) return [];
    const defaultHost = hosts[0];
    const subSources: BookSource[] = [];

    for (const sourceName of audioSourceNames) {
      subSources.push(AggregateSourceExpander.buildAudioSubSource(parentSource, sourceName, defaultHost));
    }
    return subSources;
  }

  private static extractHosts(jsLib: string): string[] {
    const hostsMatch = jsLib.match(/let\s+hosts\s*=\s*\[([\s\S]*?)\]/);
    if (!hostsMatch) return [];
    const hostLines = hostsMatch[1].split('\n');
    const hosts: string[] = [];
    for (const line of hostLines) {
      const match = line.match(/["'](https?:\/\/[^"']+)["']/);
      if (match && match[1]) hosts.push(match[1]);
    }
    return hosts;
  }

  private static async fetchAudioSourceNames(hosts: string[], fetcher: SourceFetchAdapter): Promise<string[]> {
    for (const host of hosts) {
      try {
        const configUrl = `${host}/static/source_config/config.json`;
        const configBody = await fetcher.fetchText(configUrl);
        const config = JSON.parse(configBody) as Record<string, Object>;
        const audioSources = config['听书'];
        if (Array.isArray(audioSources) && audioSources.length > 0) {
          return audioSources as string[];
        }
      } catch {
        continue;
      }
    }
    return [];
  }

  private static buildAudioSubSource(parentSource: BookSource, sourceName: string, defaultHost: string): BookSource {
    const encSrc = encodeURIComponent(sourceName);
    const directSearchUrl = `${defaultHost}/search?title={{key}}&tab=%E5%90%AC%E4%B9%A6&source=${encSrc}&page={{page}}&disabled_sources=0`;
    const subSource: BookSource = {
      bookSourceUrl: `聚合听书-${sourceName}-${defaultHost}`,
      bookSourceName: `${parentSource.bookSourceName}·${sourceName}`,
      bookSourceType: 1,
      bookSourceGroup: `聚合听书,${sourceName}`,
      bookSourceComment: `从 ${parentSource.bookSourceName} 提取的听书子源`,
      enabled: true,
      enabledExplore: false,
      enabledCookieJar: parentSource.enabledCookieJar,
      searchUrl: directSearchUrl,
      exploreUrl: '',
      header: parentSource.header,
      jsLib: '',
      respondTime: parentSource.respondTime,
      customOrder: parentSource.customOrder + 1,
      weight: parentSource.weight,
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
      ruleToc: {
        chapterList: '$.data[*]',
        chapterName: '$.title',
        chapterUrl: '$.content_url',
      } as TocRule,
      ruleContent: {
        content: '$.data.url',
      } as ContentRule,
      ruleExplore: {
        bookList: '',
        name: '',
        author: '',
        coverUrl: '',
        bookUrl: '',
        intro: '',
        kind: '',
        lastChapter: '',
      },
      subscriptionUrl: parentSource.subscriptionUrl,
    };
    return subSource;
  }
}
