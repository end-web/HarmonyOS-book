import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { ReadingHeatmap } from '../components/ReadingHeatmap';
import { AppColor, AppCurve, AppFont, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import {
  BookUsageStats,
  EVT_USAGE_STATS_UPDATED,
  HeatPoint,
  StatsBundle,
  StatsService,
  UsageStatsSummary
} from '../service/StatsService';

interface StatCell {
  icon: Resource;
  label: string;
  value: string;
}

const HEATMAP_DAYS: number = 122; // 约 4 个月

@ComponentV2
export struct ReadingStatsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param inTab: boolean = false;
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};

  @Local heatDays: HeatPoint[] = [];
  @Local streak: number = 0;
  @Local summary: UsageStatsSummary = { todaySeconds: 0, weekSeconds: 0, monthSeconds: 0, totalSeconds: 0 };
  @Local records: BookUsageStats[] = [];
  @Local chartVersion: number = 0;
  @Local loading: boolean = true;
  @Local appeared: boolean = false;
  @Local selectMode: boolean = false;
  @Local selectedIds: Set<string> = new Set();

  private scroller: Scroller = new Scroller();
  /** loadStats 重入保护:播放中每 15s 一次统计写会 emit 事件触发重载,
   *  并发的多次 loadStats 各自分段读盘会把 @Local 撕裂成不一致快照。 */
  private loadingStats: boolean = false;
  private reloadPending: boolean = false;
  private statsHandler = (_evt: emitter.EventData): void => {
    this.loadStats();
  };

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
    this.loadStats();
    emitter.on(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    setTimeout(() => { this.appeared = true; }, 24);
  }

  aboutToDisappear(): void {
    try {
      emitter.off(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    } catch (_e) {
      try { emitter.off(EVT_USAGE_STATS_UPDATED); } catch (_ignore) { /* ignore */ }
    }
  }

  private async loadStats(): Promise<void> {
    // 重入保护:已有加载在跑时,只记一个 pending,等当前这次结束再补一次,
    // 避免并发 loadStats 交错赋值把 6 个指标撕成不同快照。
    if (this.loadingStats) {
      this.reloadPending = true;
      return;
    }
    this.loadingStats = true;
    const ctx = this.getUIContext().getHostContext() as common.Context;
    try {
      await StatsService.init(ctx);
      // 一次读盘出整包:所有指标从同一份 records 快照算,保证内部一致
      const bundle: StatsBundle = await StatsService.getStatsBundle(HEATMAP_DAYS);
      this.heatDays = bundle.heatDays;
      this.streak = bundle.streak;
      this.summary = bundle.summary;
      this.records = bundle.records;
      this.chartVersion += 1;
      this.selectedIds = new Set(Array.from(this.selectedIds).filter((id) =>
        this.records.some((item) => item.bookId === id)));
      if (this.selectedIds.size === 0) this.selectMode = false;
    } catch (e) {
      console.error(`[ReadingStatsPage] load stats failed: ${JSON.stringify(e)}`);
    } finally {
      this.loading = false;
      this.loadingStats = false;
      if (this.reloadPending) {
        this.reloadPending = false;
        this.loadStats();
      }
    }
  }

  private formatDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    if (total < 60) return total > 0 ? '不足1分钟' : '0分钟';
    const minutes = Math.floor(total / 60);
    if (minutes < 60) return `${minutes}分钟`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest > 0 ? `${hours}小时${rest}分钟` : `${hours}小时`;
  }

  private formatCompactHours(seconds: number): string {
    const h = Math.round(seconds / 360) / 10;
    return `${h.toFixed(h >= 10 || h === 0 ? 0 : 1)} h`;
  }

  private statCells(): StatCell[] {
    return [
      { icon: $r('sys.symbol.clock_fill'), label: '累计时长', value: this.formatCompactHours(this.totalListen() + this.totalRead()) },
      { icon: $r('sys.symbol.book'), label: '阅听书籍', value: `${this.records.length}本` },
      { icon: $r('sys.symbol.flame'), label: '连续收听', value: `${this.streak}天` }
    ];
  }

  private totalListen(): number {
    return this.records.reduce((acc, item) => acc + item.listenSeconds, 0);
  }

  private totalRead(): number {
    return this.records.reduce((acc, item) => acc + item.readSeconds, 0);
  }

  private listenRatio(): number {
    const listen = this.totalListen();
    const read = this.totalRead();
    const sum = listen + read;
    return sum > 0 ? listen / sum : 0;
  }

  private toggleSelect(bookId: string): void {
    const next = new Set(this.selectedIds);
    if (next.has(bookId)) {
      next.delete(bookId);
    } else {
      next.add(bookId);
    }
    this.selectedIds = next;
    this.selectMode = next.size > 0;
  }

  private selectAll(): void {
    this.selectedIds = new Set(this.records.map((item) => item.bookId));
    this.selectMode = this.selectedIds.size > 0;
  }

  private clearSelection(): void {
    this.selectedIds = new Set();
    this.selectMode = false;
  }

  private confirmDeleteSelected(): void {
    if (this.selectedIds.size === 0) return;
    const count = this.selectedIds.size;
    this.getUIContext().getPromptAction().showDialog({
      title: '删除记录',
      message: `确认删除已选 ${count} 本书的阅听记录？`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteSelected();
      }
    }).catch(() => { /* ignore */ });
  }

  private async deleteSelected(): Promise<void> {
    const ids = Array.from(this.selectedIds);
    await StatsService.removeBookStats(ids);
    this.clearSelection();
    await this.loadStats();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [HomeTheme.BgWarmTop, 0.0],
            [HomeTheme.BgWarmMid, 0.35],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      Scroll(this.scroller) {
        Column({ space: AppSpace.Lg }) {
          this.buildHeader()
          this.buildHeroCard()
          this.buildStatCells()
          this.buildHeatmapPanel()
          this.buildRecordHeader()
          this.buildRecordList()
        }
        .width('100%')
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          bottom: this.inTab ? WindowUtils.getFloatingTabBottomVp() : WindowUtils.getBottomSafeVp() + AppSpace.Xl
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row() {
      if (!this.inTab) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
      }
      Text('记录')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .margin({ left: this.inTab ? 0 : AppSpace.Sm })
      Blank()
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Md,
      bottom: AppSpace.Sm
    })
  }

  @Builder
  buildHeroCard() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Column({ space: AppSpace.Xxs }) {
          Text('今日阅听')
            .fontSize(AppFont.Body)
            .fontColor('#F5E4DA')
            .fontWeight(FontWeight.Medium)
          Row({ space: 6 }) {
            Text(this.formatCompactHours(this.summary.todaySeconds))
              .fontSize(44)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 听 / 读 占比条
      this.buildRatioBar()
    }
    .width('100%')
    .padding(AppSpace.Lg)
    .borderRadius(AppRadius.Xl)
    .linearGradient({
      angle: 135,
      colors: [['#E7A98E', 0.0], ['#DD8A66', 0.55], ['#D0764F', 1.0]]
    })
    .shadow({ radius: 18, color: '#1FCE7049', offsetY: 8 })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, curve: AppCurve.Decelerate })
  }

  @Builder
  buildRatioBar() {
    Column({ space: AppSpace.Xs }) {
      // 注意:时长文本必须直接引用 this 的状态。原来经 @Builder 按值传参,
      // 参数不建立响应依赖,records 更新后标签恒显首帧的 0(占比条却在动)
      Row() {
        Row({ space: 6 }) {
          Column().width(8).height(8).borderRadius(4).backgroundColor('#FFFFFF')
          Text('听书')
            .fontSize(AppFont.Caption)
            .fontColor('#F5E4DA')
          Text(this.formatCompactHours(this.totalListen()))
            .fontSize(AppFont.Caption)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        Row({ space: 6 }) {
          Column().width(8).height(8).borderRadius(4).backgroundColor('#FFE0CF')
          Text('阅读')
            .fontSize(AppFont.Caption)
            .fontColor('#F5E4DA')
          Text(this.formatCompactHours(this.totalRead()))
            .fontSize(AppFont.Caption)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(10)
          .borderRadius(5)
          .backgroundColor('#40FFFFFF')
        Row()
          .width(`${Math.round((this.appeared ? this.listenRatio() : 0) * 100)}%`)
          .height(10)
          .borderRadius(5)
          .backgroundColor(Color.White)
          .animation({ duration: 640, curve: AppCurve.Decelerate })
      }
      .width('100%')
      .height(10)
    }
    .width('100%')
  }

  @Builder
  buildStatCells() {
    Row({ space: AppSpace.Sm }) {
      ForEach(this.statCells(), (item: StatCell) => {
        Column({ space: AppSpace.Xxs }) {
          SymbolGlyph(item.icon)
            .fontSize(18)
            .fontColor([$r('sys.color.font_tertiary')])
          Text(item.value)
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Text(item.label)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .layoutWeight(1)
        .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Lg)
      }, (item: StatCell) => `${item.label}|${item.value}`) // key 必须含 value:纯 label 作 key 时数据更新后 ForEach 不重渲染,三格恒显首帧的 0
    }
    .width('100%')
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, delay: 80, curve: AppCurve.Decelerate })
  }

  @Builder
  buildHeatmapPanel() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text('阅听热力图')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('近4个月')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')

      ReadingHeatmap({ days: this.heatDays, version: this.chartVersion, chartHeight: 158 })
    }
    .width('100%')
    .padding(AppSpace.Lg)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
    .shadow({ radius: 12, color: '#0F000000', offsetY: 4 })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, delay: 150, curve: AppCurve.Decelerate })
  }

  @Builder
  buildRecordHeader() {
    Row() {
      Text('阅听记录')
        .fontSize(AppFont.Title)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
      Blank()
      if (this.records.length > 0) {
        if (this.selectMode) {
          Text('全选')
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .margin({ right: AppSpace.Md })
            .onClick(() => this.selectAll())
          Text('删除')
            .fontSize(AppFont.Body)
            .fontColor('#FF4444')
            .margin({ right: AppSpace.Md })
            .onClick(() => this.confirmDeleteSelected())
          Text('取消')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .onClick(() => this.clearSelection())
        } else {
          Text('管理')
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .onClick(() => this.selectMode = true)
        }
      }
    }
    .width('100%')
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, delay: 210, curve: AppCurve.Decelerate })
  }

  @Builder
  buildRecordList() {
    if (this.records.length === 0 && !this.loading) {
      Column({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(36)
          .fontColor([$r('sys.color.font_tertiary')])
        Text('暂无阅听记录')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height(160)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .opacity(this.appeared ? 1 : 0)
      .animation({ duration: 460, delay: 240, curve: AppCurve.Decelerate })
    } else {
      Column({ space: AppSpace.Sm }) {
        ForEach(this.records, (item: BookUsageStats) => {
          this.buildRecordItem(item)
        }, (item: BookUsageStats) => `${item.bookId}|${item.listenSeconds}|${item.readSeconds}`) // key 含时长:纯 bookId 时播放中统计更新,列表项时长不刷新
      }
      .width('100%')
      .opacity(this.appeared ? 1 : 0)
      .translate({ y: this.appeared ? 0 : 18 })
      .animation({ duration: 460, delay: 240, curve: AppCurve.Decelerate })
    }
  }

  @Builder
  buildRecordItem(item: BookUsageStats) {
    Row({ space: AppSpace.Sm }) {
      if (this.selectMode) {
        Checkbox()
          .select(this.selectedIds.has(item.bookId))
          .selectedColor(AppColor.Brand)
          .hitTestBehavior(HitTestMode.None)
      }
      if (item.cover && item.cover.startsWith('http')) {
        Image(item.cover)
          .width(44)
          .height(58)
          .borderRadius(AppRadius.Sm)
          .objectFit(ImageFit.Cover)
          // 与列表统一解码尺寸,共享同一份解码缓存
          .sourceSize({ width: 300, height: 400 })
      } else {
        Stack() {
          Text(item.title ? item.title.substring(0, 1) : '?')
            .fontSize(AppFont.Title)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(44)
        .height(58)
        .borderRadius(AppRadius.Sm)
        .backgroundColor(AppColor.Brand)
      }

      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.author || '未知作者')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: AppSpace.Sm }) {
          Text(`听 ${this.formatDuration(item.listenSeconds)}`)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
          Text(`读 ${this.formatDuration(item.readSeconds)}`)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.formatCompactHours(item.listenSeconds + item.readSeconds))
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .padding(AppSpace.Sm)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
    .shadow({ radius: 8, color: '#0A000000', offsetY: 2 })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      if (this.selectMode) this.toggleSelect(item.bookId);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.selectMode = true;
          this.toggleSelect(item.bookId);
        })
    )
  }
}
