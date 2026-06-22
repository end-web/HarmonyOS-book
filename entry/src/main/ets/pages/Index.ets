import { common } from '@kit.AbilityKit';
import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage, PlayerBackInterceptor, PlayerEntryDecider } from './PlayerPage';
import { ReaderPage } from './ReaderPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';
import { ImportPage } from './ImportPage';
import { PrivacyPage } from './PrivacyPage';
import { BlockMorePage } from './BlockMorePage';
import { BrowserPage } from './BrowserPage';
import { LoginPage } from './LoginPage';
import { SourceDebugPage } from './SourceDebugPage';
import { SourceEditPage } from './SourceEditPage';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_WIDGET_ROUTE, KEY_WIDGET_ROUTE, WidgetRoute } from '../entryability/EntryAbility';
import { webview } from '@kit.ArkWeb';
import { JavaBridgeImpl } from '../service/rule/JavaBridge';
import { EVT_OPEN_LOGIN } from './HomePage';

interface BrowserPageParams {
  url: string;
  title: string;
}

interface WidgetRouteEvent {
  target: string;
  bookId: string;
  ts?: number;
}

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local playerTranslateY: string = '0';
  @Local playerBorderRadius: number = 0;
  // 层叠下沉:player 升起时底层首页缩小+圆角+压暗,沉到后面去
  @Local homeScale: number = 1;
  @Local homeRadius: number = 0;
  @Local homeBrightness: number = 1;
  private widgetSubscribed: boolean = false;
  /** 已消费过的路由 ts，避免冷启动时 AppStorage + emitter 两条路径同时触发同一个 push */
  private lastConsumedRouteTs: number = 0;

  aboutToAppear(): void {
    // 先 push home 作为栈底,再消费 widget 路由,保证栈不空
    this.navStack.pushPathByName('home', null, false);

    // 注册 JavaBridge 回调（toast / 浏览器 / 刷新发现页）
    this.registerJavaBridgeCallbacks();

    // 监听聚合源登录事件
    emitter.on(EVT_OPEN_LOGIN, () => {
      try {
        const params: Record<string, string> = {
          'loginUrl': 'https://v1.gyks.cf/login',
          'serverHost': 'https://v1.gyks.cf',
          'title': '登录聚合源',
        };
        this.navStack.pushPathByName('login', params);
      } catch (e) {
        console.error(`[Index] login navigation error: ${e}`);
      }
    });

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
    // 清理登录事件监听
    try {
      emitter.off(EVT_OPEN_LOGIN);
    } catch (_e) { /* ignore */ }
    if (this.widgetSubscribed) {
      try {
        emitter.off(EVT_WIDGET_ROUTE);
      } catch (_e) { /* ignore */ }
      this.widgetSubscribed = false;
    }
    // 清理 JavaBridge 回调
    JavaBridgeImpl.setToastCallback(null);
    JavaBridgeImpl.setBrowserCallback(null);
    JavaBridgeImpl.setRefreshExploreCallback(null);
  }

  private registerJavaBridgeCallbacks(): void {
    // Toast 回调
    JavaBridgeImpl.setToastCallback((msg: string, duration: number) => {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: msg,
          duration: duration,
        });
      } catch (e) {
        console.error(`[Index] toast error: ${e}`);
      }
    });

    // 浏览器回调
    JavaBridgeImpl.setBrowserCallback((url: string, title: string) => {
      try {
        const params: BrowserPageParams = { url, title };
        this.navStack.pushPathByName('browser', params);
      } catch (e) {
        console.error(`[Index] browser error: ${e}`);
      }
    });

    // 刷新发现页回调
    JavaBridgeImpl.setRefreshExploreCallback(() => {
      // 通过 emitter 通知 MainPage 刷新发现页
      try {
        emitter.emit({ eventId: 1001 });
      } catch {
        // ignore
      }
    });
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
        this.navStack.pushPathByName('player', bookId, false);
      }
      // 无 bookId 时停在主页,避免黑屏
    } else if (target === 'detail') {
      if (bookId) this.navStack.pushPathByName('detail', bookId, false);
    }
    // target === 'home' 默认停在 Tab,不需要跳转
  }

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'home') {
      NavDestination() {
        MainPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      // 作为根/底层页:被任何子页覆盖时保持静止,不走系统默认 push 的左移视差。
      // 否则 player 上滑升起时,底下首页会跟着向左滑一下。
      .systemTransition(NavigationSystemTransitionType.NONE)
      // 层叠下沉:player 升起时随之缩小+圆角+压暗(由 player 的 customTransition 联动驱动)
      .scale({ x: this.homeScale, y: this.homeScale })
      .borderRadius(this.homeRadius)
      .clip(true)
      .brightness(this.homeBrightness)
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
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'player') {
      NavDestination() {
        PlayerPageWrapper({ navStack: this.navStack, param: param as Object })
      }
      .hideTitleBar(true)
      // 关闭系统默认转场,让 customTransition 接管上滑(进)/下滑(返回)
      .systemTransition(NavigationSystemTransitionType.NONE)
      // 抽屉(章节/定时/跳过)打开时,右滑/返回先关抽屉而不是退整页
      .onBackPressed((): boolean => {
        // 优先关抽屉
        if (PlayerBackInterceptor.consume()) return true;
        // 立即标记 PlayerPage 离开,让 loadBook 异步链提前退出,不阻塞返回响应
        PlayerEntryDecider.markLeaving();
        // 放行,由 customTransition 播放下滑退场
        return false;
      })
      .backgroundColor('#000000')
      .translate({ y: this.playerTranslateY })
      .borderRadius(this.playerBorderRadius)
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        // 所有入口统一走上滑(进)/下滑(返回)转场,同时联动底层 home 缩小下沉
        if (op === NavigationOperation.PUSH && isEnter) {
          this.playerTranslateY = '100%';
          this.playerBorderRadius = 20;
          return [{
            duration: 380,
            curve: Curve.Friction,
            event: () => {
              // player 上滑归位
              this.playerTranslateY = '0';
              this.playerBorderRadius = 0;
              // 同时 home 下沉:缩到 0.93,圆角 16,亮度降到 0.7(压暗)
              this.homeScale = 0.93;
              this.homeRadius = 16;
              this.homeBrightness = 0.7;
            },
            onTransitionEnd: () => {}
          }];
        } else if (op === NavigationOperation.POP && !isEnter) {
          this.playerTranslateY = '0';
          this.playerBorderRadius = 0;
          return [{
            duration: 320,
            curve: Curve.FastOutSlowIn,
            event: () => {
              // player 下滑退场
              this.playerTranslateY = '100%';
              this.playerBorderRadius = 20;
              // 同时 home 弹回:恢复 scale=1,圆角=0,亮度=1
              this.homeScale = 1;
              this.homeRadius = 0;
              this.homeBrightness = 1;
            },
            onTransitionEnd: () => {
              // POP 动画结束后必须把状态归零,否则下次 push(尤其 animated:false 的 widget 入口)
              // 会拿到上次 POP 留下的 '100%',NavDestination 整页向下偏导致白屏。
              this.playerTranslateY = '0';
              this.playerBorderRadius = 0;
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
      // 对齐官方 ReaderKit Demo:阅读页关闭系统转场,避免夜间主题重进时先露浅色首帧。
      .backgroundColor('#121212')
      .systemTransition(NavigationSystemTransitionType.NONE)
    } else if (name === 'settings') {
      NavDestination() {
        SettingsPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'about') {
      NavDestination() {
        AboutPage({ navStack: this.navStack })
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
    } else if (name === 'browser') {
      NavDestination() {
        BrowserPage({ navStack: this.navStack, url: (param as BrowserPageParams)?.url || '', title: (param as BrowserPageParams)?.title || '' })
      }
      .hideTitleBar(true)
      .backgroundColor('#FFFFFF')
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'login') {
      NavDestination() {
        LoginPage({
          navStack: this.navStack,
          loginUrl: ((param as Record<string, string>)?.['loginUrl']) || 'https://v1.gyks.cf/login',
          serverHost: ((param as Record<string, string>)?.['serverHost']) || 'https://v1.gyks.cf',
          title: ((param as Record<string, string>)?.['title']) || '登录聚合源',
        })
      }
      .hideTitleBar(true)
      .backgroundColor('#FFFFFF')
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'sourceDebug') {
      NavDestination() {
        SourceDebugPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'sourceEdit') {
      NavDestination() {
        SourceEditPage({ navStack: this.navStack, sourceUrl: (param as Object as string) || '' })
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
    .navDestination(this.routerMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
struct DetailPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';

  build() {
    BookDetailPage({ navStack: this.navStack, bookId: this.bookId })
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
struct ReaderPageWrapper {
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
    ReaderPage({
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
