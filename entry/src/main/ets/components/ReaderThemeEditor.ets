import { ReaderColorPalette } from './ReaderColorPalette';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { TextReadingSettings } from '../model/TextReading';
import { ReaderThemeId, resolvePalette, readerColorContrast, recommendedReaderFontColor } from '../model/ReaderTheme';

/** 草稿只在本组件内存在；返回、关闭弹层与取消都不会更改阅读设置。 */
@ComponentV2
export struct ReaderThemeEditor {
  @Param themeSlot: number = 0;
  @Param themeBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Param fontColor: string = '';
  @Param fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Event onSave: (background: string, fontColor: string) => void = () => {};
  @Event onCancel: () => void = () => {};
  @Local draftBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local draftFontColor: string = '#2D2925';
  @Local editingBackground: boolean = false;
  @Local colorInputValid: boolean = true;
  @Local colorInputRevision: number = 0;

  aboutToAppear(): void {
    this.draftBackground = this.themeBackground;
    this.draftFontColor = resolvePalette(ReaderThemeId.Custom, this.themeBackground, this.fontColor).primary;
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.reader_custom_theme_edit_slot', this.themeSlot + 1))
        .fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).width('100%')
      Scroll() {
        Column({ space: AppSpace.Md }) {
          Column({ space: AppSpace.Sm }) {
            Text($r('app.string.reader_theme_preview_title'))
              .fontSize(AppFont.Caption).fontColor(this.draftFontColor).width('100%')
            Text($r('app.string.reader_theme_preview_text'))
              .fontSize(this.fontSize).fontColor(this.draftFontColor)
              .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
              .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
              .lineHeight(this.fontSize * this.lineHeight).maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg)
          .backgroundColor(this.draftBackground)
          .border({ width: 0.5, color: AppColor.GlassSheetStroke })

          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.reader_font_color'))
              .layoutWeight(1).fontColor($r('sys.color.font_primary'))
              .backgroundColor(AppColor.GlassSheetControlTint)
              .border({ width: this.editingBackground ? 0 : 1, color: AppColor.Brand })
              .onClick((): void => { this.editingBackground = false; this.colorInputValid = true; })
            Button($r('app.string.reader_background_color'))
              .layoutWeight(1).fontColor($r('sys.color.font_primary'))
              .backgroundColor(AppColor.GlassSheetControlTint)
              .border({ width: this.editingBackground ? 1 : 0, color: AppColor.Brand })
              .onClick((): void => { this.editingBackground = true; this.colorInputValid = true; })
          }.width('100%')
          Text(this.editingBackground ? $r('app.string.reader_editing_background_color') :
            $r('app.string.reader_editing_font_color'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
          // 分支重建调色盘，避免两种颜色共用上次保留的灰阶色相。
          if (this.editingBackground) {
            ReaderColorPalette({ color: this.draftBackground, resetRevision: this.colorInputRevision,
              onValidityChange: (valid: boolean): void => { this.colorInputValid = valid; },
              onChange: (color: string): void => { this.draftBackground = color; } })
          } else {
            ReaderColorPalette({ color: this.draftFontColor, resetRevision: this.colorInputRevision,
              onValidityChange: (valid: boolean): void => { this.colorInputValid = valid; },
              onChange: (color: string): void => { this.draftFontColor = color; } })
          }
          if (readerColorContrast(this.draftBackground, this.draftFontColor) < 4.5) {
            Text($r('app.string.reader_color_contrast_hint'))
              .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
            Button($r('app.string.reader_recommend_font_color'))
              .fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => { this.draftFontColor = recommendedReaderFontColor(this.draftBackground); })
          }
          Button($r('app.string.reader_theme_reset'))
            .fontColor($r('sys.color.font_secondary')).backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.draftBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
              this.draftFontColor = '#2D2925';
              this.colorInputValid = true;
              this.colorInputRevision++;
            })
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      Row({ space: AppSpace.Sm }) {
        Button($r('app.string.reader_theme_cancel')).layoutWeight(1)
          .fontColor($r('sys.color.font_primary')).backgroundColor(AppColor.GlassSheetControlTint)
          .onClick((): void => this.onCancel())
        Button($r('app.string.reader_theme_save_apply')).layoutWeight(1)
          .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .enabled(this.colorInputValid).opacity(this.colorInputValid ? 1 : 0.4)
          .onClick((): void => this.onSave(this.draftBackground, this.draftFontColor))
      }.width('100%')
    }.width('100%').height('100%').padding({ top: AppSpace.Lg, left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg })
  }
}
