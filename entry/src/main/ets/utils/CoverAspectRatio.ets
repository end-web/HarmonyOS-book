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

  static get(url: string): number {
    return CoverAspectRatio.ratios.get(url) ?? 1;
  }

  static fittedWidth(ratio: number, maxWidth: number, maxHeight: number): number {
    return Math.min(maxWidth, maxHeight * ratio);
  }
}
