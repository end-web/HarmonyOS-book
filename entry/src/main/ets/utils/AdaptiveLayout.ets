/**
 * 手机窗口统一断点。自由多窗只改变窗口尺寸，页面无需感知具体窗口模式。
 */
export class AdaptiveLayout {
  private static readonly COMPACT_WIDTH: number = 360;
  private static readonly COMPACT_HEIGHT: number = 760;
  /** 播放页除封面外的固定垂直占用：标题最多两行时的安全预算。 */
  private static readonly PLAYER_FIXED_HEIGHT: number = 438;
  private static readonly PLAYER_MIN_COVER: number = 136;

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
    // 紧凑窗口直接贴合系统安全区，把额外空间留给底部功能栏与播控区之间的间隔。
    return AdaptiveLayout.isCompact(width, height) ? 0 : 24;
  }

  static playerCoverSize(width: number, height: number): number {
    const horizontalSpace = AdaptiveLayout.horizontalPadding(width, height) * 2;
    const availableWidth = Math.max(152, width - horizontalSpace);
    // 优先用高度剩余空间收缩封面，确保两行标题、进度条和底部播控同屏。
    const heightBound = Math.max(
      AdaptiveLayout.PLAYER_MIN_COVER,
      Math.min(260, height - AdaptiveLayout.PLAYER_FIXED_HEIGHT)
    );
    return Math.min(availableWidth, heightBound);
  }

  static playerNeedsScroll(height: number): boolean {
    return height > 0 && height < AdaptiveLayout.PLAYER_FIXED_HEIGHT + AdaptiveLayout.PLAYER_MIN_COVER;
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
