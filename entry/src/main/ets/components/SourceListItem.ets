import { AppColor, AppFont, AppSpace } from '../theme/Theme';
import { BookSource } from '../model/BookSource';

@ReusableV2
@ComponentV2
export struct SourceListItem {
  @Require @Param source: BookSource;
  @Param isSelectMode: boolean = false;
  @Param isSelected: boolean = false;
  @Param isUnreachable: boolean = false;
  @Event onTap: () => void = () => {};
  @Event onLongPress: () => void = () => {};
  @Event onToggleEnabled: (enabled: boolean) => void = (_e: boolean) => {};

  build() {
    Row() {
      if (this.isSelectMode) {
        Checkbox()
          .select(this.isSelected)
          .selectedColor(AppColor.Brand)
          .margin({ right: AppSpace.Sm })
          .hitTestBehavior(HitTestMode.None)
      }

      Column({ space: 2 }) {
        Row({ space: AppSpace.Xs }) {
          Text(this.source.bookSourceName)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.isUnreachable) {
            SymbolGlyph($r('sys.symbol.nosign'))
              .fontSize(16)
              .fontColor(['#FF3B30'])
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: AppSpace.Xs }) {
          Text(this.source.bookSourceGroup || '未分组')
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.Brand)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#1A0A59F7')
          Text(this.source.bookSourceUrl)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.isSelectMode) {
        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled !== false })
          .selectedColor(AppColor.Brand)
          .onChange((isOn: boolean) => this.onToggleEnabled(isOn))
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: 10, bottom: 10 })
    .backgroundColor(this.isSelectMode && this.isSelected ? '#0D0A59F7' : Color.Transparent)
    .onClick(() => this.onTap())
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => this.onLongPress())
    )
  }
}
