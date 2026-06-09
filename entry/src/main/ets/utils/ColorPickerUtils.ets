import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { fileIo } from '@kit.CoreFileKit';

export interface RgbColor {
  r: number;
  g: number;
  b: number;
}

export interface BlurColor {
  rgb: RgbColor;
  rgba: string; // 'rgba(r,g,b,0)' 格式，用于 backgroundEffect.color
}

export class ColorPickerUtils {
  private static cache: Map<string, RgbColor> = new Map();

  static toHex(c: RgbColor, alpha?: string): string {
    const r = c.r.toString(16).padStart(2, '0');
    const g = c.g.toString(16).padStart(2, '0');
    const b = c.b.toString(16).padStart(2, '0');
    const a = alpha ? alpha : '';
    return '#' + a + r + g + b;
  }

  static darken(c: RgbColor, ratio: number): RgbColor {
    const k = Math.max(0, Math.min(1, 1 - ratio));
    return { r: Math.round(c.r * k), g: Math.round(c.g * k), b: Math.round(c.b * k) };
  }

  /** 生成 backgroundEffect.color 所需的 rgba 字符串（alpha=0 让系统只取色不叠实色） */
  static toBlurColor(c: RgbColor): string {
    return `rgba(${c.r},${c.g},${c.b},0)`;
  }

  /** 同步读取已缓存的封面色（http URL / rawfile path / 沙箱绝对路径）。命中时可避免首帧默认色闪烁。 */
  static getCached(cover: string): RgbColor | null {
    if (!cover) return null;
    if (cover.startsWith('http')) {
      return ColorPickerUtils.cache.get(cover) || null;
    }
    if (cover.startsWith('/')) {
      return ColorPickerUtils.cache.get('file:' + cover) || null;
    }
    return ColorPickerUtils.cache.get('raw:' + cover) || null;
  }

  static async pickFromUrl(url: string): Promise<RgbColor | null> {
    if (!url) return null;
    const cached = ColorPickerUtils.cache.get(url);
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
      const picker = await effectKit.createColorPicker(pixelMap);
      const color = picker.getMainColorSync();
      const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
      ColorPickerUtils.cache.set(url, rgb);
      pixelMap.release();
      source.release();
      return rgb;
    } catch (e) {
      console.error('[ColorPicker] pickFromUrl error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickFromRawfile(context: Context, path: string): Promise<RgbColor | null> {
    const key = 'raw:' + path;
    const cached = ColorPickerUtils.cache.get(key);
    if (cached) {
      return cached;
    }
    try {
      const buf = await context.resourceManager.getRawFileContent(path);
      const source = image.createImageSource(buf.buffer.slice(0));
      const pixelMap = await source.createPixelMap();
      const picker = await effectKit.createColorPicker(pixelMap);
      const color = picker.getMainColorSync();
      const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
      ColorPickerUtils.cache.set(key, rgb);
      pixelMap.release();
      source.release();
      return rgb;
    } catch (e) {
      console.error('[ColorPicker] pickFromRawfile error: ' + JSON.stringify(e));
      return null;
    }
  }

  static async pickFromFile(path: string): Promise<RgbColor | null> {
    if (!path) return null;
    const key = 'file:' + path;
    const cached = ColorPickerUtils.cache.get(key);
    if (cached) return cached;
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      const picker = await effectKit.createColorPicker(pixelMap);
      const color = picker.getMainColorSync();
      const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
      ColorPickerUtils.cache.set(key, rgb);
      pixelMap.release();
      source.release();
      return rgb;
    } catch (e) {
      console.error('[ColorPicker] pickFromFile error: ' + JSON.stringify(e));
      return null;
    } finally {
      if (file) {
        try { fileIo.closeSync(file); } catch (_e) { /* ignore */ }
      }
    }
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
