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
}

export interface ContentRule {
  content: string;
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
}

export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: number; // 0=文本, 1=音频, 2=图片, 3=文件
  bookSourceGroup: string;
  bookSourceComment?: string;
  enabled: boolean;
  enabledExplore: boolean;
  searchUrl: string;
  exploreUrl: string;
  header: string;
  loginUrl?: string;
  loginUi?: string;
  loginCheckJs?: string;
  bookUrlPattern?: string;
  respondTime: number;
  customOrder: number;
  weight: number;
  concurrentRate?: string;
  ruleSearch: SearchRule;
  ruleToc: TocRule;
  ruleContent: ContentRule;
  ruleBookInfo: BookInfoRule;
  ruleExplore: ExploreRule;
  lastUpdateTime?: number;
  subscriptionUrl?: string; // 记录该书源来自哪个订阅源 URL
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

/**
 * 首页推荐板块（用于内置源在 HomePage 上展示"精品多人/最新作品/热播..."这类区块）
 * layout: 'grid'（带简介的大卡片）/ 'horizontal'（横向滚动小封面）
 */
export interface HomeBlockSection {
  title: string;
  books: SearchResult[];
  moreUrl: string;
  layout: string;
  sourceName: string;
  sourceUrl: string;
}
