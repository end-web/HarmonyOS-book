/** 章节恢复位置策略，所有时间参数均为毫秒。 */
export class ChapterProgressPolicy {
  private static readonly START_TOLERANCE_MS: number = 5000;
  private static readonly END_TOLERANCE_MS: number = 10000;

  /**
   * 仅恢复有效播放区间内的中段进度：
   * - 片头内或刚开始播放，回到片头结束点；
   * - 距离有效片尾不足 10 秒，视为已完成，也回到片头结束点；
   * - 其余位置恢复到保存点。
   */
  static resolveResumePosition(savedPositionMs: number, durationMs: number,
    skipIntroMs: number, skipOutroMs: number): number {
    const introEndMs = Math.max(0, skipIntroMs);
    const savedMs = Math.max(0, savedPositionMs);
    if (savedMs <= introEndMs + ChapterProgressPolicy.START_TOLERANCE_MS) {
      return introEndMs;
    }

    const safeDurationMs = Math.max(0, durationMs);
    if (safeDurationMs <= 0) {
      return savedMs;
    }
    const effectiveEndMs = Math.max(introEndMs, safeDurationMs - Math.max(0, skipOutroMs));
    if (savedMs >= effectiveEndMs - ChapterProgressPolicy.END_TOLERANCE_MS) {
      return introEndMs;
    }
    return Math.min(savedMs, effectiveEndMs);
  }
}
