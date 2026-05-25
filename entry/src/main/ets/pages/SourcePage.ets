import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { BookSource, SourceSubscription } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct SourcePage {
  @Local subscriptions: SourceSubscription[] = [];
  @Local allSources: BookSource[] = [];
  @Local showAddSheet: boolean = false;
  @Local inputUrl: string = '';
  @Local isLoading: boolean = false;
  @Local loadingUrl: string = '';
  @Local activeTab: number = 0;

  aboutToAppear(): void {
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
    if (this.subscriptions.some(s => s.url === url)) {
      this.inputUrl = '';
      this.showAddSheet = false;
      return;
    }
    this.isLoading = true;
    this.loadingUrl = url;
    try {
      const sources = await BookSourceService.fetchSourcesFromUrl(url);
      const sub = BookSourceService.buildSubscription(url, sources);
      this.subscriptions.push(sub);
      await this.saveSubscriptions();
      if (sources.length > 0) {
        await SourceDataService.addSources(sources);
        this.allSources = await SourceDataService.getSources();
      }
    } catch (_e) {
      const sub: SourceSubscription = { url, name: '加载失败', count: 0, lastUpdate: Date.now() };
      this.subscriptions.push(sub);
      await this.saveSubscriptions();
    }
    this.isLoading = false;
    this.loadingUrl = '';
    this.inputUrl = '';
    this.showAddSheet = false;
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

  build() {
    Column() {
      Row() {
        Text('书源')
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(22)
          .fontColor([AppColor.Brand])
          .onClick(() => { this.showAddSheet = true; })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Lg,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm
      })

      Row({ space: 0 }) {
        this.buildTabItem('订阅源', 0)
        this.buildTabItem('全部书源', 1)
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })

      if (this.activeTab === 0) {
        this.buildSubscriptionList()
      } else {
        this.buildSourceList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .bindSheet($$this.showAddSheet, this.addSourceSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true
    })
  }

  @Builder
  buildTabItem(label: string, idx: number) {
    Text(label)
      .fontSize(AppFont.BodyL)
      .fontColor(this.activeTab === idx ? AppColor.Brand : $r('sys.color.font_tertiary'))
      .fontWeight(this.activeTab === idx ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .borderRadius(AppRadius.Pill)
      .backgroundColor(this.activeTab === idx ? '#1A0A59F7' : Color.Transparent)
      .onClick(() => { this.activeTab = idx; })
  }

  @Builder
  buildSubscriptionList() {
    Scroll() {
      Column({ space: AppSpace.Sm }) {
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
          .padding({ top: 80 })
          .justifyContent(FlexAlign.Center)
        }

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
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Lg)
          .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
        }, (sub: SourceSubscription, _idx: number) => sub.url)
      }
      .width('100%')
      .padding({ bottom: 160 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildSourceList() {
    Scroll() {
      Column({ space: 0 }) {
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
          .padding({ top: 80 })
          .justifyContent(FlexAlign.Center)
        }

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
      .padding({ bottom: 160 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  addSourceSheet() {
    Column({ space: AppSpace.Lg }) {
      Text('添加书源订阅')
        .fontSize(AppFont.TitleL)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))

      Text('输入 Legado 3.0 格式的书源 JSON 地址')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))

      TextInput({ placeholder: 'https://example.com/sources.json', text: this.inputUrl!! })
        .width('100%')
        .height(44)
        .borderRadius(AppRadius.Md)
        .backgroundColor($r('sys.color.background_primary'))

      Button(this.isLoading ? '加载中...' : '确认添加')
        .width('100%')
        .height(44)
        .backgroundColor(AppColor.Brand)
        .fontColor('#FFFFFF')
        .borderRadius(AppRadius.Md)
        .enabled(!this.isLoading && this.inputUrl.trim().length > 0)
        .onClick(() => this.addSource())
    }
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    .width('100%')
  }
}
