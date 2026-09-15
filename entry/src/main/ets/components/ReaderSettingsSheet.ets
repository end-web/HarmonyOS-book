/**
 * ReaderSettingsSheet - 阅读设置面板
 *
 * 按鸿蒙分组卡片规范重排：顶部实时预览 + 字号 / 行高 / 翻页 / 主题设置卡。
 * 面板由父页面的原生 bindSheet 提供材质，内容文字跟随系统深浅模式。
 * 阅读纸张配色只影响正文与预览，不修改 App 的外观偏好。
 *
 * 本组件只负责呈现与回调，不落盘；持久化由 ReaderPage 统一做。
 */
import { AppColor, AppFont, AppRadius, AppSpace, AppMotion, AppCurve } from '../theme/Theme';
import { TextReadingSettings, PageTurnMode } from '../model/TextReading';
import {
  ReaderPalette,
  ReaderPattern,
  ReaderThemeId,
  ReaderThemePreset,
  READER_THEME_PRESETS
} from '../model/ReaderTheme';
import { ReaderBackground } from './ReaderBackground';

/** 行高预设档位 */
class LineHeightPreset {
  label: string = '';
  value: number = 1.9;

  static of(label: string, value: number): LineHeightPreset {
    const preset = new LineHeightPreset();
    preset.label = label;
    preset.value = value;
    return preset;
  }
}

const LINE_HEIGHT_PRESETS: LineHeightPreset[] = [
  LineHeightPreset.of('紧凑', 1.5),
  LineHeightPreset.of('适中', 1.7),
  LineHeightPreset.of('标准', 1.9),
  LineHeightPreset.of('宽松', 2.2)
];

const PREVIEW_TEXT: string = '　　夜色像一层薄薄的墨，慢慢洇进窗棂。他合上书页，听见远处传来一声钟响，'
  + '于是想起许多年前的那个黄昏，也是这样的光，这样的静。';

/**
 * 设置分组卡片。
 * 内容走 @BuilderParam + 尾随闭包；UI 描述不能当普通 lambda 参数传，
 * 所以这里必须是独立组件而不是父组件里的 @Builder 方法。
 */
@ComponentV2
struct ReaderSettingCard {
  @Param title: ResourceStr = '';
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Text(this.title)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.Md)
    .borderRadius(AppRadius.Lg)
    .backgroundColor(AppColor.GlassSheetControlTint)
    .border({ width: 0.5, color: AppColor.GlassSheetStroke })
  }
}

/** 分档按钮使用 @Param 观察选中态，避免 @Builder 按值参数停留在首次渲染。 */
@ComponentV2
struct ReaderSettingChip {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(AppFont.Caption)
      .fontColor(this.selected ? AppColor.OnBrand : $r('sys.color.font_primary'))
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(AppRadius.Pill)
      .backgroundColor(this.selected ? AppColor.Brand : AppColor.GlassSheetControlTint)
      .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
      .onClick(() => this.onSelect())
  }
}

@ComponentV2
struct ReaderThemeSwatch {
  @Param preset: ReaderThemePreset = new ReaderThemePreset();
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.preset.background)
          .border({
            width: this.selected ? 2 : 0.5,
            color: this.selected ? AppColor.Brand : AppColor.GlassSheetStroke
          })
        if (this.selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([this.preset.isDark ? '#FFFFFF' : '#2A2724'])
        }
      }
      .width(44)
      .height(44)

      Text(this.preset.label)
        .fontSize(10)
        .fontColor(this.selected ? AppColor.Brand : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onSelect())
  }
}

@ComponentV2
export struct ReaderSettingsSheet {
  @Param fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Param lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Param themeId: string = ReaderThemeId.Parchment;
  @Param pattern: string = ReaderPattern.None;
  @Param bgImagePath: string = '';
  @Param overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  @Param pageTurnMode: string = PageTurnMode.Cover;
  @Param showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  /** 由父页面依 themeId / customBackground 解析好的配色 */
  @Param palette: ReaderPalette = new ReaderPalette();

  @Event onFontSizeChange: (value: number, commit: boolean) => void = () => {};
  @Event onLineHeightChange: (value: number, commit: boolean) => void = () => {};
  @Event onThemeChange: (themeId: string) => void = () => {};
  @Event onOverlayChange: (value: number, commit: boolean) => void = () => {};
  @Event onPageTurnModeChange: (mode: string) => void = () => {};
  @Event onReadingStatusChange: (enabled: boolean) => void = () => {};
  /** 请求打开相册选图；由页面侧执行 picker + 落沙箱 */
  @Event onPickImage: () => void = () => {};
  @Event onResetDefaults: () => void = () => {};
  @Event onClose: () => void = () => {};

  /** 实时预览：真实字号、行高、底色与图片，所见即所得 */
  @Builder
  buildPreview() {
    Stack() {
      ReaderBackground({
        palette: this.palette,
        pattern: this.pattern,
        bgImagePath: this.bgImagePath,
        overlayAlpha: this.overlayAlpha
      })

      Column({ space: 6 }) {
        Row() {
          Text('第十二章 归客')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('3/24')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
        }
        .width('100%')

        Text(PREVIEW_TEXT)
          .width('100%')
          .fontSize(this.fontSize)
          .fontColor(this.palette.primary)
          .lineHeight(this.fontSize * this.lineHeight)
          .textAlign(TextAlign.Start)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: AppSpace.Sm, bottom: AppSpace.Sm })
    }
    .width('100%')
    .height(160)
    .borderRadius(AppRadius.Lg)
    .clip(true)
    .border({ width: 0.5, color: ReaderPalette.withAlpha(this.palette.primary, 0x1f) })
  }

  /** 字号：左右步进 + 滑杆，步进按钮到边界自动置灰 */
  @Builder
  buildFontSizeSection() {
    ReaderSettingCard({ title: '字号' }) {
      Row({ space: AppSpace.Sm }) {
        this.stepper($r('sys.symbol.minus'), this.fontSize > TextReadingSettings.FONT_SIZE_MIN, () => {
          this.onFontSizeChange(this.fontSize - 1, true);
        })

        Slider({
          value: this.fontSize,
          min: TextReadingSettings.FONT_SIZE_MIN,
          max: TextReadingSettings.FONT_SIZE_MAX,
          step: 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(40)
          .blockColor(AppColor.OnBrand)
          .trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand)
          .trackThickness(6)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onFontSizeChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })

        this.stepper($r('sys.symbol.plus'), this.fontSize < TextReadingSettings.FONT_SIZE_MAX, () => {
          this.onFontSizeChange(this.fontSize + 1, true);
        })

        Text(`${this.fontSize}`)
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .fontWeight(FontWeight.Medium)
          .width(28)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 圆形步进按钮 */
  @Builder
  stepper(icon: Resource, enabled: boolean, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')])
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(AppColor.GlassSheetControlTint)
    .opacity(enabled ? 1 : 0.4)
    .onClick(() => {
      if (enabled) onTap();
    })
  }

  /** 当前行高是否命中某个预设档（容差 0.05，避免浮点误差导致选中态丢失） */
  private isLineHeightPreset(value: number): boolean {
    return Math.abs(this.lineHeight - value) < 0.05;
  }

  /** 行高：四档快选 + 滑杆微调，两者双向同步 */
  @Builder
  buildLineHeightSection() {
    ReaderSettingCard({ title: '行高' }) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Xs }) {
          ForEach(
            LINE_HEIGHT_PRESETS,
            (preset: LineHeightPreset) => {
              ReaderSettingChip({
                label: preset.label,
                selected: this.isLineHeightPreset(preset.value),
                onSelect: () => this.onLineHeightChange(preset.value, true)
              })
            },
            (preset: LineHeightPreset) => `lh-${preset.label}`
          )
        }
        .width('100%')

        Row({ space: AppSpace.Sm }) {
          Slider({
            value: this.lineHeight,
            min: TextReadingSettings.LINE_HEIGHT_MIN,
            max: TextReadingSettings.LINE_HEIGHT_MAX,
            step: 0.1,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .height(40)
            .blockColor(AppColor.OnBrand)
            .trackColor($r('sys.color.comp_divider'))
            .selectedColor(AppColor.Brand)
            .trackThickness(6)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.onLineHeightChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
            })

          Text(`${this.lineHeight.toFixed(1)}`)
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .fontWeight(FontWeight.Medium)
            .width(32)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
    }
  }

  /** 预设主题与自定义图片互斥，图片主题内保留换图和蒙层。 */
  @Builder
  buildThemeSection() {
    ReaderSettingCard({ title: $r('app.string.reader_theme_title') }) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Sm }) {
          ForEach(
            READER_THEME_PRESETS,
            (preset: ReaderThemePreset) => {
              ReaderThemeSwatch({
                preset: preset,
                selected: this.themeId === preset.id,
                onSelect: () => this.onThemeChange(preset.id)
              })
            },
            (preset: ReaderThemePreset) => `theme-${preset.id}`
          )
          this.buildImageThemeSwatch()
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        if (this.themeId === ReaderThemeId.Image) {
          this.buildImageControls()
        }
      }
      .width('100%')
    }
  }

  @Builder
  buildImageThemeSwatch() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(20)
          .fontColor([this.themeId === ReaderThemeId.Image ? AppColor.Brand : $r('sys.color.font_secondary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.GlassSheetControlTint)
      .border({
        width: this.themeId === ReaderThemeId.Image ? 2 : 0.5,
        color: this.themeId === ReaderThemeId.Image ? AppColor.Brand : AppColor.GlassSheetStroke
      })
      .margin({ top: 2, bottom: 2 })

      Text($r('app.string.reader_custom_image'))
        .fontSize(10)
        .fontColor(this.themeId === ReaderThemeId.Image ? AppColor.Brand : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.bgImagePath.length > 0) {
        this.onThemeChange(ReaderThemeId.Image);
      } else {
        this.onPickImage();
      }
    })
  }

  @Builder
  buildImageControls() {
    Column({ space: AppSpace.Sm }) {
      Button($r('app.string.reader_change_image'))
        .fontSize(AppFont.Caption)
        .fontColor(AppColor.Brand)
        .backgroundColor(AppColor.GlassSheetControlTint)
        .onClick(() => this.onPickImage())
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_image_overlay'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width(30)
        Slider({
          value: this.overlayAlpha * 100,
          min: TextReadingSettings.OVERLAY_MIN * 100,
          max: TextReadingSettings.OVERLAY_MAX * 100,
          step: 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(32)
          .blockColor(AppColor.OnBrand)
          .trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand)
          .trackThickness(4)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onOverlayChange(value / 100,
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Text(`${Math.round(this.overlayAlpha * 100)}%`)
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .width(34)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.reader_image_overlay_hint'))
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  /** 翻页模式：覆盖、仿真 */
  @Builder
  buildPageTurnModeSection() {
    ReaderSettingCard({ title: '翻页模式' }) {
      Row({ space: AppSpace.Xs }) {
        ReaderSettingChip({
          label: '覆盖',
          selected: this.pageTurnMode === PageTurnMode.Cover,
          onSelect: () => this.onPageTurnModeChange(PageTurnMode.Cover)
        })
        ReaderSettingChip({
          label: '仿真',
          selected: this.pageTurnMode === PageTurnMode.Simulation,
          onSelect: () => this.onPageTurnModeChange(PageTurnMode.Simulation)
        })
      }
      .width('100%')
    }
  }

  @Builder
  buildReadingStatusSection() {
    ReaderSettingCard({ title: $r('app.string.reader_footer_title') }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_show_battery_time'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.showReadingStatus })
          .selectedColor(AppColor.Brand)
          .onChange((enabled: boolean): void => this.onReadingStatusChange(enabled))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Column() {
      Row() {
        Text('阅读设置')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('恢复默认')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Pill)
          .backgroundColor(AppColor.GlassSheetControlTint)
          .onClick(() => this.onResetDefaults())
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .margin({ left: AppSpace.Xs })
        .onClick(() => this.onClose())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: AppSpace.Lg, right: AppSpace.Md, bottom: AppSpace.Sm })

      Scroll() {
        Column({ space: AppSpace.Md }) {
          this.buildPreview()
          this.buildFontSizeSection()
          this.buildLineHeightSection()
          this.buildPageTurnModeSection()
          this.buildThemeSection()
          this.buildReadingStatusSection()
        }
        .width('100%')
        .padding({
          left: AppSpace.Lg,
          right: AppSpace.Lg,
          bottom: AppSpace.Lg
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }
}
