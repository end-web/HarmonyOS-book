/** 仅用于图片尺寸未知时的加载占位，不限制真实封面的比例。 */
export const BOOK_COVER_ASPECT_RATIO: number = 0.75;

/** 只缓存图片元数据，不保存位图；让详情首帧沿用首页已加载封面的真实比例。 */
export class CoverAspectRatio {
  private static readonly ratios: Map<string, number> = new Map();
  private static readonly MAX_ENTRIES: number = 512;

  static remember(url: string, width: number, height: number): void {
    if (url.length === 0 || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    if (!CoverAspectRatio.ratios.has(url) && CoverAspectRatio.ratios.size >= CoverAspectRatio.MAX_ENTRIES) {
      const oldest = CoverAspectRatio.ratios.keys().next();
      if (!oldest.done) CoverAspectRatio.ratios.delete(oldest.value);
    }
    CoverAspectRatio.ratios.set(url, width / height);
  }

  static get(url: string, fallback: number = 1): number {
    return CoverAspectRatio.ratios.get(url) ?? fallback;
  }

  static fittedWidth(ratio: number, maxWidth: number, maxHeight: number): number {
    return Math.min(maxWidth, maxHeight * ratio);
  }
}
