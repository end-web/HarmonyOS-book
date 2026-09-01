/**
 * ReaderBackground - 阅读页背景层
 *
 * 按 pattern 分四种绘制：
 *   none  → 纯底色
 *   paper → 底色 + 程序化纸纤维纹（多档低透明度斜向条带 + 暖角渐晕）
 *   cloth → 底色 + 交叉双向条带模拟织纹
 *   image → 用户相册图铺满 + 底色蒙层（浓度可调，保证正文可读）
 *
 * 纹理不用位图资源：仓库不塞二进制，且渐变随底色走，换主题时纹理自动跟着变。
 * 设置页预览卡与阅读页正文共用本组件，所见即所得。
 */
import { ReaderPattern, ReaderPalette } from '../model/ReaderTheme';

@ComponentV2
export struct ReaderBackground {
  /** 当前配色 */
  @Param palette: ReaderPalette = new ReaderPalette();
  /** 背景图案 */
  @Param pattern: string = ReaderPattern.None;
  /** pattern=image 时的沙箱图片路径 */
  @Param bgImagePath: string = '';
  /** 图片上的底色蒙层浓度 0~0.85 */
  @Param overlayAlpha: number = 0.35;

  /** 纹理条带用底色的反相微调，深底加亮、浅底压暗 */
  private fiberColor(alpha: number): string {
    const a = Math.max(0, Math.min(255, Math.round(alpha * 255)));
    const prefix = `#${a.toString(16).padStart(2, '0').toUpperCase()}`;
    return this.palette.isDark ? `${prefix}FFFFFF` : `${prefix}6B5A3E`;
  }

  build() {
    Stack() {
      // 1. 底色永远铺满，图片加载失败时它就是兜底
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.background)

      // 2. 用户相册图
      if (this.pattern === ReaderPattern.Image && this.bgImagePath.length > 0) {
        Image(this.bgImagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          // 解码失败不抛错，保持底色
          .onError(() => {})
        // 底色蒙层：正文可读性靠这层保证
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette.background)
          .opacity(this.overlayAlpha)
      }

      // 3. 纸纤维纹：斜向细条带 + 角落渐晕
      if (this.pattern === ReaderPattern.Paper) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 100,
            colors: [
              [this.fiberColor(0.05), 0.0],
              [this.fiberColor(0.0), 0.06],
              [this.fiberColor(0.04), 0.13],
              [this.fiberColor(0.0), 0.21],
              [this.fiberColor(0.05), 0.3],
              [this.fiberColor(0.0), 0.38],
              [this.fiberColor(0.03), 0.47],
              [this.fiberColor(0.0), 0.56],
              [this.fiberColor(0.05), 0.65],
              [this.fiberColor(0.0), 0.74],
              [this.fiberColor(0.04), 0.83],
              [this.fiberColor(0.0), 0.92],
              [this.fiberColor(0.03), 1.0]
            ]
          })
        // 暖角渐晕，让整页不那么平
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 160,
            colors: [
              [this.fiberColor(0.06), 0.0],
              [this.fiberColor(0.0), 0.35],
              [this.fiberColor(0.0), 0.7],
              [this.fiberColor(0.07), 1.0]
            ]
          })
      }

      // 4. 织纹：横竖两组条带交叉
      if (this.pattern === ReaderPattern.Cloth) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [
              [this.fiberColor(0.05), 0.0],
              [this.fiberColor(0.0), 0.04],
              [this.fiberColor(0.05), 0.08],
              [this.fiberColor(0.0), 0.12],
              [this.fiberColor(0.05), 0.16],
              [this.fiberColor(0.0), 0.2],
              [this.fiberColor(0.05), 0.24],
              [this.fiberColor(0.0), 0.28],
              [this.fiberColor(0.05), 0.32],
              [this.fiberColor(0.0), 0.36],
              [this.fiberColor(0.05), 0.4],
              [this.fiberColor(0.0), 0.44],
              [this.fiberColor(0.05), 0.48],
              [this.fiberColor(0.0), 0.52],
              [this.fiberColor(0.05), 0.56],
              [this.fiberColor(0.0), 0.6],
              [this.fiberColor(0.05), 0.64],
              [this.fiberColor(0.0), 0.68],
              [this.fiberColor(0.05), 0.72],
              [this.fiberColor(0.0), 0.76],
              [this.fiberColor(0.05), 0.8],
              [this.fiberColor(0.0), 0.84],
              [this.fiberColor(0.05), 0.88],
              [this.fiberColor(0.0), 0.92],
              [this.fiberColor(0.05), 0.96],
              [this.fiberColor(0.0), 1.0]
            ]
          })
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 0,
            colors: [
              [this.fiberColor(0.04), 0.0],
              [this.fiberColor(0.0), 0.04],
              [this.fiberColor(0.04), 0.08],
              [this.fiberColor(0.0), 0.12],
              [this.fiberColor(0.04), 0.16],
              [this.fiberColor(0.0), 0.2],
              [this.fiberColor(0.04), 0.24],
              [this.fiberColor(0.0), 0.28],
              [this.fiberColor(0.04), 0.32],
              [this.fiberColor(0.0), 0.36],
              [this.fiberColor(0.04), 0.4],
              [this.fiberColor(0.0), 0.44],
              [this.fiberColor(0.04), 0.48],
              [this.fiberColor(0.0), 0.52],
              [this.fiberColor(0.04), 0.56],
              [this.fiberColor(0.0), 0.6],
              [this.fiberColor(0.04), 0.64],
              [this.fiberColor(0.0), 0.68],
              [this.fiberColor(0.04), 0.72],
              [this.fiberColor(0.0), 0.76],
              [this.fiberColor(0.04), 0.8],
              [this.fiberColor(0.0), 0.84],
              [this.fiberColor(0.04), 0.88],
              [this.fiberColor(0.0), 0.92],
              [this.fiberColor(0.04), 0.96],
              [this.fiberColor(0.0), 1.0]
            ]
          })
      }
    }
    .width('100%')
    .height('100%')
  }
}
