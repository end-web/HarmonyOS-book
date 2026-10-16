import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsTabs, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { HdsCompat, CompatibleTabsModifier } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';
import { ReadingSessionService, SessionLocation } from '../service/ReadingSessionService';
import { Book, Chapter } from '../model/Book';
import { TextReaderRouteParams, TextReadingPosition } from '../model/TextReading';
import { AppColor, AppMaterial } from '../theme/Theme';
import { SearchCache } from '../utils/SearchCache';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import { PreferenceService } from '../service/PreferenceService';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { ComicPage, ComicPageDataSource, ComicReaderService } from '../service/ComicReaderService';
import { ComicSuperResolutionService } from '../service/ComicSuperResolutionService';
import { ComicPageImage } from '../components/ComicPageImage';
import { ChapterCacheIndicator } from '../components/ChapterCacheIndicator';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { BookSourceSwitchSheet } from '../components/BookSourceSwitchSheet';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ComicReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param params: TextReaderRouteParams = new TextReaderRouteParams();
  @Local book: Book | undefined = undefined;
  @Local chapterIndex: number = 0;
  @Local chapterPreview: number = -1;
  @Local pageIndex: number = 0;
  @Local pageCount: number = 0;
  @Local busy: boolean = true;
  @Local failed: boolean = false;
  @Local chrome: boolean = false;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafe: number = WindowUtils.getBottomSafeVp();
  @Local leftSafe: number = WindowUtils.getLeftSafeVp();
  @Local rightSafe: number = WindowUtils.getRightSafeVp();
  @Local mode: number = 0;
  @Local superResolution: boolean = false;
  private touchX: number = 0;
  private touchY: number = 0;
  private touchLastPage: boolean = false;
  private forwardScroll: boolean = false;
  private turning: boolean = false;
  @Local showChapters: boolean = false;
  @Local showSettings: boolean = false;
  @Local showSourceSwitch: boolean = false;
  @Local widthVp: number = 360;
  @Local heightVp: number = 640;
  @Local saveFailed: boolean = false;
  private pages: ComicPageDataSource = new ComicPageDataSource();
  private chapters: ChapterDataSource = new ChapterDataSource();
  private scroller: Scroller = new Scroller();
  private swiper: SwiperController = new SwiperController();
  private generation: number = 0;
  private alive: boolean = false;
  private foreground: boolean = true;
  private backgroundHandler = (): void => { this.savePosition(); this.foreground = false; ReadingSessionService.end('reading'); };
  private foregroundHandler = (): void => { this.foreground = true; this.savePosition(); };
  private saveTimer: number = -1;
  private restoreTimer: number = -1;
  private saveChain: Promise<void> = Promise.resolve();
  private safeAreaListener = (top: number, bottom: number): void => {
    this.topSafe = top;
    this.bottomSafe = bottom;
    this.leftSafe = WindowUtils.getLeftSafeVp();
    this.rightSafe = WindowUtils.getRightSafeVp();
  };

  private toggleChrome(): void {
    if (this.showChapters || this.showSettings || this.showSourceSwitch) return;
    this.chrome = !this.chrome;
    WindowUtils.setReaderStatusBarVisible(this.chrome);
  }

  private onContentTap(event: ClickEvent): void {
    if (event.windowX < this.widthVp * 0.1 || event.windowX > this.widthVp * 0.9 ||
      event.windowY < this.heightVp * 0.15 || event.windowY > this.heightVp * 0.85) return;
    this.toggleChrome();
  }

  private reportError(error: Object): void {
    const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    hilog.error(0x0001, 'ComicReader', 'chapter=%{public}d failed=%{public}s', this.chapterIndex,
      message.replace(/https?:\/\/\S+/g, '[address]'));
    this.chrome = true;
    WindowUtils.setReaderStatusBarVisible(true);
  }

  aboutToAppear(): void {
    this.alive = true;
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    emitter.on('app.reader.background', this.backgroundHandler);
    emitter.on('app.reader.foreground', this.foregroundHandler);
    WindowUtils.setStatusBarLight(true);
    WindowUtils.setReaderStatusBarLight(true);
    WindowUtils.setReaderStatusBarVisible(false);
    this.initialize();
  }

  aboutToDisappear(): void {
    this.savePosition();
    this.alive = false;
    ComicReaderService.cancelPendingExcept();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    emitter.off('app.reader.background', this.backgroundHandler);
    emitter.off('app.reader.foreground', this.foregroundHandler);
    ReadingSessionService.end('reading');
    this.generation++;
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    if (this.restoreTimer >= 0) clearTimeout(this.restoreTimer);
    WindowUtils.setStatusBarLight(false);
  }

  private async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) { this.busy = false; this.failed = true; return; }
    try {
      let book = SearchCache.get(this.params.bookId) ?? await DataService.getBookById(context, this.params.bookId);
      if (!book || book.contentType !== 'comic') throw new Error('Comic unavailable');
      if (book.chapters.length === 0 || book.tocComplete === false) book = await BookSourceService.loadTextBook(book);
      await PreferenceService.applyTocOrder(book);
      const position = await TextReadingProgressService.get(context, book.id);
      const superResolution = await PreferenceService.getComicSuperResolution();
      if (!this.alive) return;
      this.superResolution = superResolution && ComicSuperResolutionService.supported();
      this.book = book;
      SearchCache.put(book);
      this.chapters.setChapters(book.chaptersDescending ? book.chapters.slice().reverse() : book.chapters);
      const explicit = this.params.resourceIndex >= 0;
      this.mode = position?.domPos === 'comic:paged' ? 1 : position?.domPos === 'comic:rtl' ? 2 : position?.domPos === 'comic:dissolve' ? 3 : 0;
      await this.loadChapter(Math.max(0, Math.min(book.chapters.length - 1,
        explicit ? this.params.resourceIndex : position?.resourceIndex ?? (book.chaptersDescending ? book.chapters.length - 1 : 0))),
        explicit ? 0 : position?.pageOffset ?? 0);
    } catch (error) {
      if (this.alive) { this.reportError(error); this.failed = true; this.busy = false; }
    }
  }

  private async loadChapter(index: number, page: number = 0, force: boolean = false): Promise<void> {
    const book = this.book;
    if (!book || index < 0 || index >= book.chapters.length) {
      this.failed = true; this.busy = false; return;
    }
    this.savePosition();
    this.forwardScroll = false;
    ComicReaderService.cancelPendingExcept(book, book.chapters[index]);
    const generation = ++this.generation;
    const retainCurrent = this.pageCount > 0;
    this.busy = true;
    this.failed = false;
    hilog.info(0x0001, 'ComicReader', 'load start chapter=%{public}d force=%{public}s', index, String(force));
    try {
      const pages = await ComicReaderService.load(book, book.chapters[index], this.getUIContext().getHostContext(), force);
      if (!this.alive || generation !== this.generation) return;
      if (pages.length === 0) throw new Error('No comic images');
      this.chapterIndex = index;
      this.pages.setPages(pages);
      this.pageIndex = Math.max(0, Math.min(page, pages.length - 1));
      this.pageCount = pages.length;
      this.busy = false;
      this.restorePage();
      this.scheduleSave();
      this.preloadChapters(book, index, generation);
      hilog.info(0x0001, 'ComicReader', 'load complete chapter=%{public}d pages=%{public}d', index, pages.length);
    } catch (error) {
      if (this.alive && generation === this.generation) {
        hilog.error(0x0001, 'ComicReader', 'load failed target=%{public}d retained=%{public}s', index, String(retainCurrent));
        this.reportError(error); this.failed = !retainCurrent; this.busy = false;
        if (retainCurrent) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_next_failed') });
      }
    }
  }

  private async preloadChapters(book: Book, index: number, generation: number): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const count = await PreferenceService.getPreloadChapters();
    for (let distance = 1; distance <= count; distance++) {
      if (!this.alive || !this.foreground || generation !== this.generation) return;
      const target = index + (book.chaptersDescending ? -distance : distance);
      if (target < 0 || target >= book.chapters.length) return;
      if (distance > await PreferenceService.getPreloadChapters()) return;
      try { await ComicReaderService.load(book, book.chapters[target], context, false, true); }
      catch (_error) { return; }
    }
  }

  private restorePage(): void {
    if (this.restoreTimer >= 0) clearTimeout(this.restoreTimer);
    const target = this.pageIndex;
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.alive || this.busy || this.pageCount === 0) return;
      if (this.mode === 0) this.scroller.scrollToIndex(target, false, ScrollAlign.START);
      else if (this.mode !== 3) this.swiper.changeIndex(target, false);
    }, 100);
  }

  private scheduleSave(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout((): void => { this.saveTimer = -1; this.savePosition(); }, 500);
  }

  private savePosition(): void {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.book || this.busy || this.failed || this.pageCount === 0) return;
    const mode = this.mode === 0 ? 'comic:scroll' : this.mode === 1 ? 'comic:paged' : this.mode === 2 ? 'comic:rtl' : 'comic:dissolve';
    const position = TextReadingPosition.of(this.book.id, this.chapterIndex, mode,
      this.pageIndex, this.book.chapters[this.chapterIndex].title);
    ReadingSessionService.checkpoint('reading', SessionLocation.text(this.book, position), this.foreground);
    this.saveChain = this.saveChain.then((): Promise<void> => TextReadingProgressService.save(context, position))
      .then((): void => { if (this.alive) this.saveFailed = false; })
      .catch((): void => { if (this.alive) this.saveFailed = true; });
  }

  private adjacent(direction: number): number {
    return this.chapterIndex + (this.book?.chaptersDescending ? -direction : direction);
  }

  private canChange(direction: number): boolean {
    return !this.busy && this.adjacent(direction) >= 0 && this.adjacent(direction) < (this.book?.chapters.length ?? 0);
  }

  private changeMode(mode: number): void {
    this.forwardScroll = false;
    this.mode = mode;
    this.showSettings = false;
    this.restorePage();
    this.scheduleSave();
  }

  private currentPages(): ComicPage[] {
    return this.pageCount > 0 ? [this.pages.getData(this.pageIndex)] : [];
  }

  private async setSuperResolution(enabled: boolean): Promise<void> {
    try {
      await PreferenceService.setComicSuperResolution(enabled);
      if (this.alive) this.superResolution = enabled;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    }
  }

  private turnPage(direction: number): void {
    if (this.busy || this.failed || this.showChapters || this.showSettings || this.showSourceSwitch || this.turning) return;
    const target = this.pageIndex + direction;
    if (target < 0 || target >= this.pageCount) {
      if (this.canChange(direction)) this.loadChapter(this.adjacent(direction));
      return;
    }
    this.turning = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut,
      onFinish: () => { this.turning = false; } }, () => {
      this.pageIndex = target;
    });
    this.scheduleSave();
  }

  private contentTouch(event: TouchEvent): void {
    const touch = event.changedTouches[0];
    if (!touch || this.busy || this.restoreTimer >= 0) return;
    if (event.type === TouchType.Down) {
      this.touchX = touch.windowX;
      this.touchY = touch.windowY;
      this.touchLastPage = this.pageIndex === this.pageCount - 1;
      this.forwardScroll = false;
    } else if (event.type === TouchType.Cancel) {
      this.forwardScroll = false;
    } else if (event.type === TouchType.Up) {
      const dx = touch.windowX - this.touchX;
      const dy = touch.windowY - this.touchY;
      if (this.mode === 0) {
        this.forwardScroll = dy < -32 && Math.abs(dy) > Math.abs(dx);
        this.continueScroll();
      } else if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) {
        const direction = (this.mode === 2 ? dx > 0 : dx < 0) ? 1 : -1;
        if (this.mode === 3) this.turnPage(direction);
        else if (direction === 1 && this.touchLastPage && this.canChange(1)) this.loadChapter(this.adjacent(1));
      }
    }
  }

  private continueScroll(): void {
    if (this.mode !== 0 || !this.forwardScroll || this.busy || this.failed || this.restoreTimer >= 0 ||
      this.showSettings || this.showChapters || this.showSourceSwitch || !this.scroller.isAtEnd()) return;
    this.forwardScroll = false;
    if (this.canChange(1)) this.loadChapter(this.adjacent(1));
  }

  private imageWidth(): number { return this.widthVp - this.leftSafe - this.rightSafe - 2 * AdaptiveLayout.readerGutter(this.widthVp, this.leftSafe, this.rightSafe); }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.busy && this.pageCount === 0) {
          Column({ space: 16 }) {
            LoadingProgress().width(36).height(36).color(AppColor.Brand)
            Text($r('app.string.comic_loading')).fontColor('#CCCCCC')
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.failed) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(48).fontColor(['#888888'])
            Text($r('app.string.comic_empty')).fontColor(Color.White).fontSize(17)
            Text($r('app.string.comic_empty_hint')).fontColor('#AAAAAA').fontSize(13).textAlign(TextAlign.Center)
            Button($r('app.string.comic_retry')).backgroundColor(AppColor.Brand)
              .onClick(() => { if (this.book) this.loadChapter(this.chapterIndex, this.pageIndex); else this.initialize(); })
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center).padding(32)
        } else if (this.mode === 0) {
          List({ scroller: this.scroller, initialIndex: this.pageIndex, space: 0 }) {
            LazyForEach(this.pages, (page: ComicPage) => {
              ListItem() {
                ComicPageImage({ page: page, superResolution: this.superResolution, pageWidth: this.imageWidth(),
                  onToggle: (event: ClickEvent): void => { this.onContentTap(event); } })
              }.width('100%').align(Alignment.Center)
            }, (page: ComicPage): string => page.key)
          }.width('100%').layoutWeight(1).cachedCount(1).scrollBar(BarState.Off)
          .onScrollStop(() => this.continueScroll())
          .onScrollIndex((start: number) => {
            if (this.restoreTimer >= 0) return;
            this.pageIndex = start; this.scheduleSave();
          })
        } else if (this.mode === 3) {
          Stack() {
            ForEach(this.currentPages(), (page: ComicPage) => {
              Column() {
                ComicPageImage({ page: page, superResolution: this.superResolution,
                  pageWidth: this.imageWidth(), pageHeight: this.heightVp, paged: true,
                  onToggle: (event: ClickEvent): void => { this.onContentTap(event); } })
              }.width('100%').height('100%').transition(TransitionEffect.OPACITY)
            }, (page: ComicPage): string => page.key)
          }.width('100%').layoutWeight(1).clip(true)
        } else {
          Swiper(this.swiper) {
            LazyForEach(this.pages, (page: ComicPage) => {
              Column() {
                ComicPageImage({ page: page, superResolution: this.superResolution, pageWidth: this.imageWidth(), pageHeight: this.heightVp,
                  paged: true, onToggle: (event: ClickEvent): void => { this.onContentTap(event); } })
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            }, (page: ComicPage): string => page.key)
          }.width('100%').layoutWeight(1).index(this.pageIndex).loop(false).indicator(false).cachedCount(1)
          .direction(this.mode === 2 ? Direction.Rtl : Direction.Ltr)
          .onChange((index: number) => { this.pageIndex = index; this.scheduleSave(); })
        }
      }.width('100%').height('100%')
      .padding({ left: this.leftSafe, right: this.rightSafe })
      .onClick((event: ClickEvent) => this.onContentTap(event))
      .onTouch((event: TouchEvent) => this.contentTouch(event))
      if (this.busy && this.pageCount > 0) {
        LoadingProgress().width(36).height(36).color(AppColor.Brand)
          .margin({ top: this.topSafe + 60 }).hitTestBehavior(HitTestMode.None)
      }
      if (this.chrome) {
        Row({ space: 8 }) {
          ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.comic_back'),
            onPress: (): void => { this.savePosition(); this.navStack.pop(); } })
          Blank()
          ImmersiveCircleButton({ icon: $r('sys.symbol.arrow_clockwise'), label: $r('app.string.content_reload'),
            onPress: (): void => { this.loadChapter(this.chapterIndex, this.pageIndex, true); } }).enabled(!this.busy)
          ImmersiveCircleButton({ icon: $r('sys.symbol.arrow_left_arrow_right'), label: $r('app.string.source_switch_title'),
            onPress: (): void => { this.showSourceSwitch = true; } }).enabled(!this.busy && this.book !== undefined)
          ImmersiveCircleButton({ icon: $r('sys.symbol.info_circle'), label: $r('app.string.reader_details'),
            onPress: (): void => { this.openDetails(); } }).enabled(this.book !== undefined)
        }.width('100%').padding({ left: 16 + this.leftSafe, right: 16 + this.rightSafe })
        .margin({ top: this.topSafe + 4 }).hitTestBehavior(HitTestMode.Transparent)
      }
      // Each sheet needs its own stable host; repeated bindSheet on one node overrides earlier bindings.
      Column().width(0).height(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showSettings, this.settingsSheet(), { height: '70%', showClose: true,
          backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.ReaderSheetBlur,
          systemMaterial: AppMaterial.ReaderSheetThick, title: { title: $r('app.string.comic_reading_mode') } })
      Column().width(0).height(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showSourceSwitch, this.sourceSwitchSheet(), { height: '82%', preferType: SheetType.BOTTOM,
          showClose: true, backgroundColor: AppMaterial.SheetBackground,
          blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick })
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (!this.chrome && this.pageCount > 0) {
        Text(`${this.pageIndex + 1} / ${this.pageCount}`)
          .fontColor('#DDFFFFFF').fontSize(11).padding(8).backgroundColor('#88121212').borderRadius(12)
          .margin({ right: 16 + this.rightSafe, bottom: Math.max(12, this.bottomSafe) })
        }
        this.bottomBar()
      }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor('#121212')
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onAreaChange((_old, area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width === this.widthVp && height === this.heightVp) return;
      this.widthVp = width; this.heightVp = height;
      if (!this.busy) this.restorePage();
    })
    .bindSheet($$this.showChapters, this.chapterSheet(), { height: SheetSize.LARGE, showClose: true,
      backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick,
      title: { title: $r('app.string.comic_chapters') } })

  }

  private openDetails(): void {
    if (!this.book) return;
    this.savePosition();
    SearchCache.put(this.book);
    this.navStack.pushPathByName('detail', this.book.id);
  }

  private async switchSource(book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive || !this.showSourceSwitch || !book.chapters[index]) return;
    const pages = await ComicReaderService.load(book, book.chapters[index], context);
    if (pages.length === 0) throw new Error(context.resourceManager.getStringSync($r('app.string.source_switch_empty_content').id));
    if (!this.alive || !this.showSourceSwitch) return;
    this.savePosition();
    const mode = this.mode === 0 ? 'comic:scroll' : this.mode === 1 ? 'comic:paged' : this.mode === 2 ? 'comic:rtl' : 'comic:dissolve';
    const position = TextReadingPosition.of(book.id, index, mode,
      matched ? Math.min(this.pageIndex, pages.length - 1) : 0, book.chapters[index].title);
    await DataService.upsertCachedBook(book);
    await TextReadingProgressService.save(context, position);
    if (!this.alive || !this.showSourceSwitch) return;
    SearchCache.put(book);
    if (oldFavoriteId) await PreferenceService.replaceFavoriteSource(oldFavoriteId, book.id, replace);
    this.showSourceSwitch = false;
    this.navStack.replacePath({ name: 'comicReader', param: TextReaderRouteParams.of(book.id) }, false);
  }

  @Builder
  sourceSwitchSheet() {
    BookSourceSwitchSheet({ book: this.book ?? null, chapterTitle: this.book?.chapters[this.chapterIndex]?.title ?? '',
      chapterIndex: this.chapterIndex,
      onSelect: async (book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> => {
        await this.switchSource(book, index, matched, oldFavoriteId, replace);
      } })
  }

  private floatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return {
      barSideMargin: 16 + Math.max(this.leftSafe, this.rightSafe),
      barBottomMargin: Math.max(this.bottomSafe, 8) + 4,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 0 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      lightColor: AppColor.Brand,
      adaptToHandedness: true
    };
  }

  private tabClick(index: number): void {
    if (index === 0 && this.canChange(-1)) this.loadChapter(this.adjacent(-1));
    else if (index === 1) this.showChapters = true;
    else if (index === 2) this.showSettings = true;
    else if (index === 3 && this.canChange(1)) this.loadChapter(this.adjacent(1));
  }

  @Builder
  tabStyle(icon: Resource, label: Resource, index: number, direction: number = 0) {
    Column({ space: 2 }) {
      SymbolGlyph(icon).fontSize(22).fontColor([$r('sys.color.font_primary')])
      Text(label).fontSize(12).fontColor($r('sys.color.font_primary')).maxLines(1)
    }.width('100%').height(48).justifyContent(FlexAlign.Center)
    .opacity(direction === 0 || this.canChange(direction) ? 1 : 0.35)
    .accessibilityText(label)
    .onClick(() => { this.tabClick(index); })
  }

  private chapterOrdinal(): number {
    if (this.chapterPreview >= 0) return this.chapterPreview;
    return this.book?.chaptersDescending ? this.book.chapters.length - 1 - this.chapterIndex : this.chapterIndex;
  }

  private chapterAtOrdinal(ordinal: number): number {
    return this.book?.chaptersDescending ? this.book.chapters.length - 1 - ordinal : ordinal;
  }

  @Builder
  chapterArrow(direction: number, icon: Resource) {
    Row() {
      SymbolGlyph(icon).fontSize(20).fontColor([$r('sys.color.font_primary')])
    }.width(44).height(48).justifyContent(FlexAlign.Center).enabled(this.canChange(direction))
      .opacity(this.canChange(direction) ? 1 : 0.35)
      .onClick(() => { this.chapterPreview = -1; this.loadChapter(this.adjacent(direction)); })
  }

  private chapterFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = Math.max(1, (this.widthVp - this.leftSafe - this.rightSafe) * 0.84);
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0, barBottomMargin: 0,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 56 },
      systemMaterialEffect: HdsCompat.material,
      adaptToHandedness: false
    };
  }

  @Builder
  chapterMaterialContent() {
    Row().width('100%').height(56)
  }

  @Builder
  chapterBarContent() {
        Row() {
          this.chapterArrow(-1, $r('sys.symbol.chevron_left'))
            Slider({ value: this.chapterOrdinal(), min: 0, max: Math.max(1, (this.book?.chapters.length ?? 0) - 1),
              step: 1, style: SliderStyle.OutSet })
              .layoutWeight(1).height(48).trackThickness(6).blockSize({ width: 16, height: 16 }).selectedColor(AppColor.Brand).showSteps(false)
              .accessibilityText($r('app.string.comic_chapters'))
              .enabled((this.book?.chapters.length ?? 0) > 1 && !this.busy)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.chapterPreview = Math.round(value);
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  const target = this.chapterAtOrdinal(this.chapterPreview);
                  this.chapterPreview = -1;
                  if (target !== this.chapterIndex) this.loadChapter(target);
                }
              })
          this.chapterArrow(1, $r('sys.symbol.chevron_right'))
        }.width(Math.max(1, (this.widthVp - this.leftSafe - this.rightSafe) * 0.84)).height(56).borderRadius(28)

  }

  @Builder
  bottomBar() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs() {
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.backward_end_fill'), $r('app.string.comic_previous'), 0, -1))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.list_bullet'), $r('app.string.comic_chapters'), 1))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.gearshape'), $r('app.string.reader_settings'), 2))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.forward_end_fill'), $r('app.string.comic_next'), 3, 1))
      }.width('100%').height(120 + this.bottomSafe)
      .barOverlap(true).barMode(BarMode.Fixed).barPosition(BarPosition.End).scrollable(false)
      .attributeModifier(new CompatibleTabsModifier(this.floatingStyle(), 60 + this.bottomSafe))
      .onContentWillChange((): boolean => false)
      Column() {
        if (this.saveFailed) { Text($r('app.string.comic_save_failed')).fontColor('#FFD080').fontSize(12) }
        if (this.pageCount > 0) {
        Stack({ alignContent: Alignment.Center }) {
        if (PlatformCompat.floatingTabs) {
          HdsTabs() {
            TabContent() {}.tabBar(this.chapterMaterialContent())
          }.width('100%').height(56).barPosition(BarPosition.End).barMode(BarMode.Fixed)
            .barHeight(56).barOverlap(true).scrollable(false)
            .attributeModifier(new CompatibleTabsModifier(this.chapterFloatingStyle(), 56))
            .barBackgroundColor(Color.Transparent)
            .backgroundColor(Color.Transparent).borderRadius(28, RenderStrategy.OFFSCREEN).clip(true)
            .onContentWillChange((): boolean => false).hitTestBehavior(HitTestMode.None)
        } else {
          Row() {}.width('100%').height(56).borderRadius(28)
            .backgroundColor($r('sys.color.comp_background_tertiary')).backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        }
        this.chapterBarContent()
        }.width(Math.max(1, (this.widthVp - this.leftSafe - this.rightSafe) * 0.84)).height(56)
        }
      }.width('100%').padding({ left: 16 + this.leftSafe, right: 16 + this.rightSafe })
        .margin({ bottom: 76 + this.bottomSafe })
    }.width('100%').height(160 + this.bottomSafe)
    .animation(null).translate({ y: this.chrome ? 0 : 24 }).opacity(this.chrome ? 1 : 0)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .hitTestBehavior(this.chrome ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  chapterSheet() {
    List() {
      LazyForEach(this.chapters, (chapter: Chapter) => {
        ListItem() {
          Row() {
          ChapterCacheIndicator({ book: this.book ?? null, chapter: chapter })
          Text(chapter.title).fontSize(15).maxLines(2).padding(16).width('100%')
            .layoutWeight(1)
            .fontColor(chapter.id === this.book?.chapters[this.chapterIndex]?.id ? AppColor.Brand : $r('sys.color.font_primary'))
            .onClick(() => {
              this.showChapters = false;
              const index = this.book?.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id) ?? -1;
              this.loadChapter(index);
            })
          }.width('100%').padding({ left: 16 })
        }
      }, (chapter: Chapter): string => chapter.id)
    }.width('100%').height('100%').cachedCount(4).padding({ bottom: 24 })
  }

  @Builder
  settingsSheet() {
    Column({ space: 12 }) {
      Button($r('app.string.comic_scroll')).width('100%').backgroundColor(this.mode === 0 ? AppColor.Brand : '#555555')
        .onClick(() => this.changeMode(0))
      Button($r('app.string.comic_paged')).width('100%').backgroundColor(this.mode === 1 ? AppColor.Brand : '#555555')
        .onClick(() => this.changeMode(1))
      Button($r('app.string.comic_rtl')).width('100%').backgroundColor(this.mode === 2 ? AppColor.Brand : '#555555')
        .onClick(() => this.changeMode(2))
      Button($r('app.string.comic_dissolve')).width('100%').backgroundColor(this.mode === 3 ? AppColor.Brand : '#555555')
        .onClick(() => this.changeMode(3))
      Row() {
        Text($r('app.string.comic_ai_sr')).layoutWeight(1).fontColor($r('sys.color.font_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.superResolution })
          .selectedColor(AppColor.Brand).enabled(ComicSuperResolutionService.supported())
          .onChange((enabled: boolean) => { this.setSuperResolution(enabled); })
      }.width('100%')
      Text($r('app.string.comic_ai_sr_hint')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Row() {
        Text($r('app.string.comic_ai_color')).layoutWeight(1).fontColor($r('sys.color.font_primary'))
        Toggle({ type: ToggleType.Switch, isOn: false }).enabled(false)
      }.width('100%')
      Text($r('app.string.comic_ai_color_unavailable')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.comic_gesture_hint')).fontSize(12).fontColor($r('sys.color.font_secondary'))
    }.width('100%').padding(24)
  }
}
