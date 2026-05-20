// Progress 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/presentation/progress

// ========== 线性进度条 ==========

Progress({ value: 30, total: 100, type: ProgressType.Linear })
  .width('100%')

// ========== 环形进度条 ==========

Progress({ value: 60, total: 100, type: ProgressType.Ring })
  .width(60)
  .height(60)

// ========== 圆形进度条 ==========

Progress({ value: 70, total: 100, type: ProgressType.Eclipse })
  .width(48)
  .height(48)

// ========== 胶囊进度条 ==========

Progress({ value: 50, total: 100, type: ProgressType.Capsule })
  .width(72)
  .height(28)
  .style({
    borderColor: $r('app.color.capsule_progress_border_color'),
    borderWidth: 1,
    font: {
      size: $r('sys.float.Body_M'),
      weight: FontWeight.Medium
    },
    fontColor: $r('sys.color.font_primary'),
    enableScanEffect: false,
    showDefaultPercentage: true
  })

// ========== LoadingProgress ==========

LoadingProgress()
  .width(24)
  .height(24)
  .color($r('sys.color.icon_tertiary'))

// ========== 组件组合场景 ==========

Row() {
  Text('加载中...')
    .fontSize($r('sys.float.Subtitle_M'))
    .fontColor($r('sys.color.font_primary'))

  LoadingProgress()
    .width(24)
    .height(24)
    .color($r('sys.color.icon_tertiary'))
}

// ========== 动态进度条 ==========

@ComponentV2
struct LinearProgressDynamic {
  @Local currentProgress: number = 0
  private total: number = 100
  private intervalId: number = -1

  aboutToDisappear() {
    if (this.intervalId !== -1) {
      clearInterval(this.intervalId)
    }
  }

  build() {
    Column() {
      Row() {
        Text(this.currentProgress < this.total ? '下载中' : '完成')
          .fontSize($r('sys.float.Subtitle_S'))
          .fontColor($r('sys.color.font_secondary'))
        Text(`${this.currentProgress}%`)
          .fontSize($r('sys.float.Subtitle_S'))
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Progress({ value: this.currentProgress, total: this.total, type: ProgressType.Linear })
        .width('100%')
    }
  }
}