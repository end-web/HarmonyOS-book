import { common } from '@kit.AbilityKit';
import { AppStorageV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, HdsBarStyle } from '@kit.UIDesignKit';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
import { AppColor } from '../theme/Theme';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { SourcePage } from './SourcePage';
import { ProfilePage } from './ProfilePage';
import { MiniPlayer } from '../components/MiniPlayer';
import { AudioService } from '../service/AudioService';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct MainPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local currentTab: number = 0;
  @Local miniBarCollapsed: boolean = true;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;

  private tabController: HdsTabsController = new HdsTabsController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    AudioService.getInstance().bind(this.playerState, this.context);
    this.restoreLastPlayed();
    WindowUtils.setStatusBarLight(false);
    this.restoreDefaultTab();
  }

  private async restoreDefaultTab(): Promise<void> {
    const idx = await PreferenceService.getDefaultTab();
    if (idx <= 0 || idx > 3) return;
    // HdsTabs 挂载需要一拍,过早 changeIndex 会被忽略
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
    const chapter = book.chapters.find((c) => c.id === last.chapterId);
    if (!chapter) return;
    this.playerState.currentBook = book;
    this.playerState.currentChapter = chapter;
    this.playerState.progressMs = last.progressMs;
    this.playerState.durationMs = chapter.duration * 1000;
    this.playerState.isPlaying = false;
  }

  private buildTabBar(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(
      {
        normal: new SymbolGlyphModifier(icon).fontColor(['#8F8F8F']).fontSize(24),
        selected: new SymbolGlyphModifier(icon).fontColor([AppColor.Brand]).fontSize(24)
      },
      label
    ).labelStyle({
      unselectedColor: '#8F8F8F',
      selectedColor: AppColor.Brand
    });
  }

  build() {
    HdsTabs({ controller: this.tabController }) {
      TabContent() {
        HomePage({ onBookTap: (id: string) => this.navigateToDetail(id) })
      }
      .tabBar(this.buildTabBar($r('sys.symbol.house'), '首页'))

      TabContent() {
        FavoritePage({
          visible: this.currentTab === 1,
          navStack: this.navStack,
          onBookTap: (id: string) => this.navigateToDetail(id),
          onGotoStore: () => this.tabController.changeIndex(0)
        })
      }
      .tabBar(this.buildTabBar($r('sys.symbol.books_vertical_fill'), '书架'))

      TabContent() {
        SourcePage()
      }
      .tabBar(this.buildTabBar($r('sys.symbol.doc_text'), '书源'))

      TabContent() {
        ProfilePage({ navStack: this.navStack })
      }
      .tabBar(this.buildTabBar($r('sys.symbol.person'), '我的'))
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barFloatingStyle({
      barBottomMargin: WindowUtils.getBottomSafeVp() + 8,
      gradientMask: { maskColor: '#66F1F3F5', maskHeight: 92 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      miniBar: this.playerState.currentBook ? {
        miniBarBuilder: (): void => this.miniBarBuilder(),
        enableMiniBarBackground: true,
        enableMiniBarClip: true,
        onBarStyleChange: (miniBarStyle: HdsBarStyle): void => {
          this.miniBarCollapsed = miniBarStyle === HdsBarStyle.COLLAPSE;
        }
      } : undefined
    })
    .onChange((index: number) => { this.currentTab = index; })
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  miniBarBuilder(): void {
    MiniPlayer({
      playerState: this.playerState,
      collapsed: this.miniBarCollapsed,
      onTapBody: () => this.navigateToPlayer(),
      onToggle: () => AudioService.getInstance().toggle(),
      onNext: () => this.playNext()
    })
  }

  private navigateToDetail(bookId: string): void {
    this.navStack.pushPathByName('detail', bookId);
  }

  private navigateToPlayer(): void {
    if (this.playerState.currentBook) {
      this.navStack.pushPathByName('player', this.playerState.currentBook.id);
    }
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
