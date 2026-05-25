import { AppSpace, AppFont } from '../theme/Theme';
import { PlayerState } from '../model/PlayerState';

/**
 * 迷你栏内容（裸内容版）
 * - 折叠态：仅显示旋转封面圆，点击交给 HdsTabs 系统切换展开
 * - 展开态：完整长条（封面 + 标题 + 暂停 + 下一首），主体点击进播放页
 * - 不带背景/圆角/阴影/模糊：HdsTabs 的 miniBar 自身负责沉浸光感材质
 */
@ComponentV2
export struct MiniPlayer {
  @Param playerState: PlayerState = new PlayerState();
  @Param collapsed: boolean = true;
  @Event onTapBody: () => void = () => {};
  @Event onToggle: () => void = () => {};
  @Event onNext: () => void = () => {};

  @Local coverAngle: number = 0;
  private rotateTimer: number = -1;

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
    this.stopRotate();
    this.rotateTimer = setInterval(() => {
      this.coverAngle = (this.coverAngle + 2) % 360;
    }, 60);
  }

  private stopRotate(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
  }

  build() {
    if (this.playerState.currentBook) {
      if (this.collapsed) {
        // 折叠态:只展示旋转封面圆,点击交给系统(HdsTabs 会自动展开 miniBar)
        Stack() {
          Image($rawfile(this.playerState.currentBook.cover))
            .width('100%')
            .height('100%')
            .borderRadius(28)
            .objectFit(ImageFit.Cover)
            .rotate({ angle: this.coverAngle })
          Column()
            .width(14)
            .height(14)
            .borderRadius(7)
            .backgroundColor('#33000000')
            .border({ width: 1, color: '#55FFFFFF' })
        }
        .width('100%')
        .height('100%')
      } else {
        // 展开态:完整长条
        Row({ space: AppSpace.Sm }) {
          Stack() {
            Image($rawfile(this.playerState.currentBook.cover))
              .width(40)
              .height(40)
              .borderRadius(20)
              .objectFit(ImageFit.Cover)
              .rotate({ angle: this.coverAngle })
            Column()
              .width(12)
              .height(12)
              .borderRadius(6)
              .backgroundColor('#33000000')
              .border({ width: 1, color: '#55FFFFFF' })
          }
          .width(40)
          .height(40)
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
            .onClick(() => this.onToggle())

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor(['#1F1F1F'])
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.onNext())
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      }
    }
  }
}
