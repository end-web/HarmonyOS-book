import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { AppColor, AppSpace, AppFont, AppMotion, AppRadius } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { PlayerState, PLAYER_STATE_KEY, PlayMode } from '../model/PlayerState';
import { DataService } from '../service/DataService';
import { AudioService } from '../service/AudioService';
import { PreferenceService } from '../service/PreferenceService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';
import { ChapterCacheService, EVT_CHAPTER_DURATION_UPDATED } from '../service/ChapterCacheService';
import { ChapterDataSource } from '../utils/ChapterDataSource';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Player';

/**
 * 播放页向其 NavDestination 暴露的返回拦截器。
 * 抽屉(章节/定时/跳过)打开时,右滑/三键返回应先关抽屉而不是退出整页:
 * PlayerPage 挂载时注册 handler,NavDestination.onBackPressed 委托到这里。
 */
export class PlayerBackInterceptor {
  private static handler: (() => boolean) | null = null;

  static set(h: (() => boolean) | null): void {
    PlayerBackInterceptor.handler = h;
  }

  /** 返回 true 表示已消费(关抽屉),false 表示放行(正常退页) */
  static consume(): boolean {
    return PlayerBackInterceptor.handler ? PlayerBackInterceptor.handler() : false;
  }
}

/**
 * mini 入口标志:仅当从 MiniPlayer 点击进入 player 时为 true。
 * Index 的 customTransition 据此跳过下滑转场,让 geometryTransition 共享元素接管。
 * PlayerPage 的返回按钮也据此走 animateTo 反向共享元素。
 * 用 @ObservedV2 单例实例:mini/player 两端的 geometryTransition id 才能响应变化。
 *
 * 注意:fromMini 只在转场动画期间为 true,进入 player 后会被清成 false,
 * 避免后续 player 内部状态变化(如 isPlaying)触发 mini 节点重建,
 * 引发 geometryTransition id 误匹配导致大封面缩小到 mini。
 */
@ObservedV2
export class PlayerEntryState {
  @Trace fromMini: boolean = false;
}

export const playerEntryState = new PlayerEntryState();

/**
 * 由 PlayerPage 注册的"是否 mini 入口"决策器。
 * 进入后 playerEntryState.fromMini 会被清,但 PlayerPage 自身记忆 entryFromMini,
 * Index 的 onBackPressed 通过此决策器读取真实入口类型,决定走共享元素还是普通 pop。
 */
export class PlayerEntryDecider {
  private static handler: (() => boolean) | null = null;

  static set(h: (() => boolean) | null): void {
    PlayerEntryDecider.handler = h;
  }

  static isFromMini(): boolean {
    return PlayerEntryDecider.handler ? PlayerEntryDecider.handler() : false;
  }
}

@ComponentV2
export struct PlayerPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param resumeChapterId: string = '';
  @Param resumeProgressMs: number = 0;
  @Local book: Book | null = null;
  @Local isFavorite: boolean = false;
  @Local showChapterList: boolean = false;
  @Local showSleepSheet: boolean = false;
  @Local showSkipSheet: boolean = false;
  @Local skipIntroValue: number = 0;
  @Local skipOutroValue: number = 0;
  @Local blurColor: string = 'rgba(42,42,42,0)';
  @Local themeColorHex: string = '';
  @Local themeColorDarkHex: string = '';
  @Local hasThemeColor: boolean = false;
  @Local renderBlur: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;;
  @Local seeking: boolean = false;
  @Local seekValueMs: number = 0;
  /** 缓存版本号：每次有章节时长被解析出来就 +1，强制 V2 重渲染章节列表 */
  @Local chapterCacheTick: number = 0;
  /** 章节列表滚动位置 vs 当前播放章节的偏离（vp）；用来决定是否显示"回到当前章节"浮动按钮 */
  @Local listOffsetFromCurrent: number = 0;
  /** 章节搜索关键词；非空时章节列表按标题过滤 */
  @Local chapterSearchKeyword: string = '';

  private context: common.UIAbilityContext | null = null;
  private speeds: number[] = [0.75, 1.0, 1.25, 1.75, 2.0];
  private lastCoverKey: string = '';
  /** 正在取色的封面 key,防止异步取色并发重复触发(取色成功才写 lastCoverKey,失败可重试) */
  private pickingCover: string = '';
  private chapterListScroller: Scroller = new Scroller();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterDurationHandler = (): void => {
    this.chapterCacheTick = this.chapterCacheTick + 1;
  };
  /** 记忆入口类型:进入时捕获 fromMini 值,用于决定返回时走共享元素还是普通 pop */
  private entryFromMini: boolean = false;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 记忆入口并注册决策器
    this.entryFromMini = playerEntryState.fromMini;
    PlayerEntryDecider.set(() => this.entryFromMini);
    PlayerBackInterceptor.set((): boolean => this.handleBack());
    this.primeFromCache();
    emitter.on(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    WindowUtils.setStatusBarLight(true);
    setTimeout(() => {
      this.renderBlur = true;
      this.loadBook();
      // 共享元素动画完成后清 fromMini,避免 player 内部状态变化触发 mini 节点重建误配对
      if (this.entryFromMini) {
        setTimeout(() => {
          playerEntryState.fromMini = false;
        }, 500);
      }
    }, AppMotion.Page);
  }

  /** 同步从 SearchCache + ColorPickerUtils 缓存取得 book/cover/color，避免首帧默认色闪烁 */
  private primeFromCache(): void {
    let b = SearchCache.get(this.bookId);
    if (!b && this.playerState.currentBook) {
      b = this.playerState.currentBook;
    }
    if (!b) return;
    this.book = b;
    if (!b.cover) return;

    const rgb = ColorPickerUtils.getCached(b.cover);
    if (!rgb) {
      // 取色缓存未命中:不设置 lastCoverKey，让后续 extractCoverColor 正常执行
      return;
    }

    // 缓存命中:立即同步设置融合色,避免灰色过渡
    this.blurColor = ColorPickerUtils.toBlurColor(rgb);
    this.themeColorHex = ColorPickerUtils.toHex(rgb);
    this.themeColorDarkHex = ColorPickerUtils.toHex(ColorPickerUtils.darken(rgb, 0.4));
    this.hasThemeColor = true;
    this.lastCoverKey = b.cover;
  }

  aboutToDisappear(): void {
    PlayerBackInterceptor.set(null);
    emitter.off(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    WindowUtils.setStatusBarLight(false);
    AudioService.getInstance().flushHistory();
    // 不在这里清 fromMini,避免第二次快速进入时状态竞态
  }

  /**
   * 返回拦截:任一抽屉打开时先关抽屉并消费返回事件,否则放行让 NavDestination 正常退页。
   * 实际同时只会有一个抽屉打开,逐个判断即可。
   */
  private handleBack(): boolean {
    if (this.showChapterList) {
      this.showChapterList = false;
      return true;
    }
    if (this.showSleepSheet) {
      this.showSleepSheet = false;
      return true;
    }
    if (this.showSkipSheet) {
      this.showSkipSheet = false;
      return true;
    }
    return false;
  }

  /** 长按恢复默认值时的轻震反馈 */
  private hapticTick(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 30 },
        { id: 0, usage: 'touch' }
      ).catch((_e: object) => { /* 无震动器或权限被关 */ });
    } catch (_e) { /* 同步异常忽略 */ }
  }

  private async loadBook(): Promise<void> {
    // 等待 EntryAbility.bootstrapAudioService 完成，确保冷启动时 playerState/DataService 已就绪
    await AudioService.getInstance().whenReady();
    let b = SearchCache.get(this.bookId);
    if (!b) {
      b = await DataService.getBookById(this.context!, this.bookId) || null;
    }
    if (!b && this.playerState.currentBook) {
      // 不强制 id 匹配:卡片语义就是"打开正在播放的书",不同会话间 id 可能因
      // hash 算法差异而不一致(home_audio_xxx / search_audio_xxx),只要有 currentBook 就用
      b = this.playerState.currentBook;
    }
    if (!b) {
      console.error('[PlayerPage] loadBook failed, book not found');
      this.navStack.pop();
      return;
    }
    this.book = b;
    this.isFavorite = await PreferenceService.isFavorite(b.id);
    this.extractCoverColor(b.cover);

    // 绑定全局状态/上下文
    AudioService.getInstance().bind(this.playerState, this.context!);

    // 历史记录入口：若指定了恢复章节，且当前 AudioService 没有在播放该章节，则主动起播 + seek
    if (this.resumeChapterId) {
      await this.tryResumePlay(b);
    }
  }

  private async tryResumePlay(book: Book): Promise<void> {
    const target = book.chapters.find((c) => c.id === this.resumeChapterId);
    if (!target) {
      hilog.warn(DOMAIN, TAG, 'resume chapter not found: %{public}s', this.resumeChapterId);
      return;
    }
    // ★ PlaybackStore 同书+同章节命中:直接复用 live state,不调 AudioService 任何方法,
    //   绝对不会触发 reset。即使 progressMs 与 resumeProgressMs 略有差异,以 live 为准
    if (PlaybackStore.getInstance().isCurrentChapter(book.id, target.id)) {
      return;
    }
    // 切到不同章节(可能不同书) → AudioService 内部会 same-book/same-chapter 短路或 reset
    SearchCache.put(book);
    await AudioService.getInstance().playChapterAndSeek(book, target, this.resumeProgressMs);
  }

  private formatMs(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    const mm = m < 10 ? '0' + m : m.toString();
    const ss = s < 10 ? '0' + s : s.toString();
    return mm + ':' + ss;
  }

  /** Slider max 与右侧总时长显示用同一份兜底:prepared 前用 savedDurationMs */
  private sliderMaxMs(): number {
    if (this.playerState.durationMs > 0) return this.playerState.durationMs;
    if (this.playerState.savedDurationMs > 0) return this.playerState.savedDurationMs;
    return 1;
  }

  private displayDurationMs(): number {
    if (this.playerState.durationMs > 0) return this.playerState.durationMs;
    return this.playerState.savedDurationMs;
  }

  private async togglePlay(): Promise<void> {
    await AudioService.getInstance().toggle();
  }

  private async playPrev(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (idx > 0) {
      const ch = this.book.chapters[idx - 1];
      // AudioService 内部会查缓存/解析 URL，这里不用再做
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async playNext(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (idx >= 0 && idx < this.book.chapters.length - 1) {
      const ch = this.book.chapters[idx + 1];
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      await DataService.upsertCachedBook(this.book);
    }
  }

  private async cycleSpeed(): Promise<void> {
    const cur = this.playerState.speed;
    let idx = this.speeds.indexOf(cur);
    idx = (idx + 1) % this.speeds.length;
    await AudioService.getInstance().setSpeed(this.speeds[idx]);
  }

  private async resetSpeed(): Promise<void> {
    if (this.playerState.speed === 1.0) return;
    this.hapticTick();
    await AudioService.getInstance().setSpeed(1.0);
  }

  private isCurrentChapter(ch: Chapter): boolean {
    return this.playerState.currentChapter !== null && this.playerState.currentChapter.id === ch.id;
  }

  private formatDuration(seconds: number): string {
    if (!seconds || seconds <= 0) return '';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) {
      return h + '时' + (m > 0 ? m + '分' : '') + (s > 0 ? s + '秒' : '');
    }
    if (m > 0) {
      return m + '分' + (s > 0 ? s + '秒' : '');
    }
    return s + '秒';
  }

  /** 章节列表显示用的时长（秒）：优先用 chapter 自身的 duration，否则用 ChapterCacheService 解析出来的 */
  private chapterDurationSec(ch: Chapter): number {
    // 通过读 chapterCacheTick 把这个 getter 纳入 V2 依赖图,缓存解析完成后能自动重算
    if (this.chapterCacheTick < 0) return 0;
    if (ch.duration && ch.duration > 0) return ch.duration;
    return ChapterCacheService.getInstance().getChapterDuration(ch.id);
  }

  private async selectChapter(ch: Chapter): Promise<void> {
    if (!this.book) return;
    // 立即关抽屉（不要等 await playChapter，否则 WebView 嗅探的几秒内 UI 卡在章节列表上）
    this.showChapterList = false;
    // AudioService 内部用 playGen 替换式取消旧任务，所以反复点章节不会叠加
    AudioService.getInstance().playChapter(this.book, ch).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'selectChapter failed: %{public}s', e.message);
    });
  }

  /** 打开章节列表,加载全部章节 */
  private openChapterList(): void {
    this.showChapterList = true;
    this.listOffsetFromCurrent = 0;
    this.chapterSearchKeyword = '';
    if (!this.book) return;
    this.chapterDataSource.setChapters(this.book.chapters);
    this.scrollToCurrentChapter();
  }

  /** 按关键词过滤章节列表（关键词为空时还原全部，并滚回当前章节） */
  private applyChapterFilter(keyword: string): void {
    this.chapterSearchKeyword = keyword;
    if (!this.book) return;
    const kw = keyword.trim().toLowerCase();
    if (!kw) {
      this.chapterDataSource.setChapters(this.book.chapters);
      this.scrollToCurrentChapter();
      return;
    }
    const filtered = this.book.chapters.filter((c) => c.title.toLowerCase().includes(kw));
    this.chapterDataSource.setChapters(filtered);
    // 过滤结果重置滚动到顶部
    setTimeout(() => {
      try { this.chapterListScroller.scrollToIndex(0, false, ScrollAlign.START); } catch (_e) { /* ignore */ }
    }, 50);
  }

  private scrollToCurrentChapter(): void {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    this.scrollChapterListToIndex(idx);
  }

  /**
   * 可靠定位章节列表到指定 index。
   * 两段式延迟:首次等抽屉/列表挂载并完成首屏布局(规避 setTimeout(0) 的挂载竞态),
   * 把目标项拉进 LazyForEach 渲染窗口;二次等目标项真实行高确定后再精确居中,
   * 修正长列表按平均行高估算导致的 ScrollAlign.CENTER 偏差(原先单次定位时灵时不灵)。
   */
  private scrollChapterListToIndex(idx: number): void {
    if (idx < 0) return;
    setTimeout(() => {
      try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      setTimeout(() => {
        try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      }, 150);
    }, 50);
  }

  /** "回到当前章节"按钮:居中滚到当前章节 */
  private jumpToCurrentChapter(): void {
    this.scrollToCurrentChapter();
    this.listOffsetFromCurrent = 0;
  }

  /** 当前播放章节在列表中的索引 */
  private currentChapterIndex(): number {
    if (!this.book || !this.playerState.currentChapter) return -1;
    return this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
  }

  /** 是否需要显示"回到当前章节"浮动按钮:列表滚动距离当前章节超过 200vp（搜索过滤时不显示） */
  private shouldShowJumpButton(): boolean {
    return this.chapterSearchKeyword.trim().length === 0
      && Math.abs(this.listOffsetFromCurrent) > 200;
  }

  private formatSleepRemaining(): string {
    const ms = this.playerState.sleepRemainingMs;
    const totalSec = Math.floor(ms / 1000);
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  private setSleep(minutes: number): void {
    AudioService.getInstance().setSleepTimer(minutes);
    this.showSleepSheet = false;
  }

  private cyclePlayMode(): void {
    const next: PlayMode = this.playerState.playMode === PlayMode.Sequence
      ? PlayMode.ListLoop
      : (this.playerState.playMode === PlayMode.ListLoop ? PlayMode.SingleLoop : PlayMode.Sequence);
    AudioService.getInstance().setPlayMode(next);
  }

  private playModeIcon(): Resource {
    if (this.playerState.playMode === PlayMode.SingleLoop) {
      return $r('sys.symbol.repeat_1');
    }
    if (this.playerState.playMode === PlayMode.ListLoop) {
      return $r('sys.symbol.repeat');
    }
    return $r('sys.symbol.arrow_right');
  }

  private playModeColor(): string {
    return this.playerState.playMode === PlayMode.Sequence ? '#FFFFFF' : '#FFD480';
  }

  private async extractCoverColor(cover: string): Promise<void> {
    // 已成功取过色 / 正在取这张图 → 跳过
    if (!cover || cover === this.lastCoverKey || cover === this.pickingCover) return;

    // 缓存命中:立即同步设置融合色,不走 setTimeout
    const cachedRgb = ColorPickerUtils.getCached(cover);
    if (cachedRgb) {
      this.blurColor = ColorPickerUtils.toBlurColor(cachedRgb);
      this.themeColorHex = ColorPickerUtils.toHex(cachedRgb);
      this.themeColorDarkHex = ColorPickerUtils.toHex(ColorPickerUtils.darken(cachedRgb, 0.4));
      this.hasThemeColor = true;
      this.lastCoverKey = cover;
      return;
    }

    // 缓存未命中:异步取色
    this.pickingCover = cover;
    setTimeout(async () => {
      let rgb: RgbColor | null = null;
      try {
        if (cover.startsWith('http')) {
          rgb = await ColorPickerUtils.pickFromUrl(cover);
        } else if (cover.startsWith('/')) {
          rgb = await ColorPickerUtils.pickFromFile(cover);
        } else {
          rgb = await ColorPickerUtils.pickFromRawfile(this.context!, cover);
        }
      } catch (e) {
        console.error('[PlayerPage] extractCoverColor failed: ' + JSON.stringify(e));
      }

      // 取色失败:释放占位,允许后续重试(不写 lastCoverKey)
      if (!rgb) {
        if (this.pickingCover === cover) this.pickingCover = '';
        return;
      }
      // 取色期间封面已切换 → 丢弃旧结果
      if (cover !== this.pickingCover) return;

      this.blurColor = ColorPickerUtils.toBlurColor(rgb);
      this.themeColorHex = ColorPickerUtils.toHex(rgb);
      this.themeColorDarkHex = ColorPickerUtils.toHex(ColorPickerUtils.darken(rgb, 0.4));
      this.hasThemeColor = true;
      this.lastCoverKey = cover;   // ★ 成功后才标记,失败可重试
      this.pickingCover = '';
    }, 100);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层：统一用渐变，未取色时用深灰色过渡，取色后渐变到主色
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 160,
            colors: this.hasThemeColor
              ? [[this.themeColorHex, 0], [this.themeColorDarkHex, 1]]
              : [['#2A2A2A', 0], ['#1A1A1A', 1]]
          })
          .animation({ duration: 600, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')

      // 内容层
      Column() {
        if (this.book) {
          this.buildTopBar()
          this.buildCover()
          this.buildMeta()
          Blank()
          this.buildProgress()
          this.buildControls()
          this.buildBottomBar()
        } else {
          Column()
            .width('100%')
            .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg,
        left: AppSpace.Lg,
        right: AppSpace.Lg
      })

      if (this.showChapterList && this.book) {
        this.buildChapterOverlay()
      }
      if (this.showSleepSheet) {
        this.buildSleepOverlay()
      }
      if (this.showSkipSheet) {
        this.buildSkipOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildTopBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .onClick(() => {
          // mini 入口走共享元素反向,其他入口走 customTransition 下滑
          if (this.entryFromMini) {
            // 恢复 fromMini 让 mini 端挂上 id,然后走反向共享元素
            playerEntryState.fromMini = true;
            this.getUIContext().animateTo({
              duration: 420,
              curve: curves.springMotion(0.6, 0.9)
            }, () => {
              // 必须传 false 关闭系统默认转场,否则会吞掉共享元素动画
              this.navStack.pop(false);
            });
          } else {
            this.navStack.pop();
          }
        })
      Blank()
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .onClick(() => {
          if (this.book) {
            this.navStack.pushPathByName('detail', this.book.id);
          }
        })
    }
    .width('100%')
    .height(48)
  }

  @Builder
  buildCover() {
    Column() {
      if (this.entryFromMini) {
        // mini 入口:挂 geometryTransition 共享元素
        Stack() {
          if (this.book!.cover && this.book!.cover.startsWith('http')) {
            Image(this.book!.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .alt($r('app.media.startIcon'))
              .onError(() => {
                console.error('[PlayerPage] cover image load failed: ' + this.book!.cover);
              })
              .onAppear(() => {
                console.error('[PlayerPage] cover APPEAR, fromMini=true, id=mini-cover-' + this.bookId);
              })
          } else if (this.book!.cover && this.book!.cover.startsWith('/')) {
            Image('file://' + this.book!.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else if (this.book!.cover) {
            Image($rawfile(this.book!.cover))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(80)
                .fontColor(['#FFFFFF'])
            }
            .width('100%')
            .height('100%')
            .backgroundColor('#55FFFFFF')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(16)
        .clip(true)
        .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
        .geometryTransition('mini-cover-' + this.bookId)
      } else {
        // 其他入口:不挂 geometryTransition
        Stack() {
          if (this.book!.cover && this.book!.cover.startsWith('http')) {
            Image(this.book!.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .alt($r('app.media.startIcon'))
              .onError(() => {
                console.error('[PlayerPage] cover image load failed: ' + this.book!.cover);
              })
          } else if (this.book!.cover && this.book!.cover.startsWith('/')) {
            Image('file://' + this.book!.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else if (this.book!.cover) {
            Image($rawfile(this.book!.cover))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(80)
                .fontColor(['#FFFFFF'])
            }
            .width('100%')
            .height('100%')
            .backgroundColor('#55FFFFFF')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(16)
        .clip(true)
        .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: AppSpace.Lg })
  }

  @Builder
  buildMeta() {
    Column({ space: 4 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.playerState.currentChapter ? this.playerState.currentChapter.title : this.book!.title)
            .fontSize(AppFont.TitleL)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.book!.author)
            .fontSize(AppFont.Body)
            .fontColor('#FFFFFF')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(24)
          .fontColor([this.isFavorite ? '#FF6B8A' : '#FFFFFF'])
          .onClick(() => this.toggleFavorite())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: AppSpace.Lg })
  }

  @Builder
  buildProgress() {
    Column({ space: AppSpace.Xxs }) {
      Slider({
        value: this.seeking ? this.seekValueMs : this.playerState.progressMs,
        min: 0,
        // savedDurationMs 兜底:prepared 之前 durationMs=0 会让滑块停在 0,视觉像"从头加载",
        // 用持久化的旧时长撑住,prepared 后 durationMs 一变就被覆盖
        max: this.sliderMaxMs(),
        step: 1000,
        style: SliderStyle.OutSet
      })
        .selectedColor('#FFFFFF')
        .trackColor('#33FFFFFF')
        .blockColor('#FFFFFF')
        .blockSize({ width: 14, height: 14 })
        .trackThickness(3)
        .enabled(this.playerState.durationMs > 0)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.seeking = true;
            this.seekValueMs = value;
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.seekValueMs = value;
            AudioService.getInstance().seek(value);
            // 留 200ms 给 AVPlayer 真正 seek 完成,避免旧 timeUpdate 让滑块回弹
            setTimeout(() => { this.seeking = false; }, 200);
          }
        })

      Row() {
        Text(this.formatMs(this.seeking ? this.seekValueMs : this.playerState.progressMs))
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF')
        Blank()
        Text(this.formatMs(this.displayDurationMs()))
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF')
      }
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: AppSpace.Md })
  }

  @Builder
  buildControls() {
    Row() {
      SymbolGlyph(this.playModeIcon())
        .fontSize(22)
        .fontColor([this.playModeColor()])
        .onClick(() => this.cyclePlayMode())

      Blank()

      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(32)
        .fontColor(['#FFFFFF'])
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
        .onClick(() => this.playPrev())

      Blank()

      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 16, color: '#44FFFFFF', offsetY: 4 })
        if (this.playerState.isLoading) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#2A4A45')
        } else {
          SymbolGlyph(this.playerState.isPlaying
            ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(30)
            .fontColor(['#2A4A45'])
        }
      }
      .width(64)
      .height(64)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
      .onClick(() => {
        console.error('[PlayerPage] Play button clicked, fromMini=' + playerEntryState.fromMini);
        // 加载中禁止重复触发
        if (!this.playerState.isLoading) this.togglePlay();
      })

      Blank()

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(32)
        .fontColor(['#FFFFFF'])
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
        .onClick(() => this.playNext())

      Blank()

      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
        .onClick(() => this.openChapterList())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
  }

  @Builder
  buildBottomBar() {
    Row() {
      Column({ space: 4 }) {
        Text(this.playerState.speed.toString() + 'x')
          .fontSize(AppFont.Body)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
        Text('倍速')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF')
      }
      .layoutWeight(1)
      .onClick(() => this.cycleSpeed())
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => this.resetSpeed())
      )

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(22)
          .fontColor([this.playerState.sleepMinutes > 0 ? AppColor.Brand : '#FFFFFF'])
        Text(this.playerState.sleepMinutes > 0 ? this.formatSleepRemaining() : '定时')
          .fontSize(AppFont.Caption)
          .fontColor(this.playerState.sleepMinutes > 0 ? AppColor.Brand : '#FFFFFF')
      }
      .layoutWeight(1)
      .onClick(() => { this.showSleepSheet = true; })
      .gesture(LongPressGesture().onAction(() => {
        if (this.playerState.sleepMinutes > 0) {
          this.hapticTick();
          this.setSleep(0);
        }
      }))

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(22)
          .fontColor([this.hasSkipConfig() ? '#FF6B8A' : '#FFFFFF'])
        Text(this.hasSkipConfig() ? '已设置' : '跳过')
          .fontSize(AppFont.Caption)
          .fontColor(this.hasSkipConfig() ? '#FF6B8A' : '#FFFFFF')
      }
      .layoutWeight(1)
      .onClick(() => {
        this.skipIntroValue = this.book?.skipIntro ?? 0;
        this.skipOutroValue = this.book?.skipOutro ?? 0;
        this.showSkipSheet = true;
      })
      .gesture(LongPressGesture().onAction(() => {
        if (this.hasSkipConfig()) {
          this.hapticTick();
          this.setSkipValue('intro', 0);
          this.setSkipValue('outro', 0);
          this.skipIntroValue = 0;
          this.skipOutroValue = 0;
        }
      }))
    }
    .width('100%')
    .padding({ top: AppSpace.Lg })
  }

  @Builder
  buildChapterOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => { this.showChapterList = false; })

      Stack({ alignContent: Alignment.BottomEnd }) {
        Column({ space: AppSpace.Sm }) {
          Row() {
            Text('章节列表')
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Blank()
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_tertiary')])
              .onClick(() => { this.showChapterList = false; })
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })

          // 章节搜索框（原生 Search,与首页一致）
          Search({ value: this.chapterSearchKeyword!!, placeholder: '搜索章节' })
            .onChange((value: string) => this.applyChapterFilter(value))
            .height(40)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(AppRadius.Lg)
            .margin({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xs, bottom: AppSpace.Xs })

          this.buildChapterItems()
        }
        .width('100%')
        .height('100%')

        // "回到当前章节"浮动按钮:列表滚远时显示
        if (this.shouldShowJumpButton()) {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.scope'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
            Text('回到当前章节')
              .fontSize(AppFont.Caption)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(22)
          .backgroundColor(AppColor.Brand)
          .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
          .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
          .onClick(() => this.jumpToCurrentChapter())
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
            .animation({ curve: curves.springMotion(0.4, 0.9) }))
        }
      }
      .width('100%')
      .height('55%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 40, color: '#33000000', offsetY: -8 })
      .transition(TransitionEffect.OPACITY
        .animation({ curve: curves.springMotion(0.6, 0.9) })
        .combine(TransitionEffect.translate({ y: 1000 })
          .animation({ curve: curves.springMotion(0.6, 0.9) })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildChapterItems() {
    List({ space: 0, scroller: this.chapterListScroller }) {
      LazyForEach(this.chapterDataSource, (ch: Chapter) => {
        ListItem() {
          Row() {
            Column({ space: 2 }) {
              Text(ch.title)
                .fontSize(AppFont.BodyL)
                .fontColor(this.isCurrentChapter(ch) ? AppColor.Brand : $r('sys.color.font_primary'))
                .fontWeight(this.isCurrentChapter(ch) ? FontWeight.Medium : FontWeight.Normal)
              if (this.chapterDurationSec(ch) > 0) {
                Text(this.formatDuration(this.chapterDurationSec(ch)))
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.isCurrentChapter(ch)) {
              if (this.playerState.isLoading) {
                LoadingProgress()
                  .width(18).height(18).color(AppColor.Brand)
              } else {
                SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
                  .fontSize(18)
                  .fontColor([AppColor.Brand])
              }
            } else if (this.chapterCacheTick >= 0
              && !ChapterCacheService.getInstance().isChapterCached(ch.id)) {
              SymbolGlyph($r('sys.symbol.cloud'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_tertiary')])
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.selectChapter(ch))
        }
      }, (ch: Chapter) => ch.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .cachedCount(5)
    .onScrollIndex((firstIndex: number, lastIndex: number) => {
      // 用首尾可见 index 与当前章节 index 计算偏离
      // 行高约 64vp(BodyL+Caption+padding),用 (center - idx) * 64 估算
      const idx = this.currentChapterIndex();
      if (idx < 0) return;
      const center = (firstIndex + lastIndex) / 2;
      this.listOffsetFromCurrent = (center - idx) * 64;
    })
  }

  @Builder
  buildSleepOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => { this.showSleepSheet = false; })

      Column({ space: AppSpace.Md }) {
        Row() {
          Text('定时关闭')
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_tertiary')])
            .onClick(() => { this.showSleepSheet = false; })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })

        ForEach([15, 30, 45, 60], (min: number) => {
          Row() {
            Text(min + ' 分钟')
              .fontSize(AppFont.BodyL)
              .fontColor(this.playerState.sleepMinutes === min ? AppColor.Brand : $r('sys.color.font_primary'))
              .layoutWeight(1)
            if (this.playerState.sleepMinutes === min) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([AppColor.Brand])
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.setSleep(min))
        }, (min: number) => min.toString())

        if (this.playerState.sleepMinutes > 0) {
          Row() {
            Text('取消定时')
              .fontSize(AppFont.BodyL)
              .fontColor('#FF6B6B')
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.setSleep(0))
        }
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .padding({ bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      .shadow({ radius: 40, color: '#33000000', offsetY: -8 })
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.9) })
        .combine(TransitionEffect.translate({ y: 1000 }).animation({ curve: curves.springMotion(0.6, 0.9) })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSkipOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => { this.showSkipSheet = false; })

      Column({ space: AppSpace.Md }) {
        Row() {
          Text('跳过片头片尾')
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_tertiary')])
            .onClick(() => { this.showSkipSheet = false; })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text('片头')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(`${this.skipIntroValue} 秒`)
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Slider({ value: this.skipIntroValue, min: 0, max: 120, step: 1 })
            .blockColor(AppColor.Brand)
            .trackColor($r('sys.color.comp_background_tertiary'))
            .selectedColor(AppColor.Brand)
            .onChange((value: number) => { this.skipIntroValue = Math.round(value); })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Up) {
                this.setSkipValue('intro', this.skipIntroValue);
              }
            })
            .padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
        .width('100%')
        .padding({ top: AppSpace.Sm })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text('片尾')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(`${this.skipOutroValue} 秒`)
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Slider({ value: this.skipOutroValue, min: 0, max: 120, step: 1 })
            .blockColor(AppColor.Brand)
            .trackColor($r('sys.color.comp_background_tertiary'))
            .selectedColor(AppColor.Brand)
            .onChange((value: number) => { this.skipOutroValue = Math.round(value); })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Up) {
                this.setSkipValue('outro', this.skipOutroValue);
              }
            })
            .padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
        .width('100%')
        .padding({ top: AppSpace.Sm })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .padding({ bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      .shadow({ radius: 40, color: '#33000000', offsetY: -8 })
      .transition(TransitionEffect.OPACITY
        .animation({ curve: curves.springMotion(0.6, 0.9) })
        .combine(TransitionEffect.translate({ y: 1000 })
          .animation({ curve: curves.springMotion(0.6, 0.9) })))
    }
    .width('100%')
    .height('100%')
  }

  private hasSkipConfig(): boolean {
    if (!this.book) return false;
    return (this.book.skipIntro ?? 0) > 0 || (this.book.skipOutro ?? 0) > 0;
  }

  private async setSkipValue(type: string, seconds: number): Promise<void> {
    if (!this.book) return;
    if (type === 'intro') {
      this.book.skipIntro = seconds;
    } else {
      this.book.skipOutro = seconds;
    }
    const b = this.book;
    const cloned: Book = {
      id: b.id, title: b.title, author: b.author, narrator: b.narrator,
      cover: b.cover, category: b.category, intro: b.intro,
      totalDuration: b.totalDuration, chapterCount: b.chapterCount,
      rating: b.rating, tags: b.tags, chapters: b.chapters,
      bookUrl: b.bookUrl, sourceUrl: b.sourceUrl,
      variables: b.variables, skipIntro: b.skipIntro, skipOutro: b.skipOutro
    };
    this.book = cloned;
    await DataService.upsertCachedBook(cloned);
    SearchCache.put(cloned);
    if (this.playerState.currentBook?.id === b.id) {
      this.playerState.currentBook = cloned;
    }
  }
}
