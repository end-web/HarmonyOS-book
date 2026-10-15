import { AppColor } from '../theme/Theme';

/** 独立的渲染属性动画，不使用 JS 定时器逐帧更新播放页面。 */
@ComponentV2
export struct PlaybackLoadingIndicator {
  @Param indicatorSize: number = 36;
  @Local angle: number = 0;

  build() {
    Progress({ value: 75, total: 100, type: ProgressType.Ring })
      .width(this.indicatorSize)
      .height(this.indicatorSize)
      .color(AppColor.Brand)
      .backgroundColor(Color.Transparent)
      .style({ strokeWidth: 2.5, enableSmoothEffect: false, enableScanEffect: false, shadow: false })
      .rotate({ angle: this.angle })
      .animation({
        duration: 900,
        curve: Curve.Linear,
        iterations: -1,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      })
      .hitTestBehavior(HitTestMode.None)
      .onAppear((): void => { this.angle = 360; })
  }
}
