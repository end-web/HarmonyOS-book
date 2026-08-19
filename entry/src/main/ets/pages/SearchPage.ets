import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';
import { AppColor, AppCurve, AppFont, AppMaterial, AppMotion, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import { BookDataSource } from '../utils/BookDataSource';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { KkBiqugeTextSource } from '../service/text/KkBiqugeTextSource';
import { TextSourceError } from '../model/TextReading';
import { PlaybackStore } from '../service/PlaybackStore';
import { WindowUtils } from '../utils/WindowUtils';

const DOMAIN = 0x0000;
const TAG = 'SearchPage';
const SEARCH_HEADER_HEIGHT: number = 56;
const RESULT_TOOLBAR_HEIGHT: number = 48;

class SearchRecommendation {
  readonly label: Resource;
  readonly keyword: string;

  constructor(label: Resource, keyword: string) {
    this.label = label;
    this.keyword = keyword;
  }
}

const SEARCH_RECOMMENDATIONS: SearchRecommendation[] = [
  new SearchRecommendation($r('app.string.search_recommend_mystery'), '悬疑推理'),
  new SearchRecommendation($r('app.string.search_recommend_classics'), '经典名著'),
  new SearchRecommendation($r('app.string.search_recommend_history'), '历史故事'),
  new SearchRecommendation($r('app.string.search_recommend_city'), '都市生活'),
  new SearchRecommendation($r('app.string.search_recommend_fantasy'), '玄幻修仙'),
  new SearchRecommendation($r('app.string.search_recommend_comedy'), '相声评书'),
  new SearchRecommendation($r('app.string.search_recommend_children'), '儿童故事'),
  new SearchRecommendation($r('app.string.search_recommend_biography'), '人物传记')
];

@ComponentV2
export struct SearchPage {
  @Param navStack: NavPathStack = new NavPathStack();

  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local searchTab: number = 0;
  @Local viewMode: number = 0;
  @Local audioBooks: Book[] = [];
  @Local textBooks: Book[] = [];
  @Local audioCount: number = 0;
  @Local textCount: number = 0;
  @Local textSourceNeedsVerification: boolean = false;
  @Local textSourceError: string = '';

  private resultDataSource: BookDataSource = new BookDataSource();
  private resultScroller: Scroller = new Scroller();
  private recommendationScroller: Scroller = new Scroller();
  private searchGen: number = 0;

  aboutToAppear(): void {
    CoverPrefetcher.init();
    BookCard.resetAnimations();
  }

  aboutToDisappear(): void {
    this.searchGen++;
  }

  private clearSearch(): void {
    this.searchGen++;
    this.searching = false;
    this.hasSearched = false;
    this.searchTab = 0;
    this.audioBooks = [];
    this.textBooks = [];
    this.audioCount = 0;
    this.textCount = 0;
    this.textSourceNeedsVerification = false;
    this.textSourceError = '';
    this.resultDataSource.clear();
  }

  private submitRecommendation(item: SearchRecommendation): void {
    this.keyword = item.keyword;
    this.doSearch();
  }

  private async doSearch(): Promise<void> {
    const keyword = this.keyword.trim();
    if (!keyword) {
      this.clearSearch();
      return;
    }
    this.keyword = keyword;
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.hasSearched = true;
    this.searchTab = 0;
    this.audioBooks = [];
    this.textBooks = [];
    this.audioCount = 0;
    this.textCount = 0;
    this.textSourceNeedsVerification = false;
    this.textSourceError = '';
    this.resultDataSource.clear();
    try {
      this.resultScroller.scrollEdge(Edge.Top);
    } catch (_e) {
      // 数据源切换期间滚动容器可能尚未完成布局。
    }
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getEnabledSources();
      if (gen !== this.searchGen) return;
      const seen = new Set<string>();
      const tasks: Promise<void>[] = [];
      for (const source of sources) {
        tasks.push(this.searchOneSource(source, keyword, gen, seen));
      }
      tasks.push(this.searchTextSource(keyword, gen, seen));
      await Promise.all(tasks);
      if (gen !== this.searchGen) return;
      this.audioCount = this.audioBooks.length;
      this.textCount = this.textBooks.length;
      this.refreshVisibleBooks();
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
      this.refreshVisibleBooks();
      this.prefetchCovers(books);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'source search failed [%{public}s]: %{public}s',
        source.bookSourceName, String(e));
    }
  }

  private async searchTextSource(keyword: string, gen: number, seen: Set<string>): Promise<void> {
    try {
      const books = await KkBiqugeTextSource.search(keyword);
      if (gen !== this.searchGen) return;
      const unique: Book[] = [];
      for (const book of books) {
        const dedupeKey = `${book.sourceUrl}\u001f${book.bookUrl}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        SearchCache.put(book);
        unique.push(book);
      }
      this.textBooks = unique;
      this.textCount = unique.length;
      this.refreshVisibleBooks();
      this.prefetchCovers(unique);
    } catch (e) {
      if (e instanceof TextSourceError) {
        this.textSourceNeedsVerification = e.code === 'VERIFY_REQUIRED';
        this.textSourceError = e.message;
      }
      hilog.warn(DOMAIN, TAG, 'text source search failed: %{public}s', String(e));
    }
  }

  private prefetchCovers(books: Book[]): void {
    const covers: string[] = [];
    for (const book of books) {
      if (book.cover && book.cover.startsWith('http')) covers.push(book.cover);
    }
    CoverPrefetcher.prefetchMany(covers, 12);
  }

  private refreshVisibleBooks(): void {
    const visible: Book[] = [];
    if (this.searchTab === 0 || this.searchTab === 1) {
      for (const book of this.audioBooks) visible.push(book);
    }
    if (this.searchTab === 0 || this.searchTab === 2) {
      for (const book of this.textBooks) visible.push(book);
    }
    this.resultDataSource.setBooks(visible);
  }

  private selectSearchTab(index: number): void {
    if (index < 0 || index > 2 || this.searchTab === index) return;
    this.searchTab = index;
    this.refreshVisibleBooks();
  }

  private searchResultToBook(result: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: BookIdentity.onlineAudioBookId(result.sourceUrl || '', result.bookUrl || result.name),
      title: result.name,
      author: result.author || '未知',
      narrator: result.sourceName,
      cover: result.coverUrl || '',
      category: result.kind || '有声书',
      contentType: 'audio',
      intro: result.intro || '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [result.sourceName],
      chapters: emptyChapters,
      bookUrl: result.bookUrl,
      sourceUrl: result.sourceUrl,
      variables: result.variables,
      completed: result.completed
    };
    SearchCache.put(book);
    return book;
  }

  private openBook(book: Book): void {
    SearchCache.put(book);
    if (PlaybackStore.getInstance().isCurrentBook(book.id)) {
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', book.id, false);
      });
      return;
    }
    this.navStack.pushPathByName('detail', book.id);
  }

  @Builder
  buildRecommendation(item: SearchRecommendation) {
    Row({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([HomeTheme.Accent])
      Text(item.label)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .height(44)
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
    .margin({ bottom: AppSpace.Sm })
    .borderRadius(AppRadius.Sm)
    .systemMaterial(AppMaterial.InteractiveThin)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.submitRecommendation(item))
  }

  @Builder
  buildRecommendations() {
    Scroll(this.recommendationScroller) {
      Column({ space: AppSpace.Md }) {
        Text($r('app.string.search_recommendations'))
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(SEARCH_RECOMMENDATIONS, (item: SearchRecommendation) => {
            this.buildRecommendation(item)
          }, (item: SearchRecommendation) => item.keyword)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Md })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .padding({ top: WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT })
  }

  @Builder
  buildSearchTypeTab(label: Resource, index: number) {
    Row({ space: AppSpace.Xxs }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.searchTab === index ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
        .fontWeight(this.searchTab === index ? FontWeight.Medium : FontWeight.Regular)
      Text((index === 0 ? this.audioCount + this.textCount :
        (index === 1 ? this.audioCount : this.textCount)).toString())
        .fontSize(11)
        .fontColor(this.searchTab === index ? HomeTheme.Accent : $r('sys.color.font_tertiary'))
    }
    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
    .borderRadius(AppRadius.Pill)
    .backgroundColor(this.searchTab === index ? HomeTheme.AccentSoft : Color.Transparent)
    .onClick(() => this.selectSearchTab(index))
  }

  @Builder
  buildResultToolbar() {
    Row() {
      Row({ space: AppSpace.Xxs }) {
        this.buildSearchTypeTab($r('app.string.search_type_all'), 0)
        this.buildSearchTypeTab($r('app.string.search_type_audio'), 1)
        this.buildSearchTypeTab($r('app.string.search_type_text'), 2)
      }
      .padding({ left: 4, right: 4, top: 3, bottom: 3 })
      .borderRadius(AppRadius.Pill)
      .systemMaterial(AppMaterial.InteractiveThin)

      if (this.searching) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppColor.Brand)
          .margin({ left: AppSpace.Xs })
      }

      Blank()

      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.viewMode === 0 ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_primary')])
      }
        .width(40)
        .height(40)
        .borderRadius(AppRadius.Pill)
        .systemMaterial(AppMaterial.InteractiveThin)
        .onClick(() => {
          this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard }, () => {
            this.viewMode = this.viewMode === 0 ? 1 : 0;
            try {
              this.resultScroller.scrollEdge(Edge.Top);
            } catch (_e) {
              // 切换布局的同一帧可能暂时没有可滚动节点。
            }
          });
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Sm }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(AppColor.Brand)
      Text($r('app.string.search_loading'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.search_no_result'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Xs })
      Text($r('app.string.search_try_another'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
      if (this.textSourceNeedsVerification) {
        Text($r('app.string.search_verify_text_source'))
          .fontSize(AppFont.Body)
          .fontColor(HomeTheme.Accent)
          .fontWeight(FontWeight.Medium)
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
          .margin({ top: AppSpace.Xs })
          .borderRadius(AppRadius.Pill)
          .systemMaterial(AppMaterial.InteractiveThin)
          .onClick(() => this.navStack.pushPathByName('verifyTextSource', null))
      } else if (this.textSourceError) {
        Text(this.textSourceError)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .margin({ top: AppSpace.Xs, left: AppSpace.Xl, right: AppSpace.Xl })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGridResults() {
    Grid(this.resultScroller) {
      LazyForEach(this.resultDataSource, (book: Book, index: number) => {
        GridItem() {
          BookCard({
            book: book,
            indexHint: index,
            onTap: () => this.openBook(book)
          })
        }
      }, (book: Book) => book.id)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(AppSpace.Sm)
    .rowsGap(AppSpace.Md)
    .cachedCount(6)
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({
      left: AppSpace.Md,
      right: AppSpace.Md,
      top: WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT + RESULT_TOOLBAR_HEIGHT + AppSpace.Sm,
      bottom: WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg
    })
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          CoverImage({
            url: book.cover,
            imgWidth: 92,
            aspectRatioValue: 1,
            radius: AppRadius.Md,
            decodeW: 276,
            decodeH: 276,
            highPriority: false
          })
        } else {
          Image($r('app.media.app_icon_legacy'))
            .width(92)
            .aspectRatio(1)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
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

      Column({ space: AppSpace.Xxs }) {
        Text(book.title)
          .fontSize(AppFont.BodyL)
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
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
    .onClick(() => this.openBook(book))
  }

  @Builder
  buildListResults() {
    List({ scroller: this.resultScroller, space: AppSpace.Xs }) {
      // 与首页列表一致：顶部避让区作为可滚动首项，滚动后结果可自然进入浮层下方。
      ListItem() {
        Column()
          .width('100%')
          .height(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
            RESULT_TOOLBAR_HEIGHT + AppSpace.Sm)
      }
      LazyForEach(this.resultDataSource, (book: Book) => {
        ListItem() {
          this.buildListItem(book)
        }
      }, (book: Book) => book.id)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(6)
    .clip(false)
    .padding({
      left: AppSpace.Md,
      right: AppSpace.Md
    })
  }

  @Builder
  buildSearchHeader() {
    Column() {
      Column()
        .width('100%')
        .height(WindowUtils.getStatusBarHeightVp())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      Row({ space: AppSpace.Xs }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('sys.color.icon_primary')])
        }
          .width(40)
          .height(40)
          .borderRadius(AppRadius.Pill)
          .systemMaterial(AppMaterial.InteractiveThin)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .onClick(() => this.navStack.pop())

        Search({ value: this.keyword, placeholder: $r('app.string.search_placeholder') })
          .searchButton($r('app.string.search_action'), { fontColor: HomeTheme.Accent })
          .placeholderColor($r('sys.color.font_tertiary'))
          .placeholderFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .textFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Color.Transparent)
          .systemMaterial(AppMaterial.InteractiveClean)
          .borderRadius(AppRadius.Pill)
          .id('search-page-input')
          .focusable(true)
          .defaultFocus(true)
          .onAppear(() => {
            try {
              this.getUIContext().getFocusController().requestFocus('search-page-input');
            } catch (_e) {
              // 页面转场尚未完成时请求可能失败，defaultFocus 会在下一帧兜底。
            }
          })
          .onSubmit(() => this.doSearch())
          .onChange((value: string) => {
            this.keyword = value;
            if (value.length === 0 && this.hasSearched) this.clearSearch();
          })
      }
      .width('100%')
      .height(SEARCH_HEADER_HEIGHT)
      .padding({ left: AppSpace.Xs, right: AppSpace.Md })
      .alignItems(VerticalAlign.Center)
      if (this.hasSearched) {
        this.buildResultToolbar()
      }
    }
    .width('100%')
    .height(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
      (this.hasSearched ? RESULT_TOOLBAR_HEIGHT : 0))
    .backgroundColor(Color.Transparent)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HomeTheme.BgNeutral)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      HdsNavigation() {
        Column() {
          if (!this.hasSearched) {
            this.buildRecommendations()
          } else if (this.resultDataSource.totalCount() === 0 && this.searching) {
            this.buildLoadingState()
          } else if (this.resultDataSource.totalCount() === 0) {
            this.buildEmptyState()
          } else {
            if (this.viewMode === 0) {
              this.buildGridResults()
            } else {
              this.buildListResults()
            }
          }
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: { mainTitle: '' }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
          },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary'),
                subTitleColor: $r('sys.color.font_secondary')
              },
              backIconStyle: { iconColor: Color.Transparent }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary'),
                subTitleColor: $r('sys.color.font_secondary')
              },
              backIconStyle: { iconColor: Color.Transparent }
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
      .bindToScrollable([this.resultScroller, this.recommendationScroller])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .clip(false)
      .backgroundColor(Color.Transparent)

      this.buildSearchHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.BgNeutral)
  }
}
