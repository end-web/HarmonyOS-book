import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';
import { AppColor, AppCurve, AppFont, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import {
  BookUsageStats,
  EVT_USAGE_STATS_UPDATED,
  StatsBundle,
  StatsService
} from '../service/StatsService';
import {
  PlayHistoryItem,
  PreferenceService
} from '../service/PreferenceService';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import {
  ListeningHistoryPolicy,
  ListeningRecordCandidate,
  MergedListeningRecord
} from '../service/ListeningHistoryPolicy';

interface ListenRecordView {
  bookId: string;
  aliasBookIds: string[];
  title: string;
  author: string;
  cover: string;
  chapterId: string;
  chapterTitle: string;
  progressMs: number;
  durationMs: number;
  progressPercent: number;
  listenSeconds: number;
  updatedAt: number;
}

const AVERAGE_BOOK_SECONDS: number = 8 * 60 * 60;
const MINI_TITLE_BAR_HEIGHT: number = 56;

@ComponentV2
export struct ReadingStatsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param inTab: boolean = false;
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};

  @Local streak: number = 0;
  @Local sourceRecords: BookUsageStats[] = [];
  @Local records: ListenRecordView[] = [];
  @Local loading: boolean = true;
  @Local appeared: boolean = false;
  @Local selectMode: boolean = false;
  @Local selectedIds: Set<string> = new Set();

  private scroller: Scroller = new Scroller();
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
    if (this.loadingStats) {
      this.reloadPending = true;
      return;
    }
    this.loadingStats = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await StatsService.init(ctx);
      await PreferenceService.ensureReady(ctx);
      const bundle: StatsBundle = await StatsService.getStatsBundle(1);
      const history = await PreferenceService.getHistory();
      this.streak = bundle.streak;
      this.sourceRecords = bundle.records;
      this.records = await this.buildRecordViews(ctx, bundle.records, history);
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

  private async buildRecordViews(context: common.UIAbilityContext, stats: BookUsageStats[],
    history: PlayHistoryItem[]): Promise<ListenRecordView[]> {
    const statsMap = new Map<string, BookUsageStats[]>();
    const historyMap = new Map<string, PlayHistoryItem>();
    const bookIds = new Set<string>();
    for (const item of stats) {
      if (!item || !item.bookId || item.listenSeconds <= 0 || this.isLegacyTextBook(item.bookId)) continue;
      let bookStats = statsMap.get(item.bookId);
      if (!bookStats) {
        bookStats = [];
        statsMap.set(item.bookId, bookStats);
      }
      bookStats.push(item);
      bookIds.add(item.bookId);
    }
    for (const item of history) {
      if (!item || !item.bookId || this.isLegacyTextBook(item.bookId)) continue;
      const current = historyMap.get(item.bookId);
      if (!current || item.updatedAt >= current.updatedAt) historyMap.set(item.bookId, item);
      bookIds.add(item.bookId);
    }

    const candidates: ListeningRecordCandidate[] = [];
    const books = new Map<string, Book>();
    for (const bookId of bookIds) {
      const candidate = new ListeningRecordCandidate(bookId);
      const bookStats = statsMap.get(bookId) ?? [];
      for (const stat of bookStats) {
        candidate.addStats(stat.listenSeconds, stat.updatedAt, stat.title, stat.author, stat.cover,
          stat.sourceUrl, stat.bookUrl);
      }
      const historyItem = historyMap.get(bookId);
      if (historyItem) {
        candidate.setHistory(historyItem.chapterId, historyItem.chapterTitle ?? '', historyItem.progressMs,
          historyItem.durationMs ?? 0, historyItem.updatedAt, historyItem.sourceUrl, historyItem.bookUrl);
      }
      const progress = await PreferenceService.getProgress(bookId);
      if (progress) {
        candidate.setProgress(progress.chapterId, progress.chapterTitle, progress.positionMs, progress.durationMs,
          progress.chapterIndex, progress.updatedAt, progress.sourceUrl, progress.bookUrl);
      }
      const book = await DataService.getBookById(context, bookId) ?? null;
      if (book) {
        books.set(bookId, book);
        candidate.setBook(book.sourceUrl, book.bookUrl, book.title, book.author || book.narrator, book.cover);
      }
      candidates.push(candidate);
    }

    const merged = ListeningHistoryPolicy.merge(candidates);
    const views: ListenRecordView[] = [];
    for (const item of merged) {
      views.push(this.createRecordView(item, books.get(item.bookId) ?? null));
    }
    return views.sort((a, b) => b.updatedAt - a.updatedAt);
  }

  private isLegacyTextBook(bookId: string): boolean {
    return bookId.startsWith('search_text_') || bookId.startsWith('home_text_');
  }

  private createRecordView(item: MergedListeningRecord, book: Book | null): ListenRecordView {
    let chapterId = item.chapterId;
    let chapterIndex = item.chapterIndex;
    if (book && book.chapters && book.chapters.length > 0) {
      const resolvedIndex = DataService.resolveChapterIndex(book, item.chapterId, item.chapterTitle);
      if (resolvedIndex >= 0) {
        chapterIndex = resolvedIndex;
        chapterId = book.chapters[resolvedIndex].id;
      }
    }
    const ratio = this.calculateBookProgress(book, chapterId, item.chapterTitle, chapterIndex,
      item.progressMs, item.durationMs);
    return {
      bookId: item.bookId,
      aliasBookIds: item.aliasBookIds,
      title: book?.title || item.title || '未知书籍',
      author: book?.author || book?.narrator || item.author || '未知作者',
      cover: book?.cover || item.cover || '',
      chapterId,
      chapterTitle: item.chapterTitle,
      progressMs: item.progressMs,
      durationMs: item.durationMs,
      progressPercent: Math.round(ratio * 100),
      listenSeconds: item.listenSeconds,
      updatedAt: item.updatedAt || Date.now()
    };
  }

  private calculateBookProgress(book: Book | null, chapterId: string, chapterTitle: string,
    savedChapterIndex: number, progressMs: number, durationMs: number): number {
    const chapterRatio = durationMs > 0 ? Math.max(0, Math.min(1, progressMs / durationMs)) : 0;
    if (!book) return chapterRatio;

    const chapterCount = book.chapters && book.chapters.length > 0 ? book.chapters.length : (book.chapterCount || 0);
    if (chapterCount <= 0) return chapterRatio;

    let chapterIndex = -1;
    if (book.chapters && book.chapters.length > 0) {
      chapterIndex = DataService.resolveChapterIndex(
        book,
        chapterId,
        chapterTitle
      );
    }
    if (chapterIndex < 0 && savedChapterIndex >= 0) chapterIndex = savedChapterIndex;
    if (chapterIndex < 0) return chapterRatio;

    const safeIndex = Math.max(0, Math.min(chapterCount - 1, chapterIndex));
    return Math.max(0, Math.min(1, (safeIndex + chapterRatio) / chapterCount));
  }

  private totalListenSeconds(): number {
    return this.sourceRecords.reduce((acc, item) => acc + item.listenSeconds, 0);
  }

  private monthListenSeconds(): number {
    const currentMonth = this.formatMonthKey(new Date());
    let total = 0;
    for (const record of this.sourceRecords) {
      if (record.days.length === 0) {
        if (this.formatMonthKey(new Date(record.updatedAt)) === currentMonth) total += record.listenSeconds;
        continue;
      }
      for (const day of record.days) {
        if (day.day.startsWith(currentMonth)) total += day.listenSeconds;
      }
    }
    return total;
  }

  private equivalentBookCount(): number {
    return Math.max(0, Math.round(this.totalListenSeconds() / AVERAGE_BOOK_SECONDS));
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

  private formatDurationText(item: ListenRecordView): string {
    const total = item.listenSeconds;
    if (total > 0) return this.formatDuration(total);
    if (item.progressMs > 0) return this.formatDuration(Math.floor(item.progressMs / 1000));
    return '刚刚开始';
  }

  private formatMonthKey(date: Date): string {
    const m = date.getMonth() + 1;
    return `${date.getFullYear()}-${m < 10 ? `0${m}` : `${m}`}`;
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
      message: `确认删除已选 ${count} 本书的收听记录？`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#C45D34' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteSelected();
      }
    }).catch(() => { /* ignore */ });
  }

  private async deleteSelected(): Promise<void> {
    const deletedIds = new Set<string>();
    for (const item of this.records) {
      if (!this.selectedIds.has(item.bookId)) continue;
      for (const aliasBookId of item.aliasBookIds) deletedIds.add(aliasBookId);
    }
    for (const selectedId of this.selectedIds) deletedIds.add(selectedId);
    const ids = Array.from(deletedIds);
    await StatsService.removeBookStats(ids);
    for (const id of ids) {
      await PreferenceService.removeHistory(id);
      await PreferenceService.removeProgress(id);
    }
    this.clearSelection();
    await this.loadStats();
  }

  private openDetail(item: ListenRecordView): void {
    if (!item.bookId || this.selectMode) return;
    this.navStack.pushPathByName('detail', item.bookId);
  }

  private resumeRecord(item: ListenRecordView): void {
    if (!item.bookId) return;
    const params: Record<string, Object> = {
      'bookId': item.bookId,
      'chapterId': item.chapterId,
      'progressMs': item.progressMs
    };
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', params, false);
    });
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
            [HomeTheme.BgWarmMid, 0.42],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: AppSpace.Md }) {
            this.buildSummaryCard()
            this.buildRecordList()
          }
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: WindowUtils.getStatusBarHeightVp() + MINI_TITLE_BAR_HEIGHT + AppSpace.Sm,
            bottom: this.inTab ? WindowUtils.getFloatingTabBottomVp() : WindowUtils.getBottomSafeVp() + AppSpace.Xl
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor(Color.Transparent)
        .align(Alignment.Top)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: '收听记录'
          },
          backIcon: {
            icon: $r('sys.symbol.chevron_left'),
            action: () => this.navStack.pop()
          },
          menu: {
            value: [{
              content: {
                icon: $r('sys.symbol.clock'),
                label: '收听记录',
                action: () => {}
              }
            }]
          }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              backIconStyle: {
                iconColor: $r('sys.color.icon_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              backIconStyle: {
                iconColor: $r('sys.color.icon_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.inTab)
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildSummaryCard() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          Blank()
          this.buildSummaryArt()
        }
        .width('100%')
        .height('100%')
        .padding({ right: AppSpace.Sm })
        .alignItems(VerticalAlign.Top)

        Column({ space: AppSpace.Xs }) {
          Text('累计收听时长')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(`${Math.floor(this.totalListenSeconds() / 3600)}`)
              .fontSize(32)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('小时')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ bottom: 4 })
            Text(`${Math.floor((this.totalListenSeconds() % 3600) / 60)}`)
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 2 })
            Text('分钟')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ bottom: 4 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .justifyContent(FlexAlign.Start)
          Text(`相当于读完 ${this.equivalentBookCount()} 本书`)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('62%')
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppSpace.Md, top: AppSpace.Md })
      }
      .height(98)
      .width('100%')

      Row() {
        Column({ space: AppSpace.Sm }) {
          Text('连续收听')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(`${this.streak}`)
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('天')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(0.5)
          .height(34)
          .backgroundColor(AppColor.Divider)

        Column({ space: AppSpace.Sm }) {
          Text('本月收听')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(`${Math.floor(this.monthListenSeconds() / 3600)}`)
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('小时')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Text(`${Math.floor((this.monthListenSeconds() % 3600) / 60)}`)
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('分钟')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .padding({ left: AppSpace.Md })
        .alignItems(HorizontalAlign.Start)
      }
      .height(72)
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
      .backgroundColor('#66FFFFFF')
      .borderRadius({ topLeft: AppRadius.Lg, topRight: AppRadius.Lg, bottomLeft: AppRadius.Xl, bottomRight: AppRadius.Xl })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(170)
    .borderRadius(AppRadius.Xl)
    .backgroundColor($r('app.color.home_card_surface_soft'))
    .shadow({ radius: 18, color: HomeTheme.CardShadow, offsetY: 6 })
    .clip(true)
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, curve: AppCurve.Decelerate })
  }

  @Builder
  buildSummaryArt() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width(108)
        .height(108)
        .borderRadius(54)
        .backgroundColor('#42FFFFFF')
        .margin({ right: 0, bottom: 0 })

      Column()
        .width(80)
        .height(80)
        .borderRadius(40)
        .backgroundColor('#18D9BDAA')
        .margin({ right: 18, bottom: 14 })

      Column()
        .width(96)
        .height(6)
        .borderRadius(3)
        .backgroundColor('#16A98363')
        .margin({ right: 4, bottom: 5 })

      Column()
        .width(2)
        .height(34)
        .borderRadius(1)
        .backgroundColor('#BFA38D')
        .rotate({ angle: -28 })
        .margin({ right: 83, bottom: 59 })

      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor('#BFA38D')
        .margin({ right: 95, bottom: 88 })

      Column()
        .width(48)
        .height(18)
        .borderRadius({ topLeft: 16, topRight: 16 })
        .border({ width: 4, color: '#C5A187' })
        .margin({ right: 28, bottom: 54 })

      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(92)
          .height(56)
          .borderRadius(14)
          .backgroundColor('#D7AE8E')

        Column()
          .width(62)
          .height(6)
          .borderRadius(3)
          .backgroundColor('#40FFFFFF')
          .margin({ left: 15, top: 10 })

        Row({ space: 5 }) {
          Column().width(3).height(18).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(24).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(14).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(22).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(16).borderRadius(2).backgroundColor('#9D7A61')
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 15, top: 23 })

        Column()
          .width(27)
          .height(27)
          .borderRadius(14)
          .backgroundColor('#F3DFCE')
          .margin({ left: 54, top: 22 })

        Column()
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor('#9D7A61')
          .margin({ left: 62, top: 30 })

        Row({ space: 5 }) {
          Column().width(8).height(8).borderRadius(4).backgroundColor('#F3DFCE')
          Column().width(8).height(8).borderRadius(4).backgroundColor('#F3DFCE')
        }
        .margin({ left: 57, top: 45 })
      }
      .width(92)
      .height(56)
      .margin({ right: 4, bottom: 10 })
    }
    .width(132)
    .height(98)
    .opacity(0.64)
  }

  @Builder
  buildRecordList() {
    if (this.loading) {
      this.buildLoadingState()
    } else if (this.records.length === 0) {
      this.buildEmptyState()
    } else {
      Column({ space: AppSpace.Md }) {
        this.buildHistoryHeader()
        Column({ space: AppSpace.Sm }) {
          ForEach(this.records, (item: ListenRecordView) => {
            this.buildRecordItem(item)
          }, (item: ListenRecordView) =>
            `${item.bookId}|${item.updatedAt}|${item.progressPercent}|${item.listenSeconds}`)
        }
        .width('100%')
      }
      .width('100%')
      .opacity(this.appeared ? 1 : 0)
      .translate({ y: this.appeared ? 0 : 18 })
      .animation({ duration: 460, delay: 160, curve: AppCurve.Decelerate })
    }
  }

  @Builder
  buildHistoryHeader() {
    Row() {
      Column({ space: 5 }) {
        Text('收听历史')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Column()
          .width(20)
          .height(2)
          .borderRadius(1)
          .backgroundColor(HomeTheme.Accent)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()
      this.buildEditActions()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  buildEditActions() {
    if (this.selectMode) {
      Row({ space: AppSpace.Md }) {
        Text('全选')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .onClick(() => this.selectAll())
        Text('删除')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.BrandDark)
          .onClick(() => this.confirmDeleteSelected())
        Text('取消')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .onClick(() => this.clearSelection())
      }
      .alignItems(VerticalAlign.Center)
    } else {
      Row({ space: AppSpace.Md }) {
        Text('编辑')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => this.selectMode = true)
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .height(28)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  buildRecordItem(item: ListenRecordView) {
    Row({ space: AppSpace.Md }) {
      if (this.selectMode) {
        Checkbox()
          .select(this.selectedIds.has(item.bookId))
          .selectedColor(AppColor.Brand)
          .hitTestBehavior(HitTestMode.None)
      }

      this.buildCover(item)

      Column({ space: AppSpace.Xs }) {
        Row() {
          Column({ space: AppSpace.Xs }) {
            Text(item.title)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(item.author)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: AppSpace.Sm }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(10)
              .fontColor([HomeTheme.Accent])
            Text(`已听 ${item.progressPercent}%`)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(VerticalAlign.Center)

          Text(this.formatDurationText(item))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 5 })

        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width('100%')
            .height(3)
            .borderRadius(2)
            .backgroundColor(HomeTheme.ProgressTrack)
          Column()
            .width(`${Math.max(3, item.progressPercent)}%`)
            .height(3)
            .borderRadius(2)
            .backgroundColor(HomeTheme.Accent)
        }
        .width('100%')
        .height(3)
      }
      .layoutWeight(1)
      .height(76)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      if (!this.selectMode) {
        Stack() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(HomeTheme.CardSurface)
        .border({ width: 1, color: AppColor.Divider })
        .shadow({ radius: 8, color: HomeTheme.CardShadow, offsetY: 2 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        .onClick(() => this.resumeRecord(item))
      }
    }
    .width('100%')
    .height(88)
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      if (this.selectMode) {
        this.toggleSelect(item.bookId);
      } else {
        this.openDetail(item);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.selectMode = true;
          this.toggleSelect(item.bookId);
        })
    )
  }

  @Builder
  buildCover(item: ListenRecordView) {
    if (item.cover && item.cover.startsWith('http')) {
      Image(item.cover)
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 400 })
        .alt($r('app.media.app_icon_legacy'))
    } else if (item.cover && (item.cover.startsWith('/') || item.cover.startsWith('file://'))) {
      Image('file://' + item.cover.replace(/^file:\/\//, ''))
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 400 })
        .syncLoad(true)
    } else if (item.cover) {
      Image($rawfile(item.cover))
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.app_icon_legacy'))
    } else {
      Stack() {
        Text(item.title ? item.title.substring(0, 1) : '?')
          .fontSize(24)
          .fontColor(AppColor.OnBrand)
          .fontWeight(FontWeight.Bold)
      }
      .width(72)
      .height(72)
      .borderRadius(AppRadius.Sm)
      .backgroundColor(HomeTheme.Accent)
    }
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Lg }) {
      ForEach([0, 1, 2], (_loadingIndex: number) => {
        Row({ space: AppSpace.Md }) {
          Column()
            .width(72)
            .height(72)
            .borderRadius(AppRadius.Sm)
            .backgroundColor(HomeTheme.ProgressTrack)
          Column({ space: AppSpace.Sm }) {
            Column().width('72%').height(16).borderRadius(8).backgroundColor(HomeTheme.ProgressTrack)
            Column().width('52%').height(12).borderRadius(6).backgroundColor(HomeTheme.ProgressTrack)
            Column().width('90%').height(3).borderRadius(2).backgroundColor(HomeTheme.ProgressTrack)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
        }
        .height(88)
      }, (loadingIndex: number) => loadingIndex.toString())
    }
    .width('100%')
    .opacity(0.7)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Md }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(26)
          .fontColor([HomeTheme.Accent])
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor(AppColor.BrandSoft)
      Text('暂无收听记录')
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
      Text('开始播放后，这里会自动记录你的聆听进度。')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(190)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
    .border({ width: 0.5, color: AppColor.Divider })
    .opacity(this.appeared ? 1 : 0)
    .animation({ duration: 460, delay: 160, curve: AppCurve.Decelerate })
  }
}
