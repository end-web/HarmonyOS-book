import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';

export interface RgbColor {
  r: number;
  g: number;
  b: number;
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

  static async pickFromUrl(url: string): Promise<RgbColor | null> {
    if (!url) return null;
    const cached = ColorPickerUtils.cache.get(url);
    if (cached) {
      console.info('[ColorPicker] cache hit for ' + url);
      return cached;
    }
    console.info('[ColorPicker] pickFromUrl start: ' + url);
    try {
      const buf = await ColorPickerUtils.downloadImage(url);
      if (!buf) {
        console.error('[ColorPicker] downloadImage returned null');
        return null;
      }
      console.info('[ColorPicker] downloaded ' + buf.byteLength + ' bytes');
      const source = image.createImageSource(buf);
      const pixelMap = await source.createPixelMap();
      console.info('[ColorPicker] created pixelMap');
      const picker = await effectKit.createColorPicker(pixelMap);
      console.info('[ColorPicker] created picker');
      const color = picker.getMainColorSync();
      const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
      console.info('[ColorPicker] extracted color: r=' + rgb.r + ', g=' + rgb.g + ', b=' + rgb.b);
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
    console.info('[ColorPicker] pickFromRawfile start: ' + path);
    const cached = ColorPickerUtils.cache.get(key);
    if (cached) {
      console.info('[ColorPicker] cache hit for ' + key);
      return cached;
    }
    try {
      console.info('[ColorPicker] loading rawfile: ' + path);
      const buf = await context.resourceManager.getRawFileContent(path);
      console.info('[ColorPicker] rawfile loaded, size=' + buf.byteLength);
      const source = image.createImageSource(buf.buffer.slice(0));
      console.info('[ColorPicker] image source created');
      const pixelMap = await source.createPixelMap();
      console.info('[ColorPicker] pixelMap created');
      const picker = await effectKit.createColorPicker(pixelMap);
      console.info('[ColorPicker] color picker created');
      const color = picker.getMainColorSync();
      const rgb: RgbColor = { r: color.red, g: color.green, b: color.blue };
      console.info('[ColorPicker] extracted color: r=' + rgb.r + ', g=' + rgb.g + ', b=' + rgb.b);
      ColorPickerUtils.cache.set(key, rgb);
      pixelMap.release();
      source.release();
      return rgb;
    } catch (e) {
      console.error('[ColorPicker] pickFromRawfile error: ' + JSON.stringify(e));
      return null;
    }
  }

  private static async downloadImage(url: string): Promise<ArrayBuffer | null> {
    console.info('[ColorPicker] downloadImage start: ' + url);
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      console.info('[ColorPicker] downloadImage response code: ' + resp.responseCode);
      if (resp.responseCode !== 200) {
        console.error('[ColorPicker] downloadImage failed with code ' + resp.responseCode);
        return null;
      }
      const data = resp.result;
      if (data instanceof ArrayBuffer) {
        console.info('[ColorPicker] downloadImage success, size=' + data.byteLength);
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
