import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage, PlayerBackInterceptor, PlayerEntryDecider } from './PlayerPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';
import { GuidePage } from './GuidePage';
import { ImportPage } from './ImportPage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { UnfavoritedHistoryPage } from './UnfavoritedHistoryPage';
import { PrivacyPage } from './PrivacyPage';
import { BlockMorePage } from './BlockMorePage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { ReaderPage } from './ReaderPage';
import { ReaderKitVerifyPage } from './ReaderKitVerifyPage';
import { TextSourceVerifyPage } from './TextSourceVerifyPage';
import { SearchPage } from './SearchPage';
import { RuleSourcePage } from './RuleSourcePage';
import { RuleSourceAccountPage } from './RuleSourceAccountPage';
import { RuleSourceChildrenPage } from './RuleSourceChildrenPage';
import { RuleSourceLoginPage } from './RuleSourceLoginPage';
import { TextReaderRouteParams } from '../model/TextReading';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_WIDGET_ROUTE, KEY_WIDGET_ROUTE, WidgetRoute } from '../entryability/EntryAbility';
import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { AppRadius } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import {
  BookOneShotPayload,
  NavigationOneShotRunner,
  OneShotRect,
  OneShotTransitionCoordinator,
  OneShotTransitionIds
} from '../utils/OneShotTransition';

interface WidgetRouteEvent {
  target: string;
  bookId: string;
  ts?: number;
}

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local playerRenderGroup: boolean = false;
  @Local playerOpacity: number = 1;
  // detail 路由自定义转场:缩放淡入,无方向位移
  @Local detailScale: number = 1;
  @Local detailOpacity: number = 1;
  @Local searchRenderGroup: boolean = false;
  @Local searchOpacity: number = 1;
  @Local searchTranslateX: number = 0;
  private widgetSubscribed: boolean = false;
  /** 已消费过的路由 ts，避免冷启动时 AppStorage + emitter 两条路径同时触发同一个 push */
  private lastConsumedRouteTs: number = 0;

  aboutToAppear(): void {
    // 先 push home 作为栈底,再消费 widget 路由,保证栈不空
    this.navStack.pushPathByName('home', null, false);

    this.consumePendingWidgetRoute();
    if (!this.widgetSubscribed) {
      emitter.on(EVT_WIDGET_ROUTE, (data) => {
        const ev = data.data as WidgetRouteEvent | undefined;
        if (!ev) return;
        // 同一次卡片点击会走 AppStorage（冷启动） + emitter（热启动）两条路径，
        // 用 ts 去重，避免同一份 want 被压栈两次产生空白页 / 重叠 PlayerPage。
        const ts = ev.ts ?? 0;
        if (ts > 0 && ts === this.lastConsumedRouteTs) return;
        this.lastConsumedRouteTs = ts;
        this.handleWidgetRoute(ev.target, ev.bookId);
      });
      this.widgetSubscribed = true;
    }
  }

  aboutToDisappear(): void {
    if (this.widgetSubscribed) {
      try {
        emitter.off(EVT_WIDGET_ROUTE);
      } catch (_e) { /* ignore */ }
      this.widgetSubscribed = false;
    }
  }

  private resolveParam(param: object, key: string): string {
    if (typeof param === 'string') return '';
    const r = param as Record<string, Object>;
    const v = r[key];
    return typeof v === 'string' ? v : '';
  }

  /** EntryAbility.onCreate 写入路由后,Index 首次挂载时消费一次 */
  private consumePendingWidgetRoute(): void {
    const r = AppStorage.get<WidgetRoute>(KEY_WIDGET_ROUTE);
    if (!r) return;
    AppStorage.setOrCreate<WidgetRoute | undefined>(KEY_WIDGET_ROUTE, undefined);
    this.lastConsumedRouteTs = r.ts ?? 0;
    this.handleWidgetRoute(r.target, r.bookId ?? '');
  }

  private handleWidgetRoute(target: string, bookId: string): void {
    if (target === 'resume') {
      // 软拉起:对齐控制中心交互——只把应用拉到前台,
      // 用户停留在哪个页就保留哪个页,不强制跳到 PlayerPage。
      return;
    }
    if (target === 'player') {
      if (bookId && bookId.length > 0) {
        // 防止已经在播放页时又重复 push 一份空白的（widget 反复点击）
        const cur = this.navStack.getAllPathName();
        if (cur && cur.length > 0 && cur[cur.length - 1] === 'player') return;
        this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
          this.navStack.pushPathByName('player', bookId, false);
        });
      }
      // 无 bookId 时停在主页,避免黑屏
    } else if (target === 'detail') {
      if (bookId) this.navStack.pushPathByName('detail', bookId, false);
    } else if (target === 'downloads') {
      const cur = this.navStack.getAllPathName();
      if (cur && cur.length > 0 && cur[cur.length - 1] === 'downloads') return;
      this.navStack.pushPathByName('downloads', null, false);
    } else if (target === 'readerKitVerify') {
      const cur = this.navStack.getAllPathName();
      if (cur && cur.length > 0 && cur[cur.length - 1] === 'readerKitVerify') return;
      this.navStack.pushPathByName('readerKitVerify', null, false);
    }
    // target === 'home' 默认停在 Tab,不需要跳转
  }

  private oneShotNavigationTransition(from: NavContentInfo, to: NavContentInfo,
    operation: NavigationOperation): NavigationAnimatedTransition | undefined {
    const toName = to.name ?? '';
    const coordinator = OneShotTransitionCoordinator.getInstance();
    if (!coordinator.canHandle(from, to, operation)) {
      if (operation === NavigationOperation.PUSH && toName !== 'detail') coordinator.discardPending();
      return undefined;
    }
    const animatedTransition: NavigationAnimatedTransition = {
      timeout: 1800,
      onTransitionEnd: (success: boolean): void => {
        if (!success) console.warn('[Index] advanced one-shot transition did not finish successfully');
      },
      transition: (transitionProxy: NavigationTransitionProxy): void => {
        coordinator.run(operation, from, to, transitionProxy);
      }
    };
    return animatedTransition;
  }

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'home') {
      NavDestination() {
        MainPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.NONE)
      .onBackPressed((): boolean => {
        // 根页返回:移到后台而不是 pop,保证退出应用
        try {
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          ctx.moveAbilityToBackground();
          return true;
        } catch (e) {
          console.error(`[Index] moveAbilityToBackground error: ${e}`);
          return false;
        }
      })
    } else if (name === 'detail') {
      NavDestination() {
        DetailPageWrapper({ navStack: this.navStack, bookId: param as Object as string })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      // 关闭系统默认转场,用 customTransition 做缩放淡入,无位移方向感
      .systemTransition(NavigationSystemTransitionType.NONE)
      .scale({ x: this.detailScale, y: this.detailScale })
      .opacity(this.detailOpacity)
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        if (op === NavigationOperation.PUSH && isEnter) {
          // 进:从 0.94 放大到 1.0,透明度 0→1,减速曲线
          this.detailScale = 0.94;
          this.detailOpacity = 0;
          return [{
            duration: 320,
            curve: Curve.LinearOutSlowIn,
            event: () => {
              this.detailScale = 1;
              this.detailOpacity = 1;
            },
            onTransitionEnd: () => {}
          }];
        } else if (op === NavigationOperation.POP && !isEnter) {
          // 出:缩到 0.94 + 淡出,加速曲线(开始稍快)
          this.detailScale = 1;
          this.detailOpacity = 1;
          return [{
            duration: 240,
            curve: Curve.FastOutLinearIn,
            event: () => {
              this.detailScale = 0.94;
              this.detailOpacity = 0;
            },
            onTransitionEnd: () => {
              this.detailScale = 1;
              this.detailOpacity = 1;
            }
          }];
        }
        return undefined;
      })
    } else if (name === 'player') {
      NavDestination() {
        PlayerPageWrapper({ navStack: this.navStack, param: param as Object })
      }
      .hideTitleBar(true)
      // 关闭系统默认转场,让 customTransition 接管上滑(进)/下滑(返回)
      .systemTransition(NavigationSystemTransitionType.NONE)
      // 抽屉(章节/定时/跳过)打开时,右滑/返回先关抽屉而不是退整页
      .onBackPressed((): boolean => {
        if (PlayerBackInterceptor.consume()) return true;
        PlayerEntryDecider.markLeaving();
        this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutLinearIn }, () => {
          this.navStack.pop(false);
        });
        return true;
      })
      .backgroundColor('#000000')
      .renderGroup(this.playerRenderGroup)
      .opacity(this.playerOpacity)
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        if (op === NavigationOperation.PUSH && isEnter) {
          this.playerRenderGroup = true;
          this.playerOpacity = 0;
          return [{
            duration: 400,
            curve: Curve.FastOutSlowIn,
            event: () => {
              this.playerOpacity = 1;
            },
            onTransitionEnd: () => {
              this.playerRenderGroup = false;
              PlayerEntryDecider.markEntered();
            }
          }];
        } else if (op === NavigationOperation.POP && !isEnter) {
          // 出:淡出下滑。不启用 renderGroup——共享元素转场的"源"(播放页封面)若被离屏
          // 合成拍扁,框架无法从中抽取封面做回飞形变,会变成一卡一卡;
          // pop 时页面内容静止,直接合成即可,不依赖离屏缓冲。
          this.playerRenderGroup = false;
          this.playerOpacity = 1;
          return [{
            duration: 300,
            curve: Curve.FastOutLinearIn,
            event: () => {
              this.playerOpacity = 0;
            },
            onTransitionEnd: () => {
              this.playerOpacity = 1;
              this.playerRenderGroup = false;
            }
          }];
        }
        return undefined;
      })
    } else if (name === 'reader') {
      NavDestination() {
        ReaderPageWrapper({ navStack: this.navStack, param: param as Object })
      }
      .hideTitleBar(true)
      .backgroundColor('#F5F2EA')
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'search') {
      NavDestination() {
        SearchPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.NONE)
      .renderGroup(this.searchRenderGroup)
      .opacity(this.searchOpacity)
      .translate({ x: this.searchTranslateX })
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        if (op === NavigationOperation.PUSH && isEnter) {
          this.searchRenderGroup = true;
          this.searchOpacity = 0;
          this.searchTranslateX = 24;
          return [{
            duration: 220,
            curve: Curve.FastOutSlowIn,
            event: () => {
              this.searchOpacity = 1;
              this.searchTranslateX = 0;
            },
            onTransitionEnd: () => {
              this.searchRenderGroup = false;
            }
          }];
        } else if (op === NavigationOperation.POP && !isEnter) {
          this.searchRenderGroup = true;
          this.searchOpacity = 1;
          this.searchTranslateX = 0;
          return [{
            duration: 160,
            curve: Curve.FastOutLinearIn,
            event: () => {
              this.searchOpacity = 0;
              this.searchTranslateX = 24;
            },
            onTransitionEnd: () => {
              this.searchOpacity = 1;
              this.searchTranslateX = 0;
              this.searchRenderGroup = false;
            }
          }];
        }
        return undefined;
      })
    } else if (name === 'verifyTextSource') {
      NavDestination() {
        TextSourceVerifyPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'readerKitVerify') {
      NavDestination() {
        ReaderKitVerifyPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor('#F5F2EA')
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'settings') {
      NavDestination() {
        SettingsPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'ruleSources') {
      NavDestination() {
        RuleSourcePage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_secondary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'ruleSourceAccount') {
      NavDestination() {
        RuleSourceAccountPage({ navStack: this.navStack, sourceUrl: String(param) })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'ruleSourceChildren') {
      NavDestination() {
        RuleSourceChildrenPage({ navStack: this.navStack, sourceUrl: String(param) })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_secondary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'ruleSourceLogin') {
      NavDestination() {
        RuleSourceLoginPage({
          navStack: this.navStack,
          route: param instanceof RuleSourceLoginRouteParams ?
            param : new RuleSourceLoginRouteParams()
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'downloads') {
      NavDestination() {
        DownloadManagerPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_secondary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'about') {
      NavDestination() {
        AboutPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'guide') {
      NavDestination() {
        GuidePage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'import') {
      NavDestination() {
        ImportPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'stats') {
      NavDestination() {
        ReadingStatsPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'unfavoriteHistory') {
      NavDestination() {
        UnfavoritedHistoryPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'privacy') {
      NavDestination() {
        PrivacyPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'blockMore') {
      NavDestination() {
        BlockMorePageWrapper({ navStack: this.navStack, param: param as Object })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    }
  }

  build() {
    Navigation(this.navStack) {
      // home 已在 aboutToAppear 中 push,根内容留空
    }
    .backgroundColor('#000000')
    .navDestination(this.routerMap)
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo,
      operation: NavigationOperation): NavigationAnimatedTransition | undefined => {
      return this.oneShotNavigationTransition(from, to, operation);
    })
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .id(OneShotTransitionIds.ROOT_NAVIGATION)
  }
}

@ComponentV2
struct DetailPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';

  @Local detailSurfaceScale: number = 1;
  @Local detailSurfaceTranslateX: number = 0;
  @Local detailSurfaceTranslateY: number = 0;
  @Local detailSurfaceWidth: Dimension = '100%';
  @Local detailSurfaceHeight: Dimension = '100%';
  @Local detailSurfaceRadius: number = 0;
  @Local detailSurfaceOpacity: number = 1;
  @Local detailSurfaceClipEnabled: boolean = false;
  @Local transitionPreviewVisible: boolean = false;
  @Local transitionPreviewX: number = 0;
  @Local transitionPreviewY: number = 0;
  @Local transitionPreviewWidth: number = 0;
  @Local transitionPreviewHeight: number = 0;
  @Local transitionPreviewRadius: number = AppRadius.Md;
  @Local transitionPreviewOpacity: number = 1;

  private transitionPayload: BookOneShotPayload | undefined = undefined;
  private transitionSnapshot: image.PixelMap | undefined = undefined;
  private transitionRunning: boolean = false;
  private navigationRunner: NavigationOneShotRunner =
    (isPush: boolean, transitionProxy: NavigationTransitionProxy): void => {
      this.runNavigationTransition(isPush, transitionProxy);
    };

  aboutToAppear(): void {
    if (this.transitionPayload !== undefined) return;
    const payload = OneShotTransitionCoordinator.getInstance().claim(this.bookId);
    if (payload === undefined || payload.snapshot === undefined) return;
    this.transitionPayload = payload;
    this.transitionSnapshot = payload.snapshot;
    this.configureSurfaceStart(payload.sourceRect, payload.viewportRect);
    this.applyPreviewRect(payload.sourceRect, payload.viewportRect, AppRadius.Md);
    this.detailSurfaceOpacity = 0.08;
    this.detailSurfaceClipEnabled = true;
    this.transitionPreviewVisible = true;
    this.transitionPreviewOpacity = 1;
    OneShotTransitionCoordinator.getInstance().register(this.bookId, this.navigationRunner);
  }

  private configureSurfaceStart(sourceRect: OneShotRect, viewportRect: OneShotRect): void {
    const widthScale = sourceRect.widthPx / viewportRect.widthPx;
    const heightScale = sourceRect.heightPx / viewportRect.heightPx;
    const initialScale = Math.max(widthScale, heightScale);
    this.detailSurfaceScale = initialScale;
    this.detailSurfaceTranslateX = WindowUtils.pxToVp(sourceRect.centerXPx() - viewportRect.centerXPx());
    this.detailSurfaceTranslateY = WindowUtils.pxToVp(sourceRect.centerYPx() - viewportRect.centerYPx());
    if (widthScale >= heightScale) {
      this.detailSurfaceWidth = WindowUtils.pxToVp(viewportRect.widthPx);
      this.detailSurfaceHeight = WindowUtils.pxToVp(sourceRect.heightPx / initialScale);
    } else {
      this.detailSurfaceWidth = WindowUtils.pxToVp(sourceRect.widthPx / initialScale);
      this.detailSurfaceHeight = WindowUtils.pxToVp(viewportRect.heightPx);
    }
    this.detailSurfaceRadius = AppRadius.Md / initialScale;
    this.detailSurfaceClipEnabled = true;
  }

  private configureSurfaceEnd(opacityValue: number): void {
    this.detailSurfaceScale = 1;
    this.detailSurfaceTranslateX = 0;
    this.detailSurfaceTranslateY = 0;
    this.detailSurfaceWidth = '100%';
    this.detailSurfaceHeight = '100%';
    this.detailSurfaceRadius = 34;
    this.detailSurfaceOpacity = opacityValue;
    this.detailSurfaceClipEnabled = true;
  }

  private applyPreviewRect(rect: OneShotRect, viewportRect: OneShotRect, radius: number): void {
    this.transitionPreviewX = WindowUtils.pxToVp(rect.leftPx - viewportRect.leftPx);
    this.transitionPreviewY = WindowUtils.pxToVp(rect.topPx - viewportRect.topPx);
    this.transitionPreviewWidth = WindowUtils.pxToVp(rect.widthPx);
    this.transitionPreviewHeight = WindowUtils.pxToVp(rect.heightPx);
    this.transitionPreviewRadius = radius;
  }

  private measureRect(componentId: string): OneShotRect | undefined {
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(componentId);
      const rect = OneShotRect.fromComponentInfo(info);
      return rect.isValid() ? rect : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private viewportMatches(first: OneShotRect, second: OneShotRect): boolean {
    return Math.abs(first.widthPx - second.widthPx) < 2 &&
      Math.abs(first.heightPx - second.heightPx) < 2;
  }

  private rectIntersectsViewport(rect: OneShotRect, viewportRect: OneShotRect): boolean {
    const rectRight = rect.leftPx + rect.widthPx;
    const rectBottom = rect.topPx + rect.heightPx;
    const viewportRight = viewportRect.leftPx + viewportRect.widthPx;
    const viewportBottom = viewportRect.topPx + viewportRect.heightPx;
    return rectRight > viewportRect.leftPx && rect.leftPx < viewportRight &&
      rectBottom > viewportRect.topPx && rect.topPx < viewportBottom;
  }

  private runNavigationTransition(isPush: boolean, transitionProxy: NavigationTransitionProxy): void {
    if (this.transitionRunning) {
      transitionProxy.finishTransition();
      return;
    }
    this.transitionRunning = true;
    if (isPush) {
      this.preparePushTransition(transitionProxy);
    } else {
      this.preparePopTransition(transitionProxy);
    }
  }

  private preparePushTransition(transitionProxy: NavigationTransitionProxy): void {
    const payload = this.transitionPayload;
    if (payload === undefined) {
      this.finishFailedTransition(transitionProxy);
      return;
    }
    const viewportRect = this.measureRect(OneShotTransitionIds.ROOT_NAVIGATION) ?? payload.viewportRect;
    // Measure the destination at its final geometry while the surface remains invisible.
    this.configureSurfaceEnd(0);
    setTimeout((): void => {
      const targetRect = this.measureRect(OneShotTransitionIds.detailCover(this.bookId));
      if (targetRect === undefined) {
        this.finishFailedTransition(transitionProxy);
        return;
      }
      this.configureSurfaceStart(payload.sourceRect, viewportRect);
      this.applyPreviewRect(payload.sourceRect, viewportRect, AppRadius.Md);
      this.detailSurfaceOpacity = 0.08;
      this.transitionPreviewVisible = true;
      this.transitionPreviewOpacity = 1;
      setTimeout((): void => {
        this.animatePush(targetRect, viewportRect, transitionProxy);
      }, 0);
    }, 0);
  }

  private animatePush(targetRect: OneShotRect, viewportRect: OneShotRect,
    transitionProxy: NavigationTransitionProxy): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 328, 36),
      onFinish: (): void => {
        this.transitionRunning = false;
        this.transitionPreviewVisible = false;
        this.detailSurfaceClipEnabled = false;
        this.detailSurfaceRadius = 0;
        transitionProxy.finishTransition();
      }
    }, (): void => {
      this.configureSurfaceEnd(1);
      this.applyPreviewRect(targetRect, viewportRect, AppRadius.Sm);
    });
    this.getUIContext().animateTo({
      duration: 220,
      delay: 180,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.transitionPreviewOpacity = 0;
    });
  }

  private preparePopTransition(transitionProxy: NavigationTransitionProxy): void {
    const payload = this.transitionPayload;
    if (payload === undefined) {
      this.finishFailedTransition(transitionProxy);
      return;
    }
    const viewportRect = this.measureRect(OneShotTransitionIds.ROOT_NAVIGATION) ?? payload.viewportRect;
    if (!this.viewportMatches(payload.viewportRect, viewportRect)) {
      this.animateFallbackPop(transitionProxy);
      return;
    }
    const targetRect = this.measureRect(OneShotTransitionIds.detailCover(this.bookId));
    if (targetRect === undefined) {
      this.animateFallbackPop(transitionProxy);
      return;
    }
    const currentSourceRect = this.measureRect(payload.sourceNodeId);
    if (currentSourceRect === undefined || !this.rectIntersectsViewport(currentSourceRect, viewportRect)) {
      this.animateFallbackPop(transitionProxy);
      return;
    }
    this.configureSurfaceEnd(1);
    this.applyPreviewRect(targetRect, viewportRect, AppRadius.Sm);
    this.transitionPreviewVisible = true;
    this.transitionPreviewOpacity = 1;
    setTimeout((): void => {
      this.animatePop(currentSourceRect, viewportRect, transitionProxy);
    }, 0);
  }

  private animatePop(sourceRect: OneShotRect, viewportRect: OneShotRect,
    transitionProxy: NavigationTransitionProxy): void {
    this.getUIContext().animateTo({
      duration: 350,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        transitionProxy.finishTransition();
        this.finishReturnTransition();
      }
    }, (): void => {
      this.configureSurfaceStart(sourceRect, viewportRect);
      this.detailSurfaceOpacity = 0;
      this.applyPreviewRect(sourceRect, viewportRect, AppRadius.Md);
    });
  }

  private animateFallbackPop(transitionProxy: NavigationTransitionProxy): void {
    this.transitionPreviewVisible = false;
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.FastOutLinearIn,
      onFinish: (): void => {
        transitionProxy.finishTransition();
        this.finishReturnTransition();
      }
    }, (): void => {
      this.detailSurfaceOpacity = 0;
    });
  }

  private finishFailedTransition(transitionProxy: NavigationTransitionProxy): void {
    this.configureSurfaceEnd(1);
    this.detailSurfaceClipEnabled = false;
    this.detailSurfaceRadius = 0;
    this.transitionPreviewVisible = false;
    this.transitionRunning = false;
    transitionProxy.finishTransition();
    OneShotTransitionCoordinator.getInstance().unregister(this.bookId);
    this.releaseSnapshot();
  }

  private finishReturnTransition(): void {
    this.transitionRunning = false;
    this.transitionPreviewVisible = false;
    this.configureSurfaceEnd(1);
    this.detailSurfaceClipEnabled = false;
    this.detailSurfaceRadius = 0;
    OneShotTransitionCoordinator.getInstance().unregister(this.bookId);
    this.releaseSnapshot();
  }

  private releaseSnapshot(): void {
    const snapshot = this.transitionSnapshot;
    this.transitionSnapshot = undefined;
    OneShotTransitionCoordinator.releaseSnapshot(snapshot);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {
        BookDetailPage({ navStack: this.navStack, bookId: this.bookId })
      }
      .width(this.detailSurfaceWidth)
      .height(this.detailSurfaceHeight)
      .scale({ x: this.detailSurfaceScale, y: this.detailSurfaceScale })
      .translate({ x: this.detailSurfaceTranslateX, y: this.detailSurfaceTranslateY })
      .borderRadius(this.detailSurfaceRadius)
      .clip(this.detailSurfaceClipEnabled)
      .opacity(this.detailSurfaceOpacity)
      .id(OneShotTransitionIds.DETAIL_SURFACE)

      if (this.transitionPreviewVisible && this.transitionSnapshot !== undefined) {
        Image(this.transitionSnapshot)
          .width(this.transitionPreviewWidth)
          .height(this.transitionPreviewHeight)
          .position({ x: this.transitionPreviewX, y: this.transitionPreviewY })
          .borderRadius(this.transitionPreviewRadius)
          .clip(true)
          .objectFit(ImageFit.Cover)
          .opacity(this.transitionPreviewOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}

@ComponentV2
struct PlayerPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = '';

  private resolveBookId(): string {
    if (typeof this.param === 'string') return this.param as string;
    const r = this.param as Record<string, Object>;
    return (r['bookId'] as string) ?? '';
  }

  private resolveChapterId(): string {
    if (typeof this.param === 'string') return '';
    const r = this.param as Record<string, Object>;
    return (r['chapterId'] as string) ?? '';
  }

  private resolveProgressMs(): number {
    if (typeof this.param === 'string') return 0;
    const r = this.param as Record<string, Object>;
    const v = r['progressMs'];
    return typeof v === 'number' ? v : 0;
  }

  build() {
    PlayerPage({
      navStack: this.navStack,
      bookId: this.resolveBookId(),
      resumeChapterId: this.resolveChapterId(),
      resumeProgressMs: this.resolveProgressMs()
    })
  }
}

@ComponentV2
struct BlockMorePageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = '';

  private str(key: string): string {
    if (typeof this.param === 'string') return '';
    const r = this.param as Record<string, Object>;
    const v = r[key];
    return typeof v === 'string' ? v : '';
  }

  build() {
    BlockMorePage({
      navStack: this.navStack,
      sourceUrl: this.str('sourceUrl'),
      sourceName: this.str('sourceName'),
      title: this.str('title'),
      moreUrl: this.str('moreUrl')
    })
  }
}

@ComponentV2
struct ReaderPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = new TextReaderRouteParams();

  private resolveBookId(): string {
    if (this.param instanceof TextReaderRouteParams) return this.param.bookId;
    const value = this.param as Record<string, Object>;
    const bookId = value['bookId'];
    return typeof bookId === 'string' ? bookId : '';
  }

  private resolveResourceIndex(): number {
    if (this.param instanceof TextReaderRouteParams) return this.param.resourceIndex;
    const value = this.param as Record<string, Object>;
    const index = value['resourceIndex'];
    return typeof index === 'number' ? index : -1;
  }

  private resolveDomPos(): string {
    if (this.param instanceof TextReaderRouteParams) return this.param.domPos;
    const value = this.param as Record<string, Object>;
    const domPos = value['domPos'];
    return typeof domPos === 'string' ? domPos : '';
  }

  build() {
    ReaderPage({
      navStack: this.navStack,
      bookId: this.resolveBookId(),
      targetResourceIndex: this.resolveResourceIndex(),
      targetDomPos: this.resolveDomPos()
    })
  }
}
