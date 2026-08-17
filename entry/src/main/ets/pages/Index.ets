import { common } from '@kit.AbilityKit';
import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage, PlayerBackInterceptor, PlayerEntryDecider } from './PlayerPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';
import { GuidePage } from './GuidePage';
import { ImportPage } from './ImportPage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { PrivacyPage } from './PrivacyPage';
import { BlockMorePage } from './BlockMorePage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { ReaderPage } from './ReaderPage';
import { ReaderKitVerifyPage } from './ReaderKitVerifyPage';
import { TextSourceVerifyPage } from './TextSourceVerifyPage';
import { TextReaderRouteParams } from '../model/TextReading';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_WIDGET_ROUTE, KEY_WIDGET_ROUTE, WidgetRoute } from '../entryability/EntryAbility';
import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';

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
      .backgroundColor($r('sys.color.background_primary'))
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
