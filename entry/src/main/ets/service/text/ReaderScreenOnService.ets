import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { TextReadingSettings } from '../../model/TextReading';

/** 阅读期间保持亮屏；计时结束交还系统灭屏策略，离开页面/退后台立即释放。 */
export class ReaderScreenOnService {
  private mainWindow: window.Window | null = null;
  private minutes: number = 0;
  private visible: boolean = false;
  private foreground: boolean = true;
  private timer: number = -1;
  private serial: number = 0;
  private keepOn: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  private readonly windowListener = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) {
      this.foreground = false;
      this.release();
    } else if (event === window.WindowEventType.WINDOW_SHOWN) {
      this.foreground = true;
      this.touch();
    }
  };

  async init(context: common.Context): Promise<void> {
    const ticket = ++this.serial;
    const win = await window.getLastWindow(context);
    if (ticket !== this.serial) return;
    this.mainWindow = win;
    win.on('windowEvent', this.windowListener);
    this.touch();
  }

  configure(minutes: number): void {
    this.minutes = TextReadingSettings.normalizeScreenOnMinutes(minutes);
    this.touch();
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    if (visible) this.touch();
    else this.release();
  }

  touch(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    const active = this.visible && this.foreground && this.minutes !== 0;
    this.apply(active);
    if (active && this.minutes > 0) {
      this.timer = setTimeout((): void => {
        this.timer = -1;
        this.apply(false);
      }, this.minutes * 60000);
    }
  }

  private apply(enabled: boolean): void {
    const win = this.mainWindow;
    if (win === null || this.keepOn === enabled) return;
    this.keepOn = enabled;
    this.queue = this.queue.then((): Promise<void> => win.setWindowKeepScreenOn(enabled))
      .catch((): void => { this.keepOn = false; });
  }

  private release(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    this.apply(false);
  }

  dispose(): void {
    this.serial++;
    this.visible = false;
    this.release();
    this.mainWindow?.off('windowEvent', this.windowListener);
    this.mainWindow = null;
  }
}
