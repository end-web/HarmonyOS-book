import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { AppColor, AppSpace, AppFont, AppMotion, AppRadius } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { PlayerState, PLAYER_STATE_KEY, PlayMode } from '../model/PlayerState';
import { DataService } from '../service/DataService';
import { AudioPlayFailedPayload, AudioService, EVT_AUDIO_PLAY_FAILED } from '../service/AudioService';
import { PreferenceService } from '../service/PreferenceService';
import { PlaybackStore } from '../service/PlaybackStore';
import { DownloadService, DownloadUpdatePayload, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadChapterRecord } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, CoverColorPalette } from '../utils/ColorPickerUtils';
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
 * 由 PlayerPage 注册的离场协调器:
 * 返回时通知 PlayerPage 取消延迟加载 timer、提前中断 loadBook 异步链,避免阻塞返回响应。
 */
export class PlayerEntryDecider {
  /** 取消 pending 的延迟加载 timer */
  private static cancelPendingClearHandler: (() => void) | null = null;
  /** 标记 PlayerPage 即将离开,让 loadBook 异步链提前退出 */
  private static markLeavingHandler: (() => void) | null = null;

  static setCancelPendingClear(h: (() => void) | null): void {
    PlayerEntryDecider.cancelPendingClearHandler = h;
  }

  static setMarkLeaving(h: (() => void) | null): void {
    PlayerEntryDecider.markLeavingHandler = h;
  }

  /** 返回前调用,取消 pending 的延迟加载 timer */
  static cancelPendingClear(): void {
    if (PlayerEntryDecider.cancelPendingClearHandler) {
      PlayerEntryDecider.cancelPendingClearHandler();
    }
  }

  /** 返回前调用,通知 PlayerPage 立即停止 loadBook 等异步操作 */
  static markLeaving(): void {
    if (PlayerEntryDecider.markLeavingHandler) {
      PlayerEntryDecider.markLeavingHandler();
    }
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
  @Local showSpeedSheet: boolean = false;
  @Local skipIntroValue: number = 0;
  @Local skipOutroValue: number = 0;
  /** 倍速滑块当前值(拖动时实时显示,松手才真正下发到 AudioService) */
  @Local speedValue: number = 1.0;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;;
  @Local seeking: boolean = false;
  @Local seekValueMs: number = 0;
  /** 缓存版本号：每次有章节时长被解析出来就 +1，强制 V2 重渲染章节列表 */
  @Local chapterCacheTick: number = 0;
  @Local downloadTick: number = 0;
  /** 章节列表滚动位置 vs 当前播放章节的偏离（vp）；用来决定是否显示"回到当前章节"浮动按钮 */
  @Local listOffsetFromCurrent: number = 0;
  /** 章节搜索关键词；非空时章节列表按标题过滤 */
  @Local chapterSearchKeyword: string = '';

  private context: common.UIAbilityContext | null = null;
  private lastCoverKey: string = '';
  /** 正在取色的封面 key,防止异步取色并发重复触发(取色成功才写 lastCoverKey,失败可重试) */
  private pickingCover: string = '';
  private chapterListScroller: Scroller = new Scroller();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterDurationHandler = (): void => {
    this.chapterCacheTick = this.chapterCacheTick + 1;
    this.chapterDataSource.notifyDataReloaded();
  };
  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId !== this.bookId) return;
    this.downloadTick = this.downloadTick + 1;
    if (!data.progressOnly) this.chapterDataSource.notifyDataReloaded();
  };
  private audioPlayFailedHandler = (evt: emitter.EventData): void => {
    const data = evt.data as AudioPlayFailedPayload;
    if (!data || data.bookId !== this.bookId) return;
    if (this.playerState.currentChapter && data.chapterId !== this.playerState.currentChapter.id) return;
    this.showToast(data.message || '播放失败，请点击重试');
  };
  /** 延迟加载 timer id,用户立即返回时需要 cancel,避免阻塞返回响应 */
  private deferredLoadTimerId: number = -1;
  /** 用户已触发返回,loadBook 异步链应在 await 后检查并提前退出,避免阻塞主线程 */
  private isLeaving: boolean = false;
  /** 错落渐显:控制内容进场动画,进入后延迟触发 */
  @Local contentVisible: boolean = false;

  /** 取消 pending 的延迟加载 timer,返回前调用避免阻塞返回响应 */
  private cancelPendingClearTimers(): void {
    if (this.deferredLoadTimerId !== -1) {
      clearTimeout(this.deferredLoadTimerId);
      this.deferredLoadTimerId = -1;
    }
  }

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    PlayerEntryDecider.setCancelPendingClear(() => this.cancelPendingClearTimers());
    PlayerEntryDecider.setMarkLeaving(() => { this.isLeaving = true; });
    PlayerBackInterceptor.set((): boolean => this.handleBack());
    this.primeFromCache();
    emitter.on(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    emitter.on(EVT_AUDIO_PLAY_FAILED, this.audioPlayFailedHandler);
    WindowUtils.setStatusBarLight(true);
    // 错落渐显:进场后下一帧触发内容动画
    setTimeout(() => { this.contentVisible = true; }, 16);
    this.deferredLoadTimerId = setTimeout(() => {
      this.deferredLoadTimerId = -1;
      this.loadBook();
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
    AudioService.getInstance().prewarmBookSource(b);
    if (!b.cover) return;

    const palette = ColorPickerUtils.getPaletteCached(b.cover);
    if (!palette) {
      // 分区取色缓存未命中:不设置 lastCoverKey，让后续 extractCoverColor 正常执行
      return;
    }

    // 缓存命中:立即同步设置融合色,避免灰色过渡
    this.applyCoverPalette(palette, b.cover);
    this.lastCoverKey = b.cover;
  }

  aboutToDisappear(): void {
    this.isLeaving = true;
    PlayerBackInterceptor.set(null);
    PlayerEntryDecider.setCancelPendingClear(null);
    PlayerEntryDecider.setMarkLeaving(null);
    this.cancelPendingClearTimers();
    emitter.off(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    emitter.off(EVT_AUDIO_PLAY_FAILED, this.audioPlayFailedHandler);
    WindowUtils.setStatusBarLight(false);
    AudioService.getInstance().flushHistory();
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
    if (this.showSpeedSheet) {
      this.showSpeedSheet = false;
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
    if (this.isLeaving) return;
    let b = SearchCache.get(this.bookId);
    if (!b) {
      b = await DataService.getBookById(this.context!, this.bookId) || null;
      if (this.isLeaving) return;
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
    // 独立 KV 为权威:贴回 skip,纠正冷启动缓存书壳可能丢失的跳过头尾
    await PreferenceService.applySkipConfig(b);
    if (this.isLeaving) return;
    this.book = b;
    AudioService.getInstance().prewarmBookSource(b);
    this.isFavorite = await PreferenceService.isFavorite(b.id);
    if (this.isLeaving) return;
    this.extractCoverColor(b.cover);

    // 绑定全局状态/上下文
    AudioService.getInstance().bind(this.playerState, this.context!);

    // 历史记录入口：若指定了恢复章节，且当前 AudioService 没有在播放该章节，则主动起播 + seek
    if (this.resumeChapterId && !this.isLeaving) {
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
    const idx = this.currentChapterIndex();
    if (idx > 0) {
      const ch = this.book.chapters[idx - 1];
      // AudioService 内部会查缓存/解析 URL，这里不用再做
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async playNext(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.currentChapterIndex();
    if (idx >= 0 && idx < this.book.chapters.length - 1) {
      const ch = this.book.chapters[idx + 1];
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    // 收藏 id 还在但本地快照已丢失:补回快照、保留收藏,而不是把仅存的收藏 id 也 toggle 掉
    if (this.isFavorite && this.context) {
      const snap = await DataService.getBookById(this.context!, this.book.id);
      if (!snap) {
        await DataService.upsertCachedBook(this.book);
        this.isFavorite = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '已重新加入书架' });
        } catch (_e) { /* ignore */ }
        return;
      }
    }
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      await DataService.upsertCachedBook(this.book);
    }
  }

  /** 倍速显示:整十分位用一位小数(1.0/1.2/2.0),其余保留两位(0.75/1.25) */
  private fmtSpeed(s: number): string {
    const r = Math.round(s * 20) / 20;
    return Math.abs(r * 10 - Math.round(r * 10)) < 1e-6 ? r.toFixed(1) : r.toFixed(2);
  }

  private async resetSpeed(): Promise<void> {
    if (this.playerState.speed === 1.0) return;
    this.hapticTick();
    await AudioService.getInstance().setSpeed(1.0);
  }

  private isCurrentChapter(ch: Chapter): boolean {
    if (!this.playerState.currentChapter) return false;
    if (this.playerState.currentChapter.id === ch.id) return true;
    if (!this.book) return false;
    const idx = this.currentChapterIndex();
    return idx >= 0 && this.book.chapters[idx].id === ch.id;
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

  private chapterDownloadRecord(ch: Chapter): DownloadChapterRecord | null {
    if (this.downloadTick < 0 || !this.book) return null;
    return DownloadService.getInstance().getChapterStatus(this.book.id, ch);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_e) {
      // ignore
    }
  }

  private handleChapterDownloadLongPress(ch: Chapter): void {
    if (!this.book) return;
    const record = this.chapterDownloadRecord(ch);
    if (record?.status === 'completed') {
      this.confirmDeleteChapterDownload(ch);
      return;
    }
    if (record && (record.status === 'pending' || record.status === 'resolving' || record.status === 'downloading')) {
      this.showToast('这一章正在下载');
      return;
    }
    DownloadService.getInstance().downloadChapter(this.book, ch).then(() => {
      this.downloadTick = this.downloadTick + 1;
      this.showToast('已加入单章下载');
    }).catch(() => this.showToast('下载操作失败，请重试'));
  }

  private confirmDeleteChapterDownload(ch: Chapter): void {
    if (!this.book) return;
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '删除单章下载',
      message: `删除《${ch.title}》的离线音频？`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1 && this.book) {
        DownloadService.getInstance().deleteChapterDownload(
          this.book.id, ch.id, DownloadPolicy.stablePageUrl(ch)).then(() => {
          this.downloadTick = this.downloadTick + 1;
          this.showToast('单章下载已删除');
        }).catch(() => this.showToast('删除下载失败，请重试'));
      }
    }).catch(() => { /* ignore */ });
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
    const idx = this.currentChapterIndex();
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
    return DataService.resolveChapterIndex(
      this.book,
      this.playerState.currentChapter.id,
      this.playerState.currentChapter.title
    );
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
    if (this.playerState.playMode === PlayMode.SingleLoop) return $r('sys.symbol.repeat_1');
    if (this.playerState.playMode === PlayMode.ListLoop) return $r('sys.symbol.repeat');
    return $r('sys.symbol.arrow_right');
  }

  private playModeColor(): string {
    return this.playerState.playMode === PlayMode.Sequence ? '#FFFFFF' : '#FFD480';
  }

  private openBookDetail(): void {
    const id = this.book?.id || this.bookId;
    if (!id) {
      this.showToast('暂无书籍详情');
      return;
    }
    this.navStack.pushPathByName('detail', id);
  }

  private applyCoverPalette(palette: CoverColorPalette, cover: string): void {
    const theme = ColorPickerUtils.toAmbientTheme(palette);
    // 颜色状态变化包进 animateTo:背景主色渐变随封面切换平滑过渡,而不是硬跳
    this.getUIContext().animateTo({ duration: 500, curve: Curve.Linear }, () => {
      this.playerState.accentColor = theme.center;
      this.playerState.ambientCover = cover;
      this.playerState.ambientMainColor = theme.main;
      this.playerState.ambientTopColor = theme.top;
      this.playerState.ambientBottomColor = theme.bottom;
      this.playerState.ambientLeftColor = theme.left;
      this.playerState.ambientRightColor = theme.right;
      this.playerState.ambientCenterColor = theme.center;
      this.playerState.ambientDarkColor = theme.dark;
      this.playerState.hasAmbientColor = true;
    });
  }

  private async extractCoverColor(cover: string): Promise<void> {
    // 已成功取过色 / 正在取这张图 → 跳过
    if (!cover || cover === this.lastCoverKey || cover === this.pickingCover) return;

    // 缓存命中:立即同步设置融合色,不走 setTimeout
    const cachedPalette = ColorPickerUtils.getPaletteCached(cover);
    if (cachedPalette) {
      this.applyCoverPalette(cachedPalette, cover);
      this.lastCoverKey = cover;
      return;
    }

    // 缓存未命中:异步取色
    this.pickingCover = cover;
    setTimeout(async () => {
      let palette: CoverColorPalette | null = null;
      try {
        if (cover.startsWith('http')) {
          palette = await ColorPickerUtils.pickPaletteFromUrl(cover);
        } else if (cover.startsWith('/')) {
          palette = await ColorPickerUtils.pickPaletteFromFile(cover);
        } else {
          palette = await ColorPickerUtils.pickPaletteFromRawfile(this.context!, cover);
        }
      } catch (e) {
        console.error('[PlayerPage] extractCoverColor failed: ' + JSON.stringify(e));
      }

      // 取色失败:释放占位,允许后续重试(不写 lastCoverKey)
      if (!palette) {
        if (this.pickingCover === cover) this.pickingCover = '';
        return;
      }
      // 取色期间封面已切换 → 丢弃旧结果
      if (cover !== this.pickingCover) return;

      this.applyCoverPalette(palette, cover);
      this.lastCoverKey = cover;   // ★ 成功后才标记,失败可重试
      this.pickingCover = '';
    }, 100);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildAmbientBackground()

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
      if (this.showSpeedSheet) {
        this.buildSpeedOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildAmbientBackground() {
    Stack() {
      // 深色安静底:全屏白字/白控件的可读性基座
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#15171B')

      // 封面主色从顶部向下 alpha 消散融入深底:背景跟随封面主题色,换书由 animateTo 平滑过渡
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.playerState.hasAmbientColor
            ? [[this.playerState.ambientMainColor, 0],
               [ColorPickerUtils.withAlpha(this.playerState.ambientMainColor, '73'), 0.42],
               [ColorPickerUtils.withAlpha(this.playerState.ambientMainColor, '00'), 0.88]]
            : [['#3B4650', 0], ['#733B4650', 0.42], ['#003B4650', 0.88]]
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTopBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .onClick(() => {
          // 立即标记离开,让 loadBook 异步链提前退出,不阻塞主线程
          this.isLeaving = true;
          // 统一走 customTransition 下滑退场
          this.navStack.pop();
        })
      Blank()
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .onClick(() => this.openBookDetail())
    }
    .width('100%')
    .height(48)
  }

  @Builder
  coverContent() {
    if (this.book!.cover && this.book!.cover.startsWith('http')) {
      Image(this.book!.cover)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.app_icon_legacy'))
        .onError(() => {
          console.error('[PlayerPage] cover image load failed: ' + this.book!.cover);
        })
    } else if (this.book!.cover && (this.book!.cover.startsWith('/') || this.book!.cover.startsWith('file://'))) {
      // 判断与 BookCard.isLocalFile 对齐:file:// 前缀不能掉进 $rawfile 分支
      // 大封面不设 sourceSize:全屏展示需要原图清晰度
      Image('file://' + this.book!.cover.replace(/^file:\/\//, ''))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.book!.cover) {
      Image($rawfile(this.book!.cover))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      // 无封面:用 app 图标占位(替代旧的绿色书形占位)
      Image($r('app.media.app_icon_legacy'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
  }

  @Builder
  buildCover() {
    Column() {
      Stack() {
        this.coverContent()
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(16)
      .clip(true)
      .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: AppSpace.Lg })
    // 错落渐显:封面先入场(50ms delay)
    .opacity(this.contentVisible ? 1 : 0)
    .translate({ y: this.contentVisible ? 0 : 20 })
    .animation({ duration: 400, delay: 50, curve: Curve.Sharp })
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
        .blockSize({ width: 18, height: 18 })
        .trackThickness(6)
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
      // 左右内缩 ~ block 半径,让时间对齐到轨道两端而非贴边
      .padding({ left: 9, right: 9 })
      // 再往上靠一点点,缩小与进度条的间距
      .margin({ top: -3 })
    }
    .width('100%')
    .padding({ bottom: AppSpace.Md })
    // 错落渐显:进度条第二入场(100ms delay)
    .opacity(this.contentVisible ? 1 : 0)
    .translate({ y: this.contentVisible ? 0 : 20 })
    .animation({ duration: 400, delay: 100, curve: Curve.Sharp })
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
            .color(this.playerState.hasAmbientColor ? this.playerState.ambientDarkColor : '#333333')
        } else {
          SymbolGlyph(this.playerState.isPlaying
            ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(30)
            .fontColor([this.playerState.hasAmbientColor ? this.playerState.ambientDarkColor : '#333333'])
        }
      }
      .width(64)
      .height(64)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
      .onClick(() => {
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
    // 错落渐显:控制条最后入场(150ms delay)
    .opacity(this.contentVisible ? 1 : 0)
    .translate({ y: this.contentVisible ? 0 : 20 })
    .animation({ duration: 400, delay: 150, curve: Curve.Sharp })
  }

  @Builder
  buildBottomBar() {
    Row() {
      Column({ space: 4 }) {
        Text(this.fmtSpeed(this.playerState.speed) + 'x')
          .fontSize(AppFont.Body)
          .fontColor(this.playerState.speed !== 1.0 ? AppColor.Brand : '#FFFFFF')
          .fontWeight(FontWeight.Medium)
        Text('倍速')
          .fontSize(AppFont.Caption)
          .fontColor(this.playerState.speed !== 1.0 ? AppColor.Brand : '#FFFFFF')
      }
      .layoutWeight(1)
      .onClick(() => {
        this.speedValue = this.playerState.speed;
        this.showSpeedSheet = true;
      })
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
          .fontColor([this.hasSkipConfig() ? AppColor.Brand : '#FFFFFF'])
        Text(this.hasSkipConfig() ? '已设置' : '跳过')
          .fontSize(AppFont.Caption)
          .fontColor(this.hasSkipConfig() ? AppColor.Brand : '#FFFFFF')
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
          this.persistSkip(0, 0);
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
            } else {
              this.buildChapterDownloadIndicator(ch)
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.selectChapter(ch))
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => this.handleChapterDownloadLongPress(ch))
          )
        }
      }, (ch: Chapter) => DownloadPolicy.stablePageUrl(ch) || ch.id)
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

  @Builder
  buildSpeedOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => { this.showSpeedSheet = false; })

      Column({ space: AppSpace.Md }) {
        Row() {
          Text('播放速度')
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Blank()
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_tertiary')])
            .onClick(() => { this.showSpeedSheet = false; })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text('倍速')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(this.fmtSpeed(this.speedValue) + 'x')
              .fontSize(AppFont.TitleL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Slider({ value: this.speedValue, min: 0.5, max: 3.0, step: 0.05 })
            .blockColor(AppColor.Brand)
            .trackColor($r('sys.color.comp_background_tertiary'))
            .selectedColor(AppColor.Brand)
            .onChange((value: number) => { this.speedValue = Math.round(value * 20) / 20; })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Up) {
                AudioService.getInstance().setSpeed(this.speedValue);
              }
            })
            .padding({ left: AppSpace.Md, right: AppSpace.Md })

          Row() {
            Text('0.5x')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Blank()
            Text('3.0x')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
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
    const intro = type === 'intro' ? seconds : (this.book.skipIntro ?? 0);
    const outro = type === 'outro' ? seconds : (this.book.skipOutro ?? 0);
    await this.persistSkip(intro, outro);
  }

  /** 原子写片头+片尾:一次 saveSkipConfig,避免长按清空时两次异步各写各的留半状态 */
  private async persistSkip(intro: number, outro: number): Promise<void> {
    if (!this.book) return;
    const b = this.book;
    const cloned: Book = {
      id: b.id, title: b.title, author: b.author, narrator: b.narrator,
      cover: b.cover, category: b.category, intro: b.intro,
      totalDuration: b.totalDuration, chapterCount: b.chapterCount,
      rating: b.rating, tags: b.tags, chapters: b.chapters,
      bookUrl: b.bookUrl, sourceUrl: b.sourceUrl,
      variables: b.variables, skipIntro: intro, skipOutro: outro
    };
    this.book = cloned;
    // 独立 KV 落盘(权威来源):冷启动恢复不依赖缓存书索引,避免走 legacy/persistUnsafe 兜底时丢 skip
    await PreferenceService.saveSkipConfig(cloned.id, intro, outro);
    await DataService.upsertCachedBook(cloned);
    SearchCache.put(cloned);
    if (this.playerState.currentBook?.id === b.id) {
      this.playerState.currentBook = cloned;
    }
  }

  @Builder
  buildChapterDownloadIndicator(ch: Chapter) {
    if (this.chapterDownloadRecord(ch)?.status === 'completed') {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(16)
        .fontColor([AppColor.Brand])
    } else if (this.chapterDownloadRecord(ch)?.status === 'pending'
      || this.chapterDownloadRecord(ch)?.status === 'resolving'
      || this.chapterDownloadRecord(ch)?.status === 'downloading') {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(AppColor.Brand)
    } else if (this.chapterDownloadRecord(ch)?.status === 'failed') {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(16)
        .fontColor(['#D03050'])
    } else if (this.chapterCacheTick >= 0 && !ChapterCacheService.getInstance().isAudioChapterCached(this.book!, ch)) {
      SymbolGlyph($r('sys.symbol.cloud'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
    }
  }
}
