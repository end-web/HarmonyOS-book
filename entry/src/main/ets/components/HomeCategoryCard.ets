import { AppCurve, AppRadius, AppSpace } from '../theme/Theme';

/** 分类总览卡片进入可见区域后按阅读顺序浮现，不为整份分类表创建定时器。 */
@ComponentV2
export struct HomeCategoryCard {
  @Param label: string = '';
  @Param cardColor: ResourceColor = Color.Transparent;
  @Param indexHint: number = 0;
  @Event onTap: () => void = () => {};
  @Local entered: boolean = false;

  private reveal(): void {
    if (this.entered) return;
    // 首屏逐项错开；后续懒加载行只区分左右列，避免越往下等待越久。
    const delay: number = (this.indexHint < 12 ? this.indexHint : this.indexHint % 2) * 45;
    this.getUIContext().animateTo({ duration: 420, delay: delay, curve: AppCurve.Decelerate }, () => {
      this.entered = true;
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      SymbolGlyph($r('sys.symbol.square_grid_2x2'))
        .fontSize(56).fontColor([Color.White]).opacity(0.16)
        .rotate({ angle: -12 }).margin({ right: AppSpace.Sm, bottom: AppSpace.Sm })
      Column() {
        Text(this.label)
          .fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16).fontColor([Color.White]).opacity(0.9)
      }
      .width('100%').height('100%').padding(AppSpace.Md)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height(112).borderRadius(AppRadius.Md)
    .backgroundColor(this.cardColor)
    .clip(true)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 18 })
    .scale({ x: this.entered ? 1 : 0.97, y: this.entered ? 1 : 0.97 })
    .onVisibleAreaChange([0.01], (visible: boolean, ratio: number): void => {
      if (visible && ratio > 0) this.reveal();
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .accessibilityGroup(true).accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}
