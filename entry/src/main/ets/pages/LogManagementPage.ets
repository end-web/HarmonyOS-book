import { pasteboard } from '@kit.BasicServicesKit';
import { DiagnosticLogEntry, DiagnosticLogService } from '../service/DiagnosticLogService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

class LogDataSource implements IDataSource {
  private entries: DiagnosticLogEntry[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.entries.length; }
  getData(index: number): DiagnosticLogEntry { return this.entries[index]; }
  update(entries: DiagnosticLogEntry[]): void {
    this.entries = entries;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct LogManagementPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local onlyErrors: boolean = false;
  @Local count: number = 0;
  @Local errorCount: number = 0;
  @Local busy: boolean = false;
  @Local loggingEnabled: boolean = false;
  @Local storageError: string = '';
  private entries: DiagnosticLogEntry[] = [];
  private source: LogDataSource = new LogDataSource();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) DiagnosticLogService.init(context);
    this.loggingEnabled = DiagnosticLogService.isEnabled();
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.entries = await DiagnosticLogService.list();
    this.errorCount = this.entries.filter((entry: DiagnosticLogEntry): boolean => entry.level === 'ERROR').length;
    this.storageError = DiagnosticLogService.getStorageError();
    this.applyFilter();
  }

  private applyFilter(): void {
    const visible = this.entries.filter((entry: DiagnosticLogEntry): boolean => !this.onlyErrors || entry.level === 'ERROR');
    this.count = visible.length;
    this.source.update(visible);
  }

  private async check(): Promise<void> {
    if (this.busy || !this.loggingEnabled) return;
    this.busy = true;
    try { await DiagnosticLogService.check(); await this.refresh(); }
    finally { this.busy = false; }
  }

  private async setLoggingEnabled(enabled: boolean): Promise<void> {
    if (this.busy || enabled === DiagnosticLogService.isEnabled()) return;
    this.busy = true;
    this.loggingEnabled = enabled;
    try {
      await DiagnosticLogService.setEnabled(enabled);
      await this.refresh();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    } finally {
      this.loggingEnabled = DiagnosticLogService.isEnabled();
      this.busy = false;
    }
  }

  private async copy(): Promise<void> {
    try {
      const text = this.entries.filter((entry: DiagnosticLogEntry): boolean => !this.onlyErrors || entry.level === 'ERROR')
        .map((entry: DiagnosticLogEntry): string => `${entry.time} [${entry.level}] ${entry.stage}\n${entry.message}`)
        .join('\n\n');
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_copied') });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    }
  }

  private async clear(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.log_clear'), message: $r('app.string.log_clear_confirm'),
        buttons: [
          { text: $r('app.string.log_cancel'), color: $r('sys.color.font_secondary') },
          { text: $r('app.string.log_clear'), color: AppColor.Brand }
        ]
      });
      if (result.index !== 1) return;
      await DiagnosticLogService.clear();
      await this.refresh();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    }
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24).fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text($r('app.string.log_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Text($r('app.string.log_refresh')).fontColor(AppColor.Brand).onClick(() => this.refresh())
      }
      .width('100%')
      Text($r('app.string.log_hint')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.log_enabled')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.loggingEnabled })
          .selectedColor(AppColor.Brand)
          .enabled(!this.busy)
          .accessibilityText($r('app.string.log_enabled'))
          .onChange((value: boolean): void => { this.setLoggingEnabled(value); })
      }
      .width('100%')
      Row({ space: AppSpace.Sm }) {
        Button($r('app.string.log_check')).backgroundColor(AppColor.Brand).fontColor(Color.Black)
          .layoutWeight(1).enabled(!this.busy && this.loggingEnabled).onClick(() => this.check())
        Button($r('app.string.log_copy')).backgroundColor($r('sys.color.comp_background_secondary'))
          .fontColor($r('sys.color.font_primary')).layoutWeight(1).enabled(this.count > 0).onClick(() => this.copy())
        Button($r('app.string.log_clear')).backgroundColor($r('sys.color.comp_background_secondary'))
          .fontColor($r('sys.color.font_primary')).layoutWeight(1).enabled(!this.busy).onClick(() => this.clear())
      }
      .width('100%')
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.log_count', this.count, this.errorCount)).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        Text($r('app.string.log_errors_only')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        Toggle({ type: ToggleType.Switch, isOn: this.onlyErrors }).selectedColor(AppColor.Brand)
          .onChange((value: boolean): void => { this.onlyErrors = value; this.applyFilter(); })
      }
      .width('100%')
      if (this.busy) { LoadingProgress().color(AppColor.Brand).width(24).height(24) }
      if (this.storageError.length > 0) {
        Text($r('app.string.log_storage_failed')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
      }
      if (this.count === 0) {
        Text($r('app.string.log_empty')).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      } else {
        List({ space: AppSpace.Sm }) {
          LazyForEach(this.source, (entry: DiagnosticLogEntry) => {
            ListItem() {
              Column({ space: AppSpace.Xs }) {
                Text(`${entry.time.replace('T', ' ').replace('Z', ' UTC')}  ${entry.level}`)
                  .fontSize(AppFont.Caption).fontColor(entry.level === 'ERROR' ? AppColor.Brand : $r('sys.color.font_tertiary'))
                Text(entry.stage).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text(entry.message).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
                  .copyOption(CopyOptions.LocalDevice).wordBreak(WordBreak.BREAK_ALL)
              }
              .width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
              .borderRadius(AppRadius.Md).backgroundColor($r('sys.color.comp_background_secondary'))
            }
          }, (entry: DiagnosticLogEntry): string => entry.id)
        }
        .width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      bottom: WindowUtils.getBottomSafeVp() + AppSpace.Sm })
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
