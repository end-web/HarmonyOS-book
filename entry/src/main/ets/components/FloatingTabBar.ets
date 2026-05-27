import { AppColor, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';
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
  { id: 2, label: '我的', symbol: $r('sys.symbol.person'), symbolFill: $r('sys.symbol.person_fill') }
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
            .fontColor([this.selectedIndex === tab.id ? AppColor.Brand : '#999999'])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .scale({
              x: this.selectedIndex === tab.id ? 1.12 : 1,
              y: this.selectedIndex === tab.id ? 1.12 : 1
            })
            .animation({ duration: AppMotion.Base, curve: AppCurve.Spring })

          Text(tab.label)
            .fontSize(AppFont.Caption)
            .fontColor(this.selectedIndex === tab.id ? AppColor.Brand : '#999999')
            .opacity(this.selectedIndex === tab.id ? 1 : 0.8)
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
    .backgroundColor('#CCFFFFFF')
    .backdropBlur(25)
    .border({ width: { top: 0.5 }, color: '#1A000000' })
    .padding({ bottom: WindowUtils.getBottomSafeVp() })
  }
}
