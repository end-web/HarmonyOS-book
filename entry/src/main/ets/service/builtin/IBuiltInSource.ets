/**
 * 听友 FM 内置源数据类型。
 *
 * ArkTS 严格模式：使用 class 而非 interface 作为数据载体，便于 new 实例化避免 obj-literal 报错。
 */

export class BuiltInBook {
  coverUrl: string = '';
  bookUrl: string = '';
  title: string = '';
  author: string = '';
  artist: string = '';
  intro: string = '';
  status: string = '';
  completed: boolean = false;

  constructor(coverUrl: string, bookUrl: string, title: string, author: string, artist: string) {
    this.coverUrl = coverUrl;
    this.bookUrl = bookUrl;
    this.title = title;
    this.author = author;
    this.artist = artist;
  }

  static of(coverUrl: string, bookUrl: string, title: string, author: string, artist: string): BuiltInBook {
    return new BuiltInBook(coverUrl, bookUrl, title, author, artist);
  }
}
export class BuiltInEpisode {
  title: string;
  url: string;
  isFree: boolean;
  coverUrl: string = '';

  constructor(title: string, url: string, isFree: boolean = true) {
    this.title = title;
    this.url = url;
    this.isFree = isFree;
  }
}

export class BuiltInBookDetail {
  episodes: BuiltInEpisode[];
  intro: string;

  constructor(episodes: BuiltInEpisode[] = [], intro: string = '') {
    this.episodes = episodes;
    this.intro = intro;
  }
}

export class BuiltInSearchResult {
  books: BuiltInBook[];
  totalPage: number;

  constructor(books: BuiltInBook[] = [], totalPage: number = 1) {
    this.books = books;
    this.totalPage = totalPage;
  }
}

export class BuiltInCategoryTab {
  title: string;
  url: string;

  constructor(title: string, url: string) {
    this.title = title;
    this.url = url;
  }
}

export class BuiltInCategoryMenu {
  title: string;
  tabs: BuiltInCategoryTab[];

  constructor(title: string, tabs: BuiltInCategoryTab[]) {
    this.title = title;
    this.tabs = tabs;
  }
}

export class BuiltInCategory {
  books: BuiltInBook[];
  currentPage: number;
  totalPage: number;
  url: string;
  nextUrl: string;

  constructor(books: BuiltInBook[], currentPage: number, totalPage: number, url: string, nextUrl: string) {
    this.books = books;
    this.currentPage = currentPage;
    this.totalPage = totalPage;
    this.url = url;
    this.nextUrl = nextUrl;
  }
}

/**
 * 首页推荐板块（一个源可以有多个板块：精品多人 / 最新作品 / 热播 / ...）
 * layout:
 *   'horizontal' = 小封面横向滚动（默认）
 *   'grid'       = 大卡片含简介（如"最新作品"那种 book-ol 结构）
 */
export class HomeBlock {
  title: string;
  books: BuiltInBook[];
  moreUrl: string;
  layout: string;

  constructor(title: string, books: BuiltInBook[], moreUrl: string = '', layout: string = 'horizontal') {
    this.title = title;
    this.books = books;
    this.moreUrl = moreUrl;
    this.layout = layout;
  }
}

/** 内置音频源接口。 */
export interface IBuiltInSource {
  /** 源 ID（保持与 eprendre 原 ID 一致，便于后续兼容老收藏） */
  readonly id: string;
  /** 显示名称 */
  readonly name: string;
  /** 站点首页 */
  readonly url: string;
  /** 描述（含推荐指数） */
  readonly desc: string;
  /** 是否支持搜索（不支持时仅出现在分类发现） */
  readonly searchable: boolean;
  /** 可选：该源解析真实音频地址允许的总等待时间。 */
  readonly audioResolveTimeoutMs?: number;

  search(keywords: string, page: number): Promise<BuiltInSearchResult>;
  getCategoryMenus(): Promise<BuiltInCategoryMenu[]>;
  getCategoryList(url: string): Promise<BuiltInCategory>;
  getBookDetail(bookUrl: string, loadEpisodes: boolean, loadFullPages: boolean): Promise<BuiltInBookDetail>;
  /** 可选：按需预热播放会话。调用方不应阻塞页面渲染。 */
  prepareAudio?(): Promise<void>;
  getAudioUrl(chapterUrl: string): Promise<string>;
  /** 可选：音频请求所需的额外头（Referer/Cookie 等） */
  getAudioHeaders(audioUrl: string): Record<string, string>;
  /** 首页推荐板块；不支持时返回空数组即可 */
  getHomeBlocks(): Promise<HomeBlock[]>;
}
