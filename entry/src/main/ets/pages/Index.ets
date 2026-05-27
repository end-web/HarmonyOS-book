import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage } from './PlayerPage';
import { TextReaderPage } from './TextReaderPage';
import { HistoryPage } from './HistoryPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';
import { ImportPage } from './ImportPage';
import { PrivacyPage } from './PrivacyPage';
import { RuleEngineTestPage } from './RuleEngineTestPage';

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local playerTranslateY: string = '0';
  @Local playerBorderRadius: number = 0;

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'detail') {
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
      .backgroundColor('#000000')
      .translate({ y: this.playerTranslateY })
      .borderRadius(this.playerBorderRadius)
      .customTransition((op: NavigationOperation, isEnter: boolean): Array<NavDestinationTransition> | undefined => {
        if (op === NavigationOperation.PUSH && isEnter) {
          this.playerTranslateY = '100%';
          this.playerBorderRadius = 20;
          return [{
            duration: 380,
            curve: Curve.Friction,
            event: () => {
              this.playerTranslateY = '0';
              this.playerBorderRadius = 0;
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
              this.playerTranslateY = '100%';
              this.playerBorderRadius = 20;
            },
            onTransitionEnd: () => {}
          }];
        }
        return undefined;
      })
    } else if (name === 'TextReaderPage') {
      NavDestination() {
        TextReaderPageWrapper({ navStack: this.navStack, param: param as Object as Record<string, Object> })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    } else if (name === 'history') {
      NavDestination() {
        HistoryPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
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
    } else if (name === 'RuleEngineTestPage') {
      NavDestination() {
        RuleEngineTestPageWrapper({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    }
  }

  build() {
    Navigation(this.navStack) {
      MainPage({ navStack: this.navStack })
    }
    .navDestination(this.routerMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
struct RuleEngineTestPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();

  build() {
    RuleEngineTestPage({ navStack: this.navStack })
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
struct TextReaderPageWrapper {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param param: Record<string, Object> = {};

  build() {
    TextReaderPage({
      navStack: this.navStack,
      bookId: this.param['bookId'] as string,
      chapterIndex: this.param['chapterIndex'] as number
    })
  }
}
