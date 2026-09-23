import { ChapterCacheIndicator } from '../components/ChapterCacheIndicator';
import { ReaderSpeechFloating } from '../components/ReaderSpeechFloating';
import { ReaderFontService, ReaderImportedFont } from '../service/text/ReaderFontService';
import { ReaderScreenOnService } from '../service/text/ReaderScreenOnService';
import { HdsTabs, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { HdsCompat, CompatibleTabsModifier } from '../utils/HdsCompat';
import { PreferenceService } from '../service/PreferenceService';
import { ReaderSpeechText } from '../components/ReaderSpeechText';
import { ReaderSpeechSheet } from '../components/ReaderSpeechSheet';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { curves, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { readerCore } from '@hms.core.readerservice.readerComponent';
import { EpubReaderComponent } from '../components/EpubReaderComponent';
import { Book, Chapter } from '../model/Book';
import {
  TextReadingPosition,
  PageTurnMode,
  TextReadingSettings,
  EVT_READER_JUMP_CHAPTER,
  ReaderJumpChapterEvent
} from '../model/TextReading';
import { emitter } from '@kit.BasicServicesKit';
import { ReaderPalette, ReaderPattern, ReaderThemeId, resolvePalette } from '../model/ReaderTheme';
import { ReaderBackground } from '../components/ReaderBackground';
import { ReaderContinuousComponent } from '../components/ReaderContinuousComponent';
import { ReaderPageTurnComponent } from '../components/ReaderPageTurnComponent';
import { ReaderSettingsSheet } from '../components/ReaderSettingsSheet';
import { ChapterSegmentGrid } from '../components/ChapterSegmentGrid';
import { ReaderStatusIndicator } from '../components/ReaderStatusIndicator';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import {
  OnlineTextNavigationTarget,
  OnlineTextPage,
  OnlineTextPageNavigator,
  OnlineTextPaginator
} from '../service/text/OnlineTextPaginator';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppSpace, AppRadius, AppMaterial } from '../theme/Theme';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';

const READER_LOG_DOMAIN: number = 0x0000;
const READER_LOG_TAG: string = 'ReaderPage';
const READER_FLOATING_BOTTOM: number = 4;
const READER_MIN_SAFE_BOTTOM: number = 8;
/** 手势/悬浮小白条的最大正文避让：只需让过悬浮条本体，不占完整手势区。 */
const READER_GESTURE_SAFE_MAX: number = 16;
// 与首页 HdsTabs barFloatingStyle 官方沉浸栏同款视觉参数。
const READER_BAR_HEIGHT: number = 56;
const READER_BAR_MASK_HEIGHT: number = 92;
const READER_BAR_SIDE_MARGIN: number = 12;
const READER_CHAPTER_ROW_HEIGHT: number = 64;
const READER_CHAPTER_JUMP_DISTANCE: number = 200;
const READER_TEXT_HORIZONTAL_PADDING: number = 24;
const READER_TEXT_HEADER_HEIGHT: number = 36;
const READER_TEXT_FOOTER_HEIGHT: number = 24;
const READER_TEXT_LAYOUT_GUARD: number = 4;
class ReaderOnlineTextTurnPreview {
  chapterIndex: number = 0;
  pageIndex: number = 0;
  content: string = '';
  pages: OnlineTextPage[] = [];
}

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
  private pickingBackgroundImage: boolean = false;
  @Local followSystemTheme: boolean = false;
  @Local systemNightOverride: boolean = false;
  @Local marginLeft: number = 16;
  @Local marginRight: number = 16;
  @Local marginTop: number = 12;
  @Local marginBottom: number = 12;
  /** 上边距上限：跟随阅读视口高度（最高一半），旋转/分屏时更新 */
  @Local marginTopMax: number = 64;
  @Local chapterQuery: string = '';
  private readonly readerColorListener = (): void => {
    if (this.followSystemTheme && !this.leaving) {
      this.refreshPalette();
      this.applyReadingSettings(false);
    }
  };
  @Local themeId: string = TextReadingSettings.THEME_DEFAULT;
  @Local customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local backgroundPattern: string = ReaderPattern.None;
  @Local bgImagePath: string = '';
  @Local overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  @Local pageTurnMode: string = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
  @Local showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  @Local alwaysShowStatusBar: boolean = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
  /** 由 themeId / customBackground 解析出的当前配色；所有阅读色都从这里取 */
  @Local palette: ReaderPalette = resolvePalette(TextReadingSettings.THEME_DEFAULT,
    TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT);
  @Local readerKitReady: boolean = false;
  @Local jumpingResourceIndex: number = -1;
  @Local readerBarVisible: boolean = false;
  @Local showChapterSheet: boolean = false;
  @Local chapterSegmented: boolean = false;
  @Local showSettingsSheet: boolean = false;
  @Local fontPanel: boolean = false;
  @Local fontWeight: number = 400;
  @Local fontColor: string = '';
  @Local fontFamily: string = 'HarmonyOS Sans';
  @Local fontPath: string = '';
  @Local fontName: string = '';
  @Local importedFonts: ReaderImportedFont[] = [];
  @Local screenOnMinutes: number = 0;
  private pickingFont: boolean = false;
  private screenOn: ReaderScreenOnService = new ReaderScreenOnService();
  @Local showSpeechSheet: boolean = false;
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local speechCanResume: boolean = false;
  private followingSpeech: boolean = false;
  private speechFollowChapter: number = -1;
  private readonly speechListener = (): void => { this.followSpeechPosition(); };
  /** 详情页返回栈内阅读页时按所选章节跳转 */
  private readonly jumpChapterHandler: (e: emitter.EventData) => void = (e) => this.onJumpChapterEvent(e);
  @Local chapterListOffsetFromCurrent: number = 0;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local onlineTextPages: OnlineTextPage[] = [];
  @Local onlineTextPageIndex: number = 0;
  @Local continuousRevision: number = 0;
  @Local continuousFollowOffset: number = -1;
  @Local onlineTextLoading: boolean = false;
  @Local onlineTextTurnPreview: ReaderOnlineTextTurnPreview | null = null;
  private onlineTextTurnSerial: number = 0;
  private onlineTextTurnLoading: boolean = false;
  private onlineTextTurnConfirmed: boolean = false;
  private currentPosition: TextReadingPosition | null = null;
  private context: common.UIAbilityContext | null = null;
  private leaving: boolean = false;
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterListScroller: Scroller = new Scroller();
  private readerKitController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  private readerKitHandler: bookParser.BookParserHandler | null = null;
  private readerSetting: readerCore.ReaderSetting | null = null;
  private readerKitDomPos: string = '';
  private readerKitPageOffset: number = 0;
  /** EPUB handler 缓存：记录已解析的文件路径，避免重复调用 getDefaultHandler */
  private static epubHandlerCache: Map<string, bookParser.BookParserHandler> = new Map();
  /** 缓存上限，避免内存占用过大 */
  private static readonly MAX_HANDLER_CACHE_SIZE: number = 3;
  /** 在线文本章节内存缓存：按书源、书籍及章节地址隔离 */
  private static onlineTextContentCache: Map<string, string> = new Map();
  /** 在线文本章节内容缓存上限 */
  private static readonly MAX_TEXT_CONTENT_CACHE_SIZE: number = 50;

  /** 供外部调用的缓存清除方法 */
  static clearEpubCache(): void {
    ReaderPage.epubHandlerCache.clear();
  }

  /** 清除在线文本章节缓存 */
  static clearTextContentCache(): void {
    ReaderPage.onlineTextContentCache.clear();
  }

  private onlineTextContent: string = '';
  private onlineTextContentRequests: Map<number, Promise<string>> = new Map();
  private onlineTextLoadSerial: number = 0;
  private readerViewportWidthVp: number = 0;
  private readerViewportHeightVp: number = 0;
  private readerTextWidthVp: number = 0;
  private readerTextHeightVp: number = 0;
  private readerSettingsRefreshTimerId: number = -1;
  private safeAreaChangeHandler: (topVp: number, bottomVp: number) => void =
    (topVp: number, bottomVp: number): void => {
      const topChanged = Math.abs(this.topSafeVp - topVp) >= 0.1;
      const bottomChanged = Math.abs(this.bottomSafeVp - bottomVp) >= 0.1;
      this.topSafeVp = topVp;
      this.bottomSafeVp = bottomVp;
      if (topChanged || bottomChanged) this.scheduleReaderSettingsRefresh();
    };

  private backgroundHandler = (): void => {
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    this.saveProgress();
  };

  aboutToAppear(): void {
    emitter.on('app.reader.background', this.backgroundHandler);
    this.leaving = false;
    this.readerBarVisible = false;
    this.syncReaderStatusBar();
    WindowUtils.setReaderActive(true);
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowUtils.setStatusBarLight(false);
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.addReaderColorListener(this.readerColorListener);
    WindowUtils.refreshAvoidArea();
    TextToSpeechService.getInstance().addListener(this.speechListener);
    emitter.on(EVT_READER_JUMP_CHAPTER, this.jumpChapterHandler);
    this.screenOn.init(this.context).catch((): void => {});
    this.screenOn.setVisible(true);
    this.initializeReader();
  }

  aboutToDisappear(): void {
    this.screenOn.dispose();
    emitter.off('app.reader.background', this.backgroundHandler);
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    this.leaving = true;
    emitter.off(EVT_READER_JUMP_CHAPTER, this.jumpChapterHandler);
    TextToSpeechService.getInstance().removeListener(this.speechListener);
    WindowUtils.setReaderActive(false);
    this.onlineTextLoadSerial++;
    this.cancelReaderSettingsRefresh();
    this.saveProgress();
    this.saveReadingSettings();
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.removeReaderColorListener(this.readerColorListener);
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
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number' ||
      newValue.width <= 0 || newValue.height <= 0) return;
    const changed = Math.abs(this.readerViewportWidthVp - newValue.width) >= 0.5 ||
      Math.abs(this.readerViewportHeightVp - newValue.height) >= 0.5;
    this.readerViewportWidthVp = newValue.width;
    this.readerViewportHeightVp = newValue.height;
    this.updateMarginTopMax();
    if (!changed) return;
    this.scheduleReaderSettingsRefresh();
  }

  /** 上边距允许到阅读视口一半；换小屏后把已保存的超大值压回上限内。 */
  private updateMarginTopMax(): void {
    const height = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp :
      WindowUtils.pxToVp(display.getDefaultDisplaySync().height);
    const nextMax = Math.max(TextReadingSettings.MARGIN_UI_MAX, Math.floor(height / 2));
    if (Math.abs(nextMax - this.marginTopMax) < 1) return;
    this.marginTopMax = nextMax;
    if (this.marginTop > nextMax) {
      this.marginTop = nextMax;
      this.applyReadingSettings();
      this.saveReadingSettings();
    }
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
        value.chapters = await DataService.getChaptersForBook(value.id);
      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        value = await BookSourceService.loadTextBook(value);

      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        this.failReader('这本书暂时没有可读章节');
        return;
      }
      if (this.leaving) return;
      // 阅读记录依赖持久书籍身份，已有目录时也必须保存。
      await DataService.upsertCachedBook(value);
      await PreferenceService.applyTocOrder(value);
      this.book = value;
      this.chapterDataSource.setChapters(PreferenceService.orderedChapters(value));
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
    if (this.speechState.active && this.speechState.bookId === book.id) {
      return TextReadingPosition.atChar(book.id, this.speechState.chapterIndex, '', this.speechState.charOffset, 0, this.speechState.chapterTitle);
    }
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
    const first = PreferenceService.chapterStep(book) < 0 ? book.chapters.length - 1 : 0;
    return TextReadingPosition.atChar(book.id, first, '', 0, 0, this.chapterTitle(first));
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
    this.completeOnlineTextTurn(false);
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
      const offset = !openLastPage && charOffset > 0 ? Math.min(charOffset, content.length) :
        pages[nextPageIndex].startOffset;
      this.updateOnlineTextPosition(true, offset);
      if (this.pageTurnMode === PageTurnMode.Vertical) this.continuousRevision++;
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
    const chapter = book.chapters[resourceIndex];
    if (chapter === undefined) throw new Error('章节索引无效');
    const chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    const cacheKey = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id, chapterUrl);
    const cached = ReaderPage.onlineTextContentCache.get(cacheKey);
    if (cached !== undefined) {
      ReaderPage.onlineTextContentCache.delete(cacheKey);
      ReaderPage.onlineTextContentCache.set(cacheKey, cached);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'reuse cached text content: %{public}s chapter %{public}d',
        book.title, resourceIndex);
      return cached;
    }
    const pending = this.onlineTextContentRequests.get(resourceIndex);
    if (pending !== undefined) return pending;
    const request = this.readOrFetchOnlineTextContent(book, chapter, chapterUrl, cacheKey);
    this.onlineTextContentRequests.set(resourceIndex, request);
    try {
      const content = await request;
      // LRU 淘汰：缓存超限时移除最早的
      if (ReaderPage.onlineTextContentCache.size >= ReaderPage.MAX_TEXT_CONTENT_CACHE_SIZE) {
        for (const firstKey of ReaderPage.onlineTextContentCache.keys()) {
          ReaderPage.onlineTextContentCache.delete(firstKey);
          break;
        }
        hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'evict oldest text content from cache');
      }
      ReaderPage.onlineTextContentCache.set(cacheKey, content);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'cached text content: %{public}s chapter %{public}d',
        book.title, resourceIndex);
      return content;
    } finally {
      this.onlineTextContentRequests.delete(resourceIndex);
    }
  }

  private async readOrFetchOnlineTextContent(book: Book, chapter: Chapter,
    chapterUrl: string, cacheKey: string): Promise<string> {
    const context = this.context;
    if (context !== null) {
      const saved = await OnlineTextContentCache.read(context, cacheKey);
      if (saved !== undefined) return saved;
    }
    const value = await BookSourceService.getTextChapterContent(book, chapterUrl, chapter.title, chapter.variables);
    const content = OnlineTextPaginator.normalizeContent(value.content);
    if (context !== null) await OnlineTextContentCache.write(context, cacheKey, content);
    return content;
  }

  private paginateOnlineTextContent(content: string): OnlineTextPage[] {
    const currentDisplay = display.getDefaultDisplaySync();
    const density = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 1;
    const scaledDensity = currentDisplay.scaledDensity > 0 ? currentDisplay.scaledDensity : density;
    const viewportWidthVp = this.readerViewportWidthVp > 0 ?
      this.readerViewportWidthVp : currentDisplay.width / density;
    const viewportHeightVp = this.readerViewportHeightVp > 0 ?
      this.readerViewportHeightVp : currentDisplay.height / density;
    const contentWidthVp = this.readerTextWidthVp > 0 ? this.readerTextWidthVp :
      Math.max(80, viewportWidthVp - this.marginLeft - this.marginRight);
    const reservedHeightVp = this.topSafeVp + this.readerBottomInsetVp() +
      this.marginTop + this.marginBottom + READER_TEXT_HEADER_HEIGHT +
      READER_TEXT_FOOTER_HEIGHT + READER_TEXT_LAYOUT_GUARD;
    const contentHeightVp = this.readerTextHeightVp > 0 ?
      Math.max(1, this.readerTextHeightVp - READER_TEXT_LAYOUT_GUARD) :
      Math.max(80, viewportHeightVp - reservedHeightVp);
    return OnlineTextPaginator.paginate(content, contentWidthVp * density,
      contentHeightVp * density, this.fontSize * scaledDensity, this.lineHeight, this.fontFamily, this.fontWeight);
  }

  private currentOnlineTextCharOffset(): number {
    if (this.currentPosition !== null && this.currentPosition.resourceIndex === this.currentResourceIndex) {
      return this.currentPosition.charOffset;
    }
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (page !== undefined) return page.startOffset;
    const position = this.currentPosition;
    return position !== null ? position.charOffset : 0;
  }

  private handleReaderTextSizeChange(size: SizeOptions): void {
    if (typeof size.width !== 'number' || typeof size.height !== 'number' ||
      size.width <= 0 || size.height <= 0) return;
    if (Math.abs(this.readerTextWidthVp - size.width) < 0.5 &&
      Math.abs(this.readerTextHeightVp - size.height) < 0.5) return;
    this.readerTextWidthVp = size.width;
    this.readerTextHeightVp = size.height;
    this.scheduleReaderSettingsRefresh();
  }

  private repaginateOnlineText(): void {
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    if (!this.isOnlineTextBook() || this.onlineTextContent.length === 0) return;
    const charOffset = this.currentOnlineTextCharOffset();
    const pages = this.paginateOnlineTextContent(this.onlineTextContent);
    this.onlineTextPages = pages;
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(pages, charOffset);
    // 窗口/安全区变化只改变分页；保留已确认字符，避免恢复视口后逐次回退。
    this.updateOnlineTextPosition(false, charOffset);
    if (this.pageTurnMode === PageTurnMode.Vertical) this.continuousRevision++;
  }

  private updateContinuousPosition(chapterIndex: number, offset: number, content: string, persist: boolean): void {
    if (this.leaving || this.onlineTextLoading || this.book === null) return;
    if (chapterIndex !== this.currentResourceIndex || this.onlineTextContent !== content) {
      this.currentResourceIndex = chapterIndex;
      this.currentChapterTitle = this.chapterTitle(chapterIndex);
      this.onlineTextContent = content;
      this.onlineTextPages = this.paginateOnlineTextContent(content);
    }
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, offset);
    this.currentPosition = TextReadingPosition.atChar(this.book.id, chapterIndex, '', offset,
      this.onlineTextPageIndex, this.currentChapterTitle);
    if (persist) this.saveProgress();
  }

  private updateOnlineTextPosition(persist: boolean, charOffset: number = -1): void {
    const currentBook = this.book;
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (currentBook === null || page === undefined) return;
    this.currentPosition = TextReadingPosition.atChar(
      currentBook.id, this.currentResourceIndex, '',
      charOffset >= 0 ? Math.min(charOffset, this.onlineTextContent.length) : page.startOffset,
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
    if (epubPath.length === 0) {
      throw new Error('电子书文件路径为空');
    }
    // 先查缓存
    const cached = ReaderPage.epubHandlerCache.get(epubPath);
    if (cached) {
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'reuse cached epub handler: %{public}s',
        epubPath.substring(epubPath.lastIndexOf('/') + 1));
      return cached;
    }
    // 缓存未命中，解析并缓存
    const handler = await bookParser.getDefaultHandler(epubPath);
    // LRU 淘汰：缓存超限时移除最早的
    if (ReaderPage.epubHandlerCache.size >= ReaderPage.MAX_HANDLER_CACHE_SIZE) {
      const firstKey = ReaderPage.epubHandlerCache.keys().next().value as string;
      ReaderPage.epubHandlerCache.delete(firstKey);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'evict oldest handler from cache');
    }
    ReaderPage.epubHandlerCache.set(epubPath, handler);
    hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'cached new epub handler: %{public}s',
      epubPath.substring(epubPath.lastIndexOf('/') + 1));
    return handler;
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
      this.followSystemTheme = settings.followSystemTheme;
      this.marginLeft = settings.marginLeft;
      this.marginRight = settings.marginRight;
      this.marginTop = settings.marginTop;
      this.marginBottom = settings.marginBottom;
      this.fontWeight = settings.fontWeight;
      this.fontColor = settings.fontColor;
      this.fontPath = settings.fontPath;
      this.fontName = settings.fontName;
      this.importedFonts = await ReaderFontService.list(currentContext, this.fontPath, this.fontName);
      this.screenOnMinutes = settings.screenOnMinutes;
      this.screenOn.configure(this.screenOnMinutes);
      if (this.fontPath.length > 0) {
        try { this.fontFamily = ReaderFontService.register(currentContext, this.fontPath); }
        catch (_e) { this.fontPath = ''; this.fontName = ''; this.fontFamily = 'HarmonyOS Sans'; }
      }
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
      this.themeId = settings.themeId;
      this.customBackground = settings.customBackground;
      this.backgroundPattern = settings.pattern;
      this.bgImagePath = settings.backgroundImage;
      if (this.bgImagePath.length > 0 && !await fileIo.access(this.bgImagePath)) {
        this.bgImagePath = '';
        this.backgroundPattern = ReaderPattern.None;
        if (this.themeId === ReaderThemeId.Image) this.themeId = TextReadingSettings.THEME_DEFAULT;
      }
      this.overlayAlpha = settings.overlayAlpha;
      this.pageTurnMode = settings.pageTurnMode;
      this.showReadingStatus = settings.showReadingStatus;
      this.alwaysShowStatusBar = settings.alwaysShowStatusBar;
      this.syncReaderStatusBar();
      this.updateMarginTopMax();
      this.refreshPalette();
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'restore settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.applyDefaultReadingSettings();
    }
  }

  /** 读盘失败或用户点「恢复默认」时回到出厂配置 */
  private applyDefaultReadingSettings(): void {
    this.followSystemTheme = false;
    this.marginLeft = 16;
    this.marginRight = 16;
    this.marginTop = 12;
    this.marginBottom = 12;
    this.fontWeight = 400;
    this.fontColor = '';
    this.fontFamily = 'HarmonyOS Sans';
    this.fontPath = '';
    this.fontName = '';
    this.screenOnMinutes = 0;
    this.screenOn.configure(0);
    this.fontSize = TextReadingSettings.FONT_SIZE_DEFAULT;
    this.lineHeight = TextReadingSettings.LINE_HEIGHT_DEFAULT;
    this.themeId = TextReadingSettings.THEME_DEFAULT;
    this.customBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    this.backgroundPattern = ReaderPattern.None;
    this.bgImagePath = '';
    this.overlayAlpha = TextReadingSettings.OVERLAY_DEFAULT;
    this.pageTurnMode = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
    this.showReadingStatus = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    this.alwaysShowStatusBar = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
    this.syncReaderStatusBar();
    this.refreshPalette();
  }

  /** themeId / customBackground 变了就重算配色，并同步状态栏字色 */
  private refreshPalette(): void {
    // WindowUtils 由 EntryAbility.onConfigurationUpdate / 设置页同步，应用「跟随系统」时正确反映系统深浅色。
    const systemDark = WindowUtils.isDarkMode();
    this.systemNightOverride = this.followSystemTheme && systemDark;
    // 系统夜间只覆盖显示，不改写用户保存的图片、蒙层和白天主题。
    const daytimeTheme = this.themeId === ReaderThemeId.Night || this.themeId === ReaderThemeId.Black ?
      ReaderThemeId.Parchment : this.themeId;
    const effectiveTheme = this.followSystemTheme ?
      (this.systemNightOverride ? ReaderThemeId.Night : daytimeTheme) : this.themeId;
    const palette = resolvePalette(effectiveTheme, this.customBackground);
    if (this.fontColor.length > 0 && !this.systemNightOverride) palette.primary = this.fontColor;
    this.palette = palette;
    // 深色底配白字状态栏，浅色底配黑字
    WindowUtils.setReaderStatusBarLight(this.palette.isDark).catch((_e: Error): void => {});
  }

  private saveReadingSettings(): void {
    const currentContext = this.context;
    if (currentContext === null) return;
    const settings = TextReadingSettings.ofAll(this.fontSize, this.lineHeight, this.themeId,
      this.customBackground, this.backgroundPattern, this.bgImagePath, this.overlayAlpha, this.pageTurnMode, this.showReadingStatus);
    settings.fontWeight = this.fontWeight;
    settings.fontColor = this.fontColor;
    settings.fontPath = this.fontPath;
    settings.fontName = this.fontName;
    settings.screenOnMinutes = this.screenOnMinutes;
    settings.followSystemTheme = this.followSystemTheme;
    settings.alwaysShowStatusBar = this.alwaysShowStatusBar;
    settings.marginLeft = this.marginLeft;
    settings.marginRight = this.marginRight;
    settings.marginTop = this.marginTop;
    settings.marginBottom = this.marginBottom;
    TextReadingSettingsService.save(currentContext, settings).catch((e: Error): void => {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'save settings failed: %{public}s', e.message);
    });
  }

  private createReaderSetting(): readerCore.ReaderSetting {
    const currentDisplay = display.getDefaultDisplaySync();
    const scaledDensity = currentDisplay.scaledDensity > 0 ? currentDisplay.scaledDensity : 1;
    const density = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 1;
    const verticalSafePx = (this.topSafeVp + this.readerBottomInsetVp() +
      READER_TEXT_FOOTER_HEIGHT + this.marginTop + this.marginBottom) * density;
    const pageConfig: readerCore.ReaderSetting = {
      fontName: this.fontName || this.fontFamily,
      fontSize: TextReadingSettings.normalizeFontSize(this.fontSize),
      fontWeight: this.fontWeight,
      fontColor: this.palette.primary,
      fontPath: this.fontPath,
      lineHeight: TextReadingSettings.normalizeLineHeight(this.lineHeight),
      nightMode: this.palette.isDark,
      themeColor: this.palette.background,
      // ReaderKit 自己渲染排版，背景图使用它要求的沙箱文件路径
      themeBgImg: !this.systemNightOverride && this.backgroundPattern === ReaderPattern.Image ? this.bgImagePath : '',
      flipMode: '0',
      scaledDensity: scaledDensity,
      viewPortWidth: Math.max(1, currentDisplay.width - (this.marginLeft + this.marginRight) * density),
      viewPortHeight: Math.max(1, currentDisplay.height - verticalSafePx)
    };
    return pageConfig;
  }

  private applyReadingSettings(reflow: boolean = true): void {
    try {
      if (this.isOnlineTextBook()) {
        if (reflow) this.repaginateOnlineText();
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
    if (themeId === ReaderThemeId.Image && this.bgImagePath.length === 0) {
      this.pickBackgroundImage();
      return;
    }
    this.followSystemTheme = false;
    this.themeId = TextReadingSettings.normalizeThemeId(themeId);
    this.backgroundPattern = this.themeId === ReaderThemeId.Image ? ReaderPattern.Image : ReaderPattern.None;
    this.refreshPalette();
    this.applyReadingSettings(false);
    this.saveReadingSettings();
  }

  private handleOverlayChange(value: number, commit: boolean): void {
    this.overlayAlpha = TextReadingSettings.normalizeOverlay(value);
    if (commit) this.saveReadingSettings();
  }

  private handlePageTurnModeChange(mode: string): void {
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    const offset = this.currentOnlineTextCharOffset();
    this.pageTurnMode = TextReadingSettings.normalizePageTurnMode(mode);
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, offset);
    this.updateOnlineTextPosition(true, offset);
    this.saveReadingSettings();
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
  private selectReaderFont(font: ReaderImportedFont): void {
    if (this.context === null) return;
    try {
      const family = font.path.length > 0 ? ReaderFontService.register(this.context, font.path) : 'HarmonyOS Sans';
      this.fontPath = font.path; this.fontName = font.name; this.fontFamily = family;
      this.applyReadingSettings(); this.saveReadingSettings();
    } catch (_e) { this.showToast($r('app.string.reader_font_unavailable')); }
  }

  private async deleteReaderFont(font: ReaderImportedFont): Promise<void> {
    if (this.context === null || this.pickingFont) return;
    this.pickingFont = true;
    try {
      this.importedFonts = await ReaderFontService.remove(this.context, font.path);
      if (this.fontPath === font.path) this.selectReaderFont(new ReaderImportedFont());
    } catch (_e) { this.showToast($r('app.string.reader_font_delete_failed')); }
    finally { this.pickingFont = false; }
  }

  private async pickReaderFont(): Promise<void> {
    if (this.context === null || this.pickingFont) return;
    this.pickingFont = true;
    try {
      const result = await ReaderFontService.pick(this.context);
      if (this.leaving) return;
      this.importedFonts = await ReaderFontService.list(this.context);
      if (result.fonts.length > 0) this.selectReaderFont(result.fonts[result.fonts.length - 1]);
      if (result.failures.length > 0) this.showToast($r('app.string.reader_font_partial', result.fonts.length, result.failures.length));
    } catch (_e) {
      this.showToast($r('app.string.reader_import_font_failed'));
    } finally { this.pickingFont = false; }
  }

  private async pickBackgroundImage(): Promise<void> {
    const currentContext = this.context;
    if (currentContext === null || this.pickingBackgroundImage) return;
    this.pickingBackgroundImage = true;
    let destination: string = '';
    let applied: boolean = false;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0 || this.leaving) return;
      const dir = `${currentContext.filesDir}/reader_bg`;
      if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
      destination = `${dir}/bg_${Date.now()}.jpg`;
      const src = await fileIo.open(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        await fileIo.copyFile(src.fd, destination);
      } finally {
        await fileIo.close(src);
      }
      // 验证图片可解码后再替换当前主题；取消或失败保留原图与原设置。
      const imageSource = image.createImageSource(destination);
      try {
        await imageSource.getImageInfo();
      } finally {
        await imageSource.release();
      }
      if (this.leaving) return;
      const previous = this.bgImagePath;
      if (this.themeId !== ReaderThemeId.Image) this.customBackground = this.palette.background;
      this.bgImagePath = destination;
      this.followSystemTheme = false;
      this.themeId = ReaderThemeId.Image;
      this.backgroundPattern = ReaderPattern.Image;
      this.refreshPalette();
      this.applyReadingSettings(false);
      const settings = TextReadingSettings.ofAll(this.fontSize, this.lineHeight, this.themeId,
        this.customBackground, this.backgroundPattern, this.bgImagePath, this.overlayAlpha, this.pageTurnMode, this.showReadingStatus);
      settings.fontWeight = this.fontWeight;
      settings.fontColor = this.fontColor;
      settings.fontPath = this.fontPath;
      settings.fontName = this.fontName;
      settings.screenOnMinutes = this.screenOnMinutes;
      settings.followSystemTheme = this.followSystemTheme;
      settings.alwaysShowStatusBar = this.alwaysShowStatusBar;
      settings.marginLeft = this.marginLeft;
      settings.marginRight = this.marginRight;
      settings.marginTop = this.marginTop;
      settings.marginBottom = this.marginBottom;
      applied = true;
      await TextReadingSettingsService.save(currentContext, settings);
      // 新路径持久化成功后才删除上一张，避免重启仍引用已删文件。
      if (previous.length > 0 && previous !== destination) {
        fileIo.unlink(previous).catch((_e: Error): void => {});
      }
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'pick background failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.showToast($r('app.string.reader_image_apply_failed'));
    } finally {
      this.pickingBackgroundImage = false;
      if (!applied && destination.length > 0) {
        fileIo.unlink(destination).catch((_e: Error): void => {});
      }
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
    if (!this.showChapterSheet && !this.showSettingsSheet &&
      (info.resourceIndex !== this.currentResourceIndex || info.startDomPos !== this.readerKitDomPos ||
        info.pageOffset !== this.readerKitPageOffset)) {
      this.hideReaderBar();
    }
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
    const resourceIndex = this.chapterResourceIndex(chapter);
    if (resourceIndex < 0) return;
    await this.jumpToResourceIndex(resourceIndex);
  }

  /** 跳到指定章节：EPUB 走 ReaderKit，在线文本走分页加载。 */
  private async jumpToResourceIndex(resourceIndex: number): Promise<void> {
    if (this.jumpingResourceIndex >= 0) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    if (resourceIndex < 0 || resourceIndex >= currentBook.chapters.length) return;
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
      this.currentChapterTitle = this.chapterTitle(resourceIndex);
      this.readerKitDomPos = '';
      this.readerKitPageOffset = 0;
      this.currentPosition = TextReadingPosition.atChar(
        currentBook.id, resourceIndex, '', 0, 0, this.currentChapterTitle);
      this.saveProgress();
    } catch (e) {
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG, 'chapter jump failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    } finally {
      this.jumpingResourceIndex = -1;
    }
  }

  /** 详情页选中章节返回阅读页时触发；未指定章节时保持原进度。 */
  private onJumpChapterEvent(e: emitter.EventData): void {
    const data = e.data as ReaderJumpChapterEvent | undefined;
    if (data === undefined || data === null) return;
    if (this.leaving || data.bookId !== this.bookId) return;
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.showSpeechSheet = false;
    if (data.resourceIndex >= 0) {
      this.jumpToResourceIndex(data.resourceIndex);
    }
  }

  private async prepareOnlineTextTurn(forward: boolean): Promise<boolean> {
    if (this.onlineTextLoading || this.leaving) return false;
    const currentBook = this.book;
    if (currentBook === null) return false;
    // 只收起覆盖正文的工具栏，正文视口和系统栏始终保持不变。
    this.hideReaderBar();
    const displayIndex = PreferenceService.chapterDisplayIndex(currentBook, this.currentResourceIndex);
    const target: OnlineTextNavigationTarget = forward ? OnlineTextPageNavigator.next(
      displayIndex, this.onlineTextPageIndex,
      this.onlineTextPages.length, currentBook.chapters.length) :
      OnlineTextPageNavigator.previous(displayIndex, this.onlineTextPageIndex);
    target.chapterIndex = PreferenceService.chapterDisplayIndex(currentBook, target.chapterIndex);
    if (!target.moved) {
      this.showToast(forward ? $r('app.string.reader_last_page') : $r('app.string.reader_first_page'));
      return false;
    }
    const ticket = ++this.onlineTextTurnSerial;
    const preview = new ReaderOnlineTextTurnPreview();
    preview.chapterIndex = target.chapterIndex;
    preview.content = this.onlineTextContent;
    preview.pages = this.onlineTextPages;
    try {
      if (target.chapterIndex !== this.currentResourceIndex) {
        this.onlineTextTurnLoading = true;
        this.onlineTextLoading = true;
        this.jumpingResourceIndex = target.chapterIndex;
        preview.content = await this.getOnlineTextChapterContent(currentBook, target.chapterIndex);
        if (this.leaving || ticket !== this.onlineTextTurnSerial) return false;
        preview.pages = this.paginateOnlineTextContent(preview.content);
      }
      if (this.leaving || ticket !== this.onlineTextTurnSerial) return false;
      preview.pageIndex = target.openLastPage ? Math.max(0, preview.pages.length - 1) : target.pageIndex;
      this.onlineTextTurnPreview = preview;
      return true;
    } catch (e) {
      if (!this.leaving && ticket === this.onlineTextTurnSerial) {
        this.showToast(e instanceof Error ? e.message : String(e));
      }
      return false;
    } finally {
      if (ticket === this.onlineTextTurnSerial) {
        this.onlineTextTurnLoading = false;
        this.onlineTextLoading = false;
        this.jumpingResourceIndex = -1;
      }
    }
  }

  private completeOnlineTextTurn(commit: boolean): void {
    const preview = this.onlineTextTurnPreview;
    this.onlineTextTurnConfirmed = false;
    this.onlineTextTurnSerial++;
    this.onlineTextTurnPreview = null;
    if (this.onlineTextTurnLoading) {
      this.onlineTextTurnLoading = false;
      this.onlineTextLoading = false;
      this.jumpingResourceIndex = -1;
    }
    if (commit && preview !== null && !this.leaving) {
      this.onlineTextContent = preview.content;
      this.onlineTextPages = preview.pages;
      this.onlineTextPageIndex = preview.pageIndex;
      this.currentResourceIndex = preview.chapterIndex;
      this.currentChapterTitle = this.chapterTitle(preview.chapterIndex);
      this.updateOnlineTextPosition(true);
      this.prefetchAdjacentOnlineTextChapters(preview.chapterIndex);
    }
  }

  private currentOnlineTextPageContent(): string {
    const preview = this.onlineTextTurnPreview;
    const page = preview !== null ? preview.pages[preview.pageIndex] :
      this.onlineTextPages[this.onlineTextPageIndex];
    return page !== undefined ? page.text : '';
  }

  private currentOnlineTextPageSource(): string {
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    return page !== undefined ? this.onlineTextContent.substring(page.startOffset, page.endOffset) : '';
  }

  private onlineTextPageLabel(): string {
    const preview = this.onlineTextTurnPreview;
    const total = Math.max(1, preview !== null ? preview.pages.length : this.onlineTextPages.length);
    const index = preview !== null ? preview.pageIndex : this.onlineTextPageIndex;
    return `${Math.min(index + 1, total)}/${total}`;
  }

  private onlineTextChapterIndex(): number {
    const preview = this.onlineTextTurnPreview;
    return preview !== null ? preview.chapterIndex : this.currentResourceIndex;
  }

  private onlineTextTurnRevision(): string {
    return `${this.currentResourceIndex}:${this.onlineTextPageIndex}:${this.fontSize}:${this.lineHeight}:` +
      `${this.fontFamily}:${this.fontWeight}:${this.fontColor}:${this.themeId}:${this.customBackground}:${this.backgroundPattern}:${this.bgImagePath}:${this.overlayAlpha}:` +
      `${this.topSafeVp}:${this.readerBottomInsetVp()}:${this.marginLeft}:${this.marginRight}:${this.marginTop}:${this.marginBottom}:${this.palette.background}`;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
      // 页面退出过程中提示能力可能已经释放。
    }
  }

  @Builder
  readerTabStyle(icon: Resource, label: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(icon).fontSize(24).fontColor([this.palette.primary])
        .accessibilityText(label)
    }.width('100%').height(48)
  }

  /** 正文底部避让：三键导航等实体底栏完整避让；手势/悬浮小白条只留最小间隙。 */
  private readerBottomInsetVp(): number {
    if (WindowUtils.getSystemBottomVp() > 0) return this.bottomSafeVp;
    return Math.max(READER_MIN_SAFE_BOTTOM, Math.min(this.bottomSafeVp, READER_GESTURE_SAFE_MAX));
  }

  private readerFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return {
      barSideMargin: READER_BAR_SIDE_MARGIN,
      barBottomMargin: Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + READER_FLOATING_BOTTOM,
      gradientMask: { maskColor: this.palette.background, maskHeight: READER_BAR_MASK_HEIGHT },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      lightColor: AppColor.Brand,
      adaptToHandedness: true
    };
  }

  @Builder
  buildReaderTabs(): void {
    // HdsTabs 保持稳定布局，显隐只作用于外层，避免浮动栏布局与属性动画互相干扰。
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs() {
        TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.info_circle'), $r('app.string.reader_details')))
        TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.list_bullet'), $r('app.string.reader_chapters')))
        TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.gearshape'), $r('app.string.reader_settings')))
        TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.textformat'), $r('app.string.reader_font_tab')))
      }
      .width('100%')
      .height(READER_BAR_MASK_HEIGHT + this.bottomSafeVp + READER_FLOATING_BOTTOM)
      .barOverlap(true)
      .barMode(BarMode.Fixed)
      .barPosition(BarPosition.End)
      .scrollable(false)
      .attributeModifier(new CompatibleTabsModifier(this.readerFloatingStyle(), READER_BAR_HEIGHT + this.bottomSafeVp))
      .onTabBarClick((index: number): void => this.handleReaderTabClick(index))
      .onContentWillChange((): boolean => false)
    }
    .width('100%')
    .height(READER_BAR_MASK_HEIGHT + this.bottomSafeVp + READER_FLOATING_BOTTOM)
    .animation(null)
    .translate({ y: this.readerBarVisible ? 0 : 24 })
    .opacity(this.readerBarVisible ? 1 : 0)
    .animation({ duration: 180, curve: curves.cubicBezierCurve(0.2, 0, 0, 1) })
    .hitTestBehavior(this.readerBarVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  private toggleReaderBar(): void {
    if (this.showChapterSheet || this.showSettingsSheet || this.showSpeechSheet) return;
    if (this.readerBarVisible) {
      this.hideReaderBar();
    } else {
      this.showReaderBar();
    }
  }

  private hideReaderBar(): void {
    this.readerBarVisible = false;
    this.syncReaderStatusBar();
  }

  private showReaderBar(): void {
    if (!this.leaving) {
      this.readerBarVisible = true;
      this.syncReaderStatusBar();
    }
  }

  private syncReaderStatusBar(): void {
    WindowUtils.setReaderStatusBarVisible(this.alwaysShowStatusBar || this.readerBarVisible);
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
    // 阅读页保留在栈内：详情页选章节后可返回原阅读页并跳转；防连点重复入栈。
    const names = this.navStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === 'detail' &&
      this.navStack.getParamByIndex(names.length - 1) === currentBook.id) {
      return;
    }
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
    this.chapterQuery = '';
    this.chapterDataSource.setChapters(PreferenceService.orderedChapters(currentBook));
    this.hideReaderBar();
    this.showChapterSheet = true;
    this.scrollChapterListToCurrent();
  }

  private closeChapterSheet(): void {
    this.showChapterSheet = false;
    this.showReaderBar();
  }

  private openSettingsSheet(fontPanel: boolean = false): void {
    this.fontPanel = fontPanel;
    this.showChapterSheet = false;
    this.hideReaderBar();
    this.showSettingsSheet = true;
  }

  private closeSettingsSheet(): void {
    this.saveReadingSettings();
    this.showSettingsSheet = false;
    this.showReaderBar();
  }

  private filterReaderChapters(query: string): void {
    this.chapterQuery = query;
    const keyword = query.trim().toLowerCase();
    const chapters = this.book ? PreferenceService.orderedChapters(this.book) : [];
    this.chapterDataSource.setChapters(chapters.filter((chapter: Chapter): boolean =>
      chapter.title.toLowerCase().includes(keyword)));
    if (!this.chapterSegmented) this.chapterListScroller.scrollToIndex(0, false);
  }

  private scrollChapterListToCurrent(): void {
    if (this.chapterSegmented) return;
    if (this.chapterQuery.length > 0) this.filterReaderChapters('');
    const currentBook = this.book;
    if (currentBook === null || currentBook.chapters.length === 0) return;
    const index = PreferenceService.chapterDisplayIndex(currentBook,
      this.clampResourceIndex(this.currentResourceIndex, currentBook.chapters.length));
    setTimeout((): void => {
      if (this.chapterSegmented || !this.showChapterSheet) return;
      try {
        this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      } catch (_e) {
        return;
      }
      setTimeout((): void => {
        if (this.chapterSegmented || !this.showChapterSheet) return;
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
    return !this.chapterSegmented && Math.abs(this.chapterListOffsetFromCurrent) > READER_CHAPTER_JUMP_DISTANCE;
  }

  private handleReaderTabClick(index: number): void {
    if (index === 0) {
      this.openBookDetail();
    } else if (index === 1) {
      this.openChapterSheet();
    } else if (index === 2) {
      this.openSettingsSheet();
    } else if (index === 3) {
      this.openSettingsSheet(true);
    }
  }

  private async openSpeechSheet(): Promise<void> {
    if (!this.isOnlineTextBook() || this.context === null || this.book === null) return;
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    const speech = TextToSpeechService.getInstance();
    try {
      await speech.initialize(this.context);
      if (this.leaving) return;
      this.speechCanResume = speech.hasSavedPosition(this.book);
      this.hideReaderBar();
      this.showSpeechSheet = true;
      speech.refreshVoices();
    } catch (_error) { this.showToast($r('app.string.tts_engine_error')); }
  }

  private startSpeech(restore: boolean): void {
    if (this.book === null) return;
    TextToSpeechService.getInstance().start(this.book, this.currentResourceIndex,
      this.currentOnlineTextCharOffset(), restore);
    this.speechCanResume = true;
  }

  private async followSpeechPosition(): Promise<void> {
    const state = this.speechState;
    if (this.leaving || !state.active || !state.follow || state.bookId !== this.bookId ||
      !state.playing || this.followingSpeech || this.onlineTextTurnPreview !== null) return;
    // 自然段跨页时仍按实际朗读句起点跟随，整段高亮不把页面拉回段首。
    const readOffset = state.charOffset;
    if (state.chapterIndex !== this.currentResourceIndex) {
      if (this.onlineTextLoading || this.speechFollowChapter === state.chapterIndex) return;
      this.followingSpeech = true;
      this.speechFollowChapter = state.chapterIndex;
      try { await this.loadOnlineTextChapter(state.chapterIndex, readOffset, 0, false, false); }
      finally { this.followingSpeech = false; this.speechFollowChapter = -1; }
    }
    if (this.leaving || !state.follow || state.chapterIndex !== this.currentResourceIndex) return;
    if (this.pageTurnMode === PageTurnMode.Vertical) {
      this.continuousFollowOffset = readOffset;
      return;
    }
    const page = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, readOffset);
    if (page !== this.onlineTextPageIndex) {
      this.onlineTextPageIndex = page;
      this.updateOnlineTextPosition(true);
    }
  }

  @Builder
  private buildSpeechSheet(): void {
    ReaderSpeechSheet({ state: this.speechState, bookId: this.bookId, canResume: this.speechCanResume,
      bookTitle: this.book?.title ?? '', cover: this.book?.cover ?? '', chapterTitle: this.currentChapterTitle,
      onStart: (restore: boolean): void => this.startSpeech(restore),
      onClose: (): void => { this.showSpeechSheet = false; }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层最底：预设底色或自定义图片与蒙层
      ReaderBackground({
        palette: this.palette,
        pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        overlayAlpha: this.overlayAlpha
      })
        // 每个弹层使用独立宿主；同一节点连续 bindSheet 会覆盖前一个绑定。
        .bindSheet($$this.showSpeechSheet, this.buildSpeechSheet(), {
          height: '82%', preferType: SheetType.BOTTOM, showClose: false,
          backgroundColor: AppMaterial.SheetBackground,
          maskColor: Color.Transparent,
          blurStyle: AppMaterial.ReaderSheetBlur,
          systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => {
            this.showSpeechSheet = false;
            if (!this.leaving) this.showReaderBar();
          }
        })

      if (!this.loading && !this.readerError) {
        Stack({ alignContent: Alignment.Bottom }) {
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
                    left: this.marginLeft, right: this.marginRight,
                    top: this.topSafeVp + this.marginTop,
                    bottom: this.readerBottomInsetVp() + READER_TEXT_FOOTER_HEIGHT + this.marginBottom
                  })
                if (this.showReadingStatus) {
                  ReaderStatusIndicator({ color: this.palette.secondary })
                    .height(READER_TEXT_FOOTER_HEIGHT)
                    .margin({ bottom: this.readerBottomInsetVp() + this.marginBottom })
                }
              }

            }
            .width('100%')
            .height('100%')
          this.buildReaderTabs()
          if (this.isOnlineTextBook() && this.readerBarVisible) {
            Row() {
              ReaderSpeechFloating({ playing: this.speechState.playing && this.speechState.bookId === this.bookId,
                onOpen: (): void => { this.openSpeechSheet(); } })
            }
            .width('100%').justifyContent(FlexAlign.End)
            .padding({ right: 16 }).margin({ bottom: this.bottomSafeVp + 86 })
            .hitTestBehavior(HitTestMode.Transparent)
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.showSettingsSheet, this.buildSettingsSheet(), {
          height: '82%',
          preferType: SheetType.BOTTOM,
          showClose: false,
          backgroundColor: AppMaterial.SheetBackground,
          maskColor: Color.Transparent,
          blurStyle: AppMaterial.ReaderSheetBlur,
          systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => {
            this.showSettingsSheet = false;
            if (!this.leaving) {
              this.saveReadingSettings();
              if (!this.showChapterSheet) this.showReaderBar();
            }
          }
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
    .bindSheet($$this.showChapterSheet, this.buildChapterSheet(), {
      height: '58%',
      preferType: SheetType.BOTTOM,
      showClose: false,
      backgroundColor: AppMaterial.SheetBackground,
      maskColor: Color.Transparent,
      blurStyle: AppMaterial.ReaderSheetBlur,
      systemMaterial: AppMaterial.ReaderSheetThick,
      onAppear: (): void => this.scrollChapterListToCurrent(),
      onDisappear: (): void => {
        this.showChapterSheet = false;
        if (!this.leaving && !this.showSettingsSheet) this.showReaderBar();
      }
    })
    .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) this.screenOn.touch(); })
    .onVisibleAreaChange([0, 1], (visible: boolean): void => this.screenOn.setVisible(visible))
    // 背景由 ReaderBackground 铺，根节点保持透明
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.handleViewportSizeChange(oldValue, newValue);
    })
  }

  @Builder
  buildOnlineTextPage(): void {
    Stack() {
      ReaderBackground({
        palette: this.palette,
        pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        overlayAlpha: this.overlayAlpha
      })
      Column() {
        Row() {
          Text(this.chapterTitle(this.onlineTextChapterIndex()))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.pageTurnMode === PageTurnMode.Vertical ?
            `${Math.round(this.currentOnlineTextCharOffset() / Math.max(1, this.onlineTextContent.length) * 100)}%` : this.onlineTextPageLabel())
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
        }
        .width('100%')
        .height(READER_TEXT_HEADER_HEIGHT)
        .alignItems(VerticalAlign.Center)

        Column() {
          if (this.pageTurnMode === PageTurnMode.Vertical) {
            ReaderContinuousComponent({
              revision: this.continuousRevision, chapterIndex: this.currentResourceIndex,
              content: this.onlineTextContent, charOffset: this.currentOnlineTextCharOffset(),
              chapterCount: this.book?.chapters.length ?? 0,
              chapterStep: this.book !== null ? PreferenceService.chapterStep(this.book) : 1,
              fontSize: this.fontSize, lineHeight: this.lineHeight, palette: this.palette,
              fontFamily: this.fontFamily, fontWeight: this.fontWeight,
              bookId: this.bookId, speechState: this.speechState, followOffset: this.continuousFollowOffset,
              topGestureInset: Math.max(0, this.readerViewportHeightVp * 0.1 -
                this.topSafeVp - this.marginTop - READER_TEXT_HEADER_HEIGHT),
              getContent: async (index: number): Promise<string> => {
                if (this.book === null) throw new Error('Reader book unavailable');
                return this.getOnlineTextChapterContent(this.book, index);
              },
              getTitle: (index: number): string => this.chapterTitle(index),
              getKey: (index: number): string => `${this.bookId}:${this.book?.chapters[index]?.id ?? index}`,
              onPosition: (index: number, offset: number, content: string, persist: boolean): void =>
                this.updateContinuousPosition(index, offset, content, persist),
              onCenterTap: (): void => this.toggleReaderBar(),
              onScrollStart: (): void => this.hideReaderBar()
            })
          } else {
            ReaderSpeechText({
              text: this.currentOnlineTextPageContent(),
              source: this.currentOnlineTextPageSource(),
              sourceStart: this.onlineTextPages[this.onlineTextPageIndex]?.startOffset ?? 0,
              state: this.speechState,
              highlightEnabled: this.onlineTextTurnPreview === null && this.speechState.bookId === this.bookId &&
                this.speechState.chapterIndex === this.currentResourceIndex,
              fontSize: this.fontSize, lineHeight: this.lineHeight, palette: this.palette,
              fontFamily: this.fontFamily, fontWeight: this.fontWeight
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => this.handleReaderTextSizeChange(size))

        Row({ space: AppSpace.Sm }) {
          Text(this.book !== null ? `${this.onlineTextChapterIndex() + 1}/${this.book.chapters.length}` : '')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.showReadingStatus) {
            ReaderStatusIndicator({ color: this.palette.secondary })
          }
          Text(this.book !== null ? this.book.title : '')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
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
        left: this.marginLeft,
        right: this.marginRight,
        // 只让正文避开系统栏；背景和翻页纸面始终使用完整视口，保持图片连续。
        top: this.topSafeVp + this.marginTop,
        bottom: this.readerBottomInsetVp() + this.marginBottom
      })

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildOnlineTextReader(): void {
    Stack() {
      if (this.pageTurnMode === PageTurnMode.Vertical) {
        this.buildOnlineTextPage()
      } else {
        ReaderPageTurnComponent({
          mode: this.pageTurnMode,
          revision: this.onlineTextTurnRevision(),
          paperColor: this.palette.background,
          pageContent: (): void => this.buildOnlineTextPage(),
          onPrepare: (forward: boolean): Promise<boolean> => this.prepareOnlineTextTurn(forward),
          onConfirm: (): void => { this.onlineTextTurnConfirmed = true; },
          onComplete: (commit: boolean): void => this.completeOnlineTextTurn(commit),
          onCenterTap: (): void => this.toggleReaderBar()
        })
      }
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
  }

  @Builder
  buildChapterSheet(): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppSpace.Sm }) {
      Row() {
        Text($r('app.string.reader_chapters'))
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Button($r('app.string.chapter_total_switch_text', this.book?.chapters.length ?? 0))
          .fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.chapterSegmented = !this.chapterSegmented;
            this.chapterListOffsetFromCurrent = 0;
            if (!this.chapterSegmented && this.chapterQuery.length === 0) this.scrollChapterListToCurrent();
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick((): void => this.closeChapterSheet())
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })

      Search({ value: this.chapterQuery, placeholder: $r('app.string.reader_search_chapters') })
        .onChange((query: string): void => this.filterReaderChapters(query))
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .searchIcon({ size: 18, color: $r('sys.color.font_secondary') })
        .height(40)
        .borderRadius(AppRadius.Lg)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xs, bottom: AppSpace.Xs })
      if (this.chapterSegmented) {
        ChapterSegmentGrid({
          book: this.book,
          chapters: this.book?.chapters ?? [],
          currentId: this.book?.chapters[this.currentResourceIndex]?.id ?? '',
          keyword: this.chapterQuery,
          descending: this.book?.chaptersDescending ?? false,
          onSelect: (chapter: Chapter): void => { this.selectChapter(chapter); }
        }).layoutWeight(1)
      } else {
      if (this.chapterDataSource.totalCount() === 0) {
        Text($r('app.string.reader_no_matching_chapters'))
          .fontColor($r('sys.color.font_secondary'))
          .padding(AppSpace.Md)
      }
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
                  .fontColor(this.isCurrentChapter(chapter) ? $r('sys.color.font_primary') :
                    $r('sys.color.font_secondary'))
                  .fontWeight(this.isCurrentChapter(chapter) ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${this.chapterResourceIndex(chapter) + 1}`)
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.isCurrentChapter(chapter)) {
                SymbolGlyph($r('sys.symbol.scope'))
                  .fontSize(18)
                  .fontColor([AppColor.Brand])
              }
              ChapterCacheIndicator({ book: this.book, chapter: chapter })
            }
            .width('100%')
            .constraintSize({ minHeight: READER_CHAPTER_ROW_HEIGHT })
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
            .backgroundColor(this.isCurrentChapter(chapter) ?
              AppColor.BrandSoft : Color.Transparent)
            .onClick((): void => {
              this.selectChapter(chapter);
            })
          }
        }, (chapter: Chapter) => this.chapterStableKey(chapter))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: AppSpace.Sm })
      .scrollBar(BarState.On)
      .cachedCount(8)
      .onScrollIndex((firstIndex: number, lastIndex: number): void => {
        const centerIndex = (firstIndex + lastIndex) / 2;
        this.chapterListOffsetFromCurrent =
          (centerIndex - (this.book ? PreferenceService.chapterDisplayIndex(this.book, this.currentResourceIndex) : 0)) * READER_CHAPTER_ROW_HEIGHT;
      })
      }
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
        .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
        .onClick((): void => {
          this.jumpToCurrentChapter();
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
          .animation({ curve: curves.springMotion(0.4, 0.9) }))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSettingsSheet(): void {
    ReaderSettingsSheet({
      fontPanel: this.fontPanel, fontWeight: this.fontWeight,
      fonts: this.importedFonts, fontPath: this.fontPath,
      onSelectFont: (font: ReaderImportedFont): void => this.selectReaderFont(font),
      onDeleteFont: (font: ReaderImportedFont): void => { this.deleteReaderFont(font); },
      fontFamily: this.fontFamily, fontName: this.fontName, screenOnMinutes: this.screenOnMinutes,
      onWeightChange: (weight: number, commit: boolean): void => {
        this.fontWeight = TextReadingSettings.normalizeFontWeight(weight);
        this.applyReadingSettings();
        if (commit) this.saveReadingSettings();
      },
      onColorChange: (color: string, background: boolean, commit: boolean): void => {
        this.followSystemTheme = false;
        if (background) {
          this.customBackground = color;
          this.themeId = ReaderThemeId.Custom;
          this.backgroundPattern = ReaderPattern.None;
        } else { this.fontColor = color; }
        this.refreshPalette();
        this.applyReadingSettings(false);
        if (commit) this.saveReadingSettings();
      },
      onPickFont: (): void => { this.pickReaderFont(); },
      onSystemFont: (): void => {
        this.fontFamily = 'HarmonyOS Sans'; this.fontPath = ''; this.fontName = '';
        this.applyReadingSettings(); this.saveReadingSettings();
      },
      onScreenOnChange: (minutes: number): void => {
        this.screenOnMinutes = minutes; this.screenOn.configure(minutes); this.saveReadingSettings();
      },
      fontSize: this.fontSize,
      lineHeight: this.lineHeight,
      themeId: this.themeId,
      pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
      bgImagePath: this.bgImagePath,
      overlayAlpha: this.overlayAlpha,
      pageTurnMode: this.pageTurnMode,
      showReadingStatus: this.showReadingStatus,
      alwaysShowStatusBar: this.alwaysShowStatusBar,
      onStatusBarChange: (enabled: boolean): void => {
        this.alwaysShowStatusBar = enabled;
        this.syncReaderStatusBar();
        this.saveReadingSettings();
      },
      palette: this.palette,
      followSystemTheme: this.followSystemTheme,
      marginLeft: this.marginLeft, marginRight: this.marginRight,
      marginTop: this.marginTop, marginBottom: this.marginBottom,
      marginTopMax: this.marginTopMax,
      onFollowSystemChange: (enabled: boolean): void => {
        this.followSystemTheme = enabled;
        this.refreshPalette();
        this.applyReadingSettings(false);
        this.saveReadingSettings();
      },
      onMarginChange: (edge: string, value: number, commit: boolean): void => {
        const margin = TextReadingSettings.normalizeMargin(value, 16,
          edge === 'top' ? this.marginTopMax : TextReadingSettings.MARGIN_UI_MAX);
        if (edge === 'left') this.marginLeft = margin;
        if (edge === 'right') this.marginRight = margin;
        if (edge === 'top') this.marginTop = margin;
        if (edge === 'bottom') this.marginBottom = margin;
        this.applyReadingSettings();
        if (commit) this.saveReadingSettings();
      },
      onFontSizeChange: (value: number, commit: boolean): void => {
        this.handleFontSizeChange(value, commit);
      },
      onLineHeightChange: (value: number, commit: boolean): void => {
        this.handleLineHeightChange(value, commit);
      },
      onThemeChange: (themeId: string): void => {
        this.handleThemeChange(themeId);
      },
      onOverlayChange: (value: number, commit: boolean): void => {
        this.handleOverlayChange(value, commit);
      },
      onPageTurnModeChange: (mode: string): void => {
        this.handlePageTurnModeChange(mode);
      },
      onReadingStatusChange: (enabled: boolean): void => {
        this.showReadingStatus = enabled;
        this.saveReadingSettings();
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
