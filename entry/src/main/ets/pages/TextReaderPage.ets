import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { vibrator } from '@kit.SensorServiceKit';
import { mediaquery, AppStorageV2 } from '@kit.ArkUI';
import { AppColor, AppSpace, AppFont, AppMotion, AppRadius } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { ReadingState, READING_STATE_KEY } from '../model/PlayerState';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import { PreferenceService, ReaderBookmark } from '../service/PreferenceService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { BrightnessUtil } from '../utils/BrightnessUtil';
import { FoldUtil } from '../utils/FoldUtil';
import { ParagraphDataSource, splitParagraphs } from '../utils/ParagraphDataSource';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Reader';

interface BgOption {
  mode: number;
  bg: string;
  fg: string;
  label: string;
  light: boolean;
}

interface FontOption {
  family: string;
  label: string;
}

interface FlipModeOption {
  label: string;
  icon: Resource;
}

const FONT_MIN = 12;
const FONT_MAX = 28;
const FONT_DEFAULT = 18;
const CHAPTER_GROUP_SIZE = 1000;

const FLIP_MODE_OPTIONS: FlipModeOption[] = [
  { label: '滚动', icon: $r('sys.symbol.text_alignleft') }
  // { label: '翻页', icon: $r('sys.symbol.arrow_left_arrow_right') },
  // { label: '仿真', icon: $r('sys.symbol.book') }
];

// mode -1=跟随系统  0=纸白  1=护眼  2=夜间
const BG_OPTIONS: BgOption[] = [
  { mode: -1, bg: '#FFFFFF', fg: '#1A1A1A', label: '跟随', light: false },
  { mode: 0, bg: '#FFFFFF', fg: '#1A1A1A', label: '纸白', light: false },
  { mode: 1, bg: '#F5EDDA', fg: '#3D2E1E', label: '护眼', light: false },
  { mode: 2, bg: '#1A1A1A', fg: '#CCCCCC', label: '夜间', light: true }
];

const FONT_OPTIONS: FontOption[] = [
  { family: 'HarmonyOS Sans', label: '系统' },
  { family: 'serif', label: '宋体' },
  { family: '楷体', label: '楷体' }
];


const SAVE_DEBOUNCE_MS = 500;
const HUD_HIDE_MS = 800;

@ComponentV2
export struct TextReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param chapterIndex: number = 0;

  @Local book: Book | null = null;
  @Local currentChapter: Chapter | null = null;
  @Local currentIndex: number = 0;
  @Local loading: boolean = false;
  @Local errorMsg: string = '';

  @Local fontSize: number = FONT_DEFAULT;
  @Local lineSpacing: number = 1.8;
  @Local bgMode: number = -1;
  @Local fontFamily: string = 'HarmonyOS Sans';
  @Local brightnessVal: number = -1;
  @Local foldWide: boolean = false;

  @Local scrollPercent: number = 0;
  @Local showSettings: boolean = false;
  @Local showChapterList: boolean = false;
  @Local showBookmarkList: boolean = false;
  @Local sheetType: 'none' | 'settings' | 'chapters' | 'bookmarks' = 'none';
  @Local sheetOpen: boolean = false;
  @Local chapterTabIdx: number = 0;
  @Local flipMode: number = 0;
  @Local toolbarVisible: boolean = false;
  @Local currentPage: number = 0;
  @Local pageCount: number = 1;
  @Local contentAreaHeight: number = 600;
  @Local pageOffsetX: number = 0;
  @Local pageWidth: number = 360;
  @Local dragDirection: number = 0;
  @Local flipping: boolean = false;

  @Local hudKind: 'none' | 'brightness' | 'font' = 'none';
  @Local hudValue: number = 0;
  @Local toast: string = '';

  @Local bookmarks: ReaderBookmark[] = [];
  @Local sysDark: boolean = false;

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private scroller: Scroller = new Scroller();
  private chapterListScroller: Scroller = new Scroller();
  private dataSource: ParagraphDataSource = new ParagraphDataSource();
  private saveTimer: number = -1;
  private hudTimer: number = -1;
  private toastTimer: number = -1;
  private restoring: boolean = false;
  private userScrolled: boolean = false;
  private foldListener: (wide: boolean) => void = (wide) => { this.foldWide = wide; };
  private darkListener: mediaquery.MediaQueryListener | null = null;
  private readingState: ReadingState = AppStorageV2.connect(ReadingState, READING_STATE_KEY, () => new ReadingState())!;
  private scrollHideTimer: number = -1;

  aboutToAppear(): void {
    this.currentIndex = this.chapterIndex;
    FoldUtil.init();
    this.foldWide = FoldUtil.isWide();
    FoldUtil.onChange(this.foldListener);
    this.darkListener = mediaquery.matchMediaSync('(dark-mode: true)');
    this.sysDark = this.darkListener.matches;
    this.darkListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.sysDark = res.matches;
      this.applyStatusBar();
    });
    this.loadPrefs();
    this.loadBook();
  }

  aboutToDisappear(): void {
    FoldUtil.offChange(this.foldListener);
    if (this.darkListener) {
      this.darkListener.off('change');
      this.darkListener = null;
    }
    this.flushScrollPos();
    this.saveProgress();
    BrightnessUtil.reset();
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    if (this.hudTimer >= 0) clearTimeout(this.hudTimer);
    if (this.toastTimer >= 0) clearTimeout(this.toastTimer);
    if (this.scrollHideTimer >= 0) clearTimeout(this.scrollHideTimer);
    WindowUtils.setStatusBarLight(false);
  }

  private async loadPrefs(): Promise<void> {
    this.fontSize = await PreferenceService.getReaderFontSize();
    this.lineSpacing = await PreferenceService.getReaderLineSpacing();
    this.bgMode = await PreferenceService.getReaderBgMode();
    this.fontFamily = await PreferenceService.getReaderFontFamily();
    this.brightnessVal = await PreferenceService.getReaderBrightness();
    this.flipMode = await PreferenceService.getReaderFlipMode();
    if (this.brightnessVal >= 0) {
      await BrightnessUtil.setWindowBrightness(this.brightnessVal);
    }
    this.applyStatusBar();
  }

  // 跟随模式下夜间反白；显式选了主题则按主题来
  private applyStatusBar(): void {
    const opt = this.resolvedBgOption();
    WindowUtils.setStatusBarLight(opt.light);
  }

  private resolvedBgOption(): BgOption {
    if (this.bgMode === -1) {
      return this.sysDark ? BG_OPTIONS[3] : BG_OPTIONS[1];
    }
    return BG_OPTIONS.find((o) => o.mode === this.bgMode) ?? BG_OPTIONS[1];
  }

  private async saveProgress(): Promise<void> {
    if (!this.book || !this.currentChapter) return;
    await PreferenceService.upsertHistory({
      bookId: this.book.id,
      chapterId: this.currentChapter.id,
      progressMs: 0,
      updatedAt: Date.now()
    });
  }

  private async loadBook(): Promise<void> {
    let b = SearchCache.get(this.bookId);
    if (!b) {
      b = await DataService.getBookById(this.context, this.bookId) || null;
    }
    if (!b) {
      hilog.error(DOMAIN, TAG, 'book not found');
      this.errorMsg = '未找到书籍';
      return;
    }
    this.book = b;
    this.bookmarks = await PreferenceService.getBookmarks(b.id);
    await this.loadChapter(this.currentIndex);
  }

  private async loadChapter(index: number): Promise<void> {
    if (!this.book || index < 0 || index >= this.book.chapters.length) return;
    this.loading = true;
    this.errorMsg = '';
    this.currentChapter = this.book.chapters[index];
    this.currentIndex = index;
    this.restoring = true;
    this.userScrolled = false;
    this.readingState.set(this.book.id, this.currentChapter.id);

    try {
      const text = await this.fetchChapterText();
      const paras = splitParagraphs(text);
      this.dataSource.setData(this.currentChapter.id, paras.length > 0 ? paras : [text || '']);
      this.scrollPercent = 0;
      this.currentPage = 0;
      this.refreshPages();
      const total = this.dataSource.totalCount();
      const restorePara = await PreferenceService.getReaderScrollPos(this.book.id, this.currentChapter.id);
      if (restorePara > 0 && restorePara < total) {
        if (this.flipMode > 0) {
          for (let p = 0; p < this.cachedPages.length; p++) {
            const indices = this.cachedPages[p];
            if (indices.indexOf(restorePara) >= 0) {
              this.currentPage = p;
              break;
            }
          }
          this.updateScrollPercent();
          setTimeout((): void => { this.restoring = false; }, 150);
        } else {
          setTimeout((): void => {
            this.scroller.scrollToIndex(restorePara);
            if (total > 1) {
              this.scrollPercent = Math.min(100, Math.max(0, restorePara / (total - 1) * 100));
            }
            setTimeout((): void => { this.restoring = false; }, 250);
          }, 200);
        }
      } else {
        if (this.flipMode === 0) {
          this.scroller.scrollEdge(Edge.Top);
        }
        setTimeout((): void => { this.restoring = false; }, 150);
      }
      this.saveProgress();
    } catch (err) {
      const error = err as BusinessError;
      this.errorMsg = `加载失败: ${error.message}`;
      this.dataSource.setData(this.currentChapter.id, []);
      this.restoring = false;
    } finally {
      this.loading = false;
    }
  }

  private async fetchChapterText(): Promise<string> {
    if (!this.book || !this.currentChapter) return '';
    const src = this.currentChapter.source;
    if (src.type === 'file') {
      const text = await this.readLocalText(src.value);
      return text || '文件内容为空';
    }
    if (!this.book.sourceUrl) return '书源信息缺失';
    const sourcesJson = await PreferenceService.getBookSources();
    const sources = JSON.parse(sourcesJson) as BookSource[];
    const source = sources.find((s) => s.bookSourceUrl === this.book!.sourceUrl);
    if (!source) return '找不到对应书源';
    const text = await BookSourceService.getTextContent(source, src.value);
    return text || '无法获取章节内容';
  }

  private async readLocalText(filePath: string): Promise<string> {
    try {
      const stat = await fileIo.stat(filePath);
      if (stat.size === 0) return '';
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file);
      const bytes = new Uint8Array(buf);
      try {
        const dec = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: false });
        return dec.decodeToString(bytes);
      } catch (_e) {
        try {
          const dec = util.TextDecoder.create('gbk');
          return dec.decodeToString(bytes);
        } catch (_e2) {
          const dec = util.TextDecoder.create('utf-8');
          return dec.decodeToString(bytes);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      return `读取文件失败: ${err.message}`;
    }
  }

  // ============ 设置变更 ============

  private setFontSize(size: number, persist: boolean = true): void {
    const v = Math.max(FONT_MIN, Math.min(FONT_MAX, Math.round(size)));
    if (v === this.fontSize) return;
    this.fontSize = v;
    if (this.flipMode > 0) this.refreshPages();
    if (persist) PreferenceService.setReaderFontSize(v);
  }



  private setBgMode(mode: number): void {
    this.bgMode = mode;
    PreferenceService.setReaderBgMode(mode);
    this.applyStatusBar();
  }

  private setFontFamily(family: string): void {
    this.fontFamily = family;
    PreferenceService.setReaderFontFamily(family);
  }

  private async setBrightness(v: number, persist: boolean = true): Promise<void> {
    const c = Math.max(0, Math.min(1, v));
    this.brightnessVal = c;
    await BrightnessUtil.setWindowBrightness(c);
    if (persist) PreferenceService.setReaderBrightness(c);
  }

  // ============ 滚动位置防抖保存 ============

  private scheduleSaveScrollPos(paraIndex: number): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      if (this.book && this.currentChapter) {
        PreferenceService.setReaderScrollPos(this.book.id, this.currentChapter.id, paraIndex);
      }
      this.saveTimer = -1;
    }, SAVE_DEBOUNCE_MS);
  }

  private flushScrollPos(): void {
    if (!this.book || !this.currentChapter) return;
    if (this.restoring) return;
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    const total = this.dataSource.totalCount();
    if (total === 0) return;
    let paraIndex = 0;
    if (this.flipMode > 0) {
      const page = this.cachedPages[this.currentPage];
      if (page && page.length > 0) {
        paraIndex = page[0];
      }
    } else {
      paraIndex = Math.min(total - 1, Math.round(this.scrollPercent / 100 * (total - 1)));
    }
    if (paraIndex <= 0) return;
    PreferenceService.setReaderScrollPos(
      this.book.id,
      this.currentChapter.id,
      paraIndex
    );
  }

  // ============ HUD / Toast ============

  private showHud(kind: 'brightness' | 'font', value: number): void {
    this.hudKind = kind;
    this.hudValue = value;
    if (this.hudTimer >= 0) clearTimeout(this.hudTimer);
    this.hudTimer = setTimeout(() => {
      this.hudKind = 'none';
      this.hudTimer = -1;
    }, HUD_HIDE_MS);
  }

  private showToast(msg: string): void {
    this.toast = msg;
    if (this.toastTimer >= 0) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => { this.toast = ''; this.toastTimer = -1; }, 1200);
  }

  // ============ 书签 ============

  private async toggleBookmarkAtCurrent(): Promise<void> {
    if (!this.book || !this.currentChapter) return;
    const total = this.dataSource.totalCount();
    if (total === 0) return;
    const yOff = this.scroller.currentOffset()?.yOffset ?? 0;
    const totalH = Math.max(1, this.fontSize * this.lineSpacing * total * 1.5);
    const paraIndex = Math.min(total - 1, Math.max(0, Math.round(yOff / totalH * total)));
    const preview = (this.dataSource.getData(paraIndex) ?? '').slice(0, 40);
    const list = await PreferenceService.getBookmarks(this.book.id);
    const exist = list.find((m) => m.chapterId === this.currentChapter!.id && m.paraIndex === paraIndex);
    if (exist) {
      await PreferenceService.removeBookmark(this.book.id, this.currentChapter.id, paraIndex);
      this.showToast('已删除书签');
    } else {
      const mark: ReaderBookmark = {
        chapterId: this.currentChapter.id,
        chapterTitle: this.currentChapter.title,
        paraIndex,
        preview,
        addedAt: Date.now()
      };
      await PreferenceService.addBookmark(this.book.id, mark);
      this.showToast('已添加书签');
      this.tryVibrate();
    }
    this.bookmarks = await PreferenceService.getBookmarks(this.book.id);
  }

  private tryVibrate(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 30 },
        { id: 0, usage: 'touch' }
      ).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `vibrate failed: ${e.code} ${e.message}`);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `vibrate err: ${err.code} ${err.message}`);
    }
  }

  private jumpToBookmark(m: ReaderBookmark): void {
    if (!this.book) return;
    const idx = this.book.chapters.findIndex((c) => c.id === m.chapterId);
    this.sheetOpen = false;
    if (idx < 0) return;
    if (idx === this.currentIndex) {
      this.scroller.scrollToIndex(m.paraIndex);
    } else {
      this.loadChapter(idx).then((): void => {
        setTimeout((): void => { this.scroller.scrollToIndex(m.paraIndex); }, 80);
      });
    }
  }

  // ============ 字号宽屏上限 ============
  private maxFontSize(): number {
    return Math.round(FONT_MAX * FoldUtil.fontScale());
  }

  private chapterTabLabels(): string[] {
    const total = (this.book?.chapters || []).length;
    const groups = Math.ceil(total / CHAPTER_GROUP_SIZE);
    const labels: string[] = [];
    for (let i = 0; i < groups; i++) {
      const start = i * CHAPTER_GROUP_SIZE + 1;
      const end = Math.min((i + 1) * CHAPTER_GROUP_SIZE, total);
      labels.push(`${start}-${end}`);
    }
    return labels;
  }

  private chapterTabSlice(): Chapter[] {
    const chapters = this.book?.chapters || [];
    const start = this.chapterTabIdx * CHAPTER_GROUP_SIZE;
    return chapters.slice(start, start + CHAPTER_GROUP_SIZE);
  }

  private initChapterTab(): void {
    this.chapterTabIdx = Math.floor(this.currentIndex / CHAPTER_GROUP_SIZE);
    const offsetInTab = this.currentIndex % CHAPTER_GROUP_SIZE;
    setTimeout(() => {
      this.chapterListScroller.scrollToIndex(offsetInTab, true, ScrollAlign.CENTER);
    }, 100);
  }

  private charsPerLine(): number {
    const padPercent = this.foldWide ? 0.24 : 0.16;
    const screenW = this.pageWidth > 0 ? this.pageWidth : 360;
    const textW = screenW * (1 - padPercent) - this.fontSize * 2;
    return Math.max(10, Math.floor(textW / this.fontSize));
  }

  private paraLines(para: string): number {
    const cpl = this.charsPerLine();
    return Math.max(1, Math.ceil(para.length / cpl));
  }

  private buildPages(): number[][] {
    const total = this.dataSource.totalCount();
    if (total === 0) return [[0]];
    const lineH = this.fontSize * this.lineSpacing;
    const paraGap = this.fontSize * 0.6;
    const maxH = this.contentAreaHeight - 32;
    const pages: number[][] = [];
    let page: number[] = [];
    let usedH = 0;
    for (let i = 0; i < total; i++) {
      const text = (this.dataSource.getData(i) ?? '') as string;
      const lines = this.paraLines(text);
      const h = lines * lineH + paraGap;
      if (page.length > 0 && usedH + h > maxH) {
        pages.push(page);
        page = [i];
        usedH = h;
      } else {
        page.push(i);
        usedH += h;
      }
    }
    if (page.length > 0) pages.push(page);
    return pages;
  }

  private cachedPages: number[][] = [];

  private refreshPages(): void {
    this.cachedPages = this.buildPages();
    this.pageCount = this.cachedPages.length;
  }

  private getPageParas(pageIdx: number): string[] {
    if (pageIdx >= this.cachedPages.length) return [];
    const indices = this.cachedPages[pageIdx];
    const result: string[] = [];
    for (const i of indices) {
      const p = this.dataSource.getData(i);
      if (p !== undefined) result.push(p as string);
    }
    return result;
  }

  private updateScrollPercent(): void {
    if (this.pageCount <= 1) {
      this.scrollPercent = 0;
    } else {
      this.scrollPercent = Math.min(100, this.currentPage / (this.pageCount - 1) * 100);
    }
  }

  // ============ 渲染 ============

  build() {
    Stack() {
      this.buildBody();
      if (this.hudKind !== 'none') {
        this.buildHud();
      }
      if (this.toast.length > 0) {
        this.buildToast();
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolvedBgOption().bg)
    .bindSheet(this.sheetOpen!!, this.buildSheetContent(), {
      height: this.sheetType === 'chapters' ? '70%' : '60%',
      dragBar: true,
      backgroundColor: this.resolvedBgOption().bg,
      onDisappear: () => { this.sheetType = 'none'; this.sheetOpen = false; }
    })
  }

  @Builder
  buildSheetContent() {
    if (this.sheetType === 'settings') {
      this.buildSettingsPanel()
    } else if (this.sheetType === 'chapters') {
      this.buildChapterList()
    } else if (this.sheetType === 'bookmarks') {
      this.buildBookmarkList()
    }
  }

  @Builder
  buildBody() {
    Column() {
      // 顶栏：仅在工具栏显示时出现;否则只占状态栏 + 常驻进度条
      if (this.toolbarVisible) {
        this.buildTopBar()
      } else {
        Row()
          .width('100%')
          .height(WindowUtils.getStatusBarHeightVp())
        this.buildProgressBar()
      }

      // 正文：撑满，叠加分区手势
      Stack() {
        if (this.loading) {
          this.buildLoading()
        } else if (this.errorMsg.length > 0) {
          this.buildError()
        } else {
          this.buildContent()
        }
        // 透明分区遮罩，仅承接手势 / 单击；不拦截 Scroll 滑动
        this.buildTapZones()
      }
      .layoutWeight(1)
      .width('100%')

      if (this.toolbarVisible) {
        this.buildBottomBar()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTopBar() {
    Column() {
      Row()
        .width('100%')
        .height(WindowUtils.getStatusBarHeightVp())
        .backgroundColor(this.resolvedBgOption().bg)
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20).fontColor([this.resolvedBgOption().fg])
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.navStack.pop())

        Text(this.currentChapter?.title || (this.book?.title ?? '加载中...'))
          .fontSize(AppFont.Title)
          .fontColor(this.resolvedBgOption().fg)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: AppSpace.Sm })

        Text(`${this.currentIndex + 1}/${this.book?.chapters.length || 0}`)
          .fontSize(AppFont.Caption)
          .fontColor(this.resolvedBgOption().fg)
          .opacity(0.6)
      }
      .width('100%')
      .height(48)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .backgroundColor(this.resolvedBgOption().bg)

      // 进度条
      this.buildProgressBar()
    }
    .transition(TransitionEffect.OPACITY.animation({ duration: AppMotion.Base, curve: Curve.Smooth }))
  }

  @Builder
  buildProgressBar() {
    Stack({ alignContent: Alignment.Start }) {
      Row().width('100%').height(2)
        .backgroundColor(this.bgMode === 2 ? '#333333' : '#E8E8E8')
      Row().width(`${this.scrollPercent}%`).height(2)
        .backgroundColor(AppColor.Brand)
    }
    .width('100%').height(2)
  }

  @Builder
  buildBottomBar() {
    Row() {
      Column({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(22).fontColor([this.resolvedBgOption().fg])
        Text('书签').fontSize(10).fontColor(this.resolvedBgOption().fg)
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.sheetType = 'bookmarks'; this.sheetOpen = true; })

      Column({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(22).fontColor([this.resolvedBgOption().fg])
        Text('目录').fontSize(10).fontColor(this.resolvedBgOption().fg)
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.initChapterTab(); this.sheetType = 'chapters'; this.sheetOpen = true; })

      Column({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(22).fontColor([this.resolvedBgOption().fg])
        Text('设置').fontSize(10).fontColor(this.resolvedBgOption().fg)
      }
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.sheetType = 'settings'; this.sheetOpen = true; })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 12, bottom: 12 + WindowUtils.getBottomSafeVp() })
    .backgroundColor(this.resolvedBgOption().bg)
    .transition(TransitionEffect.OPACITY.animation({ duration: AppMotion.Base, curve: Curve.Smooth }))
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColor.Brand)
      Text('加载中...')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .margin({ top: AppSpace.Md })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.resolvedBgOption().bg)
  }

  @Builder
  buildError() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(40).fontColor([this.resolvedBgOption().fg])
      Text(this.errorMsg)
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
      Button('重试')
        .fontSize(AppFont.Body)
        .backgroundColor(AppColor.Brand)
        .fontColor(Color.White)
        .onClick(() => this.loadChapter(this.currentIndex))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.resolvedBgOption().bg)
  }

  @Builder
  buildContent() {
    if (this.flipMode === 0) {
      this.buildScrollContent()
    } else {
      this.buildPageContent()
    }
  }

  @Builder
  buildScrollContent() {
    List({ space: 0, scroller: this.scroller }) {
      ListItem() {
        Row().height(this.toolbarVisible ? AppSpace.Md : AppSpace.Lg)
      }
      LazyForEach(this.dataSource, (para: string, index: number) => {
        ListItem() {
          Text(para)
            .fontSize(this.fontSize)
            .fontFamily(this.fontFamily)
            .fontColor(this.resolvedBgOption().fg)
            .lineHeight(this.fontSize * this.lineSpacing)
            .textIndent(this.fontSize * 2)
            .width('100%')
            .padding({ bottom: this.fontSize * 0.6 })
        }
      }, (para: string, index: number) => this.dataSource.keyOf(index))
      ListItem() {
        Row().height(20)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.foldWide ? '8%' : '5%', right: this.foldWide ? '8%' : '5%' })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(8)
    .backgroundColor(this.resolvedBgOption().bg)
    .onReachEnd(() => {
      if (this.restoring || this.loading) return;
      if (!this.userScrolled) return;
      const chapters = this.book?.chapters || [];
      if (this.currentIndex < chapters.length - 1) {
        this.loadChapter(this.currentIndex + 1);
      }
    })
    .onScrollStart(() => {
      this.userScrolled = true;
      // 滑动开始时隐藏工具栏
      if (this.toolbarVisible) {
        animateTo({ duration: AppMotion.Fast, curve: Curve.Smooth }, () => {
          this.toolbarVisible = false;
        });
      }
      // 清除之前的定时器
      if (this.scrollHideTimer >= 0) {
        clearTimeout(this.scrollHideTimer);
        this.scrollHideTimer = -1;
      }
    })
    .onScrollIndex((first: number, _last: number) => {
      if (this.restoring) return;
      const total = this.dataSource.totalCount();
      if (total <= 1) {
        this.scrollPercent = 0;
      } else {
        this.scrollPercent = Math.min(100, Math.max(0, first / (total - 1) * 100));
      }
      this.scheduleSaveScrollPos(first);
    })
    .onScrollStop(() => {
      // 滚动停止后，延迟恢复工具栏显示（可选）
      // 如果需要自动恢复工具栏，取消下面的注释
      // if (this.scrollHideTimer >= 0) clearTimeout(this.scrollHideTimer);
      // this.scrollHideTimer = setTimeout(() => {
      //   if (!this.toolbarVisible) {
      //     animateTo({ duration: AppMotion.Base, curve: Curve.Smooth }, () => {
      //       this.toolbarVisible = true;
      //     });
      //   }
      //   this.scrollHideTimer = -1;
      // }, 2000);
    })
    .onAreaChange((_o, n) => {
      this.contentAreaHeight = n.height as number;
    })
  }

  @Builder
  buildPageContent() {
    Stack() {
      // 下一页（最底层，显示在当前页右侧之下，往左拖时露出）
      this.buildSinglePage(this.currentPage + 1, false)

      // 当前页：左拖跟随手指；右拖时由上一页覆盖在它上面
      Column() {
        this.buildSinglePage(this.currentPage, true)
      }
      .width('100%')
      .height('100%')
      .translate({ x: this.dragDirection < 0 ? this.pageOffsetX : 0 })
      .shadow({
        radius: this.flipMode === 2 && this.dragDirection < 0 && this.pageOffsetX < 0 ? 20 : 0,
        color: '#40000000', offsetX: -8, offsetY: 0
      })

      // 上一页：默认在屏幕外左边，往右拖时跟随手指进入
      Column() {
        this.buildSinglePage(this.currentPage - 1, false)
      }
      .width('100%')
      .height('100%')
      .translate({
        x: this.dragDirection > 0
          ? -this.pageWidth + this.pageOffsetX
          : -this.pageWidth
      })
      .shadow({
        radius: this.flipMode === 2 && this.dragDirection > 0 && this.pageOffsetX > 0 ? 20 : 0,
        color: '#40000000', offsetX: 8, offsetY: 0
      })
    }
    .alignContent(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.resolvedBgOption().bg)
    .onAreaChange((_o, n) => {
      this.contentAreaHeight = n.height as number;
      this.pageWidth = n.width as number;
      this.refreshPages();
    })
  }

  @Builder
  buildSinglePage(pageIdx: number, isCurrent: boolean) {
    if (pageIdx >= 0 && pageIdx < this.pageCount) {
      Column() {
        ForEach(this.getPageParas(pageIdx), (para: string, idx: number) => {
          Text(para)
            .fontSize(this.fontSize)
            .fontFamily(this.fontFamily)
            .fontColor(this.resolvedBgOption().fg)
            .lineHeight(this.fontSize * this.lineSpacing)
            .textIndent(this.fontSize * 2)
            .width('100%')
            .padding({ bottom: this.fontSize * 0.6 })
        }, (para: string, idx: number) => `${pageIdx}_${idx}_${isCurrent}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.foldWide ? '8%' : '5%', right: this.foldWide ? '8%' : '5%', top: 16 })
      .clip(true)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.resolvedBgOption().bg)
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolvedBgOption().bg)
    }
  }

  // 翻页手势：跟手拖动 + 松手回弹/完成
  private startFlipDrag(direction: number): void {
    if (this.flipping) return;
    if (direction < 0 && this.currentPage >= this.pageCount - 1) {
      const chapters = this.book?.chapters || [];
      if (this.currentIndex >= chapters.length - 1) {
        this.showToast('已是最后一页');
        return;
      }
    }
    if (direction > 0 && this.currentPage <= 0) {
      if (this.currentIndex <= 0) {
        this.showToast('已是第一页');
        return;
      }
    }
    this.dragDirection = direction;
  }

  private updateFlipDrag(offsetX: number): void {
    if (this.flipping) return;
    if (this.dragDirection < 0) {
      // 向左拖，offsetX 为负
      this.pageOffsetX = Math.max(-this.pageWidth, Math.min(0, offsetX));
    } else if (this.dragDirection > 0) {
      // 向右拖，offsetX 为正
      this.pageOffsetX = Math.max(0, Math.min(this.pageWidth, offsetX));
    }
  }

  private endFlipDrag(velocity: number): void {
    if (this.flipping) return;
    if (this.dragDirection === 0) {
      this.pageOffsetX = 0;
      return;
    }
    const threshold = this.pageWidth * 0.25;
    const fast = Math.abs(velocity) > 600;
    const distance = Math.abs(this.pageOffsetX);
    const shouldFlip = distance > threshold || fast;
    const dir = this.dragDirection;
    this.flipping = true;
    if (shouldFlip) {
      const target = dir < 0 ? -this.pageWidth : this.pageWidth;
      animateTo({
        duration: 280,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.commitFlip(dir);
          this.flipping = false;
        }
      }, () => {
        this.pageOffsetX = target;
      });
    } else {
      animateTo({
        duration: 220,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.dragDirection = 0;
          this.flipping = false;
        }
      }, () => {
        this.pageOffsetX = 0;
      });
    }
  }

  private commitFlip(direction: number): void {
    const next = this.currentPage + (direction < 0 ? 1 : -1);
    if (next < 0) {
      // 翻到上一章
      const targetIdx = this.currentIndex - 1;
      this.pageOffsetX = 0;
      this.dragDirection = 0;
      if (targetIdx >= 0) {
        this.flushScrollPos();
        this.loadChapter(targetIdx).then(() => {
          this.currentPage = Math.max(0, this.pageCount - 1);
          this.updateScrollPercent();
        });
      }
      return;
    }
    if (next >= this.pageCount) {
      // 翻到下一章
      const chapters = this.book?.chapters || [];
      const targetIdx = this.currentIndex + 1;
      this.pageOffsetX = 0;
      this.dragDirection = 0;
      if (targetIdx < chapters.length) {
        this.flushScrollPos();
        this.loadChapter(targetIdx);
      }
      return;
    }
    this.currentPage = next;
    this.pageOffsetX = 0;
    this.dragDirection = 0;
    this.updateScrollPercent();
  }

  private flipByTap(direction: number): void {
    if (this.flipping) return;
    if (direction < 0 && this.currentPage >= this.pageCount - 1) {
      const chapters = this.book?.chapters || [];
      if (this.currentIndex >= chapters.length - 1) {
        this.showToast('已是最后一页');
        return;
      }
    }
    if (direction > 0 && this.currentPage <= 0) {
      if (this.currentIndex <= 0) {
        this.showToast('已是第一页');
        return;
      }
    }
    this.dragDirection = direction;
    const target = direction < 0 ? -this.pageWidth : this.pageWidth;
    this.flipping = true;
    animateTo({
      duration: 280,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.commitFlip(direction);
        this.flipping = false;
      }
    }, () => {
      this.pageOffsetX = target;
    });
  }

  // 单击中间 toggle 工具栏 / 双击书签 / 捏合字号 / 左侧上下滑亮度
  @Builder
  buildTapZones() {
    Row() {
      if (this.flipMode > 0) {
        // 左侧点击翻上页
        Column()
          .width('30%')
          .height('100%')
          .onClick(() => this.flipByTap(1))
        // 中间 toggle 工具栏
        Column()
          .width('40%')
          .height('100%')
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2 }).onAction(() => { this.toggleBookmarkAtCurrent(); }),
              TapGesture({ count: 1 }).onAction(() => {
                animateTo({ duration: AppMotion.Base, curve: Curve.Smooth }, () => {
                  this.toolbarVisible = !this.toolbarVisible;
                });
              })
            )
          )
        // 右侧点击翻下页
        Column()
          .width('30%')
          .height('100%')
          .onClick(() => this.flipByTap(-1))
      } else {
        Column()
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 }).onAction(() => { this.toggleBookmarkAtCurrent(); }),
        TapGesture({ count: 1 }).onAction(() => {
          if (this.flipMode > 0) return;
          animateTo({ duration: AppMotion.Base, curve: Curve.Smooth }, () => {
            this.toolbarVisible = !this.toolbarVisible;
          });
        })
      )
    )
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, fingers: 1, distance: 10 })
        .onActionStart((evt: GestureEvent) => {
          if (this.flipMode === 0 || this.flipping) return;
          const dir = evt.offsetX < 0 ? -1 : 1;
          this.startFlipDrag(dir);
        })
        .onActionUpdate((evt: GestureEvent) => {
          if (this.flipMode === 0 || this.dragDirection === 0) return;
          this.updateFlipDrag(evt.offsetX);
        })
        .onActionEnd((evt: GestureEvent) => {
          if (this.flipMode === 0 || this.dragDirection === 0) return;
          this.endFlipDrag(evt.velocityX);
        })
        .onActionCancel(() => {
          if (this.dragDirection !== 0) {
            this.endFlipDrag(0);
          }
        })
    )
  }

  @Builder
  buildHud() {
    Column({ space: AppSpace.Xs }) {
      if (this.hudKind === 'brightness') {
        SymbolGlyph($r('sys.symbol.sun_max'))
          .fontSize(28).fontColor(['#FFFFFF'])
        Text(`${this.hudValue}%`)
          .fontSize(AppFont.BodyL)
          .fontColor('#FFFFFF')
      } else {
        Text('T')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text(`${this.hudValue}fp`)
          .fontSize(AppFont.BodyL)
          .fontColor('#FFFFFF')
      }
    }
    .padding(AppSpace.Md)
    .backgroundColor('#CC000000')
    .borderRadius(AppRadius.Md)
    .transition(TransitionEffect.OPACITY.animation({ duration: AppMotion.Fast, curve: Curve.Smooth }))
  }

  @Builder
  buildToast() {
    Column() {
      Text(this.toast)
        .fontSize(AppFont.Body)
        .fontColor('#FFFFFF')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .backgroundColor('#CC000000')
        .borderRadius(AppRadius.Pill)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .position({ y: '70%' })
  }

  // ============ 设置面板 ============

  @Builder
  buildSettingsPanel() {
    Column({ space: 0 }) {
      // 标题区
      Column({ space: 4 }) {
        Text('阅读设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolvedBgOption().fg)
        Text('个性化你的阅读体验')
          .fontSize(AppFont.Caption)
          .fontColor(this.resolvedBgOption().fg)
          .opacity(0.5)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Md })

      Scroll() {
        Column({ space: AppSpace.Md }) {
          this.buildBrightnessRow()
          this.buildFontSizeRow()
          this.buildLineSpacingRow()
          this.buildFontFamilyRow()
          this.buildFlipModeRow()
          this.buildThemeSection()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

      // 底部提示
      Row() {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14).fontColor([this.resolvedBgOption().fg]).opacity(0.5)
        Text('所有设置自动保存')
          .fontSize(AppFont.Caption)
          .fontColor(this.resolvedBgOption().fg)
          .opacity(0.5)
          .margin({ left: 4 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: AppSpace.Sm, bottom: AppSpace.Md + WindowUtils.getBottomSafeVp() })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildBrightnessRow() {
    Row({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.sun_max'))
        .fontSize(20).fontColor([this.resolvedBgOption().fg])
      Text('亮度')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
      Slider({
        value: this.brightnessVal < 0 ? 50 : this.brightnessVal * 100,
        min: 0, max: 100, step: 1, style: SliderStyle.InSet
      })
        .blockColor(AppColor.Brand)
        .selectedColor(AppColor.Brand)
        .trackThickness(4)
        .layoutWeight(1)
        .onChange((v: number) => this.setBrightness(v / 100, false))
        .onTouch((evt: TouchEvent) => {
          if (evt.type === TouchType.Up && this.brightnessVal >= 0) {
            PreferenceService.setReaderBrightness(this.brightnessVal);
          }
        })
      Text(this.brightnessVal < 0 ? '系统' : `${Math.round(this.brightnessVal * 100)}%`)
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .width(48)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildFontSizeRow() {
    Row({ space: AppSpace.Sm }) {
      Text('aA')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvedBgOption().fg)
        .width(24)
      Text('字号')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
      Slider({
        value: this.fontSize,
        min: FONT_MIN, max: this.maxFontSize(), step: 1, style: SliderStyle.InSet
      })
        .blockColor(AppColor.Brand)
        .selectedColor(AppColor.Brand)
        .trackThickness(4)
        .layoutWeight(1)
        .onChange((v: number) => this.setFontSize(v, false))
        .onTouch((evt: TouchEvent) => {
          if (evt.type === TouchType.Up) {
            PreferenceService.setReaderFontSize(this.fontSize);
          }
        })
      Text(`${this.fontSize}`)
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .width(36)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildLineSpacingRow() {
    Row({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.text_alignleft'))
        .fontSize(20).fontColor([this.resolvedBgOption().fg])
      Text('行距')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
      Slider({
        value: this.lineSpacing * 10,
        min: 12, max: 28, step: 1, style: SliderStyle.InSet
      })
        .blockColor(AppColor.Brand)
        .selectedColor(AppColor.Brand)
        .trackThickness(4)
        .layoutWeight(1)
        .onChange((v: number) => {
          const sp = Math.round(v) / 10;
          if (Math.abs(sp - this.lineSpacing) < 0.05) return;
          this.lineSpacing = sp;
          if (this.flipMode > 0) this.refreshPages();
        })
        .onTouch((evt: TouchEvent) => {
          if (evt.type === TouchType.Up) {
            PreferenceService.setReaderLineSpacing(this.lineSpacing);
          }
        })
      Text(this.lineSpacing.toFixed(1))
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .width(36)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildFontFamilyRow() {
    Row({ space: AppSpace.Sm }) {
      Text('Tt')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvedBgOption().fg)
        .width(20)
      Text('字体')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
      Row().layoutWeight(1)
      Text(FONT_OPTIONS.find(f => f.family === this.fontFamily)?.label || '系统')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .opacity(0.6)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16).fontColor([this.resolvedBgOption().fg]).opacity(0.4)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      const idx = FONT_OPTIONS.findIndex(f => f.family === this.fontFamily);
      const next = FONT_OPTIONS[(idx + 1) % FONT_OPTIONS.length];
      this.setFontFamily(next.family);
    })
  }

  @Builder
  buildFlipModeRow() {
    Column({ space: 8 }) {
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(20).fontColor([this.resolvedBgOption().fg])
        Text('翻页模式')
          .fontSize(AppFont.Body)
          .fontColor(this.resolvedBgOption().fg)
      }
      .width('100%')

      Row({ space: 12 }) {
        ForEach(FLIP_MODE_OPTIONS, (opt: FlipModeOption, idx: number) => {
          Column({ space: 4 }) {
            SymbolGlyph(opt.icon)
              .fontSize(24)
              .fontColor([this.flipMode === idx ? AppColor.Brand : this.resolvedBgOption().fg])
            Text(opt.label)
              .fontSize(AppFont.Caption)
              .fontColor(this.flipMode === idx ? AppColor.Brand : this.resolvedBgOption().fg)
          }
          .layoutWeight(1)
          .height(56)
          .justifyContent(FlexAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.flipMode === idx ? '#1A' + AppColor.Brand.substring(1) : 'transparent')
          .border({
            width: this.flipMode === idx ? 1 : 0.5,
            color: this.flipMode === idx ? AppColor.Brand : this.resolvedBgOption().fg,
            style: BorderStyle.Solid
          })
          .opacity(this.flipMode === idx ? 1 : 0.6)
          .onClick(() => {
            this.flipMode = idx;
            PreferenceService.setReaderFlipMode(idx);
          })
        }, (opt: FlipModeOption, idx: number) => `${idx}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  buildThemeSection() {
    Column({ space: AppSpace.Sm }) {
      Text('主题')
        .fontSize(AppFont.Body)
        .fontColor(this.resolvedBgOption().fg)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(BG_OPTIONS, (item: BgOption) => {
          this.buildThemeCard(item)
        }, (item: BgOption) => item.mode.toString())
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
  }

  @Builder
  buildThemeCard(item: BgOption) {
    Column({ space: 6 }) {
      Stack() {
        Column({ space: 3 }) {
          Row().width('80%').height(2).backgroundColor(item.fg).opacity(0.6).borderRadius(1)
          Row().width('60%').height(2).backgroundColor(item.fg).opacity(0.4).borderRadius(1)
          Row().width('70%').height(2).backgroundColor(item.fg).opacity(0.4).borderRadius(1)
        }
        .width(56).height(56)
        .padding(8)
        .backgroundColor(item.mode === -1 ? (this.sysDark ? BG_OPTIONS[3].bg : BG_OPTIONS[1].bg) : item.bg)
        .borderRadius(8)
        .border({
          width: this.bgMode === item.mode ? 2 : 1,
          color: this.bgMode === item.mode ? AppColor.Brand : (item.mode === 2 ? '#444444' : '#E0E0E0')
        })
        .alignItems(HorizontalAlign.Start)
        if (this.bgMode === item.mode) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(16)
            .fontColor([AppColor.Brand])
            .position({ x: '100%', y: '100%' })
            .translate({ x: -8, y: -8 })
        }
      }
      .alignContent(Alignment.BottomEnd)
      Text(item.label)
        .fontSize(12)
        .fontColor(this.resolvedBgOption().fg)
        .opacity(0.7)
    }
    .layoutWeight(1)
    .onClick(() => this.setBgMode(item.mode))
  }

  @Builder
  buildChapterList() {
    Column() {
      Text('目录')
        .fontSize(AppFont.Title)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvedBgOption().fg)
        .padding({ left: AppSpace.Md, top: AppSpace.Md, bottom: AppSpace.Sm })
        .width('100%')

      if ((this.book?.chapters || []).length > 100) {
        this.buildChapterTabs()
      } else {
        this.buildChapterPlainList(this.book?.chapters || [], 0)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildChapterTabs() {
    Column() {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.chapterTabLabels(), (label: string, idx: number) => {
            Text(label)
              .fontSize(AppFont.Body)
              .fontColor(idx === this.chapterTabIdx ? '#FFFFFF' : this.resolvedBgOption().fg)
              .backgroundColor(idx === this.chapterTabIdx ? AppColor.Brand : 'transparent')
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => { this.chapterTabIdx = idx; })
          }, (label: string, idx: number) => `${idx}`)
        }
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(40)

      List({ scroller: this.chapterListScroller }) {
        ForEach(this.chapterTabSlice(), (ch: Chapter, idx: number) => {
          ListItem() {
            Text(ch.title)
              .fontSize(AppFont.Body)
              .fontColor((this.chapterTabIdx * CHAPTER_GROUP_SIZE + idx) === this.currentIndex ? AppColor.Brand : this.resolvedBgOption().fg)
              .fontWeight((this.chapterTabIdx * CHAPTER_GROUP_SIZE + idx) === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: AppSpace.Md, right: AppSpace.Md, top: 12, bottom: 12 })
              .width('100%')
          }
          .onClick(() => {
            this.sheetOpen = false;
            this.flushScrollPos();
            this.loadChapter(this.chapterTabIdx * CHAPTER_GROUP_SIZE + idx);
          })
        }, (ch: Chapter, _idx: number) => `${this.chapterTabIdx}_${ch.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .layoutWeight(1)
  }

  @Builder
  buildChapterPlainList(chapters: Chapter[], baseIdx: number) {
    List({ scroller: this.chapterListScroller }) {
      ForEach(chapters, (ch: Chapter, idx: number) => {
        ListItem() {
          Text(ch.title)
            .fontSize(AppFont.Body)
            .fontColor((baseIdx + idx) === this.currentIndex ? AppColor.Brand : this.resolvedBgOption().fg)
            .fontWeight((baseIdx + idx) === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: AppSpace.Md, right: AppSpace.Md, top: 12, bottom: 12 })
            .width('100%')
        }
        .onClick(() => {
          this.sheetOpen = false;
          this.sheetType = 'none';
          this.flushScrollPos();
          this.loadChapter(baseIdx + idx);
        })
      }, (ch: Chapter, _idx: number) => ch.id)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  buildBookmarkList() {
    Column() {
      Text(`书签 (${this.bookmarks.length})`)
        .fontSize(AppFont.Title)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvedBgOption().fg)
        .padding({ left: AppSpace.Md, top: AppSpace.Md, bottom: AppSpace.Sm })
        .width('100%')
      if (this.bookmarks.length === 0) {
        Column() {
          Text('在阅读时双击屏幕中央可添加书签')
            .fontSize(AppFont.Body)
            .fontColor(this.resolvedBgOption().fg)
            .opacity(0.6)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.bookmarks, (m: ReaderBookmark) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(m.chapterTitle)
                  .fontSize(AppFont.Body)
                  .fontColor(this.resolvedBgOption().fg)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(m.preview || '(空段落)')
                  .fontSize(AppFont.Caption)
                  .fontColor(this.resolvedBgOption().fg)
                  .opacity(0.7)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .padding({ left: AppSpace.Md, right: AppSpace.Md, top: 12, bottom: 12 })
              .width('100%')
            }
            .onClick(() => this.jumpToBookmark(m))
            .swipeAction({
              end: this.buildBookmarkSwipe(m)
            })
          }, (m: ReaderBookmark) => `${m.chapterId}#${m.paraIndex}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildBookmarkSwipe(m: ReaderBookmark) {
    Row() {
      Button('删除')
        .height(48)
        .backgroundColor('#E64646')
        .fontColor(Color.White)
        .fontSize(AppFont.Body)
        .borderRadius(0)
        .onClick(async () => {
          if (!this.book) return;
          await PreferenceService.removeBookmark(this.book.id, m.chapterId, m.paraIndex);
          this.bookmarks = await PreferenceService.getBookmarks(this.book.id);
        })
    }
    .height(48)
  }
}
