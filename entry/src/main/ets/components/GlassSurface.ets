import { curves } from '@kit.ArkUI';
import { AppColor, AppMaterial, AppRadius } from '../theme/Theme';

/** 使用系统沉浸材质的轻量玻璃控件表面。 */
@ComponentV2
export struct GlassControlSurface {
  @Param cornerRadius: number = AppRadius.Pill;
  @Param tintColor: ResourceColor = AppColor.GlassControlTint;
  @Param strokeColor: ResourceColor = AppColor.GlassStroke;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .backgroundColor(this.tintColor)
        .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.Center }) {
        this.content()
      }
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.cornerRadius)
      .systemMaterial(AppMaterial.InteractiveClean)

      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(this.cornerRadius)
        .border({ width: 0.5, color: this.strokeColor })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.cornerRadius)
    .clip(true)
  }
}

/** 播放与阅读底部弹层共用的深色玻璃表面。 */
@ComponentV2
export struct GlassSheetSurface {
  @Param cornerRadius: number = 20;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .systemMaterial(AppMaterial.DialogUltraThick)
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .backgroundColor(AppColor.GlassSheetFallback)
        .hitTestBehavior(HitTestMode.None)

      this.content()
    }
    .width('100%')
    .borderRadius({ topLeft: this.cornerRadius, topRight: this.cornerRadius })
    .clip(true)
    .border({ width: 0.5, color: AppColor.GlassSheetStroke })
    .transition(TransitionEffect.OPACITY
      .animation({ curve: curves.springMotion(0.6, 0.9) })
      .combine(TransitionEffect.translate({ y: 1000 })
        .animation({ curve: curves.springMotion(0.6, 0.9) })))
  }
}
