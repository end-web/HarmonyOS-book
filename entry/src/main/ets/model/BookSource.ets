export interface SearchRule {
  bookList: string;
  name: string;
  author: string;
  coverUrl: string;
  bookUrl: string;
  intro: string;
  kind: string;
  lastChapter: string;
}

export interface TocRule {
  chapterList: string;
  chapterName: string;
  chapterUrl: string;
}

export interface ContentRule {
  content: string;
  audioUrl: string;
}

export interface BookInfoRule {
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  tocUrl: string;
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
}

export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: number;
  bookSourceGroup: string;
  enabled: boolean;
  enabledExplore: boolean;
  searchUrl: string;
  exploreUrl: string;
  header: string;
  loginUrl: string;
  respondTime: number;
  customOrder: number;
  weight: number;
  ruleSearch: SearchRule;
  ruleToc: TocRule;
  ruleContent: ContentRule;
  ruleBookInfo: BookInfoRule;
  ruleExplore: ExploreRule;
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
  sourceName: string;
  sourceUrl: string;
}

export interface TocItem {
  name: string;
  url: string;
}
