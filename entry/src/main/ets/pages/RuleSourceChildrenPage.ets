import {
  RuleSourceChild,
  RuleSourceChildKind,
  RuleSourceChildLoadResult,
  RuleSourceChildStatus
} from '../model/RuleSourceChild';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { RuleSourceChildService } from '../service/rulesource/RuleSourceChildService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const CHILD_SOURCE_SUCCESS: string = '#168A5B';
const CHILD_SOURCE_WARNING: string = '#9A6700';

class RuleSourceChildFilter {
  static readonly ALL: number = 0;
  static readonly TEXT: number = 1;
  static readonly AUDIO: number = 2;
}

class RuleSourceChildDataSource implements IDataSource {
  private items: RuleSourceChild[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): RuleSourceChild {
    return this.items[index];
  }

  setItems(items: RuleSourceChild[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}

@ComponentV2
export struct RuleSourceChildrenPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local sourceName: string = '';
  @Local allChildren: RuleSourceChild[] = [];
  @Local visibleCount: number = 0;
  @Local filterMode: number = RuleSourceChildFilter.ALL;
  @Local query: string = '';
  @Local isRefreshing: boolean = false;
  @Local refreshFailed: boolean = false;
  private dataSource: RuleSourceChildDataSource = new RuleSourceChildDataSource();

  aboutToAppear(): void {
    if (!RuleSourceChildService.supports(this.sourceUrl)) {
      this.navStack.pop();
      return;
    }
    this.sourceName = this.sourceUrl;
    this.allChildren = RuleSourceChildService.catalog(this.sourceUrl);
    this.applyFilter();
    this.loadSourceName();
    this.refreshChildren(false);
  }

  private async loadSourceName(): Promise<void> {
    try {
      const source: LocalRuleSource | undefined =
        await LocalRuleSourceRepository.get(this.sourceUrl);
      if (source !== undefined && source.bookSourceName.trim().length > 0) {
        this.sourceName = source.bookSourceName.trim();
      }
    } catch (_error) {
      // 子源目录仍可使用来源标识展示。
    }
  }

  private async refreshChildren(showFailure: boolean): Promise<void> {
    if (this.isRefreshing) return;
    this.isRefreshing = true;
    try {
      const result: RuleSourceChildLoadResult =
        await RuleSourceChildService.load(this.sourceUrl);
      this.allChildren = result.items;
      this.refreshFailed = !result.networkUpdated;
      this.applyFilter();
      if (showFailure && !result.networkUpdated) {
        this.showToast($r('app.string.rule_source_child_refresh_failed'));
      }
    } catch (_error) {
      this.refreshFailed = true;
      if (showFailure) this.showToast($r('app.string.rule_source_child_refresh_failed'));
    } finally {
      this.isRefreshing = false;
    }
  }

  private applyFilter(): void {
    const filtered: RuleSourceChild[] = [];
    const cleanQuery = this.query.trim().toLowerCase();
    for (const child of this.allChildren) {
      if (this.filterMode === RuleSourceChildFilter.TEXT &&
        child.kind !== RuleSourceChildKind.TEXT) continue;
      if (this.filterMode === RuleSourceChildFilter.AUDIO &&
        child.kind !== RuleSourceChildKind.AUDIO) continue;
      if (cleanQuery.length > 0 && !child.name.toLowerCase().includes(cleanQuery)) continue;
      filtered.push(child);
    }
    this.visibleCount = filtered.length;
    this.dataSource.setItems(filtered);
  }

  private selectFilter(mode: number): void {
    if (this.filterMode === mode) return;
    this.filterMode = mode;
    this.applyFilter();
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  private openWebLogin(child: RuleSourceChild): void {
    if (!child.canOpenLogin() || !RuleSourceChildService.isAllowedLoginUrl(child.loginUrl)) return;
    const route = RuleSourceLoginRouteParams.of(this.sourceUrl, child.name, child.loginUrl);
    this.navStack.pushPathByName('ruleSourceLogin', route);
  }

  private statusLabel(status: number): ResourceStr {
    if (status === RuleSourceChildStatus.ACTIVE) {
      return $r('app.string.rule_source_child_status_active');
    }
    if (status === RuleSourceChildStatus.DISABLED) {
      return $r('app.string.rule_source_child_status_disabled');
    }
    return $r('app.string.rule_source_child_status_known');
  }

  private statusColor(status: number): ResourceColor {
    if (status === RuleSourceChildStatus.ACTIVE) return CHILD_SOURCE_SUCCESS;
    if (status === RuleSourceChildStatus.DISABLED) return CHILD_SOURCE_WARNING;
    return $r('sys.color.font_tertiary');
  }

  build() {
    Column() {
      this.buildHeader()

      Column({ space: AppSpace.Sm }) {
        this.buildOverview()

        TextInput({
          placeholder: $r('app.string.rule_source_child_search_placeholder'),
          text: this.query
        })
          .width('100%')
          .height(44)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Sm)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
          .onChange((value: string) => {
            this.query = value;
            this.applyFilter();
          })

        Row({ space: AppSpace.Xxs }) {
          this.buildFilterButton($r('app.string.rule_source_child_filter_all'),
            RuleSourceChildFilter.ALL)
          this.buildFilterButton($r('app.string.rule_source_type_text'),
            RuleSourceChildFilter.TEXT)
          this.buildFilterButton($r('app.string.rule_source_type_audio'),
            RuleSourceChildFilter.AUDIO)
        }
        .width('100%')
        .height(40)
        .padding(AppSpace.Xxs)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Sm)
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })

      List({ space: AppSpace.Sm }) {
        if (this.visibleCount === 0) {
          ListItem() {
            this.buildEmptyState()
          }
        } else {
          LazyForEach(this.dataSource, (child: RuleSourceChild) => {
            ListItem() {
              this.buildChildItem(child)
            }
          }, (child: RuleSourceChild) => child.id)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Xl })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
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

      Text($r('app.string.rule_source_child_title'))
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .maxLines(1)

      Button() {
        if (this.isRefreshing) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppColor.Brand)
        } else {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([AppColor.Brand])
        }
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Pill)
      .enabled(!this.isRefreshing)
      .accessibilityText($r('app.string.rule_source_child_refresh'))
      .onClick(() => this.refreshChildren(true))
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xs,
      left: AppSpace.Xs,
      right: AppSpace.Xs,
      bottom: AppSpace.Xs
    })
  }

  @Builder
  buildOverview() {
    Row({ space: AppSpace.Sm }) {
      Column({ space: AppSpace.Xxs }) {
        Text(this.sourceName)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.isRefreshing ? $r('app.string.rule_source_child_catalog_refreshing') :
          (this.refreshFailed ? $r('app.string.rule_source_child_catalog_fallback') :
            $r('app.string.rule_source_child_catalog_updated')))
          .fontSize(AppFont.Caption)
          .fontColor(this.refreshFailed ? CHILD_SOURCE_WARNING : $r('sys.color.font_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: AppSpace.Xxs }) {
        Text(this.visibleCount.toString())
          .fontSize(AppFont.Title)
          .fontColor(AppColor.Brand)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.rule_source_child_count_unit'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildFilterButton(label: ResourceStr, mode: number) {
    Button(label)
      .height(32)
      .layoutWeight(1)
      .fontSize(AppFont.Body)
      .fontColor(this.filterMode === mode ? AppColor.Brand : $r('sys.color.font_secondary'))
      .fontWeight(this.filterMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .backgroundColor(this.filterMode === mode ? AppColor.BrandSoft : Color.Transparent)
      .borderRadius(AppRadius.Xs)
      .onClick(() => this.selectFilter(mode))
  }

  @Builder
  buildChildItem(child: RuleSourceChild) {
    Column({ space: AppSpace.Sm }) {
      Column({ space: AppSpace.Xs }) {
        Row({ space: AppSpace.Xs }) {
          Text(child.name)
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(child.isAudio() ? $r('app.string.rule_source_type_audio') :
            $r('app.string.rule_source_type_text'))
            .fontSize(AppFont.Caption)
            .fontColor(AppColor.Brand)
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 2, bottom: 2 })
            .backgroundColor(AppColor.BrandSoft)
            .borderRadius(AppRadius.Xs)
        }
        .width('100%')

        Row({ space: AppSpace.Xs }) {
          Column()
            .width(8)
            .height(8)
            .backgroundColor(this.statusColor(child.status))
            .borderRadius(AppRadius.Pill)
          Text(this.statusLabel(child.status))
            .fontSize(AppFont.Caption)
            .fontColor(this.statusColor(child.status))
            .fontWeight(FontWeight.Medium)
          if (child.resultCount > 0) {
            Text(child.resultCount.toString())
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Text($r('app.string.rule_source_child_result_unit'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          if (child.responseTimeMs > 0) {
            Text(`${child.responseTimeMs} ms`)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (child.canOpenLogin() && RuleSourceChildService.isAllowedLoginUrl(child.loginUrl)) {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))

        Button() {
          Row({ space: AppSpace.Xxs }) {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(16)
              .fontColor([AppColor.Brand])
            Text($r('app.string.rule_source_child_web_login'))
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(40)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
        .backgroundColor(AppColor.BrandSoft)
        .borderRadius(AppRadius.Sm)
        .onClick(() => this.openWebLogin(child))
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 76 })
    .padding(AppSpace.Md)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(30)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.rule_source_child_empty'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(160)
    .justifyContent(FlexAlign.Center)
  }
}
