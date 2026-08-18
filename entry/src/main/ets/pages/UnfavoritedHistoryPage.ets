import { ReadingStatsPage } from './ReadingStatsPage';

/** 顶部时钟入口：展示未加入书架的收听历史。 */
@ComponentV2
export struct UnfavoritedHistoryPage {
  @Param navStack: NavPathStack = new NavPathStack();

  build() {
    ReadingStatsPage({
      navStack: this.navStack,
      onlyUnfavorited: true
    })
  }
}
