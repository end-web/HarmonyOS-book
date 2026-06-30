export interface SearchRule {
  bookList: string;
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  lastChapter: string;
  wordCount?: string;
  checkKeyWord?: string;
  updateTime?: string;
}

export interface ReviewRule {
  reviewList?: string;
  avatar?: string;
  name?: string;
  time?: string;
  title?: string;
  content?: string;
  reviewUrl?: string;
}

export interface TocRule {
  chapterList: string;
  chapterName: string;
  chapterUrl: string;
  nextTocUrl?: string;
  isVip?: string;
  isPay?: string;
  isVolume?: string;
  updateTime?: string;
  duration?: string;
  preUpdateJs?: string;
  formatJs?: string;
}

export interface ContentRule {
  content: string;
  title?: string;
  audioUrl?: string;
  nextContentUrl?: string;
  replaceRegex?: string;
  sourceRegex?: string;
  webJs?: string;
}

export interface BookInfoRule {
  init?: string;
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  kind?: string;
  wordCount?: string;
  lastChapter?: string;
  updateTime?: string;
  tocUrl: string;
  canReName?: string;
  downloadUrls?: string;
}

export interface ExploreRule {
  bookList: string;
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  lastChapter: string;
  updateTime?: string;
  wordCount?: string;
}

export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: number;
  bookSourceGroup: string;
  bookSourceComment?: string;
  enabled: boolean;
  enabledExplore: boolean;
  enabledCookieJar?: boolean;
  searchUrl: string;
  exploreUrl: string;
  header: string;
  loginUrl?: string;
  loginUi?: string;
  loginCheckJs?: string;
  bookUrlPattern?: string;
  variableComment?: string;
  jsLib?: string;
  customButton?: boolean;
  eventListener?: boolean;
  exploreScreen?: string;
  coverDecodeJs?: string;
  respondTime: number;
  customOrder: number;
  weight: number;
  concurrentRate?: string;
  ruleSearch: SearchRule;
  ruleToc: TocRule;
  ruleContent: ContentRule;
  ruleBookInfo: BookInfoRule;
  ruleExplore: ExploreRule;
  ruleReview?: ReviewRule;
  lastUpdateTime?: number;
  subscriptionUrl?: string;
}

export interface SourceSubscription {
  url: string;
  name: string;
  count: number;
  lastUpdate: number;
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
