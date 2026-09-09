import { AppAppearance } from '../model/AppAppearance';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace } from '../theme/Theme';

class MaterialChoice {
  value: number;
  label: Resource;
  constructor(value: number, label: Resource) {
    this.value = value;
    this.label = label;
  }
}

class AccentChoice {
  color: string;
  label: Resource;
  constructor(color: string, label: Resource) {
    this.color = color;
    this.label = label;
  }
}

const MATERIAL_CHOICES: MaterialChoice[] = [
  new MaterialChoice(0, $r('app.string.appearance_material_default')),
  new MaterialChoice(1, $r('app.string.appearance_material_ultra_thin')),
  new MaterialChoice(2, $r('app.string.appearance_material_thin')),
  new MaterialChoice(3, $r('app.string.appearance_material_regular')),
  new MaterialChoice(4, $r('app.string.appearance_material_thick')),
  new MaterialChoice(5, $r('app.string.appearance_material_ultra_thick'))
];

const ACCENT_CHOICES: AccentChoice[] = [
  new AccentChoice('', $r('app.string.appearance_accent_default')),
  new AccentChoice('#C4475B', $r('app.string.appearance_accent_rose')),
  new AccentChoice('#8E55B8', $r('app.string.appearance_accent_purple')),
  new AccentChoice('#2869B8', $r('app.string.appearance_accent_blue')),
  new AccentChoice('#008577', $r('app.string.appearance_accent_teal')),
  new AccentChoice('#557C36', $r('app.string.appearance_accent_green'))
];

/** 仅由系统设置页使用；通过共享 V2 外观状态即时刷新控件。 */
@ComponentV2
export struct AppearanceSettingsComponent {
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local showMaterial: boolean = false;
  @Local showAccent: boolean = false;
  @Local customHex: string = '';
  @Local colorInvalid: boolean = false;
  @Local saving: boolean = false;

  private async applyMaterial(value: number): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await PreferenceService.setMaterialStyle(value);
    } catch (_e) {
      this.showSaveError();
    } finally {
      this.saving = false;
    }
  }

  private async applyAccent(value: string): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await PreferenceService.setAccentColor(value);
      this.customHex = value || '#FF6B3D';
      this.colorInvalid = false;
    } catch (_e) {
      this.showSaveError();
    } finally {
      this.saving = false;
    }
  }

  private applyCustomAccent(): void {
    const normalized: string = AppAppearance.normalizeAccent(this.customHex);
    this.colorInvalid = normalized.length === 0;
    if (!this.colorInvalid) this.applyAccent(normalized);
  }

  private showSaveError(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.appearance_save_failed') });
    } catch (_e) { /* 页面关闭后无需提示。 */ }
  }

  @Builder
  divider() {
    Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ left: AppSpace.Md })
  }

  @Builder
  materialSheet() {
    Column({ space: AppSpace.Xs }) {
      Text($r('app.string.appearance_material_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ bottom: AppSpace.Xs })
      ForEach(MATERIAL_CHOICES, (choice: MaterialChoice) => {
        Row() {
          Text(choice.label)
            .fontSize(AppFont.BodyL)
            .fontColor(this.appearance.material === choice.value ? AppColor.Brand : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (this.appearance.material === choice.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([AppColor.Brand])
          }
        }
        .width('100%')
        .padding(AppSpace.Sm)
        .constraintSize({ minHeight: 48 })
        .borderRadius(AppRadius.Md)
        .backgroundColor(this.appearance.material === choice.value ? AppColor.BrandSoft : Color.Transparent)
        .enabled(!this.saving)
        .onClick(() => this.applyMaterial(choice.value))
      }, (choice: MaterialChoice) => choice.value.toString())
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg })
  }

  @Builder
  accentSheet() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.appearance_accent_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(ACCENT_CHOICES, (choice: AccentChoice) => {
          Column({ space: AppSpace.Xs }) {
            Stack() {
              Circle().width(42).height(42).fill(choice.color || '#FF6B3D')
              if (this.appearance.accent === choice.color) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(20)
                  .fontColor([AppAppearance.foreground(choice.color || '#FF6B3D')])
              }
            }
            Text(choice.label).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
          }
          .width('30%')
          .padding({ top: AppSpace.Xs, bottom: AppSpace.Sm })
          .enabled(!this.saving)
          .onClick(() => this.applyAccent(choice.color))
        }, (choice: AccentChoice) => choice.color || 'default')
      }
      Row({ space: AppSpace.Sm }) {
        TextInput({ text: this.customHex, placeholder: $r('app.string.appearance_accent_hex_hint') })
          .layoutWeight(1)
          .maxLength(7)
          .onChange((value: string) => {
            this.customHex = value;
            this.colorInvalid = false;
          })
          .onSubmit(() => this.applyCustomAccent())
        Button($r('app.string.appearance_apply'))
          .backgroundColor(AppColor.Brand)
          .fontColor(AppColor.OnBrand)
          .enabled(!this.saving)
          .onClick(() => this.applyCustomAccent())
      }
      .width('100%')
      if (this.colorInvalid) {
        Text($r('app.string.appearance_accent_invalid'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg })
  }

  build() {
    Column() {
      this.divider()
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_material')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Text(MATERIAL_CHOICES[this.appearance.material].label).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%').padding(AppSpace.Md).constraintSize({ minHeight: 56 })
      .onClick(() => { this.showMaterial = true; })
      .bindSheet($$this.showMaterial, this.materialSheet(), {
        height: SheetSize.FIT_CONTENT,
        preferType: SheetType.BOTTOM,
        title: { title: $r('app.string.appearance_material') },
        backgroundColor: Color.Transparent,
        systemMaterial: AppMaterial.Sheet
      })
      this.divider()
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.appearance_accent')).fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Circle().width(22).height(22).fill(AppColor.Brand)
        Text(this.appearance.accent || $r('app.string.appearance_accent_default')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%').padding(AppSpace.Md).constraintSize({ minHeight: 56 })
      .onClick(() => {
        this.customHex = this.appearance.accent || '#FF6B3D';
        this.colorInvalid = false;
        this.showAccent = true;
      })
      .bindSheet($$this.showAccent, this.accentSheet(), {
        height: SheetSize.FIT_CONTENT,
        preferType: SheetType.BOTTOM,
        title: { title: $r('app.string.appearance_accent') },
        backgroundColor: Color.Transparent,
        systemMaterial: AppMaterial.Sheet
      })
    }
    .width('100%')
  }
}
