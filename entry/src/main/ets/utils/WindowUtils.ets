import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 沉浸式 + 安全区域工具
 * 全屏布局 + 透明系统栏，业务页面用 expandSafeArea 自行延伸
 */
export class WindowUtils {
  private static topPx: number = 0;
  private static bottomPx: number = 0;
  private static density: number = 3.25;
  private static mainWindow: window.Window | null = null;
  private static safeAreaListeners: Array<(topVp: number, bottomVp: number) => void> = [];
  private static layoutRefreshTimerId: number = -1;
  private static settledRefreshTimerId: number = -1;
  private static readonly FALLBACK_BOTTOM_SAFE_VP: number = 24;
  /** 当前生效的深浅色模式（由 EntryAbility 的 config / onConfigurationUpdate 同步） */
  private static colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 最近一次页面请求的状态栏诉求：true=强制白字(深色背景页)，false=跟随系统 */
  private static forceLight: boolean = false;

  static async setupImmersive(stage: window.WindowStage, colorMode?: ConfigurationConstant.ColorMode): Promise<void> {
    const win = await stage.getMainWindow();
    const previousWindow = WindowUtils.mainWindow;
    if (previousWindow !== null) {
      try {
        previousWindow.off('avoidAreaChange', WindowUtils.handleAvoidAreaChange);
        previousWindow.off('windowSizeChange', WindowUtils.handleWindowSizeChange);
        previousWindow.off('windowStatusDidChange', WindowUtils.handleWindowStatusDidChange);
      } catch (_e) { /* ignore */ }
    }
    WindowUtils.cancelPendingRefreshes();
    WindowUtils.mainWindow = win;
    if (colorMode !== undefined) {
      WindowUtils.colorMode = colorMode;
    }
    await win.setWindowLayoutFullScreen(true);
    await win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000'
    });
    try {
      await win.setFloatNavigationAvoidAreaEnabled(true);
    } catch (_e) {
      // Keep the regular system/nav-indicator fallback on devices without float-navigation support.
    }
    await WindowUtils.applySystemBarContent();
    win.on('avoidAreaChange', WindowUtils.handleAvoidAreaChange);
    win.on('windowSizeChange', WindowUtils.handleWindowSizeChange);
    win.on('windowStatusDidChange', WindowUtils.handleWindowStatusDidChange);
    WindowUtils.refreshAvoidArea();
  }

  static addSafeAreaListener(listener: (topVp: number, bottomVp: number) => void): void {
    if (WindowUtils.safeAreaListeners.indexOf(listener) < 0) {
      WindowUtils.safeAreaListeners.push(listener);
    }
    listener(WindowUtils.getStatusBarHeightVp(), WindowUtils.getBottomSafeVp());
  }

  static removeSafeAreaListener(listener: (topVp: number, bottomVp: number) => void): void {
    const index = WindowUtils.safeAreaListeners.indexOf(listener);
    if (index >= 0) WindowUtils.safeAreaListeners.splice(index, 1);
  }

  static refreshAvoidArea(): void {
    const currentWindow = WindowUtils.mainWindow;
    if (currentWindow === null) return;
    WindowUtils.syncAvoidArea(currentWindow);
    WindowUtils.scheduleAvoidAreaRefresh();
  }

  /**
   * 设置状态栏/导航栏文字色。
   * @param isLight true 强制白字（用于封面/播放器等始终深色背景的页面）；
   *                false 跟随系统深浅色（浅色→黑字，深色→白字）。
   */
  static async setStatusBarLight(isLight: boolean): Promise<void> {
    WindowUtils.forceLight = isLight;
    await WindowUtils.applySystemBarContent();
  }

  /** 深浅色模式变更时调用（EntryAbility.onConfigurationUpdate），重新刷新当前状态栏字色 */
  static updateColorMode(colorMode: ConfigurationConstant.ColorMode): void {
    WindowUtils.colorMode = colorMode;
    WindowUtils.applySystemBarContent().catch(() => { /* ignore */ });
  }

  private static async applySystemBarContent(): Promise<void> {
    if (!WindowUtils.mainWindow) return;
    const isDark = WindowUtils.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    // 强制白字，或深色模式 → 白字；否则黑字
    const useWhite = WindowUtils.forceLight || isDark;
    const content = useWhite ? '#FFFFFFFF' : '#FF000000';
    await WindowUtils.mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: content,
      navigationBarContentColor: content
    });
  }

  static getStatusBarHeightVp(): number {
    return WindowUtils.topPx / WindowUtils.density;
  }

  static getBottomSafeVp(): number {
    const measuredVp = WindowUtils.bottomPx / WindowUtils.density;
    return Math.max(measuredVp, WindowUtils.FALLBACK_BOTTOM_SAFE_VP);
  }

  static pxToVp(valuePx: number): number {
    return valuePx / WindowUtils.density;
  }

  static vpToPx(valueVp: number): number {
    return valueVp * WindowUtils.density;
  }

  // 与 MainPage 中常量保持一致
  private static readonly FLOATING_TAB_HEIGHT: number = 60;
  private static readonly FLOATING_GAP: number = 12;
  private static readonly FLOATING_BOTTOM: number = 4;

  /**
   * TabContent 底部需要为浮动 Tab 栏让出的高度(vp)。
   * 计算公式: bottomSafe + FLOATING_BOTTOM + FLOATING_TAB_HEIGHT + FLOATING_GAP
   * 说明: FloatingTabBar 内部用 padding-bottom = bottomSafe 把自身抬到导航条之上,
   *       所以业务页留出的高度也要包含 bottomSafe,否则最后一行会被手势条遮住一截。
   */
  static getFloatingTabBottomVp(bottomSafeVp?: number): number {
    const safeBottom = bottomSafeVp !== undefined ? bottomSafeVp : WindowUtils.getBottomSafeVp();
    return safeBottom +
           WindowUtils.FLOATING_BOTTOM +
           WindowUtils.FLOATING_TAB_HEIGHT +
           WindowUtils.FLOATING_GAP;
  }

  private static handleAvoidAreaChange(_data: window.AvoidAreaOptions): void {
    WindowUtils.refreshAvoidArea();
  }

  private static handleWindowSizeChange(_size: window.Size): void {
    WindowUtils.refreshAvoidArea();
  }

  private static handleWindowStatusDidChange(_status: window.WindowStatusType): void {
    WindowUtils.refreshAvoidArea();
  }

  private static cancelPendingRefreshes(): void {
    if (WindowUtils.layoutRefreshTimerId !== -1) {
      clearTimeout(WindowUtils.layoutRefreshTimerId);
      WindowUtils.layoutRefreshTimerId = -1;
    }
    if (WindowUtils.settledRefreshTimerId !== -1) {
      clearTimeout(WindowUtils.settledRefreshTimerId);
      WindowUtils.settledRefreshTimerId = -1;
    }
  }

  private static scheduleAvoidAreaRefresh(): void {
    WindowUtils.cancelPendingRefreshes();
    WindowUtils.layoutRefreshTimerId = setTimeout((): void => {
      WindowUtils.layoutRefreshTimerId = -1;
      const currentWindow = WindowUtils.mainWindow;
      if (currentWindow !== null) WindowUtils.syncAvoidArea(currentWindow);
    }, 32);
    WindowUtils.settledRefreshTimerId = setTimeout((): void => {
      WindowUtils.settledRefreshTimerId = -1;
      const currentWindow = WindowUtils.mainWindow;
      if (currentWindow !== null) WindowUtils.syncAvoidArea(currentWindow);
    }, 240);
  }

  private static notifySafeAreaChange(): void {
    const topVp = WindowUtils.getStatusBarHeightVp();
    const bottomVp = WindowUtils.getBottomSafeVp();
    WindowUtils.safeAreaListeners.forEach((listener: (topVp: number, bottomVp: number) => void): void => {
      listener(topVp, bottomVp);
    });
  }

  private static readAvoidArea(win: window.Window, type: window.AvoidAreaType): window.AvoidArea | null {
    try {
      return win.getWindowAvoidArea(type);
    } catch (_e) {
      return null;
    }
  }

  private static updateDensity(win: window.Window): void {
    try {
      const densityInfo = win.getWindowDensityInfo();
      const windowDensity = densityInfo.customDensity > 0 ? densityInfo.customDensity : densityInfo.systemDensity;
      if (windowDensity > 0) {
        WindowUtils.density = windowDensity;
        return;
      }
    } catch (_e) { /* use display density */ }
    const displayDensity = display.getDefaultDisplaySync().densityPixels;
    if (displayDensity > 0) WindowUtils.density = displayDensity;
  }

  private static syncAvoidArea(win: window.Window): void {
    try {
      WindowUtils.updateDensity(win);
      const systemArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const floatNavigationArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_FLOAT_NAVIGATION);
      let hasBottomArea: boolean = false;
      let nextBottomPx: number = 0;
      if (systemArea !== null) {
        WindowUtils.topPx = systemArea.topRect.height;
        nextBottomPx = Math.max(nextBottomPx, systemArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (navigationArea !== null) {
        nextBottomPx = Math.max(nextBottomPx, navigationArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (floatNavigationArea !== null) {
        nextBottomPx = Math.max(nextBottomPx, floatNavigationArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (hasBottomArea) WindowUtils.bottomPx = nextBottomPx;
      WindowUtils.notifySafeAreaChange();
    } catch (_e) {
      // keep previous cached values
    }
  }
}
