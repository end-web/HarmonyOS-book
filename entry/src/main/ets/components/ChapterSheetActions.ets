import { AppColor, AppSpace } from '../theme/Theme';

/** 两种章节弹框共用紧凑工具栏，图标按钮保留无障碍说明。 */
@ComponentV2
export struct ChapterSheetActions {
  @Param descending: boolean = false;
  @Event onOrder: () => void = () => {};
  @Event onTop: () => void = () => {};
  @Event onBottom: () => void = () => {};

  @Builder
  edgeButton(bottom: boolean) {
    Button({ type: ButtonType.Circle }) {
      Column({ space: 1 }) {
        if (!bottom) {
          Row().width(14).height(2).backgroundColor(AppColor.Brand)
        }
        SymbolGlyph(bottom ? $r('sys.symbol.arrow_down') : $r('sys.symbol.arrow_up'))
          .fontSize(18).fontColor([AppColor.Brand])
        if (bottom) {
          Row().width(14).height(2).backgroundColor(AppColor.Brand)
        }
      }
    }.width(40).height(40).padding(0).backgroundColor(AppColor.BrandSoft)
    .accessibilityText(bottom ? $r('app.string.chapter_back_bottom') : $r('app.string.chapter_back_top'))
    .onClick((): void => { if (bottom) this.onBottom(); else this.onTop(); })
  }

  build() {
    Row({ space: AppSpace.Sm }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.descending ? $r('sys.symbol.arrow_down') : $r('sys.symbol.arrow_up'))
          .fontSize(20).fontColor([AppColor.Brand])
      }.width(40).height(40).padding(0).backgroundColor(AppColor.BrandSoft)
      .accessibilityText(this.descending ? $r('app.string.chapter_order_descending') : $r('app.string.chapter_order_ascending'))
      .onClick((): void => this.onOrder())
      Blank()
      this.edgeButton(false)
      this.edgeButton(true)
    }.width('100%').padding({ left: AppSpace.Lg, right: AppSpace.Lg })
  }
}
