import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct TechnicalSupportPage {
  @Param navStack: NavPathStack = new NavPathStack();

  @Builder
  buildSection(title: ResourceStr, names: ResourceStr) {
    Column({ space: AppSpace.Md }) {
      Text(title)
        .fontSize(AppFont.BodyL)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text(names)
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(36)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpace.Lg)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .accessibilityText($r('app.string.common_back'))
          .onClick(() => this.navStack.pop())
        Text($r('app.string.about_technical_support'))
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

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          this.buildSection($r('app.string.technical_support_title'), $r('app.string.technical_support_names'))
          this.buildSection($r('app.string.sponsor_thanks_title'), $r('app.string.sponsor_thanks_names'))
        }
        .width('100%')
        .padding({
          left: AppSpace.Sm, right: AppSpace.Sm,
          bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
