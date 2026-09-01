import { fileIo, picker } from '@kit.CoreFileKit';
import { LocalRuleSource, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { BookSourceService } from '../service/BookSourceService';
import { HttpClient, HttpResponse } from '../service/http/HttpClient';
import { LocalRuleSourceImportParser } from '../service/rulesource/LocalRuleSourceImportParser';
import {
  LocalRuleSourceBulkTester,
  LocalRuleSourceBulkTestProgress,
  LocalRuleSourceBulkTestReport
} from '../service/rulesource/LocalRuleSourceBulkTester';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleHttpClient } from '../service/rulesource/LocalRuleHttpClient';
import { NativeRuleSourceDispatcher } from '../service/rulesource/NativeRuleSourceDispatcher';
import {
  RuleSourceAccountService,
  RuleSourceAccountState
} from '../service/rulesource/RuleSourceAccountService';
import { RuleSourceChildService } from '../service/rulesource/RuleSourceChildService';
import { SourceDataService } from '../service/SourceDataService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { CharsetCodec } from '../utils/CharsetCodec';
import { WindowUtils } from '../utils/WindowUtils';

const RULE_SOURCE_SUCCESS: string = '#168A5B';
const RULE_SOURCE_DANGER: string = '#D03050';
const RULE_SOURCE_WARNING: string = '#9A6700';
const RULE_SOURCE_IMPORT_MAX_LENGTH: number = 10 * 1024 * 1024;

class RuleSourceDataSource implements IDataSource {
  private sources: LocalRuleSource[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.sources.length;
  }

  getData(index: number): LocalRuleSource {
    return this.sources[index];
  }

  setSources(sources: LocalRuleSource[]): void {
    this.sources = sources;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

@ComponentV2
export struct RuleSourcePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local importJson: string = '';
  @Local testKeyword: string = '斗破苍穹';
  @Local sourceCount: number = 0;
  @Local isLoading: boolean = true;
  @Local isImporting: boolean = false;
  @Local isBulkTesting: boolean = false;
  @Local bulkTestTotal: number = 0;
  @Local bulkTestCompleted: number = 0;
  @Local bulkTestPassed: number = 0;
  @Local bulkTestFailed: number = 0;
  @Local bulkTestDeleted: number = 0;
  @Local loadFailed: boolean = false;
  @Local busySourceUrl: string = '';
  private dataSource: RuleSourceDataSource = new RuleSourceDataSource();

  aboutToAppear(): void {
    this.loadSources();
  }

  private async loadSources(showLoading: boolean = true): Promise<void> {
    if (showLoading) {
      this.isLoading = true;
    }
    try {
      const sources = await LocalRuleSourceRepository.list();
      this.sourceCount = sources.length;
      this.dataSource.setSources(sources);
      this.loadFailed = false;
    } catch (_error) {
      this.sourceCount = 0;
      this.dataSource.setSources([]);
      this.loadFailed = true;
    } finally {
      this.isLoading = false;
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  private async importSources(): Promise<void> {
    const input = this.importJson.trim();
    if (this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0 || input.length === 0) {
      if (input.length === 0) {
        this.showToast($r('app.string.rule_source_import_empty'));
      }
      return;
    }

    this.isImporting = true;
    try {
      const content = await this.resolveImportContent(input);
      const imported = await this.persistImportContent(content);
      if (imported) this.importJson = '';
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.isImporting = false;
    }
  }

  private async importLocalFile(): Promise<void> {
    if (this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0) return;
    this.isImporting = true;
    try {
      const uri = await this.pickLocalJsonUri();
      if (uri.length === 0) return;
      const content = await this.readLocalJson(uri);
      if (content === undefined) return;
      await this.persistImportContent(content);
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.isImporting = false;
    }
  }

  private async pickLocalJsonUri(): Promise<string> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) return '';
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: Array<string> = await documentPicker.select(options);
      return uris.length > 0 ? uris[0] : '';
    } catch (_error) {
      // 用户取消选择时不提示错误。
      return '';
    }
  }

  private async readLocalJson(uri: string): Promise<string | undefined> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0) {
        this.showToast($r('app.string.rule_source_import_file_empty'));
        return undefined;
      }
      if (stat.size > RULE_SOURCE_IMPORT_MAX_LENGTH) {
        this.showToast($r('app.string.rule_source_import_file_too_large'));
        return undefined;
      }
      const buffer = new ArrayBuffer(stat.size);
      const bytesRead = await fileIo.read(file.fd, buffer);
      if (bytesRead !== stat.size) {
        this.showToast($r('app.string.rule_source_import_file_failed'));
        return undefined;
      }
      const content = CharsetCodec.decodeBuffer(buffer);
      if (content.trim().length === 0) {
        this.showToast($r('app.string.rule_source_import_file_empty'));
        return undefined;
      }
      return content;
    } catch (_error) {
      this.showToast($r('app.string.rule_source_import_file_failed'));
      return undefined;
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (_error) {
          // 关闭失败不影响已经读取的导入内容。
        }
      }
    }
  }

  private async persistImportContent(content: string): Promise<boolean> {
    const report = LocalRuleSourceImportParser.parse(content);
    if (report.sources.length === 0) {
      this.showToast(report.message.length > 0 ? report.message : $r('app.string.rule_source_import_invalid'));
      return false;
    }
    await LocalRuleSourceRepository.upsertImportedBatch(report.sources);
    SourceDataService.invalidateLocalSources();
    await this.loadSources(false);
    this.showToast($r('app.string.rule_source_import_success'));
    return true;
  }

  private isRemoteImport(input: string): boolean {
    const value = input.toLowerCase();
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private async resolveImportContent(input: string): Promise<string> {
    if (input.length > RULE_SOURCE_IMPORT_MAX_LENGTH) {
      throw new Error('Rule source import content exceeds limit');
    }
    if (!this.isRemoteImport(input)) return input;
    const response: HttpResponse = await HttpClient.request(input, {
      method: 'GET',
      timeout: 20000,
      retry: 1
    });
    if (response.statusCode < 200 || response.statusCode >= 300 ||
      response.body.length > RULE_SOURCE_IMPORT_MAX_LENGTH) {
      throw new Error('Rule source import response rejected');
    }
    return response.body;
  }

  private async changeEnabled(source: LocalRuleSource, enabled: boolean): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!source.canExecute()) {
      this.showToast($r('app.string.rule_source_unsupported_action'));
      return;
    }

    const previousEnabled = source.enabled;
    source.enabled = enabled;
    this.busySourceUrl = source.bookSourceUrl;
    try {
      await LocalRuleSourceRepository.setEnabled(source.bookSourceUrl, enabled);
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
    } catch (_error) {
      source.enabled = previousEnabled;
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private async testSource(source: LocalRuleSource): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting || !source.canExecute()) return;
    const keyword = this.testKeyword.trim();
    if (keyword.length === 0) {
      this.showToast($r('app.string.rule_source_test_keyword_empty'));
      return;
    }
    if (!(await this.hasMainAccount(source))) {
      this.showToast($r('app.string.rule_source_account_required_for_test'));
      this.openMainAccount(source);
      return;
    }
    this.busySourceUrl = source.bookSourceUrl;
    try {
      const health = await BookSourceService.testLocalSource(source, keyword);
      source.validationStatus = health.status;
      source.validationMessage = health.message;
      await LocalRuleSourceRepository.upsert(source);
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
      await this.loadSources(false);
      if (health.status === LocalRuleSourceStatus.READY) {
        this.showToast($r('app.string.rule_source_test_success'));
      } else {
        this.showToast(health.message.length > 0 ? health.message : $r('app.string.rule_source_test_failed'));
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_test_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private canOpenSourceLogin(source: LocalRuleSource): boolean {
    if (RuleSourceChildService.supports(source.bookSourceUrl)) return false;
    return source.loginUrl.trim().toLowerCase().startsWith('https://');
  }

  private async hasMainAccount(source: LocalRuleSource): Promise<boolean> {
    if (!RuleSourceAccountService.supports(source.bookSourceUrl)) return true;
    const state: RuleSourceAccountState = await RuleSourceAccountService.getState(source.bookSourceUrl);
    return state.loggedIn;
  }

  private openMainAccount(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!RuleSourceAccountService.supports(source.bookSourceUrl)) return;
    if (RuleSourceAccountService.usesWebLogin(source.bookSourceUrl)) {
      const loginUrl = RuleSourceAccountService.webLoginUrl(source.bookSourceUrl);
      const route = RuleSourceLoginRouteParams.forMainAccount(
        source.bookSourceUrl, source.bookSourceName, loginUrl);
      if (route.isValid()) this.navStack.pushPathByName('ruleSourceLogin', route);
      return;
    }
    this.navStack.pushPathByName('ruleSourceAccount', source.bookSourceUrl);
  }

  private openSourceLogin(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!this.canOpenSourceLogin(source)) return;
    const route = RuleSourceLoginRouteParams.of(
      source.bookSourceUrl, source.bookSourceName, source.loginUrl);
    this.navStack.pushPathByName('ruleSourceLogin', route);
  }

  private openSourceChildren(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    if (!RuleSourceChildService.supports(source.bookSourceUrl)) return;
    this.navStack.pushPathByName('ruleSourceChildren', source.bookSourceUrl);
  }

  private confirmDelete(source: LocalRuleSource): void {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_delete_title'),
      message: $r('app.string.rule_source_delete_message'),
      primaryButton: {
        value: $r('app.string.rule_source_delete_action'),
        fontColor: RULE_SOURCE_DANGER,
        action: () => {
          this.deleteSource(source);
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async deleteSource(source: LocalRuleSource): Promise<void> {
    this.busySourceUrl = source.bookSourceUrl;
    try {
      const deleted = await LocalRuleSourceRepository.delete(source.bookSourceUrl);
      if (deleted) {
        await LocalRuleHttpClient.clearCookies(source.bookSourceUrl);
        SourceDataService.invalidateLocalSources(source.bookSourceUrl);
        await this.loadSources(false);
        this.showToast($r('app.string.rule_source_delete_success'));
      } else {
        this.showToast($r('app.string.rule_source_not_found'));
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private async confirmBulkTest(): Promise<void> {
    if (this.isBulkTesting || this.isImporting || this.busySourceUrl.length > 0 || this.sourceCount === 0) return;
    if (this.testKeyword.trim().length === 0) {
      this.showToast($r('app.string.rule_source_test_keyword_empty'));
      return;
    }
    try {
      const sources = await LocalRuleSourceRepository.list();
      for (const source of sources) {
        if (!(await this.hasMainAccount(source))) {
          this.showToast($r('app.string.rule_source_account_required_for_test'));
          this.openMainAccount(source);
          return;
        }
      }
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_bulk_confirm_title'),
      message: $r('app.string.rule_source_bulk_confirm_message'),
      primaryButton: {
        value: $r('app.string.rule_source_bulk_confirm_action'),
        fontColor: RULE_SOURCE_DANGER,
        action: () => {
          this.runBulkTest();
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async runBulkTest(): Promise<void> {
    if (this.isBulkTesting || this.isImporting || this.busySourceUrl.length > 0) return;
    const keyword = this.testKeyword.trim();
    if (keyword.length === 0) return;
    this.isBulkTesting = true;
    this.bulkTestTotal = 0;
    this.bulkTestCompleted = 0;
    this.bulkTestPassed = 0;
    this.bulkTestFailed = 0;
    this.bulkTestDeleted = 0;
    try {
      const sources = await LocalRuleSourceRepository.list();
      const tester = LocalRuleSourceBulkTester.createDefault();
      const report: LocalRuleSourceBulkTestReport = await tester.run(sources, keyword,
        (progress: LocalRuleSourceBulkTestProgress) => {
          this.bulkTestTotal = progress.total;
          this.bulkTestCompleted = progress.completed;
          this.bulkTestPassed = progress.passed;
          this.bulkTestFailed = progress.failed;
        });
      for (const source of sources) {
        if (source.validationStatus !== LocalRuleSourceStatus.READY) {
          await LocalRuleHttpClient.clearCookies(source.bookSourceUrl);
        }
      }
      this.bulkTestDeleted = report.deleted;
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.showToast($r('app.string.rule_source_bulk_completed'));
    } catch (_error) {
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.showToast($r('app.string.rule_source_bulk_operation_failed'));
    } finally {
      this.isBulkTesting = false;
    }
  }

  private statusLabel(status: number): ResourceStr {
    if (status === LocalRuleSourceStatus.READY) return $r('app.string.rule_source_status_ready');
    if (status === LocalRuleSourceStatus.FAILED) return $r('app.string.rule_source_status_failed');
    if (status === LocalRuleSourceStatus.UNSUPPORTED) return $r('app.string.rule_source_status_unsupported');
    return $r('app.string.rule_source_status_unchecked');
  }

  private statusColor(status: number): ResourceColor {
    if (status === LocalRuleSourceStatus.READY) return RULE_SOURCE_SUCCESS;
    if (status === LocalRuleSourceStatus.FAILED) return RULE_SOURCE_DANGER;
    if (status === LocalRuleSourceStatus.UNSUPPORTED) return RULE_SOURCE_WARNING;
    return $r('sys.color.font_tertiary');
  }

  private statusMessage(source: LocalRuleSource): ResourceStr {
    if (source.validationMessage.length > 0) return source.validationMessage;
    return $r('app.string.rule_source_waiting_test');
  }

  build() {
    Column() {
      this.buildHeader()

      if (this.isLoading) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(AppColor.Brand)
          Text($r('app.string.rule_source_loading'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppSpace.Sm }) {
          ListItem() {
            this.buildImportSection()
          }

          ListItem() {
            Row() {
              Text($r('app.string.rule_source_installed'))
                .fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_tertiary'))
              Blank()
              Text(`${this.sourceCount}`)
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
              Text($r('app.string.rule_source_count_unit'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
                .margin({ left: 2 })
            }
            .width('100%')
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: AppSpace.Xs })
          }

          if (!this.loadFailed && this.sourceCount > 0) {
            ListItem() {
              TextInput({
                placeholder: $r('app.string.rule_source_test_keyword'),
                text: this.testKeyword
              })
                .width('100%')
                .height(42)
                .fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_primary'))
                .backgroundColor($r('sys.color.comp_background_primary'))
                .borderRadius(AppRadius.Sm)
                .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
                .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
                .onChange((value: string) => {
                  this.testKeyword = value;
                })
            }

            ListItem() {
              this.buildBulkTestSection()
            }
          }

          if (this.loadFailed) {
            ListItem() {
              this.buildLoadFailed()
            }
          } else if (this.sourceCount === 0) {
            ListItem() {
              this.buildEmptyState()
            }
          } else {
            LazyForEach(this.dataSource, (source: LocalRuleSource) => {
              ListItem() {
                this.buildSourceItem(source)
              }
            }, (source: LocalRuleSource) => source.bookSourceUrl)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: AppSpace.Xs,
          bottom: AppSpace.Xl
        })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Sm }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(AppRadius.Pill)
      .onClick(() => this.navStack.pop())

      Text($r('app.string.rule_source_title'))
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xs,
      left: AppSpace.Xs,
      right: AppSpace.Md,
      bottom: AppSpace.Xs
    })
  }

  @Builder
  buildImportSection() {
    Column({ space: AppSpace.Sm }) {
      Column({ space: 2 }) {
        Text($r('app.string.rule_source_import_title'))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
        Text($r('app.string.rule_source_import_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button() {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(18)
            .fontColor([AppColor.Brand])
          Text($r('app.string.rule_source_import_file_action'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColor.BrandSoft)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
      .opacity(this.isImporting || this.isBulkTesting || this.busySourceUrl.length > 0 ? 0.55 : 1)
      .onClick(() => this.importLocalFile())

      TextArea({
        placeholder: $r('app.string.rule_source_import_placeholder'),
        text: this.importJson
      })
        .width('100%')
        .height(132)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.background_secondary'))
        .borderRadius(AppRadius.Sm)
        .padding(AppSpace.Sm)
        .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
        .onChange((value: string) => {
          this.importJson = value;
        })

      Button() {
        Row({ space: AppSpace.Xs }) {
          if (this.isImporting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(18)
              .fontColor([AppColor.OnBrand])
          }
          Text(this.isImporting ? $r('app.string.rule_source_importing') :
            $r('app.string.rule_source_import_action'))
            .fontSize(AppFont.Body)
            .fontColor(this.isImporting ? AppColor.Brand : AppColor.OnBrand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(this.isImporting ? AppColor.BrandSoft :
        (this.importJson.trim().length > 0 ? AppColor.Brand : AppColor.BrandDisabled))
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0 &&
        this.importJson.trim().length > 0)
      .onClick(() => this.importSources())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
  }

  @Builder
  buildBulkTestSection() {
    Column({ space: AppSpace.Xs }) {
      Button() {
        Row({ space: AppSpace.Xs }) {
          if (this.isBulkTesting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([AppColor.OnBrand])
          }
          Text(this.isBulkTesting ? $r('app.string.rule_source_bulk_running') :
            $r('app.string.rule_source_bulk_action'))
            .fontSize(AppFont.Body)
            .fontColor(this.isBulkTesting ? AppColor.Brand : AppColor.OnBrand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(this.isBulkTesting ? AppColor.BrandSoft : AppColor.Brand)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0 &&
        this.testKeyword.trim().length > 0)
      .onClick(() => this.confirmBulkTest())

      if (this.bulkTestTotal > 0) {
        Progress({
          value: this.bulkTestCompleted,
          total: this.bulkTestTotal,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(4)
          .color(AppColor.Brand)

        Row({ space: AppSpace.Xs }) {
          Text($r('app.string.rule_source_bulk_tested'))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
          Text(`${this.bulkTestCompleted}/${this.bulkTestTotal}`)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          Text($r('app.string.rule_source_bulk_passed'))
            .fontSize(AppFont.Caption)
            .fontColor(RULE_SOURCE_SUCCESS)
          Text(`${this.bulkTestPassed}`)
            .fontSize(AppFont.Caption)
            .fontColor(RULE_SOURCE_SUCCESS)
          Text($r('app.string.rule_source_bulk_failed_count'))
            .fontSize(AppFont.Caption)
            .fontColor(RULE_SOURCE_DANGER)
          Text(`${this.bulkTestFailed}`)
            .fontSize(AppFont.Caption)
            .fontColor(RULE_SOURCE_DANGER)
          Text($r('app.string.rule_source_bulk_deleted'))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
          Text(`${this.bulkTestDeleted}`)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Xs, right: AppSpace.Xs })
  }

  @Builder
  buildLoadFailed() {
    Column({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(32)
        .fontColor([RULE_SOURCE_DANGER])
      Text($r('app.string.rule_source_load_failed'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.common_retry'))
        .height(40)
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .backgroundColor(AppColor.BrandSoft)
        .borderRadius(AppRadius.Sm)
        .onClick(() => this.loadSources())
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.bookshelf'))
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.rule_source_empty'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.rule_source_empty_hint'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSourceItem(source: LocalRuleSource) {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Column({ space: AppSpace.Xxs }) {
          Row({ space: AppSpace.Xs }) {
            Text(source.bookSourceName)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(NativeRuleSourceDispatcher.isSourceUrl(source.bookSourceUrl)
              ? $r('app.string.rule_source_type_mixed')
              : (source.isAudio() ? $r('app.string.rule_source_type_audio') :
                $r('app.string.rule_source_type_text')))
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 2, bottom: 2 })
              .backgroundColor(AppColor.BrandSoft)
              .borderRadius(AppRadius.Xs)
          }
          .width('100%')

          Text(source.bookSourceUrl)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          if (this.busySourceUrl === source.bookSourceUrl) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(AppColor.Brand)
          } else {
            Toggle({ type: ToggleType.Switch, isOn: source.enabled && source.canExecute() })
              .enabled(source.canExecute() && !this.isImporting && !this.isBulkTesting &&
                this.busySourceUrl.length === 0)
              .onChange((isOn: boolean) => this.changeEnabled(source, isOn))
          }
          Text($r('app.string.rule_source_search_enabled'))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width(72)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: AppSpace.Xs }) {
        Column()
          .width(8)
          .height(8)
          .backgroundColor(this.statusColor(source.validationStatus))
          .borderRadius(AppRadius.Pill)
        Text(this.statusLabel(source.validationStatus))
          .fontSize(AppFont.Caption)
          .fontColor(this.statusColor(source.validationStatus))
          .fontWeight(FontWeight.Medium)
        Text(this.statusMessage(source))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))

      Row({ space: AppSpace.Xs }) {
        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(19)
            .fontColor([source.canExecute() ? AppColor.Brand : $r('sys.color.font_tertiary')])
        }
        .layoutWeight(1)
        .height(42)
        .constraintSize({ minWidth: 0 })
        .backgroundColor(source.canExecute() ? AppColor.BrandSoft : Color.Transparent)
        .borderRadius(AppRadius.Sm)
        .enabled(source.canExecute() && this.testKeyword.trim().length > 0 && !this.isImporting &&
          !this.isBulkTesting && this.busySourceUrl.length === 0)
        .accessibilityText($r('app.string.rule_source_test_action'))
        .onClick(() => this.testSource(source))

        if (RuleSourceAccountService.supports(source.bookSourceUrl)) {
          Button() {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(19)
              .fontColor([AppColor.Brand])
          }
          .layoutWeight(1)
          .height(42)
          .constraintSize({ minWidth: 0 })
          .backgroundColor($r('sys.color.background_secondary'))
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_account_action'))
          .onClick(() => this.openMainAccount(source))
        }

        if (RuleSourceChildService.supports(source.bookSourceUrl)) {
          Button() {
            SymbolGlyph($r('sys.symbol.list_bullet'))
              .fontSize(19)
              .fontColor([AppColor.Brand])
          }
          .layoutWeight(1)
          .height(42)
          .constraintSize({ minWidth: 0 })
          .backgroundColor($r('sys.color.background_secondary'))
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_child_action'))
          .onClick(() => this.openSourceChildren(source))
        } else if (this.canOpenSourceLogin(source)) {
          Button() {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(19)
              .fontColor([AppColor.Brand])
          }
          .layoutWeight(1)
          .height(42)
          .constraintSize({ minWidth: 0 })
          .backgroundColor($r('sys.color.background_secondary'))
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_login_action'))
          .onClick(() => this.openSourceLogin(source))
        }

        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(19)
            .fontColor([RULE_SOURCE_DANGER])
        }
        .layoutWeight(1)
        .height(42)
        .constraintSize({ minWidth: 0 })
        .backgroundColor(Color.Transparent)
        .borderRadius(AppRadius.Sm)
        .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
        .accessibilityText($r('app.string.rule_source_delete_action'))
        .onClick(() => this.confirmDelete(source))
      }
      .width('100%')
      .height(42)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
  }
}
