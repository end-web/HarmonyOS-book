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

  // HdsTabs 悬浮 Tab 栏估算高度(BottomTabBarStyle 在 floating 模式下约 60vp)
  private static readonly FLOATING_TAB_BAR_HEIGHT: number = 60;
  // MainPage 中 barBottomMargin 与 bottomSafe 之间额外保留的间距,需与 MainPage 配置保持一致
  private static readonly FLOATING_TAB_BOTTOM_GAP: number = 8;

  /**
   * 悬浮 Tab 区域占用的底部高度(vp)
   * 用于 TabContent 内可滚动容器的 bottom padding,避免最后一项被悬浮 Tab 遮挡
   */
  static getFloatingTabBottomVp(): number {
    return WindowUtils.FLOATING_TAB_BAR_HEIGHT
      + WindowUtils.FLOATING_TAB_BOTTOM_GAP
      + WindowUtils.getBottomSafeVp()
      + 8;
  }
}
