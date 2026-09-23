import { HdsCompat } from '../utils/HdsCompat';
import { curves, FrameCallback, LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { ImmersiveTabComponent } from '../components/ImmersiveTabComponent';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HdsNavigation, HdsNavigationTitleMode, HideMode, BottomBuilderParams, BuilderOptions, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMaterial, AppCurve, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { PlatformCompat } from '../utils/PlatformCompat';
import { Book, Chapter } from '../model/Book';
import { SearchResult, HomeBlockSection } from '../model/BookSource';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import {
  HomeCoverCarousel, homeCoverPerspective, homeCoverCarouselHeight, homeCoverSize, homeCoverSideDistance
} from '../components/HomeCoverCarousel';
import { HomeCategoryCard } from '../components/HomeCategoryCard';
import { HomeCategoryBookRow, HomeCategoryRowDataSource } from '../utils/HomeCategoryRowDataSource';
import { HomeCategoryOverviewRow, HomeCategoryOverviewDataSource } from '../utils/HomeCategoryOverviewDataSource';
import { HomeBlockDataSource } from '../utils/HomeBlockDataSource';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { BookSourceService, ExploreFetchResult } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { DataService } from '../service/DataService';
import { emitter } from '@kit.BasicServicesKit';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { EVT_HOME_SOURCE_CHANGED, EVT_FAVORITES_CHANGED, PreferenceService } from '../service/PreferenceService';
import { HomeSourceCategory, HomeSourceContent, HomeSourceService } from '../service/rulesource/HomeSourceService';

class HomeCategoryDataSource implements IDataSource {
  private categories: HomeSourceCategory[] = [];
  private listeners: DataChangeListener[] = [];

  setCategories(categories: HomeSourceCategory[]): void {
    this.categories = categories;
    for (const listener of this.listeners) listener.onDataReloaded();
  }

  totalCount(): number {
    return this.categories.length;
  }

  getData(index: number): HomeSourceCategory {
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

/** 等待准备帧完成布局，再提交展开动画，避免 animateTo 同步刷新整批新书卡。 */
class HomeCarouselReadyFrame extends FrameCallback {
  private callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onIdle(_timeLeftInNano: number): void {
    this.callback();
  }
}

const SEARCH_FIELD_HEIGHT: number = 40;
const SEARCH_FIELD_ROW_HEIGHT: number = 56;
const CATEGORY_NAV_HEIGHT: number = 34;
const CATEGORY_NAV_FADE_LENGTH: number = 24;
const CATEGORY_NAV_ROW_HEIGHT: number = 48;
const HOME_REFRESH_TRIGGER_DISTANCE: number = 96;
// 内容位移为手指移动的一半：至少下拉约 192vp，再松手才刷新。
const HOME_REFRESH_PULL_DOWN_RATIO: number = 0.5;
// 临界阻尼不回弹；连续反向切换由原生弹簧继承当前速度。
const HOME_CAROUSEL_TRANSITION_CURVE = curves.springMotion(0.32, 1);
const HOME_CONTENT_TRANSITION_DURATION: number = 360;
const HOME_CAROUSEL_SCROLL_FADE_DISTANCE: number = 64;
const COLLAPSED_SEARCH_SIZE: number = 42;
const FEATURED_PAGE_SIZE: number = 3;
const FEATURED_ROW_HEIGHT: number = 72;
const FEATURED_COVER_SIZE: number = 60;
const FEATURED_NEXT_PEEK: number = 32;
const HOME_COVER_CARD_SIZE: number = 128;
const HOME_FIRST_BLOCK_TITLE_OFFSET: number = AppSpace.Xxs;
const HOME_BLOCK_TITLE_HEIGHT: number = 28;
const CATEGORY_OVERVIEW_INDEX: number = -2;
const CATEGORY_CARD_COLORS: string[] = ['#B84332', '#287EA2', '#6750AB', '#248279',
  '#AA4169', '#9B632F', '#475EA8', '#54783A'];

@ComponentV2
struct HomeLoadingSkeleton {
  @Param showCarousel: boolean = true;
  @Param showRecommendations: boolean = true;
  @Param contentWidth: number = 360;
  @Local pulsing: boolean = false;

  onDidBuild(): void {
    if (!this.pulsing) this.pulsing = true;
  }

  @Computed
  get coverContentWidth(): number {
    return this.contentWidth - AppSpace.Md * 2;
  }

  @Computed
  get coverSize(): number {
    return homeCoverSize(this.coverContentWidth);
  }

  @Computed
  get sideDistancePx(): number {
    return this.getUIContext().vp2px(homeCoverSideDistance(this.coverContentWidth));
  }

  @Builder
  skeletonCover() {
    Column({ space: 6 }) {
      Row()
        .width('100%')
        .aspectRatio(0.75)
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
    .width(HOME_COVER_CARD_SIZE)
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
    Column({ space: AppSpace.Xs }) {
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
      .height(HOME_BLOCK_TITLE_HEIGHT)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .translate({ y: HOME_FIRST_BLOCK_TITLE_OFFSET })
      Column() {
        this.skeletonFeaturedRow(true)
        this.skeletonFeaturedRow(true)
        this.skeletonFeaturedRow(false)
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md + FEATURED_NEXT_PEEK })
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
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
  }

  @Builder
  skeletonSection() {
    Column({ space: AppSpace.Xs }) {
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
      .height(HOME_BLOCK_TITLE_HEIGHT)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      this.skeletonCoverRow()
    }
    .width('100%')
  }

  build() {
    Column() {
      Column({ space: AppSpace.Xs }) {
        if (this.showCarousel) {
          Stack() {
            Row().width(this.coverSize).height(this.coverSize).borderRadius(AppRadius.Md)
              .scale({ centerX: 0, centerY: 0, x: 1, y: 1 })
              .transform3D(homeCoverPerspective(this.getUIContext().vp2px(this.coverSize), -1, -this.sideDistancePx))
              .backgroundColor(AppColor.Divider).opacity(0.55)
            Row().width(this.coverSize).height(this.coverSize).borderRadius(AppRadius.Md)
              .scale({ centerX: 0, centerY: 0, x: 1, y: 1 })
              .transform3D(homeCoverPerspective(this.getUIContext().vp2px(this.coverSize), 1, this.sideDistancePx))
              .backgroundColor(AppColor.Divider).opacity(0.55)
            Row().width(this.coverSize).height(this.coverSize).borderRadius(AppRadius.Md)
              .backgroundColor(AppColor.Divider)
          }
          .width('100%').height(homeCoverCarouselHeight(this.coverContentWidth))
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
        if (this.showRecommendations) {
          this.skeletonFeaturedSection()
          this.skeletonSection()
        }
      }
      .width('100%')
      .opacity(this.pulsing ? 0.48 : 0.9)
      .animation({
        duration: 900,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      })
    }
    .width('100%')
    .backgroundColor(HomeTheme.BgNeutral)
    .clip(true)
  }
}

@ComponentV2
export struct HomePage {
  @Local homeBlocks: HomeBlockSection[] = [];
  @Local carouselBooks: SearchResult[] = [];
  @Local loadingHome: boolean = false;
  @Local homeError: ResourceStr = '';
  @Local homeSourceName: string = '';
  @Local homeSources: LocalRuleSource[] = [];
  @Local homeSourceIndex: number = -1;
  @Local savingHomeSource: boolean = false;
  @Local favoriteIds: string[] = [];
  @Local savingFavorite: boolean = false;
  private favoritesChangedHandler: () => void = (): void => { this.loadFavorites(); };
  @Local homeCategories: HomeSourceCategory[] = [];
  private currentSource: LocalRuleSource | undefined = undefined;
  private lastSourceRevision: number = -1;
  private sourceChangedHandler: () => void = (): void => { this.reloadSource(); };
  /** 当前入口：-1=推荐，-2=分类总览，非负值对应所选源的分类。 */
  @Local selectedCategoryIndex: number = -1;
  /** 分类书单数据 */
  @Local categoryBooks: Book[] = [];
  @Local categoryLoading: boolean = false;
  @Local categoryError: ResourceStr = '';
  @Local categoryHasMore: boolean = true;
  @Local categoryNextUrl: string = '';
  private categoryNextPage: number = 1;
  private categoryLoadOnReachEnd: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local refreshPullOffset: number = 0;
  @Local contentEntered: boolean = true;
  // 只提交动画终值，不在 ArkTS 帧回调中回写状态。
  @Local carouselExpansion: number = 1;
  @Local carouselLayoutExpansion: number = 1;
  @Local carouselTransitioning: boolean = false;
  private carouselAnimationSerial: number = 0;
  private carouselTargetExpansion: number = 1;
  private contentEntranceTimer: number = -1;

  @Event onBookTap: (id: string) => void = () => {};
  @Event onBlockMore: (block: HomeBlockSection) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onSearchTap: () => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  /** 分类入口点击:跳到分类书单页(复用 blockMore 路由) */
  @Event onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) => void = () => {};

  private contentScroller: Scroller = new Scroller();
  private recommendationScroller: Scroller = new Scroller();
  private headerScroller: Scroller = new Scroller();
  private categoryNavScroller: Scroller = new Scroller();
  private categoryDS: HomeCategoryRowDataSource = new HomeCategoryRowDataSource();
  private categoryNavDataSource: HomeCategoryDataSource = new HomeCategoryDataSource();
  private categoryOverviewDataSource: HomeCategoryOverviewDataSource = new HomeCategoryOverviewDataSource();
  private homeBlockDataSource: HomeBlockDataSource = new HomeBlockDataSource();
  private homeCoverDataSources: Map<string, HomeRecommendationDataSource<SearchResult>> = new Map();
  private emptyHomeCoverDataSource: HomeRecommendationDataSource<SearchResult> = new HomeRecommendationDataSource();
  private featuredPageDataSource: HomeRecommendationDataSource<SearchResult[]> = new HomeRecommendationDataSource();
  private homeGen: number = 0;
  private refreshInFlight: boolean = false;
  private readonly searchTitleBarBuilder: CustomBuilder = (): void => this.buildSearchTitleBar();
  private readonly homeNavigationBottomBuilder: CustomBuilder = (): void => this.buildHomeNavigationBottom();

  aboutToAppear(): void {
    this.onBackHandlerChange((): boolean => {
      if (this.selectedCategoryIndex === -1) return false;
      this.switchCategory(-1);
      return true;
    });
    hilog.info(DOMAIN, TAG, 'HomePage aboutToAppear');
    CoverPrefetcher.init();
    this.lastSourceRevision = SourceDataService.getInvalidationCounter();
    emitter.on(EVT_HOME_SOURCE_CHANGED, this.sourceChangedHandler);
    emitter.on(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
    this.loadFavorites();
    this.loadHomeBlocks();
    // 把滚动控制器交给上层(MainPage)绑定到 HdsTabsController
    this.onScrollerReady(this.headerScroller);
  }

  aboutToDisappear(): void {
    this.onBackHandlerChange(undefined);
    this.cancelContentEntrance();
    this.cancelCarouselAnimation();
    emitter.off(EVT_HOME_SOURCE_CHANGED, this.sourceChangedHandler);
    emitter.off(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
    this.homeGen++;
  }

  private async loadFavorites(): Promise<void> {
    try {
      this.favoriteIds = await PreferenceService.getFavorites();
    } catch (_error) {
      hilog.warn(DOMAIN, TAG, 'Failed to load home favorites');
    }
  }

  private isFeaturedFavorite(r: SearchResult): boolean {
    return this.favoriteIds.includes(this.homeBookId(r));
  }

  private async toggleFeaturedFavorite(r: SearchResult): Promise<void> {
    if (this.savingFavorite) return;
    this.savingFavorite = true;
    try {
      const book = this.homeBookFromResult(r);
      if (!(await PreferenceService.isFavorite(book.id))) {
        const context = this.getUIContext().getHostContext();
        if (!context) return;
        const cached = await DataService.getBookById(context, book.id);
        await DataService.upsertCachedBook(cached ?? book);
      }
      await PreferenceService.toggleFavorite(book.id);
      await this.loadFavorites();
    } catch (_error) {
      this.showHomeSourceToast($r('app.string.home_favorite_failed'));
    } finally {
      this.savingFavorite = false;
    }
  }

  private reloadSource(): void {
    this.cancelContentEntrance();
    this.cancelCarouselAnimation();
    this.contentEntered = true;
    this.lastSourceRevision = SourceDataService.getInvalidationCounter();
    this.selectedCategoryIndex = -1;
    this.carouselExpansion = 1;
    this.carouselLayoutExpansion = 1;
    this.carouselTargetExpansion = 1;
    this.resetSearchCollapse();
    this.scrollContentToTop();
    this.revealCategoryTab(-1);
    this.loadHomeBlocks();
  }

  private async selectHomeSource(index: number): Promise<void> {
    const source: LocalRuleSource | undefined = this.homeSources[index];
    if (this.savingHomeSource || source === undefined) return;
    this.homeSourceIndex = index;
    this.homeSourceName = source.bookSourceName;
    if (source.bookSourceUrl === this.currentSource?.bookSourceUrl) return;
    this.savingHomeSource = true;
    try {
      // 与书源管理共用保存入口，由现有源变更事件刷新推荐和分类。
      await HomeSourceService.setSelectedSource(source.bookSourceUrl);
      this.showHomeSourceToast($r('app.string.home_source_saved'));
    } catch (_error) {
      this.showHomeSourceToast($r('app.string.rule_source_operation_failed'));
      this.homeSourceIndex = this.homeSources.findIndex((item: LocalRuleSource): boolean =>
        item.bookSourceUrl === this.currentSource?.bookSourceUrl);
      this.homeSourceName = this.currentSource?.bookSourceName ?? '';
    } finally {
      this.savingHomeSource = false;
    }
  }

  private showHomeSourceToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      hilog.warn(DOMAIN, TAG, 'Home source toast unavailable');
    }
  }

  /** 刷新推荐板块或当前分类，保留旧内容直到新数据返回。 */
  private async refreshHomeData(): Promise<void> {
    if (this.lastSourceRevision !== SourceDataService.getInvalidationCounter()) {
      this.lastSourceRevision = SourceDataService.getInvalidationCounter();
      this.selectedCategoryIndex = -1;
      this.cancelCarouselAnimation();
      this.carouselExpansion = 1;
      this.carouselLayoutExpansion = 1;
      this.carouselTargetExpansion = 1;
      await this.loadHomeBlocks(false, true);
    } else if (this.selectedCategoryIndex < 0) {
      await this.loadHomeBlocks(true, true);
    } else {
      await this.switchCategory(this.selectedCategoryIndex, true);
    }
  }

  private async handleHomeRefresh(): Promise<void> {
    if (this.refreshInFlight) return;
    // 自定义指示器与实际请求共用阈值，短拉回弹不发出刷新请求。
    if (this.refreshPullOffset < HOME_REFRESH_TRIGGER_DISTANCE - 0.5) {
      this.isRefreshing = false;
      return;
    }
    this.refreshInFlight = true;
    this.isRefreshing = true;
    hilog.debug(DOMAIN, TAG, 'Home refresh started at offset %{public}.1fvp', this.refreshPullOffset);
    try {
      await this.refreshHomeData();
    } finally {
      this.refreshInFlight = false;
      this.isRefreshing = false;
    }
  }

  private async loadHomeBlocks(preserveContent: boolean = false, forceRefresh: boolean = false): Promise<void> {
    const generation = ++this.homeGen;
    this.loadingHome = true;
    this.categoryLoading = false;
    this.homeError = '';
    if (!preserveContent) {
      this.updateHomeBlocks([]);
      this.updateHomeCategories([]);
      this.currentSource = undefined;
      this.homeSourceName = '';
      this.homeSourceIndex = -1;
    }
    this.categoryBooks = [];
    this.categoryDS.setBooks([]);
    try {
      const sources: LocalRuleSource[] = await HomeSourceService.getSources();
      const source = HomeSourceService.selectAvailable(sources, await PreferenceService.getHomeSourceUrl());
      if (generation !== this.homeGen) return;
      this.homeSources = sources;
      this.homeSourceIndex = sources.findIndex((item: LocalRuleSource): boolean =>
        item.bookSourceUrl === source?.bookSourceUrl);
      if (source === undefined || source.bookSourceUrl !== this.currentSource?.bookSourceUrl) {
        this.updateHomeBlocks([]);
        this.updateHomeCategories([]);
      }
      this.currentSource = source;
      this.homeSourceName = source?.bookSourceName ?? '';
      if (source === undefined) {
        this.homeError = $r('app.string.home_source_no_audio');
        return;
      }
      if (!HomeSourceService.hasHomeContent(source)) {
        this.homeError = $r('app.string.home_source_no_discovery');
        return;
      }
      const content = await HomeSourceService.loadHome(source, forceRefresh,
        (partial: HomeSourceContent): void => {
          if (generation !== this.homeGen) return;
          if (this.homeCategories !== partial.categories) this.updateHomeCategories(partial.categories);
          // 刷新时保留现有书单；首次加载则哪个分类先完成就先展示。
          if (partial.blocks.length > 0 && this.homeBlocks !== partial.blocks) this.updateHomeBlocks(partial.blocks);
        });
      if (generation !== this.homeGen) return;
      const blocks = content.blocks;
      this.updateHomeBlocks(blocks);
      const covers: string[] = [];
      for (const block of blocks) {
        for (const book of block.books) {
          if (book.coverUrl.startsWith('http')) covers.push(book.coverUrl);
        }
      }
      CoverPrefetcher.prefetchMany(covers, 12);
    } catch (error) {
      if (generation !== this.homeGen) return;
      this.homeError = $r('app.string.home_source_load_failed');
      hilog.error(DOMAIN, TAG, 'loadHomeBlocks failed: %{public}s', String(error));
    } finally {
      if (generation === this.homeGen) this.loadingHome = false;
    }
  }

  private scrollContentToTop(): void {
    try {
      this.recommendationScroller.scrollEdge(Edge.Top);
      this.contentScroller.scrollEdge(Edge.Top);
      this.headerScroller.scrollEdge(Edge.Top);
    } catch (_e) { /* ignore */ }
  }

  private updateHomeCategories(categories: HomeSourceCategory[]): void {
    this.homeCategories = categories;
    this.categoryNavDataSource.setCategories(categories);
    this.categoryOverviewDataSource.setCategories(categories);
  }

  private revealCategoryTab(index: number, animated: boolean = false): void {
    try {
      // 滚动列表首项是精品推荐，源分类的列表索引顺延一位。
      this.categoryNavScroller.scrollToIndex(index < 0 ? 0 : index + 1, animated,
        index < 0 ? ScrollAlign.START : ScrollAlign.CENTER);
    } catch (_error) { /* 分类标签尚未布局时保留当前位置。 */ }
  }

  private cancelContentEntrance(): void {
    if (this.contentEntranceTimer !== -1) {
      clearTimeout(this.contentEntranceTimer);
      this.contentEntranceTimer = -1;
    }
  }

  private animateContentEntrance(): void {
    this.cancelContentEntrance();
    if (this.carouselTransitioning) {
      // 头部和书单已经整体移动，不再叠加一次书单入场。
      this.contentEntered = true;
      return;
    }
    this.contentEntered = false;
    // 先提交新内容的起始帧；快速连续切换只保留最后一次入场。
    this.contentEntranceTimer = setTimeout(() => {
      this.contentEntranceTimer = -1;
      this.getUIContext().animateTo({ duration: HOME_CONTENT_TRANSITION_DURATION, curve: AppCurve.Decelerate }, () => {
        this.contentEntered = true;
      });
    }, 16);
  }

  private selectCategoryTab(index: number): void {
    this.selectedCategoryIndex = index;
    this.resetSearchCollapse();
    this.scrollContentToTop();
    this.revealCategoryTab(index, true);
    this.animateCarouselExpansion(index === -1 ? 1 : 0);
    this.animateContentEntrance();
  }

  private cancelCarouselAnimation(): void {
    this.carouselAnimationSerial++;
    this.carouselTransitioning = false;
    this.carouselLayoutExpansion = this.carouselExpansion;
    this.carouselTargetExpansion = this.carouselExpansion;
  }

  private animateCarouselExpansion(target: number): void {
    // 分类之间切换时保留正在进行的收起动画及其完成回调。
    if (this.carouselTargetExpansion === target) return;
    const prepareExpansion: boolean = target === 1 && this.carouselLayoutExpansion === 0 &&
      !this.carouselTransitioning;
    this.carouselTargetExpansion = target;
    const serial: number = ++this.carouselAnimationSerial;
    if (this.carouselFullHeight <= 0 || this.carouselExpansion === target) {
      // 准备帧尚未启动便被反向点击取消时，直接恢复收起状态。
      this.carouselExpansion = target;
      this.carouselLayoutExpansion = target;
      this.carouselTransitioning = false;
      return;
    }
    // 动画期间保留完整滚动占位，HDS 标题栏和内部布局始终使用完整轮播高度。
    // 仅 translate / opacity 参与动画；收起完成后一次性回收外层滚动占位。
    this.carouselLayoutExpansion = 1;
    this.carouselTransitioning = true;
    if (prepareExpansion) {
      // 展开比收起多了推荐节点创建、隐藏封面恢复和滚动占位扩展。
      // 这些工作先提交到准备帧；反向切换直接续接当前弹簧，不等待空闲帧。
      this.getUIContext().postFrameCallback(new HomeCarouselReadyFrame((): void => {
        if (serial === this.carouselAnimationSerial) this.startCarouselAnimation(target, serial);
      }));
      return;
    }
    this.startCarouselAnimation(target, serial);
  }

  private startCarouselAnimation(target: number, serial: number): void {
    this.getUIContext().animateTo({
      curve: HOME_CAROUSEL_TRANSITION_CURVE,
      onFinish: (): void => {
        if (serial !== this.carouselAnimationSerial) return;
        this.carouselLayoutExpansion = target;
        this.carouselTransitioning = false;
      }
    }, (): void => {
      this.carouselExpansion = target;
    });
  }

  private showCategoryOverview(): void {
    if (this.selectedCategoryIndex === CATEGORY_OVERVIEW_INDEX) return;
    // 首次加载仍需取得分类定义；已有分类书单请求则停止回写。
    if (!this.loadingHome) this.homeGen++;
    this.selectCategoryTab(CATEGORY_OVERVIEW_INDEX);
    this.categoryLoading = false;
  }

  /** 切换首页入口（-1=推荐，其他值为榜单或具体分类）。 */
  private async switchCategory(index: number, forceReload: boolean = false): Promise<void> {
    if (this.selectedCategoryIndex === index && !forceReload) return;
    this.homeGen++;
    if (!forceReload) this.selectCategoryTab(index);
    this.categoryLoadOnReachEnd = false;
    this.loadingHome = false;
    this.categoryLoading = false;
    if (index === -1) {
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
      if (this.homeBlocks.length === 0) await this.loadHomeBlocks();
      return;
    }
    const category = this.homeCategories[index];
    const source = this.currentSource;
    if (category === undefined || source === undefined) return;
    if (!forceReload) {
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
    }
    this.categoryError = '';
    this.categoryHasMore = true;
    this.categoryNextUrl = category.url;
    this.categoryNextPage = 1;
    await this.loadCategoryPage(false, !forceReload);
  }

  private async loadCategoryPage(append: boolean, animateEntrance: boolean = false): Promise<void> {
    const source = this.currentSource;
    if (source === undefined || this.selectedCategoryIndex < 0 || this.categoryLoading ||
      !this.categoryHasMore || !this.categoryNextUrl) return;
    const generation = this.homeGen;
    const pageNumber = this.categoryNextPage;
    this.categoryLoadOnReachEnd = false;
    this.categoryLoading = true;
    this.categoryError = '';
    try {
      const page: ExploreFetchResult = await BookSourceService.getExploreBooksByUrl(
        source, this.categoryNextUrl, pageNumber);
      if (generation !== this.homeGen) return;
      const newBooks: Book[] = [];
      const seen = new Set<string>(append ? this.categoryBooks.map((book: Book): string => book.bookUrl) : []);
      for (const item of page.books) {
        if (seen.has(item.bookUrl)) continue;
        seen.add(item.bookUrl);
        newBooks.push(this.homeBookFromResult(item));
      }
      this.categoryBooks = append ? this.categoryBooks.concat(newBooks) : newBooks;
      this.categoryDS.setBooks(this.categoryBooks);
      if (animateEntrance) this.animateContentEntrance();
      this.categoryNextUrl = page.nextUrl;
      this.categoryNextPage = page.nextPage ?? (pageNumber + 1);
      this.categoryHasMore = page.nextUrl.length > 0 && newBooks.length > 0;
      if (this.categoryBooks.length === 0) this.categoryError = $r('app.string.home_source_empty');
      CoverPrefetcher.prefetchMany(newBooks.map((book: Book): string => book.cover)
        .filter((cover: string): boolean => cover.startsWith('http')), 16);
    } catch (error) {
      if (generation !== this.homeGen) return;
      this.categoryError = append ? $r('app.string.home_category_more_failed') :
        $r('app.string.home_source_category_failed');
      hilog.error(DOMAIN, TAG, 'loadCategoryPage failed: %{public}s', String(error));
    } finally {
      if (generation === this.homeGen) this.categoryLoading = false;
    }
  }

  /** 通过 URL 切换分类 */
  private async switchCategoryByUrl(url: string): Promise<void> {
    const index = this.homeCategories.findIndex(cat => cat.url === url);
    if (index !== -1) {
      await this.switchCategory(index);
    }
  }

  private isCategorySelected(cat: HomeSourceCategory): boolean {
    if (this.selectedCategoryIndex < 0) return false;
    const selected = this.homeCategories[this.selectedCategoryIndex];
    return selected && selected.url === cat.url;
  }

  private homeBookId(r: SearchResult): string {
    return r.contentType === 'text' ? BookIdentity.onlineTextBookId(r.sourceUrl || '', r.bookUrl || r.name) :
      BookIdentity.onlineAudioBookId(r.sourceUrl || '', r.bookUrl || r.name);
  }

  private homeBookFromResult(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: this.homeBookId(r),
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: r.kind || (r.contentType === 'text' ? '小说' : '有声书'),
      contentType: r.contentType ?? 'audio',
      intro: r.intro || '',
      wordCount: r.wordCount,
      latestChapterTitle: r.lastChapter,
      updateTime: r.updateTime,
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

  private collectCarouselBooks(blocks: HomeBlockSection[]): SearchResult[] {
    const books: SearchResult[] = [];
    const seen = new Set<string>();
    // 优先使用封面推荐板块，其余板块补足；内容始终来自当前首页源。
    const ordered = blocks.filter((block: HomeBlockSection): boolean => block.layout === 'horizontal')
      .concat(blocks.filter((block: HomeBlockSection): boolean => block.layout !== 'horizontal'));
    for (const block of ordered) {
      for (const book of block.books) {
        const key = `${book.sourceUrl}#${book.bookUrl}`;
        if (!book.bookUrl || !book.coverUrl.startsWith('http') || seen.has(key)) continue;
        seen.add(key);
        books.push(book);
        if (books.length === 6) return books;
      }
    }
    return books;
  }

  private homeBlockKey(block: HomeBlockSection): string {
    return `${block.sourceUrl}#${block.moreUrl}#${block.title}`;
  }

  private homeCoverDataSource(block: HomeBlockSection): HomeRecommendationDataSource<SearchResult> {
    return this.homeCoverDataSources.get(this.homeBlockKey(block)) ?? this.emptyHomeCoverDataSource;
  }

  private updateHomeBlocks(blocks: HomeBlockSection[]): void {
    if (blocks.length === this.homeBlocks.length &&
      blocks.every((block: HomeBlockSection, index: number): boolean => block === this.homeBlocks[index])) return;
    const sources: Map<string, HomeRecommendationDataSource<SearchResult>> = new Map();
    for (const block of blocks) {
      const key = this.homeBlockKey(block);
      const source = this.homeCoverDataSources.get(key) ?? new HomeRecommendationDataSource<SearchResult>();
      const previous = this.homeBlocks.find((item: HomeBlockSection): boolean => this.homeBlockKey(item) === key);
      if (previous?.books !== block.books) source.setItems(block.books);
      sources.set(key, source);
    }
    this.homeCoverDataSources = sources;
    // 分页只在数据更新时计算，返回精品推荐时复用同一个数据源。
    if (this.homeBlocks[0]?.books !== blocks[0]?.books) {
      this.featuredPageDataSource.setItems(this.featuredPages(blocks.length > 0 ? blocks[0].books : []));
    }
    this.homeBlocks = blocks;
    const carousel = this.collectCarouselBooks(blocks);
    if (carousel.length !== this.carouselBooks.length ||
      carousel.some((book: SearchResult, index: number): boolean => book !== this.carouselBooks[index])) {
      this.carouselBooks = carousel;
    }
    this.homeBlockDataSource.setBlocks(blocks);
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

  /** 外层移动整个头部，Tab 吸顶后才把滚动交给内容列表。 */
  @Local isAtContentTop: boolean = true;
  @Local isSearchCollapsed: boolean = false;
  @Local contentWidth: number = 360;
  @Local contentHeight: number = 800;
  @Local headerScrollOffset: number = 0;

  @Computed
  get carouselFullHeight(): number {
    if (this.loadingHome && this.homeBlocks.length === 0) {
      return homeCoverCarouselHeight(this.contentWidth - AppSpace.Md * 2);
    }
    if (this.carouselBooks.length === 0) return 0;
    return homeCoverCarouselHeight(this.contentWidth - AppSpace.Md * 2);
  }

  @Computed
  get carouselPanelHeight(): number {
    return this.carouselLayoutExpansion * this.carouselFullHeight;
  }

  @Computed
  get carouselViewportOpacity(): number {
    // Tab 吸顶时封面底部仍位于透明状态栏内，最后 64vp 淡出，连阴影一起退出。
    if (this.isSearchCollapsed) return 0;
    const remaining: number = SEARCH_FIELD_ROW_HEIGHT + this.carouselFullHeight - this.headerScrollOffset;
    return Math.max(0, Math.min(1, remaining / HOME_CAROUSEL_SCROLL_FADE_DISTANCE));
  }

  @Computed
  get headerScrollRange(): number {
    return SEARCH_FIELD_ROW_HEIGHT + this.carouselPanelHeight;
  }

  @Computed
  get carouselScrollEffectEnabled(): boolean {
    // 外层只模糊经过顶部的轮播；无轮播或 Tab 已吸顶时，模糊由内层导航接管。
    return this.carouselPanelHeight > 0.5 && !this.isSearchCollapsed;
  }

  @Computed
  get topBlurExtraHeight(): number {
    // 模糊尾部止于尚未吸顶的 Tab 上方；吸顶后的内容模糊由 Tab 所在标题栏接管。
    if (!this.carouselScrollEffectEnabled) return 0;
    return Math.min(32, Math.max(0, this.headerScrollRange - this.headerScrollOffset));
  }

  @Computed
  get searchTitleBarContent(): TitleBarContentOptions {
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' },
      stackBuilder: this.searchTitleBarBuilder
    };
    if (PlatformCompat.supports(26)) {
      const searchBuilder: BuilderOptions = { builder: this.searchTitleBarBuilder, updated: false };
      content.stackBuilderContent = searchBuilder;
    }
    return content;
  }

  @Computed
  get homeTitleBarContent(): TitleBarContentOptions {
    const bottom: BottomBuilderParams = {
      builder: this.homeNavigationBottomBuilder,
      height: this.carouselFullHeight + CATEGORY_NAV_ROW_HEIGHT
    };
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' },
      bottomBuilder: bottom
    };
    if (PlatformCompat.supports(26)) {
      // 数据或尺寸变化时保留搜索和标签节点；滚动不改变标题栏高度或构建函数。
      const bottomBuilder: BuilderOptions = { builder: this.homeNavigationBottomBuilder, updated: false };
      bottom.builderContent = bottomBuilder;
    }
    return content;
  }

  private syncHeaderScrollState(): void {
    try {
      const y: number = this.headerScroller.currentOffset().yOffset;
      this.headerScrollOffset = Math.max(0, Math.min(this.headerScrollRange, y));
      const nextAtTop: boolean = y <= 0.5;
      // 主导航双击使外层回顶时，也归零内层列表；手势下滑由 SELF_FIRST 保证先回内容顶部。
      const scroller = this.selectedCategoryIndex === -1 ? this.recommendationScroller : this.contentScroller;
      if (nextAtTop && scroller.currentOffset().yOffset > 0.5) {
        scroller.scrollEdge(Edge.Top);
      }
      const nextCollapsed: boolean = y >= this.headerScrollRange - 0.5;
      if (nextAtTop !== this.isAtContentTop) {
        this.isAtContentTop = nextAtTop;
      }
      if (nextCollapsed !== this.isSearchCollapsed) {
        this.isSearchCollapsed = nextCollapsed;
      }
    } catch (_e) {
      this.isAtContentTop = true;
      this.isSearchCollapsed = false;
      this.headerScrollOffset = 0;
    }
  }

  private resetSearchCollapse(): void {
    this.isAtContentTop = true;
    this.isSearchCollapsed = false;
    this.headerScrollOffset = 0;
  }

  /** 标题栏主区域：放入 Navigation 生效范围，启用原生沉浸光感。 */
  @LocalBuilder
  buildSearchTitleBar() {
    Row({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Xs }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([$r('sys.color.icon_secondary')])
        Text($r('app.string.search_placeholder'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height(SEARCH_FIELD_HEIGHT)
      .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      .borderRadius(AppRadius.Pill)
      .backgroundColor(Color.Transparent)
      .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
      .onClick(() => this.onSearchTap())

      Select(this.homeSources.map((source: LocalRuleSource): SelectOption => {
        return { value: source.bookSourceName };
      }))
        .selected($$this.homeSourceIndex)
        .value(this.homeSourceName || $r('app.string.home_source_setting'))
        .font({ size: 13, weight: FontWeight.Medium })
        .arrowModifier(new SymbolGlyphModifier().visibility(Visibility.None))
        .fontColor(AppColor.Brand)
        .selectedOptionFontColor(AppColor.Brand)
        .selectedOptionBgColor(AppColor.BrandSoft)
        .space(0)
        .menuAlign(MenuAlignType.END)
        .width(LayoutPolicy.wrapContent)
        .constraintSize({ maxWidth: '45%' })
        .height(SEARCH_FIELD_HEIGHT)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
        .borderRadius(AppRadius.Pill)
        .backgroundColor(Color.Transparent)
        .attributeModifier(AppMaterial.selectModifier())
        .enabled(this.homeSources.length > 0 && !this.savingHomeSource)
        .accessibilityDescription($r('app.string.home_source_setting'))
        .onSelect((index: number) => this.selectHomeSource(index))
    }
    .width('100%')
    .height(SEARCH_FIELD_ROW_HEIGHT)
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    // 原生显隐只负责收起标题区域；自定义搜索内容同步移动，避免到阈值才原地消失。
    .translate({ y: -Math.min(SEARCH_FIELD_ROW_HEIGHT, this.headerScrollOffset) })
    .opacity(Math.max(0, Math.min(1, (SEARCH_FIELD_ROW_HEIGHT - this.headerScrollOffset) / 24)))
    .visibility(this.headerScrollOffset >= SEARCH_FIELD_ROW_HEIGHT - 0.5 ? Visibility.Hidden : Visibility.Visible)
  }

  /** 位于分类 Tab 下方、推荐内容上方的下拉刷新指示器。 */
  @Builder
  pullRefreshIndicator() {
    Row() {
      if (this.isRefreshing) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AppColor.Brand)
      } else {
        Progress({
          value: Math.min(100, this.refreshPullOffset / HOME_REFRESH_TRIGGER_DISTANCE * 100),
          total: 100,
          type: ProgressType.Ring
        })
          .width(24)
          .height(24)
          .color(AppColor.Brand)
          .backgroundColor(Color.Transparent)
          .style({ strokeWidth: 2, enableSmoothEffect: false })
      }
    }
    .width('100%')
    .height(this.refreshPullOffset)
    .justifyContent(FlexAlign.Center)
    .opacity(Math.min(1, this.refreshPullOffset / 24))
    .clip(true)
  }

  @Builder
  emptyRefreshIndicator() {
    Column().width(0).height(0)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HomeTheme.BgNeutral)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      // 固定视口的原生渐变模糊，搜索和轮播整体从其后方经过。
      HdsNavigation() {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.emptyRefreshIndicator() }) {
          Scroll(this.headerScroller) {
            Column() {
              this.buildHomeNavigation()
            }
            .width('100%')
            .height(this.contentHeight + this.headerScrollRange)
            .clip(false)
            // 刷新位移独立于展开动画，避免覆盖原生弹簧的 translate。
            .translate({ y: -this.refreshPullOffset })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .enableScrollInteraction(!this.carouselTransitioning)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .clip(false)
          .onDidScroll(() => this.syncHeaderScrollState())
        }
        .onRefreshing(() => this.handleHomeRefresh())
        .onOffsetChange((offset: number) => { this.refreshPullOffset = Math.max(0, offset); })
        .refreshOffset(HOME_REFRESH_TRIGGER_DISTANCE)
        .pullDownRatio(HOME_REFRESH_PULL_DOWN_RATIO)
        .pullToRefresh(this.isAtContentTop && !this.carouselTransitioning)
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: this.searchTitleBarContent,
        style: {
          scrollEffectOpts: {
            enableScrollEffect: this.carouselScrollEffectEnabled,
            scrollEffectType: HdsCompat.scrollEffect
          },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: this.topBlurExtraHeight }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: this.topBlurExtraHeight }
          },
          thermoCtrl: true,
          systemMaterialEffect: this.carouselScrollEffectEnabled ? HdsCompat.material : undefined
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .bindToScrollable([this.headerScroller])
      .dynamicHideTitleBar({
        hideTitleArea: true,
        hideBottomBuilder: true,
        hideStatusBar: false,
        mode: HideMode.SCROLL_UP_TO,
        hideRatio: 1.0
      })
      .systemBarStyle(
        { statusBarContentColor: WindowUtils.getSystemBarContentColor() },
        { statusBarContentColor: WindowUtils.getSystemBarContentColor() }
      )
      .backgroundColor(Color.Transparent)
    }
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      const width: number = Number(newSize.width);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 1) {
        this.contentWidth = width;
      }
      const height: number = Number(newSize.height);
      if (Number.isFinite(height) && height > 0 && Math.abs(height - this.contentHeight) > 1) {
        this.contentHeight = height;
      }
    })
    .onVisibleAreaChange([0, 1], (visible: boolean): void => {
      if (visible && this.lastSourceRevision !== SourceDataService.getInvalidationCounter()) this.reloadSource();
    })
  }

  @Builder
  buildHomeNavigation() {
    HdsNavigation() {
      Column() {
        Column()
          .width('100%')
          .height(WindowUtils.getStatusBarHeightVp() + SEARCH_FIELD_ROW_HEIGHT +
            this.carouselFullHeight + CATEGORY_NAV_ROW_HEIGHT)

        Stack({ alignContent: Alignment.Top }) {
          if (this.refreshPullOffset > 0) {
            this.pullRefreshIndicator()
          }
          // 推荐节点跨入口切换保留，避免恢复轮播时重新创建首屏书单、解码封面。
          this.buildHomeContent(true)
          this.buildHomeContent(false)
        }
        .width('100%')
        .height(Math.max(1, this.contentHeight - WindowUtils.getStatusBarHeightVp() - CATEGORY_NAV_ROW_HEIGHT))
        .clip(false)
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: this.homeTitleBarContent,
      style: {
        scrollEffectOpts: {
          scrollEffectType: HdsCompat.scrollEffect
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        thermoCtrl: true,
        systemMaterialEffect: HdsCompat.material
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .systemBarStyle(
      { statusBarContentColor: WindowUtils.getSystemBarContentColor() },
      { statusBarContentColor: WindowUtils.getSystemBarContentColor() }
    )
    // 标题栏只响应吸顶后的内层滚动；外层原生移动整个 HDS，避免每帧裁剪、重建轮播。
    .bindToScrollable([this.recommendationScroller, this.contentScroller])
    .width('100%')
    .height(this.contentHeight + SEARCH_FIELD_ROW_HEIGHT + this.carouselFullHeight)
    .flexShrink(0)
    // 整个 HDS（轮播、Tab、书单）等距移动，内部高度和标题栏配置不参与动画。
    .translate({ y: (this.carouselExpansion - 1) * this.carouselFullHeight })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildHomeContent(recommendations: boolean) {
    List({ scroller: recommendations ? this.recommendationScroller : this.contentScroller }) {
      ListItemGroup() {
        // 第2~N项：分类总览、推荐板块或分类书单。
        if (recommendations) {
          if (this.loadingHome && this.homeBlocks.length === 0) {
            ListItem() {
              HomeLoadingSkeleton({ showCarousel: false, contentWidth: this.contentWidth })
            }
          } else if (this.homeBlocks.length > 0) {
            LazyForEach(this.homeBlockDataSource, (block: HomeBlockSection, idx: number) => {
              ListItem() {
                this.buildHomeBlock(block, idx)
              }
              .margin({ bottom: AppSpace.Sm })
            }, (block: HomeBlockSection) => `${block.sourceUrl}#${block.moreUrl}#${block.title}`)
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
                Text(this.homeError || $r('app.string.home_source_empty'))
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
        } else if (this.selectedCategoryIndex === CATEGORY_OVERVIEW_INDEX) {
          ListItem() {
            Row() {
              Text($r('app.string.home_categories_all'))
                .fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
              Blank()
              Text($r('app.string.home_categories_count', this.homeCategories.length))
                .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
            }
            .width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md,
              top: AppSpace.Sm, bottom: AppSpace.Md })
          }
          if (this.homeCategories.length === 0) {
            ListItem() {
              Column({ space: AppSpace.Sm }) {
                if (this.loadingHome) {
                  LoadingProgress().width(32).height(32).color(AppColor.Brand)
                } else {
                  Text(this.homeError || $r('app.string.home_categories_empty'))
                    .fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
                    .textAlign(TextAlign.Center)
                }
              }
              .width('100%').height(220).justifyContent(FlexAlign.Center).padding(AppSpace.Md)
            }
          } else {
            LazyForEach(this.categoryOverviewDataSource, (row: HomeCategoryOverviewRow) => {
              ListItem() {
                Row({ space: AppSpace.Sm }) {
                  ForEach(row.categories, (category: HomeSourceCategory, columnIndex: number) => {
                    Column() {
                      this.buildCategoryCard(category, row.startIndex + columnIndex)
                    }
                    .layoutWeight(1)
                  }, (category: HomeSourceCategory) => category.url)
                  if (row.categories.length < 2) {
                    Column().layoutWeight(1)
                  }
                }
                .width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md })
              }
              .margin({ bottom: AppSpace.Sm })
            }, (row: HomeCategoryOverviewRow) => `${this.currentSource?.bookSourceUrl}#${row.key}`)
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
          // LazyVGridLayout 嵌入 List 从 API 26 才支持；统一使用 API 20 可用的懒加载行。
          LazyForEach(this.categoryDS, (row: HomeCategoryBookRow) => {
            ListItem() {
              Row({ space: AppSpace.Sm }) {
                ForEach(row.books, (book: Book, columnIndex: number) => {
                  Column() {
                    BookCard({
                      book: book,
                      indexHint: row.startIndex + columnIndex,
                      showSourceBadge: false,
                      onTap: () => this.openBook(book)
                    })
                  }
                  .layoutWeight(1)
                }, (book: Book) => book.id)
                if (row.books.length < 3) {
                  Column().layoutWeight(1)
                }
                if (row.books.length < 2) {
                  Column().layoutWeight(1)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }
            .margin({ bottom: AppSpace.Md })
          }, (row: HomeCategoryBookRow) => row.key)
          if (this.categoryLoading || this.categoryHasMore || this.categoryError) {
            ListItem() {
              Row({ space: AppSpace.Xs }) {
                if (this.categoryLoading) {
                  LoadingProgress().width(24).height(24).color(AppColor.Brand)
                }
                Text(this.categoryError || (this.categoryLoading ?
                  $r('app.string.home_category_loading_more') : $r('app.string.home_category_load_more')))
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%').height(48).justifyContent(FlexAlign.Center)
              .onClick(() => this.loadCategoryPage(this.categoryNextPage !== 1))
            }
          }
        }

        // 底部留白避开浮动 Tab + MiniPlayer。
        ListItem() {
          Column().height(WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg)
        }
      }
    }
    .width('100%')
    .height(Math.max(1, this.contentHeight - WindowUtils.getStatusBarHeightVp() - CATEGORY_NAV_ROW_HEIGHT))
    .listDirection(Axis.Vertical)
    .enableScrollInteraction(!this.carouselTransitioning)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(recommendations ? 1 : 5)
    .onScrollFrameBegin((offset: number, state: ScrollState) => {
      if (!recommendations && this.selectedCategoryIndex >= 0 && !this.categoryLoading &&
        state === ScrollState.Scroll && offset > 0) {
        this.categoryLoadOnReachEnd = true;
      }
      return { offsetRemain: offset };
    })
    .onReachEnd(() => {
      if (!recommendations && this.selectedCategoryIndex >= 0 && this.categoryBooks.length > 0 &&
        this.categoryLoadOnReachEnd && !this.categoryError && !this.isRefreshing) {
        this.loadCategoryPage(true);
      }
    })
    .translate({ y: this.refreshPullOffset + (this.contentEntered ? 0 : 12) })
    .opacity(this.contentEntered ? 1 : 0)
    .clip(false)
    .backgroundColor(Color.Transparent)
    .visibility(recommendations === (this.selectedCategoryIndex === -1) ? Visibility.Visible : Visibility.Hidden)
    .enabled(recommendations === (this.selectedCategoryIndex === -1))
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
      .height(HOME_BLOCK_TITLE_HEIGHT)
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
        // 按横向视口创建书卡；Scroll + Row 会在展开首帧创建整组封面。
        List({ space: AppSpace.Sm }) {
          LazyForEach(this.homeCoverDataSource(block), (r: SearchResult, i: number) => {
            ListItem() {
              this.buildHomeCoverCard(r, blockIdx * 1000 + i)
            }
          }, (r: SearchResult) => `${block.sourceUrl}#${r.bookUrl}`)
        }
        .listDirection(Axis.Horizontal)
        .height(LayoutPolicy.wrapContent)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .cachedCount(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .clip(false)
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  buildFeaturedCarousel(block: HomeBlockSection) {
    Swiper() {
      LazyForEach(this.featuredPageDataSource, (pageBooks: SearchResult[]) => {
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
    .cachedCount(1)
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

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.isFeaturedFavorite(r) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(22)
            .fontColor([this.isFeaturedFavorite(r) ? AppColor.Brand : $r('sys.color.font_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .enabled(!this.savingFavorite)
        .accessibilityText(this.isFeaturedFavorite(r) ?
          $r('app.string.home_favorite_remove') : $r('app.string.home_favorite_add'))
        .onClick(() => {
          this.toggleFeaturedFavorite(r);
        })
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
  buildCategoryCard(category: HomeSourceCategory, index: number) {
    HomeCategoryCard({
      label: category.name,
      cardColor: CATEGORY_CARD_COLORS[index % CATEGORY_CARD_COLORS.length],
      indexHint: index,
      animateEntrance: !this.carouselTransitioning,
      onTap: () => this.switchCategoryByUrl(category.url)
    })
  }

  @LocalBuilder
  buildHomeNavigationBottom() {
    Column() {
      // 固定尺寸节点随整个导航移动，避免 HDS 在展开途中重新布局、裁掉封面。
      if (this.carouselFullHeight > 0) {
        Column() {
          Column() {
            if (this.loadingHome && this.homeBlocks.length === 0) {
              HomeLoadingSkeleton({ showRecommendations: false, contentWidth: this.contentWidth })
            } else {
              HomeCoverCarousel({
                books: this.carouselBooks,
                active: this.selectedCategoryIndex === -1 && !this.carouselTransitioning && !this.isSearchCollapsed,
                onBookTap: (book: SearchResult) => this.openBook(this.homeBookFromResult(book))
              })
                .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }
          }
          .width('100%').height(this.carouselFullHeight)
          .flexShrink(0)
          .opacity(this.carouselExpansion)
        }
        .width('100%')
        .height(this.carouselFullHeight)
        .clip(true)
        .opacity(this.carouselViewportOpacity)
        .visibility(!this.carouselTransitioning && this.carouselExpansion === 0 ? Visibility.Hidden : Visibility.Visible)
        .enabled(this.selectedCategoryIndex === -1 && !this.carouselTransitioning && !this.isSearchCollapsed)
      }
      this.buildCategoryTags()
    }
    .width('100%')
    .height(this.carouselFullHeight + CATEGORY_NAV_ROW_HEIGHT)
  }

  @Builder
  buildCategoryTags() {
    Row({ space: AppSpace.Xs }) {
      ImmersiveTabComponent({
        label: $r('app.string.home_categories'),
        itemWidth: 56,
        selected: this.selectedCategoryIndex === CATEGORY_OVERVIEW_INDEX,
        onTap: () => this.showCategoryOverview()
      })
      List({ space: AppSpace.Xs, scroller: this.categoryNavScroller }) {
        ListItem() {
          ImmersiveTabComponent({
            label: $r('app.string.home_recommendations'),
            selected: this.selectedCategoryIndex === -1,
            onTap: () => this.switchCategory(-1)
          })
        }
        LazyForEach(this.categoryNavDataSource, (cat: HomeSourceCategory) => {
          ListItem() {
            ImmersiveTabComponent({
              label: cat.name,
              selected: this.isCategorySelected(cat),
              onTap: () => this.switchCategoryByUrl(cat.url)
            })
          }
        }, (cat: HomeSourceCategory) => `${this.currentSource?.bookSourceUrl}#${cat.url}#${cat.name}`)
      }
      .layoutWeight(1)
      .height(CATEGORY_NAV_HEIGHT)
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      // 标签在固定分类入口和收起后的搜索按钮旁渐隐，避免胶囊被硬切。
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(CATEGORY_NAV_FADE_LENGTH) })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
          .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
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
