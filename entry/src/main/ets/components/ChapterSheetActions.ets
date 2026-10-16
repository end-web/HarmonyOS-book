import { AppFont, AppSpace } from '../theme/Theme';

/** 两种章节弹框共用紧凑工具栏，图标按钮保留无障碍说明。 */
@ComponentV2
export struct ChapterSheetActions {
  @Param descending: boolean = false;
  @Event onOrder: () => void = () => {};
  @Event onTop: () => void = () => {};
  @Event onBottom: () => void = () => {};

  @Builder
  edgeButton(bottom: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(bottom ? $r('sys.symbol.arrow_down_to_line') : $r('sys.symbol.arrow_up_to_line'))
        .fontSize(18).fontColor([$r('sys.color.font_secondary')])
    }.width(44).height(36).padding(0).backgroundColor(Color.Transparent)
    .accessibilityText(bottom ? $r('app.string.chapter_back_bottom') : $r('app.string.chapter_back_top'))
    .onClick((): void => { if (bottom) this.onBottom(); else this.onTop(); })
  }

  build() {
    Row({ space: AppSpace.Sm }) {
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 6 }) {
          SymbolGlyph(this.descending ? $r('sys.symbol.arrow_down') : $r('sys.symbol.arrow_up'))
            .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          Text(this.descending ? $r('app.string.chapter_order_descending') : $r('app.string.chapter_order_ascending'))
            .fontSize(AppFont.Caption).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        }
      }.height(36).padding({ left: 12, right: 12 }).backgroundColor($r('sys.color.comp_background_tertiary'))
      .accessibilityText(this.descending ? $r('app.string.chapter_order_descending') : $r('app.string.chapter_order_ascending'))
      .onClick((): void => this.onOrder())
      Blank()
      Row() {
        this.edgeButton(false)
        Divider().vertical(true).height(14).color($r('sys.color.comp_divider'))
        this.edgeButton(true)
      }.borderRadius(18).clip(true).backgroundColor($r('sys.color.comp_background_tertiary'))
    }.width('100%').padding({ left: AppSpace.Lg, right: AppSpace.Lg })
  }
}
