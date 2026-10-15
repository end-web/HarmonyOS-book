import { NativeSourceDraft, NativeSourceField } from '../service/rulesource/NativeSourceDraft';
import { AppColor, AppFont, AppSpace, AppRadius } from '../theme/Theme';

@ObservedV2
class NativeFieldRow {
  id: string = '';
  @Trace field: NativeSourceField = new NativeSourceField();
}

class NativeFieldDataSource implements IDataSource {
  private items: NativeFieldRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): NativeFieldRow { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
  update(items: NativeSourceField[], draft: NativeSourceDraft): void {
    const rows: NativeFieldRow[] = [];
    for (const item of items) {
      const id = draft.stableKey(item.path);
      const row = this.items.find((value: NativeFieldRow): boolean => value.id === id) ?? new NativeFieldRow();
      row.id = id;
      row.field = item;
      rows.push(row);
    }
    this.items = rows;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

function nativeFieldLabel(field: NativeSourceField): ResourceStr {
  if (/^\d+$/.test(field.key)) return $r('app.string.native_editor_item', Number(field.key) + 1);
  switch (field.key) {
    case 'name': return $r('app.string.native_field_name');
    case 'url': return $r('app.string.native_field_url');
    case 'group': return $r('app.string.native_field_group');
    case 'comment': return $r('app.string.native_field_comment');
    case 'type': return $r('app.string.native_field_type');
    case 'headers': return $r('app.string.native_field_headers');
    case 'method': return $r('app.string.native_field_method');
    case 'body': return $r('app.string.native_field_body');
    case 'fields': return $r('app.string.native_field_fields');
    case 'list': return $r('app.string.native_field_list');
    case 'vars': return $r('app.string.native_field_vars');
    case 'menus': return $r('app.string.native_field_menus');
    case 'dynamicMenus': return $r('app.string.native_field_dynamic_menus');
    case 'let': return $r('app.string.native_field_let');
    case 'keep': return $r('app.string.native_field_keep');
    case 'lib': return $r('app.string.native_field_lib');
    case 'enabled': return $r('app.string.native_field_enabled');
    case 'enabledExplore': return $r('app.string.rule_source_explore_enabled');
    default: return field.key;
  }
}

@ComponentV2
struct NativeSourceFieldInput {
  @Param field: NativeSourceField = new NativeSourceField();
  @Event onEdit: (field: NativeSourceField, value: string) => void = () => {};
  @Event onOpen: (field: NativeSourceField) => void = () => {};
  @Event onRemove: (field: NativeSourceField) => void = () => {};
  @Local edited: boolean = false;

  @Monitor('field')
  private resetEdited(): void { this.edited = false; }

  build() {
    Column({ space: AppSpace.Xs }) {
      Row({ space: AppSpace.Xs }) {
        Text(nativeFieldLabel(this.field)).fontSize(AppFont.Body).layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        if ((this.field.exists || this.edited) && !this.field.readOnly) {
          Button($r('app.string.native_editor_remove')).fontSize(AppFont.Caption)
            .fontColor(AppColor.Brand).backgroundColor(Color.Transparent).height(40)
            .onClick(() => this.onRemove(this.field))
        }
      }.width('100%')
      Text(this.field.path).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        .width('100%').maxLines(2)
      if (this.field.kind === 'object' || this.field.kind === 'array') {
        Button($r('app.string.native_editor_open')).width('100%').height(44)
          .fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
          .onClick(() => this.onOpen(this.field))
      } else if (this.field.kind === 'boolean') {
        Toggle({ type: ToggleType.Switch, isOn: this.field.value === 'true' })
          .selectedColor(AppColor.Brand).enabled(!this.field.readOnly)
          .onChange((value: boolean): void => { this.edited = true; this.onEdit(this.field, String(value)); })
      } else if (this.field.kind === 'null') {
        Text('null').fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
      } else {
        TextArea({ text: this.field.value, placeholder: $r('app.string.native_editor_optional') })
          .height(this.field.key === 'lib' || this.field.value.includes('\n') ? 144 : 72)
          .width('100%').fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(AppRadius.Xs)
          .caretColor(AppColor.Brand).selectedBackgroundColor(AppColor.BrandSoft)
          .enabled(!this.field.readOnly)
          .onChange((value: string): void => { this.edited = true; this.onEdit(this.field, value); })
      }
    }.width('100%').padding(AppSpace.Sm)
  }
}

@ComponentV2
export struct NativeSourceForm {
  @Param draft: NativeSourceDraft = new NativeSourceDraft();
  @Param section: string = '';
  @Event onChanged: () => void = () => {};
  @Local path: string = '';
  @Local addName: string = '';
  @Local addKind: string = 'string';
  @Local addTypeIndex: number = 0;
  @Local error: ResourceStr = '';
  private fields: NativeFieldDataSource = new NativeFieldDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.resetSection(); }
  @Monitor('section', 'draft')
  private resetSection(): void {
    this.path = this.section;
    this.refresh();
  }
  private refresh(): void {
    this.fields.update(this.draft.fields(this.path), this.draft);
    this.addName = '';
    this.error = this.draft.errorPath() ? $r('app.string.native_editor_number_error', this.draft.errorPath()) : '';
  }
  private open(field: NativeSourceField): void {
    this.path = field.path;
    this.refresh();
    this.scroller.scrollEdge(Edge.Top);
  }
  private edit(field: NativeSourceField, value: string): void {
    // ArkUI can report initial text even for disabled inputs.
    if (field.readOnly) return;
    const current = this.draft.fields(this.draft.parent(field.path))
      .find((item: NativeSourceField): boolean => item.path === field.path);
    if (!current || current.value === value) return;
    this.draft.edit(field, value);
    this.error = this.draft.errorPath() ? $r('app.string.native_editor_number_error', this.draft.errorPath()) : '';
    this.onChanged();
  }
  private remove(field: NativeSourceField): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.native_editor_remove'),
      message: $r('app.string.native_editor_remove_confirm', field.path),
      buttons: [
        { value: $r('app.string.common_cancel'), action: () => {} },
        { value: $r('app.string.native_editor_remove'), action: () => {
          this.draft.remove(field); this.refresh(); this.onChanged();
        } }
      ]
    });
  }
  private add(): void {
    try {
      this.draft.add(this.path, this.addName, this.addKind);
      this.refresh(); this.onChanged();
    } catch (_error) { this.error = $r('app.string.native_editor_add_error'); }
  }
  build() {
    Column({ space: AppSpace.Xs }) {
      Row() {
        if (this.path !== this.section) {
          Button($r('app.string.native_editor_parent')).fontColor(AppColor.Brand)
            .backgroundColor(Color.Transparent).onClick(() => {
              this.path = this.draft.parent(this.path); this.refresh();
              this.scroller.scrollEdge(Edge.Top);
            })
        }
        Text(this.path || $r('app.string.native_editor_basic')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).layoutWeight(1).maxLines(2)
      }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      if (this.error) {
        Text(this.error).fontSize(AppFont.Caption).fontColor(AppColor.Brand).padding(AppSpace.Sm)
      }
      List({ scroller: this.scroller, space: AppSpace.Xs }) {
        LazyForEach(this.fields, (row: NativeFieldRow) => {
          ListItem() {
            NativeSourceFieldInput({ field: row.field,
              onEdit: (item: NativeSourceField, value: string): void => this.edit(item, value),
              onOpen: (item: NativeSourceField): void => this.open(item),
              onRemove: (item: NativeSourceField): void => this.remove(item) })
          }
        }, (row: NativeFieldRow): string => row.id)
        ListItem() {
          Column({ space: AppSpace.Sm }) {
            if (this.draft.kind(this.path) !== 'array') {
              TextInput({ text: this.addName, placeholder: $r('app.string.native_editor_key') })
                .caretColor(AppColor.Brand).onChange((value: string): void => { this.addName = value; })
            }
            Select([
              { value: $r('app.string.native_editor_string') }, { value: $r('app.string.native_editor_object') },
              { value: $r('app.string.native_editor_array') }, { value: $r('app.string.native_editor_boolean') },
              { value: $r('app.string.native_editor_number') }
            ]).selected(this.addTypeIndex).fontColor($r('sys.color.font_primary'))
              .onSelect((index: number): void => {
                this.addTypeIndex = index;
                this.addKind = ['string', 'object', 'array', 'boolean', 'number'][index];
              })
            Button($r('app.string.native_editor_add')).width('100%').fontColor(Color.White)
              .backgroundColor(AppColor.Brand).onClick(() => this.add())
          }.width('100%').padding(AppSpace.Sm)
        }
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }.width('100%').height('100%')
  }
}
