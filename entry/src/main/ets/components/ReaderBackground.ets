/** 阅读页与设置预览共用的底色 / 自定义图片背景，图片上保留可调蒙层。 */
import { fileUri } from '@kit.CoreFileKit';
import { ReaderPattern, ReaderPalette, ReaderImageMode } from '../model/ReaderTheme';

@ComponentV2
export struct ReaderBackground {
  @Param palette: ReaderPalette = new ReaderPalette();
  @Param pattern: string = ReaderPattern.None;
  /** 持久化保留沙箱路径，仅显示时转换为 Image 支持的文件 URI。 */
  @Param bgImagePath: string = '';
  @Param imageMode: ReaderImageMode = ReaderImageMode.Cover;
  @Param overlayAlpha: number = 0.35;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.background)

      if (this.pattern === ReaderPattern.Image && this.bgImagePath.length > 0) {
        if (this.imageMode === ReaderImageMode.Tile) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundImage(fileUri.getUriFromPath(this.bgImagePath), ImageRepeat.XY)
            .backgroundImageSize(ImageSize.Auto)
            .backgroundImagePosition(Alignment.TopStart)
        } else {
          Image(fileUri.getUriFromPath(this.bgImagePath))
            .width('100%')
            .height('100%')
            .objectFit(this.imageMode === ReaderImageMode.Contain ? ImageFit.Contain :
              this.imageMode === ReaderImageMode.Stretch ? ImageFit.Fill : ImageFit.Cover)
            .interpolation(ImageInterpolation.Medium)
        }
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette.background)
          .opacity(this.overlayAlpha)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
