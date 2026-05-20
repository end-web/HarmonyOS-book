// Search 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/input/search

// ========== 标准搜索框 ==========

Search({ value: '', placeholder: '搜索' })
  .width('100%')
  .height(40)
  .backgroundColor($r('sys.color.comp_background_tertiary'))
  .placeholderColor($r('sys.color.font_secondary'))
  .placeholderFont({
    size: $r('sys.float.Body_L'),
    weight: FontWeight.Regular
  })
  .textFont({
    size: $r('sys.float.Body_L'),
    weight: FontWeight.Regular
  })

// ========== 带麦克风图标 ==========

Search({ value: '', placeholder: '搜索' })
  .width('100%')
  .height(40)
  .backgroundColor($r('sys.color.comp_background_tertiary'))
  .placeholderColor($r('sys.color.font_secondary'))
  .searchIcon({
    src: $r('sys.media.ohos_ic_public_search_filled')
  })
  .cancelButton({
    style: CancelButtonStyle.CONSTANT,
    icon: new SymbolGlyphModifier($r('sys.symbol.mic'))
      .fontSize($r('sys.float.Subtitle_M'))
      .fontColor([$r('sys.color.icon_secondary')])
  })

// ========== 带清除图标 ==========

Search({ value: '', placeholder: '搜索' })
  .width('100%')
  .height(40)
  .backgroundColor($r('sys.color.comp_background_tertiary'))
  .searchIcon({
    src: $r('sys.media.ohos_ic_public_search_filled')
  })
  .cancelButton({
    style: CancelButtonStyle.CONSTANT,
    icon: new SymbolGlyphModifier($r('sys.symbol.xmark_circle_fill'))
      .fontSize($r('sys.float.Subtitle_M'))
      .fontColor([$r('sys.color.icon_fourth')])
  })

// ========== 带事件搜索框 ==========

@ComponentV2
struct SearchWithEvent {
  @Local searchValue: string = ''

  build() {
    Search({ value: this.searchValue, placeholder: '搜索' })
      .width('100%')
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onSubmit((value: string) => {
        console.info('搜索: ' + value)
      })
      .onChange((value: string) => {
        this.searchValue = value
      })
  }
}