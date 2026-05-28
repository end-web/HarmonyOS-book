import { AppSpace, AppFont } from '../theme/Theme';
import { PlayerState } from '../model/PlayerState';

@ComponentV2
export struct MiniPlayer {
  @Param playerState: PlayerState = new PlayerState();
  @Param collapsed: boolean = true;
  @Event onTapBody: () => void = () => {};
  @Event onToggle: () => void = () => {};
  @Event onNext: () => void = () => {};
  @Event onExpand: () => void = () => {};

  @Local coverAngle: number = 0;
  @Local rotating: boolean = false;
  private animationTimer: number = -1;
  private startTime: number = 0;

  aboutToAppear(): void {
    this.syncRotate();
  }

  aboutToDisappear(): void {
    this.stopRotate();
  }

  @Monitor('playerState.isPlaying')
  onPlayingChange(): void {
    this.syncRotate();
  }

  private syncRotate(): void {
    if (this.playerState.isPlaying) {
      this.startRotate();
    } else {
      this.stopRotate();
    }
  }

  private startRotate(): void {
    if (this.rotating) return;
    this.rotating = true;
    this.startTime = Date.now();
    const animate = () => {
      if (!this.rotating) return;
      const elapsed = Date.now() - this.startTime;
      this.coverAngle = (elapsed / 12000) * 360;
    };
    this.animationTimer = setInterval(animate, 16);
  }

  private stopRotate(): void {
    if (!this.rotating) return;
    this.rotating = false;
    if (this.animationTimer >= 0) {
      clearInterval(this.animationTimer);
      this.animationTimer = -1;
    }
    this.coverAngle = this.coverAngle % 360;
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
          .borderRadius(this.collapsed ? 28 : 20)
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.coverAngle })
          .id('mini-cover-img')
      } else if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('/')) {
        Image('file://' + this.playerState.currentBook.cover)
          .width('100%')
          .height('100%')
          .borderRadius(this.collapsed ? 28 : 20)
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.coverAngle })
          .id('mini-cover-img')
      } else if (this.playerState.currentBook.cover) {
        Image($rawfile(this.playerState.currentBook.cover))
          .width('100%')
          .height('100%')
          .borderRadius(this.collapsed ? 28 : 20)
          .objectFit(ImageFit.Cover)
          .rotate({ angle: this.coverAngle })
          .id('mini-cover-img')
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
          Stack() {
            this.coverImageBuilder()
          }
          .width(40)
          .height(40)
          .geometryTransition('mini-cover-' + this.bookId(), { follow: true })
          .onClick(() => this.onTapBody())

          Column({ space: 2 }) {
            Text(this.playerState.currentBook.title)
              .fontSize(AppFont.Body)
              .fontColor('#1F1F1F')
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.playerState.currentChapter ? this.playerState.currentChapter.title : '--')
              .fontSize(AppFont.Caption)
              .fontColor('#8F8F8F')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.onTapBody())

          SymbolGlyph(this.playerState.isPlaying
            ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(24)
            .fontColor(['#1F1F1F'])
            .hitTestBehavior(HitTestMode.Block)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onToggle())

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor(['#1F1F1F'])
            .hitTestBehavior(HitTestMode.Block)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => this.onNext())
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      }
    }
  }
}
