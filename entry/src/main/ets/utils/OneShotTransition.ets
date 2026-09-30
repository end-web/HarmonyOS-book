import { componentUtils, FrameCallback, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { WindowUtils } from './WindowUtils';

/** Window-relative component bounds used by the advanced Navigation transition. */
export class OneShotRect {
  leftPx: number = 0;
  topPx: number = 0;
  widthPx: number = 0;
  heightPx: number = 0;

  static fromComponentInfo(info: componentUtils.ComponentInfo): OneShotRect {
    const rect = new OneShotRect();
    const scaleX = info.scale.x > 0 ? info.scale.x : 1;
    const scaleY = info.scale.y > 0 ? info.scale.y : 1;
    const scaleGapX = WindowUtils.vpToPx(info.scale.centerX) * (1 - scaleX);
    const scaleGapY = WindowUtils.vpToPx(info.scale.centerY) * (1 - scaleY);
    rect.leftPx = info.windowOffset.x + WindowUtils.vpToPx(info.translate.x) + scaleGapX;
    rect.topPx = info.windowOffset.y + WindowUtils.vpToPx(info.translate.y) + scaleGapY;
    rect.widthPx = info.size.width * scaleX;
    rect.heightPx = info.size.height * scaleY;
    return rect;
  }

  centerXPx(): number {
    return this.leftPx + this.widthPx / 2;
  }

  centerYPx(): number {
    return this.topPx + this.heightPx / 2;
  }

  isValid(): boolean {
    return this.widthPx > 1 && this.heightPx > 1;
  }
}

export class BookOneShotPayload {
  bookId: string = '';
  sourceNodeId: string = '';
  sourceRect: OneShotRect = new OneShotRect();
  viewportRect: OneShotRect = new OneShotRect();
  snapshot: image.PixelMap | undefined = undefined;
  createdAt: number = 0;
  sourceRadius: number = 12;

  static create(bookId: string, sourceNodeId: string, sourceRect: OneShotRect,
    viewportRect: OneShotRect, snapshot: image.PixelMap): BookOneShotPayload {
    const payload = new BookOneShotPayload();
    payload.bookId = bookId;
    payload.sourceNodeId = sourceNodeId;
    payload.sourceRect = sourceRect;
    payload.viewportRect = viewportRect;
    payload.snapshot = snapshot;
    payload.createdAt = Date.now();
    return payload;
  }
}

/** 在布局提交之后读取目标位置，避免零延时定时器读到上一帧布局。 */
export class OneShotLayoutCallback extends FrameCallback {
  private action: () => void;

  constructor(action: () => void) {
    super();
    this.action = action;
  }

  onFrame(_frameTimeInNano: number): void {
    this.action();
  }
}

@ObservedV2
export class OneShotCoverState {
  @Trace hiddenSourceId: string = '';
  @Trace detailBookId: string = '';
}

export type NavigationOneShotRunner =
  (isPush: boolean, transitionProxy: NavigationTransitionProxy) => void;

export class OneShotTransitionIds {
  private static sourceSeed: number = 0;

  static nextSourceId(prefix: string): string {
    OneShotTransitionIds.sourceSeed++;
    return prefix + '-' + OneShotTransitionIds.sourceSeed.toString();
  }

  static readonly ROOT_NAVIGATION: string = 'one-shot-root-navigation';
  static readonly DETAIL_SURFACE: string = 'one-shot-detail-surface';

  private static hashBookId(bookId: string): string {
    let hash: number = 17;
    for (let index = 0; index < bookId.length; index++) {
      hash = ((hash * 31) + bookId.charCodeAt(index)) & 0x7FFFFFFF;
    }
    return hash.toString(36);
  }

  static sourceCover(bookId: string): string {
    return 'one-shot-source-cover-' + OneShotTransitionIds.hashBookId(bookId);
  }

  static detailCover(bookId: string): string {
    return 'one-shot-detail-cover-' + OneShotTransitionIds.hashBookId(bookId);
  }
}

/**
 * Carries the clicked cover into the destination and exposes the destination's
 * transition runner to the root Navigation custom transition delegate.
 */
export class OneShotTransitionCoordinator {
  private static readonly MAX_PENDING_AGE_MS: number = 1500;
  private static readonly instance: OneShotTransitionCoordinator = new OneShotTransitionCoordinator();
  readonly coverState: OneShotCoverState = new OneShotCoverState();
  private pending: BookOneShotPayload | undefined = undefined;
  private captureGeneration: number = 0;
  private activeBookId: string = '';
  private activeRunner: NavigationOneShotRunner | undefined = undefined;
  private activeNavDestinationId: string = '';
  private activeDestinationIndex: number = -1;
  private pushReady: boolean = false;

  static getInstance(): OneShotTransitionCoordinator {
    return OneShotTransitionCoordinator.instance;
  }

  capture(uiContext: UIContext, bookId: string, nodeId: string, radius: number): void {
    try {
      const sourceRect = OneShotRect.fromComponentInfo(uiContext.getComponentUtils().getRectangleById(nodeId));
      const viewportRect = OneShotRect.fromComponentInfo(
        uiContext.getComponentUtils().getRectangleById(OneShotTransitionIds.ROOT_NAVIGATION));
      if (!sourceRect.isValid() || !viewportRect.isValid()) {
        this.discardPending();
        return;
      }
      const snapshot = uiContext.getComponentSnapshot().getSync(nodeId);
      const payload = BookOneShotPayload.create(bookId, nodeId, sourceRect, viewportRect, snapshot);
      payload.sourceRadius = radius;
      this.prepare(payload);
    } catch (_error) {
      this.discardPending();
    }
  }

  prepare(payload: BookOneShotPayload): void {
    this.releasePendingSnapshot();
    this.pending = payload;
  }

  async captureAsync(uiContext: UIContext, bookId: string, nodeId: string, radius: number): Promise<void> {
    this.discardPending();
    const generation = this.captureGeneration;
    try {
      const sourceRect = OneShotRect.fromComponentInfo(uiContext.getComponentUtils().getRectangleById(nodeId));
      const viewportRect = OneShotRect.fromComponentInfo(
        uiContext.getComponentUtils().getRectangleById(OneShotTransitionIds.ROOT_NAVIGATION));
      if (!sourceRect.isValid() || !viewportRect.isValid()) return;
      // 截图只服务于动效；GPU 忙时及时进入详情，迟到的像素图直接释放。
      await new Promise<void>((resolve: () => void): void => {
        let settled: boolean = false;
        const timer = setTimeout((): void => {
          settled = true;
          resolve();
        }, 160);
        uiContext.getComponentSnapshot().get(nodeId, {
          scale: Math.min(1, 600 / Math.max(sourceRect.widthPx, sourceRect.heightPx))
        }).then((snapshot: image.PixelMap): void => {
          if (settled || generation !== this.captureGeneration) {
            OneShotTransitionCoordinator.releaseSnapshot(snapshot);
          } else {
            const payload = BookOneShotPayload.create(bookId, nodeId, sourceRect, viewportRect, snapshot);
            payload.sourceRadius = radius;
            this.prepare(payload);
          }
          settled = true;
          clearTimeout(timer);
          resolve();
        }).catch((_error: Error): void => {
          settled = true;
          clearTimeout(timer);
          resolve();
        });
      });
    } catch (_error) {
      this.discardPending();
    }
  }

  claim(bookId: string): BookOneShotPayload | undefined {
    const payload = this.pending;
    if (payload === undefined) return undefined;
    this.pending = undefined;
    if (payload.bookId !== bookId || Date.now() - payload.createdAt > OneShotTransitionCoordinator.MAX_PENDING_AGE_MS) {
      OneShotTransitionCoordinator.releaseSnapshot(payload.snapshot);
      return undefined;
    }
    return payload;
  }

  discardPending(): void {
    this.captureGeneration++;
    this.releasePendingSnapshot();
    this.pending = undefined;
  }

  register(bookId: string, runner: NavigationOneShotRunner): void {
    this.activeBookId = bookId;
    this.coverState.detailBookId = bookId;
    this.activeRunner = runner;
    this.activeNavDestinationId = '';
    this.activeDestinationIndex = -1;
    this.pushReady = true;
  }

  unregister(bookId: string): void {
    if (this.activeBookId !== bookId) return;
    this.activeBookId = '';
    this.coverState.detailBookId = '';
    this.activeRunner = undefined;
    this.activeNavDestinationId = '';
    this.activeDestinationIndex = -1;
    this.pushReady = false;
  }

  canHandle(from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation): boolean {
    if (this.activeRunner === undefined) return false;
    if (operation === NavigationOperation.PUSH) return this.pushReady && to.name === 'detail';
    if (operation === NavigationOperation.POP) {
      if (from.name !== 'detail') return false;
      if (this.activeNavDestinationId.length > 0 && from.navDestinationId !== undefined) {
        return from.navDestinationId === this.activeNavDestinationId;
      }
      return from.index === this.activeDestinationIndex;
    }
    return false;
  }

  run(operation: NavigationOperation, from: NavContentInfo, to: NavContentInfo,
    transitionProxy: NavigationTransitionProxy): void {
    const runner = this.activeRunner;
    if (runner === undefined) {
      transitionProxy.finishTransition();
      return;
    }
    if (operation === NavigationOperation.PUSH) {
      this.pushReady = false;
      this.activeNavDestinationId = to.navDestinationId ?? '';
      this.activeDestinationIndex = to.index;
    }
    runner(operation === NavigationOperation.PUSH, transitionProxy);
  }

  private releasePendingSnapshot(): void {
    const payload = this.pending;
    if (payload !== undefined) OneShotTransitionCoordinator.releaseSnapshot(payload.snapshot);
  }

  static releaseSnapshot(snapshot: image.PixelMap | undefined): void {
    if (snapshot === undefined) return;
    snapshot.release().catch((_error: Error): void => {});
  }
}
