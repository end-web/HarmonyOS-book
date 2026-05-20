// Toast 提示示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/presentation/toast

// ========== 基础Toast ==========

@ComponentV2
struct BasicToastExample {
  private promptAction: PromptAction | undefined = undefined

  aboutToAppear(): void {
    this.promptAction = this.getUIContext().getPromptAction()
  }

  build() {
    Button('显示Toast')
      .onClick(() => {
        this.promptAction?.openToast({
          message: '当前信号较弱',
          duration: 3000
        })
      })
  }
}

// ========== 底部Toast ==========

this.promptAction.openToast({
  message: '提示信息',
  duration: 3000
})

// ========== 指定位置Toast ==========

this.promptAction.openToast({
  message: '提示信息',
  duration: 3000,
  layoutDirection: ToastLayoutDirection.TOP
})

// ========== 关闭Toast ==========

@ComponentV2
struct ToastWithClose {
  @Local toastId: number = -1
  private promptAction: PromptAction | undefined = undefined

  aboutToAppear(): void {
    this.promptAction = this.getUIContext().getPromptAction()
  }

  aboutToDisappear(): void {
    if (this.toastId !== -1) {
      this.promptAction?.closeToast(this.toastId)
    }
  }

  build() {
    Column() {
      Button('显示Toast')
        .onClick(() => {
          this.promptAction?.openToast({
            message: '提示信息',
            duration: 3000
          }).then((toastId: number) => {
            this.toastId = toastId
          })
        })

      Button('关闭Toast')
        .onClick(() => {
          if (this.toastId !== -1) {
            this.promptAction?.closeToast(this.toastId)
            this.toastId = -1
          }
        })
    }
  }
}