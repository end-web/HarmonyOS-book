import { common } from '@kit.AbilityKit';
import { emitter, BusinessError, batteryInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display } from '@kit.ArkUI';
import { bookParser, ReadPageComponent, readerCore } from '@kit.ReaderKit';
import { AppColor, AppFont, AppRadius, AppSpace, AppCurve } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { PreferenceService, ReaderSettingsItem } from '../service/PreferenceService';
import { ReaderService } from '../service/ReaderService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { EVT_HISTORY_UPDATED } from '../service/AudioService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { DataService } from '../service/DataService';
import { EVT_SWITCH_TAB } from './ImportPage';

/** 详情页(由阅读页进入)点章节 → 通知阅读页:弹掉详情并切到该章。payload: { bookId, chapterId } */
export const EVT_READER_JUMP_CHAPTER = 'app.reader.jumpChapter';

interface ReaderTheme {
  name: string;
  bg: string;
  text: string;
  sub: string;
  /** 工具栏毛玻璃底色(带透明度,配合 backdropBlur) */
  glass: string;
}

/** 索引 0=系统白;1=护眼米(默认,贴合截图纸质风);末位=夜间 */
const READER_THEMES: ReaderTheme[] = [
  { name: '白', bg: '#FFFFFFFF', text: '#FF1A1A1A', sub: '#99555555', glass: 'rgba(255, 255, 255, 0.72)' },
  { name: '米', bg: '#FFFAF3E8', text: '#FF3A332A', sub: '#99746A5A', glass: 'rgba(250, 243, 232, 0.78)' },
  { name: '绿', bg: '#FFE9F1E7', text: '#FF2A352B', sub: '#99586A5B', glass: 'rgba(233, 241, 231, 0.78)' },
  { name: '夜', bg: '#FF121212', text: '#FFD8D5CF', sub: '#99999086', glass: 'rgba(18, 18, 18, 0.72)' },
];
const NIGHT_INDEX = 3;
/** 进页默认主题:护眼米(索引 1) */
const DEFAULT_THEME_INDEX = 1;
/** 工具栏显隐动画时长(ms),按 UI 规范取 300 */
const TOOLBAR_ANIM = 300;

/** #AARRGGBB / #RRGGBB -> rgba(r, g, b, a)（Reader Kit themeColor 接受 rgba 或 6 位 hex,统一走 rgba） */
function toRgba(c: string): string {
  let hex = c;
  if (hex.charAt(0) === '#') hex = hex.substring(1);
  let a = 1;
  let r = 0;
  let g = 0;
  let b = 0;
  if (hex.length === 8) {
    a = parseInt(hex.substring(0, 2), 16) / 255;
    r = parseInt(hex.substring(2, 4), 16);
    g = parseInt(hex.substring(4, 6), 16);
    b = parseInt(hex.substring(6, 8), 16);
  } else if (hex.length === 6) {
    r = parseInt(hex.substring(0, 2), 16);
    g = parseInt(hex.substring(2, 4), 16);
    b = parseInt(hex.substring(4, 6), 16);
  }
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

/** #AARRGGBB / #RRGGBB -> #RRGGBB（Reader Kit fontColor 用 6 位 hex，对齐官方示例） */
function hex6(c: string): string {
  if (c.length === 9 && c.charAt(0) === '#') {
    return '#' + c.substring(3);
  }
  return c;
}

/** 目录搜索结果行:章节 + 在完整目录中的原始索引 */
interface ChapterRow {
  ch: Chapter;
  idx: number;
}

interface PageBounds {
  parsed: boolean;
  current: number;
  total: number;
  isFirst: boolean;
  isLast: boolean;
}

function parsePageBounds(footer: string): PageBounds {
  const empty: PageBounds = { parsed: false, current: 0, total: 0, isFirst: false, isLast: false };
  if (!footer) return empty;
  const patterns: RegExp[] = [
    /(\d+)\s*[\/／]\s*(\d+)/,
    /第?\s*(\d+)\s*页\s*(?:共|\/|／|of)?\s*(\d+)\s*页?/i,
    /(\d+)\s*页?\s*(?:共|of)\s*(\d+)\s*页?/i
  ];
  for (const pattern of patterns) {
    const m = footer.match(pattern);
    if (!m) continue;
    const current = parseInt(m[1], 10);
    const total = parseInt(m[2], 10);
    if (!isNaN(current) && !isNaN(total) && total > 0) {
      return {
        parsed: true,
        current,
        total,
        isFirst: current <= 1,
        isLast: current >= total
      };
    }
  }
  return empty;
}

@ComponentV2
export struct ReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param resumeChapterId: string = '';
  @Param resumeProgressMs: number = 0;

  @Local book: Book | null = null;
  @Local currentChapter: Chapter | null = null;
  @Local chapterIndex: number = -1;
  @Local loading: boolean = true;
  @Local errorMsg: string = '';
  @Local toolbarVisible: boolean = false;
  // 底部抽屉:统一一个 bindSheet。sheetMode 0=关,1=目录,2=设置。
  // (多个 bindSheet 链式挂在同一组件上会冲突,导致第二个"设置"打不开)
  @Local sheetOpen: boolean = false;
  @Local sheetMode: number = 0;
  @Local fontSize: number = 18;
  @Local lineHeight: number = 1.9;
  /** 目录搜索关键词 */
  @Local chapterQuery: string = '';
  @Local themeIndex: number = 0;
  @Local flipModeIndex: number = 0; // 0=仿真翻页, 1=平移翻页
  @Local pageFooter: string = '';
  // 屏幕亮度:-1=跟随系统, [0,1]=覆盖。命名避开组件内置 .brightness() 属性
  @Local screenBrightness: number = -1;
  @Local hudTime: string = '';
  @Local batteryPercent: number = -1;

  private context: common.UIAbilityContext | null = null;
  private chapterScroller: Scroller = new Scroller();
  private readerController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  private inited: boolean = false;
  private opened: boolean = false;
  private isLeaving: boolean = false;
  private switching: boolean = false;
  private pageShowBound: boolean = false;
  private currentDomPos: string = '';
  private lastPersistAt: number = 0;
  // 每次 openChapter 自增,失效旧的兜底定时器/异步分支
  private openSeq: number = 0;
  // 翻页边界检测:flipPage 后等 pageShow,超时未变页=到边界
  private flipSeq: number = 0;
  private pendingDir: number = 0; // 1=向后翻待确认, -1=向前翻待确认, 0=无
  // driveFlip 翻页前记录的页起始位置;pageShow 回来若 startDomPos 相同=没翻动(到章首/章末)
  private flipBaselineDomPos: string = '';
  private flipBaselineFooter: string = '';
  private flipBaselineAtLastPage: boolean = false;
  private flipBaselineAtFirstPage: boolean = false;
  // 排版视口实测尺寸(px)。用组件实际尺寸而非屏幕尺寸,避免窗口≠屏幕导致的留白/拉伸
  private pageViewW: number = 0;
  private pageViewH: number = 0;
  private hudTimerId: number = -1;
  // 当前页在本章的位置(从 pageFooterContent 解析),用于快速判断首/末页
  private isLastPage: boolean = false;
  private isFirstPage: boolean = false;
  // ReadPageComponent 必须先就绪(readerCallback 触发),否则排版引擎(textTpl)未挂载,
  // register/startPlay 会静默失败(getSpineItemContent Invalid request)→ 黑屏。书架直达比搜索更快会撞上此竞态。
  private componentReady: boolean = false;
  private pendingRender: boolean = false;
  private renderHandler: bookParser.BookParserHandler | null = null;
  private renderSpineIndex: number = 0;
  private renderDomPos: string = '';
  private renderOpenId: number = 0;

  /**
   * 详情页(由本阅读页进入)点章节:先弹掉详情页让本页回到栈顶,隔帧再把本页替换成目标章的新阅读页实例。
   * 「弹详情」与「替换」必须分两个事件循环回合(同一回合 pop+replace 不能正确合成,会残留旧阅读页)。
   */
  private onJumpChapter = (evt: emitter.EventData): void => {
    const d = evt.data as Record<string, Object> | undefined;
    if (!d || !this.book) return;
    if ((d.bookId as string) !== this.bookId) return;
    const idx = DataService.resolveChapterIndex(this.book, (d.chapterId as string) ?? '');
    if (idx < 0) return;
    try { this.navStack.pop(false); } catch (_e) { /* ignore */ } // 弹掉详情页(回合一)
    if (idx === this.chapterIndex) return; // 同章:仅关闭详情
    setTimeout((): void => {
      if (!this.isLeaving) this.navigateToChapter(idx); // 替换为目标章新实例(回合二)
    }, 50);
  };

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 先按系统深浅给默认主题:浅色→护眼米,深色→夜间,避免深色模式下闪白
    this.themeIndex = WindowUtils.isDarkMode() ? NIGHT_INDEX : DEFAULT_THEME_INDEX;
    this.applyStatusBar();
    WindowUtils.setStatusBarVisible(false);
    this.startHudTicker();
    emitter.on(EVT_READER_JUMP_CHAPTER, this.onJumpChapter);
    this.bootstrap();
  }

  aboutToDisappear(): void {
    this.isLeaving = true;
    // 离开阅读页恢复系统亮度,避免覆盖值影响其他页面
    WindowUtils.setReaderBrightness(-1);
    WindowUtils.setStatusBarVisible(true);
    this.stopHudTicker();
    this.persistProgress(true);
    if (this.pageShowBound) {
      try { this.readerController.off('pageShow'); } catch (_e) { /* ignore */ }
    }
    try { emitter.off(EVT_READER_JUMP_CHAPTER); } catch (_e) { /* ignore */ }
    try { this.readerController.releaseBook(); } catch (_e) { /* ignore */ }
  }

  /** 先加载持久化的阅读外观设置(覆盖默认),再加载书与章节 */
  private bootstrap(): void {
    PreferenceService.getReaderSettings().then((s: ReaderSettingsItem | null): void => {
      if (s) {
        if (s.fontSize > 0) this.fontSize = s.fontSize;
        if (s.themeIndex >= 0 && s.themeIndex < READER_THEMES.length) this.themeIndex = s.themeIndex;
        if (s.flipModeIndex === 0 || s.flipModeIndex === 1) this.flipModeIndex = s.flipModeIndex;
        if (s.lineHeight !== undefined && s.lineHeight >= 1.2 && s.lineHeight <= 2.4) this.lineHeight = s.lineHeight;
        if (s.brightness !== undefined && s.brightness >= 0 && s.brightness <= 1) {
          this.screenBrightness = s.brightness;
          WindowUtils.setReaderBrightness(s.brightness);
        }
        this.applyStatusBar();
      }
    }).catch((): void => { /* ignore */ }).then((): Promise<void> => this.loadBookAndChapter())
      .catch((): void => { /* ignore */ });
  }

  private theme(): ReaderTheme {
    return READER_THEMES[Math.max(0, Math.min(this.themeIndex, READER_THEMES.length - 1))];
  }

  private applyStatusBar(): void {
    // 夜间主题用浅色(白)状态栏图标,其余跟随系统
    WindowUtils.setStatusBarLight(this.themeIndex === NIGHT_INDEX);
  }

  private persistReaderSettings(): void {
    const item: ReaderSettingsItem = {
      fontSize: this.fontSize,
      themeIndex: this.themeIndex,
      flipModeIndex: this.flipModeIndex,
      brightness: this.screenBrightness,
      lineHeight: this.lineHeight
    };
    PreferenceService.setReaderSettings(item).catch((): void => { /* ignore */ });
  }

  /**
   * 注册页面展示回调。组件常驻(不再 remount),整页生命周期只绑一次。
   * 不再按 version/openId 过滤:切章用 releaseBook + 重新 registerBookParser + startPlay,
   * 旧章 pageShow 不会在 releaseBook 后到达;当前 pageShow 即对应当前章。
   */
  private registerPageShow(): void {
    try {
      if (this.pageShowBound) return;
      this.readerController.on('pageShow', (data: readerCore.PageDataInfo): void => {
        if (this.isLeaving) return;
        hilog.info(0x9527, 'RdrDbg', 'pageShow state=%{public}d footer=%{public}s startDom=%{public}s resIdx=%{public}d',
          data.state, data.pageFooterContent, data.startDomPos, data.resourceIndex);
        if (data.state === readerCore.PageState.PAGE_ON_SHOW) {
          // 翻页后页起始位置没变(startDomPos 相同)= 已到章首/章末,这次翻页是 no-op。
          // 有些机型/翻页模式下 Reader Kit 到末页仍会回调 pageShow,且 startDomPos 可能轻微变化;
          // 此时再用页脚和翻页前的首末页状态兜底,避免误判为翻页成功而停在当前章。
          // 保留 pendingDir 不清,交给 driveFlip 的 280ms 超时去自动续章(避免连跳)。
          if (this.isBoundaryNoopPageShow(data.pageFooterContent, data.startDomPos)) {
            this.pageFooter = data.pageFooterContent;
            this.updatePageBounds(data.pageFooterContent);
            return;
          }
          this.loading = false;
          this.errorMsg = ''; // 正文已出页:清掉可能由兜底/初始化失败设过的错误态,避免错误页盖住正文
          this.pendingDir = 0; // 真实翻页发生,取消边界待确认
          this.currentDomPos = data.startDomPos;
          this.pageFooter = data.pageFooterContent;
          this.updatePageBounds(data.pageFooterContent);
          this.persistProgress(false);
        } else if (data.state === readerCore.PageState.OPEN_BOOK_FAIL) {
          this.loading = false;
          this.errorMsg = '打开本章失败';
        }
      });
      this.pageShowBound = true;
    } catch (_e) { /* ignore */ }
  }

  /** 解析 "cur/total" 形式的页脚,更新首/末页标记;解析不出则保持 false,交给翻页超时兜底 */
  private updatePageBounds(footer: string): void {
    this.isLastPage = false;
    this.isFirstPage = false;
    const bounds = parsePageBounds(footer);
    if (!bounds.parsed) return;
    this.isLastPage = bounds.isLast;
    this.isFirstPage = bounds.isFirst;
  }

  private isBoundaryNoopPageShow(footer: string, startDomPos: string): boolean {
    if (this.pendingDir === 0) return false;
    if (startDomPos && startDomPos === this.flipBaselineDomPos) return true;
    if (footer && footer === this.flipBaselineFooter) return true;
    const bounds = parsePageBounds(footer);
    if (this.pendingDir > 0 && this.flipBaselineAtLastPage && (!bounds.parsed || bounds.isLast)) return true;
    if (this.pendingDir < 0 && this.flipBaselineAtFirstPage && (!bounds.parsed || bounds.isFirst)) return true;
    return false;
  }

  private buildSetting(): readerCore.ReaderSetting {
    let d: display.Display | null = null;
    try {
      d = display.getDefaultDisplaySync();
    } catch (_e) {
      d = null;
    }
    const t = this.theme();
    const night = this.themeIndex === NIGHT_INDEX;
    const vw = this.pageViewW > 0 ? this.pageViewW : (d ? d.width : 1080);
    const vh = this.pageViewH > 0 ? this.pageViewH : (d ? d.height : 1920);
    hilog.info(0x9527, 'RdrDbg', 'buildSetting vp=%{public}dx%{public}d', vw, vh);
    const setting: readerCore.ReaderSetting = {
      // 纯系统字体:fontName='系统字体' + fontPath=''(不引入任何字体文件)
      fontName: '系统字体',
      fontPath: '',
      fontSize: this.fontSize,
      fontWeight: 400,
      fontColor: hex6(t.text),
      lineHeight: this.lineHeight, // 用户设置的行距(settingSheet 行距滑块)
      nightMode: night,
      themeColor: toRgba(t.bg),
      themeBgImg: '',
      flipMode: this.flipModeIndex === 1 ? '1' : '0',
      scaledDensity: d && d.scaledDensity > 0 ? d.scaledDensity : 1,
      // 优先用实测组件尺寸(铺满不拉伸);未测到时回退屏幕尺寸
      viewPortWidth: vw,
      viewPortHeight: vh,
    };
    return setting;
  }

  private async loadBookAndChapter(): Promise<void> {
    if (!this.context || !this.bookId) {
      this.errorMsg = '缺少书籍参数';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      let book = await ReaderService.getBook(this.context, this.bookId);
      if (this.isLeaving) return;
      if (!book) {
        this.errorMsg = '书籍不存在';
        this.loading = false;
        return;
      }
      const loaded: Book = await ReaderService.ensureChapters(book);
      if (this.isLeaving) return;
      this.book = loaded;
      if (!loaded.chapters || loaded.chapters.length === 0) {
        this.errorMsg = '暂无章节';
        this.loading = false;
        return;
      }
      let idx = 0;
      let domPos = '';
      const prog = await PreferenceService.getProgress(loaded.id);
      // 1) 调用方指定的章节(从书架带过来的 resumeChapterId)优先
      if (this.resumeChapterId) {
        const hit = DataService.resolveChapterIndex(loaded, this.resumeChapterId);
        if (hit >= 0) idx = hit;
      }
      // 2) 用持久化进度补全:章节(若未指定)+ 章内位置 domPos。
      //    关键:只要 prog 指向"要打开的这一章"(按解析后的索引比对,标题容错),
      //    就恢复 domPos —— 不再要求 chapterId 字符串完全相等(位置型 id 会漂移)。
      if (prog) {
        const progIdx = DataService.resolveChapterIndex(loaded, prog.chapterId, prog.chapterTitle);
        if (progIdx >= 0) {
          if (!this.resumeChapterId) idx = progIdx;
          if (progIdx === idx && prog.domPos) domPos = prog.domPos;
        }
      } else {
        // 3) 没有 progress,退回播放历史
        const history = await PreferenceService.getHistory();
        const h = history.find((it) => it.bookId === loaded.id);
        if (h) {
          const hit = DataService.resolveChapterIndex(loaded, h.chapterId, h.chapterTitle);
          if (hit >= 0) { idx = hit; domPos = h.domPos ?? ''; }
        }
      }
      await this.openChapter(idx, domPos);
    } catch (e) {
      if (this.isLeaving) return;
      this.errorMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    }
  }

  /**
   * 兜底定时器:在任何 await 之前同步挂起。若超时仍 loading(startPlay 静默未触发 pageShow,
   * 多为 stale domPos 或组件渲染异常),先从章首重渲染,再不行则停止转圈,绝不无限加载。
   */
  private armLoadingFailsafe(openId: number): void {
    setTimeout((): void => {
      if (this.isLeaving || openId !== this.openSeq || !this.loading) return;
      // 仍在 loading:多为 stale domPos 导致 startPlay 不触发 pageShow。从章首重挂重渲染。
      hilog.warn(0x9527, 'RdrDbg', 'failsafe: no pageShow, re-render from head openId=%{public}d ready=%{public}s',
        openId, String(this.componentReady));
      this.renderDomPos = '';
      this.currentDomPos = '';
      this.requestRender(openId);
      setTimeout((): void => {
        if (!this.isLeaving && openId === this.openSeq && this.loading) {
          this.loading = false; // 重渲染仍未出页 → 停止转圈
          // 关键兜底:停转圈后若仍无正文,必须给错误态。否则三个 UI 分支全不命中,
          // 只剩主题底色 → 深色主题(#121212)下就是用户看到的"黑屏"。
          if (!this.errorMsg) this.errorMsg = '正文加载失败,请返回重试';
        }
      }, 2500);
    }, 3000);
  }

  private async openChapter(index: number, domPos: string = ''): Promise<void> {
    if (!this.book || !this.book.chapters || index < 0 || index >= this.book.chapters.length) return;
    if (this.isLeaving || this.switching) return;
    this.switching = true;
    this.persistProgress(true);
    // 切章释放旧书要延后到 doRender:先把新章节正文和 parser 准备好,
    // 再在 registerBookParser 前立即 releaseBook,避免旧 parser 继续显示上一章。
    this.loading = true;
    this.errorMsg = '';
    this.chapterIndex = index;
    this.currentChapter = this.book.chapters[index];
    this.currentDomPos = domPos;
    this.pageFooter = '';
    this.isLastPage = false;
    this.isFirstPage = false;
    // 新章重置:位置基线清空、取消未决翻页,避免跨章误判
    this.flipBaselineDomPos = '';
    this.flipBaselineFooter = '';
    this.flipBaselineAtLastPage = false;
    this.flipBaselineAtFirstPage = false;
    this.pendingDir = 0;
    const openId = ++this.openSeq;
    // 关键:在任何 await 之前挂兜底定时器,避免 startPlay 卡死时永不恢复
    this.armLoadingFailsafe(openId);
    try {
      const next = index + 1 < this.book.chapters.length ? this.book.chapters[index + 1] : undefined;
      hilog.info(0x9527, 'RdrDbg', 'openChapter begin openId=%{public}d idx=%{public}d title=%{public}s url=%{public}s',
        openId, index, this.currentChapter.title,
        this.currentChapter.originSourceValue || this.currentChapter.source.value);
      const text = await ReaderService.loadChapterText(this.book, this.currentChapter, next);
      if (this.isLeaving || openId !== this.openSeq) { this.switching = false; return; }
      if (!text || !text.trim()) {
        this.errorMsg = '正文为空';
        this.loading = false;
        this.switching = false;
        return;
      }
      const path = await ReaderService.writeChapterTxt(this.context!, this.book, this.currentChapter, text);
      hilog.info(0x9527, 'RdrDbg', 'openChapter txt openId=%{public}d idx=%{public}d title=%{public}s path=%{public}s len=%{public}d head=%{public}s',
        openId, index, this.currentChapter.title, path, text.length, text.substring(0, 120));
      if (this.isLeaving || openId !== this.openSeq) { this.switching = false; return; }
      const handler = await bookParser.getDefaultHandler(path);
      if (this.isLeaving || openId !== this.openSeq) { this.switching = false; return; }
      // 用真实 spine 索引(txt 的 spine[0].index 未必为 0),否则排版引擎请求无效 spine → 解析失败黑屏
      let spineIndex = 0;
      try {
        const spineList = handler.getSpineList();
        if (spineList && spineList.length > 0) spineIndex = spineList[0].index;
      } catch (_e) { /* ignore */ }
      hilog.info(0x9527, 'RdrDbg', 'openChapter parser openId=%{public}d idx=%{public}d spine=%{public}d',
        openId, index, spineIndex);
      this.renderHandler = handler;
      this.renderSpineIndex = spineIndex;
      this.renderDomPos = domPos ?? '';
      this.renderOpenId = openId;
      this.opened = true;
      this.switching = false;
      this.requestRender(openId);
      this.persistProgress(true);
      ChapterCacheService.getInstance().preloadTextChapters(this.book, index);
    } catch (e) {
      this.switching = false;
      if (this.isLeaving) return;
      const be = e as BusinessError;
      if (be && be.code === 1016910004) {
        this.errorMsg = 'Reader Kit 未授权：可能需在 AppGallery Connect 为本应用开通“阅读服务”';
      } else {
        this.errorMsg = (be && be.message) ? be.message : String(e);
      }
      this.loading = false;
    }
  }

  /**
   * 请求渲染当前章。组件常驻,每个阅读页实例只渲染一章(切章=新建阅读页实例,见 navigateToChapter):
   * - 组件已就绪 → doRender;未就绪(首次进页)→ pendingRender,等 readerCallback 触发。
   */
  private requestRender(openId: number): void {
    if (this.isLeaving || openId !== this.openSeq) return;
    if (this.componentReady) {
      this.doRender(openId);
    } else {
      this.pendingRender = true;
    }
  }

  /**
   * 向 Reader Kit 注册解析器并起播。doRender 总在「组件刚重挂、readerCallback 刚回调」后调用,
   * 此时控制器全新且未初始化,故走 init → setPageConfig → registerBookParser → startPlay
   * (每章=一个独立 txt,对 Reader Kit 即一本新书;靠重挂换书,不再 releaseBook 复用旧组件)。
   */
  private async doRender(openId: number): Promise<void> {
    if (this.isLeaving || openId !== this.openSeq || !this.renderHandler) return;
    try {
      if (!this.inited) {
        await this.readerController.init(this.context!);
        if (this.isLeaving || openId !== this.openSeq) return;
        this.inited = true;
      }
      this.readerController.setPageConfig(this.buildSetting());
      this.readerController.registerBookParser(this.renderHandler);
      hilog.info(0x9527, 'RdrDbg', 'doRender startPlay openId=%{public}d spine=%{public}d dom=%{public}s title=%{public}s',
        openId, this.renderSpineIndex, this.renderDomPos, this.currentChapter?.title ?? '');
      // 不 await:让 pageShow 回调驱动 loading=false(stale domPos 时 await 会永久挂起并阻断兜底)
      this.readerController.startPlay(this.renderSpineIndex, this.renderDomPos).catch((e: BusinessError): void => {
        const be = e as BusinessError;
        hilog.error(0x9527, 'RdrDbg', 'startPlay failed openId=%{public}d code=%{public}d msg=%{public}s',
          openId, be?.code ?? 0, be?.message ?? String(e));
      });
    } catch (e) {
      if (this.isLeaving || openId !== this.openSeq) return;
      const be = e as BusinessError;
      if (be && be.code === 1016910004) {
        this.errorMsg = 'Reader Kit 未授权：可能需在 AppGallery Connect 为本应用开通“阅读服务”';
      } else {
        // 其他初始化异常(setPageConfig/registerBookParser 等)过去被静默吞掉 → 卡 loading → 黑屏。
        // 统一回填错误态,绝不静默。
        this.errorMsg = (be && be.message) ? be.message : '阅读组件初始化失败,请返回重试';
      }
      this.loading = false;
    }
  }

  @Builder
  buildReaderComponent() {
    ReadPageComponent({
      controller: this.readerController,
      readerCallback: (err: BusinessError, data: readerCore.ReaderComponentController): void => {
        if (!err && data) {
          // 每次(重)挂载都会回调一次。控制器是全新的:重置 init/书籍/pageShow 绑定状态。
          this.readerController = data;
          this.componentReady = true;
          this.inited = false;
          this.pageShowBound = false;
          this.registerPageShow();
          hilog.info(0x9527, 'RdrDbg', 'readerCallback ready pending=%{public}s openId=%{public}d',
            String(this.pendingRender), this.renderOpenId);
          if (this.pendingRender) {
            this.pendingRender = false;
            this.doRender(this.renderOpenId);
          }
        } else {
          // 组件初始化失败过去被直接忽略 → componentReady 永为 false → 永不出页 → 黑屏。
          // 直接回填错误态,给用户可见反馈而非干等兜底定时器。
          const be = err as BusinessError;
          hilog.error(0x9527, 'RdrDbg', 'readerCallback failed code=%{public}d msg=%{public}s',
            be?.code ?? 0, be?.message ?? 'null data');
          if (!this.isLeaving) {
            this.loading = false;
            this.errorMsg = '阅读组件加载失败,请返回重试';
          }
        }
      }
    })
      .width('100%')
      // 组件铺满屏幕;视口=组件实测像素(onAreaChange),二者严格等比,Reader Kit 才会 1:1 排版。
      // 旧做法把组件做得比屏幕高(只加高度不加宽度)→ 视口纵横比 ≠ 屏幕 → 正文被纵向拉伸(字体变形),已回退。
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      // 实测组件尺寸作为排版视口(px),官方要求视口按实际尺寸取,否则会留白/拉伸
      .onAreaChange((_o: Area, n: Area) => {
        let den = 3.25;
        try {
          den = display.getDefaultDisplaySync().densityPixels;
        } catch (_e) {
          den = 3.25;
        }
        const w = Math.round((n.width as number) * den);
        const h = Math.round((n.height as number) * den);
        if (w > 0 && h > 0 && (w !== this.pageViewW || h !== this.pageViewH)) {
          this.pageViewW = w;
          this.pageViewH = h;
          if (this.opened) { this.applySetting(); } // 视口确定后重排,正文铺满不拉伸
        }
      })
  }

  private async persistProgress(force: boolean = false): Promise<void> {
    if (!this.book || !this.currentChapter) return;
    const book = this.book;
    const chapter = this.currentChapter;
    const domPos = this.currentDomPos;
    const idx = Math.max(0, this.chapterIndex);
    const now = Date.now();
    if (!force && now - this.lastPersistAt < 1200) return;
    this.lastPersistAt = now;
    await PreferenceService.upsertHistory({
      bookId: book.id,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      progressMs: 0,
      durationMs: 0,
      domPos,
      updatedAt: now
    });
    await PreferenceService.saveProgress({
      bookId: book.id,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      chapterIndex: idx,
      positionMs: 0,
      durationMs: 0,
      domPos,
      updatedAt: now
    });
    SearchCache.put(book);
    emitter.emit(EVT_HISTORY_UPDATED, { data: { bookId: book.id } });
  }

  // ─────────────── 翻页 / 章节切换 ───────────────

  private toast(msg: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: msg }); } catch (_e) { /* ignore */ }
  }

  /**
   * 切换到指定章节 —— 替换为全新的阅读页实例。
   * Reader Kit 同一页/组件无法二次换书(实测第二次 startPlay 不出页,必须退出重进);
   * 用 replacePathByName 新建一个 reader 实例 = 程序化「退出重进」,稳定渲染且不增加栈深。
   */
  private navigateToChapter(index: number): void {
    if (!this.book || !this.book.chapters || index < 0 || index >= this.book.chapters.length) return;
    if (this.isLeaving || this.switching) return;
    this.switching = true;
    this.persistProgress(true);
    const params: Record<string, Object> = {
      'bookId': this.book.id,
      'chapterId': this.book.chapters[index].id,
      'progressMs': 0
    };
    try { this.navStack.replacePathByName('reader', params, false); } catch (_e) { /* ignore */ }
  }

  private goPrevChapter(): void {
    if (this.chapterIndex <= 0) { this.toast('已是第一章'); return; }
    this.navigateToChapter(this.chapterIndex - 1);
  }

  private goNextChapter(): void {
    if (!this.book || this.chapterIndex >= this.book.chapters.length - 1) { this.toast('已是最后一章'); return; }
    this.navigateToChapter(this.chapterIndex + 1);
  }

  /**
   * 驱动 Reader Kit 翻页;若翻页后 ~280ms 内没有 pageShow(说明已在章首/章末,翻页是 no-op),
   * 则自动切到上/下一章 —— Reader Kit 没有"翻到尽头"事件,只能用此法兜住自动续章。
   */
  private driveFlip(isNext: boolean): void {
    const seq = ++this.flipSeq;
    this.pendingDir = isNext ? 1 : -1;
    // 记录翻页前页起始位置;pageShow 回来若 startDomPos 没变即判定到边界(见 registerPageShow)
    this.flipBaselineDomPos = this.currentDomPos;
    this.flipBaselineFooter = this.pageFooter;
    this.flipBaselineAtLastPage = this.isLastPage;
    this.flipBaselineAtFirstPage = this.isFirstPage;
    try { this.readerController.flipPage(isNext); } catch (_e) { /* ignore */ }
    setTimeout((): void => {
      if (this.isLeaving) return;
      if (seq !== this.flipSeq) return;     // 期间又翻页/切章,作废
      if (this.pendingDir === 0) return;    // pageShow 已确认翻页成功
      this.pendingDir = 0;
      if (isNext) this.goNextChapter(); else this.goPrevChapter();
    }, 280);
  }

  private onTapForward(): void {
    if (this.loading || this.switching || this.isLeaving || !this.opened) return;
    if (this.isLastPage) { this.goNextChapter(); return; }
    this.driveFlip(true);
  }

  private onTapBackward(): void {
    if (this.loading || this.switching || this.isLeaving || !this.opened) return;
    if (this.isFirstPage) { this.goPrevChapter(); return; }
    this.driveFlip(false);
  }

  private applySetting(): void {
    if (!this.opened) return;
    try { this.readerController.setPageConfig(this.buildSetting()); } catch (_e) { /* ignore */ }
  }

  private toggleToolbar(): void {
    this.toolbarVisible = !this.toolbarVisible;
    WindowUtils.setStatusBarVisible(this.toolbarVisible);
  }

  /** 细分隔线颜色(夜间浅、日间深) */
  private dividerColor(): string {
    return this.themeIndex === NIGHT_INDEX ? '#1AFFFFFF' : '#14000000';
  }


  // ─────────────── 亮度 ───────────────

  private setBrightnessLive(v: number): void {
    this.screenBrightness = v;
    WindowUtils.setReaderBrightness(v);
  }

  // ─────────────── 更多菜单 / 书架 ───────────────

  /** 进入本书详情页(顶栏右上角图标) */
  private gotoDetail(): void {
    if (!this.book) return;
    // 先持久化当前章,详情页据此(lastHistory)定位到正在读的章节
    this.persistProgress(true);
    this.navStack.pushPathByName('detail', this.book.id, () => { /* 返回阅读页无需额外处理 */ });
  }

  /** 回书架主页:清空导航栈回 MainPage,并切到「书架」Tab(index=1) */
  private goBookshelf(): void {
    try { this.navStack.clear(); } catch (_e) { /* ignore */ }
    emitter.emit(EVT_SWITCH_TAB, { data: { index: 1 } });
  }

  private timeText(): string {
    const d = new Date();
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  private refreshHudInfo(): void {
    this.hudTime = this.timeText();
    try {
      const soc = batteryInfo.batterySOC;
      this.batteryPercent = soc >= 0 ? Math.round(soc) : -1;
    } catch (_e) {
      this.batteryPercent = -1;
    }
  }

  private startHudTicker(): void {
    this.refreshHudInfo();
    if (this.hudTimerId >= 0) return;
    this.hudTimerId = setInterval((): void => {
      this.refreshHudInfo();
    }, 30000);
  }

  private stopHudTicker(): void {
    if (this.hudTimerId < 0) return;
    clearInterval(this.hudTimerId);
    this.hudTimerId = -1;
  }

  build() {
    Stack() {
      // 兜底底色,防止 Reader Kit 未出页时露黑底
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().bg)

      // Reader Kit 排版组件常驻挂载。每个阅读页实例只渲染一章;切章=新建阅读页实例(navigateToChapter)。
      this.buildReaderComponent()

      // HUD(底部时间/电量/页码):纯展示层,放在正文之上、热区之下。
      // 必须声明在热区之前且不设 zIndex —— 否则其内部 Blank 会盖在热区上拦截中间点击,唤不出菜单。
      // 唤出菜单时隐藏:让位给全宽底栏(沉浸 tab),避免底部重叠。
      if (!this.loading && !this.errorMsg && !this.toolbarVisible) {
        this.buildReaderHud()
      }

      // 翻页/唤起热区:左(上一页/章) 中(唤起工具栏) 右(下一页/章)。
      // 声明在 HUD 之后→处于最上层,确保中间点击命中 toggleToolbar;仅工具栏隐藏时存在,避免与按钮冲突。
      if (!this.loading && !this.errorMsg && !this.toolbarVisible) {
        Row() {
          Column()
            .width('30%')
            .height('100%')
            .onClick(() => this.onTapBackward())
          Column()
            .width('40%')
            .height('100%')
            .onClick(() => this.toggleToolbar())
          Column()
            .width('30%')
            .height('100%')
            .onClick(() => this.onTapForward())
        }
        .width('100%')
        .height('100%')
      }

      if (this.loading) {
        this.buildLoading()
      } else if (this.errorMsg) {
        this.buildError()
      }

      // 工具栏覆盖层:用纵向 Column 让顶栏贴顶、底栏沉底。
      // (此前用 Stack → 默认 alignContent=Center 把两栏都居中,子组件 .align() 改不了在 Stack 里的位置 → 按钮堆中间)
      if (this.toolbarVisible) {
        Column() {
          this.buildFloatingActions()
          // 中间空白填满剩余高度,并承接"点击收起菜单"
          Column()
            .layoutWeight(1)
            .width('100%')
            .onClick(() => this.toggleToolbar())
          this.buildBottomBar()
        }
        .width('100%')
        .height('100%')
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().bg)
    .clip(false)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.sheetOpen, this.activeSheet(), {
      // 设置面板内容高度固定(无纵向撑满元素)→ FIT_CONTENT 贴合内容,消除底部留白;
      // 目录是长列表,仍用 LARGE 占满。
      height: this.sheetMode === 2 ? SheetSize.FIT_CONTENT : SheetSize.LARGE,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: () => { this.sheetMode = 0; }
    })
  }

  /** 统一底部抽屉内容:按 sheetMode 切目录/设置 */
  @Builder
  activeSheet() {
    if (this.sheetMode === 2) {
      this.settingSheet()
    } else {
      this.chapterSheet()
    }
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress().width(42).height(42).color(AppColor.Brand)
      Text('加载正文中...')
        .fontSize(AppFont.Body)
        .fontColor(this.theme().sub)
        .margin({ top: AppSpace.Md })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme().bg)
  }

  @Builder
  buildError() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(44)
        .fontColor([this.theme().sub])
      Text(this.errorMsg)
        .fontSize(AppFont.Body)
        .fontColor(this.theme().sub)
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
      Button('返回')
        .fontSize(AppFont.Body)
        .fontColor('#FFFFFFFF')
        .backgroundColor(AppColor.Brand)
        .borderRadius(22)
        .height(44)
        .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
        .onClick(() => this.navStack.pop())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme().bg)
  }

  /** 全屏常驻底部信息:章节、时间/电量、页码。 */
  @Builder
  buildReaderHud() {
    Column() {
      Blank()
      Row() {
        Row({ space: 8 }) {
          Text(this.hudTime || this.timeText())
            .fontSize(AppFont.Caption)
            .fontColor(this.theme().sub)
          // 取不到电量(batterySOC<0)时显示占位,避免依赖具体电量档位的电池图标资源
          Text(this.batteryPercent >= 0 ? `${this.batteryPercent}%` : '--')
            .fontSize(AppFont.Caption)
            .fontColor(this.theme().sub)
        }
        .layoutWeight(1)

        // 章节已移到顶栏中间,这里底部只留 左:时间/电量 右:页码
        Text(this.pageFooter || '')
          .fontSize(AppFont.Caption)
          .fontColor(this.theme().sub)
      }
      .width('100%')
      .padding({
        left: AppSpace.Xl,
        right: AppSpace.Xl,
        bottom: WindowUtils.getBottomSafeVp() + 8
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  /** 唤出菜单时的左上返回 + 右上详情悬浮按钮。 */
  @Builder
  buildFloatingActions() {
    Row() {
      this.floatingAction($r('sys.symbol.chevron_left'), () => this.navStack.pop())
      // 顶栏中间显示当前章节(原在底部 HUD,移到此处)
      Text(this.currentChapter?.title ?? '')
        .fontSize(AppFont.Body)
        .fontColor(this.theme().text)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      this.floatingAction($r('sys.symbol.info_circle'), () => this.gotoDetail())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: AppSpace.Lg,
      right: AppSpace.Lg,
      // 用稳定状态栏高度避让:菜单唤出瞬间 topPx 可能尚未恢复,直接用 getStatusBarHeightVp 会贴到状态栏
      top: WindowUtils.getTopSafeStableVp() + AppSpace.Sm
    })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.move(TransitionEdge.TOP))
        .animation({ duration: TOOLBAR_ANIM, curve: AppCurve.Standard })
    )
    .zIndex(1)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  @Builder
  floatingAction(icon: Resource, action: () => void) {
    Button() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.theme().text])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(this.theme().glass)
    .backdropBlur(28)
    .shadow({ radius: 14, color: '#18000000', offsetY: 4 })
    .onClick(action)
  }

  /** 底部悬浮菜单:脱离底部边缘的胶囊工具条。 */
  @Builder
  buildBottomBar() {
    Row() {
      this.barRegion($r('sys.symbol.chevron_left'), '上一章', () => this.goPrevChapter())
      this.barRegion($r('sys.symbol.textformat'), '设置', () => { this.sheetMode = 2; this.sheetOpen = true; })
      this.barRegion($r('sys.symbol.list_bullet'), '目录', () => this.openCatalog())
      this.barRegion($r('sys.symbol.chevron_right'), '下一章', () => this.goNextChapter())
    }
    .width('92%')
    .height(60)
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
    // 逼近首页 HdsTabs 悬浮沉浸光感:更透的系统材质模糊(THIN)、不加不透明底色以保留通透感、悬浮圆角 + 离底间距 + 轻阴影。
    // (官方 systemMaterialEffect 仅 HdsTabs/HdsNavigation 可用,自定义底栏只能用 backgroundBlurStyle 逼近)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .borderRadius(28)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 20, color: '#1A000000', offsetY: 6 })
    .margin({ bottom: WindowUtils.getBottomSafeVp() + 18 })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.move(TransitionEdge.BOTTOM))
        .animation({ duration: TOOLBAR_ANIM, curve: AppCurve.Standard })
    )
    .zIndex(1)
    .align(Alignment.Bottom)
  }

  @Builder
  barRegion(icon: Resource, label: string, action: () => void) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('sys.color.font_primary')])
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
    .onClick(action)
  }

  /** 打开目录并滚到当前章 */
  private openCatalog(): void {
    this.chapterQuery = ''; // 每次打开都用完整目录
    this.sheetMode = 1;
    this.sheetOpen = true;
    setTimeout(() => {
      if (this.chapterIndex >= 0) {
        try { this.chapterScroller.scrollToIndex(this.chapterIndex, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      }
    }, 120);
  }

  /** 按关键词过滤目录,保留章节在完整目录中的原始索引(供跳转/高亮用) */
  private filterChapters(): ChapterRow[] {
    const list = this.book?.chapters ?? [];
    const q = this.chapterQuery.trim();
    const out: ChapterRow[] = [];
    for (let i = 0; i < list.length; i++) {
      if (!q || list[i].title.indexOf(q) >= 0) {
        out.push({ ch: list[i], idx: i });
      }
    }
    return out;
  }

  @Builder
  chapterSheet() {
    Column() {
      // 标题 + 章节搜索(对齐听书界面的章节搜索)
      Column({ space: AppSpace.Sm }) {
        Text('目录')
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        Search({ value: this.chapterQuery, placeholder: '搜索章节' })
          .height(38)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(AppRadius.Lg)
          .onChange((v: string) => { this.chapterQuery = v; })
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Md })

      List({ scroller: this.chapterScroller }) {
        ForEach(this.filterChapters(), (row: ChapterRow) => {
          ListItem() {
            Row() {
              Text(row.ch.title)
                .fontSize(AppFont.Body)
                .fontColor(row.idx === this.chapterIndex ? AppColor.Brand : $r('sys.color.font_primary'))
                .fontWeight(row.idx === this.chapterIndex ? FontWeight.Medium : FontWeight.Normal)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (row.idx === this.chapterIndex) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([AppColor.Brand])
              }
            }
            .width('100%')
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: 14, bottom: 14 })
            .onClick(() => {
              this.sheetOpen = false;
              this.navigateToChapter(row.idx);
            })
          }
        }, (row: ChapterRow) => row.ch.id)
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .divider({ strokeWidth: 0.5, color: AppColor.Divider, startMargin: AppSpace.Lg, endMargin: AppSpace.Lg })
    }
    .width('100%')
    .height('100%')
  }

  /** 阅读设置(底部抽屉):字号 / 行距 / 亮度 滑块 + 主题模式 */
  @Builder
  settingSheet() {
    Column({ space: AppSpace.Md }) {
      Text('阅读设置')
        .fontSize(AppFont.Title)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      // 字号
      Column({ space: AppSpace.Xs }) {
        Row() {
          Text('字号').fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Text(`${this.fontSize}`).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
        }.width('100%')
        Slider({ value: this.fontSize, min: 18, max: 38, step: 1, style: SliderStyle.OutSet })
          .width('100%')
          .blockColor(AppColor.Brand)
          .selectedColor(AppColor.Brand)
          .trackColor($r('sys.color.comp_background_tertiary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            this.fontSize = Math.round(value); // 数字实时更新
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.applySetting(); // 重排版较重,松手才应用
              this.persistReaderSettings();
            }
          })
      }.width('100%')

      // 行距
      Column({ space: AppSpace.Xs }) {
        Row() {
          Text('行距').fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Text(this.lineHeight.toFixed(1)).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
        }.width('100%')
        Slider({ value: this.lineHeight, min: 1.2, max: 2.4, step: 0.1, style: SliderStyle.OutSet })
          .width('100%')
          .blockColor(AppColor.Brand)
          .selectedColor(AppColor.Brand)
          .trackColor($r('sys.color.comp_background_tertiary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            this.lineHeight = Math.round(value * 10) / 10; // 数字实时更新
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.applySetting(); // 重排版较重,松手才应用
              this.persistReaderSettings();
            }
          })
      }.width('100%')

      // 亮度(滑块 + 跟随系统)
      Column({ space: AppSpace.Xs }) {
        Row() {
          Text('亮度').fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Text('跟随系统')
            .fontSize(AppFont.Caption)
            .fontColor(this.screenBrightness < 0 ? '#FFFFFFFF' : $r('sys.color.font_secondary'))
            .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 4, bottom: 4 })
            .borderRadius(AppRadius.Sm)
            .backgroundColor(this.screenBrightness < 0 ? AppColor.Brand : $r('sys.color.comp_background_tertiary'))
            .onClick(() => { this.setBrightnessLive(-1); this.persistReaderSettings(); })
        }.width('100%')
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.sun_min')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
          Slider({ value: this.screenBrightness >= 0 ? this.screenBrightness * 100 : 70, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .blockColor(AppColor.Brand)
            .selectedColor(AppColor.Brand)
            .trackColor($r('sys.color.comp_background_tertiary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              this.setBrightnessLive(value / 100);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.persistReaderSettings();
            })
          SymbolGlyph($r('sys.symbol.sun_max')).fontSize(22).fontColor([$r('sys.color.font_secondary')])
        }.width('100%')
      }.width('100%')

      // 主题模式
      Row({ space: AppSpace.Sm }) {
        Text('主题').fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).width(48)
        ForEach(READER_THEMES, (t: ReaderTheme, idx: number) => {
          Text(t.name)
            .fontSize(AppFont.Caption)
            .fontColor(idx === this.themeIndex ? AppColor.Brand : t.text)
            .layoutWeight(1)
            .height(36)
            .textAlign(TextAlign.Center)
            .backgroundColor(t.bg)
            .borderRadius(AppRadius.Sm)
            .border({ width: idx === this.themeIndex ? 2 : 0.5, color: idx === this.themeIndex ? AppColor.Brand : '#22000000' })
            .onClick(() => {
              this.themeIndex = idx;
              this.applyStatusBar();
              this.applySetting();
              this.persistReaderSettings();
            })
        }, (t: ReaderTheme) => t.name)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Md })
  }
}
