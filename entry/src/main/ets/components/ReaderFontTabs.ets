import { ReaderImportedFont } from '../service/text/ReaderFontService';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppColor, AppMaterial } from '../theme/Theme';

class ReaderFontDataSource implements IDataSource {
  private fonts: ReaderImportedFont[] = [];
  private listeners: DataChangeListener[] = [];
  update(fonts: ReaderImportedFont[]): void {
    this.fonts = [new ReaderImportedFont(), ...fonts];
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  totalCount(): number { return this.fonts.length; }
  getData(index: number): ReaderImportedFont { return this.fonts[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct ReaderFontTabs {
  @Param fonts: ReaderImportedFont[] = [];
  @Param selectedPath: string = '';
  @Event onSelect: (font: ReaderImportedFont) => void = () => {};
  @Event onDelete: (font: ReaderImportedFont) => void = () => {};
  @Local expanded: boolean = false;
  private source: ReaderFontDataSource = new ReaderFontDataSource();
  private pendingDelete: ReaderImportedFont | null = null;

  aboutToAppear(): void { this.refresh(); }
  @Monitor('fonts')
  refresh(): void { this.source.update(this.fonts); }

  private selectedName(): ResourceStr {
    return this.fonts.find((font: ReaderImportedFont): boolean => font.path === this.selectedPath)?.name ??
      $r('app.string.reader_system_font');
  }

  private menuOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.BottomRight,
      onDisappear: (): void => {
        this.expanded = false;
        const font = this.pendingDelete;
        this.pendingDelete = null;
        if (font !== null) this.onDelete(font);
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    return options;
  }

  @Builder
  fontMenu() {
    List() {
      LazyForEach(this.source, (font: ReaderImportedFont) => {
        ListItem() {
          Row({ space: 8 }) {
            Text(font.path.length > 0 ? font.name : $r('app.string.reader_system_font'))
              .fontSize(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1).height(48)
              .fontColor(font.path === this.selectedPath ? AppColor.Brand : $r('sys.color.font_primary'))
              .onClick((): void => { this.expanded = false; this.onSelect(font); })
            if (font.path.length > 0) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
              }.width(40).height(40).backgroundColor(Color.Transparent)
              .accessibilityText($r('app.string.rule_source_delete_action'))
              .onClick((): void => { this.pendingDelete = font; this.expanded = false; })
            }
          }.padding({ left: 12, right: 4 }).width('100%')
            .backgroundColor(font.path === this.selectedPath ? AppColor.BrandSoft : Color.Transparent)
        }
      }, (font: ReaderImportedFont): string => font.path || 'system')
    }.width(260).height(Math.min(288, (this.fonts.length + 1) * 48))
      .scrollBar(BarState.Auto)
  }

  build() {
    Row({ space: 8 }) {
      Text(this.selectedName()).fontSize(16).fontColor(AppColor.Brand)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14).fontColor([AppColor.Brand])
    }.width('100%').height(40).padding({ left: 12, right: 12 }).borderRadius(20)
      .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
      .onClick((): void => { this.expanded = !this.expanded; })
      .bindMenu(this.expanded, this.fontMenu(), this.menuOptions())
  }
}
