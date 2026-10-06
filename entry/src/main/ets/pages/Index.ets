import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { MainPage } from './MainPage';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage, PlayerBackInterceptor, PlayerEntryDecider } from './PlayerPage';
import { SettingsPage } from './SettingsPage';
import { MembershipPage } from './MembershipPage';
import { AboutPage } from './AboutPage';
import { TechnicalSupportPage } from './TechnicalSupportPage';
import { AccountPage } from './AccountPage';
import { AchievementPage } from './AchievementPage';
import { GuidePage } from './GuidePage';
import { ImportPage } from './ImportPage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { SessionHistoryPage } from './SessionHistoryPage';
import { UnfavoritedHistoryPage } from './UnfavoritedHistoryPage';
import { PrivacyPage } from './PrivacyPage';
import { CompliancePage } from './CompliancePage';
import { OpenSourcePage } from './OpenSourcePage';
import { BlockMorePage } from './BlockMorePage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { LogManagementPage } from './LogManagementPage';
import { ReaderPage } from './ReaderPage';
// import { ReaderKitVerifyPage } from './ReaderKitVerifyPage';
import { SearchPage } from './SearchPage';
import { RuleSourcePage } from './RuleSourcePage';
import { RuleSourceAccountPage } from './RuleSourceAccountPage';
import { RuleSourceChildrenPage } from './RuleSourceChildrenPage';
import { RuleSourceLoginPage } from './RuleSourceLoginPage';
import { RuleSourceEditPage } from './RuleSourceEditPage';
import { RuleSourceDebugPage } from './RuleSourceDebugPage';
import { RuleSourcePanelPage } from './RuleSourcePanelPage';
import { TextReaderRouteParams } from '../model/TextReading';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleBrowserLoginCoordinator } from '../service/rulesource/LocalRuleBrowserLoginCoordinator';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_WIDGET_ROUTE, KEY_WIDGET_ROUTE, WidgetRoute } from '../entryability/EntryAbility';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppRadius } from '../theme/Theme';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { WindowUtils } from '../utils/WindowUtils';
import { PlatformCompat } from '../utils/PlatformCompat';
import { LocalImportRouteParams } from '../utils/FileOpenRouting';
import {
  BookOneShotPayload,
  NavigationOneShotRunner,
  OneShotLayoutCallback,
  OneShotRect,
  OneShotTransitionCoordinator,
  OneShotTransitionIds
} from '../utils/OneShotTransition';

interface WidgetRouteEvent {
  target: string;
  bookId: string;
  fileType?: string;
  ts?: number;
}

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local playerRenderGroup: boolean = false;
  @Local playerOpacity: number = 1;
  @Local playerDragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local navigationEnabled: boolean = true;
  @Local detailOpacity: number = 1;
  private widgetSubscribed: boolean = false;
  private homeBackHandler: (() => boolean) | undefined = undefined;
  private homeShownHandler: (() => void) | undefined = undefined;
  /** 已消费过的路由 ts，避免冷启动时 AppStorage + emitter 两条路径同时触发同一个 push */
  private lastConsumedRouteTs: number = 0;
  private browserLoginOpener: (route: RuleSourceLoginRouteParams) => void = (route: RuleSourceLoginRouteParams): void => {
    this.navStack.pushPathByName('ruleSourceLogin', route);
  };

  aboutToAppear(): void {
    // 先 push home 作为栈底,再消费 widget 路由,保证栈不空
    this.navStack.pushPathByName('home', null, false);
    LocalRuleBrowserLoginCoordinator.bindNavigation(this.browserLoginOpener);

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
        AppStorage.setOrCreate<WidgetRoute | undefined>(KEY_WIDGET_ROUTE, undefined);
        this.handleWidgetRoute(ev.target, ev.bookId, ev.fileType ?? '');
      });
      this.widgetSubscribed = true;
    }
  }

  aboutToDisappear(): void {
    LocalRuleBrowserLoginCoordinator.unbindNavigation(this.browserLoginOpener);
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

  private syncReaderWindowMode(): void {
    // onHidden 也会在退后台触发；阅读路由仍在栈顶时保留系统栏和安全区。
    const paths: string[] = this.navStack.getAllPathName();
    WindowUtils.setReaderActive(paths.length > 0 && paths[paths.length - 1] === 'reader');
  }

  /** EntryAbility.onCreate 写入路由后,Index 首次挂载时消费一次 */
  private consumePendingWidgetRoute(): void {
    const r = AppStorage.get<WidgetRoute>(KEY_WIDGET_ROUTE);
    if (!r) return;
    AppStorage.setOrCreate<WidgetRoute | undefined>(KEY_WIDGET_ROUTE, undefined);
    this.lastConsumedRouteTs = r.ts ?? 0;
    this.handleWidgetRoute(r.target, r.bookId ?? '', r.fileType ?? '');
  }

  private handleWidgetRoute(target: string, bookId: string, fileType: string = ''): void {
    if (target === 'localBookImport') {
      this.navStack.pushPathByName('import', new LocalImportRouteParams(bookId, fileType), false);
      return;
    }
    if (target === 'ruleSourceImport') {
      this.navStack.pushPathByName('ruleSources', bookId, false);
      return;
    }
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
    if (operation === NavigationOperation.PUSH && to.name === 'player' && this.playerDragState.active) {
      const drag = PlayerDragTransition.getInstance();
      const animation: NavigationAnimatedTransition = {
        isInteractive: true,
        transition: (proxy: NavigationTransitionProxy): void => {
          // 原生记录终态动画；进度由 MiniPlayer 的 PanGesture 驱动，不禁用源手势。
          this.playerOpacity = 1;
          this.playerRenderGroup = false;
          const viewport = PlayerDragTransition.measure(this.getUIContext(), 'player-drag-surface');
          const cover = PlayerDragTransition.measure(this.getUIContext(), 'player-page-cover');
          // 整个播放页从迷你栏的实际矩形/圆角展开，封面独立对齐播放页封面。
          this.getUIContext().animateTo({ duration: 360, curve: Curve.Linear }, (): void => {
            drag.expandToPlayer(cover, viewport);
          });
          this.getUIContext().animateTo({ duration: 160, curve: Curve.Linear }, (): void => {
            this.playerDragState.contentOpacity = 1;
          });
          this.getUIContext().animateTo({ duration: 80, curve: Curve.Linear }, (): void => {
            this.playerDragState.sourceOpacity = 0;
          });
          this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => drag.attach(proxy)));
        },
        onTransitionEnd: (success: boolean): void => {
          drag.complete();
          if (success) PlayerEntryDecider.markEntered();
          else PlayerEntryDecider.markLeaving();
        }
      };
      return animation;
    }
    const toName = to.name ?? '';
    const coordinator = OneShotTransitionCoordinator.getInstance();
    if (!coordinator.canHandle(from, to, operation)) {
      if (operation === NavigationOperation.PUSH && toName !== 'detail') coordinator.discardPending();
      return undefined;
    }
    const animatedTransition: NavigationAnimatedTransition = {
      timeout: 2400,
      onTransitionEnd: (success: boolean): void => {
        this.navigationEnabled = true;
        if (!success) console.warn('[Index] advanced one-shot transition did not finish successfully');
      },
      transition: (transitionProxy: NavigationTransitionProxy): void => {
        this.navigationEnabled = false;
        coordinator.run(operation, from, to, transitionProxy);
      }
    };
    return animatedTransition;
  }

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'home') {
      NavDestination() {
        MainPage({
          navStack: this.navStack,
          onHomeShownHandlerChange: (handler: (() => void) | undefined): void => {
            this.homeShownHandler = handler;
          },
          onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
            this.homeBackHandler = handler;
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.NONE)
      .onShown((): void => { this.homeShownHandler?.(); })
      .onBackPressed((): boolean => {
        if (this.homeBackHandler?.()) return true;
        if (PlatformCompat.desktopWindow) {
          WindowUtils.minimize();
          return true;
        }
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
        DetailPageWrapper({
          navStack: this.navStack,
          bookId: param as Object as string,
          onTransitionFinished: (): void => { this.navigationEnabled = true; }
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      // 封面转场由根 Navigation 接管；其他入口仅淡入淡出。
      .systemTransition(NavigationSystemTransitionType.NONE)
      .opacity(this.detailOpacity)
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        if (op === NavigationOperation.PUSH && isEnter) {
          // 无可用封面时保留轻量淡入。
          this.detailOpacity = 0;
          return [{
            duration: 320,
            curve: Curve.LinearOutSlowIn,
            event: () => {
              this.detailOpacity = 1;
            },
            onTransitionEnd: () => {}
          }];
        } else if (op === NavigationOperation.POP && !isEnter) {
          // 无可用封面时淡出返回。
          this.detailOpacity = 1;
          return [{
            duration: 240,
            curve: Curve.FastOutLinearIn,
            event: () => {
              this.detailOpacity = 0;
            },
            onTransitionEnd: () => {
              this.detailOpacity = 1;
            }
          }];
        }
        return undefined;
      })
    } else if (name === 'player') {
      NavDestination() {
        PlayerPageWrapper({ navStack: this.navStack, param: param as Object, deferEntry: this.playerDragState.active })
      }
      .hideTitleBar(true)
      // 关闭系统默认转场,让 customTransition 接管上滑(进)/下滑(返回)
      .systemTransition(NavigationSystemTransitionType.NONE)
      // 抽屉(章节/定时/跳过)打开时,右滑/返回先关抽屉而不是退整页
      .onBackPressed((): boolean => {
        if (PlayerDragTransition.getInstance().cancel()) return true;
        if (PlayerBackInterceptor.consume()) return true;
        PlayerEntryDecider.markLeaving();
        this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutLinearIn }, () => {
          this.navStack.pop(false);
        });
        return true;
      })
      .backgroundColor(this.playerDragState.active ? Color.Transparent : '#000000')
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
      .onShown((): void => this.syncReaderWindowMode())
      .onHidden((): void => this.syncReaderWindowMode())
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'search') {
      SearchPage({ navStack: this.navStack })
    } else if (name === 'readerKitVerify') {
      // 华为 ReaderKit 验证页面已禁用（需要 HMS Core ReaderService 依赖）
      NavDestination() {
        Column() {
          Text('ReaderKit 验证功能暂时禁用')
            .fontSize(16)
            .fontColor('#999999')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .hideTitleBar(true)
      .backgroundColor('#F5F2EA')
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'achievements') {
      AchievementPage({ navStack: this.navStack })
    } else if (name === 'account') {
      AccountPage({ navStack: this.navStack })
    } else if (name === 'settings') {
      ProfileMenuDestination() {
        SettingsPage({ navStack: this.navStack })
      }
    } else if (name === 'membership' || name === 'membershipSubscription') {
      ProfileMenuDestination() {
        MembershipPage({ navStack: this.navStack })
      }
    } else if (name === 'ruleSources') {
      // RuleSourcePage 自带 ProfileMenuDestination：页内多级视图需拦截侧滑返回
      RuleSourcePage({ navStack: this.navStack, importFileUri: typeof param === 'string' ? param : '' })
    } else if (name === 'ruleSourceAccount') {
      ProfileMenuDestination() {
        RuleSourceAccountPage({ navStack: this.navStack, sourceUrl: String(param) })
      }
    } else if (name === 'ruleSourceChildren') {
      ProfileMenuDestination({ pageBackground: $r('sys.color.background_secondary') }) {
        RuleSourceChildrenPage({ navStack: this.navStack, sourceUrl: String(param) })
      }
    } else if (name === 'ruleSourceLogin') {
      ProfileMenuDestination() {
        RuleSourceLoginPage({
          navStack: this.navStack,
          route: param instanceof RuleSourceLoginRouteParams ?
            param : new RuleSourceLoginRouteParams()
        })
      }
    } else if (name === 'RuleSourceEditPage') {
      RuleSourceEditPage({
        navStack: this.navStack,
        sourceUrl: param ? String((param as Record<string, string>).sourceUrl) : ''
      })
    } else if (name === 'RuleSourceDebugPage') {
      RuleSourceDebugPage({
        navStack: this.navStack,
        sourceUrl: param ? String((param as Record<string, string>).sourceUrl) : ''
      })
    } else if (name === 'ruleSourceExplore' || name === 'ruleSourceLoginPanel') {
      RuleSourcePanelPage({ navStack: this.navStack, sourceUrl: String(param), login: name === 'ruleSourceLoginPanel' })
    } else if (name === 'logs') {
      ProfileMenuDestination() {
        LogManagementPage({ navStack: this.navStack })
      }
    } else if (name === 'downloads') {
      ProfileMenuDestination({ pageBackground: $r('sys.color.background_secondary') }) {
        DownloadManagerPage({ navStack: this.navStack })
      }
    } else if (name === 'about') {
      ProfileMenuDestination() {
        AboutPage({ navStack: this.navStack })
      }
    } else if (name === 'technicalSupport') {
      ProfileMenuDestination() {
        TechnicalSupportPage({ navStack: this.navStack })
      }
    } else if (name === 'guide') {
      ProfileMenuDestination() {
        GuidePage({ navStack: this.navStack })
      }
    } else if (name === 'import') {
      ProfileMenuDestination() {
        ImportPage({
          navStack: this.navStack,
          importFileUri: param ? this.resolveParam(param, 'uri') : '',
          importFileType: param ? this.resolveParam(param, 'fileType') : ''
        })
      }
    } else if (name === 'stats') {
      NavDestination() {
        ReadingStatsPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'sessionHistory') {
      NavDestination() {
        SessionHistoryPage({ navStack: this.navStack, bookIds: this.resolveParam(param, 'bookIds') })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'unfavoriteHistory') {
      NavDestination() {
        UnfavoritedHistoryPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'privacy') {
      ProfileMenuDestination() {
        PrivacyPage({ navStack: this.navStack })
      }
    } else if (name === 'compliance') {
      ProfileMenuDestination() {
        CompliancePage({ navStack: this.navStack })
      }
    } else if (name === 'openSource') {
      ProfileMenuDestination() {
        OpenSourcePage({ navStack: this.navStack })
      }
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
    .enabled(this.navigationEnabled)
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
  @Event onTransitionFinished: () => void = () => {};
  @Local detailOpacity: number = 1;
  @Local coverHidden: boolean = false;
  @Local previewVisible: boolean = false;
  @Local previewX: number = 0;
  @Local previewY: number = 0;
  @Local previewWidth: number = 0;
  @Local previewHeight: number = 0;
  @Local previewBaseWidth: number = 1;
  @Local previewBaseHeight: number = 1;
  @Local previewRadius: number = AppRadius.Md;
  @Local previewOpacity: number = 1;
  @Local entryReady: boolean = true;

  private payload: BookOneShotPayload | undefined = undefined;
  private snapshot: image.PixelMap | undefined = undefined;
  private running: boolean = false;
  private disposed: boolean = false;
  private watchdog: number = -1;
  private coverWaitTimer: number = -1;
  private coverReady: boolean = false;
  private waitingForCover: boolean = false;
  private coverHandoffProxy: NavigationTransitionProxy | undefined = undefined;
  private navigationRunner: NavigationOneShotRunner =
    (isPush: boolean, proxy: NavigationTransitionProxy): void => this.runTransition(isPush, proxy);

  aboutToAppear(): void {
    const payload = OneShotTransitionCoordinator.getInstance().claim(this.bookId);
    if (payload === undefined || payload.snapshot === undefined) return;
    this.payload = payload;
    this.entryReady = false;
    this.snapshot = payload.snapshot;
    this.detailOpacity = 0;
    this.coverHidden = true;
    this.previewVisible = false;
    this.applyRect(payload.sourceRect, payload.viewportRect, payload.sourceRadius);
    OneShotTransitionCoordinator.getInstance().register(this.bookId, this.navigationRunner);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.running = false;
    this.clearWatchdog();
    this.clearCoverWaitTimer();
    this.coverHandoffProxy = undefined;
    this.onTransitionFinished();
    this.restoreSource();
    OneShotTransitionCoordinator.getInstance().unregister(this.bookId);
    OneShotTransitionCoordinator.releaseSnapshot(this.snapshot);
    this.snapshot = undefined;
  }

  private clearWatchdog(): void {
    if (this.watchdog >= 0) clearTimeout(this.watchdog);
    this.watchdog = -1;
  }

  private clearCoverWaitTimer(): void {
    if (this.coverWaitTimer >= 0) clearTimeout(this.coverWaitTimer);
    this.coverWaitTimer = -1;
  }

  private onDetailCoverReady(_url: string): void {
    this.coverReady = true;
    if (this.waitingForCover) this.beginCoverHandoff();
  }

  private restoreSource(): void {
    const state = OneShotTransitionCoordinator.getInstance().coverState;
    if (state.hiddenSourceId === this.payload?.sourceNodeId) state.hiddenSourceId = '';
  }

  private measureRect(id: string): OneShotRect | undefined {
    try {
      const rect = OneShotRect.fromComponentInfo(this.getUIContext().getComponentUtils().getRectangleById(id));
      return rect.isValid() ? rect : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private applyRect(rect: OneShotRect, viewport: OneShotRect, radius: number): void {
    this.previewX = WindowUtils.pxToVp(rect.leftPx - viewport.leftPx);
    this.previewY = WindowUtils.pxToVp(rect.topPx - viewport.topPx);
    this.previewWidth = WindowUtils.pxToVp(rect.widthPx);
    this.previewHeight = WindowUtils.pxToVp(rect.heightPx);
    this.previewRadius = radius;
  }

  private afterLayout(action: () => void): void {
    // 用连续帧确认布局已提交，不等 onIdle：目录加载繁忙时可能连续多帧没有空闲时间。
    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
      if (this.disposed || !this.running) return;
      this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
        if (!this.disposed && this.running) action();
      }));
    }));
  }

  private finish(proxy: NavigationTransitionProxy, isPush: boolean): void {
    if (!this.running) return;
    this.running = false;
    this.clearWatchdog();
    this.clearCoverWaitTimer();
    this.waitingForCover = false;
    this.coverHandoffProxy = undefined;
    this.onTransitionFinished();
    this.restoreSource();
    this.coverHidden = false;
    this.previewVisible = false;
    this.detailOpacity = isPush ? 1 : 0;
    proxy.finishTransition();
    if (isPush) this.entryReady = true;
  }

  private runTransition(isPush: boolean, proxy: NavigationTransitionProxy): void {
    if (this.running || this.disposed) {
      this.onTransitionFinished();
      proxy.finishTransition();
      return;
    }
    this.running = true;
    // 早于 Navigation 的 timeout 清理，布局未就绪/旋转/离屏也不能留下透明页面。
    this.watchdog = setTimeout((): void => this.finish(proxy, isPush), isPush ? 1800 : 1200);
    this.afterLayout((): void => this.prepareTransition(isPush, proxy));
  }

  private prepareTransition(isPush: boolean, proxy: NavigationTransitionProxy): void {
    const payload = this.payload;
    const viewport = this.measureRect(OneShotTransitionIds.DETAIL_SURFACE);
    const target = this.measureRect(OneShotTransitionIds.detailCover(this.bookId));
    if (payload === undefined || viewport === undefined || target === undefined) {
      this.fadeFallback(isPush, proxy);
      return;
    }
    if (isPush) payload.viewportRect = viewport;
    const source = isPush ? payload.sourceRect : this.measureRect(payload.sourceNodeId);
    if (source === undefined || source.topPx + source.heightPx <= viewport.topPx ||
      source.topPx >= viewport.topPx + viewport.heightPx ||
      source.leftPx + source.widthPx <= viewport.leftPx || source.leftPx >= viewport.leftPx + viewport.widthPx ||
      (!isPush && (Math.abs(viewport.widthPx - payload.viewportRect.widthPx) > 2 ||
      Math.abs(viewport.heightPx - payload.viewportRect.heightPx) > 2))) {
      this.fadeFallback(isPush, proxy);
      return;
    }
    if (!isPush) {
      // 返回使用当前详情图片，避免详情刷新封面后倒退成进入前的截图。
      try {
        const snapshot = this.getUIContext().getComponentSnapshot().getSync(OneShotTransitionIds.detailCover(this.bookId));
        OneShotTransitionCoordinator.releaseSnapshot(this.snapshot);
        this.snapshot = snapshot;
      } catch (_error) {
        this.fadeFallback(false, proxy);
        return;
      }
    }
    this.applyRect(isPush ? source : target, viewport, isPush ? payload.sourceRadius : AppRadius.Sm);
    this.previewBaseWidth = Math.max(1, this.previewWidth);
    this.previewBaseHeight = Math.max(1, this.previewHeight);
    this.previewOpacity = 1;
    this.previewVisible = true;
    this.coverHidden = true;
    OneShotTransitionCoordinator.getInstance().coverState.hiddenSourceId = payload.sourceNodeId;
    // 起止位置均为最终布局坐标，不再缩放整个详情或在运动途中淡掉封面。
    this.afterLayout((): void => {
      this.getUIContext().animateTo({
        duration: isPush ? 420 : 350,
        curve: Curve.FastOutSlowIn,
        onFinish: (): void => {
          if (!this.running || this.disposed) return;
          if (isPush) this.handoffCover(proxy);
          else this.finish(proxy, false);
        }
      }, (): void => {
        this.applyRect(isPush ? target : source, viewport, isPush ? AppRadius.Sm : payload.sourceRadius);
        this.detailOpacity = isPush ? 1 : 0;
      });
    });
  }

  private handoffCover(proxy: NavigationTransitionProxy): void {
    this.coverHandoffProxy = proxy;
    this.waitingForCover = true;
    if (this.coverReady) {
      this.beginCoverHandoff();
      return;
    }
    this.coverWaitTimer = setTimeout((): void => this.beginCoverHandoff(), 700);
  }

  private beginCoverHandoff(): void {
    if (!this.running || !this.waitingForCover) return;
    this.waitingForCover = false;
    this.clearCoverWaitTimer();
    const proxy = this.coverHandoffProxy;
    if (proxy === undefined) return;
    this.coverHidden = false;
    // 封面已经到达目标位置，再交接真实图片，两个位置不会同时可见。
    this.afterLayout((): void => {
      this.getUIContext().animateTo({
        duration: 100,
        curve: Curve.Linear,
        onFinish: (): void => this.finish(proxy, true)
      }, (): void => { this.previewOpacity = 0; });
    });
  }

  private fadeFallback(isPush: boolean, proxy: NavigationTransitionProxy): void {
    this.coverHidden = false;
    this.previewVisible = false;
    this.restoreSource();
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish(proxy, isPush)
    }, (): void => { this.detailOpacity = isPush ? 1 : 0; });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      BookDetailPage({ navStack: this.navStack, bookId: this.bookId,
        transitionCoverHidden: this.coverHidden, deferEntry: !this.entryReady,
        onCoverReady: (url: string): void => this.onDetailCoverReady(url) })
        .width('100%')
        .height('100%')
        .renderGroup(!this.entryReady)
        .opacity(this.detailOpacity)
      if (this.previewVisible && this.snapshot !== undefined) {
        Image(this.snapshot)
          // 尺寸固定，只改变绘制变换，避免每帧重新测量详情页。
          .width(this.previewBaseWidth)
          .height(this.previewBaseHeight)
          .scale({ x: this.previewWidth / this.previewBaseWidth,
            y: this.previewHeight / this.previewBaseHeight, centerX: 0, centerY: 0 })
          .translate({ x: this.previewX, y: this.previewY })
          .borderRadius(this.previewRadius)
          .clip(true)
          .objectFit(ImageFit.Contain)
          .opacity(this.previewOpacity)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .id(OneShotTransitionIds.DETAIL_SURFACE)
  }
}

@ComponentV2
struct PlayerPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Object = '';
  @Param deferEntry: boolean = false;
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;

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
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        PlayerPage({
          navStack: this.navStack,
          bookId: this.resolveBookId(),
          deferEntry: this.deferEntry,
          resumeChapterId: this.resolveChapterId(),
          resumeProgressMs: this.resolveProgressMs()
        })
          .width(this.dragState.active ? this.dragState.viewportWidth : '100%')
          .height(this.dragState.active ? this.dragState.viewportHeight : '100%')
          .translate({ x: this.dragState.active ? -this.dragState.frameX : 0,
            y: this.dragState.active ? -this.dragState.frameY : 0 })
          .opacity(this.dragState.contentOpacity)
        if (this.dragState.active && this.dragState.snapshot !== undefined) {
          Image(this.dragState.snapshot)
            .width(this.dragState.coverWidth)
            .height(this.dragState.coverHeight)
            .position({ x: 0, y: 0 })
            .translate({ x: this.dragState.coverX - this.dragState.frameX,
              y: this.dragState.coverY - this.dragState.frameY })
            .borderRadius(this.dragState.coverRadius)
            .clip(true)
            .objectFit(ImageFit.Cover)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.dragState.active ? this.dragState.frameWidth : '100%')
      .height(this.dragState.active ? this.dragState.frameHeight : '100%')
      .translate({ x: this.dragState.active ? this.dragState.frameX : 0,
        y: this.dragState.active ? this.dragState.frameY : 0 })
      .borderRadius(this.dragState.active ? this.dragState.radius : 0)
      .backgroundColor('#000000')
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .id('player-drag-surface')
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
      moreUrl: this.str('moreUrl'),
      keyword: this.str('keyword')
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
