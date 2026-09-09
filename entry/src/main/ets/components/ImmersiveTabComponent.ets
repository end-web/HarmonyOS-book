import { AppRadius, AppSpace, AppMotion, AppCurve, AppMaterial, HomeTheme } from '../theme/Theme';

/** 首页与搜索历史共用的原生沉浸材质标签。 */
@ComponentV2
@ReusableV2
export struct ImmersiveTabComponent {
  @Param label: ResourceStr = '';
  @Param selected: boolean = false;
  @Param itemWidth: number = 76;
  @Param fitContent: boolean = false;
  @Event onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(13)
          .fontColor(this.selected ? HomeTheme.Accent : $r('sys.color.font_secondary'))
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width(this.fitContent ? LayoutPolicy.wrapContent : '100%')
          .constraintSize({ maxWidth: this.fitContent ? 176 : this.itemWidth })
          .padding({
            left: this.fitContent ? AppSpace.Sm : AppSpace.Xxs,
            right: this.fitContent ? AppSpace.Sm : AppSpace.Xxs
          })
      }
      .width(this.fitContent ? LayoutPolicy.wrapContent : '100%')
      .height(30)
      .alignItems(VerticalAlign.Center)

      if (this.selected) {
        Row()
          .width(18)
          .height(2)
          .borderRadius(1)
          .backgroundColor(HomeTheme.Accent)
      } else {
        Row()
          .width(18)
          .height(2)
          .opacity(0)
      }
    }
    .width(this.fitContent ? LayoutPolicy.wrapContent : this.itemWidth)
    .height(34)
    .borderRadius(AppRadius.Pill)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .systemMaterial(AppMaterial.InteractiveClean)
    .animation({ duration: AppMotion.Base, curve: AppCurve.Spring })
    .onClick(() => this.onTap())
  }
}

