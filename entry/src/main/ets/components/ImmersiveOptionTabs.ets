import { AppColor, AppFont, AppMaterial } from '../theme/Theme';

/** 原生沉浸下拉选项：选中行随主题色高亮，菜单材质兼容旧系统。 */
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
      .selected(this.selected)
      .value(this.labels[this.selected] ?? '')
      .font({ size: AppFont.Body })
      .fontColor(AppColor.Brand)
      .optionFont({ size: AppFont.Body })
      .optionFontColor($r('sys.color.font_primary'))
      .selectedOptionFontColor(AppColor.Brand)
      .selectedOptionBgColor(AppColor.BrandSoft)
      .optionWidth(180)
      .attributeModifier(AppMaterial.selectModifier())
      .onSelect((index: number): void => this.onSelect(index))
  }
}
