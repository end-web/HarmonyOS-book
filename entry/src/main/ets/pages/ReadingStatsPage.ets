import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { TimeStatsBarChart } from '../components/TimeStatsBarChart';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import {
  EVT_USAGE_STATS_UPDATED,
  StatsService,
  UsageStatsBucket,
  UsageStatsSummary
} from '../service/StatsService';

interface StatsMode {
  id: number;
  label: string;
}

interface SummaryTile {
  label: string;
  value: string;
  accent: ResourceColor;
}

const STATS_MODES: StatsMode[] = [
  { id: 0, label: '周' },
  { id: 1, label: '月' },
  { id: 2, label: '年' }
];

@ComponentV2
export struct ReadingStatsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local selectedMode: number = 0;
  @Local buckets: UsageStatsBucket[] = [];
  @Local summary: UsageStatsSummary = { todaySeconds: 0, weekSeconds: 0, monthSeconds: 0, totalSeconds: 0 };
  @Local chartVersion: number = 0;
  @Local loading: boolean = true;

  private statsHandler = (_evt: emitter.EventData): void => {
    this.loadStats();
  };

  aboutToAppear(): void {
    this.loadStats();
    emitter.on(EVT_USAGE_STATS_UPDATED, this.statsHandler);
  }

  aboutToDisappear(): void {
    try {
      emitter.off(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    } catch (_e) {
      try { emitter.off(EVT_USAGE_STATS_UPDATED); } catch (_ignore) { /* ignore */ }
    }
  }

  private async loadStats(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    try {
      await StatsService.init(ctx);
      const nextBuckets = this.selectedMode === 2
        ? await StatsService.getYearMonths(new Date().getFullYear())
        : await StatsService.getRecentDays(this.selectedMode === 0 ? 7 : 30);
      const nextSummary = await StatsService.getSummary();
      this.buckets = nextBuckets;
      this.summary = nextSummary;
      this.chartVersion += 1;
    } catch (e) {
      console.error(`[ReadingStatsPage] load stats failed: ${JSON.stringify(e)}`);
    } finally {
      this.loading = false;
    }
  }

  private switchMode(id: number): void {
    if (this.selectedMode === id) return;
    this.selectedMode = id;
    this.loading = true;
    this.loadStats();
  }

  private rangeTitle(): string {
    if (this.selectedMode === 0) return '近 7 天';
    if (this.selectedMode === 1) return '近 30 天';
    return `${new Date().getFullYear()} 年`;
  }

  private rangeTotalSeconds(): number {
    return this.buckets.reduce((sum: number, item: UsageStatsBucket) => {
      return sum + item.listenSeconds + item.readSeconds;
    }, 0);
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

  private summaryTiles(): SummaryTile[] {
    return [
      { label: '今天', value: this.formatDuration(this.summary.todaySeconds), accent: '#2F7DF6' },
      { label: '近7天', value: this.formatDuration(this.summary.weekSeconds), accent: '#00A870' },
      { label: '近30天', value: this.formatDuration(this.summary.monthSeconds), accent: '#FFB547' },
      { label: '累计', value: this.formatDuration(this.summary.totalSeconds), accent: '#8A5CF6' }
    ];
  }

  build() {
    Column() {
      this.buildHeader()

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          this.buildModeSelector()
          this.buildSummaryGrid()
          this.buildChartPanel()
        }
        .width('100%')
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: AppSpace.Sm,
          bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Text('听读统计')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .margin({ left: AppSpace.Sm })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      left: AppSpace.Md,
      right: AppSpace.Md,
      bottom: AppSpace.Md
    })
  }

  @Builder
  buildModeSelector() {
    Row() {
      ForEach(STATS_MODES, (mode: StatsMode) => {
        Text(mode.label)
          .fontSize(AppFont.Body)
          .fontWeight(this.selectedMode === mode.id ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selectedMode === mode.id ? AppColor.Brand : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .backgroundColor(this.selectedMode === mode.id ? $r('sys.color.comp_background_primary') : Color.Transparent)
          .borderRadius(AppRadius.Sm)
          .padding({ top: 7 })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
          .onClick(() => this.switchMode(mode.id))
      }, (mode: StatsMode) => `${mode.id}`)
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(AppRadius.Md)
  }

  @Builder
  buildSummaryGrid() {
    Grid() {
      ForEach(this.summaryTiles(), (item: SummaryTile) => {
        GridItem() {
          Column({ space: AppSpace.Xs }) {
            Text(item.label)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
            Text(item.value)
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .padding(AppSpace.Md)
          .border({ width: 1, color: '#14000000' })
          .borderRadius(AppRadius.Lg)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderColor(item.accent)
        }
      }, (item: SummaryTile) => item.label)
    }
    .columnsTemplate('1fr 1fr')
    .rowsTemplate('1fr 1fr')
    .columnsGap(AppSpace.Sm)
    .rowsGap(AppSpace.Sm)
    .height(164)
    .width('100%')
  }

  @Builder
  buildChartPanel() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.rangeTitle())
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          Text('听书 + 阅读')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.formatDuration(this.rangeTotalSeconds()))
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      TimeStatsBarChart({ buckets: this.buckets, version: this.chartVersion })

      if (!this.loading && this.rangeTotalSeconds() <= 0) {
        Text('暂无听读记录')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }
}
