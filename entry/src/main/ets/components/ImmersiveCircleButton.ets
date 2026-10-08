import { HdsTabs } from '@kit.UIDesignKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';

class ImmersiveCircleClip implements AttributeModifier<CommonAttribute> {
  private radius: number;

  constructor(radius: number) { this.radius = radius; }

  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    else node.borderRadius(this.radius);
    node.clip(true);
  }
}

/** HDS 原生浮动栏承载圆形材质，与阅读底栏使用相同渲染路径。 */
@ComponentV2
export struct ImmersiveCircleButton {
  @Param icon: Resource = $r('sys.symbol.arrow_clockwise');
  @Param label: Resource = $r('app.string.content_reload');
  @Param diameter: number = 40;
  @Param iconSize: number = 24;
  /** 图标色；已选态（如已加入书架）传品牌色。 */
  @Param iconColor: ResourceColor = $r('sys.color.font_primary');
  @Event onPress: () => void = () => {};

  @Builder
  materialContent() {
    Stack().width('100%').height('100%')
  }

  @Builder
  iconContent() {
    SymbolGlyph(this.icon)
      .fontSize(this.iconSize)
      .fontColor([this.iconColor]).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(this.diameter).tabBar(this.materialContent())
        }
        .barMode(BarMode.Fixed).barHeight(this.diameter).barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: this.diameter, mediumWidth: this.diameter, largeWidth: this.diameter },
          systemMaterialEffect: HdsCompat.material,
          barSideMargin: 0, barBottomMargin: 0,
          gradientMask: { maskColor: '#00000000', maskHeight: this.diameter },
          adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
        })
        .scrollable(false).onContentWillChange((): boolean => false)
        .width(this.diameter).height(this.diameter)
        Button({ type: ButtonType.Circle, stateEffect: false }) { this.iconContent() }
          .width(this.diameter).height(this.diameter).padding(0).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .accessibilityText(this.label).onClick((): void => this.onPress())
      } else {
        Button({ type: ButtonType.Circle }) { this.iconContent() }
          .width(this.diameter).height(this.diameter).padding(0).backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .accessibilityText(this.label).onClick((): void => this.onPress())
      }
    }.width(this.diameter).height(this.diameter).attributeModifier(new ImmersiveCircleClip(this.diameter / 2))
  }
}
