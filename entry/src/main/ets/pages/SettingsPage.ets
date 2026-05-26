import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
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
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('设置')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: AppSpace.Sm })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
      })

      Scroll() {
        Column({ space: AppSpace.Md }) {
          this.buildThemeSection()
          this.buildDefaultTabSection()
          this.buildAudioFocusSection()
        }
        .width('100%')
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm, bottom: AppSpace.Xl })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  buildDefaultTabSection() {
    Column({ space: AppSpace.Xs }) {
      Text('启动页')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: AppSpace.Md, bottom: AppSpace.Xxs })

      Row() {
        Text('默认打开')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Select(TAB_OPTIONS.map((opt: TabOption): SelectOption => { return { value: opt.label }; }))
          .selected(this.defaultTab)
          .value(TAB_OPTIONS[this.defaultTab].label)
          .onSelect((index: number) => {
            this.setDefaultTab(index);
          })
          .width(120)
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildThemeSection() {
    Column({ space: AppSpace.Xs }) {
      Text('外观')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: AppSpace.Md, bottom: AppSpace.Xxs })

      Row() {
        Text('主题模式')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Select(THEME_OPTIONS.map((opt: ThemeOption): SelectOption => { return { value: opt.label }; }))
          .selected(THEME_OPTIONS.findIndex(opt => opt.mode === this.currentMode))
          .value(THEME_OPTIONS.find(opt => opt.mode === this.currentMode)?.label || '跟随系统')
          .onSelect((index: number) => {
            this.setColorMode(THEME_OPTIONS[index].mode);
          })
          .width(120)
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: AppSpace.Md })
  }

  @Builder
  buildAudioFocusSection() {
    Column({ space: AppSpace.Xs }) {
      Text('播放')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: AppSpace.Md, bottom: AppSpace.Xxs })

      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('音频焦点')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Text(this.focusMode === 1 ? '与本应用其他音频独立计算焦点' : '与系统其他音频互斥（推荐）')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Select(FOCUS_MODE_OPTIONS.map((opt: FocusModeOption): SelectOption => {
            return { value: opt.label };
          }))
            .selected(FOCUS_MODE_OPTIONS.findIndex(opt => opt.mode === this.focusMode))
            .value(FOCUS_MODE_OPTIONS.find(opt => opt.mode === this.focusMode)?.label || '共享焦点')
            .onSelect((index: number) => {
              this.setFocusMode(FOCUS_MODE_OPTIONS[index].mode);
            })
            .width(120)
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
          .margin({ left: AppSpace.Lg, right: AppSpace.Lg })

        Row() {
          Column({ space: 2 }) {
            Text('失焦后自动恢复')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Text('被来电、导航打断后自动续播')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.autoResume })
            .onChange((isOn: boolean) => {
              this.setAutoResume(isOn);
            })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .margin({ left: AppSpace.Sm, right: AppSpace.Sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

}
