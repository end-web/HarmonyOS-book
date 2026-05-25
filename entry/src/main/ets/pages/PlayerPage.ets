import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { AppColor, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { DataService } from '../service/DataService';
import { AudioService } from '../service/AudioService';
import { PreferenceService } from '../service/PreferenceService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';

@ComponentV2
export struct PlayerPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Local book: Book | null = null;
  @Local isFavorite: boolean = false;
  @Local showChapterList: boolean = false;
  @Local showSleepSheet: boolean = false;
  @Local bgTopColor: string = '#5A8A85';
  @Local bgBottomColor: string = '#3A6A65';
  @Local hasThemeColor: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;;

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private speeds: number[] = [0.75, 1.0, 1.25, 1.75, 2.0];
  private lastCoverKey: string = '';

  aboutToAppear(): void {
    this.loadBook();
  }

  aboutToDisappear(): void {
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

    // 仅绑定状态/上下文，不主动 play —— 启动由 BookDetailPage 负责
    AudioService.getInstance().bind(this.playerState, this.context);
    console.info('[PlayerPage] loadBook complete');
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
      await AudioService.getInstance().playChapter(this.book, this.book.chapters[idx - 1]);
    }
  }

  private async playNext(): Promise<void> {
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.book.chapters.findIndex((c) => c.id === this.playerState.currentChapter!.id);
    if (idx >= 0 && idx < this.book.chapters.length - 1) {
      await AudioService.getInstance().playChapter(this.book, this.book.chapters[idx + 1]);
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
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

  private async extractCoverColor(cover: string): Promise<void> {
    if (!cover || cover === this.lastCoverKey) return;
    this.lastCoverKey = cover;

    console.info('[PlayerPage] extractCoverColor start, cover=' + cover);

    let rgb: RgbColor | null = null;
    try {
      if (cover.startsWith('http')) {
        rgb = await ColorPickerUtils.pickFromUrl(cover);
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
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层：模糊封面 + 主色调叠加
      Stack() {
        if (this.book && this.book.cover) {
          // 模糊封面背景
          if (this.book.cover.startsWith('http')) {
            Image(this.book.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(60)
          } else {
            Image($rawfile(this.book.cover))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(60)
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
          // 加载中状态
          Column() {
            Text('加载中...')
              .fontSize(AppFont.Body)
              .fontColor('#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
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
      SymbolGlyph($r('sys.symbol.more'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
    }
    .width('100%')
    .height(48)
  }

  @Builder
  buildCover() {
    Column() {
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

      // 调试信息：显示当前音频源
      if (this.playerState.currentChapter) {
        Text('音频源: ' + this.playerState.currentChapter.source.value.substring(0, 80))
          .fontSize(10)
          .fontColor('#FFFFFF88')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: AppSpace.Xs })
      }
    }
    .width('100%')
    .padding({ top: AppSpace.Lg })
  }

  @Builder
  buildProgress() {
    Column({ space: AppSpace.Xxs }) {
      Slider({
        value: this.playerState.progressMs,
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
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            AudioService.getInstance().seek(value);
          }
        })

      Row() {
        Text(this.formatMs(this.playerState.progressMs))
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
      SymbolGlyph($r('sys.symbol.repeat'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])

      Blank()

      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(32)
        .fontColor(['#FFFFFF'])
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
      .onClick(() => this.togglePlay())

      Blank()

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(32)
        .fontColor(['#FFFFFF'])
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
