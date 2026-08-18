import { common } from '@kit.AbilityKit';
import { display, SymbolGlyphModifier } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { readerCore } from '@hms.core.readerservice.readerComponent';
import { HdsAnimationMode, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { EpubReaderComponent } from '../components/EpubReaderComponent';
import { Book, Chapter } from '../model/Book';
import { TextReadingPosition, TextReadingSettings } from '../model/TextReading';
import { DataService } from '../service/DataService';
import { KkBiqugeTextSource } from '../service/text/KkBiqugeTextSource';
import { OnlineTextBookParserHandler } from '../service/text/OnlineTextBookParserHandler';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppSpace } from '../theme/Theme';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';

const READER_LOG_DOMAIN: number = 0x0000;
const READER_LOG_TAG: string = 'ReaderPage';
const READER_BACKGROUND: string = '#F5F2EA';
const READER_PRIMARY_COLOR: string = '#2D2925';
const READER_SECONDARY_COLOR: string = '#6F675E';
const READER_DIVIDER_COLOR: string = '#1A6F675E';
const READER_CURRENT_CHAPTER_BACKGROUND: string = '#14FFC15C';
const READER_FLOATING_BOTTOM: number = 4;
const READER_MIN_SAFE_BOTTOM: number = 8;

@ComponentV2
export struct ReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param targetResourceIndex: number = -1;
  @Param targetDomPos: string = '';
  @Local book: Book | null = null;
  @Local loading: boolean = true;
  @Local readerError: string = '';
  @Local currentResourceIndex: number = 0;
  @Local currentChapterTitle: string = '';
  @Local fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Local lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Local readerKitReady: boolean = false;
  @Local jumpingResourceIndex: number = -1;
  @Local currentTabIndex: number = 0;
  @Local readerBarVisible: boolean = true;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  private currentPosition: TextReadingPosition | null = null;
  private context: common.UIAbilityContext | null = null;
  private leaving: boolean = false;
  private tabController: HdsTabsController = new HdsTabsController();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private readerKitController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  private readerKitHandler: bookParser.BookParserHandler | null = null;
  private readerSetting: readerCore.ReaderSetting | null = null;
  private readerKitDomPos: string = '';
  private readerKitPageOffset: number = 0;
  private readerSettingsRefreshTimerId: number = -1;
  private safeAreaChangeHandler: (topVp: number, bottomVp: number) => void =
    (topVp: number, bottomVp: number): void => {
      const changed = Math.abs(this.topSafeVp - topVp) >= 0.1 ||
        Math.abs(this.bottomSafeVp - bottomVp) >= 0.1;
      if (!changed) return;
      this.topSafeVp = topVp;
      this.bottomSafeVp = bottomVp;
      this.scheduleReaderSettingsRefresh();
    };

  aboutToAppear(): void {
    this.leaving = false;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowUtils.setStatusBarLight(false);
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.refreshAvoidArea();
    this.initializeReader();
  }

  aboutToDisappear(): void {
    this.leaving = true;
    this.cancelReaderSettingsRefresh();
    this.saveProgress();
    this.saveReadingSettings();
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.setStatusBarLight(false);
  }

  private cancelReaderSettingsRefresh(): void {
    if (this.readerSettingsRefreshTimerId !== -1) {
      clearTimeout(this.readerSettingsRefreshTimerId);
      this.readerSettingsRefreshTimerId = -1;
    }
  }

  /** 合并旋转/窗口缩放期间的多次尺寸回调，避免 ReaderKit 重复分页。 */
  private scheduleReaderSettingsRefresh(): void {
    this.cancelReaderSettingsRefresh();
    this.readerSettingsRefreshTimerId = setTimeout((): void => {
      this.readerSettingsRefreshTimerId = -1;
      if (this.leaving) return;
      this.applyReadingSettings();
    }, 120);
  }

  private handleViewportSizeChange(_oldValue: SizeOptions, newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    this.scheduleReaderSettingsRefresh();
  }

  private async initializeReader(): Promise<void> {
    if (!this.context || !this.bookId) {
      this.failReader('电子书参数无效');
      return;
    }
    this.loading = true;
    this.readerError = '';
    try {
      await this.restoreReadingSettings();
      if (this.leaving) return;
      let value = SearchCache.get(this.bookId);
      if (!value) value = await DataService.getBookById(this.context, this.bookId) ?? null;
      if (!value) {
        this.failReader('未找到电子书');
        return;
      }
      if (!this.canOpenWithReaderKit(value)) {
        this.failReader('未找到电子书');
        return;
      }
      if (this.bookContentType(value) === 'text' && value.chapters.length === 0) {
        value = await KkBiqugeTextSource.loadBook(value);
      }
      if (this.bookContentType(value) === 'text' && value.chapters.length === 0) {
        this.failReader('这本书暂时没有可读章节');
        return;
      }
      if (this.leaving) return;
      this.book = value;
      this.chapterDataSource.setChapters(value.chapters);
      SearchCache.put(value);
      const startPosition = await this.resolveStartPosition(value);
      if (this.leaving) return;
      await this.prepareReaderKitReader(value, startPosition);
    } catch (e) {
      this.failReader(e instanceof Error ? e.message : String(e));
    }
  }

  private canOpenWithReaderKit(book: Book): boolean {
    if (this.bookContentType(book) === 'text') return true;
    return this.resolveEpubFilePath(book).length > 0;
  }

  private async resolveStartPosition(book: Book): Promise<TextReadingPosition> {
    if (!this.context) return TextReadingPosition.of(book.id, 0, '', 0, this.chapterTitle(0));
    if (this.targetResourceIndex >= 0) {
      const target = this.clampResourceIndex(this.targetResourceIndex, book.chapters.length);
      return TextReadingPosition.atChar(book.id, target, this.targetDomPos, 0, 0, this.chapterTitle(target));
    }
    const saved = await TextReadingProgressService.get(this.context, book.id);
    if (saved) {
      const titleIndex = this.chapterIndexByTitle(book, saved.chapterTitle);
      if (titleIndex >= 0) {
        return TextReadingPosition.atChar(
          book.id, titleIndex, saved.domPos, saved.charOffset, saved.pageOffset, saved.chapterTitle);
      }
      const fallbackIndex = this.clampResourceIndex(saved.resourceIndex, book.chapters.length);
      return TextReadingPosition.atChar(
        book.id, fallbackIndex, saved.domPos, saved.charOffset, saved.pageOffset, this.chapterTitle(fallbackIndex));
    }
    return TextReadingPosition.atChar(book.id, 0, '', 0, 0, this.chapterTitle(0));
  }

  private bookContentType(book: Book): string {
    return book.contentType ?? '';
  }

  private async prepareReaderKitReader(book: Book, startPosition: TextReadingPosition): Promise<void> {
    this.readerKitReady = false;
    this.readerKitController = new readerCore.ReaderComponentController();
    this.readerKitHandler = await this.createReaderKitHandler(book);
    const count = Math.max(1, book.chapters.length);
    const resourceIndex = this.clampResourceIndex(startPosition.resourceIndex, count);
    const onlineHandler = this.readerKitHandler;
    if (onlineHandler instanceof OnlineTextBookParserHandler) {
      // Reader Kit 的绝对资源路径接口是同步的，启动前必须先把当前章节写入沙箱。
      await onlineHandler.prepareSpineItem(resourceIndex);
    }
    this.readerSetting = this.createReaderSetting();
    this.currentResourceIndex = resourceIndex;
    this.readerKitDomPos = startPosition.domPos;
    this.readerKitPageOffset = startPosition.pageOffset;
    this.currentChapterTitle = this.chapterTitle(resourceIndex);
    this.currentPosition = TextReadingPosition.atChar(
      book.id, resourceIndex, this.readerKitDomPos, 0, this.readerKitPageOffset, this.currentChapterTitle);
    this.loading = false;
  }

  private async createReaderKitHandler(book: Book): Promise<bookParser.BookParserHandler> {
    const epubPath = this.resolveEpubFilePath(book);
    if (epubPath.length > 0) {
      return await bookParser.getDefaultHandler(epubPath);
    }
    if (this.bookContentType(book) === 'text') {
      const currentContext = this.context;
      if (currentContext === null) throw new Error('阅读上下文无效');
      return new OnlineTextBookParserHandler(book,
        `${currentContext.filesDir}/reader_${this.safePathId(book.id)}`);
    }
    throw new Error('电子书文件路径为空');
  }

  private resolveEpubFilePath(book: Book): string {
    const variables = book.variables;
    if (variables !== undefined) {
      const filePath = variables['filePath'];
      if (filePath !== undefined && filePath.length > 0) return this.normalizeFilePath(filePath);
      const epubPath = variables['epubPath'];
      if (epubPath !== undefined && epubPath.length > 0) return this.normalizeFilePath(epubPath);
    }
    if (book.bookUrl.startsWith('/') || book.bookUrl.startsWith('file://')) {
      return this.normalizeFilePath(book.bookUrl);
    }
    if (book.sourceUrl.startsWith('/') || book.sourceUrl.startsWith('file://')) {
      return this.normalizeFilePath(book.sourceUrl);
    }
    return '';
  }

  private normalizeFilePath(path: string): string {
    if (path.startsWith('file://')) return path.substring(7);
    return path;
  }

  private safePathId(value: string): string {
    return value.replace(new RegExp('[^A-Za-z0-9_.-]', 'g'), '_');
  }

  private retryReader(): void {
    this.initializeReader();
  }

  private saveProgress(): void {
    if (!this.context || !this.currentPosition) return;
    TextReadingProgressService.save(this.context, this.currentPosition).catch((_e: Error): void => {});
  }

  private async restoreReadingSettings(): Promise<void> {
    const currentContext = this.context;
    if (currentContext === null) return;
    try {
      const settings = await TextReadingSettingsService.get(currentContext);
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'restore settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.fontSize = TextReadingSettings.FONT_SIZE_DEFAULT;
      this.lineHeight = TextReadingSettings.LINE_HEIGHT_DEFAULT;
    }
  }

  private saveReadingSettings(): void {
    const currentContext = this.context;
    if (currentContext === null) return;
    const settings = TextReadingSettings.of(this.fontSize, this.lineHeight);
    TextReadingSettingsService.save(currentContext, settings).catch((e: Error): void => {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'save settings failed: %{public}s', e.message);
    });
  }

  private createReaderSetting(): readerCore.ReaderSetting {
    const currentDisplay = display.getDefaultDisplaySync();
    const scaledDensity = currentDisplay.scaledDensity > 0 ? currentDisplay.scaledDensity : 1;
    const density = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 1;
    const verticalSafePx = (this.topSafeVp + this.bottomSafeVp) * density;
    const pageConfig: readerCore.ReaderSetting = {
      fontName: '系统字体',
      fontSize: TextReadingSettings.normalizeFontSize(this.fontSize),
      fontWeight: 400,
      fontColor: READER_PRIMARY_COLOR,
      fontPath: '',
      lineHeight: TextReadingSettings.normalizeLineHeight(this.lineHeight),
      nightMode: false,
      themeColor: READER_BACKGROUND,
      themeBgImg: '',
      flipMode: '0',
      scaledDensity: scaledDensity,
      viewPortWidth: currentDisplay.width,
      viewPortHeight: Math.max(1, currentDisplay.height - verticalSafePx)
    };
    return pageConfig;
  }

  private applyReadingSettings(): void {
    try {
      const pageConfig = this.createReaderSetting();
      this.readerSetting = pageConfig;
      if (!this.readerKitReady) return;
      this.readerKitController.setPageConfig(pageConfig);
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'apply settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private handleFontSizeChange(value: number, mode: SliderChangeMode): void {
    this.fontSize = TextReadingSettings.normalizeFontSize(value);
    this.applyReadingSettings();
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.saveReadingSettings();
    }
  }

  private handleLineHeightChange(value: number, mode: SliderChangeMode): void {
    this.lineHeight = TextReadingSettings.normalizeLineHeight(value);
    this.applyReadingSettings();
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.saveReadingSettings();
    }
  }

  private handleReaderKitReady(): void {
    this.readerKitReady = true;
    this.applyReadingSettings();
    this.loading = false;
    this.readerError = '';
    this.preloadNextOnlineChapter(this.currentResourceIndex);
    this.hideReaderBar();
  }

  private handleReaderKitError(message: string, code: number): void {
    this.readerKitReady = false;
    const suffix = code > 0 ? ` (${code})` : '';
    this.failReader(`${message}${suffix}`);
  }

  private handleReaderKitPageShow(info: readerCore.PageDataInfo): void {
    const currentBook = this.book;
    if (currentBook === null) return;
    const count = Math.max(1, currentBook.chapters.length);
    const resourceIndex = this.clampResourceIndex(info.resourceIndex, count);
    const title = this.chapterTitle(resourceIndex);
    this.currentResourceIndex = resourceIndex;
    this.readerKitDomPos = info.startDomPos;
    this.readerKitPageOffset = info.pageOffset;
    if (title.length > 0) {
      this.currentChapterTitle = title;
    }
    this.currentPosition = TextReadingPosition.atChar(
      currentBook.id, resourceIndex, this.readerKitDomPos, 0, this.readerKitPageOffset, this.currentChapterTitle);
    this.saveProgress();
    this.preloadNextOnlineChapter(resourceIndex);
  }

  private failReader(message: string): void {
    this.readerKitReady = false;
    this.readerError = message || '暂时无法打开这本电子书';
    this.loading = false;
  }

  private chapterTitle(index: number): string {
    if (!this.book) return '';
    const chapter = this.book.chapters[index];
    return chapter ? chapter.title : '';
  }

  private chapterIndexByTitle(book: Book, title: string): number {
    if (!title) return -1;
    for (let i = 0; i < book.chapters.length; i++) {
      if (book.chapters[i].title === title) return i;
    }
    return -1;
  }

  private clampResourceIndex(index: number, count: number): number {
    if (count <= 0) return 0;
    return Math.max(0, Math.min(index, count - 1));
  }

  private chapterResourceIndex(chapter: Chapter): number {
    const currentBook = this.book;
    if (currentBook === null) return -1;
    return DataService.resolveChapterIndex(currentBook, chapter.id, chapter.title);
  }

  private chapterStableKey(chapter: Chapter): string {
    if (chapter.id.length > 0) return chapter.id;
    const originSourceValue = chapter.originSourceValue;
    if (originSourceValue !== undefined && originSourceValue.length > 0) return originSourceValue;
    if (chapter.source.value.length > 0) return chapter.source.value;
    return chapter.title;
  }

  private isCurrentChapter(chapter: Chapter): boolean {
    return this.chapterResourceIndex(chapter) === this.currentResourceIndex;
  }

  private async selectChapter(chapter: Chapter): Promise<void> {
    if (!this.readerKitReady || this.jumpingResourceIndex >= 0) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    const resourceIndex = this.chapterResourceIndex(chapter);
    if (resourceIndex < 0) return;
    this.jumpingResourceIndex = resourceIndex;
    try {
      const onlineHandler = this.readerKitHandler;
      if (onlineHandler instanceof OnlineTextBookParserHandler) {
        await onlineHandler.prepareSpineItem(resourceIndex);
      }
      await this.readerKitController.startPlay(resourceIndex, '');
      this.currentResourceIndex = resourceIndex;
      this.currentChapterTitle = chapter.title;
      this.readerKitDomPos = '';
      this.readerKitPageOffset = 0;
      this.currentPosition = TextReadingPosition.atChar(
        currentBook.id, resourceIndex, '', 0, 0, chapter.title);
      this.saveProgress();
      this.preloadNextOnlineChapter(resourceIndex);
      this.tabController.changeIndex(0);
    } catch (e) {
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG, 'chapter jump failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    } finally {
      this.jumpingResourceIndex = -1;
    }
  }

  private preloadNextOnlineChapter(resourceIndex: number): void {
    const currentBook = this.book;
    const onlineHandler = this.readerKitHandler;
    if (currentBook === null || !(onlineHandler instanceof OnlineTextBookParserHandler)) return;
    const nextIndex = resourceIndex + 1;
    if (nextIndex >= currentBook.chapters.length) return;
    onlineHandler.prepareSpineItem(nextIndex).catch((error: Error): void => {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG,
        'next chapter preload failed: %{public}s', error.message);
    });
  }

  private buildTabBar(icon: Resource, label: ResourceStr): BottomTabBarStyle {
    return new BottomTabBarStyle(
      {
        normal: new SymbolGlyphModifier(icon).fontColor([READER_SECONDARY_COLOR]).fontSize(23),
        selected: new SymbolGlyphModifier(icon).fontColor([READER_PRIMARY_COLOR]).fontSize(25)
      },
      label
    ).labelStyle({
      unselectedColor: READER_SECONDARY_COLOR,
      selectedColor: READER_PRIMARY_COLOR
    });
  }

  private toggleReaderBar(): void {
    if (this.currentTabIndex !== 0) return;
    if (this.readerBarVisible) {
      this.hideReaderBar();
    } else {
      this.tabController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
      this.readerBarVisible = true;
    }
  }

  private hideReaderBar(): void {
    if (this.currentTabIndex !== 0 || !this.readerBarVisible) return;
    this.tabController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
    this.readerBarVisible = false;
  }

  private handleTabChange(index: number): void {
    this.currentTabIndex = index;
    if (index !== 0 && !this.readerBarVisible) {
      this.tabController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
      this.readerBarVisible = true;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.loading && !this.readerError) {
        HdsTabs({ controller: this.tabController }) {
          TabContent() {
            EpubReaderComponent({
              controller: this.readerKitController,
              handler: this.readerKitHandler,
              startResourceIndex: this.currentResourceIndex,
              startDomPos: this.readerKitDomPos,
              pageConfig: this.readerSetting,
              onReady: () => {
                this.handleReaderKitReady();
              },
              onError: (message: string, code: number): void => {
                this.handleReaderKitError(message, code);
              },
              onReaderPageShow: (info: readerCore.PageDataInfo): void => {
                this.handleReaderKitPageShow(info);
              },
              onContentTap: (): void => {
                this.toggleReaderBar();
              }
            })
              .width('100%')
              .height('100%')
              .padding({
                top: this.topSafeVp,
                bottom: this.bottomSafeVp
              })
          }
          .tabBar(this.buildTabBar($r('sys.symbol.bookshelf'), $r('app.string.reader_title')))

          TabContent() {
            this.buildChapterTab()
          }
          .tabBar(this.buildTabBar($r('sys.symbol.list_bullet'), $r('app.string.reader_chapters')))

          TabContent() {
            this.buildSettingsTab()
          }
          .tabBar(this.buildTabBar($r('sys.symbol.gearshape'), $r('app.string.reader_settings')))
        }
        .width('100%')
        .height('100%')
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .barFloatingStyle({
          barBottomMargin: Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + READER_FLOATING_BOTTOM,
          gradientMask: { maskColor: '#66F5F2EA', maskHeight: 92 },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          lightColor: '#66FFC15C',
          adaptToHandedness: true
        })
        .onChange((index: number): void => {
          this.handleTabChange(index);
        })
      }

      if (this.loading) {
        this.buildLoadingState()
      } else if (this.readerError) {
        this.buildErrorState()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(READER_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.handleViewportSizeChange(oldValue, newValue);
    })
  }

  @Builder
  buildChapterTab(): void {
    Column() {
      Row() {
        Column({ space: AppSpace.Xxs }) {
          Text($r('app.string.reader_chapters'))
            .fontSize(AppFont.TitleL)
            .fontColor(READER_PRIMARY_COLOR)
            .fontWeight(FontWeight.Bold)
          if (this.book !== null) {
            Text(this.book.title)
              .fontSize(AppFont.Body)
              .fontColor(READER_SECONDARY_COLOR)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.book !== null && this.book.chapters.length > 0) {
          Text(`${this.currentResourceIndex + 1}/${this.book.chapters.length}`)
            .fontSize(AppFont.Body)
            .fontColor(READER_SECONDARY_COLOR)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: AppSpace.Lg,
        right: AppSpace.Lg,
        top: this.topSafeVp + AppSpace.Md,
        bottom: AppSpace.Md
      })

      Divider()
        .color(READER_DIVIDER_COLOR)

      List({ space: 0 }) {
        LazyForEach(this.chapterDataSource, (chapter: Chapter) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Column()
                .width(3)
                .height(32)
                .borderRadius(2)
                .backgroundColor(this.isCurrentChapter(chapter) ? AppColor.Brand : Color.Transparent)

              Column({ space: AppSpace.Xxs }) {
                Text(chapter.title)
                  .fontSize(AppFont.BodyL)
                  .fontColor(this.isCurrentChapter(chapter) ? READER_PRIMARY_COLOR : READER_SECONDARY_COLOR)
                  .fontWeight(this.isCurrentChapter(chapter) ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${this.chapterResourceIndex(chapter) + 1}`)
                  .fontSize(AppFont.Caption)
                  .fontColor(READER_SECONDARY_COLOR)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.jumpingResourceIndex === this.chapterResourceIndex(chapter)) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.Brand)
              }
            }
            .width('100%')
            .constraintSize({ minHeight: 64 })
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
            .backgroundColor(this.isCurrentChapter(chapter) ? READER_CURRENT_CHAPTER_BACKGROUND : Color.Transparent)
            .onClick(() => this.selectChapter(chapter))
          }
        }, (chapter: Chapter) => this.chapterStableKey(chapter))
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .cachedCount(8)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: WindowUtils.getFloatingTabBottomVp(this.bottomSafeVp) })
    .backgroundColor(READER_BACKGROUND)
  }

  @Builder
  buildSettingsTab(): void {
    Scroll() {
      Column({ space: AppSpace.Lg }) {
        Text($r('app.string.reader_settings'))
          .width('100%')
          .fontSize(AppFont.TitleL)
          .fontColor(READER_PRIMARY_COLOR)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Start)

        Column({ space: AppSpace.Sm }) {
          Row() {
            Text($r('app.string.reader_font_size'))
              .fontSize(AppFont.BodyL)
              .fontColor(READER_PRIMARY_COLOR)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text(`${this.fontSize}px`)
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')

          Slider({
            value: this.fontSize,
            min: TextReadingSettings.FONT_SIZE_MIN,
            max: TextReadingSettings.FONT_SIZE_MAX,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .height(44)
            .blockColor(AppColor.Brand)
            .trackColor(READER_DIVIDER_COLOR)
            .selectedColor(AppColor.Brand)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.handleFontSizeChange(value, mode);
            })

          Row() {
            Text(`${TextReadingSettings.FONT_SIZE_MIN}`)
              .fontSize(AppFont.Caption)
              .fontColor(READER_SECONDARY_COLOR)
            Text(`${TextReadingSettings.FONT_SIZE_MAX}`)
              .fontSize(AppFont.Caption)
              .fontColor(READER_SECONDARY_COLOR)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')

        Divider()
          .color(READER_DIVIDER_COLOR)

        Column({ space: AppSpace.Sm }) {
          Row() {
            Text($r('app.string.reader_line_height'))
              .fontSize(AppFont.BodyL)
              .fontColor(READER_PRIMARY_COLOR)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text(`${this.lineHeight.toFixed(1)}x`)
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')

          Slider({
            value: this.lineHeight,
            min: TextReadingSettings.LINE_HEIGHT_MIN,
            max: TextReadingSettings.LINE_HEIGHT_MAX,
            step: 0.1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .height(44)
            .blockColor(AppColor.Brand)
            .trackColor(READER_DIVIDER_COLOR)
            .selectedColor(AppColor.Brand)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.handleLineHeightChange(value, mode);
            })

          Row() {
            Text($r('app.string.reader_line_height_compact'))
              .fontSize(AppFont.Caption)
              .fontColor(READER_SECONDARY_COLOR)
            Text($r('app.string.reader_line_height_standard'))
              .fontSize(AppFont.Caption)
              .fontColor(READER_SECONDARY_COLOR)
            Text($r('app.string.reader_line_height_loose'))
              .fontSize(AppFont.Caption)
              .fontColor(READER_SECONDARY_COLOR)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: AppSpace.Lg,
        right: AppSpace.Lg,
        top: this.topSafeVp + AppSpace.Md,
        bottom: WindowUtils.getFloatingTabBottomVp(this.bottomSafeVp) + AppSpace.Lg
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor(READER_BACKGROUND)
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Sm }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(AppColor.Brand)
      Text($r('app.string.reader_loading'))
        .fontSize(AppFont.Body)
        .fontColor(READER_SECONDARY_COLOR)
      if (this.currentChapterTitle) {
        Text(this.currentChapterTitle)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(READER_BACKGROUND)
  }

  @Builder
  buildErrorState() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([AppColor.Brand])
      Text(this.readerError)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
      Button($r('app.string.common_retry'))
        .height(44)
        .fontSize(AppFont.Body)
        .fontColor('#FFFFFF')
        .backgroundColor(AppColor.Brand)
        .onClick(() => this.retryReader())
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(READER_BACKGROUND)
  }
}
