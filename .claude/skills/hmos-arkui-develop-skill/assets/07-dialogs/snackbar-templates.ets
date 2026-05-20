// SnackBar 提示示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/presentation/snackbar

// ========== 基础SnackBar ==========

import {
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarOperationType,
  SnackBarStyleOptions
} from '@kit.UIDesignKit'

@ComponentV2
struct BasicSnackBarExample {
  private uiContext: UIContext | null = null
  private hdsSnackBar: HdsSnackBar | null = null

  private icon: SnackBarIconOptions = {
    icon: $r('sys.symbol.star_circle_fill')
  }

  private message: SnackBarMessageOptions = {
    title: '计划关机'
  }

  private operation: SnackBarOperationOptions = {
    operationType: SnackBarOperationType.TEXT_WITH_ARROW,
    content: 'TEXT BT',
    textButtonId: 'snackBarTextButton',
    onArrowClick: () => {
      console.info('Arrow clicked')
    }
  }

  private style: SnackBarStyleOptions = {
    duration: 2500
  }

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    this.hdsSnackBar = new HdsSnackBar(this.uiContext)
  }

  aboutToDisappear(): void {
    this.hdsSnackBar?.dismiss()
  }

  build() {
    Button('显示SnackBar')
      .onClick(() => {
        this.hdsSnackBar?.show(this.icon, this.message, this.operation, this.style)
      })
  }
}

// ========== 带关闭按钮的SnackBar ==========

private operationWithClose: SnackBarOperationOptions = {
  operationType: SnackBarOperationType.TEXT_WITH_CLOSE,
  content: 'TEXT BT',
  textButtonId: 'snackBarTextButton2',
  onContentClick: () => {
    console.info('Content clicked')
  }
}

// ========== 常驻SnackBar ==========

private residentStyle: SnackBarStyleOptions = {
  duration: -1
}