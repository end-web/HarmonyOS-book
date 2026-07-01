import { AppFont, AppMotion, AppCurve } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

interface TabItem {
  id: number;
  label: string;
  symbol: Resource;
  symbolFill: Resource;
}

const TABS: TabItem[] = [
  { id: 0, label: '首页', symbol: $r('sys.symbol.house'), symbolFill: $r('sys.symbol.house_fill') },
  { id: 1, label: '书架', symbol: $r('sys.symbol.heart'), symbolFill: $r('sys.symbol.heart_fill') },
  { id: 2, label: '记录', symbol: $r('sys.symbol.clock'), symbolFill: $r('sys.symbol.clock_fill') },
  { id: 3, label: '我的', symbol: $r('sys.symbol.person'), symbolFill: $r('sys.symbol.person_fill') }
];

@ComponentV2
export struct FloatingTabBar {
  @Param selectedIndex: number = 0;
  @Event onTabChange: (index: number) => void = () => {};

  build() {
    Row() {
      ForEach(TABS, (tab: TabItem) => {
        Column({ space: 8 }) {
          SymbolGlyph(this.selectedIndex === tab.id ? tab.symbolFill : tab.symbol)
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .scale({
              x: this.selectedIndex === tab.id ? 1.12 : 1,
              y: this.selectedIndex === tab.id ? 1.12 : 1
            })
            .animation({ duration: AppMotion.Base, curve: AppCurve.Spring })

          Text(tab.label)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_primary'))
            .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 8 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        .onClick(() => this.onTabChange(tab.id))
      }, (tab: TabItem) => tab.id.toString())
    }
    .width('100%')
    .height(64)
    .backgroundColor($r('sys.color.background_primary'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
    .padding({ bottom: WindowUtils.getBottomSafeVp() })
  }
}
