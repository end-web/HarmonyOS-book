import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { display, SymbolGlyphModifier } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { readerCore } from '@hms.core.readerservice.readerComponent';
import { HdsAnimationMode, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { EpubReaderComponent } from '../components/EpubReaderComponent';
import { Book, Chapter } from '../model/Book';
import { TextReadingPosition, TextReadingSettings } from '../model/TextReading';
import { ReaderPalette, ReaderPattern, ReaderThemeId, resolvePalette } from '../model/ReaderTheme';
import { ReaderBackground } from '../components/ReaderBackground';
import { ReaderSettingsSheet } from '../components/ReaderSettingsSheet';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import {
  OnlineTextNavigationTarget,
  OnlineTextPage,
  OnlineTextPageNavigator,
  OnlineTextPaginator
} from '../service/text/OnlineTextPaginator';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppMaterial, AppSpace } from '../theme/Theme';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';

const READER_LOG_DOMAIN: number = 0x0000;
const READER_LOG_TAG: string = 'ReaderPage';
const READER_FLOATING_BOTTOM: number = 4;
const READER_MIN_SAFE_BOTTOM: number = 8;
const READER_CHAPTER_ROW_HEIGHT: number = 64;
const READER_CHAPTER_JUMP_DISTANCE: number = 200;
const READER_TEXT_HORIZONTAL_PADDING: number = 24;
const READER_TEXT_VERTICAL_PADDING: number = 12;
const READER_TEXT_HEADER_HEIGHT: number = 36;
const READER_TEXT_FOOTER_HEIGHT: number = 24;
const READER_TEXT_LAYOUT_GUARD: number = 4;
const READER_TEXT_SWIPE_DISTANCE: number = 48;

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
  @Local themeId: string = TextReadingSettings.THEME_DEFAULT;
  @Local customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local backgroundPattern: string = ReaderPattern.None;
  @Local bgImagePath: string = '';
  @Local overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  /** 由 themeId / customBackground 解析出的当前配色；所有阅读色都从这里取 */
  @Local palette: ReaderPalette = resolvePalette(TextReadingSettings.THEME_DEFAULT,
    TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT);
  @Local readerKitReady: boolean = false;
  @Local jumpingResourceIndex: number = -1;
  @Local readerBarVisible: boolean = false;
  @Local showChapterSheet: boolean = false;
  @Local showSettingsSheet: boolean = false;
  @Local chapterListOffsetFromCurrent: number = 0;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local onlineTextPages: OnlineTextPage[] = [];
  @Local onlineTextPageIndex: number = 0;
  @Local onlineTextLoading: boolean = false;
  private currentPosition: TextReadingPosition | null = null;
  private context: common.UIAbilityContext | null = null;
  private leaving: boolean = false;
  private tabController: HdsTabsController = new HdsTabsController();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterListScroller: Scroller = new Scroller();
  private readerKitController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  private readerKitHandler: bookParser.BookParserHandler | null = null;
  private readerSetting: readerCore.ReaderSetting | null = null;
  private readerKitDomPos: string = '';
  private readerKitPageOffset: number = 0;
  private onlineTextContent: string = '';
  private onlineTextContentCache: Map<number, string> = new Map();
  private onlineTextContentRequests: Map<number, Promise<string>> = new Map();
  private onlineTextLoadSerial: number = 0;
  private readerViewportWidthVp: number = 0;
  private readerViewportHeightVp: number = 0;
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
    this.readerBarVisible = false;
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowUtils.setStatusBarLight(false);
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.refreshAvoidArea();
    this.initializeReader();
  }

  aboutToDisappear(): void {
    this.leaving = true;
    this.onlineTextLoadSerial++;
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

  /** 合并旋转和窗口缩放期间的多次尺寸回调。 */
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
    const changed = Math.abs(this.readerViewportWidthVp - newValue.width) >= 0.5 ||
      Math.abs(this.readerViewportHeightVp - newValue.height) >= 0.5;
    this.readerViewportWidthVp = newValue.width;
    this.readerViewportHeightVp = newValue.height;
    if (!changed) return;
    this.scheduleReaderSettingsRefresh();
  }

  private async initializeReader(): Promise<void> {
    if (!this.context || !this.bookId) {
      this.failReader('电子书参数无效');
      return;
    }
    this.loading = true;
    this.readerError = '';
    this.onlineTextLoadSerial++;
    this.onlineTextLoading = false;
    try {
      await this.restoreReadingSettings();
      if (this.leaving) return;
      let value = SearchCache.get(this.bookId);
      if (!value) value = await DataService.getBookById(this.context, this.bookId) ?? null;
      if (!value) {
        this.failReader('未找到电子书');
        return;
      }
      if (!this.canOpenBook(value)) {
        this.failReader('未找到电子书');
        return;
      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        value = await BookSourceService.loadTextBook(value);
      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        this.failReader('这本书暂时没有可读章节');
        return;
      }
      if (this.leaving) return;
      this.book = value;
      this.chapterDataSource.setChapters(value.chapters);
      SearchCache.put(value);
      const startPosition = await this.resolveStartPosition(value);
      if (this.leaving) return;
      if (this.isOnlineTextBookValue(value)) {
        await this.prepareOnlineTextReader(value, startPosition);
      } else {
        await this.prepareReaderKitReader(value, startPosition);
      }
    } catch (e) {
      this.failReader(e instanceof Error ? e.message : String(e));
    }
  }

  private canOpenBook(book: Book): boolean {
    if (this.isOnlineTextBookValue(book)) return true;
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

  private isOnlineTextBook(): boolean {
    const currentBook = this.book;
    return currentBook !== null && this.isOnlineTextBookValue(currentBook);
  }

  private isOnlineTextBookValue(book: Book): boolean {
    return this.bookContentType(book) === 'text' && this.resolveEpubFilePath(book).length === 0;
  }

  private async prepareOnlineTextReader(book: Book, startPosition: TextReadingPosition): Promise<void> {
    this.readerKitReady = false;
    this.readerKitHandler = null;
    this.readerSetting = null;
    const count = Math.max(1, book.chapters.length);
    const resourceIndex = this.clampResourceIndex(startPosition.resourceIndex, count);
    this.currentResourceIndex = resourceIndex;
    this.currentChapterTitle = this.chapterTitle(resourceIndex);
    this.currentPosition = TextReadingPosition.atChar(
      book.id, resourceIndex, '', startPosition.charOffset, startPosition.pageOffset, this.currentChapterTitle);
    const loaded = await this.loadOnlineTextChapter(
      resourceIndex, startPosition.charOffset, startPosition.pageOffset, false, true);
    if (!loaded || this.leaving) return;
    setTimeout((): void => {
      if (!this.leaving) this.hideReaderBar();
    }, 0);
  }

  private async loadOnlineTextChapter(resourceIndex: number, charOffset: number,
    pageOffset: number, openLastPage: boolean, initialLoad: boolean): Promise<boolean> {
    const currentBook = this.book;
    if (currentBook === null || resourceIndex < 0 || resourceIndex >= currentBook.chapters.length) return false;
    const serial = ++this.onlineTextLoadSerial;
    this.onlineTextLoading = true;
    this.jumpingResourceIndex = resourceIndex;
    try {
      const content = await this.getOnlineTextChapterContent(currentBook, resourceIndex);
      if (this.leaving || serial !== this.onlineTextLoadSerial) return false;
      const pages = this.paginateOnlineTextContent(content);
      let nextPageIndex = 0;
      if (openLastPage) {
        nextPageIndex = Math.max(0, pages.length - 1);
      } else if (charOffset > 0) {
        nextPageIndex = OnlineTextPaginator.pageIndexForOffset(pages, charOffset);
      } else {
        nextPageIndex = Math.max(0, Math.min(pageOffset, pages.length - 1));
      }
      this.onlineTextContent = content;
      this.onlineTextPages = pages;
      this.onlineTextPageIndex = nextPageIndex;
      this.currentResourceIndex = resourceIndex;
      this.currentChapterTitle = this.chapterTitle(resourceIndex);
      this.loading = false;
      this.readerError = '';
      this.updateOnlineTextPosition(true);
      this.prefetchAdjacentOnlineTextChapters(resourceIndex);
      return true;
    } catch (e) {
      if (this.leaving || serial !== this.onlineTextLoadSerial) return false;
      const message = e instanceof Error ? e.message : String(e);
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG,
        'online chapter load failed: %{public}s', message);
      if (initialLoad) {
        this.failReader(message || '章节正文加载失败');
      } else {
        this.showToast(message || '章节正文加载失败');
      }
      return false;
    } finally {
      if (serial === this.onlineTextLoadSerial) {
        this.onlineTextLoading = false;
        this.jumpingResourceIndex = -1;
      }
    }
  }

  private async getOnlineTextChapterContent(book: Book, resourceIndex: number): Promise<string> {
    const cached = this.onlineTextContentCache.get(resourceIndex);
    if (cached !== undefined) return cached;
    const pending = this.onlineTextContentRequests.get(resourceIndex);
    if (pending !== undefined) return pending;
    const chapter = book.chapters[resourceIndex];
    if (chapter === undefined) throw new Error('章节索引无效');
    const chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    const request: Promise<string> = BookSourceService.getTextChapterContent(
      book, chapterUrl, chapter.title, chapter.variables).then((value): string => {
      return OnlineTextPaginator.normalizeContent(value.content);
    });
    this.onlineTextContentRequests.set(resourceIndex, request);
    try {
      const content = await request;
      this.onlineTextContentCache.set(resourceIndex, content);
      return content;
    } finally {
      this.onlineTextContentRequests.delete(resourceIndex);
    }
  }

  private paginateOnlineTextContent(content: string): OnlineTextPage[] {
    const currentDisplay = display.getDefaultDisplaySync();
    const density = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 1;
    const scaledDensity = currentDisplay.scaledDensity > 0 ? currentDisplay.scaledDensity : density;
    const viewportWidthVp = this.readerViewportWidthVp > 0 ?
      this.readerViewportWidthVp : currentDisplay.width / density;
    const viewportHeightVp = this.readerViewportHeightVp > 0 ?
      this.readerViewportHeightVp : currentDisplay.height / density;
    const contentWidthVp = Math.max(80,
      viewportWidthVp - READER_TEXT_HORIZONTAL_PADDING * 2);
    const reservedHeightVp = this.topSafeVp + this.bottomSafeVp +
      READER_TEXT_VERTICAL_PADDING * 2 + READER_TEXT_HEADER_HEIGHT +
      READER_TEXT_FOOTER_HEIGHT + READER_TEXT_LAYOUT_GUARD;
    const contentHeightVp = Math.max(80, viewportHeightVp - reservedHeightVp);
    return OnlineTextPaginator.paginate(content, contentWidthVp * density,
      contentHeightVp * density, this.fontSize * scaledDensity, this.lineHeight);
  }

  private currentOnlineTextCharOffset(): number {
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (page !== undefined) return page.startOffset;
    const position = this.currentPosition;
    return position !== null ? position.charOffset : 0;
  }

  private repaginateOnlineText(): void {
    if (!this.isOnlineTextBook() || this.onlineTextContent.length === 0) return;
    const charOffset = this.currentOnlineTextCharOffset();
    const pages = this.paginateOnlineTextContent(this.onlineTextContent);
    this.onlineTextPages = pages;
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(pages, charOffset);
    this.updateOnlineTextPosition(false);
  }

  private updateOnlineTextPosition(persist: boolean): void {
    const currentBook = this.book;
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (currentBook === null || page === undefined) return;
    this.currentPosition = TextReadingPosition.atChar(
      currentBook.id, this.currentResourceIndex, '', page.startOffset,
      this.onlineTextPageIndex, this.currentChapterTitle);
    if (persist) this.saveProgress();
  }

  private prefetchAdjacentOnlineTextChapters(resourceIndex: number): void {
    const currentBook = this.book;
    if (currentBook === null || !this.isOnlineTextBook()) return;
    const previousIndex = resourceIndex - 1;
    const nextIndex = resourceIndex + 1;
    if (previousIndex >= 0) {
      this.getOnlineTextChapterContent(currentBook, previousIndex).catch((error: Error): void => {
        hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG,
          'previous chapter preload failed: %{public}s', error.message);
      });
    }
    if (nextIndex < currentBook.chapters.length) {
      this.getOnlineTextChapterContent(currentBook, nextIndex).catch((error: Error): void => {
        hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG,
          'next chapter preload failed: %{public}s', error.message);
      });
    }
  }

  private async prepareReaderKitReader(book: Book, startPosition: TextReadingPosition): Promise<void> {
    this.readerKitReady = false;
    this.readerKitController = new readerCore.ReaderComponentController();
    this.readerKitHandler = await this.createReaderKitHandler(book);
    const count = Math.max(1, book.chapters.length);
    const resourceIndex = this.clampResourceIndex(startPosition.resourceIndex, count);
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
      this.themeId = settings.themeId;
      this.customBackground = settings.customBackground;
      this.backgroundPattern = settings.pattern;
      this.bgImagePath = settings.backgroundImage;
      this.overlayAlpha = settings.overlayAlpha;
      this.refreshPalette();
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'restore settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.applyDefaultReadingSettings();
    }
  }

  /** 读盘失败或用户点「恢复默认」时回到出厂配置 */
  private applyDefaultReadingSettings(): void {
    this.fontSize = TextReadingSettings.FONT_SIZE_DEFAULT;
    this.lineHeight = TextReadingSettings.LINE_HEIGHT_DEFAULT;
    this.themeId = TextReadingSettings.THEME_DEFAULT;
    this.customBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    this.backgroundPattern = ReaderPattern.None;
    this.bgImagePath = '';
    this.overlayAlpha = TextReadingSettings.OVERLAY_DEFAULT;
    this.refreshPalette();
  }

  /** themeId / customBackground 变了就重算配色，并同步状态栏字色 */
  private refreshPalette(): void {
    this.palette = resolvePalette(this.themeId, this.customBackground);
    // 深色底配白字状态栏，浅色底配黑字
    WindowUtils.setStatusBarLight(this.palette.isDark).catch((_e: Error): void => {});
  }

  private saveReadingSettings(): void {
    const currentContext = this.context;
    if (currentContext === null) return;
    const settings = TextReadingSettings.ofAll(this.fontSize, this.lineHeight, this.themeId,
      this.customBackground, this.backgroundPattern, this.bgImagePath, this.overlayAlpha);
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
      fontColor: this.palette.primary,
      fontPath: '',
      lineHeight: TextReadingSettings.normalizeLineHeight(this.lineHeight),
      nightMode: this.palette.isDark,
      themeColor: this.palette.background,
      // ReaderKit 自己渲染排版，背景图直接交给它；纸纹/布纹是 ArkUI 渐变层，这里传空
      themeBgImg: this.backgroundPattern === ReaderPattern.Image ? this.bgImagePath : '',
      flipMode: '0',
      scaledDensity: scaledDensity,
      viewPortWidth: currentDisplay.width,
      viewPortHeight: Math.max(1, currentDisplay.height - verticalSafePx)
    };
    return pageConfig;
  }

  private applyReadingSettings(): void {
    try {
      if (this.isOnlineTextBook()) {
        this.repaginateOnlineText();
        return;
      }
      const pageConfig = this.createReaderSetting();
      this.readerSetting = pageConfig;
      if (!this.readerKitReady) return;
      this.readerKitController.setPageConfig(pageConfig);
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'apply settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  /** commit=true 才落盘：拖动过程只重排不写 preferences */
  private handleFontSizeChange(value: number, commit: boolean): void {
    this.fontSize = TextReadingSettings.normalizeFontSize(value);
    this.applyReadingSettings();
    if (commit) this.saveReadingSettings();
  }

  private handleLineHeightChange(value: number, commit: boolean): void {
    this.lineHeight = TextReadingSettings.normalizeLineHeight(value);
    this.applyReadingSettings();
    if (commit) this.saveReadingSettings();
  }

  private handleThemeChange(themeId: string): void {
    this.themeId = TextReadingSettings.normalizeThemeId(themeId);
    this.refreshPalette();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  private handleCustomBackgroundChange(hex: string, commit: boolean): void {
    this.customBackground = hex;
    // 正在用自定义主题时才需要立刻重算配色并重排
    if (this.themeId === ReaderThemeId.Custom) {
      this.refreshPalette();
      this.applyReadingSettings();
    }
    if (commit) this.saveReadingSettings();
  }

  private handlePatternChange(pattern: string): void {
    this.backgroundPattern = TextReadingSettings.normalizePattern(pattern);
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  private handleOverlayChange(value: number, commit: boolean): void {
    this.overlayAlpha = TextReadingSettings.normalizeOverlay(value);
    if (commit) this.saveReadingSettings();
  }

  private handleResetDefaults(): void {
    this.applyDefaultReadingSettings();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  /**
   * 相册选图 → 复制进沙箱 files/reader_bg。
   * 相册 uri 是临时授权，重启后失效，所以必须落本地副本再引用。
   */
  private async pickBackgroundImage(): Promise<void> {
    const currentContext = this.context;
    if (currentContext === null) return;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (!result || !result.photoUris || result.photoUris.length === 0) return;
      const srcUri = result.photoUris[0];
      const dir = `${currentContext.filesDir}/reader_bg`;
      try {
        await fileIo.mkdir(dir, true);
      } catch (_e) {
        // 目录已存在
      }
      const dest = `${dir}/bg_${Date.now()}.jpg`;
      const src = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY);
      const dst = await fileIo.open(dest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.copyFile(src.fd, dst.fd);
      await fileIo.close(src);
      await fileIo.close(dst);
      const previous = this.bgImagePath;
      this.bgImagePath = dest;
      this.backgroundPattern = ReaderPattern.Image;
      this.applyReadingSettings();
      this.saveReadingSettings();
      // 换图成功后删掉上一张，避免沙箱里堆积
      if (previous.length > 0 && previous !== dest) {
        fileIo.unlink(previous).catch((_e: Error): void => {});
      }
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'pick background failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private handleReaderKitReady(): void {
    this.readerKitReady = true;
    this.applyReadingSettings();
    this.loading = false;
    this.readerError = '';
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
  }

  private failReader(message: string): void {
    this.readerKitReady = false;
    this.onlineTextLoading = false;
    this.jumpingResourceIndex = -1;
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
    if (this.jumpingResourceIndex >= 0) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    const resourceIndex = this.chapterResourceIndex(chapter);
    if (resourceIndex < 0) return;
    this.showChapterSheet = false;
    this.hideReaderBar();
    if (this.isOnlineTextBook()) {
      await this.loadOnlineTextChapter(resourceIndex, 0, 0, false, false);
      return;
    }
    if (!this.readerKitReady) return;
    this.jumpingResourceIndex = resourceIndex;
    try {
      await this.readerKitController.startPlay(resourceIndex, '');
      this.currentResourceIndex = resourceIndex;
      this.currentChapterTitle = chapter.title;
      this.readerKitDomPos = '';
      this.readerKitPageOffset = 0;
      this.currentPosition = TextReadingPosition.atChar(
        currentBook.id, resourceIndex, '', 0, 0, chapter.title);
      this.saveProgress();
    } catch (e) {
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG, 'chapter jump failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    } finally {
      this.jumpingResourceIndex = -1;
    }
  }

  private async previousOnlineTextPage(): Promise<void> {
    if (this.onlineTextLoading) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    const target: OnlineTextNavigationTarget = OnlineTextPageNavigator.previous(
      this.currentResourceIndex, this.onlineTextPageIndex);
    if (!target.moved) {
      this.showToast('已经是第一页');
      return;
    }
    if (target.chapterIndex === this.currentResourceIndex) {
      this.onlineTextPageIndex = target.pageIndex;
      this.updateOnlineTextPosition(true);
      return;
    }
    await this.loadOnlineTextChapter(
      target.chapterIndex, 0, target.pageIndex, target.openLastPage, false);
  }

  private async nextOnlineTextPage(): Promise<void> {
    if (this.onlineTextLoading) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    const target: OnlineTextNavigationTarget = OnlineTextPageNavigator.next(
      this.currentResourceIndex, this.onlineTextPageIndex,
      this.onlineTextPages.length, currentBook.chapters.length);
    if (!target.moved) {
      this.showToast('已经是最后一页');
      return;
    }
    if (target.chapterIndex === this.currentResourceIndex) {
      this.onlineTextPageIndex = target.pageIndex;
      this.updateOnlineTextPosition(true);
      return;
    }
    await this.loadOnlineTextChapter(
      target.chapterIndex, 0, target.pageIndex, target.openLastPage, false);
  }

  private handleOnlineTextPan(event: GestureEvent): void {
    if (Math.abs(event.offsetX) < READER_TEXT_SWIPE_DISTANCE ||
      Math.abs(event.offsetX) <= Math.abs(event.offsetY)) return;
    if (event.offsetX < 0) {
      this.nextOnlineTextPage();
    } else {
      this.previousOnlineTextPage();
    }
  }

  private currentOnlineTextPageContent(): string {
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    return page !== undefined ? page.text : '';
  }

  private onlineTextPageLabel(): string {
    const total = Math.max(1, this.onlineTextPages.length);
    return `${Math.min(this.onlineTextPageIndex + 1, total)}/${total}`;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
      // 页面退出过程中提示能力可能已经释放。
    }
  }

  private buildTabBar(icon: Resource, label: ResourceStr): BottomTabBarStyle {
    return new BottomTabBarStyle(
      {
        normal: new SymbolGlyphModifier(icon).fontColor([this.palette.secondary]).fontSize(23),
        selected: new SymbolGlyphModifier(icon).fontColor([this.palette.primary]).fontSize(25)
      },
      label
    ).labelStyle({
      unselectedColor: this.palette.secondary,
      selectedColor: this.palette.primary
    });
  }

  private toggleReaderBar(): void {
    if (this.showChapterSheet || this.showSettingsSheet) return;
    if (this.readerBarVisible) {
      this.hideReaderBar();
    } else {
      this.tabController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
      this.readerBarVisible = true;
    }
  }

  private hideReaderBar(): void {
    if (!this.readerBarVisible) return;
    this.tabController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
    this.readerBarVisible = false;
  }

  private hideReaderBarAfterMount(): void {
    setTimeout((): void => {
      if (this.leaving || this.readerBarVisible) return;
      this.tabController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
    }, 0);
  }

  private openBookDetail(): void {
    const currentBook = this.book;
    if (currentBook === null) {
      this.showToast($r('app.string.reader_detail_unavailable'));
      return;
    }
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.hideReaderBar();
    SearchCache.put(currentBook);
    this.navStack.pushPathByName('detail', currentBook.id);
  }

  private openChapterSheet(): void {
    const currentBook = this.book;
    if (currentBook === null || currentBook.chapters.length === 0) {
      this.showToast($r('app.string.reader_no_chapters'));
      return;
    }
    this.showSettingsSheet = false;
    this.chapterListOffsetFromCurrent = 0;
    this.chapterDataSource.setChapters(currentBook.chapters);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      this.showChapterSheet = true;
    });
    this.scrollChapterListToCurrent();
  }

  private closeChapterSheet(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, (): void => {
      this.showChapterSheet = false;
    });
  }

  private openSettingsSheet(): void {
    this.showChapterSheet = false;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      this.showSettingsSheet = true;
    });
  }

  private closeSettingsSheet(): void {
    this.saveReadingSettings();
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, (): void => {
      this.showSettingsSheet = false;
    });
  }

  private scrollChapterListToCurrent(): void {
    const currentBook = this.book;
    if (currentBook === null || currentBook.chapters.length === 0) return;
    const index = this.clampResourceIndex(this.currentResourceIndex, currentBook.chapters.length);
    setTimeout((): void => {
      try {
        this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      } catch (_e) {
        return;
      }
      setTimeout((): void => {
        try {
          this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
        } catch (_e) {
          // 弹层关闭或列表释放时无需继续定位。
        }
      }, 150);
    }, 50);
  }

  private jumpToCurrentChapter(): void {
    this.scrollChapterListToCurrent();
    this.chapterListOffsetFromCurrent = 0;
  }

  private shouldShowChapterJumpButton(): boolean {
    return Math.abs(this.chapterListOffsetFromCurrent) > READER_CHAPTER_JUMP_DISTANCE;
  }

  private handleReaderTabClick(index: number): void {
    if (index === 0) {
      this.openBookDetail();
    } else if (index === 1) {
      this.openChapterSheet();
    } else if (index === 2) {
      this.openSettingsSheet();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层最底：底色 + 纸纹/布纹/相册图，正文与弹层都浮在它上面
      ReaderBackground({
        palette: this.palette,
        pattern: this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        overlayAlpha: this.overlayAlpha
      })

      if (!this.loading && !this.readerError) {
        HdsTabs({ controller: this.tabController }) {
          TabContent() {
            Stack({ alignContent: Alignment.Bottom }) {
              if (this.isOnlineTextBook()) {
                this.buildOnlineTextReader()
              } else {
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

              if (this.showChapterSheet) {
                this.buildChapterSheet()
              }

              if (this.showSettingsSheet) {
                this.buildSettingsSheet()
              }
            }
            .width('100%')
            .height('100%')
          }
          .tabBar(this.buildTabBar($r('sys.symbol.info_circle'), $r('app.string.reader_details')))

          TabContent() {
            Column()
              .width('100%')
              .height('100%')
              // 占位 Tab
          }
          .tabBar(this.buildTabBar($r('sys.symbol.list_bullet'), $r('app.string.reader_chapters')))

          TabContent() {
            Column()
              .width('100%')
              .height('100%')
              // 占位 Tab
          }
          .tabBar(this.buildTabBar($r('sys.symbol.gearshape'), $r('app.string.reader_settings')))
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.hideReaderBarAfterMount();
        })
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .scrollable(false)
        .barFloatingStyle({
          barBottomMargin: Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + READER_FLOATING_BOTTOM,
          gradientMask: { maskColor: ReaderPalette.withAlpha(this.palette.background, 0x66), maskHeight: 92 },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          lightColor: '#66FFC15C',
          adaptToHandedness: true
        })
        .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => false)
        .onTabBarClick((index: number): void => {
          this.handleReaderTabClick(index);
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
    // 背景由 ReaderBackground 铺，根节点保持透明
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.handleViewportSizeChange(oldValue, newValue);
    })
  }

  @Builder
  buildOnlineTextReader(): void {
    Stack() {
      Column() {
        Row() {
          Text(this.currentChapterTitle)
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.onlineTextPageLabel())
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
        }
        .width('100%')
        .height(READER_TEXT_HEADER_HEIGHT)
        .alignItems(VerticalAlign.Center)

        Column() {
          Text(this.currentOnlineTextPageContent())
            .width('100%')
            .fontSize(this.fontSize)
            .fontColor(this.palette.primary)
            .fontWeight(FontWeight.Normal)
            .lineHeight(this.fontSize * this.lineHeight)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .clip(true)

        Row() {
          if (this.book !== null) {
            Text(`${this.currentResourceIndex + 1}/${this.book.chapters.length}`)
              .fontSize(AppFont.Caption)
              .fontColor(this.palette.secondary)
          }
          Blank()
          Text(this.book !== null ? this.book.title : '')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(READER_TEXT_FOOTER_HEIGHT)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: READER_TEXT_HORIZONTAL_PADDING,
        right: READER_TEXT_HORIZONTAL_PADDING,
        top: this.topSafeVp + READER_TEXT_VERTICAL_PADDING,
        bottom: this.bottomSafeVp + READER_TEXT_VERTICAL_PADDING
      })

      Row() {
        Column()
          .height('100%')
          .layoutWeight(3)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.previousOnlineTextPage();
          })
        Column()
          .height('100%')
          .layoutWeight(4)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.toggleReaderBar();
          })
        Column()
          .height('100%')
          .layoutWeight(3)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.nextOnlineTextPage();
          })
      }
      .width('100%')
      .height('100%')

      if (this.onlineTextLoading) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(AppColor.Brand)
          Text(this.chapterTitle(this.jumpingResourceIndex))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.palette.scrim)
      }
    }
    .width('100%')
    .height('100%')
    // 背景由 ReaderBackground 铺
    .parallelGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: READER_TEXT_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent): void => {
          this.handleOnlineTextPan(event);
        })
    )
  }

  @Builder
  buildChapterSheet(): void {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#24000000')
        .onClick((): void => {
          this.closeChapterSheet();
        })

      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Row() {
            Column({ space: AppSpace.Xxs }) {
              Text($r('app.string.reader_chapters'))
                .fontSize(AppFont.Title)
                .fontColor(this.palette.primary)
                .fontWeight(FontWeight.Bold)
              if (this.book !== null) {
                Text(this.book.title)
                  .fontSize(AppFont.Caption)
                  .fontColor(this.palette.secondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.book !== null && this.book.chapters.length > 0) {
              Text(`${this.currentResourceIndex + 1}/${this.book.chapters.length}`)
                .fontSize(AppFont.Body)
                .fontColor(this.palette.secondary)
                .margin({ right: AppSpace.Sm })
            }

            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(20)
                .fontColor([this.palette.secondary])
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .onClick((): void => {
              this.closeChapterSheet();
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: AppSpace.Lg, right: AppSpace.Md, top: AppSpace.Md, bottom: AppSpace.Sm })

          Divider()
            .color(this.palette.divider)

          List({ space: 0, scroller: this.chapterListScroller }) {
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
                      .fontColor(this.isCurrentChapter(chapter) ? this.palette.primary : this.palette.secondary)
                      .fontWeight(this.isCurrentChapter(chapter) ? FontWeight.Medium : FontWeight.Normal)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${this.chapterResourceIndex(chapter) + 1}`)
                      .fontSize(AppFont.Caption)
                      .fontColor(this.palette.secondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (this.isCurrentChapter(chapter)) {
                    SymbolGlyph($r('sys.symbol.scope'))
                      .fontSize(18)
                      .fontColor([AppColor.Brand])
                  }
                }
                .width('100%')
                .constraintSize({ minHeight: READER_CHAPTER_ROW_HEIGHT })
                .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
                .backgroundColor(this.isCurrentChapter(chapter) ?
                  this.palette.highlight : Color.Transparent)
                .onClick((): void => {
                  this.selectChapter(chapter);
                })
              }
            }, (chapter: Chapter) => this.chapterStableKey(chapter))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: WindowUtils.getFloatingTabBottomVp(this.bottomSafeVp) + AppSpace.Sm })
          .scrollBar(BarState.On)
          .cachedCount(8)
          .onScrollIndex((firstIndex: number, lastIndex: number): void => {
            const centerIndex = (firstIndex + lastIndex) / 2;
            this.chapterListOffsetFromCurrent =
              (centerIndex - this.currentResourceIndex) * READER_CHAPTER_ROW_HEIGHT;
          })
        }
        .width('100%')
        .height('100%')

        if (this.shouldShowChapterJumpButton()) {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.scope'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
            Text($r('app.string.reader_back_to_current_chapter'))
              .fontSize(AppFont.Caption)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(22)
          .backgroundColor(AppColor.Brand)
          .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
          .margin({ right: AppSpace.Lg, bottom: this.bottomSafeVp + AppSpace.Lg })
          .onClick((): void => {
            this.jumpToCurrentChapter();
          })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
            .animation({ curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('58%')
      .borderRadius({ topLeft: 20, topRight: 20 })
      .backgroundColor(this.palette.background)
      .systemMaterial(AppMaterial.DialogUltraThick)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 1000 }))
        .animation({ curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSettingsSheet(): void {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#24000000')
        .onClick((): void => {
          this.closeSettingsSheet();
        })

      ReaderSettingsSheet({
        fontSize: this.fontSize,
        lineHeight: this.lineHeight,
        themeId: this.themeId,
        customBackground: this.customBackground,
        pattern: this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        overlayAlpha: this.overlayAlpha,
        palette: this.palette,
        bottomSafeVp: this.bottomSafeVp,
        onFontSizeChange: (value: number, commit: boolean): void => {
          this.handleFontSizeChange(value, commit);
        },
        onLineHeightChange: (value: number, commit: boolean): void => {
          this.handleLineHeightChange(value, commit);
        },
        onThemeChange: (themeId: string): void => {
          this.handleThemeChange(themeId);
        },
        onCustomBackgroundChange: (hex: string, commit: boolean): void => {
          this.handleCustomBackgroundChange(hex, commit);
        },
        onPatternChange: (pattern: string): void => {
          this.handlePatternChange(pattern);
        },
        onOverlayChange: (value: number, commit: boolean): void => {
          this.handleOverlayChange(value, commit);
        },
        onPickImage: (): void => {
          this.pickBackgroundImage();
        },
        onResetDefaults: (): void => {
          this.handleResetDefaults();
        },
        onClose: (): void => {
          this.closeSettingsSheet();
        }
      })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 1000 }))
          .animation({ curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
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
        .fontColor(this.palette.secondary)
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
    // 背景由 ReaderBackground 铺
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
    // 背景由 ReaderBackground 铺
  }
}
