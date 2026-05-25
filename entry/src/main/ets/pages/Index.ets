import { MainPage } from './MainPage';
import { BookDetailPage } from './BookDetailPage';
import { PlayerPage } from './PlayerPage';
import { TextReaderPage } from './TextReaderPage';
import { HistoryPage } from './HistoryPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';
import { ImportPage } from './ImportPage';

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();

  @Builder
  routerMap(name: string, param: object) {
    if (name === 'detail') {
      NavDestination() {
        DetailPageWrapper({ navStack: this.navStack, bookId: param as Object as string })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'player') {
      NavDestination() {
        PlayerPageWrapper({ navStack: this.navStack, bookId: param as Object as string })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      .systemTransition(NavigationSystemTransitionType.SLIDE_BOTTOM)
    } else if (name === 'TextReaderPage') {
      NavDestination() {
        TextReaderPageWrapper({ navStack: this.navStack, param: param as Object as Record<string, Object> })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'history') {
      NavDestination() {
        HistoryPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'settings') {
      NavDestination() {
        SettingsPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'about') {
      NavDestination() {
        AboutPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
    } else if (name === 'import') {
      NavDestination() {
        ImportPage({ navStack: this.navStack })
      }
      .hideTitleBar(true)
      .backgroundColor($r('sys.color.background_primary'))
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
  @Param bookId: string = '';

  build() {
    PlayerPage({ navStack: this.navStack, bookId: this.bookId })
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
