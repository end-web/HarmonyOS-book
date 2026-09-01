/**
 * ReaderSettingsSheet - 阅读设置面板
 *
 * 按鸿蒙分组卡片规范重排：顶部实时预览 + 四张设置卡（字号 / 行高 / 主题 / 背景）。
 * 面板自身走 systemMaterial 玻璃态，卡片用当前阅读配色而非系统色，
 * 这样调主题时面板本身也跟着变，用户不用关掉面板才能看效果。
 *
 * 本组件只负责呈现与回调，不落盘；持久化由 ReaderPage 统一做。
 */
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace, AppMotion, AppCurve } from '../theme/Theme';
import { TextReadingSettings } from '../model/TextReading';
import {
  ReaderPalette,
  ReaderPattern,
  ReaderThemeId,
  ReaderThemePreset,
  READER_THEME_PRESETS,
  hexToHsv,
  hsvToHex
} from '../model/ReaderTheme';
import { ReaderBackground } from './ReaderBackground';
import { WindowUtils } from '../utils/WindowUtils';

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

/** 背景图案选项 */
class PatternOption {
  id: string = ReaderPattern.None;
  label: string = '';
  icon: Resource = $r('sys.symbol.xmark');

  static of(id: string, label: string, icon: Resource): PatternOption {
    const option = new PatternOption();
    option.id = id;
    option.label = label;
    option.icon = icon;
    return option;
  }
}

const PATTERN_OPTIONS: PatternOption[] = [
  PatternOption.of(ReaderPattern.None, '无', $r('sys.symbol.xmark')),
  PatternOption.of(ReaderPattern.Paper, '纸纹', $r('sys.symbol.doc_plaintext')),
  PatternOption.of(ReaderPattern.Cloth, '布纹', $r('sys.symbol.grid')),
  PatternOption.of(ReaderPattern.Image, '相册', $r('sys.symbol.picture'))
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
  @Param title: string = '';
  @Param palette: ReaderPalette = new ReaderPalette();
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Text(this.title)
        .fontSize(AppFont.Caption)
        .fontColor(this.palette.secondary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpace.Md)
    .borderRadius(AppRadius.Lg)
    .backgroundColor(ReaderPalette.withAlpha(this.palette.primary, 0x0d))
  }
}

@ComponentV2
export struct ReaderSettingsSheet {
  @Param fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Param lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Param themeId: string = ReaderThemeId.Parchment;
  @Param customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Param pattern: string = ReaderPattern.None;
  @Param bgImagePath: string = '';
  @Param overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  /** 由父页面依 themeId / customBackground 解析好的配色 */
  @Param palette: ReaderPalette = new ReaderPalette();
  @Param bottomSafeVp: number = 0;

  @Event onFontSizeChange: (value: number, commit: boolean) => void = () => {};
  @Event onLineHeightChange: (value: number, commit: boolean) => void = () => {};
  @Event onThemeChange: (themeId: string) => void = () => {};
  @Event onCustomBackgroundChange: (hex: string, commit: boolean) => void = () => {};
  @Event onPatternChange: (pattern: string) => void = () => {};
  @Event onOverlayChange: (value: number, commit: boolean) => void = () => {};
  /** 请求打开相册选图；由页面侧执行 picker + 落沙箱 */
  @Event onPickImage: () => void = () => {};
  @Event onResetDefaults: () => void = () => {};
  @Event onClose: () => void = () => {};

  /** 自定义色滑杆状态：面板打开时由已存色值还原 */
  @Local hue: number = 40;
  @Local colorBrightness: number = 0.96;
  @Local saturation: number = 0.04;

  aboutToAppear(): void {
    const hsv = hexToHsv(this.customBackground);
    this.hue = hsv.h;
    this.saturation = hsv.s;
    this.colorBrightness = hsv.v;
  }

  /** 胶囊按钮：分档选择用（行高档位、背景图案） */
  @Builder
  chip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(selected ? AppColor.OnBrand : this.palette.primary)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(AppRadius.Pill)
      .backgroundColor(selected ? AppColor.Brand : ReaderPalette.withAlpha(this.palette.primary, 0x0f))
      .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
      .onClick(() => onTap())
  }

  /** 实时预览：真实字号、行高、底色与纹理，所见即所得 */
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
    ReaderSettingCard({ title: '字号', palette: this.palette }) {
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
          .trackColor(ReaderPalette.withAlpha(this.palette.primary, 0x14))
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
        .fontColor([enabled ? this.palette.primary : this.palette.secondary])
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(ReaderPalette.withAlpha(this.palette.primary, 0x0f))
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
    ReaderSettingCard({ title: '行高', palette: this.palette }) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Xs }) {
          ForEach(
            LINE_HEIGHT_PRESETS,
            (preset: LineHeightPreset) => {
              this.chip(preset.label, this.isLineHeightPreset(preset.value), () => {
                this.onLineHeightChange(preset.value, true);
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
            .trackColor(ReaderPalette.withAlpha(this.palette.primary, 0x14))
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

  /** 主题色板：预设 5 个 + 自定义入口，选中打勾 */
  @Builder
  buildThemeSection() {
    ReaderSettingCard({ title: '阅读主题', palette: this.palette }) {
      Row({ space: AppSpace.Sm }) {
        ForEach(
          READER_THEME_PRESETS,
          (preset: ReaderThemePreset) => {
            this.swatch(preset.background, preset.label, this.themeId === preset.id,
              preset.isDark, () => {
                this.onThemeChange(preset.id);
              })
          },
          (preset: ReaderThemePreset) => `theme-${preset.id}`
        )
        // 自定义色入口：色块显示当前自定义色
        this.swatch(this.customBackground, '自定义', this.themeId === ReaderThemeId.Custom,
          this.palette.isDark, () => {
            this.onThemeChange(ReaderThemeId.Custom);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
  }

  /** 单个色板：圆形色块 + 名称，选中态描边并打勾 */
  @Builder
  swatch(color: string, label: string, selected: boolean, darkSwatch: boolean, onTap: () => void) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(color)
          .border({
            width: selected ? 2 : 0.5,
            color: selected ? AppColor.Brand : ReaderPalette.withAlpha(this.palette.primary, 0x33)
          })
        if (selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([darkSwatch ? '#FFFFFF' : '#2A2724'])
        }
      }
      .width(44)
      .height(44)

      Text(label)
        .fontSize(10)
        .fontColor(selected ? AppColor.Brand : this.palette.secondary)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => onTap())
  }

  /** 三个滑杆合成当前自定义色并回调 */
  private emitCustomColor(commit: boolean): void {
    this.onCustomBackgroundChange(hsvToHex(this.hue, this.saturation, this.colorBrightness), commit);
  }

  /** 自定义底色：色相 / 浓淡 / 明度三杆，实时出色值 */
  @Builder
  buildCustomColorSection() {
    ReaderSettingCard({ title: '自定义底色', palette: this.palette }) {
      Column({ space: AppSpace.Xs }) {
        // 当前色值预览条
        Row({ space: AppSpace.Sm }) {
          Column()
            .width(56)
            .height(28)
            .borderRadius(AppRadius.Sm)
            .backgroundColor(this.customBackground)
            .border({ width: 0.5, color: ReaderPalette.withAlpha(this.palette.primary, 0x33) })
          Text(this.customBackground)
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.secondary)
          Blank()
          if (this.themeId !== ReaderThemeId.Custom) {
            Text('点击应用')
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                this.onThemeChange(ReaderThemeId.Custom);
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.colorSlider('色相', this.hue, 0, 360, 1, (value: number, commit: boolean) => {
          this.hue = Math.round(value);
          this.emitCustomColor(commit);
        })
        this.colorSlider('浓淡', this.saturation * 100, 0, 100, 1, (value: number, commit: boolean) => {
          this.saturation = value / 100;
          this.emitCustomColor(commit);
        })
        this.colorSlider('明度', this.colorBrightness * 100, 0, 100, 1, (value: number, commit: boolean) => {
          this.colorBrightness = value / 100;
          this.emitCustomColor(commit);
        })
      }
      .width('100%')
    }
  }

  /** 带标签的紧凑滑杆，供自定义色三通道复用 */
  @Builder
  colorSlider(label: string, value: number, min: number, max: number, step: number,
    onValue: (value: number, commit: boolean) => void) {
    Row({ space: AppSpace.Sm }) {
      Text(label)
        .fontSize(AppFont.Caption)
        .fontColor(this.palette.secondary)
        .width(30)
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.InSet })
        .layoutWeight(1)
        .height(32)
        .blockColor(AppColor.OnBrand)
        .trackColor(ReaderPalette.withAlpha(this.palette.primary, 0x14))
        .selectedColor(AppColor.Brand)
        .trackThickness(4)
        .onChange((v: number, mode: SliderChangeMode): void => {
          onValue(v, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 背景图案：四选一，选相册时额外露出蒙层浓度杆 */
  @Builder
  buildPatternSection() {
    ReaderSettingCard({ title: '背景图案', palette: this.palette }) {
      Column({ space: AppSpace.Sm }) {
        Row({ space: AppSpace.Xs }) {
          ForEach(
            PATTERN_OPTIONS,
            (option: PatternOption) => {
              this.patternChip(option)
            },
            (option: PatternOption) => `pattern-${option.id}`
          )
        }
        .width('100%')

        if (this.pattern === ReaderPattern.Image) {
          Row({ space: AppSpace.Sm }) {
            Text('蒙层')
              .fontSize(AppFont.Caption)
              .fontColor(this.palette.secondary)
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
              .trackColor(ReaderPalette.withAlpha(this.palette.primary, 0x14))
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

          Text('蒙层越浓，图片越淡，正文越清楚')
            .fontSize(10)
            .fontColor(this.palette.secondary)
            .width('100%')
        }
      }
      .width('100%')
    }
  }

  /** 图案胶囊：带图标；相册项点了先走选图 */
  @Builder
  patternChip(option: PatternOption) {
    Column({ space: 2 }) {
      SymbolGlyph(option.icon)
        .fontSize(18)
        .fontColor([this.pattern === option.id ? AppColor.OnBrand : this.palette.primary])
      Text(option.label)
        .fontSize(10)
        .fontColor(this.pattern === option.id ? AppColor.OnBrand : this.palette.primary)
    }
    .layoutWeight(1)
    .height(50)
    .justifyContent(FlexAlign.Center)
    .borderRadius(AppRadius.Md)
    .backgroundColor(this.pattern === option.id
      ? AppColor.Brand : ReaderPalette.withAlpha(this.palette.primary, 0x0f))
    .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
    .onClick(() => {
      if (option.id === ReaderPattern.Image) {
        // 已有图时直接切回图片模式，否则拉起相册
        if (this.bgImagePath.length > 0 && this.pattern !== ReaderPattern.Image) {
          this.onPatternChange(ReaderPattern.Image);
        } else {
          this.onPickImage();
        }
      } else {
        this.onPatternChange(option.id);
      }
    })
  }

  build() {
    Column() {
      // 顶部抓手，鸿蒙弹层惯例
      Column()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(ReaderPalette.withAlpha(this.palette.primary, 0x26))
        .margin({ top: AppSpace.Sm, bottom: AppSpace.Xs })

      Row() {
        Text('阅读设置')
          .fontSize(AppFont.Title)
          .fontColor(this.palette.primary)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('恢复默认')
          .fontSize(AppFont.Caption)
          .fontColor(this.palette.secondary)
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Pill)
          .backgroundColor(ReaderPalette.withAlpha(this.palette.primary, 0x0f))
          .onClick(() => this.onResetDefaults())
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([this.palette.secondary])
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
          this.buildThemeSection()
          this.buildCustomColorSection()
          this.buildPatternSection()
        }
        .width('100%')
        .padding({
          left: AppSpace.Lg,
          right: AppSpace.Lg,
          bottom: WindowUtils.getFloatingTabBottomVp(this.bottomSafeVp) + AppSpace.Lg
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('82%')
    .borderRadius({ topLeft: 24, topRight: 24 })
    .clip(true)
    .systemMaterial(AppMaterial.DialogUltraThick)
    // 面板底也跟阅读配色走，玻璃态之上叠一层弱色，换主题时面板同步变
    .backgroundColor(ReaderPalette.withAlpha(this.palette.background, 0xdd))
  }
}
