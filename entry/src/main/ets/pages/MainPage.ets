import { common } from '@kit.AbilityKit';
import { AppStorageV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppRadius, AppSpace } from '../theme/Theme';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { HomePage } from './HomePage';
import { HomeBlockSection } from '../model/BookSource';
import { FavoritePage } from './FavoritePage';
import { SourcePage } from './SourcePage';
import { ProfilePage } from './ProfilePage';
import { MiniPlayer } from '../components/MiniPlayer';
import { AudioService } from '../service/AudioService';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { PlaybackStore } from '../service/PlaybackStore';
import { WindowUtils } from '../utils/WindowUtils';
import { EVT_SWITCH_TAB } from './ImportPage';
import { WebViewJSEngineHost } from '../service/js/WebViewJSEngine';
import { WebViewAudioExtractorHost } from '../service/builtin/WebViewAudioExtractor';

/**
 * 全局事件:点击某本书时调,统一收口路由策略。
 * 监听者(MainPage)收到后做"已在播这本书 → 直接进 player 不打断"等判断,
 * 把 Home/Favorite/MiniPlayer/BookDetail 的点击行为统一。
 */
export const EVT_NAVIGATE_TO_BOOK = 'app.navigate.to.book';

export interface NavigateToBookPayload {
  bookId: string;
  /** 调用方已知的 chapterId(可选,FavoritePage 知道历史时传) */
  chapterId?: string;
  /** 调用方已知的恢复进度(可选,FavoritePage/BookDetailPage 传) */
  progressMs?: number;
  /** 是否强制走详情(BookDetail 入口需要) */
  forceDetail?: boolean;
}

// 胶囊高度估算:HdsTabs 悬浮胶囊默认 ~60vp,MiniPlayer 胶囊取相近高度
const FLOATING_TAB_HEIGHT: number = 60;
const MINI_PLAYER_HEIGHT: number = 60;
const FLOATING_GAP: number = 12; // 上下两排胶囊之间的垂直间距
const FLOATING_BOTTOM: number = 4; // HdsTabs barBottomMargin（越小整体越贴底）

@ComponentV2
export struct MainPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local currentTab: number = 0;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;

  private tabController: HdsTabsController = new HdsTabsController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private switchTabHandler: (e: emitter.EventData) => void = (e) => this.onSwitchTabEvent(e);

  aboutToAppear(): void {
    AudioService.getInstance().bind(this.playerState, this.context);
    this.restoreLastPlayed();
    WindowUtils.setStatusBarLight(false);
    this.restoreDefaultTab();
    emitter.on(EVT_SWITCH_TAB, this.switchTabHandler);
    emitter.on(EVT_NAVIGATE_TO_BOOK, this.navigateBookHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_SWITCH_TAB, this.switchTabHandler);
    emitter.off(EVT_NAVIGATE_TO_BOOK, this.navigateBookHandler);
  }

  private navigateBookHandler: (e: emitter.EventData) => void = (e) => this.onNavigateBookEvent(e);

  private onNavigateBookEvent(e: emitter.EventData): void {
    const data = e.data as Record<string, Object> | undefined;
    if (!data) return;
    const bookId = data['bookId'] as string;
    if (!bookId) return;
    const chapterId = (data['chapterId'] as string) ?? '';
    const progressMs = (data['progressMs'] as number) ?? 0;
    const forceDetail = (data['forceDetail'] as boolean) === true;
    this.navigateToBook(bookId, chapterId, progressMs, forceDetail);
  }

  /**
   * 统一收口:决定点击书籍后走 player 还是 detail。
   * - 强制 detail(BookDetailPage 入口): 进 detail
   * - 已在播该书: 直接 push player(不带 chapter/progress,PlayerPage 复用 live state,不打断播放)
   * - 有历史(caller 传了 chapterId): 直接 push player 带恢复参数
   * - 否则: 进 detail 让用户挑章节
   */
  private navigateToBook(bookId: string, chapterId: string, progressMs: number, forceDetail: boolean): void {
    if (forceDetail) {
      this.navStack.pushPathByName('detail', bookId);
      return;
    }
    if (PlaybackStore.getInstance().isCurrentBook(bookId)) {
      // 当前正在播这本书:直接进 player,什么 resume 参数都不传,
      // PlayerPage 内部 tryResumePlay 看到 resumeChapterId='' 不会调 playChapterAndSeek
      this.navStack.pushPathByName('player', bookId);
      return;
    }
    if (chapterId) {
      const params: Record<string, Object> = {
        'bookId': bookId,
        'chapterId': chapterId,
        'progressMs': progressMs
      };
      this.navStack.pushPathByName('player', params);
      return;
    }
    this.navStack.pushPathByName('detail', bookId);
  }

  private onSwitchTabEvent(e: emitter.EventData): void {
    const data = e.data as Record<string, Object> | undefined;
    if (!data) return;
    const v = data['index'];
    if (typeof v !== 'number') return;
    const idx = v as number;
    if (idx < 0 || idx > 3) return;
    setTimeout(() => {
      this.currentTab = idx;
      this.tabController.changeIndex(idx);
    }, 60);
  }

  private async restoreDefaultTab(): Promise<void> {
    const idx = await PreferenceService.getDefaultTab();
    if (idx <= 0 || idx > 3) return;
    setTimeout(() => {
      this.currentTab = idx;
      this.tabController.changeIndex(idx);
    }, 50);
  }

  private async restoreLastPlayed(): Promise<void> {
    if (this.playerState.currentBook) return;
    const last = await PreferenceService.getLastPlayed();
    if (!last) return;
    const book = await DataService.getBookById(this.context, last.bookId);
    if (!book) return;
    // 标题优先定位:连载更新/TOC 重排后旧 chapterId 会指向错误章节
    const idx = DataService.resolveChapterIndex(book, last.chapterId, last.chapterTitle);
    if (idx < 0) return;
    const chapter = book.chapters[idx];
    this.playerState.currentBook = book;
    this.playerState.currentChapter = chapter;
    this.playerState.progressMs = last.progressMs;
    // prepared 之前用持久化时长撑住 Slider max,避免冷启动滑块停在 0
    const savedDuration = (last.durationMs && last.durationMs > 0)
      ? last.durationMs
      : (chapter.duration > 0 ? chapter.duration * 1000 : 0);
    this.playerState.durationMs = savedDuration;
    this.playerState.isPlaying = false;
    // 让 PlaybackStore 也知道"当前书是这本"——MiniPlayer 点击就能直接进 player 不打断
    PlaybackStore.getInstance().update(
      book.id, chapter.id, idx,
      chapter.source?.value ?? '', false
    );
  }

  private buildTabBar(iconNormal: Resource, iconSelected: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(
      {
        normal: new SymbolGlyphModifier(iconNormal).fontColor([$r('sys.color.font_secondary')]).fontSize(24),
        selected: new SymbolGlyphModifier(iconSelected).fontColor([$r('sys.color.font_primary')]).fontSize(26)
      },
      label
    ).labelStyle({
      unselectedColor: $r('sys.color.font_secondary'),
      selectedColor: $r('sys.color.font_primary')
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs({ controller: this.tabController }) {
        TabContent() {
          HomePage({
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onBlockMore: (block: HomeBlockSection) => this.openBlockMore(block)
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.house'), $r('sys.symbol.house_fill'), '首页'))

        TabContent() {
          FavoritePage({
            visible: this.currentTab === 1,
            navStack: this.navStack,
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onGotoStore: () => this.tabController.changeIndex(0)
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.heart'), $r('sys.symbol.heart_fill'), '书架'))

        TabContent() {
          SourcePage()
        }
        .tabBar(this.buildTabBar($r('sys.symbol.folder'), $r('sys.symbol.folder_fill'), '书源'))

        TabContent() {
          ProfilePage({ navStack: this.navStack })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.person'), $r('sys.symbol.person_fill'), '我的'))
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barFloatingStyle({
        barBottomMargin: WindowUtils.getBottomSafeVp() + FLOATING_BOTTOM,
        gradientMask: { maskColor: '#66F1F3F5', maskHeight: 92 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => { this.currentTab = index; })
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_primary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.playerState.currentBook) {
        Row() {
          MiniPlayer({
            playerState: this.playerState,
            collapsed: false,
            onTapBody: () => this.navigateToPlayer(),
            onToggle: () => AudioService.getInstance().toggle(),
            onNext: () => this.playNext(),
            onExpand: () => this.navigateToPlayer()
          })
        }
        .height(MINI_PLAYER_HEIGHT)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
        .margin({
          left: AppSpace.Lg,
          right: AppSpace.Lg,
          bottom: WindowUtils.getBottomSafeVp() + FLOATING_BOTTOM + FLOATING_TAB_HEIGHT + FLOATING_GAP
        })
        .borderRadius(AppRadius.Pill)
        .backgroundEffect({
          radius: 32,
          saturation: 1.2,
          brightness: 1.05,
          color: '#26FFFFFF'
        })
        .shadow({ radius: 20, color: '#26000000', offsetY: 3 })
      }

      WebViewJSEngineHost()
      WebViewAudioExtractorHost()
    }
    .width('100%')
    .height('100%')
  }

  private openBlockMore(block: HomeBlockSection): void {
    if (!block || !block.moreUrl) return;
    const params: Record<string, Object> = {
      'sourceUrl': block.sourceUrl,
      'sourceName': block.sourceName,
      'title': block.title,
      'moreUrl': block.moreUrl
    };
    this.navStack.pushPathByName('blockMore', params);
  }

  private navigateToPlayer(): void {
    if (!this.playerState.currentBook) return;
    // MiniPlayer 点击:走统一入口,PlaybackStore 命中→直接进 player 不带 chapter 参数,
    // PlayerPage 会复用 live state,绝不触发 reset
    this.navigateToBook(this.playerState.currentBook.id, '', 0, false);
  }

  private playNext(): void {
    if (!this.playerState.currentBook || !this.playerState.currentChapter) return;
    const chapters = this.playerState.currentBook.chapters;
    const idx = chapters.findIndex(c => c.id === this.playerState.currentChapter!.id);
    if (idx >= 0 && idx < chapters.length - 1) {
      AudioService.getInstance().playChapter(this.playerState.currentBook, chapters[idx + 1]);
    }
  }
}
