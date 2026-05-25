import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Brightness';

/**
 * 窗口级亮度调节，免「修改系统设置」权限
 * 仅作用于当前窗口，离开页面应调 reset() 还原系统亮度
 */
export class BrightnessUtil {
  private static current: number = -1;

  static async setWindowBrightness(value: number): Promise<void> {
    const v = Math.max(0, Math.min(1, value));
    try {
      const win = await window.getLastWindow(getContext());
      await win.setWindowBrightness(v);
      BrightnessUtil.current = v;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `setWindowBrightness failed: ${err.code} ${err.message}`);
    }
  }

  static getCurrent(): number {
    return BrightnessUtil.current;
  }

  static async reset(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext());
      await win.setWindowBrightness(-1);
      BrightnessUtil.current = -1;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `reset failed: ${err.code} ${err.message}`);
    }
  }
}
