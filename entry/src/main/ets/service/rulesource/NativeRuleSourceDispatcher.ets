import { BookInfo, BookSource, SearchResult, TocItem } from '../../model/BookSource';
import { LocalRuleContentResult } from './LocalRuleRuntimeTypes';
import { GuangYuSourceAdapter } from './guangyu/GuangYuSourceAdapter';
import { GuangYuSourceIdentity } from './guangyu/GuangYuSourceIdentity';
import { ShuShanSourceAdapter } from './shushan/ShuShanSourceAdapter';
import { ShuShanSourceIdentity } from './shushan/ShuShanSourceIdentity';

/** 用户导入但由受控原生协议处理的聚合源统一分发入口。 */
export class NativeRuleSourceDispatcher {
  static isSource(source: BookSource): boolean {
    return NativeRuleSourceDispatcher.isSourceUrl(source.bookSourceUrl);
  }

  static isSourceUrl(sourceUrl: string | undefined): boolean {
    return GuangYuSourceIdentity.isSourceUrl(sourceUrl) ||
      ShuShanSourceIdentity.isSourceUrl(sourceUrl);
  }

  static usesSingleContentHealthCheck(sourceUrl: string): boolean {
    return GuangYuSourceIdentity.isSourceUrl(sourceUrl);
  }

  static isNonRetryableHealthError(sourceUrl: string, error: Object): boolean {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuSourceAdapter.isNonRetryableHealthError(error);
    }
    return false;
  }

  static async search(source: BookSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    if (GuangYuSourceIdentity.isSource(source)) {
      return GuangYuSourceAdapter.search(source, keyword, page);
    }
    if (ShuShanSourceIdentity.isSource(source)) {
      return ShuShanSourceAdapter.search(source, keyword, page);
    }
    return [];
  }

  static async searchForHealthCheck(source: BookSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    if (GuangYuSourceIdentity.isSource(source)) {
      return GuangYuSourceAdapter.searchForHealthCheck(source, keyword, page);
    }
    if (ShuShanSourceIdentity.isSource(source)) {
      return ShuShanSourceAdapter.searchForHealthCheck(source, keyword, page);
    }
    return [];
  }

  static async getBookInfo(sourceUrl: string, bookUrl: string): Promise<BookInfo | null> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuSourceAdapter.getBookInfo(bookUrl);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      return ShuShanSourceAdapter.getBookInfo(bookUrl);
    }
    return null;
  }

  static async getBookToc(sourceUrl: string, tocUrl: string): Promise<TocItem[]> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuSourceAdapter.getBookToc(tocUrl);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      return ShuShanSourceAdapter.getBookToc(tocUrl);
    }
    return [];
  }

  static async resolveContent(sourceUrl: string,
    chapterUrl: string): Promise<LocalRuleContentResult> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuSourceAdapter.resolveContent(chapterUrl);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      return ShuShanSourceAdapter.resolveContent(chapterUrl);
    }
    throw new Error('当前书源没有原生内容适配器');
  }

  static async getAudioUrl(sourceUrl: string, chapterUrl: string): Promise<string> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuSourceAdapter.getAudioUrl(chapterUrl);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      return ShuShanSourceAdapter.getAudioUrl(chapterUrl);
    }
    return chapterUrl;
  }
}
