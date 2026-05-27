import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { BookSource, SourceSubscription } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { WindowUtils } from '../utils/WindowUtils';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';

enum ImportMethod {
  Network = 0,
  LocalFile = 1,
  Clipboard = 2
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
  @Local isLoading: boolean = false;
  @Local loadingUrl: string = '';
  @Local activeTab: number = 0;
  @Local importMethod: ImportMethod = ImportMethod.Network;
  @Local statusMessage: string = '';
  @Local showPreview: boolean = false;
  @Local previewSources: BookSource[] = [];
  @Local selectedPreviewIds: Set<string> = new Set();
  @Local headerOffset: number = 0;

  private readonly COLLAPSE_HEIGHT: number = 56;
  private readonly TAB_HEIGHT: number = 40;
  private subScroller: Scroller = new Scroller();
  private srcScroller: Scroller = new Scroller();
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.subscriptions = await SourceDataService.getSubscriptions();
      this.allSources = await SourceDataService.getSources();
    } catch (_e) {
      this.subscriptions = [];
      this.allSources = [];
    }
  }

  private async saveSubscriptions(): Promise<void> {
    await SourceDataService.saveSubscriptions(this.subscriptions);
  }

  private async addSource(): Promise<void> {
    const url = this.inputUrl.trim();
    if (!url) return;
    if (this.subscriptions.some((s: SourceSubscription): boolean => s.url === url)) {
      this.statusMessage = '该书源已存在';
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
      this.showAddSheet = false;
    } catch (e) {
      this.statusMessage = '网络请求失败，请检查网络后重试';
      promptAction.showToast({ message: this.statusMessage });
      const sub: SourceSubscription = { url, name: '加载失败', count: 0, lastUpdate: Date.now() };
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
        result.success++;
        result.sources.push(source);
      }
    }

    if (result.sources.length > 0) {
      await SourceDataService.addSources(result.sources);
      this.allSources = await SourceDataService.getSources();
    }

    const sub = BookSourceService.buildSubscription(url, sources);
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

  private async importFromClipboard(): Promise<void> {
    try {
      const pb = pasteboard.getSystemPasteboard();
      const hasData = await pb.hasData();
      if (!hasData) {
        this.statusMessage = '剪贴板为空';
        promptAction.showToast({ message: this.statusMessage });
        return;
      }

      this.isLoading = true;
      this.statusMessage = '正在读取剪贴板...';

      const data = await pb.getData();
      const text = data.getPrimaryText() || '';

      if (!text) {
        this.statusMessage = '剪贴板未检测到有效内容';
        promptAction.showToast({ message: this.statusMessage });
        this.isLoading = false;
        return;
      }

      const sources: BookSource[] = BookSourceService.parseSourcesFromJson(text);

      if (sources.length === 0) {
        this.statusMessage = '剪贴板未检测到有效书源';
        promptAction.showToast({ message: this.statusMessage });
        this.isLoading = false;
        return;
      }

      this.statusMessage = `已读取 ${sources.length} 个书源`;
      this.previewSources = sources;
      this.selectedPreviewIds = new Set(sources.map((s: BookSource): string => s.bookSourceUrl));
      this.showPreview = true;
      this.isLoading = false;
    } catch (e) {
      this.statusMessage = '读取剪贴板失败';
      promptAction.showToast({ message: this.statusMessage });
      this.isLoading = false;
    }
  }

  private async confirmImportPreview(): Promise<void> {
    const selected = this.previewSources.filter((s: BookSource): boolean => this.selectedPreviewIds.has(s.bookSourceUrl));
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
        result.success++;
        result.sources.push(source);
      }
    }

    if (result.sources.length > 0) {
      await SourceDataService.addSources(result.sources);
      this.allSources = await SourceDataService.getSources();
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
        await SourceDataService.saveSources(sources);
        this.allSources = await SourceDataService.getSources();
      }
    } catch (_e) { /* ignore */ }
    this.isLoading = false;
    this.loadingUrl = '';
  }

  private async deleteSource(index: number): Promise<void> {
    this.subscriptions.splice(index, 1);
    await this.saveSubscriptions();
  }

  private async toggleSourceEnabled(source: BookSource): Promise<void> {
    source.enabled = !source.enabled;
    await SourceDataService.saveSources(this.allSources);
    this.allSources = [...this.allSources];
  }

  private updateHeaderOffset(scroller: Scroller): void {
    const y = scroller.currentOffset().yOffset;
    let h = y;
    if (h < 0) h = 0;
    if (h > this.COLLAPSE_HEIGHT) h = this.COLLAPSE_HEIGHT;
    if (Math.abs(h - this.headerOffset) >= 0.5) {
      this.headerOffset = h;
    }
  }

  private collapseRatio(): number {
    return this.headerOffset / this.COLLAPSE_HEIGHT;
  }

  private contentTopPadding(): number {
    return WindowUtils.getStatusBarHeightVp() + this.COLLAPSE_HEIGHT + this.TAB_HEIGHT;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容层
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
        const s = index === 0 ? this.subScroller : this.srcScroller;
        this.updateHeaderOffset(s);
      })
      .width('100%')
      .height('100%')

      // 顶部浮层(沉浸光感 + 折叠)
      Column() {
        // 折叠区: 标题 + 操作按钮
        Column() {
          Row() {
            Text('书源管理')
              .fontSize(AppFont.TitleL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Blank()
            Row({ space: AppSpace.Sm }) {
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(20)
                .fontColor([$r('sys.color.font_tertiary')])
                .onClick(() => {
                  promptAction.showToast({ message: '长按书源可删除或刷新' });
                })
              SymbolGlyph($r('sys.symbol.plus_circle'))
                .fontSize(22)
                .fontColor([AppColor.Brand])
                .onClick(() => {
                  this.showAddSheet = true;
                  this.statusMessage = '';
                  this.importMethod = ImportMethod.Network;
                })
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

        // Tab 行(吸顶)
        Row() {
          this.buildTabItem('订阅源', 0)
          this.buildTabItem('全部书源', 1)
          Blank()
        }
        .width('100%')
        .height(this.TAB_HEIGHT)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAddSheet, this.importSheetContent(), {
      height: SheetSize.LARGE,
      dragBar: true,
      onDisappear: () => {
        this.statusMessage = '';
        this.inputUrl = '';
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
      .padding({ top: this.contentTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else {
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
                      .onClick(() => this.deleteSource(idx))
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
        .padding({ top: this.contentTopPadding() + AppSpace.Sm, bottom: 160 })
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
      .padding({ top: this.contentTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll(this.srcScroller) {
        Column({ space: 0 }) {
          Column() {
            ForEach(this.allSources, (source: BookSource, idx: number) => {
              Row() {
                Column({ space: 2 }) {
                  Text(source.bookSourceName)
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_secondary'))
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

                Toggle({ type: ToggleType.Switch, isOn: source.enabled !== false })
                  .selectedColor(AppColor.Brand)
                  .onChange((isOn: boolean) => {
                    source.enabled = isOn;
                    this.toggleSourceEnabled(source);
                  })
              }
              .width('100%')
              .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })

              if (idx < this.allSources.length - 1) {
                Divider().color($r('sys.color.comp_divider')).margin({ left: AppSpace.Lg, right: AppSpace.Lg })
              }
            }, (source: BookSource) => source.bookSourceUrl)
          }
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Lg)
          .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: this.contentTopPadding() + AppSpace.Sm, bottom: 160 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.updateHeaderOffset(this.srcScroller);
      })
    }
  }

  @Builder
  addSourceSheet() {
    Column({ space: AppSpace.Lg }) {
      Text('书源导入')
        .fontSize(AppFont.TitleL)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Text('可将网上获取的书源链接或文件导入到本 App 中')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      // 导入方式选择
      Row({ space: AppSpace.Sm }) {
        this.buildImportMethodTab('从网络导入', ImportMethod.Network)
        this.buildImportMethodTab('从本地导入', ImportMethod.LocalFile)
        this.buildImportMethodTab('从剪贴板导入', ImportMethod.Clipboard)
      }
      .width('100%')

      // 导入内容区
      if (this.importMethod === ImportMethod.Network) {
        this.buildNetworkImport()
      } else if (this.importMethod === ImportMethod.LocalFile) {
        this.buildLocalFileImport()
      } else {
        this.buildClipboardImport()
      }

      // 状态提示
      if (this.statusMessage) {
        Text(this.statusMessage)
          .fontSize(AppFont.Caption)
          .fontColor(this.statusMessage.includes('失败') || this.statusMessage.includes('错误') ?
            '#FF3B30' : $r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    .width('100%')
  }

  @Builder
  buildImportMethodTab(label: string, method: ImportMethod) {
    Text(label)
      .fontSize(AppFont.Body)
      .fontColor(this.importMethod === method ? AppColor.Brand : $r('sys.color.font_tertiary'))
      .fontWeight(this.importMethod === method ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .borderRadius(AppRadius.Pill)
      .backgroundColor(this.importMethod === method ? '#1A0A59F7' : $r('sys.color.comp_background_primary'))
      .onClick(() => {
        this.importMethod = method;
        this.statusMessage = '';
      })
  }

  @Builder
  buildNetworkImport() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Xs }) {
        Text('书源链接地址')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        TextInput({ placeholder: '例如：https://xxx.com/source.json', text: this.inputUrl!! })
          .width('100%')
          .height(44)
          .borderRadius(AppRadius.Md)
          .backgroundColor($r('sys.color.background_primary'))
      }

      Text('支持远程 JSON / TXT 格式书源')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      Button(this.isLoading ? '加载中...' : '开始导入')
        .width('100%')
        .height(44)
        .backgroundColor(AppColor.Brand)
        .fontColor('#FFFFFF')
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading && this.inputUrl.trim().length > 0)
        .onClick(() => this.addSource())
    }
    .width('100%')
  }

  @Builder
  buildLocalFileImport() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Xs }) {
        Text('从"文件管理"中选择')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        Text('支持 .json / .txt 格式')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }

      Button(this.isLoading ? '解析中...' : '选择文件')
        .width('100%')
        .height(44)
        .backgroundColor(AppColor.Brand)
        .fontColor('#FFFFFF')
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading)
        .onClick(() => this.pickLocalFile())

      Text('提示：请勿导入来源不明的书源')
        .fontSize(AppFont.Caption)
        .fontColor('#FF9500')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder
  buildClipboardImport() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Xs }) {
        Text('读取剪贴板内容')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        Text('剪贴板内容需为标准书源格式')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }

      Button(this.isLoading ? '读取中...' : '读取剪贴板内容')
        .width('100%')
        .height(44)
        .backgroundColor(AppColor.Brand)
        .fontColor('#FFFFFF')
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading)
        .onClick(() => this.importFromClipboard())
    }
    .width('100%')
  }

  @Builder
  previewSheet() {
    Column({ space: AppSpace.Md }) {
      Text(`待导入书源预览（${this.previewSources.length}个）`)
        .fontSize(AppFont.TitleL)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Row() {
        Button(this.selectedPreviewIds.size === this.previewSources.length ? '反选' : '全选')
          .fontSize(AppFont.Body)
          .height(32)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .fontColor(AppColor.Brand)
          .onClick(() => this.toggleAllPreview())

        Blank()

        Text(`已选 ${this.selectedPreviewIds.size} 个`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')

      Scroll() {
        Column({ space: AppSpace.Xs }) {
          ForEach(this.previewSources, (source: BookSource) => {
            Row({ space: AppSpace.Md }) {
              Checkbox()
                .select(this.selectedPreviewIds.has(source.bookSourceUrl))
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

      Text('请勾选您信任的书源再导入')
        .fontSize(AppFont.Caption)
        .fontColor('#FF9500')
        .width('100%')
        .textAlign(TextAlign.Center)

      Row({ space: AppSpace.Md }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .fontColor($r('sys.color.font_primary'))
          .borderRadius(AppRadius.Md)
          .onClick(() => {
            this.showPreview = false;
            this.previewSources = [];
            this.selectedPreviewIds.clear();
          })

        Button(this.isLoading ? '导入中...' : `确认导入（${this.selectedPreviewIds.size}个）`)
          .layoutWeight(2)
          .height(44)
          .backgroundColor(AppColor.Brand)
          .fontColor('#FFFFFF')
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
