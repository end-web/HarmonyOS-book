import { ReaderImportedFont } from '../service/text/ReaderFontService';
import { AppFont, AppMaterial } from '../theme/Theme';

class ReaderFontMenuModifier implements ContentModifier<MenuItemConfiguration> {
  private fonts: ReaderImportedFont[];
  private onDelete: (font: ReaderImportedFont) => void;

  constructor(fonts: ReaderImportedFont[], onDelete: (font: ReaderImportedFont) => void) {
    this.fonts = fonts;
    this.onDelete = onDelete;
  }

  deleteOption(index: number): void {
    const font = this.fonts[index - 1];
    if (index > 0 && font !== undefined) this.onDelete(font);
  }

  applyContent(): WrappedBuilder<[MenuItemConfiguration]> {
    return wrapBuilder(readerFontMenuItem);
  }
}

@Builder
function readerFontMenuItem(configuration: MenuItemConfiguration) {
  Row({ space: 8 }) {
    Text(configuration.value).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).height(48)
      .onClick((): void => {
        if (typeof configuration.value === 'string') {
          configuration.triggerSelect(configuration.index, configuration.value);
        }
      })
    if (configuration.index > 0) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
      }.width(40).height(40).backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.reader_delete_font_option', configuration.value))
      .onClick((): void => {
        const modifier = configuration.contentModifier;
        if (modifier instanceof ReaderFontMenuModifier) modifier.deleteOption(configuration.index);
      })
    }
  }.width('100%').padding({ left: 12, right: 4 })
  .borderRadius($r('sys.float.corner_radius_level8'))
  .backgroundColor(configuration.selected ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
}

/** 原生下拉外观与正文对齐一致，每个导入字体选项均可直接删除。 */
@ComponentV2
export struct ReaderFontTabs {
  @Param fonts: ReaderImportedFont[] = [];
  @Param selectedPath: string = '';
  @Event onSelect: (font: ReaderImportedFont) => void = () => {};
  @Event onDelete: (font: ReaderImportedFont) => void = () => {};

  private options(): SelectOption[] {
    const systemFont = this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.reader_system_font').id) ?? '';
    const options: SelectOption[] = [{ value: systemFont }];
    this.fonts.forEach((font: ReaderImportedFont): void => { options.push({ value: font.name }); });
    return options;
  }

  private selectedIndex(): number {
    return this.fonts.findIndex((font: ReaderImportedFont): boolean => font.path === this.selectedPath) + 1;
  }

  private selectFont(index: number): void {
    if (index === 0) {
      this.onSelect(new ReaderImportedFont());
    } else if (index > 0 && index <= this.fonts.length) {
      this.onSelect(this.fonts[index - 1]);
    }
  }

  build() {
    Select(this.options())
      .width('100%').height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .selected(this.selectedIndex()).value(this.options()[this.selectedIndex()].value)
      .font({ size: AppFont.Body }).fontColor($r('sys.color.font_primary'))
      .optionWidth(260)
      .attributeModifier(AppMaterial.selectModifier())
      .menuItemContentModifier(new ReaderFontMenuModifier(this.fonts,
        (font: ReaderImportedFont): void => this.onDelete(font)))
      .onSelect((index: number): void => this.selectFont(index))
  }
}
