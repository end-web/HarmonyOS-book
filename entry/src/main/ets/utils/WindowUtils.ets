import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';

/**
 * 沉浸式 + 安全区域工具
 * 全屏布局 + 透明系统栏，业务页面用 expandSafeArea 自行延伸
 */
export class WindowUtils {
  private static topPx: number = 0;
  private static bottomPx: number = 0;
  private static density: number = 3.25;
  private static mainWindow: window.Window | null = null;

  static async setupImmersive(stage: window.WindowStage): Promise<void> {
    const win = await stage.getMainWindow();
    WindowUtils.mainWindow = win;
    await win.setWindowLayoutFullScreen(true);
    await win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: '#FF000000',
      navigationBarContentColor: '#FF000000'
    });
    WindowUtils.density = display.getDefaultDisplaySync().densityPixels;
    const topArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const bottomArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    WindowUtils.topPx = topArea.topRect.height;
    WindowUtils.bottomPx = bottomArea.bottomRect.height;
  }

  static async setStatusBarLight(isLight: boolean): Promise<void> {
    if (!WindowUtils.mainWindow) return;
    await WindowUtils.mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: isLight ? '#FFFFFFFF' : '#FF000000',
      navigationBarContentColor: isLight ? '#FFFFFFFF' : '#FF000000'
    });
  }

  static getStatusBarHeightVp(): number {
    return WindowUtils.topPx / WindowUtils.density;
  }

  static getBottomSafeVp(): number {
    return WindowUtils.bottomPx / WindowUtils.density;
  }
}
