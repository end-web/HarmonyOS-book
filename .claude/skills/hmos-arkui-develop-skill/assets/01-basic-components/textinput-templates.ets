// TextInput/TextArea 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/input/textbox

// ========== 单行输入 ==========

TextInput({ placeholder: '请输入内容' })
  .width('100%')
  .showUnderline(true)
  .underlineColor({
    normal: $r('sys.color.comp_divider'),
    typing: $r('app.color.text_box_typing_color'),
    error: $r('sys.color.warning'),
    disable: Color.Gray
  })

// ========== 带图标输入 ==========

Stack({ alignContent: Alignment.Start }) {
  TextInput({ placeholder: '请输入内容' })
    .width('100%')
    .showUnderline(true)
    .underlineColor({
      normal: $r('sys.color.comp_divider'),
      typing: $r('app.color.text_box_typing_color'),
      error: $r('sys.color.warning'),
      disable: Color.Gray
    })
    .padding({ left: 32 })

  SymbolGlyph($r('sys.symbol.person'))
    .fontColor([$r('sys.color.icon_secondary')])
    .fontSize($r('sys.float.Title_M'))
}

// ========== 密码输入 ==========

TextInput({ text: '', placeholder: '请输入密码' })
  .type(InputType.Password)
  .showPassword(true)
  .showUnderline(true)
  .underlineColor({
    normal: $r('sys.color.comp_divider'),
    typing: $r('app.color.text_box_typing_color'),
    error: $r('sys.color.warning'),
    disable: Color.Gray
  })

// ========== 多行输入 ==========

TextArea({
  text: '',
  placeholder: '请输入内容...'
})
  .width('100%')
  .maxLength(100)
  .showCounter(true, { thresholdPercentage: 80, highlightBorder: true })

// ========== 带错误提示 ==========

@ComponentV2
struct TextInputWithError {
  @Local errMsg: ResourceStr | undefined
  @Local text: string = ''

  build() {
    TextInput({ text: this.text, placeholder: '请输入内容' })
      .width('100%')
      .showUnderline(true)
      .underlineColor({
        normal: $r('sys.color.comp_divider'),
        typing: $r('app.color.text_box_typing_color'),
        error: $r('sys.color.warning')
      })
      .showError(this.errMsg)
      .onChange((value) => {
        this.text = value
        if (value.length < 6) {
          this.errMsg = '输入内容太短'
        } else {
          this.errMsg = undefined
        }
      })
  }
}