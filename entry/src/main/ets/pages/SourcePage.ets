import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { BookSource, SourceSubscription } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SourceDataSource } from '../utils/SourceDataSource';
import { SourceListItem } from '../components/SourceListItem';
import { WindowUtils } from '../utils/WindowUtils';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { emitter } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';

export const EVT_SOURCES_CHANGED = 'app.sources.changed';

function emitSourcesChanged(): void {
  emitter.emit(EVT_SOURCES_CHANGED);
}

enum ImportMethod {
  Network = 0,
  LocalFile = 1
}

interface ImportResult {
  success: number;
  failed: number;
  duplicate: number;
  sources: BookSource[];
}

@ComponentV2
export struct SourcePage {
  @Local subscriptions: SourceSubscription[] = [];
  @Local allSources: BookSource[] = [];
  @Local showAddSheet: boolean = false;
  @Local inputUrl: string = '';
  @Local inputName: string = '';
  @Local isLoading: boolean = false;
  @Local loadingUrl: string = '';
  @Local activeTab: number = 0;
  @Local sourceTypeFilter: number = -1;
  @Local importMethod: ImportMethod = ImportMethod.Network;
  @Local statusMessage: string = '';
  @Local showPreview: boolean = false;
  @Local previewSources: BookSource[] = [];
  @Local selectedPreviewIds: Set<string> = new Set();
  @Local headerOffset: number = 0;
  @Local isSelectMode: boolean = false;
  @Local selectedSourceUrls: Set<string> = new Set();
  @Local isRefreshing: boolean = false;

  @Local isSelectAll: boolean = false;

  private readonly COLLAPSE_HEIGHT: number = 56;
  private readonly TAB_HEIGHT: number = 40;
  // 浮动批量操作栏要抬到 MiniPlayer 之上,与 MainPage 的浮层布局对齐:
  // bottomSafe + barBottomMargin(12) + floatingTab(60) + gap(12) + miniPlayer(60) + gap(12) = bottomSafe + 156
  private readonly BATCH_BAR_BOTTOM_VP: number = 156;
  private subScroller: Scroller = new Scroller();
  private srcScroller: Scroller = new Scroller();
  private context: common.UIAbilityContext | null = null;
  private sourceDataSource: SourceDataSource = new SourceDataSource();

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadData();
  }
  private async loadData(): Promise<void> {
    try {
      this.subscriptions = await SourceDataService.getSubscriptions();
      this.allSources = await SourceDataService.getSources();
      this.applySourceFilter();
    } catch (_e) {
      this.subscriptions = [];
      this.allSources = [];
      this.applySourceFilter();
    }
  }

  /**
   * 下拉刷新:批量重拉所有订阅源 → 替换 allSources。
   * 顺序遍历(避免一次性发 N 个并发请求把对方服务打瘫),失败的订阅保持旧数据。
   */
  private async refreshAllSubscriptions(): Promise<void> {
    if (this.subscriptions.length === 0) {
      // 没订阅源时下拉刷新等同 loadData(从本地重读)
      await this.loadData();
      return;
    }
    let okCount = 0;
    let failCount = 0;
    // 先拿当前所有书源,等会拿"非订阅源"那部分留住(本地导入的不要被刷掉)
    const currentAll = await SourceDataService.getSources();
    const subUrlSet = new Set(this.subscriptions.map((s: SourceSubscription): string => s.url));
    const nonSubscribed = currentAll.filter((s: BookSource): boolean =>
      !s.subscriptionUrl || !subUrlSet.has(s.subscriptionUrl));

    const refreshed: BookSource[] = [];
    for (let i = 0; i < this.subscriptions.length; i++) {
      const sub = this.subscriptions[i];
      try {
        const sources = await BookSourceService.fetchSourcesFromUrl(sub.url);
        for (const src of sources) {
          src.subscriptionUrl = sub.url;
        }
        refreshed.push(...sources);
        // 更新订阅元数据(count / lastUpdate)
        const customName = sub.name;
        this.subscriptions[i] = BookSourceService.buildSubscription(sub.url, sources);
        if (customName && customName !== '加载失败') {
          this.subscriptions[i].name = customName;
        }
        okCount++;
      } catch (_e) {
        // 失败:保留这条订阅源原有的书源(从 currentAll 里挑出来)
        const old = currentAll.filter((s: BookSource): boolean => s.subscriptionUrl === sub.url);
        refreshed.push(...old);
        failCount++;
      }
    }
    const merged = nonSubscribed.concat(refreshed);
    await SourceDataService.saveSources(merged);
    await this.saveSubscriptions();
    this.allSources = await SourceDataService.getSources();
    this.applySourceFilter();
    emitSourcesChanged();
    promptAction.showToast({
      message: failCount === 0
        ? `已刷新 ${okCount} 个订阅源`
        : `刷新完成:${okCount} 成功,${failCount} 失败`
    });
  }

  private applySourceFilter(): void {
    const list = this.sourceTypeFilter < 0
      ? this.allSources
      : this.allSources.filter((s: BookSource): boolean =>
          (s.bookSourceType ?? 0) === this.sourceTypeFilter);
    this.sourceDataSource.setSources(list);
  }

  private setSourceTypeFilter(type: number): void {
    if (this.sourceTypeFilter === type) return;
    this.sourceTypeFilter = type;
    this.applySourceFilter();
    if (this.isSelectMode) {
      this.exitSelectMode();
    }
  }

  private getFilterLabel(): string {
    switch (this.sourceTypeFilter) {
      case 0: return '小说';
      case 1: return '有声书';
      case 2: return '漫画';
      case 3: return '文件';
      default: return '全部';
    }
  }

  private countSourcesByType(type: number): number {
    if (type < 0) return this.allSources.length;
    let n = 0;
    for (const s of this.allSources) {
      if ((s.bookSourceType ?? 0) === type) n++;
    }
    return n;
  }

  private async saveSubscriptions(): Promise<void> {
    await SourceDataService.saveSubscriptions(this.subscriptions);
  }

  private async addSource(): Promise<void> {
    const url = this.inputUrl.trim();
    if (!url) return;
    if (this.subscriptions.some((s: SourceSubscription): boolean => s.url === url)) {
      promptAction.showToast({ message: '该书源已存在' });
      return;
    }
    this.isLoading = true;
    this.loadingUrl = url;
    this.statusMessage = '正在获取书源...';
    try {
      const sources = await BookSourceService.fetchSourcesFromUrl(url);
      const result = await this.importSources(sources, url);
      this.statusMessage = `导入成功！共 ${result.success} 个书源`;
      if (result.duplicate > 0) {
        this.statusMessage += `，跳过 ${result.duplicate} 个重复`;
      }
      promptAction.showToast({ message: this.statusMessage });
      this.inputUrl = '';
      this.inputName = '';
      this.showAddSheet = false;
    } catch (e) {
      this.statusMessage = '网络请求失败，请检查网络后重试';
      promptAction.showToast({ message: this.statusMessage });
      const customName = this.inputName.trim();
      const sub: SourceSubscription = {
        url, name: customName || '加载失败', count: 0, lastUpdate: Date.now()
      };
      this.subscriptions.push(sub);
      await this.saveSubscriptions();
    }
    this.isLoading = false;
    this.loadingUrl = '';
  }

  private async importSources(sources: BookSource[], url: string): Promise<ImportResult> {
    const result: ImportResult = { success: 0, failed: 0, duplicate: 0, sources: [] };
    const existingUrls = new Set(this.allSources.map((s: BookSource): string => s.bookSourceUrl));

    for (const source of sources) {
      if (existingUrls.has(source.bookSourceUrl)) {
        result.duplicate++;
      } else {
        source.subscriptionUrl = url; // 标记来源
        result.success++;
        result.sources.push(source);
      }
    }

    if (result.sources.length > 0) {
      await SourceDataService.addSources(result.sources);
      this.allSources = await SourceDataService.getSources();
      this.applySourceFilter();
      emitSourcesChanged();
    }

    const customName = this.inputName.trim();
    const sub = BookSourceService.buildSubscription(url, sources);
    if (customName) {
      sub.name = customName;
    }
    this.subscriptions.push(sub);
    await this.saveSubscriptions();

    return result;
  }
  private async pickLocalFile(): Promise<void> {
    try {
      if (!this.context) return;
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.json', '.txt'];
      const dp = new picker.DocumentViewPicker(this.context);
      const uris = await dp.select(opt);
      if (!uris || uris.length === 0) return;

      this.isLoading = true;
      this.statusMessage = '正在解析文件...';

      const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const size = Math.min(stat.size, 5 * 1024 * 1024);
      const buf = new ArrayBuffer(size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file);

      const decoder = util.TextDecoder.create('utf-8');
      const content = decoder.decodeToString(new Uint8Array(buf));
      const sources: BookSource[] = BookSourceService.parseSourcesFromJson(content);

      if (sources.length === 0) {
        this.statusMessage = '书源格式错误，请确认文件内容是否正确';
        promptAction.showToast({ message: this.statusMessage });
        this.isLoading = false;
        return;
      }

      this.previewSources = sources;
      this.selectedPreviewIds = new Set(sources.map((s: BookSource): string => s.bookSourceUrl));
      this.showPreview = true;
      this.isLoading = false;
    } catch (e) {
      this.statusMessage = '文件读取失败';
      promptAction.showToast({ message: this.statusMessage });
      this.isLoading = false;
    }
  }

  private async confirmImportPreview(): Promise<void> {
    const selected = this.previewSources.filter((s: BookSource): boolean =>
      this.selectedPreviewIds.has(s.bookSourceUrl));
    if (selected.length === 0) {
      promptAction.showToast({ message: '请至少选择一个书源' });
      return;
    }

    this.isLoading = true;
    this.statusMessage = '正在导入...';

    const result: ImportResult = { success: 0, failed: 0, duplicate: 0, sources: [] };
    const existingUrls = new Set(this.allSources.map((s: BookSource): string => s.bookSourceUrl));

    for (const source of selected) {
      if (existingUrls.has(source.bookSourceUrl)) {
        result.duplicate++;
      } else {
        // 本地导入的书源不标记 subscriptionUrl（留空）
        result.success++;
        result.sources.push(source);
      }
    }

    if (result.sources.length > 0) {
      await SourceDataService.addSources(result.sources);
      this.allSources = await SourceDataService.getSources();
      this.applySourceFilter();
      emitSourcesChanged();
    }

    this.statusMessage = `导入成功！共 ${result.success} 个书源`;
    if (result.duplicate > 0) {
      this.statusMessage += `，跳过 ${result.duplicate} 个重复`;
    }
    promptAction.showToast({ message: this.statusMessage });

    this.showPreview = false;
    this.showAddSheet = false;
    this.previewSources = [];
    this.selectedPreviewIds.clear();
    this.isLoading = false;
  }

  private togglePreviewSelection(sourceUrl: string): void {
    if (this.selectedPreviewIds.has(sourceUrl)) {
      this.selectedPreviewIds.delete(sourceUrl);
    } else {
      this.selectedPreviewIds.add(sourceUrl);
    }
    this.selectedPreviewIds = new Set(this.selectedPreviewIds);
  }

  private toggleAllPreview(): void {
    if (this.selectedPreviewIds.size === this.previewSources.length) {
      this.selectedPreviewIds.clear();
    } else {
      this.selectedPreviewIds = new Set(this.previewSources.map((s: BookSource): string => s.bookSourceUrl));
    }
  }

  private async refreshSource(index: number): Promise<void> {
    const sub = this.subscriptions[index];
    this.isLoading = true;
    this.loadingUrl = sub.url;
    try {
      const sources = await BookSourceService.fetchSourcesFromUrl(sub.url);
      this.subscriptions[index] = BookSourceService.buildSubscription(sub.url, sources);
      await this.saveSubscriptions();
      if (sources.length > 0) {
        // 给新书源打上订阅源标记
        for (const source of sources) {
          source.subscriptionUrl = sub.url;
        }
        // 获取当前所有书源，删除该订阅源的旧书源
        const allSources = await SourceDataService.getSources();
        const otherSources = allSources.filter((s: BookSource) => s.subscriptionUrl !== sub.url);
        // 合并：其他订阅源的书源 + 刚刷新的书源
        const merged = otherSources.concat(sources);
        await SourceDataService.saveSources(merged);
        this.allSources = await SourceDataService.getSources();
        this.applySourceFilter();
        emitSourcesChanged();
      }
    } catch (_e) { /* ignore */ }
    this.isLoading = false;
    this.loadingUrl = '';
  }

  private async deleteSubscription(index: number): Promise<void> {
    const sub = this.subscriptions[index];
    this.subscriptions.splice(index, 1);
    await this.saveSubscriptions();
    if (!sub) return;
    // 同步删除该订阅源下的所有书源
    const remaining = this.allSources.filter((s: BookSource): boolean =>
      s.subscriptionUrl !== sub.url);
    const removed = this.allSources.length - remaining.length;
    if (removed > 0) {
      await SourceDataService.saveSources(remaining);
      this.allSources = remaining;
      this.applySourceFilter();
      emitSourcesChanged();
      promptAction.showToast({ message: `已删除订阅及其下 ${removed} 个书源` });
    } else {
      promptAction.showToast({ message: '已删除订阅' });
    }
  }

  private async toggleSourceEnabled(source: BookSource): Promise<void> {
    // 注意：调用方（onToggleEnabled / Switch.onChange）已经把 source.enabled 设成最新值，
    // 这里只负责落盘 + 刷新 UI，不要再翻一次。
    await SourceDataService.saveSources(this.allSources);
    this.allSources = [...this.allSources];
    this.applySourceFilter();
    emitSourcesChanged();
  }

  private enterSelectMode(sourceUrl: string): void {
    this.isSelectMode = true;
    this.isSelectAll = false;
    this.selectedSourceUrls = new Set([sourceUrl]);
  }

  private exitSelectMode(): void {
    this.isSelectMode = false;
    this.isSelectAll = false;
    this.selectedSourceUrls = new Set();
  }

  private toggleSourceSelection(sourceUrl: string): void {
    if (this.isSelectAll) {
      this.isSelectAll = false;
      this.selectedSourceUrls = new Set(
        this.allSources
          .filter((s: BookSource): boolean => s.bookSourceUrl !== sourceUrl)
          .map((s: BookSource): string => s.bookSourceUrl)
      );
    } else {
      if (this.selectedSourceUrls.has(sourceUrl)) {
        this.selectedSourceUrls.delete(sourceUrl);
      } else {
        this.selectedSourceUrls.add(sourceUrl);
      }
      this.selectedSourceUrls = new Set(this.selectedSourceUrls);
    }
    if (!this.isSelectAll && this.selectedSourceUrls.size === 0) {
      this.isSelectMode = false;
    }
  }

  private selectAllSources(): void {
    this.isSelectAll = !this.isSelectAll;
    this.selectedSourceUrls = new Set();
  }

  private isSourceSelected(sourceUrl: string): boolean {
    if (this.isSelectAll) {
      return !this.selectedSourceUrls.has(sourceUrl);
    }
    return this.selectedSourceUrls.has(sourceUrl);
  }

  private getSelectedCount(): number {
    if (this.isSelectAll) {
      return this.allSources.length - this.selectedSourceUrls.size;
    }
    return this.selectedSourceUrls.size;
  }

  private async deleteSelectedSources(): Promise<void> {
    const count = this.getSelectedCount();
    if (count === 0) return;
    let remaining: BookSource[];
    if (this.isSelectAll) {
      remaining = this.allSources.filter((s: BookSource): boolean =>
        this.selectedSourceUrls.has(s.bookSourceUrl));
    } else {
      remaining = this.allSources.filter((s: BookSource): boolean =>
        !this.selectedSourceUrls.has(s.bookSourceUrl));
    }
    await SourceDataService.saveSources(remaining);
    this.allSources = remaining;
    this.applySourceFilter();
    emitSourcesChanged();
    promptAction.showToast({ message: `已删除 ${count} 个书源` });
    this.exitSelectMode();
  }

  private invertSelection(): void {
    if (this.isSelectAll) {
      const excluded = new Set(this.selectedSourceUrls);
      this.isSelectAll = false;
      this.selectedSourceUrls = excluded;
    } else {
      const selected = new Set(this.selectedSourceUrls);
      this.isSelectAll = true;
      this.selectedSourceUrls = selected;
    }
    if (!this.isSelectAll && this.selectedSourceUrls.size === 0) {
      this.isSelectMode = false;
    }
  }

  private async batchSetEnabled(enabled: boolean): Promise<void> {
    for (const source of this.allSources) {
      if (this.isSourceSelected(source.bookSourceUrl)) {
        source.enabled = enabled;
      }
    }
    await SourceDataService.saveSources(this.allSources);
    this.allSources = [...this.allSources];
    this.applySourceFilter();
    emitSourcesChanged();
    const count = this.getSelectedCount();
    promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 个书源` });
    this.exitSelectMode();
  }
  private updateHeaderOffset(scroller: Scroller): void {
    const offset = scroller.currentOffset();
    if (!offset) return;
    let h = offset.yOffset;
    if (h < 0) h = 0;
    if (h > this.COLLAPSE_HEIGHT) h = this.COLLAPSE_HEIGHT;
    if (Math.abs(h - this.headerOffset) >= 0.5) {
      this.headerOffset = h;
    }
  }

  private collapseRatio(): number {
    return this.headerOffset / this.COLLAPSE_HEIGHT;
  }

  build() {
    Column() {
      // 顶部固定区域(标题 + Tab 切换)
      Column() {
        Column() {
          Row() {
            Text('书源管理')
              .fontSize(AppFont.TitleL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Blank()
            if (this.isSelectMode) {
              Text('取消')
                .fontSize(AppFont.Body)
                .fontColor(AppColor.Brand)
                .onClick(() => this.exitSelectMode())
            } else {
              Row({ space: AppSpace.Sm }) {
                SymbolGlyph($r('sys.symbol.questionmark_circle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.font_tertiary')])
                  .onClick(() => {
                    promptAction.showToast({ message: '长按书源可进入批量管理模式' });
                  })
                SymbolGlyph($r('sys.symbol.plus_circle'))
                  .fontSize(22)
                  .fontColor([AppColor.Brand])
                  .onClick(() => {
                    this.showAddSheet = true;
                    this.statusMessage = '';
                    this.importMethod = ImportMethod.Network;
                    this.inputName = '';
                  })
              }
            }
          }
          .width('100%')
          .padding({
            top: WindowUtils.getStatusBarHeightVp() + AppSpace.Lg,
            left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm
          })
        }
        .width('100%')
        .height(this.COLLAPSE_HEIGHT * (1 - this.collapseRatio()) + WindowUtils.getStatusBarHeightVp())
        .opacity(1 - this.collapseRatio())
        .clip(true)

        Row() {
          this.buildTabItem('订阅源', 0)
          this.buildTabItem('全部书源', 1)
          Blank()
          if (this.isSelectMode) {
            Text(`已选 ${this.getSelectedCount()}`)
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
          } else if (this.activeTab === 1) {
            this.buildFilterPill()
          }
        }
        .width('100%')
        .height(this.TAB_HEIGHT)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }
      .width('100%')

      // 内容区域(占满剩余空间,Refresh 自然在 header 下方)
      Stack({ alignContent: Alignment.TopStart }) {
        Tabs({ index: this.activeTab, barPosition: BarPosition.Start }) {
          TabContent() {
            this.buildSubscriptionList()
          }

          TabContent() {
            this.buildSourceList()
          }
        }
        .barHeight(0)
        .scrollable(true)
        .animationDuration(220)
        .onChange((index: number) => {
          this.activeTab = index;
          if (this.isSelectMode && index !== 1) {
            this.exitSelectMode();
          }
          const hasContent = index === 0
            ? this.subscriptions.length > 0
            : this.allSources.length > 0;
          if (!hasContent) {
            this.headerOffset = 0;
            return;
          }
          const s = index === 0 ? this.subScroller : this.srcScroller;
          this.updateHeaderOffset(s);
        })
        .width('100%')
        .height('100%')

        if (this.isSelectMode) {
          Column() {
            this.buildBatchActionBar()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .position({ bottom: WindowUtils.getBottomSafeVp() + this.BATCH_BAR_BOTTOM_VP })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAddSheet, this.importSheetContent(), {
      height: SheetSize.LARGE,
      dragBar: true,
      onDisappear: () => {
        this.statusMessage = '';
        this.inputUrl = '';
        this.inputName = '';
        this.showPreview = false;
        this.previewSources = [];
        this.selectedPreviewIds = new Set();
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  @Builder
  buildTabItem(title: string, idx: number) {
    Text(title)
      .fontSize(14)
      .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeTab === idx ? Color.White : $r('sys.color.font_primary'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.activeTab === idx ? '#E6000000' : '#B3FFFFFF')
      .backdropBlur(this.collapseRatio() > 0.5 ? (this.activeTab === idx ? 20 : 15) : 0)
      .border({ width: 0.5, color: this.activeTab === idx ? '#33FFFFFF' : '#33000000' })
      .shadow(this.activeTab === idx
        ? { radius: 6, color: '#33000000', offsetY: 2 }
        : { radius: 4, color: '#11000000', offsetY: 1 })
      .margin({ right: AppSpace.Sm })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .onClick(() => { this.activeTab = idx; })
  }

  @Builder
  buildFilterPill() {
    Row({ space: 4 }) {
      Text(`${this.getFilterLabel()} ${this.countSourcesByType(this.sourceTypeFilter)}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.sourceTypeFilter < 0 ? $r('sys.color.font_primary') : AppColor.Brand)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([this.sourceTypeFilter < 0 ? $r('sys.color.font_secondary') : AppColor.Brand])
    }
    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.sourceTypeFilter < 0 ? '#B3FFFFFF' : '#1A0A59F7')
    .border({ width: 0.5, color: this.sourceTypeFilter < 0 ? '#22000000' : '#330A59F7' })
    .shadow({ radius: 4, color: '#11000000', offsetY: 1 })
    .bindMenu(this.buildFilterMenu(), { placement: Placement.BottomRight })
  }

  @Builder
  buildFilterMenu() {
    Menu() {
      MenuItem({ content: `全部  ${this.countSourcesByType(-1)}` })
        .selected(this.sourceTypeFilter === -1)
        .selectIcon(true)
        .onChange(() => this.setSourceTypeFilter(-1))
      MenuItem({ content: `小说  ${this.countSourcesByType(0)}` })
        .selected(this.sourceTypeFilter === 0)
        .selectIcon(true)
        .onChange(() => this.setSourceTypeFilter(0))
      MenuItem({ content: `有声书  ${this.countSourcesByType(1)}` })
        .selected(this.sourceTypeFilter === 1)
        .selectIcon(true)
        .onChange(() => this.setSourceTypeFilter(1))
      MenuItem({ content: `漫画  ${this.countSourcesByType(2)}` })
        .selected(this.sourceTypeFilter === 2)
        .selectIcon(true)
        .onChange(() => this.setSourceTypeFilter(2))
      MenuItem({ content: `文件  ${this.countSourcesByType(3)}` })
        .selected(this.sourceTypeFilter === 3)
        .selectIcon(true)
        .onChange(() => this.setSourceTypeFilter(3))
    }
  }

  @Builder
  buildBatchActionBar() {
    Column({ space: AppSpace.Xs }) {
      Row({ space: AppSpace.Xs }) {
        this.buildPillButton(this.isSelectAll ? '取消全选' : '全选',
          this.isSelectAll ? AppColor.Brand : $r('sys.color.font_primary'),
          this.isSelectAll ? '#1A0A59F7' : '#B3FFFFFF',
          () => this.selectAllSources())
        this.buildPillButton('反选', $r('sys.color.font_primary'), '#B3FFFFFF',
          () => this.invertSelection())
        this.buildPillButton('启用', '#34C759', '#1A34C759',
          () => this.batchSetEnabled(true))
        this.buildPillButton('禁用', '#FF9500', '#1AFF9500',
          () => this.batchSetEnabled(false))
      }
      Row({ space: AppSpace.Xs }) {
        this.buildPillButton(`删除 (${this.getSelectedCount()})`, Color.White,
          this.getSelectedCount() > 0 ? '#FF3B30' : '#CCCCCC',
          () => { if (this.getSelectedCount() > 0) this.deleteSelectedSources(); })
        this.buildPillButton('取消', $r('sys.color.font_primary'), '#B3FFFFFF',
          () => this.exitSelectMode())
      }
    }
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs, bottom: AppSpace.Xs })
    .borderRadius(AppRadius.Xl)
    .backgroundColor('#E6FFFFFF')
    .backdropBlur(20)
    .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
  }

  @Builder
  buildPillButton(label: string, fontColor: ResourceColor, bgColor: ResourceColor, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(fontColor)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(bgColor)
      .border({ width: 0.5, color: '#22000000' })
      .onClick(() => action())
  }

  @Builder
  importSheetContent() {
    if (this.showPreview) {
      this.previewSheet()
    } else {
      this.addSourceSheet()
    }
  }
  @Builder
  buildSubscriptionList() {
    if (this.subscriptions.length === 0) {
      Column({ space: AppSpace.Md }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(48)
          .fontColor(['#CCCCCC'])
        Text('暂无书源订阅')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_tertiary'))
        Text('点击右上角 + 添加书源订阅地址')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll(this.subScroller) {
          Column({ space: 0 }) {
            Column() {
              ForEach(this.subscriptions, (sub: SourceSubscription, idx: number) => {
                Row() {
                  Column({ space: 4 }) {
                    Text(sub.name)
                      .fontSize(AppFont.BodyL)
                      .fontColor($r('sys.color.font_secondary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(sub.url)
                      .fontSize(AppFont.Caption)
                      .fontColor($r('sys.color.font_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${sub.count} 个书源`)
                      .fontSize(AppFont.Caption)
                      .fontColor(AppColor.Brand)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.isLoading && this.loadingUrl === sub.url) {
                    LoadingProgress().width(20).height(20).color(AppColor.Brand)
                  } else {
                    Row({ space: AppSpace.Sm }) {
                      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                        .fontSize(18)
                        .fontColor([AppColor.Brand])
                        .onClick(() => this.refreshSource(idx))
                      SymbolGlyph($r('sys.symbol.trash'))
                        .fontSize(18)
                        .fontColor(['#FF4444'])
                        .onClick(() => this.deleteSubscription(idx))
                    }
                  }
                }
                .width('100%')
                .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })

                if (idx < this.subscriptions.length - 1) {
                  Divider().color($r('sys.color.comp_divider')).margin({ left: AppSpace.Lg, right: AppSpace.Lg })
                }
              }, (sub: SourceSubscription, _idx: number) => sub.url)
            }
            .backgroundColor($r('sys.color.comp_background_primary'))
            .borderRadius(AppRadius.Lg)
            .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: AppSpace.Sm, bottom: WindowUtils.getFloatingTabBottomVp() })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onDidScroll(() => {
          this.updateHeaderOffset(this.subScroller);
        })
      }
      .onRefreshing(() => {
        this.refreshAllSubscriptions().finally(() => { this.isRefreshing = false; });
      })
    }
  }
  @Builder
  buildSourceList() {
    if (this.allSources.length === 0) {
      Column({ space: AppSpace.Md }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(48)
          .fontColor(['#CCCCCC'])
        Text('暂无书源')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: $$this.isRefreshing }) {
        List({ scroller: this.srcScroller }) {
          ListItem() {
            Column().height(AppSpace.Sm)
          }

          LazyForEach(this.sourceDataSource, (source: BookSource) => {
            ListItem() {
              SourceListItem({
                source: source,
                isSelectMode: this.isSelectMode,
                isSelected: this.isSourceSelected(source.bookSourceUrl),
                onTap: () => {
                  if (this.isSelectMode) {
                    this.toggleSourceSelection(source.bookSourceUrl);
                  }
                },
                onLongPress: () => this.enterSelectMode(source.bookSourceUrl),
                onToggleEnabled: (isOn: boolean) => {
                  source.enabled = isOn;
                  this.toggleSourceEnabled(source);
                }
              })
                .reuse({ reuseId: () => this.isSelectMode ? 'select' : 'normal' })
            }
          }, (source: BookSource) => source.bookSourceUrl)

          ListItem() {
            Column().height(this.isSelectMode
              ? WindowUtils.getBottomSafeVp() + this.BATCH_BAR_BOTTOM_VP + 88
              : WindowUtils.getFloatingTabBottomVp())
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(10)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: AppSpace.Lg,
          endMargin: AppSpace.Lg
        })
        .onDidScroll(() => {
          this.updateHeaderOffset(this.srcScroller);
        })
      }
      .onRefreshing(() => {
        this.refreshAllSubscriptions().finally(() => { this.isRefreshing = false; });
      })
    }
  }
  @Builder
  addSourceSheet() {
    Column({ space: AppSpace.Lg }) {
      Row() {
        Text('导入书源')
          .fontSize(AppFont.TitleL)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text('支持 JSON / TXT 格式')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ left: AppSpace.Sm })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Row({ space: AppSpace.Sm }) {
        this.buildMethodCard('网络导入', '输入远程链接', $r('sys.symbol.link'), ImportMethod.Network)
        this.buildMethodCard('本地文件', '从文件管理选择', $r('sys.symbol.doc'), ImportMethod.LocalFile)
      }
      .width('100%')

      if (this.importMethod === ImportMethod.Network) {
        this.buildNetworkImport()
      } else {
        this.buildLocalFileImport()
      }

      if (this.statusMessage) {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph(this.statusMessage.includes('失败') || this.statusMessage.includes('错误') ?
            $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.checkmark_circle'))
            .fontSize(16)
            .fontColor([this.statusMessage.includes('失败') || this.statusMessage.includes('错误') ?
              '#FF3B30' : '#34C759'])
          Text(this.statusMessage)
            .fontSize(AppFont.Body)
            .fontColor(this.statusMessage.includes('失败') || this.statusMessage.includes('错误') ?
              '#FF3B30' : '#34C759')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: AppSpace.Sm })
      }
    }
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    .width('100%')
  }

  @Builder
  buildMethodCard(title: string, desc: string, icon: Resource, method: ImportMethod) {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph(icon)
        .fontSize(28)
        .fontColor([this.importMethod === method ? AppColor.Brand : $r('sys.color.font_tertiary')])
      Text(title)
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.importMethod === method ? AppColor.Brand : $r('sys.color.font_primary'))
      Text(desc)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
    .borderRadius(AppRadius.Lg)
    .backgroundColor(this.importMethod === method ? '#0D0A59F7' : $r('sys.color.comp_background_primary'))
    .border({
      width: 1.5,
      color: this.importMethod === method ? AppColor.Brand : Color.Transparent
    })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.importMethod = method;
      this.statusMessage = '';
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
  }
  @Builder
  buildNetworkImport() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Sm }) {
        Text('书源链接')
          .fontSize(AppFont.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        TextInput({ placeholder: 'https://xxx.com/source.json', text: this.inputUrl!! })
          .width('100%')
          .height(44)
          .borderRadius(AppRadius.Md)
          .backgroundColor($r('sys.color.comp_background_primary'))
      }

      Column({ space: AppSpace.Sm }) {
        Text('自定义名称（选填）')
          .fontSize(AppFont.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        TextInput({ placeholder: '为这个订阅源起个名字', text: this.inputName!! })
          .width('100%')
          .height(44)
          .borderRadius(AppRadius.Md)
          .backgroundColor($r('sys.color.comp_background_primary'))
      }

      Button(this.isLoading ? '加载中...' : '开始导入')
        .width('100%')
        .height(48)
        .backgroundColor(this.inputUrl.trim().length > 0 ? AppColor.Brand : '#CCCCCC')
        .fontColor(Color.White)
        .fontSize(AppFont.BodyL)
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading && this.inputUrl.trim().length > 0)
        .onClick(() => this.addSource())
    }
    .width('100%')
    .padding({ top: AppSpace.Sm })
  }

  @Builder
  buildLocalFileImport() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Xs }) {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_tertiary')])
          Text('支持 .json / .txt 格式书源文件')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(16)
            .fontColor(['#FF9500'])
          Text('请勿导入来源不明的书源')
            .fontSize(AppFont.Body)
            .fontColor('#FF9500')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button(this.isLoading ? '解析中...' : '选择文件')
        .width('100%')
        .height(48)
        .backgroundColor(AppColor.Brand)
        .fontColor(Color.White)
        .fontSize(AppFont.BodyL)
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading)
        .onClick(() => this.pickLocalFile())
    }
    .width('100%')
    .padding({ top: AppSpace.Sm })
  }

  @Builder
  previewSheet() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text(`待导入书源（${this.previewSources.length}个）`)
          .fontSize(AppFont.TitleL)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text(this.selectedPreviewIds.size === this.previewSources.length ? '反选' : '全选')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .onClick(() => this.toggleAllPreview())
      }
      .width('100%')

      Text(`已选 ${this.selectedPreviewIds.size} / ${this.previewSources.length} 个`)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      Scroll() {
        Column({ space: AppSpace.Xs }) {
          ForEach(this.previewSources, (source: BookSource) => {
            Row({ space: AppSpace.Md }) {
              Checkbox()
                .select(this.selectedPreviewIds.has(source.bookSourceUrl))
                .selectedColor(AppColor.Brand)
                .onChange(() => this.togglePreviewSelection(source.bookSourceUrl))

              Column({ space: AppSpace.Xs }) {
                Text(source.bookSourceName)
                  .fontSize(AppFont.BodyL)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(source.bookSourceUrl)
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(AppSpace.Md)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .borderRadius(AppRadius.Md)
            .onClick(() => this.togglePreviewSelection(source.bookSourceUrl))
          }, (source: BookSource) => source.bookSourceUrl)
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      Row({ space: AppSpace.Md }) {
        Button('取消')
          .layoutWeight(1)
          .height(48)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .fontColor($r('sys.color.font_primary'))
          .fontSize(AppFont.BodyL)
          .borderRadius(AppRadius.Md)
          .onClick(() => {
            this.showPreview = false;
            this.previewSources = [];
            this.selectedPreviewIds.clear();
          })

        Button(this.isLoading ? '导入中...' : `确认导入（${this.selectedPreviewIds.size}）`)
          .layoutWeight(2)
          .height(48)
          .backgroundColor(this.selectedPreviewIds.size > 0 ? AppColor.Brand : '#CCCCCC')
          .fontColor(Color.White)
          .fontSize(AppFont.BodyL)
          .borderRadius(AppRadius.Md)
          .enabled(!this.isLoading && this.selectedPreviewIds.size > 0)
          .onClick(() => this.confirmImportPreview())
      }
      .width('100%')
    }
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    .width('100%')
    .height('100%')
  }
}
