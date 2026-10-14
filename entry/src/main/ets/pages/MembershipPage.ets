import { AppFont, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AppIconPage } from './AppIconPage';

/** 免费主题选择页，沿用原文件与路由名称。 */
@ComponentV2
export struct MembershipPage {
  @Param navStack: NavPathStack = new NavPathStack();
  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([$r('sys.color.font_primary')])
        }.width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.app_icon_back')).onClick(() => this.navStack.pop())
        Text($r('app.string.membership_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })
      Scroll() {
        Column({ space: AppSpace.Lg }) {
          AppIconPage()
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
