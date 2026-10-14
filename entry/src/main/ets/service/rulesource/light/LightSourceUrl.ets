import { url } from '@kit.ArkTS';
export class LightSourceUrl {
  static resolveUrl(base: string, value: string): string {
    if (!value.trim()) return '';
    try { return new url.URL(value, base).href; } catch (_error) { return ''; }
  }
  static origin(value: string): string {
    try { return new url.URL(value).origin; } catch (_error) { return ''; }
  }
}
