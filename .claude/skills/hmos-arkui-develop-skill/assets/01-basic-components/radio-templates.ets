// Radio 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/select/radio

// ========== DOT样式 ==========

Radio({
  value: 'Radio1',
  group: 'dotRadioGroup',
  indicatorType: RadioIndicatorType.DOT
})

Radio({
  value: 'Radio2',
  group: 'dotRadioGroup',
  indicatorType: RadioIndicatorType.DOT
}).checked(true)

// ========== TICK样式 ==========

Radio({
  value: 'Radio1',
  group: 'tickRadioGroup',
  indicatorType: RadioIndicatorType.TICK
}).checked(true)

Radio({
  value: 'Radio2',
  group: 'tickRadioGroup',
  indicatorType: RadioIndicatorType.TICK
})

// ========== 带状态Radio ==========

@ComponentV2
struct DotRadioGroup {
  @Local radioVal1: Resource = $r('app.string.selected_label')
  @Local radioVal2: Resource = $r('app.string.not_selected_label')

  build() {
    Row() {
      Column({ space: 4 }) {
        Text(this.radioVal1)
          .fontColor($r('sys.color.font_primary'))
        Radio({
          value: 'Radio1',
          group: 'dotRadioGroup',
          indicatorType: RadioIndicatorType.DOT
        }).checked(true)
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.radioVal1 = $r('app.string.selected_label')
            } else {
              this.radioVal1 = $r('app.string.not_selected_label')
            }
          })
      }

      Column({ space: 4 }) {
        Text(this.radioVal2)
          .fontColor($r('sys.color.font_primary'))
        Radio({
          value: 'Radio2',
          group: 'dotRadioGroup',
          indicatorType: RadioIndicatorType.DOT
        }).checked(false)
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.radioVal2 = $r('app.string.selected_label')
            } else {
              this.radioVal2 = $r('app.string.not_selected_label')
            }
          })
      }
    }
  }
}