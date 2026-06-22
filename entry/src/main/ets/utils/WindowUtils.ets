import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

/** 系统/App 深浅色变更事件。payload: { dark: boolean }。阅读页"跟随系统"主题据此实时重排 */
export const EVT_COLOR_MODE_CHANGED = 'app.system.colorModeChanged';

/**
 * 沉浸式 + 安全区域工具
 * 全屏布局 + 透明系统栏，业务页面用 expandSafeArea 自行延伸
 */
export class WindowUtils {
  private static topPx: number = 0;
  // 最近一次非零状态栏高度:阅读页隐藏状态栏后 topPx 会变 0,布局避让用此稳定值
  private static topPxStable: number = 0;
  private static bottomPx: number = 0;
  private static density: number = 3.25;
  private static mainWindow: window.Window | null = null;
  /** 当前生效的深浅色模式（由 EntryAbility 的 config / onConfigurationUpdate 同步） */
  private static colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 最近一次页面请求的状态栏诉求：true=强制白字(深色背景页)，false=跟随系统 */
  private static forceLight: boolean = false;

  static async setupImmersive(stage: window.WindowStage, colorMode?: ConfigurationConstant.ColorMode): Promise<void> {
    const win = await stage.getMainWindow();
    WindowUtils.mainWindow = win;
    if (colorMode !== undefined) {
      WindowUtils.colorMode = colorMode;
    }
    await win.setWindowLayoutFullScreen(true);
    await win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000'
    });
    await WindowUtils.applySystemBarContent();
    WindowUtils.syncAvoidArea(win);
    win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      try {
        if (!data || !data.area) return;
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          WindowUtils.topPx = data.area.topRect.height;
          if (WindowUtils.topPx > 0) WindowUtils.topPxStable = WindowUtils.topPx;
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          WindowUtils.bottomPx = data.area.bottomRect.height;
        }
      } catch (_e) { /* ignore */ }
    });
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

  /**
   * 阅读页沉浸式系统栏显隐。
   * 全屏阅读时隐藏状态栏和导航指示区；唤出悬浮菜单时再显示。
   */
  static async setStatusBarVisible(visible: boolean): Promise<void> {
    if (!WindowUtils.mainWindow) return;
    try {
      await WindowUtils.mainWindow.setSpecificSystemBarEnabled('status', visible);
      await WindowUtils.mainWindow.setSpecificSystemBarEnabled('navigationIndicator', visible);
      if (visible) await WindowUtils.applySystemBarContent();
    } catch (_e) { /* ignore：部分设备/模拟器不支持时不阻断阅读 */ }
  }

  /**
   * 设置阅读页屏幕亮度。
   * @param v [0,1] 覆盖屏幕亮度；-1 跟随系统（离开阅读页时复位用）。
   * 仅作用于本窗口，退出阅读页须复位为 -1，避免影响其他页面。
   */
  static async setReaderBrightness(v: number): Promise<void> {
    if (!WindowUtils.mainWindow) return;
    try {
      await WindowUtils.mainWindow.setWindowBrightness(v);
    } catch (_e) { /* ignore：窗口异常时静默,不阻断阅读 */ }
  }

  /** 深浅色模式变更时调用（EntryAbility.onConfigurationUpdate），重新刷新当前状态栏字色 */
  static updateColorMode(colorMode: ConfigurationConstant.ColorMode): void {
    const changed = WindowUtils.colorMode !== colorMode;
    WindowUtils.colorMode = colorMode;
    WindowUtils.applySystemBarContent().catch(() => { /* ignore */ });
    // 仅在实际变化时广播,避免 onConfigurationUpdate 的非深浅色变更误触发重排
    if (changed) {
      emitter.emit(EVT_COLOR_MODE_CHANGED, { data: { dark: WindowUtils.isDarkMode() } });
    }
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

  /** 当前是否深色模式(由 EntryAbility 同步的 colorMode 判定),供页面挑默认主题 */
  static isDarkMode(): boolean {
    return WindowUtils.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  static getStatusBarHeightVp(): number {
    return WindowUtils.topPx / WindowUtils.density;
  }

  /**
   * 稳定顶部安全高度(vp):返回最近一次非零状态栏高度。
   * 阅读页唤菜单瞬间先显示状态栏再布局,topPx 异步更新可能仍为 0,
   * 用此值避免悬浮顶栏与状态栏重叠。
   */
  static getTopSafeStableVp(): number {
    const px = WindowUtils.topPx > 0 ? WindowUtils.topPx : WindowUtils.topPxStable;
    return px / WindowUtils.density;
  }

  /** 别名:语义同 getStatusBarHeightVp,保留兼容历史调用 */
  static getTopSafeVp(): number {
    return WindowUtils.topPx / WindowUtils.density;
  }

  static getBottomSafeVp(): number {
    return WindowUtils.bottomPx / WindowUtils.density;
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
  static getFloatingTabBottomVp(): number {
    return WindowUtils.getBottomSafeVp() +
           WindowUtils.FLOATING_BOTTOM +
           WindowUtils.FLOATING_TAB_HEIGHT +
           WindowUtils.FLOATING_GAP;
  }

  private static syncAvoidArea(win: window.Window): void {
    try {
      WindowUtils.density = display.getDefaultDisplaySync().densityPixels;
      const topArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const bottomArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      WindowUtils.topPx = topArea.topRect.height;
      if (WindowUtils.topPx > 0) WindowUtils.topPxStable = WindowUtils.topPx;
      WindowUtils.bottomPx = bottomArea.bottomRect.height;
    } catch (_e) {
      // keep previous cached values
    }
  }
}
