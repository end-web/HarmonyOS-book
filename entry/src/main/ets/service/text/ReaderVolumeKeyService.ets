import { inputConsumer, KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 系统音量键消费与组件焦点无关；只在阅读正文可交互时订阅。 */
export class ReaderVolumeKeyService {
  private upRegistered: boolean = false;
  private downRegistered: boolean = false;
  private onTurn: (forward: boolean) => void = (): void => {};
  private readonly upHandler = (): void => { this.onTurn(false); };
  private readonly downHandler = (): void => { this.onTurn(true); };

  setEnabled(enabled: boolean, onTurn: (forward: boolean) => void): void {
    this.onTurn = onTurn;
    if (!enabled) {
      this.dispose();
      return;
    }
    if (this.upRegistered && this.downRegistered) return;
    try {
      // action=1 与 isRepeat=false 在 API 20 可用；按下一次翻一页，长按不连翻。
      if (!this.upRegistered) {
        inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_UP, action: 1, isRepeat: false }, this.upHandler);
        this.upRegistered = true;
      }
      if (!this.downRegistered) {
        inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_DOWN, action: 1, isRepeat: false }, this.downHandler);
        this.downRegistered = true;
      }
    } catch (error) {
      this.dispose();
      hilog.warn(0, 'ReaderVolumeKey', 'subscribe failed: %{public}s', String(error));
    }
  }

  dispose(): void {
    this.onTurn = (): void => {};
    try {
      if (this.upRegistered) {
        inputConsumer.off('keyPressed', this.upHandler);
        this.upRegistered = false;
      }
    } catch (error) {
      hilog.warn(0, 'ReaderVolumeKey', 'unsubscribe up failed: %{public}s', String(error));
    }
    try {
      if (this.downRegistered) {
        inputConsumer.off('keyPressed', this.downHandler);
        this.downRegistered = false;
      }
    } catch (error) {
      hilog.warn(0, 'ReaderVolumeKey', 'unsubscribe down failed: %{public}s', String(error));
    }
  }
}
