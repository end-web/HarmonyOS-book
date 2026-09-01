import { componentUtils } from '@kit.ArkUI';
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

export type NavigationOneShotRunner =
  (isPush: boolean, transitionProxy: NavigationTransitionProxy) => void;

export class OneShotTransitionIds {
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
  private pending: BookOneShotPayload | undefined = undefined;
  private activeBookId: string = '';
  private activeRunner: NavigationOneShotRunner | undefined = undefined;
  private activeNavDestinationId: string = '';
  private activeDestinationIndex: number = -1;
  private pushReady: boolean = false;

  static getInstance(): OneShotTransitionCoordinator {
    return OneShotTransitionCoordinator.instance;
  }

  prepare(payload: BookOneShotPayload): void {
    this.releasePendingSnapshot();
    this.pending = payload;
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
    this.releasePendingSnapshot();
    this.pending = undefined;
  }

  register(bookId: string, runner: NavigationOneShotRunner): void {
    this.activeBookId = bookId;
    this.activeRunner = runner;
    this.activeNavDestinationId = '';
    this.activeDestinationIndex = -1;
    this.pushReady = true;
  }

  unregister(bookId: string): void {
    if (this.activeBookId !== bookId) return;
    this.activeBookId = '';
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
