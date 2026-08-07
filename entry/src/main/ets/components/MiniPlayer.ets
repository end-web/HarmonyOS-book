import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
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
  @Local coverRotationAngle: number = 0;

  private coverAnimator: AnimatorResult | null = null;
  private coverAnimatorPlaying: boolean = false;

  aboutToAppear(): void {
    this.initCoverAnimator();
  }

  aboutToDisappear(): void {
    this.disposeCoverAnimator();
  }

  @Monitor('playerState.isPlaying')
  private onPlayingStateChanged(_monitor: IMonitor): void {
    this.syncCoverAnimator();
  }

  private initCoverAnimator(): void {
    if (this.coverAnimator !== null) return;
    const startAngle: number = this.coverRotationAngle;
    const options: AnimatorOptions = {
      duration: 20000,
      easing: 'linear',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: -1,
      begin: startAngle,
      end: startAngle + 360
    };
    const animator: AnimatorResult = this.getUIContext().createAnimator(options);
    animator.onFrame = (angle: number): void => {
      this.coverRotationAngle = angle;
    };
    this.coverAnimator = animator;
    this.syncCoverAnimator();
  }

  private syncCoverAnimator(): void {
    const animator = this.coverAnimator;
    if (animator === null) return;
    if (this.playerState.isPlaying) {
      if (!this.coverAnimatorPlaying) {
        animator.play();
        this.coverAnimatorPlaying = true;
      }
      return;
    }
    if (this.coverAnimatorPlaying) {
      animator.pause();
      this.coverAnimatorPlaying = false;
    }
  }

  private disposeCoverAnimator(): void {
    if (this.coverAnimator === null) return;
    this.coverAnimator.cancel();
    this.coverAnimator = null;
    this.coverAnimatorPlaying = false;
  }

  @Builder
  coverImageBuilder(): void {
    if (this.playerState.currentBook) {
      if (this.playerState.currentBook.cover && this.playerState.currentBook.cover.startsWith('http')) {
        Image(this.playerState.currentBook.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .sourceSize({ width: 300, height: 400 })
          .id('mini-cover-img')
      } else if (this.playerState.currentBook.cover
        && (this.playerState.currentBook.cover.startsWith('/') || this.playerState.currentBook.cover.startsWith('file://'))) {
        // 判断条件与 BookCard.isLocalFile 对齐:file:// 前缀的本地封面不能掉进 $rawfile 分支
        Image('file://' + this.playerState.currentBook.cover.replace(/^file:\/\//, ''))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .sourceSize({ width: 300, height: 400 })
          .id('mini-cover-img-file')
      } else if (this.playerState.currentBook.cover) {
        // rawfile 分支不设 sourceSize:列表(BookCard/FavoritePage)的 rawfile 分支也没设,保持缓存一致
        Image($rawfile(this.playerState.currentBook.cover))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .id('mini-cover-img-raw')
      } else {
        // 无封面:用 app 图标占位(替代旧的绿色书形占位)
        Image($r('app.media.app_icon_legacy'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .id('mini-cover-img-fallback')
      }
    }
  }

  build() {
    if (this.playerState.currentBook) {
      Row({ space: this.collapsed ? 0 : AppSpace.Sm }) {
        Stack() {
          Stack() {
            this.coverImageBuilder()
          }
          .width('100%')
          .height('100%')
          .borderRadius(this.collapsed ? 999 : 22)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .clip(true)
          .rotate({ angle: this.coverRotationAngle })
        }
        .width(this.collapsed ? '100%' : 44)
        .height(this.collapsed ? '100%' : 44)
        .geometryTransition('player-cover')
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .onClick(() => {
          if (this.collapsed) {
            this.onExpand();
          } else {
            this.onTapBody();
          }
        })

        if (!this.collapsed) {
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
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.collapsed ? 0 : AppSpace.Xs,
        right: this.collapsed ? 0 : AppSpace.Md
      })
    }
  }
}
