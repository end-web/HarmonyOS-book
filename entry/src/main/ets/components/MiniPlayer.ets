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

  aboutToAppear(): void {
    this.syncRotate();
  }

  aboutToDisappear(): void {
    this.rotating = false;
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
    this.tickRotate();
  }

  private tickRotate(): void {
    if (!this.rotating) return;
    this.getUIContext().animateTo({
      duration: 12000,
      curve: Curve.Linear,
      onFinish: () => { this.tickRotate(); }
    }, () => {
      this.coverAngle = this.coverAngle + 360;
    });
  }

  private stopRotate(): void {
    if (!this.rotating) return;
    this.rotating = false;
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.coverAngle = this.coverAngle % 360;
    });
  }

  private bookId(): string {
    return this.playerState.currentBook ? this.playerState.currentBook.id : '';
  }

  build() {
    if (this.playerState.currentBook) {
      if (this.collapsed) {
        Stack() {
          if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('http')) {
            Image(this.playerState.currentBook.cover)
              .width('100%')
              .height('100%')
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
              .rotate({ angle: this.coverAngle })
          } else if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('/')) {
            Image('file://' + this.playerState.currentBook.cover)
              .width('100%')
              .height('100%')
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
              .rotate({ angle: this.coverAngle })
          } else if (this.playerState.currentBook.cover) {
            Image($rawfile(this.playerState.currentBook.cover))
              .width('100%')
              .height('100%')
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
              .rotate({ angle: this.coverAngle })
          }
          Stack() {
            SymbolGlyph(this.playerState.isPlaying
              ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
          }
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor('#66000000')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.onToggle();
            this.onExpand();
          })
        }
        .width('100%')
        .height('100%')
      } else {
        Row({ space: AppSpace.Sm }) {
          Stack() {
            if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('http')) {
              Image(this.playerState.currentBook.cover)
                .width(40)
                .height(40)
                .borderRadius(20)
                .objectFit(ImageFit.Cover)
                .rotate({ angle: this.coverAngle })
            } else if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('/')) {
              Image('file://' + this.playerState.currentBook.cover)
                .width(40)
                .height(40)
                .borderRadius(20)
                .objectFit(ImageFit.Cover)
                .rotate({ angle: this.coverAngle })
            } else if (this.playerState.currentBook.cover) {
              Image($rawfile(this.playerState.currentBook.cover))
                .width(40)
                .height(40)
                .borderRadius(20)
                .objectFit(ImageFit.Cover)
                .rotate({ angle: this.coverAngle })
            }
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
