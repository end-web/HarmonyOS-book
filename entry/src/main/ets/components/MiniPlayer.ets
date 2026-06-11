import { AppSpace, AppFont } from '../theme/Theme';
import { PlayerState } from '../model/PlayerState';
import { playerEntryState } from '../pages/PlayerPage';

@ComponentV2
export struct MiniPlayer {
  @Param playerState: PlayerState = new PlayerState();
  @Param collapsed: boolean = true;
  @Event onTapBody: () => void = () => {};
  @Event onToggle: () => void = () => {};
  @Event onNext: () => void = () => {};
  @Event onExpand: () => void = () => {};

  @Local coverAngle: number = 0;
  private rotateTimer: number = -1;

  aboutToAppear(): void {
    if (this.playerState.isPlaying) {
      this.startRotate();
    }
  }

  aboutToDisappear(): void {
    this.stopRotate();
  }

  @Monitor('playerState.isPlaying')
  onPlayingChange(): void {
    if (this.playerState.isPlaying) {
      this.startRotate();
    } else {
      this.stopRotate();
    }
  }

  private startRotate(): void {
    if (this.rotateTimer >= 0) return;
    // 20秒转360度 = 每帧(16.67ms@60fps)转0.3度
    this.rotateTimer = setInterval(() => {
      this.coverAngle = (this.coverAngle + 0.3) % 360;
    }, 16);
  }

  private stopRotate(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
    // 保持当前角度,不回正
  }

  private bookId(): string {
    return this.playerState.currentBook ? this.playerState.currentBook.id : '';
  }

  @Builder
  coverImageBuilder(): void {
    if (this.playerState.currentBook) {
      if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('http')) {
        Image(this.playerState.currentBook.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.coverAngle })
          .id('mini-cover-img')
      } else if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('/')) {
        Image('file://' + this.playerState.currentBook.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.playerState.isPlaying ? 360 : 0 })
          .animation({
            duration: this.playerState.isPlaying ? 20000 : 300,
            curve: this.playerState.isPlaying ? Curve.Linear : Curve.Friction,
            iterations: this.playerState.isPlaying ? -1 : 1,
            expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
          })
          .id('mini-cover-img-file')
      } else if (this.playerState.currentBook.cover) {
        Image($rawfile(this.playerState.currentBook.cover))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.playerState.isPlaying ? 360 : 0 })
          .animation({
            duration: this.playerState.isPlaying ? 20000 : 300,
            curve: this.playerState.isPlaying ? Curve.Linear : Curve.Friction,
            iterations: this.playerState.isPlaying ? -1 : 1,
            expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
          })
          .id('mini-cover-img-raw')
      }
    }
  }

  build() {
    if (this.playerState.currentBook) {
      if (this.collapsed) {
        Stack() {
          this.coverImageBuilder()
        }
        .width('100%')
        .height('100%')
        .onClick(() => this.onExpand())
      } else {
        Row({ space: AppSpace.Sm }) {
          if (playerEntryState.fromMini) {
            // mini 入口:挂 geometryTransition
            Stack() {
              this.coverImageBuilder()
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .clip(true)
            .geometryTransition('mini-cover-' + this.bookId(), { follow: true })
            .onClick(() => this.onTapBody())
          } else {
            // 非 mini 入口:不挂 geometryTransition
            Stack() {
              this.coverImageBuilder()
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .clip(true)
            .onClick(() => this.onTapBody())
          }

          Column({ space: 2 }) {
            Text(this.playerState.currentBook.title)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.playerState.currentChapter ? this.playerState.currentChapter.title : '--')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.onTapBody())

          SymbolGlyph(this.playerState.isPlaying
            ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .hitTestBehavior(HitTestMode.Block)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onToggle())

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
            .hitTestBehavior(HitTestMode.Block)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onNext())
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Xs, right: AppSpace.Md })
      }
    }
  }
}
