import { hilog } from '@kit.PerformanceAnalysisKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion, AppCurve, AppMaterial, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult, HomeBlockSection } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import { BookDataSource } from '../utils/BookDataSource';
import { HomeBlockDataSource } from '../utils/HomeBlockDataSource';
import { BuiltInSourceRegistry } from '../service/builtin/BuiltInSourceRegistry';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';

/** 首页分类入口项 */
interface HomeCategory {
  name: string;
  /** 分类列表 URL（欢FM 的 types/<typeId>/comprehensive/p1 路径） */
  url: string;
}

const LATEST_CATEGORY_URL = 'rank/recommend_novel/latest/p1';

/** 最新榜单 + 完整的16个分类。 */
const HOME_CATEGORIES: HomeCategory[] = [
  { name: '最新', url: LATEST_CATEGORY_URL },
  { name: '玄幻奇幻', url: 'types/46/comprehensive/p1' },
  { name: '武侠小说', url: 'types/11/comprehensive/p1' },
  { name: '恐怖惊悚', url: 'types/14/comprehensive/p1' },
  { name: '言情通俗', url: 'types/19/comprehensive/p1' },
  { name: '历史军事', url: 'types/15/comprehensive/p1' },
  { name: '官场商战', url: 'types/17/comprehensive/p1' },
  { name: '百家讲坛', url: 'types/9/comprehensive/p1' },
  { name: '有声文学', url: 'types/10/comprehensive/p1' },
  { name: '刑侦反腐', url: 'types/16/comprehensive/p1' },
  { name: '广播剧', url: 'types/36/comprehensive/p1' },
  { name: '人物纪实', url: 'types/18/comprehensive/p1' },
  { name: '相声小品', url: 'types/21/comprehensive/p1' },
  { name: '健康养生', url: 'types/33/comprehensive/p1' },
  { name: '商业财经', url: 'types/42/comprehensive/p1' },
  { name: '童话寓言', url: 'types/20/comprehensive/p1' },
  { name: '单田芳', url: 'types/1/comprehensive/p1' },
];

/** 欢FM内置源标识(分类入口固定走该源) */
const HUAN_SOURCE_URL = 'builtin://eprendre/huan_fm';
const HUAN_SOURCE_NAME = '欢FM';

const DOMAIN = 0x0000;
const TAG = 'HomePage';

const HEADER_TOOLBAR_HEIGHT: number = 40;
const SEARCH_FIELD_HEIGHT: number = 40;
const SEARCH_FIELD_ROW_HEIGHT: number = 56;
const CATEGORY_NAV_HEIGHT: number = 34;
const CATEGORY_NAV_WIDTH: number = 76;
const CATEGORY_NAV_ROW_HEIGHT: number = 48;
const FEATURED_PAGE_SIZE: number = 3;
const FEATURED_ROW_HEIGHT: number = 72;
const FEATURED_COVER_SIZE: number = 60;
const FEATURED_NEXT_PEEK: number = 32;
const HOME_COVER_CARD_SIZE: number = 128;

@ComponentV2
struct CategoryLightNavItem {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(13)
          .fontColor(this.selected ? HomeTheme.Accent : $r('sys.color.font_secondary'))
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: AppSpace.Xxs, right: AppSpace.Xxs })
      }
      .width('100%')
      .height(30)
      .alignItems(VerticalAlign.Center)

      if (this.selected) {
        Row()
          .width(18)
          .height(2)
          .borderRadius(1)
          .backgroundColor(HomeTheme.Accent)
      } else {
        Row()
          .width(18)
          .height(2)
          .opacity(0)
      }
    }
    .width(CATEGORY_NAV_WIDTH)
    .height(CATEGORY_NAV_HEIGHT)
    .borderRadius(AppRadius.Pill)
    .justifyContent(FlexAlign.Center)
    .systemMaterial(AppMaterial.InteractiveThin)
    .animation({ duration: AppMotion.Base, curve: AppCurve.Spring })
    .onClick(() => this.onTap())
  }
}

@ComponentV2
struct HomeLoadingSkeleton {
  @Local pulsing: boolean = false;

  onDidBuild(): void {
    if (!this.pulsing) this.pulsing = true;
  }

  @Builder
  skeletonCover() {
    Column({ space: 6 }) {
      Row()
        .width('100%')
        .aspectRatio(1)
        .borderRadius(AppRadius.Sm)
        .backgroundColor(AppColor.Divider)
      Row()
        .width('78%')
        .height(12)
        .borderRadius(AppRadius.Xs)
        .backgroundColor(AppColor.Divider)
      Row()
        .width('54%')
        .height(10)
        .borderRadius(AppRadius.Xs)
        .backgroundColor(HomeTheme.ProgressTrack)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  skeletonFeaturedRow(showDivider: boolean) {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Row()
          .width(FEATURED_COVER_SIZE)
          .height(FEATURED_COVER_SIZE)
          .borderRadius(AppRadius.Sm)
          .backgroundColor(AppColor.Divider)
        Column({ space: AppSpace.Xs }) {
          Row()
            .width('72%')
            .height(14)
            .borderRadius(AppRadius.Xs)
            .backgroundColor(AppColor.Divider)
          Row()
            .width('44%')
            .height(10)
            .borderRadius(AppRadius.Xs)
            .backgroundColor(HomeTheme.ProgressTrack)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(FEATURED_ROW_HEIGHT - 1)
      .alignItems(VerticalAlign.Center)

      if (showDivider) {
        Divider()
          .color(AppColor.Divider)
          .margin({ left: FEATURED_COVER_SIZE + AppSpace.Sm })
      }
    }
    .width('100%')
    .height(FEATURED_ROW_HEIGHT)
  }

  @Builder
  skeletonFeaturedSection() {
    Column({ space: AppSpace.Sm }) {
      Row() {
        Row()
          .width(104)
          .height(18)
          .borderRadius(AppRadius.Xs)
          .backgroundColor(AppColor.Divider)
        Blank()
        Row()
          .width(38)
          .height(12)
          .borderRadius(AppRadius.Xs)
          .backgroundColor(HomeTheme.ProgressTrack)
      }
      .width('100%')
      this.skeletonFeaturedRow(true)
      this.skeletonFeaturedRow(true)
      this.skeletonFeaturedRow(false)
    }
    .width('100%')
  }

  @Builder
  skeletonCoverRow() {
    Row({ space: AppSpace.Sm }) {
      this.skeletonCover()
      this.skeletonCover()
      this.skeletonCover()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  skeletonSection() {
    Column({ space: AppSpace.Sm }) {
      Row() {
        Row()
          .width(104)
          .height(18)
          .borderRadius(AppRadius.Xs)
          .backgroundColor(AppColor.Divider)
        Blank()
        Row()
          .width(38)
          .height(12)
          .borderRadius(AppRadius.Xs)
          .backgroundColor(HomeTheme.ProgressTrack)
      }
      .width('100%')
      this.skeletonCoverRow()
    }
    .width('100%')
  }

  build() {
    Column() {
      Column({ space: AppSpace.Md }) {
        this.skeletonFeaturedSection()
        this.skeletonSection()
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Md })
      .opacity(this.pulsing ? 0.48 : 0.9)
      .animation({
        duration: 900,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.BgNeutral)
    .clip(true)
  }
}

@ComponentV2
export struct HomePage {
  @Local audioBooks: Book[] = [];
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local viewMode: number = 0; // 0=grid, 1=list (默认表格模式)
  @Local audioCount: number = 0;
  @Local homeBlocks: HomeBlockSection[] = [];
  @Local loadingHome: boolean = false;
  /** 当前选中的入口索引（-1=推荐，其他值对应 HOME_CATEGORIES）。 */
  @Local selectedCategoryIndex: number = -1;
  /** 分类书单数据 */
  @Local categoryBooks: Book[] = [];
  @Local categoryLoading: boolean = false;
  @Local categoryError: string = '';
  @Local categoryHasMore: boolean = true;
  @Local categoryNextUrl: string = '';
  @Local isRefreshing: boolean = false;
  @Local refreshStatus: RefreshStatus = RefreshStatus.Inactive;

  @Event onBookTap: (id: string) => void = () => {};
  @Event onBlockMore: (block: HomeBlockSection) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  /** 分类入口点击:跳到分类书单页(复用 blockMore 路由) */
  @Event onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) => void = () => {};

  private contentScroller: Scroller = new Scroller();
  private audioDataSource: BookDataSource = new BookDataSource();
  private categoryDS: BookDataSource = new BookDataSource();
  private homeBlockDataSource: HomeBlockDataSource = new HomeBlockDataSource();
  private searchGen: number = 0;
  private homeGen: number = 0;
  private refreshInFlight: boolean = false;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'HomePage aboutToAppear');
    CoverPrefetcher.init();
    this.loadHomeBlocks();
    // 把滚动控制器交给上层(MainPage)绑定到 HdsTabsController
    this.onScrollerReady(this.contentScroller);
  }

  /** 刷新推荐板块或当前分类，保留旧内容直到新数据返回。 */
  private async refreshHomeData(): Promise<void> {
    if (this.hasSearched) return; // 搜索结果态不刷新
    if (this.selectedCategoryIndex === -1) {
      await this.loadHomeBlocks(true);
    } else {
      await this.switchCategory(this.selectedCategoryIndex, true);
    }
  }

  private async handleHomeRefresh(): Promise<void> {
    if (this.refreshInFlight) return;
    if (this.hasSearched) {
      this.isRefreshing = false;
      this.refreshStatus = RefreshStatus.Inactive;
      return;
    }
    this.refreshInFlight = true;
    this.isRefreshing = true;
    try {
      await this.refreshHomeData();
    } finally {
      this.refreshInFlight = false;
      this.isRefreshing = false;
      this.refreshStatus = RefreshStatus.Inactive;
    }
  }

  private shouldShowPullRefreshIndicator(): boolean {
    return this.isRefreshing || this.refreshStatus === RefreshStatus.Drag ||
      this.refreshStatus === RefreshStatus.OverDrag;
  }

  private async loadHomeBlocks(preserveContent: boolean = false): Promise<void> {
    hilog.info(DOMAIN, TAG, 'loadHomeBlocks START, gen=%{public}d', this.homeGen);
    this.homeGen++;
    const gen = this.homeGen;
    if (this.homeBlocks.length === 0) this.loadingHome = true;
    if (!preserveContent) {
      this.homeBlocks = [];
      this.homeBlockDataSource.clear();
    }
    hilog.info(DOMAIN, TAG, 'loadHomeBlocks: cleared data, loadingHome=%{public}s', String(this.loadingHome));
    try {
      // 只加载内置书源的首页推荐,不加载导入的书源
      const plugin = BuiltInSourceRegistry.getByUrl(HUAN_SOURCE_URL);
      if (!plugin) {
        hilog.warn(DOMAIN, TAG, 'loadHomeBlocks: Built-in source not available');
        this.loadingHome = false;
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: calling plugin.getHomeBlocks()');

      const blocks = await plugin.getHomeBlocks();
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: got %{public}d blocks', blocks.length);
      if (gen !== this.homeGen) return;

      // 转换为 HomeBlockSection 格式
      const sections: HomeBlockSection[] = [];
      for (const b of blocks) {
        const books: SearchResult[] = [];
        for (const book of b.books) {
          BuiltInSourceRegistry.cacheBookMeta(book);
          books.push({
            name: book.title,
            author: book.author,
            coverUrl: book.coverUrl,
            bookUrl: book.bookUrl,
            intro: book.intro,
            kind: book.status || '',
            completed: book.completed,
            lastChapter: '',
            sourceName: plugin.name,
            sourceUrl: HUAN_SOURCE_URL
          });
        }
        sections.push({
          title: b.title,
          books: books,
          moreUrl: b.moreUrl,
          layout: b.layout,
          sourceName: plugin.name,
          sourceUrl: HUAN_SOURCE_URL
        });
      }

      this.homeBlocks = sections;
      this.homeBlockDataSource.setBlocks(sections);
      this.loadingHome = false;
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: SUCCESS, sections=%{public}d, loadingHome=false', sections.length);
      // 预下载首页所有网络封面：前 12 张高优，其余排队，失败会自动重试直到完成
      const covers: string[] = [];
      for (const s of sections) {
        for (const b of s.books) {
          if (b.coverUrl && b.coverUrl.startsWith('http')) covers.push(b.coverUrl);
        }
      }
      CoverPrefetcher.prefetchMany(covers, 12);

    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadHomeBlocks failed: %{public}s', String(e));
    } finally {
      if (gen === this.homeGen) {
        this.loadingHome = false;
      }
    }
  }

  private clearSearch(): void {
    this.searchGen++;
    this.searching = false;
    this.hasSearched = false;
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
    this.resetSearchCollapse();
  }

  private scrollContentToTop(): void {
    try {
      this.contentScroller.scrollEdge(Edge.Top);
    } catch (_e) { /* ignore */ }
  }

  /** 切换首页入口（-1=推荐，其他值为榜单或具体分类）。 */
  private async switchCategory(index: number, forceReload: boolean = false): Promise<void> {
    if (this.selectedCategoryIndex === index && !forceReload) return; // 重复点击不处理

    this.selectedCategoryIndex = index;
    this.resetSearchCollapse();
    this.scrollContentToTop();

    if (index === -1) {
      // 切回推荐
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
      return;
    }

    // 加载分类书单
    const cat = HOME_CATEGORIES[index];
    if (!cat) return;

    if (!forceReload) {
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
    }
    this.categoryLoading = true;
    this.categoryError = '';
    this.categoryHasMore = true;
    this.categoryNextUrl = '';

    try {
      const plugin = BuiltInSourceRegistry.getByUrl(HUAN_SOURCE_URL);
      if (!plugin) {
        this.categoryLoading = false;
        this.categoryError = '欢FM源不可用';
        return;
      }

      const books: Book[] = [];
      let nextUrl = cat.url;
      const MIN_BOOKS = 50; // 至少加载50本

      // 循环加载直到达到50本以上
      while (books.length < MIN_BOOKS && nextUrl) {
        const result = await plugin.getCategoryList(nextUrl);

        for (const b of result.books) {
          BuiltInSourceRegistry.cacheBookMeta(b);
          const sr: SearchResult = {
            name: b.title, author: b.author, coverUrl: b.coverUrl,
            bookUrl: b.bookUrl, intro: b.intro, kind: b.status, lastChapter: '',
            sourceName: plugin.name, sourceUrl: HUAN_SOURCE_URL,
            completed: b.completed,
          };
          books.push(this.homeBookFromResult(sr));
        }

        nextUrl = result.nextUrl || '';

        // 如果没有更多数据了就退出
        if (!nextUrl || result.books.length === 0) {
          break;
        }
      }

      this.categoryBooks = books;
      this.categoryDS.setBooks(books);
      this.categoryNextUrl = nextUrl;
      this.categoryHasMore = nextUrl.length > 0;
      this.categoryLoading = false;
      hilog.info(DOMAIN, TAG, 'switchCategory: loaded %{public}d books for category %{public}d', books.length, index);
      const covers: string[] = [];
      for (const b of books) {
        if (b.cover && b.cover.startsWith('http')) covers.push(b.cover);
      }
      CoverPrefetcher.prefetchMany(covers, 16);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'switchCategory failed: %{public}s', String(e));
      this.categoryLoading = false;
      this.categoryError = '加载失败：' + String(e);
    }
  }

  /** 通过 URL 切换分类 */
  private async switchCategoryByUrl(url: string): Promise<void> {
    const index = HOME_CATEGORIES.findIndex(cat => cat.url === url);
    if (index !== -1) {
      await this.switchCategory(index);
    }
  }

  private isCategorySelected(cat: HomeCategory): boolean {
    if (this.selectedCategoryIndex === -1) return false;
    const selected = HOME_CATEGORIES[this.selectedCategoryIndex];
    return selected && selected.url === cat.url;
  }

  private homeBookFromResult(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: BookIdentity.onlineAudioBookId(r.sourceUrl || '', r.bookUrl || r.name),
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: r.kind || 'audio',
      contentType: 'audio',
      intro: r.intro || '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [r.sourceName],
      chapters: emptyChapters,
      bookUrl: r.bookUrl,
      sourceUrl: r.sourceUrl,
      variables: r.variables,
      completed: r.completed,
    };
    SearchCache.put(book);
    return book;
  }

  private async doSearch(): Promise<void> {
    const keyword = this.keyword.trim();
    if (!keyword) {
      this.clearSearch();
      return;
    }
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.hasSearched = true;
    this.resetSearchCollapse();
    this.scrollContentToTop();
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getEnabledSources();
      if (gen !== this.searchGen) return;
      const seen = new Set<string>();
      const tasks: Promise<void>[] = [];
      for (const source of sources) {
        tasks.push(this.searchOneSource(source, keyword, gen, seen));
      }
      await Promise.all(tasks);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
    } finally {
      if (gen === this.searchGen) this.searching = false;
    }
  }

  private async searchOneSource(source: BookSource, keyword: string, gen: number,
    seen: Set<string>): Promise<void> {
    try {
      const results = await BookSourceService.searchBooks(source, keyword);
      if (gen !== this.searchGen) return;
      const books: Book[] = [];
      for (const item of results) {
        const dedupeKey = `${item.sourceUrl}\u001f${item.bookUrl}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        books.push(this.searchResultToBook(item));
      }
      if (books.length === 0) return;
      this.audioBooks = this.audioBooks.concat(books);
      this.audioCount = this.audioBooks.length;
      this.audioDataSource.appendBooks(books);
      const covers: string[] = [];
      for (const b of books) {
        if (b.cover && b.cover.startsWith('http')) covers.push(b.cover);
      }
      CoverPrefetcher.prefetchMany(covers, 12);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'source search failed [%{public}s]: %{public}s',
        source.bookSourceName, String(e));
    }
  }

  private searchResultToBook(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: BookIdentity.onlineAudioBookId(r.sourceUrl || '', r.bookUrl || r.name),
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: r.kind || 'audio',
      contentType: 'audio',
      intro: r.intro || '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [r.sourceName],
      chapters: emptyChapters,
      bookUrl: r.bookUrl,
      sourceUrl: r.sourceUrl,
      variables: r.variables,
      completed: r.completed,
    };
    SearchCache.put(book);
    return book;
  }

  /** 首板块按每页三条分组，横向切换时保留稳定的书籍顺序。 */
  private featuredPages(books: SearchResult[]): SearchResult[][] {
    const pages: SearchResult[][] = [];
    let page: SearchResult[] = [];
    for (const book of books) {
      page.push(book);
      if (page.length === FEATURED_PAGE_SIZE) {
        pages.push(page);
        page = [];
      }
    }
    if (page.length > 0) {
      pages.push(page);
    }
    return pages;
  }

  private featuredPageKey(pageBooks: SearchResult[]): string {
    if (pageBooks.length === 0) return 'featured-empty';
    const firstBook = pageBooks[0];
    return `${firstBook.sourceUrl}#${firstBook.bookUrl}`;
  }

  /** 吸顶次行高度：分类标签行或搜索结果工具条 */
  private currentSubHeaderHeight(): number {
    return this.hasSearched
      ? HEADER_TOOLBAR_HEIGHT
      : CATEGORY_NAV_ROW_HEIGHT;
  }

  /**
   * 列表纵向偏移。搜索折叠由滚动驱动：collapse = clamp(y, 0, SEARCH_ROW)，
   * 一次滑动即可收起/展开，不再二次消费手势。
   */
  @Local listScrollY: number = 0;

  /** 搜索行已折叠像素(0=展开, SEARCH_FIELD_ROW_HEIGHT=完全收起) */
  @Computed
  get searchCollapsePx(): number {
    if (this.listScrollY <= 0) {
      return 0;
    }
    if (this.listScrollY >= SEARCH_FIELD_ROW_HEIGHT) {
      return SEARCH_FIELD_ROW_HEIGHT;
    }
    return this.listScrollY;
  }

  /** 搜索行当前可视高度 */
  @Computed
  get searchRowHeight(): number {
    return SEARCH_FIELD_ROW_HEIGHT - this.searchCollapsePx;
  }

  /**
   * 列表顶部占位始终为完整顶栏高度（状态栏+搜索+吸顶次行）。
   * 折叠只改浮层视觉，不改占位，避免高度跳动导致“拉两次”。
   */
  @Computed
  get headerHeight(): number {
    return WindowUtils.getStatusBarHeightVp() + SEARCH_FIELD_ROW_HEIGHT + this.currentSubHeaderHeight();
  }

  /** 搜索是否完全展开（在顶部），允许下拉刷新 */
  @Computed
  get isSearchFullyExpanded(): boolean {
    return this.listScrollY <= 0.5;
  }

  /** 搜索折叠进度 0~1，用于透明度 */
  @Computed
  get searchCollapseProgress(): number {
    return this.searchCollapsePx / SEARCH_FIELD_ROW_HEIGHT;
  }

  private syncListScrollY(): void {
    try {
      const y: number = this.contentScroller.currentOffset().yOffset;
      this.listScrollY = y > 0 ? y : 0;
    } catch (_e) {
      this.listScrollY = 0;
    }
  }

  private resetSearchCollapse(): void {
    this.listScrollY = 0;
  }

  /**
   * 方案2 浮层顶栏：HDS 渐变模糊 + 搜索折叠 + 分类吸顶。
   */
  @Builder
  fixedSearchBar() {
    Column() {
      // 仅保留状态栏布局空间，模糊由 HdsNavigation 渐变材质统一绘制。
      Column()
        .width('100%')
        .height(WindowUtils.getStatusBarHeightVp())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      Column() {
        Search({ value: this.keyword!!, placeholder: '搜索书籍、作者...' })
          .searchButton('搜索', { fontColor: HomeTheme.Accent })
          .placeholderColor($r('sys.color.font_tertiary'))
          .placeholderFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .textFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .onSubmit(() => this.doSearch())
          .onChange((value: string) => {
            this.keyword = value;
            if (value.length === 0 && this.hasSearched) {
              this.clearSearch();
            }
          })
          .height(SEARCH_FIELD_HEIGHT)
          .backgroundColor(Color.Transparent)
          .systemMaterial(AppMaterial.InteractiveClean)
          .borderRadius(AppRadius.Pill)
          .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
          .opacity(1 - this.searchCollapseProgress)
      }
      .width('100%')
      .height(this.searchRowHeight)
      .clip(true)
      .opacity(this.searchRowHeight > 0 ? 1 : 0)

      if (!this.hasSearched) {
        this.buildCategoryTags()
      } else {
        Row() {
          Text(`有声书 ${this.audioCount}`)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
          if (this.searching) {
            LoadingProgress()
              .width(18).height(18)
              .color(AppColor.Brand)
              .margin({ left: AppSpace.Xs })
          }
          Blank()
          SymbolGlyph(this.viewMode === 0
            ? $r('sys.symbol.list_bullet')
            : $r('sys.symbol.square_grid_2x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
            .padding(8)
            .borderRadius(18)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.getUIContext()?.animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard },
                () => { this.viewMode = this.viewMode === 0 ? 1 : 0; });
            })
        }
        .width('100%')
        .height(HEADER_TOOLBAR_HEIGHT)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Xs })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  /** 隐藏 Refresh 默认指示器，避免它出现在固定顶栏后方。 */
  @Builder
  emptyRefreshIndicator() {
    Column().width(0).height(0)
  }

  /** 位于固定分类栏与内容列表之间的下拉刷新指示器。 */
  @Builder
  pullRefreshIndicator() {
    LoadingProgress()
      .width(24)
      .height(24)
      .color(AppColor.Brand)
      .margin({ bottom: AppSpace.Sm })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 页面与列表共用同一底色，并延伸到状态栏，避免顶部出现色差。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HomeTheme.BgNeutral)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      // L1 原 HdsNavigation
      HdsNavigation() {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.emptyRefreshIndicator() }) {
          List({ scroller: this.contentScroller }) {
        // 第1项:完整顶栏等高占位(高度固定，折叠只改浮层)。
        // 下拉时刷新圈从占位项底部露出，位于分类栏和内容列表之间。
        ListItem() {
          Column() {
            if (this.shouldShowPullRefreshIndicator()) {
              this.pullRefreshIndicator()
            }
          }
          .width('100%')
          .height(this.headerHeight)
          .justifyContent(FlexAlign.End)
        }

        // 第2~N项：内容主体（推荐板块 / 搜索结果 / 空态）
        if (this.hasSearched && this.audioCount === 0 && this.searching) {
          ListItem() {
            this.buildSearchingState()
          }
        } else if (this.hasSearched && this.audioCount === 0 && !this.searching) {
          ListItem() {
            this.buildNoResultState()
          }
        } else if (this.hasSearched) {
          // 搜索结果：直接渲染为 ListItem
          if (this.viewMode === 0) {
            // API 26:直接使用外层 List 的视口按需创建网格项。
            LazyVGridLayout() {
              LazyForEach(this.audioDataSource, (book: Book, idx: number) => {
                BookCard({ book: book, indexHint: idx, onTap: () => this.onBookTap(book.id) })
              }, (book: Book) => book.id)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(LengthMetrics.vp(AppSpace.Sm))
            .rowsGap(LengthMetrics.vp(AppSpace.Md))
            .width('100%')
            .padding({ left: AppSpace.Md, right: AppSpace.Md })
          } else {
            // List 模式：每本书一个 ListItem
            LazyForEach(this.audioDataSource, (book: Book) => {
              ListItem() {
                this.buildListItem(book)
              }
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }, (book: Book) => book.id)
          }
        } else {
          // 未搜索状态:根据 selectedCategoryIndex 显示推荐或分类书单
          if (this.selectedCategoryIndex === -1) {
            // 推荐板块或空态
            if (this.loadingHome && this.homeBlocks.length === 0) {
              ListItem() {
                Column().width('100%').height(300)
              }
            } else if (this.homeBlocks.length > 0) {
              // 推荐板块：每个板块一个 ListItem
              LazyForEach(this.homeBlockDataSource, (block: HomeBlockSection, idx: number) => {
                ListItem() {
                  this.buildHomeBlock(block, idx)
                }
                .margin({ bottom: AppSpace.Sm })
              }, (block: HomeBlockSection, idx: number) => `${block.sourceUrl}#${block.title}#${idx}`)
            } else {
              ListItem() {
                Column() {
                  SymbolGlyph($r('sys.symbol.magnifyingglass'))
                    .fontSize(48)
                    .fontColor([$r('sys.color.font_tertiary')])
                  Text('搜索你想听的书')
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Md })
                  Text(HUAN_SOURCE_NAME)
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Xs })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            }
          } else {
            // 分类书单
            if (this.categoryLoading && this.categoryBooks.length === 0) {
              ListItem() {
                Column() {
                  LoadingProgress().width(40).height(40).color(AppColor.Brand)
                  Text('加载中...')
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Sm })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.categoryError && this.categoryBooks.length === 0) {
              ListItem() {
                Column() {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(48)
                    .fontColor([$r('sys.color.font_tertiary')])
                  Text(this.categoryError)
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Md })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.categoryBooks.length > 0) {
              LazyVGridLayout() {
                LazyForEach(this.categoryDS, (book: Book, idx: number) => {
                  BookCard({
                    book: book,
                    indexHint: idx,
                    onTap: () => this.onBookTap(book.id)
                  })
                }, (book: Book) => book.id)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(LengthMetrics.vp(AppSpace.Sm))
              .rowsGap(LengthMetrics.vp(AppSpace.Md))
              .width('100%')
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }
          }
        }

        // 底部留白避开浮动 Tab + MiniPlayer
        ListItem() {
          Column().height(WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg)
        }
      }
      .width('100%')
      .height('100%')
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
    .clip(false)
    .backgroundColor(Color.Transparent)
    .onDidScroll(() => {
      this.syncListScrollY();
    })
    }
    .onStateChange((state: RefreshStatus) => {
          this.refreshStatus = state;
        })
        .onRefreshing(() => {
          this.handleHomeRefresh();
        })
        .refreshOffset(64)
        // 列表在顶部、搜索完全展开时才允许下拉刷新
        .pullToRefresh(!this.hasSearched && this.isSearchFullyExpanded)
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: { title: { mainTitle: '' } },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.contentScroller])
    .backgroundColor(Color.Transparent)

      if (this.loadingHome && this.homeBlocks.length === 0) {
        Column() {
          HomeLoadingSkeleton()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.headerHeight })
      }

      // 方案2：浮层顶栏，搜索折叠 + 分类吸顶
      this.fixedSearchBar()
    }
  }

  @Builder
  buildSearchingState() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColor.Brand)
      Text(`正在搜索 ${HUAN_SOURCE_NAME}...`)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Sm })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildNoResultState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text('未找到相关有声书')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Md })
      Text('试试其他关键词')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Xs })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildHomeBlock(block: HomeBlockSection, blockIdx: number) {
    Column({ space: AppSpace.Xs }) {
      // 板块标题行
      Row() {
        Text(block.title)
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(` · ${block.sourceName}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        Blank()
        Row({ space: AppSpace.Xxs }) {
          Text('更多')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 6, bottom: 6 })
        .onClick(() => this.onBlockMore(block))
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .alignItems(VerticalAlign.Center)

      // 首板块采用每屏三条的横向轮播，形成参考图中的紧凑私享列表。
      if (blockIdx === 0) {
        this.buildFeaturedCarousel(block)
      } else if (block.layout === 'grid') {
        // 大卡片 + 简介：竖向 List
        Column({ space: AppSpace.Sm }) {
          ForEach(block.books, (r: SearchResult) => {
            this.buildHomeListItem(r)
          }, (r: SearchResult) => `${block.sourceUrl}#${r.bookUrl}`)
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      } else {
        // 横向滚动小封面
        Scroll() {
          Row({ space: AppSpace.Sm }) {
            ForEach(block.books, (r: SearchResult, i?: number) => {
              this.buildHomeCoverCard(r, blockIdx * 1000 + (i ?? 0))
            }, (r: SearchResult) => `${block.sourceUrl}#${r.bookUrl}`)
          }
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  buildFeaturedCarousel(block: HomeBlockSection) {
    Swiper() {
      ForEach(this.featuredPages(block.books), (pageBooks: SearchResult[]) => {
        Column() {
          ForEach(pageBooks, (rowBook: SearchResult, rowIndex?: number) => {
            this.buildFeaturedRow(rowBook, (rowIndex ?? 0) < pageBooks.length - 1)
          }, (rowBook: SearchResult) => `${block.sourceUrl}#featured#${rowBook.bookUrl}`)
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }, (pageBooks: SearchResult[]) => this.featuredPageKey(pageBooks))
    }
    .width('100%')
    .height(FEATURED_ROW_HEIGHT * FEATURED_PAGE_SIZE)
    .nextMargin(FEATURED_NEXT_PEEK, true)
    .indicator(false)
    .loop(false)
    .effectMode(EdgeEffect.Spring)
  }

  @Builder
  buildFeaturedRow(r: SearchResult, showDivider: boolean) {
    Column() {
      Row({ space: AppSpace.Sm }) {
        if (r.coverUrl && r.coverUrl.startsWith('http')) {
          CoverImage({
            url: r.coverUrl,
            imgWidth: FEATURED_COVER_SIZE,
            imgHeight: FEATURED_COVER_SIZE,
            useFixedHeight: true,
            radius: AppRadius.Sm,
            decodeW: 180,
            decodeH: 180,
            highPriority: true
          })
        } else {
          Image($r('app.media.app_icon_legacy'))
            .width(FEATURED_COVER_SIZE)
            .height(FEATURED_COVER_SIZE)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
        }

        Column({ space: AppSpace.Xxs }) {
          Text(r.name)
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(r.author || r.sourceName)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .height(FEATURED_ROW_HEIGHT - 1)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
      .onClick(() => {
        const book = this.homeBookFromResult(r);
        this.onBookTap(book.id);
      })

      if (showDivider) {
        Divider()
          .color(AppColor.Divider)
          .margin({ left: FEATURED_COVER_SIZE + AppSpace.Sm })
      }
    }
    .width('100%')
    .height(FEATURED_ROW_HEIGHT)
  }

  @Builder
  buildHomeCoverCard(r: SearchResult, indexHint: number) {
    Column({ space: 4 }) {
      BookCard({
        book: this.homeBookFromResult(r),
        cardWidth: HOME_COVER_CARD_SIZE,
        indexHint: indexHint,
        onTap: () => {
          const book = this.homeBookFromResult(r);
          this.onBookTap(book.id);
        }
      })
    }
    .width(HOME_COVER_CARD_SIZE)
  }

  @Builder
  buildHomeListItem(r: SearchResult) {
    Row({ space: AppSpace.Md }) {
      if (r.coverUrl && r.coverUrl.startsWith('http')) {
        CoverImage({
          url: r.coverUrl,
          imgWidth: 72,
          imgHeight: 72,
          useFixedHeight: true,
          radius: AppRadius.Sm,
          decodeW: 216,
          decodeH: 216,
          highPriority: true
        })
      } else {
        Stack() {
          Column().width('100%').height('100%').backgroundColor($r('sys.color.brand'))
          Text(r.name ? r.name.substring(0, 1) : '?')
            .fontSize(24).fontColor($r('sys.color.font_on_primary')).fontWeight(FontWeight.Bold)
        }
        .width(72).height(72).borderRadius(AppRadius.Sm).clip(true)
      }
      Column({ space: 4 }) {
        Text(r.name)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (r.author) {
          Text(r.author)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (r.intro) {
          Text(r.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
    .onClick(() => {
      const book = this.homeBookFromResult(r);
      this.onBookTap(book.id);
    })
  }

  @Builder
  buildCategoryTags() {
    Scroll() {
      Row({ space: AppSpace.Xs }) {
        CategoryLightNavItem({
          label: '推荐',
          selected: this.selectedCategoryIndex === -1,
          onTap: () => this.switchCategory(-1)
        })

        ForEach(HOME_CATEGORIES, (cat: HomeCategory) => {
          CategoryLightNavItem({
            label: cat.name,
            selected: this.isCategorySelected(cat),
            onTap: () => this.switchCategoryByUrl(cat.url)
          })
        }, (cat: HomeCategory) => cat.url)
      }
      .height(CATEGORY_NAV_ROW_HEIGHT)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .alignItems(VerticalAlign.Center)
    }
    .height(CATEGORY_NAV_ROW_HEIGHT)
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          CoverImage({
            url: book.cover,
            imgWidth: 100,
            aspectRatioValue: 1,
            radius: AppRadius.Md,
            decodeW: 300,
            decodeH: 300,
            highPriority: false
          })
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('sys.color.brand'))
            Text(book.title ? book.title.substring(0, 1) : '?')
              .fontSize(32)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width(100)
          .aspectRatio(1)
          .borderRadius(AppRadius.Md)
          .clip(true)
        }
        if (book.narrator) {
          Text(book.narrator)
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('sys.color.ohos_id_color_mask_thin'))
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Md })
        }
      }

      Column({ space: 4 }) {
        Text(book.title)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(book.author)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (book.intro) {
          Text(book.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
    .onClick(() => this.onBookTap(book.id))
  }

}
