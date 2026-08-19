/**
 * 手机窗口统一断点。自由多窗只改变窗口尺寸，页面无需感知具体窗口模式。
 */
export class AdaptiveLayout {
  private static readonly COMPACT_WIDTH: number = 360;
  private static readonly COMPACT_HEIGHT: number = 760;

  static isCompact(width: number, height: number): boolean {
    if (width <= 0 || height <= 0) return false;
    return width < AdaptiveLayout.COMPACT_WIDTH || height < AdaptiveLayout.COMPACT_HEIGHT;
  }

  static horizontalPadding(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 16 : 24;
  }

  static sectionSpacing(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 16 : 24;
  }

  static playerTopSpacing(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 8 : 12;
  }

  static playerBottomSpacing(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 12 : 24;
  }

  static playerCoverSize(width: number, height: number): number {
    const horizontalSpace = AdaptiveLayout.horizontalPadding(width, height) * 2;
    const availableWidth = Math.max(152, width - horizontalSpace);
    const heightBound = Math.max(152, Math.min(260, height * 0.34));
    return Math.min(availableWidth, heightBound);
  }

  static detailHeroHeight(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 216 : 230;
  }

  static detailCoverWidth(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 84 : 100;
  }

  static detailCoverHeight(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 109 : 130;
  }
}
