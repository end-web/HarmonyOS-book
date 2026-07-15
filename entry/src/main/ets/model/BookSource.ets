/**
 * 听书源与页面之间的最小数据契约。
 *
 * 在线内容只由内置音频源提供，因此这里不再携带 Legado 规则、登录或订阅字段。
 */
export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
}

export interface SearchResult {
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  lastChapter: string;
  wordCount?: string;
  sourceName: string;
  sourceUrl: string;
  variables?: Record<string, string>;
}

export interface TocItem {
  name: string;
  url: string;
  isVip?: boolean;
  isPay?: boolean;
  isVolume?: boolean;
  updateTime?: string;
  duration?: number;
}

export interface BookInfo {
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  kind: string;
  wordCount: string;
  lastChapter: string;
  tocUrl: string;
  variables?: Record<string, string>;
}

export interface HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;
}
