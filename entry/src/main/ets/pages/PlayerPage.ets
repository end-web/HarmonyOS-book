import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppSpace, AppFont, AppMotion } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { PlayerState, PLAYER_STATE_KEY, PlayMode } from '../model/PlayerState';
import { DataService } from '../service/DataService';
import { AudioService } from '../service/AudioService';
import { BookSourceService } from '../service/BookSourceService';
import { PreferenceService } from '../service/PreferenceService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';
import { ChapterCacheService } from '../service/ChapterCacheService';

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
  @Local bgTopColor: string = '#2A2A2A';
  @Local bgBottomColor: string = '#0F0F0F';
  @Local hasThemeColor: boolean = false;
  @Local renderBlur: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;;
  @Local seeking: boolean = false;
  @Local seekValueMs: number = 0;

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private speeds: number[] = [0.75, 1.0, 1.25, 1.75, 2.0];
  private lastCoverKey: string = '';

  aboutToAppear(): void {
    this.primeFromCache();
    // loadBook 内含 AVSession 初始化、prefs 读取、可能的网络请求,推迟到转场结束后再执行,
    // 让 380ms 的 push 动画跑得干净
    setTimeout(() => {
      this.renderBlur = true;
      this.loadBook();
    }, AppMotion.Page);
  }

  /** 同步从 SearchCache + ColorPickerUtils 缓存取得 book/cover/color，避免首帧默认色闪烁 */
  private primeFromCache(): void {
    const b = SearchCache.get(this.bookId);
    if (!b) return;
    this.book = b;
    if (!b.cover) return;
    const rgb = ColorPickerUtils.getCached(b.cover);
    if (!rgb) return;
    const top = ColorPickerUtils.darken(rgb, 0.2);
    const bottom = ColorPickerUtils.darken(rgb, 0.4);
    this.bgTopColor = ColorPickerUtils.toHex(top);
    this.bgBottomColor = ColorPickerUtils.toHex(bottom);
    this.hasThemeColor = true;
    this.lastCoverKey = b.cover;
  }

  aboutToDisappear(): void {
    // 退出播放页时立即把进度落盘,避免书架要等下一个 5s tick 才能看到最新进度
    AudioService.getInstance().flushHistory();
  }

  private async loadBook(): Promise<void> {
    console.info('[PlayerPage] loadBook start, bookId=' + this.bookId);
    let b = SearchCache.get(this.bookId);
    if (!b) {
      b = await DataService.getBookById(this.context, this.bookId) || null;
    }
    if (!b) {
      console.error('[PlayerPage] loadBook failed, book not found');
      return;
    }
    console.info('[PlayerPage] loadBook success, title=' + b.title);
    this.book = b;
    this.isFavorite = await PreferenceService.isFavorite(b.id);
    this.extractCoverColor(b.cover);

    // 绑定全局状态/上下文
    AudioService.getInstance().bind(this.playerState, this.context);

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
    // 当前已经是同一书 + 同一章节：直接复用,不重新 seek 打断进度
    const cur = this.playerState.currentChapter;
    const curBook = this.playerState.currentBook;
    if (curBook && cur && curBook.id === book.id && cur.id === target.id) {
      hilog.info(DOMAIN, TAG, 'resume: already current chapter, skip restart');
      return;
    }
    // url 类型 + 书源:解析真实播放地址（优先读预加载缓存）
    if (target.source.type === 'url' && book.sourceUrl) {
      const cached = ChapterCacheService.getInstance().getAudioUrl(target.id);
      if (cached) {
        target.source = { type: 'url', value: cached };
      } else {
        try {
          const sourcesJson = await PreferenceService.getBookSources();
          const sources = JSON.parse(sourcesJson) as BookSource[];
          const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
          if (source) {
            const audioUrl = await BookSourceService.getAudioUrl(source, target.source.value);
            target.source = { type: 'url', value: audioUrl };
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'resume getAudioUrl failed');
        }
      }
    }
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

  private async togglePlay(): Promise<void> {
    await AudioService.getInstance().toggle();
  }

  private async playPrev(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (idx > 0) {
      const ch = this.book.chapters[idx - 1];
      this.applyCachedUrl(ch);
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async playNext(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (idx >= 0 && idx < this.book.chapters.length - 1) {
      const ch = this.book.chapters[idx + 1];
      this.applyCachedUrl(ch);
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private applyCachedUrl(chapter: Chapter): void {
    if (chapter.source.type !== 'url') return;
    const cached = ChapterCacheService.getInstance().getAudioUrl(chapter.id);
    if (cached) {
      chapter.source = { type: 'url', value: cached };
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

  private isCurrentChapter(ch: Chapter): boolean {
    return this.playerState.currentChapter !== null && this.playerState.currentChapter.id === ch.id;
  }

  private formatDuration(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return m + '分' + (s > 0 ? s + '秒' : '');
  }

  private async selectChapter(ch: Chapter): Promise<void> {
    if (!this.book) return;
    await AudioService.getInstance().playChapter(this.book, ch);
    this.showChapterList = false;
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
    if (!cover || cover === this.lastCoverKey) return;
    this.lastCoverKey = cover;

    console.info('[PlayerPage] extractCoverColor start, cover=' + cover);

    // 异步提取，不阻塞 UI
    setTimeout(async () => {
      let rgb: RgbColor | null = null;
      try {
        if (cover.startsWith('http')) {
          rgb = await ColorPickerUtils.pickFromUrl(cover);
        } else if (cover.startsWith('/')) {
          rgb = await ColorPickerUtils.pickFromFile(cover);
        } else {
          rgb = await ColorPickerUtils.pickFromRawfile(this.context, cover);
        }
      } catch (e) {
        console.error('[PlayerPage] extractCoverColor failed: ' + JSON.stringify(e));
      }

      if (!rgb) {
        console.warn('[PlayerPage] extractCoverColor got null, keep default colors');
        return;
      }

      if (cover !== this.lastCoverKey) {
        console.warn('[PlayerPage] cover changed during extraction, abort');
        return;
      }

      const top = ColorPickerUtils.darken(rgb, 0.2);
      const bottom = ColorPickerUtils.darken(rgb, 0.4);
      this.bgTopColor = ColorPickerUtils.toHex(top);
      this.bgBottomColor = ColorPickerUtils.toHex(bottom);
      this.hasThemeColor = true;

      console.info('[PlayerPage] extractCoverColor success, top=' + this.bgTopColor + ', bottom=' + this.bgBottomColor);
    }, 100);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层：模糊封面 + 主色调叠加
      Stack() {
        // 兜底纯色背景（避免转场时透出）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.bgBottomColor)

        if (this.book && this.book.cover) {
          if (this.book.cover.startsWith('http')) {
            Image(this.book.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(this.renderBlur ? 60 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut })
          } else if (this.book.cover.startsWith('/')) {
            Image('file://' + this.book.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(this.renderBlur ? 60 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut })
          } else {
            Image($rawfile(this.book.cover))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(this.renderBlur ? 60 : 0)
              .animation({ duration: 600, curve: Curve.EaseOut })
          }
        }

        // 主色调叠加层
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [[this.bgTopColor + '99', 0.0], [this.bgBottomColor + 'CC', 1.0]]
          })
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
        max: this.playerState.durationMs > 0 ? this.playerState.durationMs : 1,
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
        Text(this.formatMs(this.playerState.durationMs))
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

      Stack() {
        Column()
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 16, color: '#44FFFFFF', offsetY: 4 })
        SymbolGlyph(this.playerState.isPlaying
          ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(30)
          .fontColor(['#2A4A45'])
      }
      .width(64)
      .height(64)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
      .onClick(() => this.togglePlay())

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
        .onClick(() => { this.showChapterList = true; })
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

      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(22)
          .fontColor([this.playerState.sleepMinutes > 0 ? '#FF6B8A' : '#FFFFFF'])
        Text(this.playerState.sleepMinutes > 0 ? this.formatSleepRemaining() : '定时')
          .fontSize(AppFont.Caption)
          .fontColor(this.playerState.sleepMinutes > 0 ? '#FF6B8A' : '#FFFFFF')
      }
      .layoutWeight(1)
      .onClick(() => { this.showSleepSheet = true; })
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

        List({ space: 0 }) {
          ForEach(this.book!.chapters, (ch: Chapter) => {
            ListItem() {
              Row() {
                Column({ space: 2 }) {
                  Text(ch.title)
                    .fontSize(AppFont.BodyL)
                    .fontColor(this.isCurrentChapter(ch) ? AppColor.Brand : $r('sys.color.font_primary'))
                    .fontWeight(this.isCurrentChapter(ch) ? FontWeight.Medium : FontWeight.Normal)
                  Text(this.formatDuration(ch.duration))
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.isCurrentChapter(ch)) {
                  SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
                    .fontSize(18)
                    .fontColor([AppColor.Brand])
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
      }
      .width('100%')
      .height('55%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 40, color: '#33000000', offsetY: -8 })
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.9) })
        .combine(TransitionEffect.translate({ y: 1000 }).animation({ curve: curves.springMotion(0.6, 0.9) })))
    }
    .width('100%')
    .height('100%')
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
}
