import { FrameCallback } from '@kit.ArkUI';

class PosterReadyFrame extends FrameCallback {
  private action: () => void;

  constructor(action: () => void) {
    super();
    this.action = action;
  }

  onFrame(): void { this.action(); }
}

/** 两层低分辨率封面同步交叉淡化，透明度直接作用于各自的绘制分组。 */
@ComponentV2
export struct RankingPosterBackground {
  @Param cover: string = '';
  @Param imageHeight: number = 656;
  @Param suspended: boolean = false;
  @Local first: string[] = [];
  @Local second: string[] = [];
  @Local firstOpacity: number = 0;
  @Local secondOpacity: number = 0;
  @Local frontSlot: number = 1;
  private currentSlot: number = 0;
  private currentCover: string = '';
  private pendingCover: string = '';
  private firstReady: string = '';
  private secondReady: string = '';
  private animating: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.updateCover();
  }

  aboutToDisappear(): void { this.alive = false; }

  @Monitor('cover', 'suspended')
  updateCover(): void {
    if (!this.alive || this.animating || this.suspended) return;
    if (this.cover === this.currentCover) return;
    this.pendingCover = this.cover;
    // 只替换完全透明的备用层；快速切换时直接加载最新目标。
    const images: string[] = this.cover.length > 0 && this.cover !== this.currentCover ? [this.cover] : [];
    if (this.currentSlot === 0) {
      if (this.secondReady !== this.cover) this.secondReady = '';
      this.second = images;
      if (this.cover.length > 0 && this.secondReady === this.cover) this.showReadyCover(this.cover, 1);
    } else {
      if (this.firstReady !== this.cover) this.firstReady = '';
      this.first = images;
      if (this.cover.length > 0 && this.firstReady === this.cover) this.showReadyCover(this.cover, 0);
    }
    if (this.cover.length === 0 && this.currentCover.length > 0) {
      this.showReadyCover('', 1 - this.currentSlot);
    }
  }

  private markReady(cover: string, slot: number): void {
    if (cover !== this.pendingCover) return;
    if (slot === 0) this.firstReady = cover;
    else this.secondReady = cover;
    this.showReadyCover(cover, slot);
  }

  private showReadyCover(cover: string, slot: number): void {
    if (!this.alive || this.animating || this.suspended || slot === this.currentSlot ||
      cover !== this.pendingCover || cover !== this.cover) return;
    this.animating = true;
    this.frontSlot = slot;
    // 解码回调早于纹理提交；让备用层先完成布局/绘制，再启动透明度动画。
    this.getUIContext().postFrameCallback(new PosterReadyFrame((): void => {
      if (!this.alive) return;
      this.getUIContext().postFrameCallback(new PosterReadyFrame((): void => {
        if (!this.alive) return;
        if (cover !== this.cover || this.suspended) {
          this.animating = false;
          this.updateCover();
          return;
        }
        this.fadeReadyCover(cover, slot);
      }));
    }));
  }

  private fadeReadyCover(cover: string, slot: number): void {
    // 固定容器绑定可观察状态，让 animateTo 捕获透明度起止值。
    // 图片加载和层级调整已在前两帧完成，不与渐入动画合并提交。
    this.getUIContext().animateTo({ duration: 1000, curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (!this.alive) return;
        this.currentSlot = slot;
        this.currentCover = cover;
        if (slot === 0) this.secondOpacity = 0;
        else this.firstOpacity = 0;
        this.animating = false;
        // 两层同时到达终值后，连续切牌接续最新封面。
        this.updateCover();
      }
    }, (): void => {
      if (cover.length === 0) {
        this.firstOpacity = 0;
        this.secondOpacity = 0;
      } else {
        this.firstOpacity = slot === 0 ? 1 : 0;
        this.secondOpacity = slot === 1 ? 1 : 0;
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.first, (cover: string) => {
          Image(cover).width('100%').height(this.imageHeight / 4)
            .objectFit(ImageFit.Cover).sourceSize({ width: 100, height: 140 }).blur(55 / 4)
            .onComplete((event) => {
              if (event?.loadingStatus === 1) this.markReady(cover, 0);
            })
        }, (cover: string): string => cover)
      }.width('25%').height(this.imageHeight / 4).renderGroup(true)
        .scale({ x: 4, y: 4, centerX: 0, centerY: 0 })
        .opacity(this.firstOpacity * 0.22).zIndex(this.frontSlot === 0 ? 1 : 0)
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.second, (cover: string) => {
          Image(cover).width('100%').height(this.imageHeight / 4)
            .objectFit(ImageFit.Cover).sourceSize({ width: 100, height: 140 }).blur(55 / 4)
            .onComplete((event) => {
              if (event?.loadingStatus === 1) this.markReady(cover, 1);
            })
        }, (cover: string): string => cover)
      }.width('25%').height(this.imageHeight / 4).renderGroup(true)
        .scale({ x: 4, y: 4, centerX: 0, centerY: 0 })
        .opacity(this.secondOpacity * 0.22).zIndex(this.frontSlot === 1 ? 1 : 0)
    }.width('100%').height(this.imageHeight)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
