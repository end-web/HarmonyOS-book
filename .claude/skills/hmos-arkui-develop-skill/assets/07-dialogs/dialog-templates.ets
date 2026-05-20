// Dialog 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/container/dialog

// ========== 基础对话框 ==========

@ComponentV2
struct BasicDialogExample {
  private dialogController: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.dialogController = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: '标题',
        contentBuilder: () => {
          this.buildContent()
        },
        buttons: [
          {
            value: '取消',
            buttonStyle: ButtonStyleMode.TEXTUAL
          },
          {
            value: '确定',
            buttonStyle: ButtonStyleMode.TEXTUAL
          }
        ]
      })
    })
  }

  @Builder
  buildContent(): void {
    Column() {
      Text('对话框内容')
        .fontColor($r('sys.color.font_emphasize'))
    }
    .width('100%')
    .height(80)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Button('显示对话框')
      .onClick(() => {
        this.dialogController?.open()
      })
  }
}

// ========== 双行标题对话框 ==========

new CustomDialogController({
  builder: CustomContentDialog({
    primaryTitle: '主标题',
    secondaryTitle: '副标题',
    contentBuilder: () => {
      Column() {
        Text('内容')
      }
    },
    buttons: [
      { value: '取消', buttonStyle: ButtonStyleMode.TEXTUAL },
      { value: '确定', buttonStyle: ButtonStyleMode.TEXTUAL }
    ]
  })
})

// ========== 三按钮对话框 ==========

new CustomDialogController({
  builder: CustomContentDialog({
    primaryTitle: '标题',
    contentBuilder: () => {
      Column() {
        Text('内容')
      }
    },
    buttons: [
      { value: '按钮1', buttonStyle: ButtonStyleMode.EMPHASIZED },
      { value: '按钮2', buttonStyle: ButtonStyleMode.TEXTUAL },
      { value: '按钮3', buttonStyle: ButtonStyleMode.TEXTUAL }
    ]
  })
})

// ========== 带单选的对话框 ==========

@ComponentV2
struct MessageDialogExample {
  @Local isRadioChecked: boolean = false
  private dialogController: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.dialogController = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: '信息对话框',
        contentBuilder: () => {
          Column() {
            Text('消息内容')
              .fontSize($r('sys.float.Body_L'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))

            Row() {
              Radio({ value: 'Radio', group: 'radioGroup' })
                .checked(this.isRadioChecked)
              Text('选项内容')
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
            }
            .width('100%')
            .onClick(() => {
              this.isRadioChecked = !this.isRadioChecked
            })
          }
          .width('100%')
        },
        buttons: [
          { value: '取消', buttonStyle: ButtonStyleMode.TEXTUAL }
        ]
      })
    })
  }

  build() {
    Button('显示对话框')
      .onClick(() => {
        this.dialogController?.open()
      })
  }
}