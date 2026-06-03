import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

export enum AppButtonVariant {
  Primary = 0,
  Secondary = 1,
  Ghost = 2,
}

export enum AppButtonSize {
  Md = 0,
  Sm = 1,
}

@ComponentV2
export struct AppButton {
  @Param label: string = '';
  @Param variant: AppButtonVariant = AppButtonVariant.Primary;
  @Param btnSize: AppButtonSize = AppButtonSize.Md;
  @Param disabled: boolean = false;
  @Param loading: boolean = false;
  @Param fullWidth: boolean = false;
  @Param leadingIcon: Resource | null = null;
  @Event onTap: () => void = () => {};

  @Local pressed: boolean = false;

  build() {
    Button() {
      Stack() {
        if (this.loading) {
          LoadingProgress()
            .width(this.btnSize === AppButtonSize.Md ? 18 : 14)
            .height(this.btnSize === AppButtonSize.Md ? 18 : 14)
            .color(this.fgColor())
        } else {
          Row({ space: AppSpace.Xs }) {
            if (this.leadingIcon) {
              SymbolGlyph(this.leadingIcon)
                .fontSize(this.btnSize === AppButtonSize.Md ? 16 : 14)
                .fontColor([this.fgColor()])
            }
            Text(this.label)
              .fontSize(this.btnSize === AppButtonSize.Md ? AppFont.Body : 13)
              .fontColor(this.fgColor())
              .fontWeight(FontWeight.Bold)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width(this.fullWidth ? '100%' : undefined)
    .height(this.btnSize === AppButtonSize.Md ? 40 : 32)
    .padding({
      left: this.btnSize === AppButtonSize.Md ? 20 : 16,
      right: this.btnSize === AppButtonSize.Md ? 20 : 16
    })
    .backgroundColor(this.bgColor())
    .borderRadius(AppRadius.Pill)
    .borderWidth(this.variant === AppButtonVariant.Ghost ? 1 : 0)
    .borderColor(this.variant === AppButtonVariant.Ghost ? AppColor.Brand : Color.Transparent)
    .stateEffect(false)
    .enabled(!this.disabled && !this.loading)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.disabled || this.loading) return;
      this.onTap();
    })
  }

  private bgColor(): ResourceColor {
    if (this.disabled) {
      if (this.variant === AppButtonVariant.Primary) return AppColor.BrandDisabled;
      return Color.Transparent;
    }
    if (this.variant === AppButtonVariant.Primary) {
      return this.pressed ? AppColor.BrandPressed : AppColor.Brand;
    }
    if (this.variant === AppButtonVariant.Secondary) {
      return AppColor.BrandSoft;
    }
    return this.pressed ? AppColor.BrandSoft : Color.Transparent;
  }

  private fgColor(): ResourceColor {
    if (this.disabled) {
      if (this.variant === AppButtonVariant.Primary) return AppColor.OnBrand;
      return $r('sys.color.font_tertiary');
    }
    if (this.variant === AppButtonVariant.Primary) return AppColor.OnBrand;
    return AppColor.Brand;
  }
}
