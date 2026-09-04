import { hilog } from '@kit.PerformanceAnalysisKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HideMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion, AppCurve, AppMaterial, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult, HomeBlockSection } from '../model/BookSource';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import { BookDataSource } from '../utils/BookDataSource';
import { HomeBlockDataSource } from '../utils/HomeBlockDataSource';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { BookSourceService, ExploreFetchResult } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { TingYouSourceIdentity } from '../service/rulesource/tingyou/TingYouSourceIdentity';

/** 首页分类入口项 */
interface HomeCategory {
  name: string;
  /** 分类列表 URL（欢FM 的 types/<typeId>/comprehensive/p1 路径） */
  url: string;
}

/** 听友公开分类；只有用户已导入并启用听友源时才会请求。 */
const HOME_CATEGORIES: HomeCategory[] = [
  { name: '玄幻奇幻', url: 'types/46/popular/p1' },
  { name: '武侠小说', url: 'types/11/popular/p1' },
  { name: '恐怖惊悚', url: 'types/14/popular/p1' },
  { name: '言情通俗', url: 'types/19/popular/p1' },
  { name: '历史军事', url: 'types/15/popular/p1' },
  { name: '官场商战', url: 'types/17/popular/p1' },
  { name: '百家讲坛', url: 'types/9/popular/p1' },
  { name: '有声文学', url: 'types/10/popular/p1' },
  { name: '刑侦反腐', url: 'types/16/popular/p1' },
  { name: '广播剧', url: 'types/36/popular/p1' },
  { name: '人物纪实', url: 'types/18/popular/p1' },
  { name: '相声小品', url: 'types/21/popular/p1' },
  { name: '健康养生', url: 'types/33/popular/p1' },
  { name: '商业财经', url: 'types/42/popular/p1' },
  { name: '童话寓言', url: 'types/20/popular/p1' },
  { name: '单田芳', url: 'types/1/popular/p1' }
];

class HomeCategoryDataSource implements IDataSource {
  private categories: HomeCategory[] = HOME_CATEGORIES;
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.categories.length;
  }

  getData(index: number): HomeCategory {
    return this.categories[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

const DOMAIN = 0x0000;
const TAG = 'HomePage';

const SEARCH_FIELD_HEIGHT: number = 40;
const SEARCH_FIELD_ROW_HEIGHT: number = 56;
const CATEGORY_NAV_HEIGHT: number = 34;
const CATEGORY_NAV_WIDTH: number = 76;
const CATEGORY_NAV_ROW_HEIGHT: number = 48;
const COLLAPSED_SEARCH_SIZE: number = 42;
const FEATURED_PAGE_SIZE: number = 3;
const FEATURED_ROW_HEIGHT: number = 72;
const FEATURED_COVER_SIZE: number = 60;
const FEATURED_NEXT_PEEK: number = 32;
const HOME_COVER_CARD_SIZE: number = 128;
const HOME_FIRST_BLOCK_TITLE_OFFSET: number = AppSpace.Xxs;

@ComponentV2
@ReusableV2
struct CategoryLightNavItem {
  @Param label: ResourceStr = '';
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
    .backgroundColor(Color.Transparent)
    .systemMaterial(AppMaterial.InteractiveClean)
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
  @Local homeBlocks: HomeBlockSection[] = [];
  @Local loadingHome: boolean = false;
  /** 当前选中的入口索引（-1=推荐，其他值对应 HOME_CATEGORIES）。 */
  @Local selectedCategoryIndex: number = -1;
  /** 分类书单数据 */
  @Local categoryBooks: Book[] = [];
  @Local categoryLoading: boolean = false;
  @Local categoryError: ResourceStr = '';
  @Local categoryHasMore: boolean = true;
  @Local categoryNextUrl: string = '';
  @Local isRefreshing: boolean = false;
  @Local refreshStatus: RefreshStatus = RefreshStatus.Inactive;

  @Event onBookTap: (id: string) => void = () => {};
  @Event onBlockMore: (block: HomeBlockSection) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onSearchTap: () => void = () => {};
  /** 分类入口点击:跳到分类书单页(复用 blockMore 路由) */
  @Event onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) => void = () => {};

  private contentScroller: Scroller = new Scroller();
  private categoryDS: BookDataSource = new BookDataSource();
  private categoryNavDataSource: HomeCategoryDataSource = new HomeCategoryDataSource();
  private homeBlockDataSource: HomeBlockDataSource = new HomeBlockDataSource();
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
    if (this.selectedCategoryIndex === -1) {
      await this.loadHomeBlocks(true);
    } else {
      await this.switchCategory(this.selectedCategoryIndex, true);
    }
  }

  private async handleHomeRefresh(): Promise<void> {
    if (this.refreshInFlight) return;
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
    this.homeGen++;
    const generation = this.homeGen;
    if (this.homeBlocks.length === 0) this.loadingHome = true;
    if (!preserveContent) {
      this.homeBlocks = [];
      this.homeBlockDataSource.clear();
    }
    this.categoryBooks = [];
    this.categoryDS.setBooks([]);
    try {
      const source = await this.findEnabledTingYouSource();
      if (source === undefined) {
        return;
      }
      const blocks = await BookSourceService.getHomeBlocks(source);
      if (generation !== this.homeGen) return;
      this.homeBlocks = blocks;
      this.homeBlockDataSource.setBlocks(blocks);
      const covers: string[] = [];
      for (const block of blocks) {
        for (const book of block.books) {
          if (book.coverUrl.startsWith('http')) covers.push(book.coverUrl);
        }
      }
      CoverPrefetcher.prefetchMany(covers, 12);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadHomeBlocks failed: %{public}s', String(error));
    } finally {
      if (generation === this.homeGen) this.loadingHome = false;
    }
  }

  private scrollContentToTop(): void {
    try {
      this.contentScroller.scrollEdge(Edge.Top);
    } catch (_e) { /* ignore */ }
  }

  /** 切换首页入口（-1=推荐，其他值为榜单或具体分类）。 */
  private async switchCategory(index: number, forceReload: boolean = false): Promise<void> {
    if (this.selectedCategoryIndex === index && !forceReload) return;
    this.selectedCategoryIndex = index;
    this.resetSearchCollapse();
    this.scrollContentToTop();
    if (index === -1) {
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
      if (this.homeBlocks.length === 0) await this.loadHomeBlocks();
      return;
    }
    const category = HOME_CATEGORIES[index];
    if (category === undefined) return;
    if (!forceReload) {
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
    }
    this.categoryLoading = true;
    this.categoryError = '';
    this.categoryHasMore = true;
    this.categoryNextUrl = '';
    try {
      const source = await this.findEnabledTingYouSource();
      if (source === undefined) {
        this.categoryError = $r('app.string.home_source_required');
        return;
      }
      const books: Book[] = [];
      const visited = new Set<string>();
      let nextUrl = category.url;
      while (books.length < 50 && nextUrl.length > 0 && !visited.has(nextUrl)) {
        visited.add(nextUrl);
        const page: ExploreFetchResult = await BookSourceService.getExploreBooksByUrl(
          source, nextUrl, 1);
        for (const item of page.books) books.push(this.homeBookFromResult(item));
        nextUrl = page.nextUrl;
        if (page.books.length === 0) break;
      }
      this.categoryBooks = books;
      this.categoryDS.setBooks(books);
      this.categoryNextUrl = nextUrl;
      this.categoryHasMore = nextUrl.length > 0;
      const covers: string[] = [];
      for (const book of books) {
        if (book.cover.startsWith('http')) covers.push(book.cover);
      }
      CoverPrefetcher.prefetchMany(covers, 16);
    } catch (error) {
      this.categoryError = `加载失败：${String(error)}`;
      hilog.error(DOMAIN, TAG, 'switchCategory failed: %{public}s', String(error));
    } finally {
      this.categoryLoading = false;
    }
  }

  private async findEnabledTingYouSource(): Promise<BookSource | undefined> {
    const sources = await SourceDataService.getEnabledSources();
    for (const source of sources) {
      if (TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl)) return source;
    }
    return undefined;
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
      category: r.kind || '有声书',
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

  private openBook(book: Book): void {
    SearchCache.put(book);
    this.onBookTap(book.id);
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

  /** 仅在滚动跨过关键阈值时更新，避免每帧重建标题栏。 */
  @Local isAtContentTop: boolean = true;
  @Local isSearchCollapsed: boolean = false;

  /**
   * 列表顶部占位始终为完整顶栏高度（状态栏+搜索+吸顶次行）。
   * 折叠只改浮层视觉，不改占位，避免高度跳动导致“拉两次”。
   */
  @Computed
  get headerHeight(): number {
    return WindowUtils.getStatusBarHeightVp() + SEARCH_FIELD_ROW_HEIGHT + CATEGORY_NAV_ROW_HEIGHT;
  }

  private syncHeaderScrollState(): void {
    try {
      const y: number = this.contentScroller.currentOffset().yOffset;
      const nextAtTop: boolean = y <= 0.5;
      const nextCollapsed: boolean = y >= SEARCH_FIELD_ROW_HEIGHT - 0.5;
      if (nextAtTop !== this.isAtContentTop) {
        this.isAtContentTop = nextAtTop;
      }
      if (nextCollapsed !== this.isSearchCollapsed) {
        this.isSearchCollapsed = nextCollapsed;
      }
    } catch (_e) {
      this.isAtContentTop = true;
      this.isSearchCollapsed = false;
    }
  }

  private resetSearchCollapse(): void {
    this.isAtContentTop = true;
    this.isSearchCollapsed = false;
  }

  /** 标题栏主区域：放入 Navigation 生效范围，启用原生沉浸光感。 */
  @Builder
  buildSearchTitleBar() {
    Column() {
      Row({ space: AppSpace.Xs }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([$r('sys.color.icon_secondary')])
        Text($r('app.string.search_placeholder'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
      .height(SEARCH_FIELD_HEIGHT)
      .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      .borderRadius(AppRadius.Pill)
      .backgroundColor(Color.Transparent)
      .systemMaterial(AppMaterial.InteractiveClean)
      .onClick(() => this.onSearchTap())
    }
    .width('100%')
    .height(SEARCH_FIELD_ROW_HEIGHT)
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
    .justifyContent(FlexAlign.Center)
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

        // 第2~N项：推荐板块或分类书单。
        if (this.selectedCategoryIndex === -1) {
          if (this.loadingHome && this.homeBlocks.length === 0) {
            ListItem() {
              Column().width('100%').height(300)
            }
          } else if (this.homeBlocks.length > 0) {
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
                Text($r('app.string.search_placeholder'))
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: AppSpace.Md })
                Text($r('app.string.home_imported_source_hint'))
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: AppSpace.Xs })
              }
              .width('100%')
              .height(300)
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.onSearchTap())
            }
          }
        } else if (this.categoryLoading && this.categoryBooks.length === 0) {
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
                showSourceBadge: false,
                onTap: () => this.openBook(book)
              })
            }, (book: Book) => book.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(LengthMetrics.vp(AppSpace.Sm))
          .rowsGap(LengthMetrics.vp(AppSpace.Md))
          .width('100%')
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
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
      this.syncHeaderScrollState();
    })
    }
    .onStateChange((state: RefreshStatus) => {
          this.refreshStatus = state;
        })
        .onRefreshing(() => {
          this.handleHomeRefresh();
        })
        .refreshOffset(64)
        // 列表在顶部、搜索入口完全展开时才允许下拉刷新
        .pullToRefresh(this.isAtContentTop)
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '' },
        stackBuilder: (): void => this.buildSearchTitleBar(),
        bottomBuilder: {
          builder: (): void => this.buildCategoryTags(),
          height: CATEGORY_NAV_ROW_HEIGHT
        }
      },
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
        thermoCtrl: true
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    // 横屏时 HdsNavigation 默认会自动切换 Split，把首页内容压缩到左栏。
    // 首页没有独立的导航栏，始终使用全宽 Stack 模式。
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .systemBarStyle(
      { statusBarContentColor: WindowUtils.getSystemBarContentColor() },
      { statusBarContentColor: WindowUtils.getSystemBarContentColor() }
    )
    .bindToScrollable([this.contentScroller])
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: false,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP_TO,
      hideRatio: 1.0
    })
    .backgroundColor(Color.Transparent)

      if (this.loadingHome && this.homeBlocks.length === 0) {
        Column() {
          HomeLoadingSkeleton()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.headerHeight })
      }
    }
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
        Blank()
        if (block.moreUrl && block.moreUrl.length > 0) {
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
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .alignItems(VerticalAlign.Center)
      .translate({ y: blockIdx === 0 ? HOME_FIRST_BLOCK_TITLE_OFFSET : 0 })

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
          if (r.author) {
            Text(r.author)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
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
        this.openBook(book);
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
        showSourceBadge: false,
        onTap: () => {
          const book = this.homeBookFromResult(r);
          this.openBook(book);
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
      this.openBook(book);
    })
  }

  @Builder
  buildCategoryTags() {
    Row({ space: AppSpace.Xs }) {
      List({ space: AppSpace.Xs }) {
        ListItem() {
          CategoryLightNavItem({
            label: $r('app.string.home_tingyou_source_label'),
            selected: this.selectedCategoryIndex === -1,
            onTap: () => this.switchCategory(-1)
          })
        }

        LazyForEach(this.categoryNavDataSource, (cat: HomeCategory) => {
          ListItem() {
            CategoryLightNavItem({
              label: cat.name,
              selected: this.isCategorySelected(cat),
              onTap: () => this.switchCategoryByUrl(cat.url)
            })
          }
        }, (cat: HomeCategory) => cat.url)
      }
      .layoutWeight(1)
      .height(CATEGORY_NAV_HEIGHT)
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(1)

      if (this.isSearchCollapsed) {
        Stack() {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .width(COLLAPSED_SEARCH_SIZE)
          .height(COLLAPSED_SEARCH_SIZE)
          .borderRadius(AppRadius.Pill)
          .backgroundColor(Color.Transparent)
          .systemMaterial(AppMaterial.InteractiveClean)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .onClick(() => this.onSearchTap())
        }
        .width(COLLAPSED_SEARCH_SIZE)
        .height(COLLAPSED_SEARCH_SIZE)
      }
    }
    .height(CATEGORY_NAV_ROW_HEIGHT)
    .width('100%')
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: 3, bottom: 3 })
    .alignItems(VerticalAlign.Center)
  }

}
