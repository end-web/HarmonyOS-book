import { AppColor, AppFont, AppSpace } from '../theme/Theme';

/**
 * 详情页操作行单元：图标 + 文案，选中态（如已加入书架）整体走主题色。
 *
 * 为什么做成组件而不是页面里的 @Builder：
 * @Builder 按值传参时参数变化不会触发 UI 刷新（ArkUI 既定行为），
 * 会出现「爱心已经变成实心，操作行的书架图标却还是旧图标」这种半刷新状态。
 * @ComponentV2 的 @Param 是响应式的，能从根上避免这个问题。
 */
@ComponentV2
export struct DetailActionItem {
  @Param icon: Resource = $r('sys.symbol.list_bullet');
  @Param label: ResourceStr = '';
  @Param active: boolean = false;
  @Event onTap: () => void = () => {};

  build() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph(this.icon)
        .fontSize(22)
        .fontColor([this.active ? AppColor.Brand : $r('sys.color.font_primary')])
      Text(this.label)
        .fontSize(AppFont.Caption)
        .fontColor(this.active ? AppColor.Brand : $r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick((): void => this.onTap())
  }
}
