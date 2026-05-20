// BottomTabBar 底部标签栏示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/navigation/bottomtabbar

// ========== 基础底部标签栏 ==========

@ComponentV2
struct BasicTabBarExample {
  @Local selectedIndex: number = 0
  @Local currentIndex: number = 0

  @Builder
  tabBuilder(index: number) {
    Column() {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
        .fontSize($r('sys.float.Title_M'))
        .fontColor(this.selectedIndex === index ? 
          [$r('sys.color.icon_emphasize')] : [$r('sys.color.icon_tertiary')])

      Text(`Tab${index + 1}`)
        .fontColor(this.selectedIndex === index ? 
          $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
        .fontSize($r('sys.float.Caption_M'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
  }

  build() {
    Tabs({ index: this.currentIndex }) {
      TabContent() {
        Text('内容1')
      }
      .tabBar(this.tabBuilder(0))

      TabContent() {
        Text('内容2')
      }
      .tabBar(this.tabBuilder(1))

      TabContent() {
        Text('内容3')
      }
      .tabBar(this.tabBuilder(2))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(true)
    .onChange((index) => {
      this.selectedIndex = index
      this.currentIndex = index
    })
  }
}

// ========== 垂直标签栏 ==========

Tabs() {
  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签1'))

  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签2'))
}
.vertical(true)
.barWidth(96)

// ========== 可滚动标签栏 ==========

Tabs() {
  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签1'))
  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签2'))
}
.barMode(BarMode.Scrollable)