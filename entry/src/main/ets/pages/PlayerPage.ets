import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppColor, AppSpace, AppFont, AppMotion } from '../theme/Theme';
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
  /** 章节分段索引，当前查看的分段 */
  @Local chapterSegmentIndex: number = 0;
  /** 章节列表滚动位置 vs 当前播放章节的偏离（vp）；用来决定是否显示"回到当前章节"浮动按钮 */
  @Local listOffsetFromCurrent: number = 0;

  private context: common.UIAbilityContext | null = null;
  private speeds: number[] = [0.75, 1.0, 1.25, 1.75, 2.0];
  private lastCoverKey: string = '';
  /** 正在取色的封面 key,防止异步取色并发重复触发(取色成功才写 lastCoverKey,失败可重试) */
  private pickingCover: string = '';
  private chapterListScroller: Scroller = new Scroller();
  private segmentTabsScroller: Scroller = new Scroller();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterDurationHandler = (): void => {
    this.chapterCacheTick = this.chapterCacheTick + 1;
  };

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.primeFromCache();
    emitter.on(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    WindowUtils.setStatusBarLight(true);
    setTimeout(() => {
      this.renderBlur = true;
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
    if (!b.cover) return;

    const rgb = ColorPickerUtils.getCached(b.cover);
    if (!rgb) {
      // 取色缓存未命中:不设置 lastCoverKey，让后续 extractCoverColor 正常执行
      return;
    }

    // ★ 延迟 200ms 设置背景色,给封面 Image 组件留解码时间
    setTimeout(() => {
      const cachedRgb = ColorPickerUtils.getCached(b!.cover);
      if (!cachedRgb) return;
      this.blurColor = ColorPickerUtils.toBlurColor(cachedRgb);
      this.themeColorHex = ColorPickerUtils.toHex(cachedRgb);
      this.themeColorDarkHex = ColorPickerUtils.toHex(ColorPickerUtils.darken(cachedRgb, 0.4));
      this.hasThemeColor = true;
      this.lastCoverKey = b!.cover;
    }, 200);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    WindowUtils.setStatusBarLight(false);
    AudioService.getInstance().flushHistory();
  }

  private async loadBook(): Promise<void> {
    console.info('[PlayerPage] loadBook start, bookId=' + this.bookId);
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
      console.info('[PlayerPage] loadBook fallback to playerState.currentBook, requested='
        + this.bookId + ' actual=' + b.id);
    }
    if (!b) {
      console.error('[PlayerPage] loadBook failed, book not found');
      this.navStack.pop();
      return;
    }
    console.info('[PlayerPage] loadBook success, title=' + b.title);
    this.book = b;
    this.isFavorite = await PreferenceService.isFavorite(b.id);
    this.extractCoverColor(b.cover);

    // 绑定全局状态/上下文
    AudioService.getInstance().bind(this.playerState, this.context!);

    // 历史记录入口：若指定了恢复章节，且当前 AudioService 没有在播放该章节，则主动起播 + seek
    if (this.resumeChapterId) {
      await this.tryResumePlay(b);
    }
    console.info('[PlayerPage] loadBook complete');
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
      hilog.info(DOMAIN, TAG, 'resume: PlaybackStore current chapter, reuse live state');
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

  private readonly SEGMENT_SIZE: number = 1000;

  /** 打开章节列表时，根据章节数决定是否分段 */
  private openChapterList(): void {
    this.showChapterList = true;
    this.listOffsetFromCurrent = 0;
    if (!this.book) return;
    // 日志：验证实际章节数（排查"显示 2000 章"问题）
    hilog.info(DOMAIN, TAG, `打开章节列表：共 ${this.book.chapters.length} 章`);
    if (this.book.chapters.length <= this.SEGMENT_SIZE) {
      this.chapterSegmentIndex = 0;
      this.chapterDataSource.setChapters(this.book.chapters);
      this.scrollToCurrentChapter(0);
    } else {
      // 多于 1000 章时，自动定位到当前章节所在分段
      if (this.playerState.currentChapter) {
        const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
        if (idx >= 0) {
          this.chapterSegmentIndex = Math.floor(idx / this.SEGMENT_SIZE);
          this.chapterDataSource.setChapters(this.getSegmentChapters());
          hilog.info(DOMAIN, TAG, `当前章节索引 ${idx}，定位到第 ${this.chapterSegmentIndex + 1} 段`);
          this.scrollToCurrentChapter(this.chapterSegmentIndex * this.SEGMENT_SIZE);
          return;
        }
      }
      this.chapterSegmentIndex = 0;
      this.chapterDataSource.setChapters(this.getSegmentChapters());
    }
  }

  private scrollToCurrentChapter(segmentStart: number): void {
    if (!this.book || !this.playerState.currentChapter) return;
    const globalIdx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (globalIdx < 0) return;
    const localIdx = globalIdx - segmentStart;
    if (localIdx < 0) return;
    setTimeout(() => {
      try {
        this.chapterListScroller.scrollToIndex(localIdx, true, ScrollAlign.CENTER);
      } catch (_e) { /* ignore */ }
    }, 240);
  }

  private getSegmentCount(): number {
    if (!this.book) return 0;
    const total = this.book.chapters.length;
    if (total <= this.SEGMENT_SIZE) return 1;

    const rawCount = Math.ceil(total / this.SEGMENT_SIZE);
    const lastSegSize = total - (rawCount - 1) * this.SEGMENT_SIZE;

    // 最后一段 < 500 章 → 合并到倒数第二段
    if (lastSegSize < 500) {
      return rawCount - 1;
    }
    return rawCount;
  }

  private getSegmentChapters(): Chapter[] {
    if (!this.book || this.chapterSegmentIndex < 0) return [];
    const total = this.book.chapters.length;
    const segCount = this.getSegmentCount();
    const start = this.chapterSegmentIndex * this.SEGMENT_SIZE;

    // 最后一段：吸收所有剩余章节（包括合并的小段）
    if (this.chapterSegmentIndex === segCount - 1) {
      return this.book.chapters.slice(start, total);
    }

    // 非最后一段：标准 1000 章
    const end = Math.min(start + this.SEGMENT_SIZE, total);
    return this.book.chapters.slice(start, end);
  }

  private getSegmentLabel(segIdx: number): string {
    if (!this.book) return '';
    const total = this.book.chapters.length;
    const segCount = this.getSegmentCount();
    const start = segIdx * this.SEGMENT_SIZE;

    // 最后一段：显示到总章节数
    if (segIdx === segCount - 1) {
      return `${start + 1}-${total}`;
    }

    // 非最后一段：标准 1000 章分段
    const end = Math.min(start + this.SEGMENT_SIZE, total);
    return `${start + 1}-${end}`;
  }

  /** "回到当前章节"按钮:切回当前章节所在分段并居中滚到 */
  private jumpToCurrentChapter(): void {
    if (!this.book || !this.playerState.currentChapter) return;
    const globalIdx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (globalIdx < 0) return;
    const targetSeg = Math.floor(globalIdx / this.SEGMENT_SIZE);
    if (targetSeg !== this.chapterSegmentIndex) {
      this.chapterSegmentIndex = targetSeg;
      this.chapterDataSource.setChapters(this.getSegmentChapters());
    }
    this.scrollToCurrentChapter(targetSeg * this.SEGMENT_SIZE);
    this.listOffsetFromCurrent = 0;
  }

  /** 当前播放章节在当前分段内的局部索引,-1 表示不在本分段 */
  private currentChapterLocalIndex(): number {
    if (!this.book || !this.playerState.currentChapter) return -1;
    const globalIdx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (globalIdx < 0) return -1;
    const segStart = this.chapterSegmentIndex * this.SEGMENT_SIZE;
    const localIdx = globalIdx - segStart;
    if (localIdx < 0 || localIdx >= this.SEGMENT_SIZE) return -1;
    return localIdx;
  }

  /** 是否需要显示"回到当前章节"浮动按钮:列表滚动距离当前章节超过 200vp,或当前章节不在本分段 */
  private shouldShowJumpButton(): boolean {
    if (!this.book || !this.playerState.currentChapter) return false;
    const globalIdx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (globalIdx < 0) return false;
    const segStart = this.chapterSegmentIndex * this.SEGMENT_SIZE;
    const localIdx = globalIdx - segStart;
    // 当前章节不在本分段 → 一定显示
    if (localIdx < 0 || localIdx >= this.SEGMENT_SIZE) return true;
    // 在本分段:看滚动偏离
    return Math.abs(this.listOffsetFromCurrent) > 200;
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
      // 背景层：取色成功用主色渐变，失败/未完成时封面模糊兜底
      Stack() {
        if (this.hasThemeColor) {
          // 取色成功：主色→深主色渐变，不渲染封面图
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 160,
              colors: [[this.themeColorHex, 0], [this.themeColorDarkHex, 1]]
            })
            .animation({ duration: 600, curve: Curve.EaseOut })
        } else {
          // 取色未完成/失败：封面模糊兜底
          if (this.book && this.book.cover) {
            if (this.book.cover.startsWith('http')) {
              Image(this.book.cover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            } else if (this.book.cover.startsWith('/')) {
              Image('file://' + this.book.cover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            } else {
              Image($rawfile(this.book.cover))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            }
          }
          // 封面模糊层
          Column()
            .width('100%')
            .height('100%')
            .backgroundEffect({
              radius: this.renderBlur ? 80 : 0,
              saturation: 0.7,
              brightness: 0.85,
              color: this.blurColor
            })
            .animation({ duration: 600, curve: Curve.EaseOut })
        }
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
        .onClick(() => this.navStack.pop())
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
      Stack() {
        if (this.book!.cover && this.book!.cover.startsWith('http')) {
          Image(this.book!.cover)
            .width('100%')
            .aspectRatio(1)
            .borderRadius(16)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
            .alt($r('app.media.startIcon'))
            .onError(() => {
              console.error('[PlayerPage] cover image load failed: ' + this.book!.cover);
            })
            .onComplete(() => {
              console.info('[PlayerPage] cover image loaded: ' + this.book!.cover);
            })
        } else if (this.book!.cover && this.book!.cover.startsWith('/')) {
          Image('file://' + this.book!.cover)
            .width('100%')
            .aspectRatio(1)
            .borderRadius(16)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
        } else if (this.book!.cover) {
          Image($rawfile(this.book!.cover))
            .width('100%')
            .aspectRatio(1)
            .borderRadius(16)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 32, color: '#55000000', offsetY: 12 })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(80)
              .fontColor(['#FFFFFF'])
          }
          .width('100%')
          .aspectRatio(1)
          .borderRadius(16)
          .backgroundColor('#55FFFFFF')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .geometryTransition('book-cover-' + this.bookId, { follow: true })
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
          this.setSleep(0);
        }
      }))
      .gesture(LongPressGesture().onAction(() => {
        if (this.playerState.sleepMinutes > 0) {
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

          if (this.book!.chapters.length > this.SEGMENT_SIZE) {
            this.buildSegmentTabs()
          }

          this.buildChapterItems()
        }
        .width('100%')
        .height('100%')

        // "回到当前章节"浮动按钮:列表滚远了或当前章节不在本分段时显示
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
  buildSegmentTabs() {
    Scroll(this.segmentTabsScroller) {
      Row({ space: 8 }) {
        ForEach(Array.from({ length: this.getSegmentCount() },
          (_: undefined, i: number) => i), (segIdx: number) => {
          Text(this.getSegmentLabel(segIdx))
            .fontSize(AppFont.Body)
            .fontColor(this.chapterSegmentIndex === segIdx ? '#FFFFFF' : $r('sys.color.font_secondary'))
            .backgroundColor(this.chapterSegmentIndex === segIdx ? AppColor.Brand : $r('sys.color.comp_background_tertiary'))
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => {
              this.chapterSegmentIndex = segIdx;
              this.chapterDataSource.setChapters(this.getSegmentChapters());
              this.scrollToCurrentChapter(segIdx * this.SEGMENT_SIZE);
            })
        }, (segIdx: number) => segIdx.toString())
      }
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
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
    .cachedCount(5)
    .onScrollIndex((firstIndex: number, lastIndex: number) => {
      // 用首尾可见 index 与当前章节 localIndex 计算偏离
      // 行高约 64vp(BodyL+Caption+padding),用 (firstIndex - localIdx) * 64 估算
      const localIdx = this.currentChapterLocalIndex();
      if (localIdx < 0) return;
      const center = (firstIndex + lastIndex) / 2;
      this.listOffsetFromCurrent = (center - localIdx) * 64;
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
