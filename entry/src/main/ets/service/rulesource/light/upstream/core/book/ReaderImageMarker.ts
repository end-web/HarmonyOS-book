export class ReaderImageMarkerInfo {
  source: string = '';
  width: number = 0;
  height: number = 0;
}

export class ReaderImageMarker {
  static readonly PREFIX: string = '[[LEGADO_EPUB_IMAGE:';
  static readonly SUFFIX: string = ']]';
  // encodeURIComponent 会转义 "|"，因此它可以无歧义地分隔来源与可选的原始尺寸。
  private static readonly SIZE_SEPARATOR: string = '|';

  static create(source: string, width: number = 0, height: number = 0): string {
    const value = (source || '').trim();
    if (!value) return '';
    const safeWidth = Math.round(width);
    const safeHeight = Math.round(height);
    const size = safeWidth > 0 && safeHeight > 0 ?
      `${ReaderImageMarker.SIZE_SEPARATOR}${safeWidth}x${safeHeight}` : '';
    return `${ReaderImageMarker.PREFIX}${encodeURIComponent(value)}${size}${ReaderImageMarker.SUFFIX}`;
  }

  static isMarker(value: string): boolean {
    const text = (value || '').trim();
    return text.startsWith(ReaderImageMarker.PREFIX) && text.endsWith(ReaderImageMarker.SUFFIX);
  }

  static parse(value: string): ReaderImageMarkerInfo {
    const info = new ReaderImageMarkerInfo();
    const text = (value || '').trim();
    if (!ReaderImageMarker.isMarker(text)) return info;
    let payload = text.substring(ReaderImageMarker.PREFIX.length, text.length - ReaderImageMarker.SUFFIX.length);
    const separator = payload.lastIndexOf(ReaderImageMarker.SIZE_SEPARATOR);
    if (separator >= 0) {
      const size = /^(\d{1,6})x(\d{1,6})$/.exec(payload.substring(separator + 1));
      if (size) {
        info.width = parseInt(size[1], 10);
        info.height = parseInt(size[2], 10);
        payload = payload.substring(0, separator);
      }
    }
    try {
      info.source = decodeURIComponent(payload);
    } catch (_) {
      info.source = payload;
    }
    return info;
  }
}
