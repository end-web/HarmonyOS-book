import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_ExtMedia';

/**
 * 监测系统里其他 App 的「视频/游戏/视频通话」音频流是否消失。
 *
 * 背景:抖音/B 站等视频应用抢焦点时,系统给我们下发 INTERRUPT_HINT_STOP,且
 * 视频结束后不会再下发 INTERRUPT_HINT_RESUME(华为官方焦点策略)。
 * 这个 watcher 用 AudioStreamManager.audioRendererChange 旁路监听,
 * 当观察到的外部 MEDIA 流从「有」变成「无」时,触发回调让 AudioService 续播。
 *
 * 只关心 MOVIE / GAME / VIDEO_COMMUNICATION 三类高优先级会强制打断 Music 的流。
 * MUSIC 不算 —— 别人在听音乐时不应该把人家抢回来。
 */
export class ExternalMediaWatcher {
  private streamMgr: audio.AudioStreamManager | null = null;
  private armed: boolean = false;
  private callback: (() => void) | null = null;
  private timeoutTimer: number = -1;
  private hadExternalMedia: boolean = false;
  private static readonly TIMEOUT_MS: number = 30_000;

  private listener: (arr: audio.AudioRendererChangeInfoArray) => void =
    (arr: audio.AudioRendererChangeInfoArray) => this.onChange(arr);

  /** arm 后,当外部 MEDIA 流从有变无时调一次 cb,然后自动 disarm */
  arm(cb: () => void): void {
    if (this.armed) {
      this.disarm();
    }
    try {
      if (!this.streamMgr) {
        this.streamMgr = audio.getAudioManager().getStreamManager();
      }
      this.streamMgr.on('audioRendererChange', this.listener);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'arm failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      return;
    }
    this.armed = true;
    this.callback = cb;
    this.hadExternalMedia = false;
    // 立即拍一次快照,把当前是否有外部 MEDIA 的状态记下来。
    // 如果 arm 时已经无外部 MEDIA(可能视频已经结束但还没到这儿),
    // 不立刻触发,等下一次 change 事件再判定 —— 否则空数组直接触发会误续播。
    try {
      const initial = this.streamMgr.getCurrentAudioRendererInfoArraySync();
      this.evaluate(initial);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'initial snapshot failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    this.timeoutTimer = setTimeout(() => {
      hilog.info(DOMAIN, TAG, 'arm timeout, give up');
      this.disarm();
    }, ExternalMediaWatcher.TIMEOUT_MS);
    hilog.info(DOMAIN, TAG, 'armed, hadExternalMedia=%{public}d',
      this.hadExternalMedia ? 1 : 0);
  }

  disarm(): void {
    if (!this.armed) return;
    this.armed = false;
    try {
      this.streamMgr?.off('audioRendererChange', this.listener);
    } catch (_e) { /* ignore */ }
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
    this.callback = null;
    this.hadExternalMedia = false;
    hilog.info(DOMAIN, TAG, 'disarmed');
  }

  isArmed(): boolean {
    return this.armed;
  }

  private isExternalMediaUsage(usage: audio.StreamUsage): boolean {
    return usage === audio.StreamUsage.STREAM_USAGE_MOVIE
        || usage === audio.StreamUsage.STREAM_USAGE_GAME
        || usage === audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION;
  }

  private onChange(arr: audio.AudioRendererChangeInfoArray): void {
    if (!this.armed) return;
    this.evaluate(arr);
  }

  private evaluate(arr: audio.AudioRendererChangeInfoArray): void {
    let externalMediaCount = 0;
    for (let i = 0; i < arr.length; i++) {
      const info = arr[i];
      if (this.isExternalMediaUsage(info.rendererInfo.usage)) {
        externalMediaCount++;
      }
    }
    if (externalMediaCount > 0) {
      this.hadExternalMedia = true;
      return;
    }
    if (this.hadExternalMedia) {
      hilog.info(DOMAIN, TAG, 'external media gone, fire callback');
      const cb = this.callback;
      this.disarm();
      if (cb) cb();
    }
  }
}
