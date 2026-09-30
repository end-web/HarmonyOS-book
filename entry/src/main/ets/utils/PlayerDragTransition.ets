import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { OneShotRect, OneShotTransitionIds, OneShotTransitionCoordinator } from './OneShotTransition';
import { WindowUtils } from './WindowUtils';

export class PlayerDragOrigin {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
  coverLeft: number = 0;
  coverTop: number = 0;
  coverWidth: number = 0;
  coverHeight: number = 0;
  viewportWidth: number = 0;
  viewportHeight: number = 0;
  viewportLeftPx: number = 0;
  viewportTopPx: number = 0;
  snapshot: image.PixelMap | undefined = undefined;
}

@ObservedV2
export class PlayerDragState {
  @Trace viewportWidth: number = 0;
  @Trace viewportHeight: number = 0;
  @Trace active: boolean = false;
  @Trace frameX: number = 0;
  @Trace frameY: number = 0;
  @Trace frameWidth: number = 0;
  @Trace frameHeight: number = 0;
  @Trace radius: number = 0;
  @Trace coverX: number = 0;
  @Trace coverY: number = 0;
  @Trace coverWidth: number = 0;
  @Trace coverHeight: number = 0;
  @Trace coverRadius: number = 0;
  @Trace contentOpacity: number = 1;
  @Trace sourceOpacity: number = 1;
  @Trace snapshot: image.PixelMap | undefined = undefined;
}

/** 只协调迷你栏上拖产生的 PUSH；完成/取消由 Navigation 原生交互式转场处理。 */
export class PlayerDragTransition {
  private static readonly instance: PlayerDragTransition = new PlayerDragTransition();
  readonly state: PlayerDragState = new PlayerDragState();
  private proxy: NavigationTransitionProxy | undefined = undefined;
  private distance: number = 1;
  private progress: number = 0;
  private decision: boolean | undefined = undefined;
  private settling: boolean = false;

  static getInstance(): PlayerDragTransition {
    return PlayerDragTransition.instance;
  }

  static measure(uiContext: UIContext, id: string): OneShotRect {
    const rect = OneShotRect.fromComponentInfo(uiContext.getComponentUtils().getRectangleById(id));
    // HDS 浮动栏通过祖先节点位移定位，windowOffset 不包含这部分绘制变换。
    const node = uiContext.getFrameNodeById(id);
    if (node !== null) {
      const position = node.getPositionToWindowWithTransform();
      rect.leftPx = WindowUtils.vpToPx(Number(position.x));
      rect.topPx = WindowUtils.vpToPx(Number(position.y));
    }
    return rect;
  }

  capture(uiContext: UIContext): PlayerDragOrigin | undefined {
    try {
      const bar = PlayerDragTransition.measure(uiContext, 'mini-player-bar');
      const cover = PlayerDragTransition.measure(uiContext, 'mini-player-cover-image');
      const viewport = PlayerDragTransition.measure(uiContext, OneShotTransitionIds.ROOT_NAVIGATION);
      if (!bar.isValid() || !cover.isValid() || !viewport.isValid()) return undefined;
      const origin = new PlayerDragOrigin();
      origin.left = WindowUtils.pxToVp(bar.leftPx - viewport.leftPx);
      origin.top = WindowUtils.pxToVp(bar.topPx - viewport.topPx);
      origin.width = WindowUtils.pxToVp(bar.widthPx);
      origin.height = WindowUtils.pxToVp(bar.heightPx);
      origin.coverLeft = WindowUtils.pxToVp(cover.leftPx - viewport.leftPx);
      origin.coverTop = WindowUtils.pxToVp(cover.topPx - viewport.topPx);
      origin.coverWidth = WindowUtils.pxToVp(cover.widthPx);
      origin.coverHeight = WindowUtils.pxToVp(cover.heightPx);
      origin.viewportWidth = WindowUtils.pxToVp(viewport.widthPx);
      origin.viewportHeight = WindowUtils.pxToVp(viewport.heightPx);
      origin.viewportLeftPx = viewport.leftPx;
      origin.viewportTopPx = viewport.topPx;
      // 截取未被父容器圆形裁剪的图片，放大时才能连续变成播放页圆角封面。
      origin.snapshot = uiContext.getComponentSnapshot().getSync('mini-player-cover-image');
      return origin;
    } catch (_error) {
      return undefined;
    }
  }

  begin(height: number, offsetY: number, origin: PlayerDragOrigin): boolean {
    if (this.state.active || height <= 0 || offsetY >= 0 || origin.width <= 0 || origin.height <= 0) {
      OneShotTransitionCoordinator.releaseSnapshot(origin.snapshot);
      return false;
    }
    this.distance = height;
    this.progress = Math.min(1, Math.max(0, -offsetY / height));
    this.decision = undefined;
    this.settling = false;
    this.proxy = undefined;
    this.state.viewportWidth = origin.viewportWidth;
    this.state.viewportHeight = origin.viewportHeight;
    this.state.frameX = origin.left;
    this.state.frameY = origin.top;
    this.state.frameWidth = origin.width;
    this.state.frameHeight = origin.height;
    this.state.radius = origin.height / 2;
    this.state.coverX = origin.coverLeft;
    this.state.coverY = origin.coverTop;
    this.state.coverWidth = origin.coverWidth;
    this.state.coverHeight = origin.coverHeight;
    this.state.coverRadius = Math.min(origin.coverWidth, origin.coverHeight) / 2;
    this.state.snapshot = origin.snapshot;
    this.state.contentOpacity = 0;
    this.state.sourceOpacity = 1;
    this.state.active = true;
    return true;
  }

  expandToPlayer(cover: OneShotRect, viewport: OneShotRect): void {
    this.state.frameX = 0;
    this.state.frameY = 0;
    this.state.frameWidth = WindowUtils.pxToVp(viewport.widthPx);
    this.state.frameHeight = WindowUtils.pxToVp(viewport.heightPx);
    this.state.radius = 0;
    this.state.coverX = WindowUtils.pxToVp(cover.leftPx - viewport.leftPx);
    this.state.coverY = WindowUtils.pxToVp(cover.topPx - viewport.topPx);
    this.state.coverWidth = WindowUtils.pxToVp(cover.widthPx);
    this.state.coverHeight = WindowUtils.pxToVp(cover.heightPx);
    this.state.coverRadius = 16;
  }

  attach(proxy: NavigationTransitionProxy): void {
    if (!this.state.active) return;
    this.proxy = proxy;
    proxy.updateTransition?.(this.progress);
    this.settle();
  }

  update(offsetY: number): void {
    if (!this.state.active || this.decision !== undefined) return;
    this.progress = Math.min(1, Math.max(0, -offsetY / this.distance));
    this.proxy?.updateTransition?.(this.progress);
  }

  end(offsetY: number, velocityY: number): void {
    if (!this.state.active || this.decision !== undefined) return;
    this.update(offsetY);
    // 长拖或明确的向上甩动展开；往回拖/向下甩则取消，手抖不误打开。
    this.decision = velocityY < 650 &&
      (this.progress >= 0.18 || (offsetY <= -24 && velocityY <= -900));
    this.settle();
  }

  cancel(): boolean {
    if (!this.state.active) return false;
    if (!this.settling) {
      this.decision = false;
      this.settle();
    }
    return true;
  }

  private settle(): void {
    if (this.proxy === undefined || this.decision === undefined || this.settling) return;
    this.settling = true;
    if (this.decision) this.proxy.finishTransition();
    else this.proxy.cancelTransition?.();
  }

  complete(): void {
    this.proxy = undefined;
    this.decision = undefined;
    this.settling = false;
    this.progress = 0;
    this.state.active = false;
    this.state.contentOpacity = 1;
    this.state.sourceOpacity = 1;
    const snapshot = this.state.snapshot;
    this.state.snapshot = undefined;
    OneShotTransitionCoordinator.releaseSnapshot(snapshot);
  }
}
