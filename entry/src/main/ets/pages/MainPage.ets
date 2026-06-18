import { common } from '@kit.AbilityKit';
import { AppStorageV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial, HdsBarStyle } from '@kit.UIDesignKit';
import { emitter } from '@kit.BasicServicesKit';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { HomePage, EVT_REFRESH_HOME } from './HomePage';
import { HomeBlockSection } from '../model/BookSource';
import { FavoritePage } from './FavoritePage';
import { SourcePage } from './SourcePage';
import { ProfilePage } from './ProfilePage';
import { MiniPlayer } from '../components/MiniPlayer';
import { AudioService } from '../service/AudioService';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { EVT_SWITCH_TAB } from './ImportPage';
import { WebViewJSEngineHost } from '../service/js/WebViewJSEngine';
import { WebViewAudioExtractorHost } from '../service/builtin/WebViewAudioExtractor';

/**
 * 全局事件:点击某本书时调,统一收口路由策略。
 */
export const EVT_NAVIGATE_TO_BOOK = 'app.navigate.to.book';

export interface NavigateToBookPayload {
  bookId: string;
  chapterId?: string;
  progressMs?: number;
  forceDetail?: boolean;
}

const FLOATING_BOTTOM: number = 4;

@ComponentV2
export struct MainPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local currentTab: number = 0;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  /** 当前迷你栏样式,折叠态下让 MiniPlayer 只渲染封面 */
  @Local miniBarCollapsed: boolean = false;

  private tabController: HdsTabsController = new HdsTabsController();
  private context: common.UIAbilityContext | null = null;
  private switchTabHandler: (e: emitter.EventData) => void = (e) => this.onSwitchTabEvent(e);
  /** 各 Tab 页的滚动控制器,用于双击 Tab 回顶部 */
  private scrollers: Map<number, Scroller> = new Map();
  /** 上一次 Tab 点击时间,用于双击检测 */
  private lastTabClickTime: number = 0;
  private lastTabClickIndex: number = -1;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  private navigateToBook(bookId: string, chapterId: string, progressMs: number, forceDetail: boolean): void {
    if (forceDetail) {
      this.navStack.pushPathByName('detail', bookId);
      return;
    }
    const cached = SearchCache.get(bookId);
    const isTextBook = cached?.contentType === 'text' || cached?.category === 'text';
    if (isTextBook && chapterId) {
      const params: Record<string, Object> = {
        'bookId': bookId,
        'chapterId': chapterId,
        'progressMs': progressMs
      };
      this.navStack.pushPathByName('reader', params);
      return;
    }
    if (isTextBook) {
      this.navStack.pushPathByName('detail', bookId);
      return;
    }
    if (PlaybackStore.getInstance().isCurrentBook(bookId)) {
      // 点击当前正在播放的书,直接进播放页
      this.navStack.pushPathByName('player', bookId);
      return;
    }
    if (chapterId) {
      // 从详情页进入指定章节
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
    const book = await DataService.getBookById(this.context!, last.bookId);
    if (!book) return;
    const idx = DataService.resolveChapterIndex(book, last.chapterId, last.chapterTitle);
    if (idx < 0) return;
    const chapter = book.chapters[idx];
    this.playerState.currentBook = book;
    this.playerState.currentChapter = chapter;
    this.playerState.progressMs = last.progressMs;
    const savedDuration = (last.durationMs && last.durationMs > 0)
      ? last.durationMs
      : (chapter.duration > 0 ? chapter.duration * 1000 : 0);
    this.playerState.durationMs = savedDuration;
    this.playerState.isPlaying = false;
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

  /**
   * 迷你栏内容 Builder
   * 由 HdsTabs 官方管理折叠/展开状态:
   * - 折叠态(COLLAPSE): 显示一个圆形播放控制按钮
   * - 展开态(EXPAND): 显示完整的 MiniPlayer
   */
  @Builder
  miniBarBuilder(): void {
    if (this.playerState.currentBook) {
      MiniPlayer({
        playerState: this.playerState,
        collapsed: this.miniBarCollapsed,
        onTapBody: () => {
          // 折叠态:点击封面 → 展开迷你栏(不进播放器);展开态:进播放器
          if (this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        },
        onToggle: () => AudioService.getInstance().toggle(),
        onNext: () => this.playNext(),
        onExpand: () => {
          if (this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        }
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs({ controller: this.tabController }) {
        TabContent() {
          HomePage({
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onBlockMore: (block: HomeBlockSection) => this.openBlockMore(block),
            onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) =>
              this.openCategory(sourceUrl, sourceName, title, url),
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(0, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.house'), $r('sys.symbol.house_fill'), '首页'))

        TabContent() {
          FavoritePage({
            visible: this.currentTab === 1,
            navStack: this.navStack,
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onGotoStore: () => this.tabController.changeIndex(0),
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(1, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.archivebox'), $r('sys.symbol.archivebox_fill'), '书架'))

        TabContent() {
          SourcePage({
            navStack: this.navStack,
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(2, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.folder'), $r('sys.symbol.folder_fill'), '书源'))

        TabContent() {
          ProfilePage({
            navStack: this.navStack,
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(3, scroller); }
          })
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
        },
        // 智感握持:左右手自动跟手
        adaptToHandedness: true,
        // 迷你栏配置:HdsTabs 会自动管理折叠/展开
        miniBar: this.playerState.currentBook ? {
          miniBarBuilder: () => this.miniBarBuilder(),
          // 跟随当前实际状态,避免主题切换等重建把迷你栏强制重置回展开态
          miniBarStyle: this.miniBarCollapsed ? HdsBarStyle.COLLAPSE : HdsBarStyle.EXPAND,
          enableMiniBarBackground: true,
          enableMiniBarClip: true,
          // 系统切换样式时同步给 MiniPlayer,让它切换内部布局(折叠态只显示封面)
          onBarStyleChange: (miniStyle: HdsBarStyle, _tabStyle: HdsBarStyle) => {
            this.miniBarCollapsed = miniStyle === HdsBarStyle.COLLAPSE;
          }
        } : undefined
      })
      .onTabBarClick((index: number) => {
        const now = Date.now();
        const DOUBLE_TAP_DELAY = 300;
        if (index === this.lastTabClickIndex && (now - this.lastTabClickTime) < DOUBLE_TAP_DELAY) {
          if (index === 0) {
            // 双击首页 → 刷新首页数据(不再返回顶部)
            emitter.emit(EVT_REFRESH_HOME);
          } else {
            // 双击其它 Tab → 滚动回顶部
            const scroller = this.scrollers.get(index);
            if (scroller) {
              try { scroller.scrollEdge(Edge.Top); } catch (_e) { /* ignore */ }
            }
          }
        }
        this.lastTabClickTime = now;
        this.lastTabClickIndex = index;
      })
      .onChange((index: number) => { this.currentTab = index; })
      .width('100%')
      .height('100%')
      .backgroundColor('#FFF5F5F5')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

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

  /** 分类入口:复用 blockMore 路由展示分类书单 */
  private openCategory(sourceUrl: string, sourceName: string, title: string, url: string): void {
    if (!sourceUrl || !url) return;
    const params: Record<string, Object> = {
      'sourceUrl': sourceUrl,
      'sourceName': sourceName,
      'title': title,
      'moreUrl': url
    };
    this.navStack.pushPathByName('blockMore', params);
  }

  private navigateToPlayer(): void {
    if (!this.playerState.currentBook) return;
    const bookId = this.playerState.currentBook.id;
    // mini→player:走与其他入口一致的 customTransition 上滑转场。
    // (放弃跨 NavDestination 的 geometryTransition 共享元素——它在 push/pop 反复时
    //  绑定表错乱,返回动画正常/异常交替,且非官方推荐用法。)
    this.navStack.pushPathByName('player', bookId);
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
