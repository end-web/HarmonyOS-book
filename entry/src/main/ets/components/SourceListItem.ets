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
        // 第 1 行：名称 + 连通图标（紧跟名称后面）
        Row({ space: AppSpace.Xs }) {
          Text(this.source.bookSourceName)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.isUnreachable) {
            SymbolGlyph($r('sys.symbol.nosign'))
              .fontSize(16)
              .fontColor(['#FF3B30'])
          }
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 第 2 行：标签（无灰色底）
        Text(this.source.bookSourceGroup || '未分组')
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 第 3 行：地址（单行省略，避免不定行高在 LazyForEach 中导致滑动跳动）
        Text(this.source.bookSourceUrl)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.isSelectMode) {
        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled !== false })
          .selectedColor(AppColor.Brand)
          .onChange((isOn: boolean) => {
            // @ReusableV2 复用列表项时,Toggle 重绑 isOn 会触发一次 onChange。
            // 若新值与当前源状态一致,说明不是用户操作而是复用重绑,直接忽略,
            // 否则会误改到正在显示的(其它)书源的 enabled,导致禁用错位/丢失。
            if (isOn === (this.source.enabled !== false)) return;
            this.onToggleEnabled(isOn);
          })
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: 10, bottom: 10 })
    .backgroundColor(this.isSelectMode && this.isSelected ? '#0D0A59F7' : Color.Transparent)
    .onClick(() => this.onTap())
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => this.onLongPress())
    )
  }
}
