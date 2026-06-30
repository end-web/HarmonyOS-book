import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { fileIo } from '@kit.CoreFileKit';

export interface RgbColor {
  r: number;
  g: number;
  b: number;
}

export interface CoverColorPalette {
  main: RgbColor;
  top: RgbColor;
  bottom: RgbColor;
  left: RgbColor;
  right: RgbColor;
  center: RgbColor;
}

export interface CoverAmbientTheme {
  main: string;
  top: string;
  bottom: string;
  left: string;
  right: string;
  center: string;
  dark: string;
}

export interface BlurColor {
  rgb: RgbColor;
  rgba: string; // 'rgba(r,g,b,0)' 格式，用于 backgroundEffect.color
}

export class ColorPickerUtils {
  private static cache: Map<string, RgbColor> = new Map();
  private static paletteCache: Map<string, CoverColorPalette> = new Map();

  private static readonly REGION_TOP: Array<number> = [0, 0, 1, 0.46];
  private static readonly REGION_BOTTOM: Array<number> = [0, 0.54, 1, 1];
  private static readonly REGION_LEFT: Array<number> = [0, 0, 0.46, 1];
  private static readonly REGION_RIGHT: Array<number> = [0.54, 0, 1, 1];
  private static readonly REGION_CENTER: Array<number> = [0.22, 0.18, 0.78, 0.82];

  static toHex(c: RgbColor, alpha?: string): string {
    const r = c.r.toString(16).padStart(2, '0');
    const g = c.g.toString(16).padStart(2, '0');
    const b = c.b.toString(16).padStart(2, '0');
    const a = alpha ? alpha : '';
    return '#' + a + r + g + b;
  }

  static withAlpha(hex: string, alpha: string): string {
    if (!hex || !hex.startsWith('#')) return hex;
    if (hex.length === 7) {
      return '#' + alpha + hex.substring(1);
    }
    if (hex.length === 9) {
      return '#' + alpha + hex.substring(3);
    }
    return hex;
  }

  static darken(c: RgbColor, ratio: number): RgbColor {
    const k = Math.max(0, Math.min(1, 1 - ratio));
    return { r: Math.round(c.r * k), g: Math.round(c.g * k), b: Math.round(c.b * k) };
  }

  static blend(a: RgbColor, b: RgbColor, ratio: number): RgbColor {
    const k = Math.max(0, Math.min(1, ratio));
    return {
      r: Math.round(a.r * (1 - k) + b.r * k),
      g: Math.round(a.g * (1 - k) + b.g * k),
      b: Math.round(a.b * (1 - k) + b.b * k)
    };
  }

  static toAmbientTheme(palette: CoverColorPalette): CoverAmbientTheme {
    const main = ColorPickerUtils.normalizeAmbientColor(palette.main);
    const top = ColorPickerUtils.normalizeAmbientColor(palette.top);
    const bottom = ColorPickerUtils.normalizeAmbientColor(palette.bottom);
    const left = ColorPickerUtils.normalizeAmbientColor(palette.left);
    const right = ColorPickerUtils.normalizeAmbientColor(palette.right);
    const center = ColorPickerUtils.normalizeAmbientColor(palette.center);
    const darkBase = ColorPickerUtils.blend(bottom, main, 0.35);
    return {
      main: ColorPickerUtils.toHex(main),
      top: ColorPickerUtils.toHex(top),
      bottom: ColorPickerUtils.toHex(bottom),
      left: ColorPickerUtils.toHex(left),
      right: ColorPickerUtils.toHex(right),
      center: ColorPickerUtils.toHex(center),
      dark: ColorPickerUtils.toHex(ColorPickerUtils.darken(darkBase, 0.58))
    };
  }

  /** 生成 backgroundEffect.color 所需的 rgba 字符串（alpha=0 让系统只取色不叠实色） */
  static toBlurColor(c: RgbColor): string {
    return `rgba(${c.r},${c.g},${c.b},0)`;
  }

  /** 同步读取已缓存的封面色（http URL / rawfile path / 沙箱绝对路径）。命中时可避免首帧默认色闪烁。 */
  static getCached(cover: string): RgbColor | null {
    if (!cover) return null;
    const key = ColorPickerUtils.cacheKey(cover);
    const palette = ColorPickerUtils.paletteCache.get(key);
    if (palette) return palette.main;
    return ColorPickerUtils.cache.get(key) || null;
  }

  static getPaletteCached(cover: string): CoverColorPalette | null {
    if (!cover) return null;
    const key = ColorPickerUtils.cacheKey(cover);
    return ColorPickerUtils.paletteCache.get(key) || null;
  }

  static async pickPaletteFromUrl(url: string): Promise<CoverColorPalette | null> {
    if (!url) return null;
    const key = ColorPickerUtils.cacheKey(url);
    const cached = ColorPickerUtils.paletteCache.get(key);
    if (cached) return cached;
    try {
      const buf = await ColorPickerUtils.downloadImage(url);
      if (!buf) {
        console.error('[ColorPicker] downloadImage returned null');
        return null;
      }
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      try {
        const palette = await ColorPickerUtils.pickPaletteFromPixelMap(pixelMap);
        ColorPickerUtils.savePalette(key, palette);
        return palette;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickPaletteFromUrl error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickPaletteFromRawfile(context: Context, path: string): Promise<CoverColorPalette | null> {
    const key = ColorPickerUtils.cacheKey(path);
    const cached = ColorPickerUtils.paletteCache.get(key);
    if (cached) return cached;
    try {
      const buf = await context.resourceManager.getRawFileContent(path);
      const source = image.createImageSource(buf.buffer.slice(0));
      const pixelMap = await source.createPixelMap();
      try {
        const palette = await ColorPickerUtils.pickPaletteFromPixelMap(pixelMap);
        ColorPickerUtils.savePalette(key, palette);
        return palette;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickPaletteFromRawfile error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickPaletteFromFile(path: string): Promise<CoverColorPalette | null> {
    if (!path) return null;
    const normalizedPath = path.startsWith('file://') ? path.substring('file://'.length) : path;
    const key = ColorPickerUtils.cacheKey(normalizedPath);
    const cached = ColorPickerUtils.paletteCache.get(key);
    if (cached) return cached;
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(normalizedPath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      try {
        const palette = await ColorPickerUtils.pickPaletteFromPixelMap(pixelMap);
        ColorPickerUtils.savePalette(key, palette);
        return palette;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickPaletteFromFile error: ' + JSON.stringify(e));
      return null;
    } finally {
      if (file) {
        try { fileIo.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  static async pickFromUrl(url: string): Promise<RgbColor | null> {
    if (!url) return null;
    const key = ColorPickerUtils.cacheKey(url);
    const cached = ColorPickerUtils.getCached(url);
    if (cached) {
      return cached;
    }
    try {
      const buf = await ColorPickerUtils.downloadImage(url);
      if (!buf) {
        console.error('[ColorPicker] downloadImage returned null');
        return null;
      }
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      try {
        const picker = await effectKit.createColorPicker(pixelMap);
        const color = picker.getMainColorSync();
        const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
        ColorPickerUtils.cache.set(key, rgb);
        return rgb;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickFromUrl error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickFromRawfile(context: Context, path: string): Promise<RgbColor | null> {
    const key = ColorPickerUtils.cacheKey(path);
    const cached = ColorPickerUtils.getCached(path);
    if (cached) {
      return cached;
    }
    try {
      const buf = await context.resourceManager.getRawFileContent(path);
      const source = image.createImageSource(buf.buffer.slice(0));
      const pixelMap = await source.createPixelMap();
      try {
        const picker = await effectKit.createColorPicker(pixelMap);
        const color = picker.getMainColorSync();
        const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
        ColorPickerUtils.cache.set(key, rgb);
        return rgb;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickFromRawfile error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickFromFile(path: string): Promise<RgbColor | null> {
    if (!path) return null;
    const normalizedPath = path.startsWith('file://') ? path.substring('file://'.length) : path;
    const key = ColorPickerUtils.cacheKey(normalizedPath);
    const cached = ColorPickerUtils.getCached(normalizedPath);
    if (cached) return cached;
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(normalizedPath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      try {
        const picker = await effectKit.createColorPicker(pixelMap);
        const color = picker.getMainColorSync();
        const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
        ColorPickerUtils.cache.set(key, rgb);
        return rgb;
      } finally {
        pixelMap.release();
        source.release();
      }
    } catch (e) {
      console.error('[ColorPicker] pickFromFile error: ' + JSON.stringify(e));
      return null;
    } finally {
      if (file) {
        try { fileIo.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  private static cacheKey(cover: string): string {
    if (cover.startsWith('http')) return cover;
    if (cover.startsWith('file://')) return 'file:' + cover.substring('file://'.length);
    if (cover.startsWith('/')) return 'file:' + cover;
    return 'raw:' + cover;
  }

  private static savePalette(key: string, palette: CoverColorPalette): void {
    ColorPickerUtils.paletteCache.set(key, palette);
    ColorPickerUtils.cache.set(key, palette.main);
  }

  private static async pickPaletteFromPixelMap(pixelMap: image.PixelMap): Promise<CoverColorPalette> {
    const main = await ColorPickerUtils.pickPixelMapColor(pixelMap);
    return {
      main: main,
      top: await ColorPickerUtils.pickPixelMapColor(pixelMap, ColorPickerUtils.REGION_TOP, main),
      bottom: await ColorPickerUtils.pickPixelMapColor(pixelMap, ColorPickerUtils.REGION_BOTTOM, main),
      left: await ColorPickerUtils.pickPixelMapColor(pixelMap, ColorPickerUtils.REGION_LEFT, main),
      right: await ColorPickerUtils.pickPixelMapColor(pixelMap, ColorPickerUtils.REGION_RIGHT, main),
      center: await ColorPickerUtils.pickPixelMapColor(pixelMap, ColorPickerUtils.REGION_CENTER, main)
    };
  }

  private static async pickPixelMapColor(pixelMap: image.PixelMap, region?: Array<number>, fallback?: RgbColor): Promise<RgbColor> {
    try {
      const picker = region
        ? await effectKit.createColorPicker(pixelMap, region)
        : await effectKit.createColorPicker(pixelMap);
      const color = picker.getMainColorSync();
      return ColorPickerUtils.sanitizeColor({ r: color.red, g: color.green, b: color.blue }, fallback);
    } catch (_e) {
      if (fallback) return fallback;
      throw new Error('pick pixel map color failed');
    }
  }

  private static sanitizeColor(c: RgbColor, fallback?: RgbColor): RgbColor {
    if (!ColorPickerUtils.isFiniteNumber(c.r) || !ColorPickerUtils.isFiniteNumber(c.g)
      || !ColorPickerUtils.isFiniteNumber(c.b)) {
      return fallback ?? { r: 42, g: 42, b: 42 };
    }
    return {
      r: Math.max(0, Math.min(255, Math.round(c.r))),
      g: Math.max(0, Math.min(255, Math.round(c.g))),
      b: Math.max(0, Math.min(255, Math.round(c.b)))
    };
  }

  private static isFiniteNumber(v: number): boolean {
    return !isNaN(v) && v !== Infinity && v !== -Infinity;
  }

  private static luminance(c: RgbColor): number {
    return c.r * 0.299 + c.g * 0.587 + c.b * 0.114;
  }

  private static normalizeAmbientColor(c: RgbColor): RgbColor {
    let normalized = ColorPickerUtils.sanitizeColor(c);
    const lum = ColorPickerUtils.luminance(normalized);
    if (lum > 178) {
      normalized = ColorPickerUtils.blend(normalized, { r: 36, g: 36, b: 40 }, 0.34);
    } else if (lum < 38) {
      normalized = ColorPickerUtils.blend(normalized, { r: 88, g: 88, b: 94 }, 0.36);
    } else {
      normalized = ColorPickerUtils.blend(normalized, { r: 20, g: 20, b: 24 }, 0.12);
    }
    return normalized;
  }

  private static async downloadImage(url: string): Promise<ArrayBuffer | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (resp.responseCode !== 200) {
        console.error('[ColorPicker] downloadImage failed with code ' + resp.responseCode);
        return null;
      }
      const data = resp.result;
      if (data instanceof ArrayBuffer) {
        return data;
      }
      console.error('[ColorPicker] downloadImage result is not ArrayBuffer');
      return null;
    } catch (e) {
      console.error('[ColorPicker] downloadImage exception: ' + JSON.stringify(e));
      return null;
    } finally {
      req.destroy();
    }
  }
}
