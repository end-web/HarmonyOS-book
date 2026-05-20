// Toggle 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/select/toggle

// ========== 默认开关 ==========

Toggle({ type: ToggleType.Switch, isOn: true })
  .selectedColor($r('sys.color.ohos_id_color_emphasize'))
  .switchPointColor($r('sys.color.ohos_id_color_foreground_contrary'))

// ========== 自定义颜色和圆角 ==========

Toggle({ type: ToggleType.Switch, isOn: true })
  .selectedColor($r('sys.color.multi_color_02'))
  .switchStyle({
    pointRadius: 8,
    trackBorderRadius: 4,
    unselectedColor: Color.Grey
  })

// ========== 自定义尺寸 ==========

Toggle({ type: ToggleType.Switch, isOn: true })
  .width(28)
  .height(10)
  .selectedColor($r('app.color.multi_color_08'))
  .switchStyle({
    pointRadius: 8,
    trackBorderRadius: 12,
    pointColor: $r('sys.color.multi_color_08')
  })

// ========== 带状态Toggle ==========

@ComponentV2
struct ToggleWithState {
  @Local isOn: boolean = true

  build() {
    Toggle({ type: ToggleType.Switch, isOn: this.isOn })
      .selectedColor($r('sys.color.ohos_id_color_emphasize'))
      .switchPointColor($r('sys.color.ohos_id_color_foreground_contrary'))
      .onChange((isOn: boolean) => {
        this.isOn = isOn
      })
  }
}