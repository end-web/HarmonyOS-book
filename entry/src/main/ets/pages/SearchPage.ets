import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';
import { AppColor, AppCurve, AppFont, AppMaterial, AppMotion, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, HomeBlockSection, SearchResult } from '../model/BookSource';
import { LocalRuleSource, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import { BookDataSource } from '../utils/BookDataSource';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { PlaybackStore } from '../service/PlaybackStore';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';
import { TingYouSourceIdentity } from '../service/rulesource/tingyou/TingYouSourceIdentity';

const DOMAIN = 0x0000;
const TAG = 'SearchPage';
const LOCAL_RULE_SEARCH_CONCURRENCY: number = 6;
const LOCAL_RULE_COVER_CONCURRENCY: number = 3;
const LOCAL_RULE_COVER_LIMIT: number = 12;
const SEARCH_COVER_ASPECT_RATIO: number = 0.75;
const SEARCH_HEADER_HEIGHT: number = 56;
const RESULT_TOOLBAR_HEIGHT: number = 48;
const SEARCH_FOCUS_DELAY_MS: number = 320;
const SEARCH_RECOMMENDATION_COUNT: number = 5;
const SEARCH_RECOMMENDATION_SOURCE_LIMIT: number = 6;
const SEARCH_RECOMMENDATION_BATCH_SIZE: number = 3;
const SEARCH_HISTORY_DELETE_COLOR: string = '#D03050';
const SEARCH_RECOMMENDATION_KEYWORDS: string[] = [
  '斗破苍穹', '三体', '凡人修仙传', '诡秘之主', '红楼梦', '盗墓笔记', '西游记', '庆余年'
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
  @Local visibleResultCount: number = 0;
  @Local searchHistory: string[] = [];
  @Local recommendationBooks: Book[] = [];
  @Local recommendationsLoading: boolean = false;

  private resultDataSource: BookDataSource = new BookDataSource();
  private resultScroller: Scroller = new Scroller();
  private recommendationScroller: Scroller = new Scroller();
  private searchGen: number = 0;
  private recommendationGen: number = 0;
  private focusTimerId: number = -1;
  private initialFocusRequested: boolean = false;

  aboutToAppear(): void {
    CoverPrefetcher.init();
    BookCard.resetAnimations();
    this.loadSearchHistory();
    this.loadRecommendations();
  }

  aboutToDisappear(): void {
    this.searchGen++;
    this.recommendationGen++;
    this.cancelSearchFocus();
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      this.searchHistory = await PreferenceService.getSearchHistory();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load search history failed: %{public}s', String(e));
    }
  }

  private scheduleSearchFocus(): void {
    if (this.initialFocusRequested) {
      return;
    }
    this.initialFocusRequested = true;
    this.focusTimerId = setTimeout((): void => {
      this.focusTimerId = -1;
      try {
        this.getUIContext().getFocusController().requestFocus('search-page-input');
      } catch (_e) {
        // 页面已离开或输入框尚未挂载时忽略，用户仍可点击输入框聚焦。
      }
    }, SEARCH_FOCUS_DELAY_MS);
  }

  private cancelSearchFocus(): void {
    if (this.focusTimerId < 0) {
      return;
    }
    clearTimeout(this.focusTimerId);
    this.focusTimerId = -1;
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
    this.visibleResultCount = 0;
    this.resultDataSource.clear();
  }

  private submitHistoryKeyword(keyword: string): void {
    this.keyword = keyword;
    this.doSearch();
  }

  private async removeHistoryItem(keyword: string): Promise<void> {
    try {
      await PreferenceService.removeSearchHistory(keyword);
      this.searchHistory = await PreferenceService.getSearchHistory();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'remove search history failed: %{public}s', String(e));
    }
  }

  private async clearAllHistory(): Promise<void> {
    try {
      await PreferenceService.clearSearchHistory();
      this.searchHistory = [];
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'clear search history failed: %{public}s', String(e));
    }
  }

  private async loadRecommendations(): Promise<void> {
    this.recommendationGen++;
    const generation = this.recommendationGen;
    this.recommendationsLoading = true;
    try {
      const sources = await SourceDataService.getEnabledSources();
      if (generation !== this.recommendationGen) return;
      const orderedSources = this.shuffleSources(sources);
      const books: Book[] = [];
      const seen = new Set<string>();

      for (const source of orderedSources) {
        if (!TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl)) continue;
        try {
          const blocks = await BookSourceService.getHomeBlocks(source);
          if (generation !== this.recommendationGen) return;
          this.appendHomeRecommendationBooks(source, blocks, books, seen);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'load source home recommendations failed: %{public}s', String(error));
        }
        break;
      }

      if (books.length < SEARCH_RECOMMENDATION_COUNT) {
        await this.appendSearchRecommendationBooks(orderedSources, books, seen, generation);
      }
      if (generation !== this.recommendationGen) return;
      this.recommendationBooks = this.pickRecommendationBooks(books);
      this.prefetchCovers(this.recommendationBooks);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'load recommendations failed: %{public}s', String(error));
      if (generation === this.recommendationGen) this.recommendationBooks = [];
    } finally {
      if (generation === this.recommendationGen) this.recommendationsLoading = false;
    }
  }

  private shuffleSources(sources: BookSource[]): BookSource[] {
    const shuffled = sources.slice();
    for (let index = shuffled.length - 1; index > 0; index--) {
      const randomIndex = Math.floor(Math.random() * (index + 1));
      const current = shuffled[index];
      shuffled[index] = shuffled[randomIndex];
      shuffled[randomIndex] = current;
    }
    return shuffled;
  }

  private appendHomeRecommendationBooks(source: BookSource, blocks: HomeBlockSection[],
    books: Book[], seen: Set<string>): void {
    const fallbackType: 'audio' | 'text' = source.bookSourceType === 0 || source.bookSourceType === 3
      ? 'text' : 'audio';
    for (const block of blocks) {
      for (const result of block.books) {
        const book = this.searchResultToBook(result, result.contentType ?? fallbackType);
        this.appendRecommendationBook(book, books, seen);
      }
    }
  }

  private async appendSearchRecommendationBooks(sources: BookSource[], books: Book[], seen: Set<string>,
    generation: number): Promise<void> {
    const readySources: BookSource[] = [];
    for (const source of sources) {
      if (source instanceof LocalRuleSource && source.validationStatus === LocalRuleSourceStatus.READY) {
        readySources.push(source);
      }
    }
    const sourcePool = readySources.length > 0 ? readySources : sources;
    const candidates: BookSource[] = [];
    for (const source of sourcePool) {
      candidates.push(source);
      if (candidates.length >= SEARCH_RECOMMENDATION_SOURCE_LIMIT) break;
    }
    for (let start = 0; start < candidates.length; start += SEARCH_RECOMMENDATION_BATCH_SIZE) {
      if (generation !== this.recommendationGen) return;
      const tasks: Promise<Book[]>[] = [];
      const end = Math.min(candidates.length, start + SEARCH_RECOMMENDATION_BATCH_SIZE);
      for (let index = start; index < end; index++) {
        const keywordIndex = Math.floor(Math.random() * SEARCH_RECOMMENDATION_KEYWORDS.length);
        tasks.push(this.loadSourceRecommendationBooks(candidates[index],
          SEARCH_RECOMMENDATION_KEYWORDS[keywordIndex]));
      }
      const batches = await Promise.all(tasks);
      if (generation !== this.recommendationGen) return;
      for (const batch of batches) {
        for (const book of batch) this.appendRecommendationBook(book, books, seen);
      }
      if (books.length >= SEARCH_RECOMMENDATION_COUNT * 2) return;
    }
  }

  private async loadSourceRecommendationBooks(source: BookSource, keyword: string): Promise<Book[]> {
    try {
      const results = await BookSourceService.searchBooks(source, keyword);
      const fallbackType: 'audio' | 'text' = source.bookSourceType === 0 || source.bookSourceType === 3
        ? 'text' : 'audio';
      const books: Book[] = [];
      for (const result of results) {
        books.push(this.searchResultToBook(result, result.contentType ?? fallbackType));
      }
      return books;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'recommendation source failed [%{public}s]: %{public}s',
        source.bookSourceName, String(error));
      return [];
    }
  }

  private appendRecommendationBook(book: Book, books: Book[], seen: Set<string>): void {
    const key = `${book.sourceUrl}\u001f${book.bookUrl}`;
    if (book.title.trim().length === 0 || book.bookUrl.trim().length === 0 || seen.has(key)) return;
    seen.add(key);
    books.push(book);
  }

  private pickRecommendationBooks(books: Book[]): Book[] {
    const shuffled = books.slice();
    for (let index = shuffled.length - 1; index > 0; index--) {
      const randomIndex = Math.floor(Math.random() * (index + 1));
      const current = shuffled[index];
      shuffled[index] = shuffled[randomIndex];
      shuffled[randomIndex] = current;
    }
    return shuffled.slice(0, SEARCH_RECOMMENDATION_COUNT);
  }

  private async doSearch(): Promise<void> {
    const keyword = this.keyword.trim();
    if (!keyword) {
      this.clearSearch();
      return;
    }
    this.keyword = keyword;
    PreferenceService.addSearchHistory(keyword).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'save search history failed: %{public}s', e.message);
    });
    this.loadSearchHistory().catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'reload search history failed: %{public}s', e.message);
    });
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.hasSearched = true;
    this.searchTab = 0;
    this.audioBooks = [];
    this.textBooks = [];
    this.audioCount = 0;
    this.textCount = 0;
    this.visibleResultCount = 0;
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
      const localSources: BookSource[] = [];
      for (const source of sources) {
        if (SourceDataService.isLocalRuleSource(source.bookSourceUrl)) {
          localSources.push(source);
        } else {
          tasks.push(this.searchOneSource(source, keyword, gen, seen));
        }
      }
      tasks.push(this.searchLocalSources(localSources, keyword, gen, seen));
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

  private async searchLocalSources(sources: BookSource[], keyword: string, gen: number,
    seen: Set<string>): Promise<void> {
    for (let start = 0; start < sources.length; start += LOCAL_RULE_SEARCH_CONCURRENCY) {
      if (gen !== this.searchGen) return;
      const batch: Promise<void>[] = [];
      const end = Math.min(sources.length, start + LOCAL_RULE_SEARCH_CONCURRENCY);
      for (let index = start; index < end; index++) {
        batch.push(this.searchOneSource(sources[index], keyword, gen, seen));
      }
      await Promise.all(batch);
    }
  }

  private async searchOneSource(source: BookSource, keyword: string, gen: number,
    seen: Set<string>): Promise<void> {
    try {
      const results = await BookSourceService.searchBooks(source, keyword);
      if (gen !== this.searchGen) return;
      const books: Book[] = [];
      const audioBooks: Book[] = [];
      const textBooks: Book[] = [];
      const fallbackContentType: 'audio' | 'text' = source.bookSourceType === 0 || source.bookSourceType === 3
        ? 'text' : 'audio';
      for (const item of results) {
        const dedupeKey = `${item.sourceUrl}\u001f${item.bookUrl}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        const contentType: 'audio' | 'text' = item.contentType ?? fallbackContentType;
        const book = this.searchResultToBook(item, contentType);
        books.push(book);
        if (contentType === 'text') {
          textBooks.push(book);
        } else {
          audioBooks.push(book);
        }
      }
      if (books.length === 0) return;
      if (textBooks.length > 0) {
        this.textBooks = this.textBooks.concat(textBooks);
        this.textCount = this.textBooks.length;
      }
      if (audioBooks.length > 0) {
        this.audioBooks = this.audioBooks.concat(audioBooks);
        this.audioCount = this.audioBooks.length;
      }
      this.refreshVisibleBooks();
      this.prefetchCovers(books);
      if (source instanceof LocalRuleSource && source.ruleSearch.coverUrl.trim().length === 0 &&
        source.ruleBookInfo.coverUrl.trim().length > 0) {
        this.hydrateMissingLocalRuleCovers(source, books, gen).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'cover hydration failed [%{public}s]: %{public}s',
            source.bookSourceName, error.message);
        });
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'source search failed [%{public}s]: %{public}s',
        source.bookSourceName, String(e));
    }
  }

  private prefetchCovers(books: Book[]): void {
    const covers: string[] = [];
    for (const book of books) {
      if (book.cover && book.cover.startsWith('http')) covers.push(book.cover);
    }
    CoverPrefetcher.prefetchMany(covers, 12);
  }

  private async hydrateMissingLocalRuleCovers(source: LocalRuleSource, books: Book[],
    gen: number): Promise<void> {
    const candidates: Book[] = [];
    for (const book of books) {
      if (book.cover.trim().length > 0 || book.bookUrl.trim().length === 0) continue;
      candidates.push(book);
      if (candidates.length >= LOCAL_RULE_COVER_LIMIT) break;
    }
    for (let start = 0; start < candidates.length; start += LOCAL_RULE_COVER_CONCURRENCY) {
      if (gen !== this.searchGen) return;
      const tasks: Promise<Book | undefined>[] = [];
      const end = Math.min(candidates.length, start + LOCAL_RULE_COVER_CONCURRENCY);
      for (let index = start; index < end; index++) {
        tasks.push(this.hydrateOneLocalRuleCover(source, candidates[index], gen));
      }
      const hydratedBooks = await Promise.all(tasks);
      if (gen !== this.searchGen) return;
      for (const hydratedBook of hydratedBooks) {
        if (hydratedBook !== undefined) this.replaceSearchBook(hydratedBook);
      }
      this.refreshVisibleBooks();
    }
    this.prefetchCovers(candidates);
  }

  private async hydrateOneLocalRuleCover(source: LocalRuleSource, book: Book,
    gen: number): Promise<Book | undefined> {
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
    if (gen !== this.searchGen || info === null) return undefined;
    const coverUrl = info.coverUrl.trim();
    if (coverUrl.length === 0) return undefined;
    book.cover = coverUrl;
    const hydratedBook = this.cloneBook(book);
    SearchCache.put(hydratedBook);
    return hydratedBook;
  }

  private replaceSearchBook(book: Book): void {
    const audioBooks = this.audioBooks.slice();
    let audioChanged = false;
    for (let index = 0; index < audioBooks.length; index++) {
      if (audioBooks[index].id !== book.id) continue;
      audioBooks[index] = book;
      audioChanged = true;
      break;
    }
    if (audioChanged) this.audioBooks = audioBooks;

    const textBooks = this.textBooks.slice();
    let textChanged = false;
    for (let index = 0; index < textBooks.length; index++) {
      if (textBooks[index].id !== book.id) continue;
      textBooks[index] = book;
      textChanged = true;
      break;
    }
    if (textChanged) this.textBooks = textBooks;
  }

  private cloneBook(book: Book): Book {
    const cloned: Book = {
      id: book.id,
      contentType: book.contentType,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      cover: book.cover,
      category: book.category,
      intro: book.intro,
      totalDuration: book.totalDuration,
      chapterCount: book.chapterCount,
      rating: book.rating,
      tags: book.tags,
      chapters: book.chapters,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      completed: book.completed
    };
    return cloned;
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
    this.visibleResultCount = visible.length;
  }

  private selectSearchTab(index: number): void {
    if (index < 0 || index > 2 || this.searchTab === index) return;
    this.searchTab = index;
    this.refreshVisibleBooks();
  }

  private searchResultToBook(result: SearchResult, contentType: 'audio' | 'text'): Book {
    const emptyChapters: Chapter[] = [];
    const id = contentType === 'text'
      ? BookIdentity.onlineTextBookId(result.sourceUrl || '', result.bookUrl || result.name)
      : BookIdentity.onlineAudioBookId(result.sourceUrl || '', result.bookUrl || result.name);
    const book: Book = {
      id,
      title: result.name,
      author: result.author || '未知',
      narrator: result.sourceName,
      cover: result.coverUrl || '',
      category: result.kind || (contentType === 'text' ? '电子书' : '有声书'),
      contentType,
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
  buildHistoryItem(keyword: string) {
    Row({ space: AppSpace.Xxs }) {
      Text(keyword)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 144 })
        .height(32)
        .padding({ left: AppSpace.Sm })
        .onClick(() => this.submitHistoryKeyword(keyword))

      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(12)
          .fontColor([SEARCH_HISTORY_DELETE_COLOR])
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .borderRadius(AppRadius.Pill)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
      .onClick(() => this.removeHistoryItem(keyword))
    }
    .height(32)
    .padding({ right: 2 })
    .borderRadius(AppRadius.Pill)
    .backgroundColor(Color.Transparent)
    .systemMaterial(AppMaterial.InteractiveThin)
    .margin({ right: AppSpace.Xs, bottom: AppSpace.Xs })
  }

  @Builder
  buildSearchHistory() {
    if (this.searchHistory.length > 0) {
      Column({ space: AppSpace.Sm }) {
        Row() {
          Text($r('app.string.search_history'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)

          Text($r('app.string.search_clear_history'))
            .fontSize(AppFont.Caption)
            .fontColor(HomeTheme.Accent)
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 4, bottom: 4 })
            .borderRadius(AppRadius.Xs)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
            .onClick(() => this.clearAllHistory())
        }
        .width('100%')

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.searchHistory, (keyword: string) => {
            this.buildHistoryItem(keyword)
          }, (keyword: string) => keyword)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: AppSpace.Md })
    }
  }

  @Builder
  buildRecommendations() {
    Scroll(this.recommendationScroller) {
      Column({ space: AppSpace.Md }) {
        this.buildSearchHistory()

        Text($r('app.string.search_recommendations'))
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        if (this.recommendationsLoading && this.recommendationBooks.length === 0) {
          Row({ space: AppSpace.Xs }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(AppColor.Brand)
            Text($r('app.string.search_recommend_loading'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .height(72)
          .justifyContent(FlexAlign.Center)
        } else if (this.recommendationBooks.length === 0) {
          Text($r('app.string.search_recommend_empty'))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .height(56)
            .textAlign(TextAlign.Center)
        } else {
          Column() {
            ForEach(this.recommendationBooks, (book: Book) => {
              this.buildListItem(book)
            }, (book: Book) => book.id)
          }
          .width('100%')
        }
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
            coverAspectRatio: SEARCH_COVER_ASPECT_RATIO,
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
            aspectRatioValue: SEARCH_COVER_ASPECT_RATIO,
            radius: AppRadius.Md,
            decodeW: 276,
            decodeH: 368,
            highPriority: false
          })
        } else {
          Image($r('app.media.app_icon_legacy'))
            .width(92)
            .aspectRatio(SEARCH_COVER_ASPECT_RATIO)
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
          .onAppear(() => this.scheduleSearchFocus())
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
    .backgroundColor(this.hasSearched ? Color.Transparent : HomeTheme.BgNeutral)
  }

  @Builder
  buildSearchBody() {
    if (!this.hasSearched) {
      this.buildRecommendations()
    } else if (this.visibleResultCount === 0 && this.searching) {
      this.buildLoadingState()
    } else if (this.visibleResultCount === 0) {
      this.buildEmptyState()
    } else {
      if (this.viewMode === 0) {
        this.buildGridResults()
      } else {
        this.buildListResults()
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HomeTheme.BgNeutral)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.hasSearched) {
        HdsNavigation() {
          Column() {
            this.buildSearchBody()
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
      } else {
        Column() {
          this.buildSearchBody()
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(HomeTheme.BgNeutral)
      }

      this.buildSearchHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.BgNeutral)
  }
}
