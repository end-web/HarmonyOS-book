// Button 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/action/button

// ========== 按钮样式 ==========

Button('Emphasized')
  .buttonStyle(ButtonStyleMode.EMPHASIZED)

Button('Normal')
  .buttonStyle(ButtonStyleMode.NORMAL)

Button('Warning')
  .buttonStyle(ButtonStyleMode.NORMAL)
  .role(ButtonRole.ERROR)

Button('Text')
  .buttonStyle(ButtonStyleMode.TEXTUAL)

// ========== 按钮尺寸 ==========

Button('Medium', { controlSize: ControlSize.NORMAL, buttonStyle: ButtonStyleMode.EMPHASIZED })

Button('Small', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.EMPHASIZED })

// ========== 加载状态按钮 ==========

Button({ type: ButtonType.Capsule, stateEffect: true }) {
  Row({ space: 4 }) {
    LoadingProgress()
      .width(24)
      .height(24)
      .color($r('sys.color.font_on_primary'))
    Text('Loading')
      .fontSize($r('sys.float.Body_L'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_on_primary'))
  }
}
.height(40)
.buttonStyle(ButtonStyleMode.EMPHASIZED)

// ========== 禁用状态 ==========

Button('Disable')
  .height(40)
  .buttonStyle(ButtonStyleMode.EMPHASIZED)
  .stateEffect(false)
  .hoverEffect(HoverEffect.None)
  .enabled(false)

// ========== 图标按钮 ==========

Button({ type: ButtonType.Circle }) {
  SymbolGlyph($r('sys.symbol.bell'))
    .fontColor([$r('sys.color.icon_on_primary')])
    .fontSize($r('sys.float.Title_M'))
}
.buttonStyle(ButtonStyleMode.EMPHASIZED)
.width(40)
.height(40)

// ========== 带状态按钮 ==========

@ComponentV2
struct LoadingButtonState {
  @Local isLoading: boolean = false

  build() {
    Button({ type: ButtonType.Capsule }) {
      if (this.isLoading) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color($r('sys.color.font_on_primary'))
      } else {
        Text('Submit')
          .fontColor($r('sys.color.font_on_primary'))
      }
    }
    .height(40)
    .buttonStyle(ButtonStyleMode.EMPHASIZED)
    .enabled(!this.isLoading)
    .onClick(() => {
      this.isLoading = true
    })
  }
}