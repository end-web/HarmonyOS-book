import { HdsNavigation, HdsNavigationTitleMode, TitleBarContentOptions, BottomBuilderParams, BuilderOptions } from '@kit.UIDesignKit';
import { RankingBoard, RankingBook, RankingPlatform } from '../model/Ranking';
import { ImmersiveTabComponent } from '../components/ImmersiveTabComponent';
import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { CoverImage } from '../components/CoverImage';
import { AppColor, AppMaterial, HomeTheme, AppSpace } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';
import { WindowUtils } from '../utils/WindowUtils';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { SearchCache } from '../utils/SearchCache';
import { RankingService } from '../service/ranking/RankingService';
import { BookMatchService, RankingMatch, RankingMatchProgress } from '../service/ranking/BookMatchService';
import { DataService } from '../service/DataService';
import { SourceDataService } from '../service/SourceDataService';
import { BookSource } from '../model/BookSource';

@ComponentV2
struct RankingBookRow {
  @Param book: RankingBook = new RankingBook();
  @Event onChoose: (book: RankingBook) => void = () => {};

  build() {
    Row({ space: 14 }) {
      Text(this.book.rank.toString().padStart(2, '0'))
        .fontSize(26).fontWeight(FontWeight.Lighter).fontStyle(FontStyle.Italic)
        .fontColor(this.book.rank <= 3 ? AppColor.Brand : $r('sys.color.font_tertiary')).width(34)
      CoverImage({ url: this.book.coverUrl, imgWidth: 58, imgHeight: 78, useFixedHeight: true,
        radius: 7, decodeW: 174, decodeH: 234 })
      Column({ space: 7 }) {
        Text(this.book.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.book.author || this.book.narrator).fontSize(12)
          .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ top: 12, bottom: 12 }).constraintSize({ minHeight: 102 })
    .onClick(() => this.onChoose(this.book))
    .accessibilityGroup(true).accessibilityText(this.book.title)
  }
}

@ComponentV2
struct RankingSection {
  @Require @Param board: RankingBoard;
  @Event onChoose: (book: RankingBook) => void = () => {};
  @Event onMore: (board: RankingBoard) => void = () => {};
  private audioData: HomeRecommendationDataSource<RankingBook> = new HomeRecommendationDataSource<RankingBook>();

  aboutToAppear(): void { this.audioData.setItems(this.board.books.slice(0, 8)); }
  @Monitor('board')
  updateBoard(): void { this.audioData.setItems(this.board.books.slice(0, 8)); }

  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 5 }) {
          Text(this.board.platformName).fontSize(11).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
          Text(this.board.title).fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button($r('app.string.ranking_more'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(12).fontColor($r('sys.color.font_secondary')).height(44)
          .onClick(() => this.onMore(this.board))
      }.width('100%').padding({ left: 24, right: 18 })
      if (this.board.books.length === 0) {
        Text(this.board.unavailable ? $r('app.string.ranking_unavailable') : $r('app.string.ranking_loading'))
          .fontSize(13).fontColor($r('sys.color.font_tertiary')).width('100%').height(90)
      } else if (this.board.books[0]?.contentType === 'text') {
        Column() {
          ForEach(this.board.books.slice(0, 3), (book: RankingBook) => {
            RankingBookRow({ book: book, onChoose: this.onChoose })
          }, (book: RankingBook): string => book.id)
        }.padding({ left: 24, right: 24 }).width('100%')
      } else {
        List({ space: 16 }) {
          LazyForEach(this.audioData, (book: RankingBook) => {
            ListItem() {
              Column({ space: 9 }) {
                Stack({ alignContent: Alignment.BottomStart }) {
                  CoverImage({ url: book.coverUrl, imgWidth: 152, imgHeight: 152, useFixedHeight: true,
                    radius: 12, decodeW: 456, decodeH: 456 })
                  Text(book.rank.toString().padStart(2, '0')).fontSize(30).fontWeight(FontWeight.Bold)
                    .fontColor(Color.White).textShadow({ radius: 10, color: '#66000000', offsetY: 2 })
                    .margin({ left: 10, bottom: 7 })
                }
                Text(book.title).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary')).maxLines(2).height(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(book.narrator || book.author).fontSize(11).fontColor($r('sys.color.font_secondary'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width(152).alignItems(HorizontalAlign.Start).onClick(() => this.onChoose(book))
            }
          }, (book: RankingBook): string => book.id)
        }.listDirection(Axis.Horizontal).height(228).width('100%').scrollBar(BarState.Off)
        .contentStartOffset(24).contentEndOffset(24).cachedCount(1)
      }
      if (this.board.stale) {
        Text($r('app.string.ranking_cached')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          .width('100%').padding({ left: 24, right: 24 })
      }
      Divider().color(AppColor.Divider).margin({ left: 24, right: 24, top: 8 })
    }.width('100%').padding({ top: 26, bottom: 4 }).alignItems(HorizontalAlign.Start)
  }
}

class RankingPosterItem {
  book: RankingBook;
  platformName: Resource;
  boardName: Resource;
  constructor(book: RankingBook, platformName: Resource, boardName: Resource) {
    this.book = book;
    this.platformName = platformName;
    this.boardName = boardName;
  }
}

@ComponentV2
struct RankingPoster {
  @Require @Param item: RankingPosterItem;
  @Event onChoose: (book: RankingBook) => void = () => {};

  build() {
    Stack() {
      Row({ space: 22 }) {
        Column({ space: 12 }) {
          Text(this.item.platformName).fontSize(11).letterSpacing(1).fontColor(AppColor.Brand)
          Text(this.item.book.title).fontSize(25).fontWeight(FontWeight.Bold).maxLines(3)
            .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.item.book.author || this.item.book.narrator).fontSize(12).maxLines(2)
            .fontColor($r('sys.color.font_secondary'))
          Text(this.item.boardName).fontSize(11).fontColor($r('sys.color.font_secondary'))
          Row({ space: 5 }) {
            Text($r('app.string.ranking_find_source')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
            SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(13).fontColor([AppColor.Brand])
          }.margin({ top: 10 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        CoverImage({ url: this.item.book.coverUrl, imgWidth: '43%', imgHeight: this.item.book.contentType === 'text' ? 214 : 158,
          useFixedHeight: true, radius: 10, decodeW: 480, decodeH: 640 })
      }.width('100%').padding({ left: 26, right: 26, top: 20, bottom: 30 })
    }.height(292).width('100%').clip(true).onClick(() => this.onChoose(this.item.book))
  }
}

@Builder
function rankingEmptyHeader() { Row().height(56) }

class RankingMatchRestoreFrame extends FrameCallback {
  private restore: () => void;
  constructor(restore: () => void) { super(); this.restore = restore; }
  onIdle(_timeLeftInNano: number): void { this.restore(); }
}

@ComponentV2
export struct RankingHomePage {
  @BuilderParam headerBuilder: () => void = rankingEmptyHeader;
  @Event onBookTap: (id: string, resume: () => void) => void = () => {};
  @Event onSearchTap: () => void = () => {};
  @Event onManageSources: (resume: () => void) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Local boards: RankingBoard[] = [];
  @Local platformId: string = '';
  @Local activeBoard: RankingBoard | undefined = undefined;
  @Local posterCount: number = 0;
  @Local posterVisible: boolean = false;
  @Local posterCover: string = '';
  @Local contentHeight: number = 800;
  @Local headerOffset: number = 0;
  @Local overview: boolean = false;
  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local refreshPullOffset: number = 0;
  @Local showSheet: boolean = false;
  @Local selectedBook: RankingBook = new RankingBook();
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local sourceTotal: number = -1;
  @Local completed: number = 0;
  @Local failed: number = 0;
  @Local matchesCount: number = 0;
  @Local matchType: string = '';
  @Local allMatches: RankingMatch[] = [];
  @Local matchError: boolean = false;
  @Local opening: boolean = false;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  @Local leftSafe: number = WindowUtils.getLeftSafeVp();
  @Local rightSafe: number = WindowUtils.getRightSafeVp();
  private platforms: RankingPlatform[] = RankingService.platforms();
  private boardData: HomeRecommendationDataSource<RankingBoard> = new HomeRecommendationDataSource<RankingBoard>();
  private fullData: HomeRecommendationDataSource<RankingBook> = new HomeRecommendationDataSource<RankingBook>();
  private matchData: HomeRecommendationDataSource<RankingMatch> = new HomeRecommendationDataSource<RankingMatch>();
  private platformData: HomeRecommendationDataSource<RankingPlatform> = new HomeRecommendationDataSource<RankingPlatform>();
  private posterData: HomeRecommendationDataSource<RankingPosterItem> = new HomeRecommendationDataSource<RankingPosterItem>();
  private categoryScroller: Scroller = new Scroller();
  private posterIdentity: string = '';
  private posterController: SwiperController = new SwiperController();
  private scroller: Scroller = new Scroller();
  private headerScroller: Scroller = new Scroller();
  private matchScroller: Scroller = new Scroller();
  private matchOffset: number = 0;
  private matchSuspended: boolean = false;
  private readonly navigationBottomBuilder: CustomBuilder = (): void => this.navigationBottom();
  private readonly searchHeaderBuilder: CustomBuilder = (): void => this.headerBuilder();
  private matcher: BookMatchService = new BookMatchService();
  private generation: number = 0;
  private matchGeneration: number = 0;
  private alive: boolean = false;
  private readonly safeAreaListener = (top: number, _bottom: number): void => {
    this.topSafe = top;
    this.leftSafe = WindowUtils.getLeftSafeVp();
    this.rightSafe = WindowUtils.getRightSafeVp();
  };

  aboutToAppear(): void {
    this.alive = true;
    this.platformData.setItems(this.platforms);
    this.onScrollerReady(this.headerScroller);
    this.onBackHandlerChange((): boolean => {
      if (this.showSheet) { this.showSheet = false; return true; }
      if (this.activeBoard !== undefined) { this.closeBoard(); return true; }
      if (this.overview) { this.selectPlatform(''); return true; }
      return false;
    });
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.load(false);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.matchGeneration++;
    this.matcher.cancel();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange(undefined);
  }

  private syncBoards(): void {
    const visible = this.boards.filter((board: RankingBoard): boolean => !this.platformId || board.platformId === this.platformId);
    this.boardData.setItems(visible);
    const posters: RankingPosterItem[] = [];
    const seen = new Set<string>();
    // 从当前平台各榜轮流取书，最多六张；同一本书跨榜不重复。
    for (let index = 0; index < 6 && posters.length < 6; index++) {
      for (const board of visible) {
        const book = board.books[index];
        if (book === undefined || seen.has(book.id) || posters.length >= 6) continue;
        seen.add(book.id);
        posters.push(new RankingPosterItem(book, board.platformName, board.title));
      }
    }
    const posterIdentity = posters.map((item: RankingPosterItem): string => item.book.id).join('|');
    if (this.posterIdentity !== posterIdentity) {
      this.posterIdentity = posterIdentity;
      this.posterData.setItems(posters);
      this.posterCount = posters.length;
      this.posterCover = posters[0]?.book.coverUrl ?? '';
      this.posterController.changeIndex(0, false);
    }
    if (this.activeBoard !== undefined) {
      const id = this.activeBoard.id;
      const updated = this.boards.find((board: RankingBoard): boolean => board.id === id);
      if (updated !== this.activeBoard) {
        this.activeBoard = updated;
        this.fullData.setItems(updated?.books ?? []);
      }
    }
  }

  private async load(force: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) { this.loading = false; this.refreshing = false; return; }
    const generation = ++this.generation;
    this.loading = true;
    try {
      if (this.boards.length === 0) {
        const cached = await Promise.all(RankingService.boards().map((board: RankingBoard): Promise<RankingBoard> =>
          RankingService.cached(context, board)));
        if (generation !== this.generation) return;
        this.boards = cached;
        this.syncBoards();
      }
      const snapshot = this.boards.slice();
      // 榜单最多三个并发，逐板块显示，单平台失败不阻塞其他内容。
      let cursor = 0;
      const worker = async (): Promise<void> => {
        while (generation === this.generation && cursor < snapshot.length) {
          const board = snapshot[cursor++];
          const loaded = await RankingService.load(context, board, force);
          if (generation !== this.generation) return;
          this.boards = this.boards.map((entry: RankingBoard): RankingBoard => entry.id === loaded.id ? loaded : entry);
          this.syncBoards();
        }
      };
      await Promise.all([worker(), worker(), worker()]);
    } finally {
      if (generation === this.generation) { this.loading = false; this.refreshing = false; }
    }
  }

  private selectPlatform(id: string): void {
    this.platformId = id;
    this.overview = false;
    this.syncBoards();
    // 不操作纵向滚动控制器；平台切换保持当前海报与分类栏位置。
  }

  private openBoard(board: RankingBoard): void {
    this.activeBoard = board;
    this.onScrollerReady(this.scroller);
    this.fullData.setItems(board.books);
    this.scroller.scrollEdge(Edge.Top);
    this.headerScroller.scrollEdge(Edge.Top);
  }

  private closeBoard(): void {
    this.activeBoard = undefined;
    this.onScrollerReady(this.headerScroller);
    this.scroller.scrollEdge(Edge.Top);
    this.headerScroller.scrollEdge(Edge.Top);
  }

  private openMatch(book: RankingBook): void {
    this.selectedBook = book;
    this.keyword = BookMatchService.keyword(book);
    this.matchType = '';
    this.matchSuspended = false;
    this.matchOffset = 0;
    this.showSheet = true;
    this.searchMatches();
  }

  private async searchMatches(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.keyword.trim()) return;
    const generation = ++this.matchGeneration;
    this.searching = true;
    this.matchError = false;
    this.sourceTotal = -1;
    this.completed = 0;
    this.failed = 0;
    this.matchesCount = 0;
    this.allMatches = [];
    this.matchOffset = 0;
    this.matchData.setItems([]);
    try {
      await this.matcher.search(context, this.selectedBook, this.keyword.trim(), (progress: RankingMatchProgress): void => {
        if (generation !== this.matchGeneration || !this.alive) return;
        this.sourceTotal = progress.total;
        this.completed = progress.completed;
        this.failed = progress.failed;
        this.allMatches = progress.matches.slice();
        this.filterMatches();
      });
    } catch (_error) {
      if (generation === this.matchGeneration) this.matchError = true;
    } finally {
      if (generation === this.matchGeneration) this.searching = false;
    }
  }

  private filterMatches(): void {
    const visible = this.allMatches.filter((match: RankingMatch): boolean =>
      this.matchType.length === 0 || match.book.contentType === this.matchType);
    this.matchesCount = visible.length;
    this.matchData.setItems(visible);
  }

  private selectMatchType(type: string): void {
    this.matchType = type;
    this.matchOffset = 0;
    this.filterMatches();
    this.matchScroller.scrollEdge(Edge.Top);
  }

  private async chooseMatch(match: RankingMatch): Promise<void> {
    if (this.opening) return;
    this.opening = true;
    const selected = this.selectedBook;
    const generation = this.matchGeneration;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const sources = await SourceDataService.getEnabledSources();
      if (!sources.some((source: BookSource): boolean => source.bookSourceUrl === match.book.sourceUrl)) {
        throw new Error('Selected source is no longer enabled');
      }
      await DataService.upsertCachedBook(match.book);
      await BookMatchService.remember(context, selected, match);
      if (!this.alive || generation !== this.matchGeneration || !this.showSheet) return;
      SearchCache.put(match.book);
      this.matchSuspended = true;
      this.matchOffset = this.matchScroller.currentOffset().yOffset;
      this.showSheet = false;
      this.onBookTap(match.book.id, (): void => {
        if (!this.alive || this.selectedBook.id !== selected.id) return;
        this.matchSuspended = false;
        this.showSheet = true;
      });
    } catch (_error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_open_failed') });
      } catch (_ignored) { /* 页面离开时不显示提示。 */ }
    } finally { this.opening = false; }
  }

  private manageSources(): void {
    this.showSheet = false;
    this.onManageSources((): void => {
      if (!this.alive) return;
      this.showSheet = true;
      this.searchMatches();
    });
  }

  @Builder
  private heroContent() {
    if (this.posterCount > 0) {
      Swiper(this.posterController) {
        LazyForEach(this.posterData, (item: RankingPosterItem) => {
          RankingPoster({ item: item, onChoose: (book: RankingBook): void => this.openMatch(book) })
        }, (item: RankingPosterItem): string => item.book.id)
      }.width('100%').height(292).loop(true).autoPlay(this.posterVisible && !this.showSheet && this.posterCount > 1)
      .interval(5000).duration(450).cachedCount(1)
      .onChange((index: number): void => { this.posterCover = this.posterData.getData(index)?.book.coverUrl ?? ''; })
      .indicator(new DotIndicator().itemWidth(5).itemHeight(5).selectedItemWidth(16).selectedItemHeight(5)
        .color(AppColor.Divider).selectedColor(AppColor.Brand).bottom(10))
      .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number): void => { this.posterVisible = visible && ratio >= 0.5; })
    } else if (this.loading) {
      Row({ space: 24 }) {
        Column({ space: 14 }) {
          Row().height(22).width('80%').backgroundColor(AppColor.Divider).borderRadius(6)
          Row().height(16).width('55%').backgroundColor(AppColor.Divider).borderRadius(5)
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row().width('43%').height(210).borderRadius(10).backgroundColor(AppColor.Divider)
      }.height(292).width('100%').padding(26)
    }
  }

  @Builder
  private platformTabs() {
    Row({ space: AppSpace.Xs }) {
      ImmersiveTabComponent({ label: $r('app.string.home_categories'), itemWidth: 56,
        selected: this.overview, onTap: (): void => { this.overview = true; } })
      List({ space: AppSpace.Xs, scroller: this.categoryScroller }) {
        LazyForEach(this.platformData, (platform: RankingPlatform) => {
          ListItem() {
            ImmersiveTabComponent({ label: platform.name,
              selected: !this.overview && this.platformId === platform.id,
              onTap: (): void => this.selectPlatform(platform.id) })
          }
        }, (platform: RankingPlatform): string => platform.id || 'recommendations')
      }.layoutWeight(1).height(34).listDirection(Axis.Horizontal).scrollBar(BarState.Off)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(24) })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).cachedCount(1)
    }.height(48).width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: 3, bottom: 3 })
  }

  @Builder
  private categoryOverview() {
    Column({ space: 12 }) {
      ForEach(this.platforms.filter((platform: RankingPlatform): boolean => platform.id.length > 0),
        (platform: RankingPlatform) => {
          Column({ space: 12 }) {
            Text(platform.name).fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
              ForEach(this.boards.filter((board: RankingBoard): boolean => board.platformId === platform.id),
                (board: RankingBoard) => {
                  Button(board.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
                    .height(44).backgroundColor(AppColor.BrandSoft).onClick(() => this.openBoard(board))
                }, (board: RankingBoard): string => board.id)
            }.width('100%')
          }.alignItems(HorizontalAlign.Start).padding(18).width('100%').borderRadius(16)
          .backgroundColor(AppColor.GlassSheetControlTint)
        }, (platform: RankingPlatform): string => platform.id)
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private refreshIndicator() {
    Row() {
      if (this.refreshing) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      } else {
        Progress({ value: Math.min(100, this.refreshPullOffset / 96 * 100), total: 100, type: ProgressType.Ring })
          .width(24).height(24).color(AppColor.Brand).backgroundColor(Color.Transparent)
          .style({ strokeWidth: 2, enableSmoothEffect: false })
      }
    }.width('100%').height(this.refreshPullOffset).justifyContent(FlexAlign.Center)
      .opacity(Math.min(1, this.refreshPullOffset / 24)).clip(true)
  }

  @Builder
  private emptyRefreshIndicator() {
    Column().width(0).height(0)
  }

  @Builder
  private sheetContent() {
    Column({ space: 16 }) {
        Row({ space: 14 }) {
          CoverImage({ url: this.selectedBook.coverUrl, imgWidth: 54, imgHeight: 70, useFixedHeight: true, radius: 7 })
          Column({ space: 7 }) {
            Text(this.selectedBook.title).fontSize(18).fontWeight(FontWeight.Bold).maxLines(2)
              .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.selectedBook.author || this.selectedBook.narrator).fontSize(12).maxLines(1)
              .fontColor($r('sys.color.font_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        Search({ value: this.keyword, placeholder: $r('app.string.ranking_search_keyword') })
          .height(44).searchButton($r('app.string.ranking_search'), { fontColor: AppColor.Brand })
          .onChange((text: string): void => { this.keyword = text; })
          .onSubmit(() => this.searchMatches())
        Row({ space: 8 }) {
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_all_count', this.allMatches.length),
            fitContent: true, selected: this.matchType === '', onTap: (): void => this.selectMatchType('') })
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_audio_count',
            this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'audio').length),
            fitContent: true, selected: this.matchType === 'audio', onTap: (): void => this.selectMatchType('audio') })
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_text_count',
            this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'text').length),
            fitContent: true, selected: this.matchType === 'text', onTap: (): void => this.selectMatchType('text') })
        }.width('100%').height(40)
        if (this.searching) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(AppColor.Brand)
            Text($r('app.string.ranking_matching', this.completed, Math.max(0, this.sourceTotal)))
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          }.width('100%')
        } else if (this.sourceTotal === 0) {
          Text($r('app.string.ranking_no_sources')).fontSize(14).fontColor($r('sys.color.font_secondary'))
            .width('100%').padding({ top: 14, bottom: 14 })
        } else if (this.matchesCount === 0) {
          Text(this.matchError || this.failed > 0 ? $r('app.string.ranking_match_failed') : $r('app.string.ranking_no_match'))
            .fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
        } else {
          Text($r('app.string.ranking_choose_version')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
        }
        List({ space: 8, scroller: this.matchScroller }) {
          LazyForEach(this.matchData, (match: RankingMatch) => {
            ListItem() {
              Column({ space: 7 }) {
                Row() {
                  Text(match.sourceName).fontSize(12).fontColor(AppColor.Brand).layoutWeight(1).maxLines(1)
                  Text(match.book.contentType === 'text' ? $r('app.string.search_type_text') : $r('app.string.search_type_audio'))
                    .fontSize(10).fontColor($r('sys.color.font_secondary')).margin({ right: 8 })
                  if (match.remembered) {
                    Text($r('app.string.ranking_last_choice')).fontSize(10).fontColor(AppColor.Brand)
                  }
                }.width('100%')
                Text(match.book.title).fontSize(16).fontWeight(FontWeight.Medium).maxLines(2)
                  .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(match.book.author || match.book.intro).fontSize(12).maxLines(2)
                  .fontColor($r('sys.color.font_secondary')).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%').padding(14).alignItems(HorizontalAlign.Start).borderRadius(14)
              .backgroundColor(AppColor.GlassSheetControlTint).enabled(!this.opening)
              .onClick(() => this.chooseMatch(match))
            }
          }, (match: RankingMatch): string => `${match.book.sourceUrl}\u001f${match.book.bookUrl}`)
        }.width('100%').layoutWeight(1).cachedCount(2)
        if (!this.searching && this.matchesCount === 0) {
          Button($r('app.string.ranking_manage_sources'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontColor(AppColor.Brand).height(44).onClick(() => this.manageSources())
        }
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 14, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Computed
  get headerRange(): number { return this.activeBoard === undefined ? 292 : 0; }

  @Computed
  get posterViewportHeight(): number {
    return Math.max(0, this.headerRange - this.headerOffset);
  }

  @Computed
  get navigationTitleContent(): TitleBarContentOptions {
    const bottom: BottomBuilderParams = {
      builder: this.navigationBottomBuilder,
      height: this.activeBoard === undefined ? this.posterViewportHeight + 48 : 0
    };
    if (PlatformCompat.supports(26)) {
      const builderContent: BuilderOptions = { builder: this.navigationBottomBuilder, updated: false };
      bottom.builderContent = builderContent;
    }
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' }, bottomBuilder: bottom
    };
    if (this.activeBoard === undefined) {
      content.stackBuilder = this.searchHeaderBuilder;
    } else {
      content.backIcon = {
        icon: $r('sys.symbol.chevron_left'),
        action: (): void => this.closeBoard()
      };
    }
    return content;
  }

  private syncHeaderScroll(): void {
    const previousOffset = this.headerOffset;
    this.headerOffset = Math.max(0, this.headerScroller.currentOffset().yOffset);
    // 只联动首页头部从收起到回顶的变化；具体榜单没有头部滚动行程，偏移始终为零。
    if (this.activeBoard === undefined && previousOffset >= 0.5 &&
      this.headerOffset < 0.5 && this.scroller.currentOffset().yOffset > 0.5) {
      this.scroller.scrollEdge(Edge.Top);
    }
  }

  @LocalBuilder
  private navigationBottom() {
    Column() {
      if (this.activeBoard === undefined) {
        Stack({ alignContent: Alignment.Top }) {
          Column() { this.heroContent() }.width('100%').height(292)
            .translate({ y: -Math.min(this.headerRange, this.headerOffset) })
        }.width('100%').height(this.posterViewportHeight).clip(true)
        this.platformTabs()
      }
    }.width('100%').height(this.activeBoard === undefined ? this.posterViewportHeight + 48 : 0)
  }

  @Builder
  private rankingContent() {
    // 正文铺到唯一的 HDS 导航后方；胶囊和搜索都在该导航的前景，避免被另一层模糊采样。
          List({ scroller: this.scroller }) {
            if (this.activeBoard === undefined) {
              ListItemGroup() {
                if (this.overview) {
                  ListItem() { this.categoryOverview() }
                } else {
                  LazyForEach(this.boardData, (board: RankingBoard) => {
                    ListItem() {
                      RankingSection({ board: board, onChoose: (book: RankingBook): void => this.openMatch(book),
                        onMore: (item: RankingBoard): void => this.openBoard(item) })
                    }
                  }, (board: RankingBoard): string => board.id)
                }
              }
            } else {
              ListItem() {
                Column({ space: 10 }) {
                  Text(this.activeBoard.platformName).fontSize(12).fontColor(AppColor.Brand)
                  Text(this.activeBoard.title).fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
                  Text(this.activeBoard.fetchedAt > 0
                    ? $r('app.string.ranking_updated', new Date(this.activeBoard.fetchedAt).toLocaleString())
                    : $r('app.string.ranking_unavailable')).fontSize(11).fontColor($r('sys.color.font_secondary'))
                  if (this.activeBoard.stale) {
                    Text($r('app.string.ranking_cached')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
                  }
                  Text($r('app.string.ranking_top_count', this.activeBoard.books.length))
                    .fontSize(11).fontColor($r('sys.color.font_tertiary'))
                }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
              }
              LazyForEach(this.fullData, (book: RankingBook) => {
                ListItem() {
                  Column() {
                    RankingBookRow({ book: book, onChoose: (item: RankingBook): void => this.openMatch(item) })
                  }.padding({ left: 24, right: 24 })
                }
              }, (book: RankingBook): string => book.id)
            }
            ListItem() {
              Text($r('app.string.ranking_footer')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
                .textAlign(TextAlign.Center).width('100%').padding({ top: 30, bottom: 120, left: 24, right: 24 })
            }
          }.width('100%').height(this.contentHeight + this.headerRange)
          .contentStartOffset(this.topSafe + 56 + (this.activeBoard === undefined ? 340 : 0))
          .scrollBar(BarState.Off).cachedCount(1)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.posterCover.length > 0 && this.activeBoard === undefined) {
        Stack({ alignContent: Alignment.Top }) {
          Image(this.posterCover).width('100%').height(this.topSafe + 56 + 600)
            .objectFit(ImageFit.Cover).sourceSize({ width: 100, height: 140 }).blur(55).opacity(0.22)
          Column().width('100%').height(this.topSafe + 56 + 600)
            .linearGradient({ angle: 180, colors: [[Color.Transparent, 0.25], [HomeTheme.BgNeutral, 1]] })
        }.width('100%').height(this.topSafe + 56 + 600)
          .translate({ y: -this.headerOffset }).clip(true).hitTestBehavior(HitTestMode.None)
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP])
          .accessibilityLevel('no')
      }
      HdsNavigation() {
        Refresh({ refreshing: $$this.refreshing, builder: this.emptyRefreshIndicator() }) {
          Scroll(this.headerScroller) {
            Column() { this.rankingContent() }
              .width('100%').height(this.contentHeight + this.headerRange).clip(false)
          }.width('100%').height('100%').scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).clip(false)
            .onDidScroll((): void => this.syncHeaderScroll())
        }.onRefreshing(() => this.load(true)).width('100%').height('100%')
        .onOffsetChange((offset: number): void => { this.refreshPullOffset = Math.max(0, offset); })
        .refreshOffset(96).pullDownRatio(0.5)
        .pullToRefresh(this.headerOffset < 0.5)
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: this.navigationTitleContent,
        style: {
          scrollEffectOpts: { scrollEffectType: HdsCompat.scrollEffect },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent },
            contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent },
            contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
          },
          thermoCtrl: true, systemMaterialEffect: HdsCompat.material
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(this.activeBoard === undefined).mode(NavigationMode.Stack)
      .bindToScrollable([this.headerScroller, this.scroller]).backgroundColor(Color.Transparent)
      .systemBarStyle({ statusBarContentColor: WindowUtils.getSystemBarContentColor() },
        { statusBarContentColor: WindowUtils.getSystemBarContentColor() })
      if (this.refreshPullOffset > 0) {
        Column() { this.refreshIndicator() }.width('100%')
          .position({ x: 0, y: this.topSafe + 56 + (this.activeBoard === undefined ? this.posterViewportHeight + 48 : 0) })
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').backgroundColor(HomeTheme.BgNeutral)
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const height: number = Number(size.height);
      if (Number.isFinite(height) && height > 0) this.contentHeight = height;
    })
    .padding({ left: this.leftSafe, right: this.rightSafe })
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: '92%', preferType: SheetType.BOTTOM, showClose: true, dragBar: true,
      backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.SheetBlur, systemMaterial: AppMaterial.Sheet,
      onAppear: (): void => {
        const restoreOffset: number = this.matchOffset;
        this.getUIContext().postFrameCallback(new RankingMatchRestoreFrame((): void => {
          if (this.alive && this.showSheet && restoreOffset > 0) {
            this.matchScroller.scrollTo({ xOffset: 0, yOffset: restoreOffset, animation: false });
          }
        }));
      },
      onDisappear: (): void => {
        if (!this.showSheet && !this.matchSuspended) {
          this.matcher.cancel(); this.matchGeneration++; this.searching = false;
        }
      }
    })
  }
}
