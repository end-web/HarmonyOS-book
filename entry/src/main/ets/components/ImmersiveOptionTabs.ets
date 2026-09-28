import { AppFont, AppMaterial } from '../theme/Theme';

/** 原生沉浸下拉选项：选项文字随系统深浅模式适配，菜单材质兼容旧系统。 */
@ComponentV2
export struct ImmersiveOptionTabs {
  @Param labels: ResourceStr[] = [];
  @Param selected: number = 0;
  @Param fillWidth: boolean = false;
  @Event onSelect: (index: number) => void = () => {};

  private options(): SelectOption[] {
    return this.labels.map((label: ResourceStr): SelectOption => { return { value: label }; });
  }

  build() {
    Select(this.options())
      .width(this.fillWidth ? '100%' : LayoutPolicy.wrapContent)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .selected(this.selected)
      .value(this.labels[this.selected] ?? '')
      .font({ size: AppFont.Body })
      .fontColor($r('sys.color.font_primary'))
      .optionFont({ size: AppFont.Body })
      .optionFontColor($r('sys.color.font_primary'))
      .selectedOptionFontColor($r('sys.color.font_primary'))
      .selectedOptionBgColor($r('sys.color.comp_background_tertiary'))
      .optionWidth(180)
      .attributeModifier(AppMaterial.selectModifier())
      .onSelect((index: number): void => this.onSelect(index))
  }
}
