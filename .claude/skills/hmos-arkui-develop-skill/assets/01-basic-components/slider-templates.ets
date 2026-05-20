// Slider 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/select/slider

// ========== 普通滑块 ==========

Slider({
  value: 50,
  min: 0,
  max: 100,
  style: SliderStyle.NONE
})
  .trackColor($r('sys.color.comp_background_tertiary'))
  .selectedColor($r('sys.color.comp_background_secondary'))

// ========== OutSet滑块 ==========

Slider({
  value: 50,
  min: 0,
  max: 100,
  style: SliderStyle.OutSet
})
  .trackColor($r('sys.color.comp_background_tertiary'))

// ========== InSet滑块 ==========

Slider({
  value: 50,
  min: 0,
  max: 100,
  style: SliderStyle.InSet
})
  .blockColor($r('sys.color.ohos_id_color_foreground_contrary'))
  .trackColor($r('sys.color.comp_background_tertiary'))
  .selectedColor($r('sys.color.ohos_id_color_emphasize'))

// ========== 带气泡提示 ==========

Slider({
  value: 40,
  min: 0,
  max: 100,
  style: SliderStyle.InSet
})
  .showTips(true, '40')
  .trackColor($r('sys.color.comp_background_tertiary'))
  .selectedColor($r('sys.color.ohos_id_color_emphasize'))

// ========== 间歇滑动 ==========

Slider({
  value: 50,
  min: 0,
  max: 100,
  step: 10,
  style: SliderStyle.InSet
})
  .showSteps(true)
  .trackColor($r('sys.color.comp_background_tertiary'))
  .selectedColor($r('sys.color.ohos_id_color_emphasize'))

// ========== 自定义滑块形状 ==========

Slider({
  value: 50,
  min: 0,
  max: 100,
  step: 10,
  style: SliderStyle.InSet
})
  .selectedColor($r('sys.color.ohos_id_color_emphasize'))
  .trackColor($r('sys.color.comp_background_tertiary'))
  .trackBorderRadius(4)
  .blockSize({ width: 12, height: 12 })
  .blockColor(Color.White)
  .showSteps(true)
  .blockStyle({
    type: SliderBlockType.SHAPE,
    shape: new Rect({ width: 12, height: 12 }).radius(2)
  })

// ========== 带状态Slider ==========

@ComponentV2
struct SliderWithTips {
  @Local tipsValue: number = 40

  build() {
    Slider({
      value: this.tipsValue,
      min: 0,
      max: 100,
      style: SliderStyle.InSet
    })
      .showTips(true, this.tipsValue.toFixed())
      .trackColor($r('sys.color.comp_background_tertiary'))
      .selectedColor($r('sys.color.ohos_id_color_emphasize'))
      .onChange(value => {
        this.tipsValue = value
      })
  }
}