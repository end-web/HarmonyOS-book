import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
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
  { idx: 2, label: '书源' },
  { idx: 3, label: '我的' }
];

const FOCUS_MODE_OPTIONS: FocusModeOption[] = [
  { mode: 0, label: '共享焦点' },
  { mode: 1, label: '独立焦点' }
];

const ROW_INDENT: number = AppSpace.Md;

@ComponentV2
export struct SettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @Local defaultTab: number = 0;
  @Local focusMode: number = 0;
  @Local autoResume: boolean = true;

  aboutToAppear(): void {
    this.loadColorMode();
    this.loadDefaultTab();
    this.loadAudioFocusPrefs();
  }

  private async loadColorMode(): Promise<void> {
    this.currentMode = await PreferenceService.getColorMode();
  }

  private async loadDefaultTab(): Promise<void> {
    this.defaultTab = await PreferenceService.getDefaultTab();
  }

  private async loadAudioFocusPrefs(): Promise<void> {
    this.focusMode = await PreferenceService.getAudioInterruptMode();
    this.autoResume = await PreferenceService.getAudioAutoResume();
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

  private async setColorMode(mode: number): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const appCtx = ctx.getApplicationContext();
      appCtx.setColorMode(mode);
      this.currentMode = mode;
      await PreferenceService.setColorMode(mode);
    } catch (_e) { /* ignore */ }
  }

  build() {
    Column() {
      this.buildHeader()

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          this.buildAppearanceGroup()
          this.buildLaunchGroup()
          this.buildPlaybackGroup()
          this.buildDeveloperGroup()
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
        this.buildSelectItem(
          '主题模式',
          '',
          THEME_OPTIONS.map((opt: ThemeOption): SelectOption => { return { value: opt.label }; }),
          THEME_OPTIONS.findIndex((opt: ThemeOption) => opt.mode === this.currentMode),
          THEME_OPTIONS.find((opt: ThemeOption) => opt.mode === this.currentMode)?.label ?? '跟随系统',
          (index: number) => this.setColorMode(THEME_OPTIONS[index].mode)
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
  buildLaunchGroup() {
    Column() {
      this.buildGroupTitle('启动')

      Column() {
        this.buildSelectItem(
          '默认打开',
          '',
          TAB_OPTIONS.map((opt: TabOption): SelectOption => { return { value: opt.label }; }),
          this.defaultTab,
          TAB_OPTIONS[this.defaultTab].label,
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
          FOCUS_MODE_OPTIONS.find((opt: FocusModeOption) => opt.mode === this.focusMode)?.label ?? '共享焦点',
          (index: number) => this.setFocusMode(FOCUS_MODE_OPTIONS[index].mode)
        )

        this.buildDivider()

        this.buildSwitchItem(
          '失焦后自动恢复',
          '被来电、导航打断后自动续播',
          this.autoResume,
          (isOn: boolean) => this.setAutoResume(isOn)
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
  buildSelectItem(
    title: string,
    subtitle: string,
    options: SelectOption[],
    selected: number,
    valueLabel: string,
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
        .value(valueLabel)
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
  buildDeveloperGroup() {
    Column() {
      this.buildGroupTitle('开发者')

      Column() {
        Row() {
          Text('规则引擎测试')
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_tertiary')])
        }
        .width('100%')
        .padding({
          left: ROW_INDENT,
          right: ROW_INDENT,
          top: AppSpace.Sm,
          bottom: AppSpace.Sm
        })
        .constraintSize({ minHeight: 56 })
        .onClick(() => {
          this.navStack.pushPathByName('RuleEngineTestPage', null);
        })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
}
