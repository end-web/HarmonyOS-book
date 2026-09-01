import { describe, it, expect } from '@ohos/hypium';
import {
  ReaderPalette,
  ReaderPattern,
  ReaderThemeId,
  findThemePreset,
  hexLuminance,
  hexToHsv,
  hsvToHex,
  normalizeHex,
  resolvePalette
} from '../main/ets/model/ReaderTheme';
import { TextReadingSettings } from '../main/ets/model/TextReading';

export default function readerThemeTest() {
  describe('ReaderTheme', () => {
    it('normalizes hex input shapes and rejects garbage', 0, () => {
      expect(normalizeHex('#ff8800')).assertEqual('#FF8800');
      // 缺少 # 前缀
      expect(normalizeHex('FF8800')).assertEqual('#FF8800');
      // #RGB 简写展开
      expect(normalizeHex('#f80')).assertEqual('#FF8800');
      // #AARRGGBB 丢掉 alpha 段
      expect(normalizeHex('#CCFF8800')).assertEqual('#FF8800');
      // 非法值回落默认底色
      expect(normalizeHex('not-a-color')).assertEqual('#F5F2EA');
      expect(normalizeHex('')).assertEqual('#F5F2EA');
      expect(normalizeHex('#GGHHII')).assertEqual('#F5F2EA');
    });

    it('derives readable text color from background luminance', 0, () => {
      // 浅底 → 深字
      const light = resolvePalette(ReaderThemeId.Custom, '#FFFFFF');
      expect(light.isDark).assertFalse();
      // 深底 → 浅字
      const dark = resolvePalette(ReaderThemeId.Custom, '#101010');
      expect(dark.isDark).assertTrue();
      // 正文色不用纯黑纯白，避免高对比刺眼
      expect(light.primary === '#000000').assertFalse();
      expect(dark.primary === '#FFFFFF').assertFalse();
    });

    it('computes luminance in the expected order', 0, () => {
      expect(hexLuminance('#000000') < hexLuminance('#808080')).assertTrue();
      expect(hexLuminance('#808080') < hexLuminance('#FFFFFF')).assertTrue();
    });

    it('resolves preset themes and falls back for unknown ids', 0, () => {
      const night = resolvePalette(ReaderThemeId.Night, '#FFFFFF');
      expect(night.isDark).assertTrue();
      expect(findThemePreset('no-such-theme') === null).assertTrue();
      // 未知 id 走默认羊皮纸，而不是自定义色
      const fallback = resolvePalette('no-such-theme', '#101010');
      expect(fallback.isDark).assertFalse();
    });

    it('round-trips hsv and hex within rounding tolerance', 0, () => {
      const hex = hsvToHex(40, 0.06, 0.96);
      const hsv = hexToHsv(hex);
      expect(Math.abs(hsv.v - 0.96) < 0.02).assertTrue();
      expect(Math.abs(hsv.s - 0.06) < 0.02).assertTrue();
      // 灰阶的色相无意义，只要求饱和度归零
      expect(hexToHsv('#808080').s < 0.01).assertTrue();
    });

    it('prefixes alpha without corrupting the rgb body', 0, () => {
      expect(ReaderPalette.withAlpha('#F5F2EA', 0xcc)).assertEqual('#CCF5F2EA');
      // 传入已带 alpha 的值时先剥离再套，不叠加
      expect(ReaderPalette.withAlpha('#CCF5F2EA', 0x66)).assertEqual('#66F5F2EA');
    });
  });

  describe('TextReadingSettings normalization', () => {
    it('clamps font size and line height into range', 0, () => {
      expect(TextReadingSettings.normalizeFontSize(2)).assertEqual(TextReadingSettings.FONT_SIZE_MIN);
      expect(TextReadingSettings.normalizeFontSize(999)).assertEqual(TextReadingSettings.FONT_SIZE_MAX);
      expect(TextReadingSettings.normalizeLineHeight(0.1)).assertEqual(TextReadingSettings.LINE_HEIGHT_MIN);
      expect(TextReadingSettings.normalizeLineHeight(99)).assertEqual(TextReadingSettings.LINE_HEIGHT_MAX);
    });

    it('clamps overlay alpha and keeps two decimals', 0, () => {
      expect(TextReadingSettings.normalizeOverlay(-1)).assertEqual(TextReadingSettings.OVERLAY_MIN);
      expect(TextReadingSettings.normalizeOverlay(5)).assertEqual(TextReadingSettings.OVERLAY_MAX);
      expect(TextReadingSettings.normalizeOverlay(0.3333)).assertEqual(0.33);
    });

    it('rejects unknown patterns and theme ids', 0, () => {
      expect(TextReadingSettings.normalizePattern('bogus')).assertEqual(ReaderPattern.None);
      expect(TextReadingSettings.normalizePattern(ReaderPattern.Cloth)).assertEqual(ReaderPattern.Cloth);
      expect(TextReadingSettings.normalizeThemeId('bogus')).assertEqual(TextReadingSettings.THEME_DEFAULT);
      expect(TextReadingSettings.normalizeThemeId(ReaderThemeId.Custom)).assertEqual(ReaderThemeId.Custom);
    });

    it('drops image pattern when no image path survived', 0, () => {
      // 声明了图片图案但路径为空 → 退回无图案，避免画出空白层
      const orphan = TextReadingSettings.ofAll(18, 1.9, ReaderThemeId.Parchment,
        '#F5F2EA', ReaderPattern.Image, '', 0.35);
      expect(orphan.pattern).assertEqual(ReaderPattern.None);
      // 有路径时保留
      const withImage = TextReadingSettings.ofAll(18, 1.9, ReaderThemeId.Parchment,
        '#F5F2EA', ReaderPattern.Image, '/data/bg.jpg', 0.35);
      expect(withImage.pattern).assertEqual(ReaderPattern.Image);
    });
  });
}
