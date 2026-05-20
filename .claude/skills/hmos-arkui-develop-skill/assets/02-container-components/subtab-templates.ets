// SubTab 子标签页示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/navigation/subtab

// ========== 下划线样式水平标签 ==========

Tabs({ barPosition: BarPosition.Start }) {
  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签1'))

  TabContent() { }
    .tabBar(SubTabBarStyle.of('标签2'))
}
.vertical(false)
.height(56)
.barMode(BarMode.Scrollable)

// ========== 下划线样式垂直标签 ==========

@ComponentV2
struct UnderlineStyleVertical {
  @Local selectedIndex: number = 0

  @Builder
  tabBuilder(index: number, val: ResourceStr) {
    Column() {
      Text(val)
        .fontColor(this.selectedIndex === index ? 
          $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
        .fontSize($r('sys.float.Subtitle_M'))
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Regular)

      Divider()
        .strokeWidth(this.selectedIndex === index ? 2 : 0)
        .color(this.selectedIndex === index ? $r('sys.color.font_emphasize') : Color.Transparent)
        .margin({ top: 8, left: 16, right: 16 })
    }
    .width(96)
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs() {
      TabContent() { }
        .tabBar(this.tabBuilder(0, '标签1'))

      TabContent() { }
        .tabBar(this.tabBuilder(1, '标签2'))

      TabContent() { }
        .tabBar(this.tabBuilder(2, '标签3'))
    }
    .vertical(true)
    .barWidth(96)
    .barMode(BarMode.Scrollable)
    .onChange((index: number) => {
      this.selectedIndex = index
    })
  }
}

// ========== 胶囊样式单选标签 ==========

import { ChipGroup, ChipSize } from '@kit.ArkUI'

ChipGroup({
  items: [
    { label: { text: '标签1' }, allowClose: false },
    { label: { text: '标签2' }, allowClose: false },
    { label: { text: '标签3' }, allowClose: false }
  ],
  itemStyle: {
    size: ChipSize.NORMAL,
    backgroundColor: $r('sys.color.ohos_id_color_button_normal'),
    fontColor: $r('sys.color.ohos_id_color_text_primary'),
    selectedBackgroundColor: $r('sys.color.ohos_id_color_emphasize'),
    selectedFontColor: $r('sys.color.ohos_id_color_text_primary_contrary')
  },
  multiple: false,
  onChange: (activatedChipsIndex: Array<number>) => {
    console.info('Selected: ' + activatedChipsIndex)
  }
})

// ========== 胶囊样式多选标签 ==========

ChipGroup({
  items: [
    { label: { text: '选项1' }, allowClose: false },
    { label: { text: '选项2' }, allowClose: false }
  ],
  itemStyle: {
    size: ChipSize.NORMAL,
    backgroundColor: $r('sys.color.ohos_id_color_button_normal'),
    fontColor: $r('sys.color.ohos_id_color_text_primary'),
    selectedBackgroundColor: $r('sys.color.ohos_id_color_emphasize'),
    selectedFontColor: $r('sys.color.ohos_id_color_text_primary_contrary')
  },
  selectedIndexes: [0],
  multiple: true,
  onChange: (activatedChipsIndex: Array<number>) => {
    console.info('Selected: ' + activatedChipsIndex)
  }
})