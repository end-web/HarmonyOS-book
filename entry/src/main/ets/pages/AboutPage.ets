import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct AboutPage {
  @Param navStack: NavPathStack = new NavPathStack();

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('关于')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: AppSpace.Sm })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
      })

      Column({ space: AppSpace.Lg }) {
        Column({ space: AppSpace.Sm }) {
          Image($r('app.media.app_icon_legacy'))
            .width(80)
            .height(80)
            .borderRadius(AppRadius.Xl)
            .clip(true)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })

          Text('ListenBook')
            .fontSize(AppFont.TitleL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Text('v1.0.0')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ top: AppSpace.Xl })

        Column() {
          Row() {
            Text('作者')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('ylwang')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('框架')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('HarmonyOS Next / ArkUI')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('SDK')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('API 12 (6.1.0)')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('隐私政策')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_tertiary')])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('privacy', ''))
        }
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Lg)
        .margin({ left: AppSpace.Sm, right: AppSpace.Sm })

        Text('纯血鸿蒙听书应用')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
