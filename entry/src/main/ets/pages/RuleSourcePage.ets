import { fileIo, picker } from '@kit.CoreFileKit';
import { LocalRuleSource, LocalRuleSourceStatus, LocalRuleSourceType } from '../model/LocalRuleSource';
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

interface RuleSourceEditParams {
  sourceUrl: string;
}

interface RuleSourceDebugParams {
  sourceUrl: string;
}

const RULE_SOURCE_SUCCESS: string = '#168A5B';
const RULE_SOURCE_DANGER: string = '#D03050';
const RULE_SOURCE_DANGER_SOFT: string = '#14D03050';
const RULE_SOURCE_WARNING: string = '#9A6700';
const RULE_SOURCE_IMPORT_MAX_LENGTH: number = 10 * 1024 * 1024;
const RULE_SOURCE_TEST_KEYWORD: string = '我的';

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
  @Local searchKeyword: string = '';
  @Local sourceCount: number = 0;
  @Local filteredSourceCount: number = 0;
  @Local isLoading: boolean = true;
  @Local isImporting: boolean = false;
  @Local isBulkTesting: boolean = false;
  @Local isEditMode: boolean = false;
  @Local showImportPanel: boolean = false;
  @Local selectedSourceCount: number = 0;
  @Local selectionRevision: number = 0;
  @Local bulkTestTotal: number = 0;
  @Local bulkTestCompleted: number = 0;
  @Local bulkTestPassed: number = 0;
  @Local bulkTestFailed: number = 0;
  @Local bulkTestRetained: number = 0;
  @Local loadFailed: boolean = false;
  @Local busySourceUrl: string = '';
  private selectedSources: Set<string> = new Set();
  private changingSourceUrls: Set<string> = new Set();
  private dataSource: RuleSourceDataSource = new RuleSourceDataSource();
  private allSources: LocalRuleSource[] = [];
  private filteredSources: LocalRuleSource[] = [];

  aboutToAppear(): void {
    this.loadSources();
  }

  private async loadSources(showLoading: boolean = true): Promise<void> {
    if (showLoading) {
      this.isLoading = true;
    }
    try {
      const sources = await LocalRuleSourceRepository.list();
      this.allSources = sources;
      this.sourceCount = sources.length;
      if (sources.length === 0) this.showImportPanel = true;
      this.applyFilters();
      this.loadFailed = false;
    } catch (_error) {
      this.sourceCount = 0;
      this.filteredSourceCount = 0;
      this.allSources = [];
      this.filteredSources = [];
      this.dataSource.setSources([]);
      this.loadFailed = true;
    } finally {
      this.isLoading = false;
    }
  }

  private applyFilters(): void {
    let filtered: LocalRuleSource[] = this.allSources.slice();

    // 搜索过滤
    if (this.searchKeyword.trim().length > 0) {
      const keyword = this.searchKeyword.trim().toLowerCase();
      filtered = filtered.filter((source: LocalRuleSource) => {
        return source.bookSourceName.toLowerCase().includes(keyword) ||
          source.bookSourceUrl.toLowerCase().includes(keyword) ||
          source.bookSourceGroup.toLowerCase().includes(keyword);
      });
    }

    const audioSources: LocalRuleSource[] = [];
    const otherSources: LocalRuleSource[] = [];
    for (const source of filtered) {
      if (source.isAudio()) {
        audioSources.push(source);
      } else {
        otherSources.push(source);
      }
    }
    filtered = audioSources.concat(otherSources);

    this.filteredSources = filtered;
    this.filteredSourceCount = filtered.length;
    this.dataSource.setSources(filtered);
  }

  private toggleEditMode(): void {
    this.isEditMode = !this.isEditMode;
    this.resetSelection();
    if (this.isEditMode) this.showImportPanel = false;
  }

  private toggleImportPanel(): void {
    this.showImportPanel = !this.showImportPanel;
    if (this.showImportPanel && this.isEditMode) {
      this.isEditMode = false;
      this.resetSelection();
    }
  }

  private resetSelection(): void {
    this.selectedSources = new Set<string>();
    this.selectedSourceCount = 0;
    this.selectionRevision++;
  }

  private isSourceSelected(sourceUrl: string, _selectionRevision: number): boolean {
    return this.selectedSources.has(sourceUrl);
  }

  private toggleSelectSource(sourceUrl: string): void {
    const nextSelected = new Set<string>(this.selectedSources);
    const wasSelected = this.isSourceSelected(sourceUrl, this.selectionRevision);
    if (wasSelected) {
      nextSelected.delete(sourceUrl);
    } else {
      nextSelected.add(sourceUrl);
    }
    this.selectedSources = nextSelected;
    this.selectionRevision++;
    if (wasSelected) {
      this.selectedSourceCount = Math.max(0, this.selectedSourceCount - 1);
    } else {
      this.selectedSourceCount = Math.min(this.filteredSourceCount, this.selectedSourceCount + 1);
    }
  }

  private selectAllSources(): void {
    if (this.areAllVisibleSourcesSelected()) {
      this.resetSelection();
      return;
    }
    const nextSelected = new Set<string>();
    for (const source of this.filteredSources) {
      nextSelected.add(source.bookSourceUrl);
    }
    this.selectedSources = nextSelected;
    this.selectedSourceCount = nextSelected.size;
    this.selectionRevision++;
  }

  private areAllVisibleSourcesSelected(): boolean {
    return this.filteredSourceCount > 0 && this.selectedSourceCount === this.filteredSourceCount;
  }

  private selectedSourceUrls(): string[] {
    const urls: string[] = [];
    for (const source of this.filteredSources) {
      if (this.isSourceSelected(source.bookSourceUrl, this.selectionRevision)) urls.push(source.bookSourceUrl);
    }
    return urls;
  }

  private finishBatchEdit(): void {
    this.resetSelection();
    this.isEditMode = false;
  }

  private async batchEnableSelected(enabled: boolean): Promise<void> {
    if (this.selectedSourceCount === 0) return;
    this.busySourceUrl = 'batch';
    try {
      const urls = this.selectedSourceUrls();
      await LocalRuleSourceRepository.setEnabledBatch(urls, enabled);
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.finishBatchEdit();
      this.showToast(enabled ? $r('app.string.rule_source_batch_enable_success') :
        $r('app.string.rule_source_batch_disable_success'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
    }
  }

  private confirmBatchDelete(): void {
    if (this.selectedSourceCount === 0) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_batch_delete_title'),
      message: $r('app.string.rule_source_batch_delete_message', this.selectedSourceCount),
      primaryButton: {
        value: $r('app.string.rule_source_delete_action'),
        fontColor: RULE_SOURCE_DANGER,
        action: () => {
          this.batchDeleteSelected();
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async batchDeleteSelected(): Promise<void> {
    if (this.selectedSourceCount === 0) return;
    this.busySourceUrl = 'batch';
    try {
      const urls = this.selectedSourceUrls();
      await LocalRuleSourceRepository.deleteBatch(urls);
      LocalRuleHttpClient.clearCookieCacheBatch(urls);
      SourceDataService.invalidateLocalSources();
      await this.loadSources(false);
      this.finishBatchEdit();
      this.showToast($r('app.string.rule_source_batch_delete_success'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.busySourceUrl = '';
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
      if (imported) {
        this.importJson = '';
        this.showImportPanel = false;
      }
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
      const imported = await this.persistImportContent(content);
      if (imported) this.showImportPanel = false;
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
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting ||
      this.changingSourceUrls.has(source.bookSourceUrl)) return;
    if (!source.canExecute()) {
      this.showToast($r('app.string.rule_source_unsupported_action'));
      return;
    }

    const previousEnabled = source.enabled;
    source.enabled = enabled;
    this.changingSourceUrls.add(source.bookSourceUrl);
    try {
      await LocalRuleSourceRepository.setEnabled(source.bookSourceUrl, enabled);
      SourceDataService.invalidateLocalSources(source.bookSourceUrl);
    } catch (_error) {
      source.enabled = previousEnabled;
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.changingSourceUrls.delete(source.bookSourceUrl);
    }
  }

  private createNewSource(): void {
    this.navStack.pushPathByName('RuleSourceEditPage', null);
  }

  private editSource(source: LocalRuleSource): void {
    const params: RuleSourceEditParams = { sourceUrl: source.bookSourceUrl };
    this.navStack.pushPathByName('RuleSourceEditPage', params);
  }

  private debugSource(source: LocalRuleSource): void {
    const params: RuleSourceDebugParams = { sourceUrl: source.bookSourceUrl };
    this.navStack.pushPathByName('RuleSourceDebugPage', params);
  }

  private async testSource(source: LocalRuleSource): Promise<void> {
    if (this.busySourceUrl.length > 0 || this.isImporting || this.isBulkTesting || !source.canExecute()) return;
    if (!(await this.hasMainAccount(source))) {
      this.showToast($r('app.string.rule_source_account_required_for_test'));
      this.openMainAccount(source);
      return;
    }
    this.busySourceUrl = source.bookSourceUrl;
    try {
      const health = await BookSourceService.testLocalSource(source, RULE_SOURCE_TEST_KEYWORD);
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
    this.isBulkTesting = true;
    this.bulkTestTotal = 0;
    this.bulkTestCompleted = 0;
    this.bulkTestPassed = 0;
    this.bulkTestFailed = 0;
    this.bulkTestRetained = 0;
    try {
      const sources = await LocalRuleSourceRepository.list();
      const tester = LocalRuleSourceBulkTester.createDefault();
      const report: LocalRuleSourceBulkTestReport = await tester.run(sources, RULE_SOURCE_TEST_KEYWORD,
        (progress: LocalRuleSourceBulkTestProgress) => {
          this.applyBulkTestProgress(progress);
        });
      this.bulkTestRetained = report.retained;
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

  private applyBulkTestProgress(progress: LocalRuleSourceBulkTestProgress): void {
    this.bulkTestTotal = progress.total;
    this.bulkTestCompleted = progress.completed;
    this.bulkTestPassed = progress.passed;
    this.bulkTestFailed = progress.failed;
    const testedSource = progress.testedSource;
    if (testedSource === undefined) return;
    for (const source of this.allSources) {
      if (source.bookSourceUrl !== testedSource.bookSourceUrl) continue;
      source.validationStatus = testedSource.validationStatus;
      source.validationMessage = testedSource.validationMessage;
      break;
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

  private sourceGroupLabels(source: LocalRuleSource): string[] {
    const rawGroup = source.bookSourceGroup.trim();
    if (rawGroup.length === 0 || rawGroup.toLowerCase() === '[object object]') return [];
    const parts = rawGroup.split(new RegExp('[,，·|]+'));
    const labels: string[] = [];
    for (const part of parts) {
      const label = part.trim();
      if (label.length > 0 && label.toLowerCase() !== '[object object]' && !labels.includes(label)) {
        labels.push(label);
      }
    }
    return labels;
  }

  private sourceTypeLabel(source: LocalRuleSource): ResourceStr {
    if (NativeRuleSourceDispatcher.isSourceUrl(source.bookSourceUrl)) {
      return $r('app.string.rule_source_type_mixed');
    }
    if (source.bookSourceType === LocalRuleSourceType.AUDIO) {
      return $r('app.string.rule_source_type_audio');
    }
    return $r('app.string.rule_source_type_text');
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
          if (this.showImportPanel) {
            ListItem() {
              this.buildImportSection()
            }
          }

          ListItem() {
            Row() {
              Text($r('app.string.rule_source_installed'))
                .fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_tertiary'))
              Blank()
              Text(`${this.filteredSourceCount}/${this.sourceCount}`)
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

          if (!this.loadFailed && this.bulkTestTotal > 0) {
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
          } else if (this.filteredSourceCount === 0) {
            ListItem() {
              this.buildNoMatchState()
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
    Column({ space: AppSpace.Xs }) {
      Row() {
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

        if (!this.isLoading && !this.loadFailed && !this.isEditMode) {
          if (this.sourceCount > 0) {
            Button() {
              if (this.isBulkTesting) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(AppColor.Brand)
              } else {
                SymbolGlyph($r('sys.symbol.bolt_fill'))
                  .fontSize(20)
                  .fontColor([AppColor.Brand])
              }
            }
            .width(36)
            .height(36)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .borderRadius(AppRadius.Pill)
            .enabled(!this.isBulkTesting && !this.isImporting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_bulk_action'))
            .onClick(() => this.confirmBulkTest())
          }

          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([AppColor.Brand])
          }
          .width(36)
          .height(36)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(AppRadius.Pill)
          .accessibilityText('新建书源')
          .onClick(() => this.createNewSource())

          Button() {
            Text(this.showImportPanel ? $r('app.string.rule_source_close_import') :
              $r('app.string.rule_source_import_short'))
              .fontSize(AppFont.Body)
              .fontColor(AppColor.Brand)
          }
          .height(36)
          .constraintSize({ minWidth: 0 })
          .padding({ left: AppSpace.Xs, right: AppSpace.Xxs })
          .backgroundColor(Color.Transparent)
          .borderRadius(AppRadius.Sm)
          .accessibilityText(this.showImportPanel ? $r('app.string.rule_source_close_import') :
            $r('app.string.rule_source_import_title'))
          .onClick(() => this.toggleImportPanel())
        }

        if (!this.isLoading && !this.loadFailed && this.sourceCount > 0) {
          Text(this.isEditMode ? $r('app.string.common_done') : $r('app.string.rule_source_manage'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .padding({ left: AppSpace.Xxs, right: 0, top: AppSpace.Xs, bottom: AppSpace.Xs })
            .onClick(() => this.toggleEditMode())
        }
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xs,
        left: AppSpace.Xs,
        right: AppSpace.Md,
        bottom: 0
      })

      if (!this.isLoading && !this.loadFailed && this.sourceCount > 0) {
        Stack({ alignContent: Alignment.Start }) {
          TextInput({
            placeholder: $r('app.string.rule_source_search_placeholder'),
            text: $$this.searchKeyword
          })
            .width('100%')
            .height(40)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.background_primary'))
            .borderRadius(AppRadius.Sm)
            .padding({ left: 38, right: AppSpace.Sm })
            .enabled(!this.isEditMode && !this.isImporting && !this.isBulkTesting &&
              this.busySourceUrl.length === 0)
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.applyFilters();
            })

          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_tertiary')])
            .margin({ left: AppSpace.Sm })
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }

      if (this.isEditMode) {
        Column({ space: AppSpace.Xs }) {
          Row() {
            Text(this.selectedSourceCount > 0 ?
              $r('app.string.rule_source_selected_count', this.selectedSourceCount) :
              $r('app.string.rule_source_select_hint'))
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)

            Text(this.areAllVisibleSourcesSelected() ? $r('app.string.rule_source_deselect_all') :
              $r('app.string.rule_source_select_all'))
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs, bottom: AppSpace.Xs })
              .borderRadius(AppRadius.Sm)
              .backgroundColor(AppColor.BrandSoft)
              .onClick(() => this.selectAllSources())
          }

          Row({ space: AppSpace.Xs }) {
            Button($r('app.string.rule_source_batch_enable'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .backgroundColor(AppColor.BrandSoft)
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.batchEnableSelected(true))

            Button($r('app.string.rule_source_batch_disable'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .backgroundColor($r('sys.color.comp_background_primary'))
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.batchEnableSelected(false))

            Button($r('app.string.rule_source_batch_delete'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .height(36)
              .fontSize(AppFont.Caption)
              .fontColor(RULE_SOURCE_DANGER)
              .backgroundColor(Color.Transparent)
              .borderRadius(AppRadius.Sm)
              .enabled(this.selectedSourceCount > 0 && this.busySourceUrl.length === 0)
              .onClick(() => this.confirmBatchDelete())
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })
      }
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_secondary'))
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
        Text($r('app.string.rule_source_bulk_retained'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        Text(`${this.bulkTestRetained}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: AppSpace.Xs, right: AppSpace.Xs, bottom: AppSpace.Xxs })
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
  buildNoMatchState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(32)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.rule_source_no_match'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.rule_source_no_match_hint'))
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
    Column({ space: AppSpace.Xs }) {
      Row({ space: AppSpace.Sm }) {
        if (this.isEditMode) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isSourceSelected(source.bookSourceUrl, this.selectionRevision)) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([AppColor.OnBrand])
            }
          }
            .width(24)
            .height(24)
            .backgroundColor(this.isSourceSelected(source.bookSourceUrl, this.selectionRevision) ?
              AppColor.Brand : Color.Transparent)
            .border({
              width: 1.5,
              color: this.isSourceSelected(source.bookSourceUrl, this.selectionRevision) ?
                AppColor.Brand : $r('sys.color.font_tertiary')
            })
            .borderRadius(AppRadius.Pill)
            .accessibilityText($r('app.string.rule_source_select_hint'))
            .onClick(() => this.toggleSelectSource(source.bookSourceUrl))
        }

        Column({ space: 6 }) {
          Row({ space: AppSpace.Xs }) {
            Text(source.bookSourceName)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')

          Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center, wrap: FlexWrap.Wrap }) {
            Text(this.sourceTypeLabel(source))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))

            if (this.sourceGroupLabels(source).length > 0) {
              ForEach(this.sourceGroupLabels(source), (groupName: string) => {
                Text(groupName)
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .margin({ left: AppSpace.Xs })
                  .backgroundColor($r('sys.color.background_secondary'))
                  .borderRadius(AppRadius.Xs)
              }, (groupName: string) => groupName)
            }
          }
          .width('100%')

          Text(source.bookSourceUrl)
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.Brand)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.isEditMode) {
          Toggle({ type: ToggleType.Switch, isOn: source.enabled && source.canExecute() })
            .enabled(source.canExecute() && !this.isImporting && !this.isBulkTesting &&
              this.busySourceUrl.length === 0)
            .onChange((isOn: boolean) => this.changeEnabled(source, isOn))
        }
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

      if (!this.isEditMode) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))

        Row({ space: AppSpace.Xs }) {
          Button() {
            Row({ space: AppSpace.Xxs }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(16)
                .fontColor([AppColor.Brand])
              Text('编辑')
                .fontSize(AppFont.Caption)
                .fontColor(AppColor.Brand)
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(36)
          .constraintSize({ minWidth: 0 })
          .backgroundColor(AppColor.BrandSoft)
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .onClick(() => this.editSource(source))

          Button() {
            Row({ space: AppSpace.Xxs }) {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(16)
                .fontColor([AppColor.Brand])
              Text('调试')
                .fontSize(AppFont.Caption)
                .fontColor(AppColor.Brand)
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(36)
          .constraintSize({ minWidth: 0 })
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .onClick(() => this.debugSource(source))

          Button() {
            Row({ space: AppSpace.Xxs }) {
              SymbolGlyph($r('sys.symbol.bolt'))
                .fontSize(16)
                .fontColor([source.canExecute() ? AppColor.Brand : $r('sys.color.font_tertiary')])
              Text($r('app.string.rule_source_test_action'))
                .fontSize(AppFont.Caption)
                .fontColor(source.canExecute() ? AppColor.Brand : $r('sys.color.font_tertiary'))
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(36)
          .constraintSize({ minWidth: 0 })
          .backgroundColor(source.canExecute() ? AppColor.BrandSoft : Color.Transparent)
          .borderRadius(AppRadius.Sm)
          .enabled(source.canExecute() && !this.isImporting && !this.isBulkTesting &&
            this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_test_action'))
          .onClick(() => this.testSource(source))

          if (RuleSourceAccountService.supports(source.bookSourceUrl)) {
            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.person_fill'))
                  .fontSize(16)
                  .fontColor([AppColor.Brand])
                Text($r('app.string.rule_source_account_action'))
                  .fontSize(AppFont.Caption)
                  .fontColor(AppColor.Brand)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor($r('sys.color.background_secondary'))
            .borderRadius(AppRadius.Sm)
            .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_account_action'))
            .onClick(() => this.openMainAccount(source))
          }

          if (RuleSourceChildService.supports(source.bookSourceUrl)) {
            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(16)
                  .fontColor([AppColor.Brand])
                Text($r('app.string.rule_source_child_action'))
                  .fontSize(AppFont.Caption)
                  .fontColor(AppColor.Brand)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor($r('sys.color.background_secondary'))
            .borderRadius(AppRadius.Sm)
            .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_child_action'))
            .onClick(() => this.openSourceChildren(source))
          } else if (this.canOpenSourceLogin(source)) {
            Button() {
              Row({ space: AppSpace.Xxs }) {
                SymbolGlyph($r('sys.symbol.person_fill'))
                  .fontSize(16)
                  .fontColor([AppColor.Brand])
                Text($r('app.string.rule_source_login_action'))
                  .fontSize(AppFont.Caption)
                  .fontColor(AppColor.Brand)
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(36)
            .constraintSize({ minWidth: 0 })
            .backgroundColor($r('sys.color.background_secondary'))
            .borderRadius(AppRadius.Sm)
            .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
            .accessibilityText($r('app.string.rule_source_login_action'))
            .onClick(() => this.openSourceLogin(source))
          }

          Button() {
            Row({ space: AppSpace.Xxs }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(16)
                .fontColor([RULE_SOURCE_DANGER])
              Text($r('app.string.rule_source_delete_action'))
                .fontSize(AppFont.Caption)
                .fontColor(RULE_SOURCE_DANGER)
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(36)
          .constraintSize({ minWidth: 0 })
          .backgroundColor(RULE_SOURCE_DANGER_SOFT)
          .borderRadius(AppRadius.Sm)
          .enabled(!this.isImporting && !this.isBulkTesting && this.busySourceUrl.length === 0)
          .accessibilityText($r('app.string.rule_source_delete_action'))
          .onClick(() => this.confirmDelete(source))
        }
        .width('100%')
        .height(36)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
    .border({ width: 1, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 6, color: AppColor.Shadow, offsetY: 2 })
  }
}
