import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { AppRadius, AppSpace, AppFont, AppColor } from '../theme/Theme';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { DataService } from '../service/DataService';
import { DownloadService } from '../service/DownloadService';
import { StatsService } from '../service/StatsService';
import { SearchCache } from '../utils/SearchCache';
import { WidgetUpdater } from '../service/WidgetUpdater';
import { WindowUtils } from '../utils/WindowUtils';

interface ThemeOption {
  mode: number;
  label: string;
}

interface TabOption {
  idx: number;
  label: string;
}

interface FocusModeOption {
  mode: number;
  label: string;
}

const THEME_OPTIONS: ThemeOption[] = [
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET, label: '跟随系统' },
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, label: '浅色模式' },
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_DARK, label: '深色模式' }
];

const TAB_OPTIONS: TabOption[] = [
  { idx: 0, label: '首页' },
  { idx: 1, label: '书架' },
  { idx: 2, label: '记录' },
  { idx: 3, label: '我的' }
];

const FOCUS_MODE_OPTIONS: FocusModeOption[] = [
  { mode: 0, label: '共享焦点' },
  { mode: 1, label: '独立焦点' }
];

interface PreloadOption {
  count: number;
  label: string;
}

const PRELOAD_OPTIONS: PreloadOption[] = [
  { count: 1, label: '1章' },
  { count: 3, label: '3章' },
  { count: 5, label: '5章' },
  { count: 10, label: '10章' }
];

const ROW_INDENT: number = AppSpace.Md;

@ComponentV2
export struct SettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @Local selectedThemeIndex: number = 0;
  @Local defaultTab: number = 0;
  @Local focusMode: number = 0;
  @Local autoResume: boolean = true;
  @Local preloadCount: number = 3;
  @Local isLoaded: boolean = false;
  @Local isClearingCache: boolean = false;
  @Local isClearingBookshelf: boolean = false;
  @Local isClearingDownloads: boolean = false;

  aboutToAppear(): void {
    this.loadPrefs();
  }

  private async loadPrefs(): Promise<void> {
    this.currentMode = await PreferenceService.getColorMode();
    this.selectedThemeIndex = THEME_OPTIONS.findIndex((opt: ThemeOption) => opt.mode === this.currentMode);
    if (this.selectedThemeIndex === -1) {
      this.selectedThemeIndex = 0;
    }
    this.defaultTab = await PreferenceService.getDefaultTab();
    this.focusMode = await PreferenceService.getAudioInterruptMode();
    this.autoResume = await PreferenceService.getAudioAutoResume();
    this.preloadCount = await PreferenceService.getPreloadChapters();
    this.isLoaded = true;
  }

  private async setDefaultTab(idx: number): Promise<void> {
    this.defaultTab = idx;
    await PreferenceService.setDefaultTab(idx);
  }

  private async setFocusMode(mode: number): Promise<void> {
    this.focusMode = mode;
    await AudioService.getInstance().setInterruptMode(mode);
  }

  private async setAutoResume(enabled: boolean): Promise<void> {
    this.autoResume = enabled;
    await AudioService.getInstance().setAutoResume(enabled);
  }

  private async setPreloadCount(count: number): Promise<void> {
    this.preloadCount = count;
    await PreferenceService.setPreloadChapters(count);
    ChapterCacheService.getInstance().setPreloadCount(count);
  }

  private async clearCache(): Promise<void> {
    if (this.isClearingCache) return;
    this.isClearingCache = true;
    try {
      const result = await ChapterCacheService.getInstance().clearAllCache();
      const msg = result.failed > 0
        ? `已清除 ${result.deleted} 项，${result.failed} 项失败`
        : `已清除 ${result.deleted} 项`;
      try { this.getUIContext().getPromptAction().showToast({ message: msg }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingCache = false;
    }
  }

  private confirmClearBookshelf(): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '清空在线收藏与播放记录',
      message: '将清除在线收藏、播放记录与进度。本地导入、下载内容和跳过头尾设置会保留。此操作不可恢复,确定吗?',
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '清空', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) this.doClearBookshelf();
    }).catch(() => { /* ignore */ });
  }

  private async doClearBookshelf(): Promise<void> {
    if (this.isClearingBookshelf) return;
    this.isClearingBookshelf = true;
    try {
      const audioService = AudioService.getInstance();
      await audioService.stopForClear();
      await PreferenceService.clearOnlineFavoritesAndHistory();
      await DataService.clearCachedBooks();
      await ChapterCacheService.getInstance().wipeDiskCaches();
      await StatsService.clearBookStats();
      SearchCache.clear();
      audioService.unfreezePersist();
      try { this.getUIContext().getPromptAction().showToast({ message: '在线收藏与播放记录已清空' }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      AudioService.getInstance().unfreezePersist();
      try { this.getUIContext().getPromptAction().showToast({ message: '清空失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingBookshelf = false;
    }
  }

  private async setColorMode(mode: number): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const appCtx = ctx.getApplicationContext();
    try {
      appCtx.setColorMode(mode);
    } catch (_e) { /* system API may throw on invalid context */ }
    this.currentMode = mode;
    const newIndex = THEME_OPTIONS.findIndex((opt: ThemeOption) => opt.mode === mode);
    this.selectedThemeIndex = newIndex !== -1 ? newIndex : 0;
    await PreferenceService.setColorMode(mode);

    // 延迟更新状态栏，让主题切换完成后再应用
    setTimeout(() => {
      WindowUtils.updateColorMode(mode);
    }, 100);
  }

  private confirmClearDownloads(): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '清除下载内容',
      message: '将删除所有整本/单章离线下载音频，不会删除书架、收藏和播放记录。确定清除吗？',
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '清除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) this.doClearDownloads();
    }).catch(() => { /* ignore */ });
  }

  private async doClearDownloads(): Promise<void> {
    if (this.isClearingDownloads) return;
    this.isClearingDownloads = true;
    try {
      await DownloadService.getInstance().clearAllDownloads();
      try { this.getUIContext().getPromptAction().showToast({ message: '下载内容已清除' }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingDownloads = false;
    }
  }

  build() {
    Column() {
      this.buildHeader()

      if (this.isLoaded) {
        Scroll() {
          Column({ space: AppSpace.Lg }) {
            this.buildAppearanceGroup()
            this.buildLaunchGroup()
            this.buildPlaybackGroup()
          }
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: AppSpace.Sm,
            bottom: AppSpace.Xl
          })
        }
        .layoutWeight(1)
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
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Text('设置')
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
  buildGroupTitle(title: string) {
    Text(title)
      .fontSize(AppFont.Body)
      .fontColor($r('sys.color.font_tertiary'))
      .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.comp_divider'))
      .margin({ left: ROW_INDENT })
  }

  @Builder
  buildAppearanceGroup() {
    Column() {
      this.buildGroupTitle('外观')

      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('主题模式')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Select(THEME_OPTIONS.map((opt: ThemeOption): SelectOption => { return { value: opt.label }; }))
            .selected(this.selectedThemeIndex)
            .value(THEME_OPTIONS[this.selectedThemeIndex]?.label ?? '跟随系统')
            .font({ size: AppFont.Body })
            .fontColor($r('sys.color.font_secondary'))
            .backgroundColor(Color.Transparent)
            .onSelect((index: number) => {
              this.setColorMode(THEME_OPTIONS[index].mode);
            })
        }
        .width('100%')
        .padding({
          left: ROW_INDENT,
          right: AppSpace.Xs,
          top: AppSpace.Sm,
          bottom: AppSpace.Sm
        })
        .constraintSize({ minHeight: 56 })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildLaunchGroup() {
    Column() {
      this.buildGroupTitle('启动')

      Column() {
        this.buildSelectItem(
          '默认打开',
          '',
          TAB_OPTIONS.map((opt: TabOption): SelectOption => { return { value: opt.label }; }),
          this.defaultTab,
          (index: number) => this.setDefaultTab(index)
        )
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildPlaybackGroup() {
    Column() {
      this.buildGroupTitle('播放')

      Column() {
        this.buildSelectItem(
          '音频焦点',
          this.focusMode === 1 ? '与本应用其他音频独立计算焦点' : '与系统其他音频互斥（推荐）',
          FOCUS_MODE_OPTIONS.map((opt: FocusModeOption): SelectOption => { return { value: opt.label }; }),
          FOCUS_MODE_OPTIONS.findIndex((opt: FocusModeOption) => opt.mode === this.focusMode),
          (index: number) => this.setFocusMode(FOCUS_MODE_OPTIONS[index].mode)
        )

        this.buildDivider()

        this.buildSwitchItem(
          '失焦后自动恢复',
          '被来电、导航、视频打断后自动续播',
          this.autoResume,
          (isOn: boolean) => this.setAutoResume(isOn)
        )

        this.buildDivider()

        this.buildSelectItem(
          '预加载章节数',
          '收听时提前缓存后续音频章节',
          PRELOAD_OPTIONS.map((opt: PreloadOption): SelectOption => { return { value: opt.label }; }),
          PRELOAD_OPTIONS.findIndex((opt: PreloadOption) => opt.count === this.preloadCount),
          (index: number) => this.setPreloadCount(PRELOAD_OPTIONS[index].count)
        )

        this.buildDivider()

        this.buildActionItem('清除预加载缓存', '释放已缓存的章节音频', () => this.clearCache(), this.isClearingCache)

        this.buildDivider()

        this.buildActionItem('清除下载内容', '删除整本/单章离线音频，保留书架和记录', () => this.confirmClearDownloads(), this.isClearingDownloads)

        this.buildDivider()

        this.buildActionItem('清空在线收藏与播放记录', '清除在线收藏 / 缓存书 / 播放记录，保留导入和下载', () => this.confirmClearBookshelf(), this.isClearingBookshelf)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildSelectItem(
    title: string,
    subtitle: string,
    options: SelectOption[],
    selected: number,
    onSelect: (index: number) => void
  ) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Select(options)
        .selected(selected)
        .value(options[selected]?.value ?? '')
        .font({ size: AppFont.Body })
        .fontColor($r('sys.color.font_secondary'))
        .backgroundColor(Color.Transparent)
        .onSelect((index: number) => onSelect(index))
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: AppSpace.Xs,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
  }

  @Builder
  buildSwitchItem(
    title: string,
    subtitle: string,
    isOn: boolean,
    onChange: (isOn: boolean) => void
  ) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((on: boolean) => onChange(on))
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
  }

  @Builder
  buildActionItem(title: string, subtitle: string, onAction: () => void, isClearing: boolean = false) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (isClearing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppColor.Brand)
      } else {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
    .enabled(!this.isClearingCache && !this.isClearingBookshelf && !this.isClearingDownloads)
    .opacity((this.isClearingCache || this.isClearingBookshelf || this.isClearingDownloads) ? 0.5 : 1.0)
    .onClick(() => onAction())
  }
}
