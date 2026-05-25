import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Fold';

const WIDE_BREAKPOINT_VP = 840;

export type FoldListener = (wide: boolean) => void;

/**
 * 折叠屏 / 平板宽屏识别
 * - wide=true：屏宽 > 840vp，按平板/展开态处理（字号上限 +20%）
 * - 设备无折叠能力时只走屏宽兜底，不会抛错
 */
export class FoldUtil {
  private static density: number = 3.25;
  private static wide: boolean = false;
  private static listeners: FoldListener[] = [];
  private static foldHooked: boolean = false;

  static init(): void {
    try {
      FoldUtil.density = display.getDefaultDisplaySync().densityPixels || 3.25;
    } catch (_e) {
      FoldUtil.density = 3.25;
    }
    FoldUtil.recompute();

    if (!FoldUtil.foldHooked) {
      try {
        if (display.isFoldable && display.isFoldable()) {
          display.on('foldStatusChange', (_status: display.FoldStatus) => {
            FoldUtil.recompute();
          });
        }
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, `foldStatusChange listen failed: ${err.code} ${err.message}`);
      }
      FoldUtil.foldHooked = true;
    }
  }

  private static recompute(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const widthVp = d.width / (d.densityPixels || FoldUtil.density);
      const next = widthVp > WIDE_BREAKPOINT_VP;
      if (next !== FoldUtil.wide) {
        FoldUtil.wide = next;
        FoldUtil.listeners.forEach((l) => l(next));
      }
    } catch (_e) {
      // 部分模拟器拿不到 display，保持原值
    }
  }

  static isWide(): boolean {
    FoldUtil.recompute();
    return FoldUtil.wide;
  }

  /** 字号放大因子：宽屏 1.2，常规 1.0 */
  static fontScale(): number {
    return FoldUtil.isWide() ? 1.2 : 1.0;
  }

  static onChange(l: FoldListener): void {
    if (!FoldUtil.listeners.includes(l)) {
      FoldUtil.listeners.push(l);
    }
  }

  static offChange(l: FoldListener): void {
    const i = FoldUtil.listeners.indexOf(l);
    if (i >= 0) FoldUtil.listeners.splice(i, 1);
  }
}
