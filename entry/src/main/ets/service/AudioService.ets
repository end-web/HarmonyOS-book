import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { Book, Chapter, AudioSource } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { PlayerState, PlayMode } from '../model/PlayerState';
import { PreferenceService, PlayProgress } from './PreferenceService';
import { SourceDataService } from './SourceDataService';
import { BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { AVSessionService, AVSessionCallbacks } from './AVSessionService';
import { BackgroundTaskService } from './BackgroundTaskService';
import { ChapterCacheService } from './ChapterCacheService';
import { DownloadService } from './DownloadService';
import { WidgetUpdater } from './WidgetUpdater';
import { PlaybackStore } from './PlaybackStore';
import { StatsService } from './StatsService';
import { getWebViewAudioExtractor } from './builtin/WebViewAudioExtractor';
import { ExternalMediaWatcher } from './ExternalMediaWatcher';
import { ColorPickerUtils, CoverColorPalette } from '../utils/ColorPickerUtils';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Audio';
const AUDIO_RESOLVE_TIMEOUT_MS = 15000;

/** 播放历史落盘后广播的事件名,书架等页面订阅以实时刷新进度文案 */
export const EVT_HISTORY_UPDATED = 'app.history.updated';
export const EVT_AUDIO_PLAY_FAILED = 'app.audio.play.failed';

export interface AudioPlayFailedPayload {
  bookId: string;
  chapterId: string;
  message: string;
}

/**
 * AVPlayer 单例封装
 * 内部按 AudioSource.type 分发：rawfile / url / file
 */
export class AudioService {
  private static instance: AudioService | null = null;
  private player: media.AVPlayer | null = null;
  private state: PlayerState | null = null;
  private context: common.UIAbilityContext | null = null;
  private timer: number = -1;
  private pendingSeek: number = 0;
  private sleepTimer: number = -1;
  private sleepEndTime: number = 0;
  private isApplying: boolean = false;
  private currentFile: fileIo.File | null = null;
  /** 用户偏好的焦点模式：0=共享(SHARE_MODE)、1=独立(INDEPENDENT_MODE) */
  private interruptMode: number = 0;
  /** 失去焦点被强制暂停后，收到 RESUME 是否自动续播 */
  private autoResume: boolean = true;
  /** 标识当前暂停是否由系统焦点变化引起（用于决定 RESUME 时是否自动续播） */
  private pausedByFocus: boolean = false;
  /** 标识当前是否被外部 MEDIA(视频/游戏/视频通话) 抢焦点强制 STOP。
   *  与 pausedByFocus 互斥:STOP 不会再下发 RESUME,要靠 ExternalMediaWatcher 旁路监测视频结束 */
  private pausedByExternalMedia: boolean = false;
  /** 视频结束监测器:被 STOP 后 arm,视频流消失即续播 */
  private externalWatcher: ExternalMediaWatcher = new ExternalMediaWatcher();
  /** 节流写入 progressMs 的最近一次时间戳。AVPlayer timeUpdate ~100ms 一次,
   *  但 progressMs 是 @Trace,会触发全局 V2 级联重渲染,降到 500ms 一次足够 UI 用 */
  private lastProgressWriteAt: number = 0;
  private static readonly PROGRESS_WRITE_INTERVAL_MS: number = 500;
  /** 节流持久化的最近一次时间戳。正常播放依靠 timeUpdate 稀疏持久化(5s 一次),
   *  避免依赖 tick 频繁落盘,配合低功耗渲染器长休眠周期 */
  private lastPersistAt: number = 0;
  private static readonly PERSIST_INTERVAL_MS: number = 5000;
  private static readonly USAGE_TICK_SECONDS: number = 15;
  private static readonly USAGE_TICK_MS: number = 15000;
  /** 续播 seek 目标(ms)。>0 表示正在等待 seek 生效:
   *  此期间 AVPlayer 可能先回调一个接近 0 的旧 timeUpdate,会把 progressMs 打回起点。
   *  守卫:位置尚未追上目标前忽略这些偏小的旧值,到达目标附近才解除。 */
  private resumeTargetMs: number = 0;
  private static readonly RESUME_GUARD_TOLERANCE_MS: number = 1500;
  /** 播放任务代次：每次 playChapter / playChapterAndSeek 都会自增。
   *  正在解析音频 URL（耗时长，比如 WebView 嗅探）的旧任务跑完后会用这个比对，
   *  如果不是最新代次就直接丢弃，不再装载到 AVPlayer，避免"切了新章节但旧的还在响"。 */
  private playGen: number = 0;

  static getInstance(): AudioService {
    if (!AudioService.instance) {
      AudioService.instance = new AudioService();
    }
    return AudioService.instance;
  }

  /**
   * 用一个 Promise 暴露"是否准备好接受播控指令"。
   * 卡片 callee（play/pause/next/prev）会等这个 Promise resolve 再调用 AudioService，
   * 否则冷启动后第一下点卡片可能 state.currentChapter 还没 restore，play() 会变 no-op。
   */
  private readyResolve: (() => void) | null = null;
  private readyPromise: Promise<void> = new Promise<void>((res) => { this.readyResolve = res; });

  /** EntryAbility.bootstrapAudioService 完成后调一次 */
  markReady(): void {
    if (this.readyResolve) {
      this.readyResolve();
      this.readyResolve = null;
    }
  }

  /** 卡片 callee 用：等 ready，但带个超时兜底（避免 ready 永远不来卡死播控） */
  async whenReady(timeoutMs: number = 3000): Promise<void> {
    let timer: number = -1;
    const timeout = new Promise<void>((res) => {
      timer = setTimeout(res, timeoutMs);
    });
    await Promise.race([this.readyPromise, timeout]);
    if (timer >= 0) clearTimeout(timer);
  }

  prewarmBookSource(book: Book): void {
    if (!book.sourceUrl) return;
    this.prepareBookSource(book.sourceUrl).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'prewarmBookSource failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  private async prepareBookSource(sourceUrl: string): Promise<void> {
    await BookSourceService.prepareAudioSource(sourceUrl);
  }

  bind(state: PlayerState, context: common.UIAbilityContext): void {
    this.state = state;
    this.context = context;
    this.loadFocusPrefs();
    this.initAVSession();
  }

  private async loadFocusPrefs(): Promise<void> {
    try {
      this.interruptMode = await PreferenceService.getAudioInterruptMode();
      this.autoResume = await PreferenceService.getAudioAutoResume();
      if (this.player) {
        this.applyInterruptMode(this.player);
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadFocusPrefs failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  /** 设置音频焦点模式：0=SHARE_MODE, 1=INDEPENDENT_MODE */
  async setInterruptMode(mode: number): Promise<void> {
    this.interruptMode = mode;
    await PreferenceService.setAudioInterruptMode(mode);
    if (this.player) {
      this.applyInterruptMode(this.player);
    }
  }

  /** 设置失焦自动恢复开关 */
  async setAutoResume(enabled: boolean): Promise<void> {
    this.autoResume = enabled;
    await PreferenceService.setAudioAutoResume(enabled);
  }

  private applyInterruptMode(p: media.AVPlayer): void {
    // audioInterruptMode 是属性 setter,鸿蒙限定必须在 prepared/playing/paused/completed
    // 状态下调用,idle/initialized/error/stopped/released 都会抛 Operate Not Permit。
    // 这里只在合法状态下设;非法状态由 stateChange 'prepared' 回调里再调一次兜底。
    const s = p.state;
    if (s !== 'prepared' && s !== 'playing' && s !== 'paused' && s !== 'completed') {
      return;
    }
    try {
      p.audioInterruptMode = this.interruptMode === 1
        ? audio.InterruptMode.INDEPENDENT_MODE
        : audio.InterruptMode.SHARE_MODE;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'applyInterruptMode failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  private initAVSession(): void {
    if (!this.context) return;
    const cbs: AVSessionCallbacks = {
      onPlay: () => { this.toggle(); },
      onPause: () => { this.pauseFromSession(); },
      onPlayNext: () => { this.playNext(); },
      onPlayPrevious: () => { this.playPrevious(); },
      onSeek: (ms: number) => { this.seek(ms); }
    };
    AVSessionService.getInstance().setCallbacks(cbs);
    AVSessionService.getInstance().init(this.context).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'init AVSession failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  private syncPlaybackState(): void {
    this.syncPlaybackStateNow(false);
  }

  private async syncPlaybackStateNow(forceWidget: boolean): Promise<void> {
    if (!this.state) return;
    try {
      await AVSessionService.getInstance().updatePlaybackState(
        this.state.isPlaying,
        this.state.progressMs,
        this.state.speed,
        this.state.durationMs
      );
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updatePlaybackState failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
    try {
      await WidgetUpdater.updatePlayerCard(this.state, forceWidget);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updatePlayerCard failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player) {
      return this.player;
    }
    const p = await media.createAVPlayer();
    p.on('stateChange', (newState: media.AVPlayerState) => {
      if (!this.state) return;
      if (newState === 'initialized') {
        // 听书内容声明为 AUDIOBOOK 流,系统据此挂载低功耗音频渲染器:
        // 亮屏缓存最大 1s、熄屏缓存最大 10s,主处理器可长时间休眠,
        // 后台/熄屏播放功耗显著下降。setter 仅在 initialized 状态合法。
        try {
          p.audioRendererInfo = {
            usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
            rendererFlags: 0
          };
        } catch (err) {
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'set audioRendererInfo failed: %{public}s',
            e?.message ?? JSON.stringify(err));
        }
        p.prepare();
      } else if (newState === 'prepared') {
        // 此时 player 已进入合法状态,补一次焦点模式 setter(ensurePlayer 阶段不能设)
        this.applyInterruptMode(p);
        this.state.durationMs = p.duration;
        // TOC 不带时长,这里把 AVPlayer 解出的真实时长回写到章节,
        // 让冷启动滑块/详情页百分比/书架文案能拿到 duration(否则恒为 0)
        if (this.state.currentChapter && p.duration > 0) {
          this.state.currentChapter.duration = Math.round(p.duration / 1000);
          // 立即持久化时长到数据库，确保冷启动后仍可用
          if (this.state.currentBook) {
            DataService.upsertCachedBook(this.state.currentBook).catch((err: Error) => {
              hilog.error(DOMAIN, TAG, 'Failed to persist chapter duration: %{public}s', err.message);
            });
          }
        }
        // prepared 即上报一次 playbackState,让控制中心能立刻拿到 duration 渲染进度条
        AVSessionService.getInstance().updateMetadataDuration(p.duration);
        this.syncPlaybackState();
        if (this.pendingSeek > 0) {
          p.seek(this.pendingSeek, media.SeekMode.SEEK_PREV_SYNC);
          this.pendingSeek = 0;
        }
        // 续用上次的倍速:切章节/换书 reset 后 AVPlayer 会回到 1.0x,这里在 prepared 合法态补回
        if (this.state.speed !== 1.0) {
          try { p.setPlaybackRate(this.state.speed); } catch (_e) { /* 状态异常忽略 */ }
        }
        // 立即设置播放状态，让UI立即响应
        this.state.isPlaying = true;
        p.play();
      } else if (newState === 'playing') {
        this.state.isPlaying = true;
        // 真正开始出声,清掉 loading 标记
        this.state.isLoading = false;
        this.startTick();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(true);
        if (this.context) {
          BackgroundTaskService.start(this.context);
        }
      } else if (newState === 'paused') {
        this.state.isPlaying = false;
        this.stopTick();
        // 立即落盘:暂停后 tick 停了,不存就会丢掉「上次 tick 到暂停」之间的进度,
        // 手动暂停 / 锁屏 / 电话打断后续播都会偏早。progressMs 此刻已是暂停位置,
        // seek 守卫保证它不会是被打回的 0。
        this.persistHistory();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        // 未在播时不要继续挂 audioPlayback 长时任务:
        // 系统会以「音频未运行」取消整条 continuous task，连同 dataTransfer 一起失效，
        // 息屏后纯下载也会被冻结。下载侧会单独维持 dataTransfer。
        if (this.context) {
          BackgroundTaskService.stop(this.context).catch((_e: Error): void => {});
        }
      } else if (newState === 'completed') {
        this.state.isPlaying = false;
        this.recordPause();
        this.stopTick();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        if (this.context) {
          BackgroundTaskService.stop(this.context).catch((_e: Error): void => {});
        }
        this.autoPlayNext();
      }
    });
    p.on('timeUpdate', (ms: number) => {
      if (!this.state) return;
      // 切换章节/书的过程中（reset 之后、新音源 prepared 之前），AVPlayer 偶尔会回调
      // 一些残留的旧位置 timeUpdate；isLoading=true 期间一律不写 progressMs，
      // 避免把进度条来回打回。
      if (this.state.isLoading) return;
      // seek 守卫:续播 seek 尚未生效时,AVPlayer 会先回调接近 0 的旧位置,
      // 若放行会把 progressMs 打回起点(还可能被 5s tick 落盘成错进度)。
      // 位置追上目标附近前忽略这些偏小旧值;到达或超过目标即解除守卫。
      if (this.resumeTargetMs > 0) {
        if (ms + AudioService.RESUME_GUARD_TOLERANCE_MS < this.resumeTargetMs) {
          return;
        }
        this.resumeTargetMs = 0;
      }
      // 片尾跳过：到达片尾位置时自动跳下一章
      this.checkSkipOutro(ms);
      // 节流:跳进度 / 暂停 / 切章节时立即写,正常播放每 500ms 写一次,
      // 避免 100ms 级 @Trace 抖动导致 V2 全局级联重绘
      const now = Date.now();
      const force = !this.state.isPlaying || Math.abs(ms - this.state.progressMs) > 1500;
      if (force || now - this.lastProgressWriteAt >= AudioService.PROGRESS_WRITE_INTERVAL_MS) {
        this.state.progressMs = ms;
        this.lastProgressWriteAt = now;
      }
      // 稀疏持久化:正常播放期间每 5s 落盘一次,避免杀进程丢失大段进度。
      // 与 tick 的 15s 持久化错开:这里管播放中兜底,tick 管 Widget 同步兜底。
      if (this.state.isPlaying && now - this.lastPersistAt >= AudioService.PERSIST_INTERVAL_MS) {
        this.persistHistory().catch(() => { /* ignore */ });
        this.lastPersistAt = now;
      }
    });
    p.on('error', (err: object) => {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      if (this.state) {
        this.state.isLoading = false;
        this.state.isPlaying = false;
        // 解析后的临时音频 URL 可能已过期（如 aikeu 的签名链接），把这个章节的缓存清掉，
        // 用户下次按播放会用 originSourceValue 重新去解析一份新的音频 URL。
        const ch = this.state.currentChapter;
        if (ch && ch.originSourceValue) {
          try { ChapterCacheService.getInstance().clearChapter(ch.id); } catch (_e) { /* ignore */ }
          ch.source = { type: 'url', value: ch.originSourceValue };
        }
      }
      this.stopTick();
    });
    p.on('audioInterrupt', (event: audio.InterruptEvent) => {
      this.handleInterrupt(event);
    });
    // 焦点模式不在这里设——AVPlayer 刚 createAVPlayer 完是 idle 状态,
    // setter 会被鸿蒙拒绝(Operate Not Permit)。改在 stateChange 'prepared' 里设。
    this.player = p;
    return p;
  }

  private handleInterrupt(event: audio.InterruptEvent): void {
    if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        // 临时暂停（语音、电话、闹铃等）：标记为焦点暂停，等待系统后续下发 RESUME
        // 旧的视频流 watcher 若残留,先 disarm 以免误触发(当前打断已被新事件接管)
        this.cancelExternalMediaWatch();
        this.pausedByFocus = true;
        if (this.state) {
          this.state.isPlaying = false;
        }
        this.stopTick();
        this.syncPlaybackState();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        // 永久失去焦点:系统不会再下发 RESUME(典型场景:抖音/B 站等视频抢焦点)。
        // 不再 reset player —— 留住 paused 状态,arm ExternalMediaWatcher,
        // 监测到外部视频流消失时主动续播。30s 超时后 watcher 自动 disarm。
        // 先把旧 watcher 清掉,避免被新一轮 STOP 重复 arm 留下双监听
        this.cancelExternalMediaWatch();
        this.pausedByFocus = false;
        this.pausedByExternalMedia = true;
        if (this.state) {
          this.state.isPlaying = false;
        }
        this.stopTick();
        // 立即把当前进度落盘:与 'paused' stateChange 分支同样的理由,
        // 防止 STOP 后 tick 停了丢掉最近一段进度
        this.persistHistory();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        if (this.autoResume) {
          this.externalWatcher.arm(() => this.resumeAfterExternalMedia());
        }
      }
      // DUCK / UNDUCK：系统仅做音量变化，播放未中断，无需处理状态
    } else if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
        // 此前因 PAUSE 临时失焦，现在系统下发可续播提示
        if (this.autoResume && this.pausedByFocus) {
          this.pausedByFocus = false;
          this.resumeFromInterrupt();
        } else {
          this.pausedByFocus = false;
        }
      }
    }
  }

  private async resumeFromInterrupt(): Promise<void> {
    try {
      const p = await this.ensurePlayer();
      if (p.state === 'paused') {
        // 立即设置播放状态
        if (this.state) {
          this.state.isPlaying = true;
        }
        await p.play();
      } else if (p.state === 'idle' || p.state === 'stopped') {
        await this.resumeFromState();
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'resumeFromInterrupt failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  /**
   * 视频流消失后,ExternalMediaWatcher 回调走这里。
   * 若用户在等待期间已经手动操作过(toggle/pause/play/playChapter),pausedByExternalMedia 已被清零,直接返回。
   */
  private async resumeAfterExternalMedia(): Promise<void> {
    if (!this.pausedByExternalMedia || !this.autoResume) return;
    this.pausedByExternalMedia = false;
    try {
      const p = await this.ensurePlayer();
      if (p.state === 'paused') {
        if (this.state) {
          this.state.isPlaying = true;
        }
        await p.play();
      } else if (p.state === 'idle' || p.state === 'stopped') {
        // 等待期间系统已经把 renderer 回收,走完整续播路径
        await this.resumeFromState();
      }
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'resumeAfterExternalMedia failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /** 用户主动操作 / 重新被打断时调用,确保旧 watcher 不残留触发 */
  private cancelExternalMediaWatch(): void {
    this.pausedByExternalMedia = false;
    if (this.externalWatcher.isArmed()) {
      this.externalWatcher.disarm();
    }
  }

  private recordPause(): void {
    // AVSession 永远保持 activated,不再做 idle deactivate。保留空方法以兼容历史调用点。
  }

  private startTick(): void {
    this.stopTick();
    this.timer = setInterval(() => {
      this.persistHistory();
      this.recordListenUsage();
      // 同步给 widget:稳态播放期间 stateChange 不再翻转,卡片那边的 FormExt 进程
      // 缓存又跟主进程隔离,系统触发 onUpdateForm 时容易读到陈旧的 isPlaying。
      // 主进程定期强推一次最新状态,卡片至多滞后该间隔即可纠正。
      // 间隔 15s:低功耗渲染器熄屏缓存最大 10s,过短的 tick 会每周期唤醒主处理器,
      // 抵消 AUDIOBOOK 流的省电收益。toggle/pause/release/seek 都有即时同步,
      // 这里只是兜底。
      this.syncPlaybackState();
    }, AudioService.USAGE_TICK_MS);
  }

  private stopTick(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private recordListenUsage(): void {
    if (!this.state || !this.state.isPlaying || !this.state.currentBook || !this.state.currentChapter) return;
    const book = this.state.currentBook;
    StatsService.addListenSeconds(AudioService.USAGE_TICK_SECONDS, {
      bookId: book.id,
      title: book.title,
      author: book.author || book.narrator || '',
      cover: book.cover || ''
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'recordListenUsage failed: %{public}s', err?.message ?? JSON.stringify(err));
    });
  }

  private async persistHistory(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    const chapterId = chapter.id;
    const chapterTitle = chapter.title;
    const progressMs = this.state.progressMs;
    const durationMs = this.state.durationMs;
    const chapterIndex = this.findChapterIndex(book, chapter);
    await PreferenceService.upsertHistory({
      bookId: book.id,
      chapterId,
      progressMs,
      updatedAt: Date.now(),
      chapterTitle,
      durationMs
    });
    await PreferenceService.setLastPlayed(book.id, chapterId, progressMs, chapterTitle, durationMs, this.state.speed);
    // 每本书独立的最新进度,切书前 reset AVPlayer 之前必须把这条落盘,
    // 切回旧书时 caller 没传 positionMs 也能从这里 fallback 到上次位置
    const progress: PlayProgress = {
      bookId: book.id,
      chapterId,
      chapterTitle,
      chapterIndex: chapterIndex >= 0 ? chapterIndex : 0,
      positionMs: progressMs,
      durationMs,
      updatedAt: Date.now(),
      speed: this.state.speed
    };
    await PreferenceService.saveProgress(progress);
    await DataService.upsertCachedBook(book);
    // PlaybackStore: 让其他页面拿到的是"现在响着的"那本书,
    // sourceUrl 走 chapter.source.value(已是解析后的真实 URL,作 same-source 判断)
    PlaybackStore.getInstance().update(
      book.id, chapterId, progress.chapterIndex,
      chapter.source?.value ?? '', this.state.isPlaying
    );
    emitter.emit(EVT_HISTORY_UPDATED, { data: { bookId: book.id } });
  }

  /** 主动把当前进度立刻落盘,供 PlayerPage 退出 / 暂停等场景调用 */
  async flushHistory(): Promise<void> {
    await this.persistHistory();
  }

  /**
   * 回前台时调用:校准 AVPlayer 健康度。
   *
   * 退后台 + paused 状态下,鸿蒙在 1~2s 内会回收 audio renderer,player.state 自己掉到 idle,
   * 但内部 fdSrc/url 已失效——此时直接走 toggle → resumeFromState → applySource 设 url
   * 不一定能驱动到 prepared,UI 表现就是"按播放没反应"。
   *
   * 这里只在异常状态下做最小干预:
   * - released:player 已不可用,丢弃引用,下次 ensurePlayer 会重建
   * - error / stopped:reset 一次回到干净 idle
   * - idle:已经是干净状态,留给后续 toggle 走 resumeFromState 路径
   * - 其他(playing/paused/prepared/initialized):说明 player 还活着,不动
   *
   * 不在这里主动起播——避免应用刚回前台就抢焦点打断别的 App。
   */
  async ensureHealthy(): Promise<void> {
    const p = this.player;
    if (!p) return;
    const s = p.state;
    if (s === 'released') {
      this.player = null;
      return;
    }
    if (s === 'error' || s === 'stopped') {
      try {
        await p.reset();
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'ensureHealthy: reset failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
  }

  /**
   * 切到某章节从头播。三态决策:
   * - 同书+同章节+player 已 prepared/playing/paused: seek(0) + play(),不 reset
   * - 同书+不同章节: await 当前进度落盘 → reset → 装载新章节
   * - 不同书: await 当前进度落盘 → reset → 拿新书 PlayProgress 兜底 savedDurationMs → 装载
   */
  async playChapter(book: Book, chapter: Chapter): Promise<void> {
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    this.cancelExternalMediaWatch();

    // 封面变化时预取融合色,让播放页入场时直接命中缓存
    if (book.cover && (!this.state.currentBook || this.state.currentBook.cover !== book.cover)) {
      this.preFetchCoverColor(book.cover);
    }

    // ★ 同书+同章节短路:不 reset,直接 seek(0) + play,避免重新嗅探 URL
    if (this.canReuseSameChapter(book, chapter)) {
      await this.replaySameChapterFromStart();
      return;
    }
    // 切书或切章节前先把上一进度落盘,避免 reset 后丢数据
    await this.flushBeforeSwitch(book, chapter);
    const skipIntroMs = (book.skipIntro ?? 0) * 1000;
    return this.doPlayChapter(book, chapter, skipIntroMs);
  }

  /** 同书+同章节复用:不 reset。视 player 状态决定 seek/play */
  private async replaySameChapterFromStart(): Promise<void> {
    if (!this.state) return;
    const p = this.player;
    if (!p) return;
    // toggle() 可能在调用前设了 isLoading=true，复用章节不需要 loading 圈
    this.state.isLoading = false;
    const skipIntroMs = (this.state.currentBook?.skipIntro ?? 0) * 1000;
    this.state.progressMs = skipIntroMs;
    if (p.state === 'completed' || p.state === 'paused' || p.state === 'prepared') {
      try {
        p.seek(skipIntroMs, media.SeekMode.SEEK_PREV_SYNC);
        this.state.isPlaying = true;
        await p.play();
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'replaySameChapterFromStart failed: %{public}s',
          e?.message ?? JSON.stringify(err));
        this.state.isPlaying = false;
      }
    } else if (p.state === 'playing') {
      try {
        p.seek(skipIntroMs, media.SeekMode.SEEK_PREV_SYNC);
      } catch (_e) { /* ignore */ }
    }
  }

  /** 判断 (book,chapter) 是否就是当前播放的同章节,且 player 处于可复用状态 */
  private canReuseSameChapter(book: Book, chapter: Chapter): boolean {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return false;
    if (this.state.currentBook.id !== book.id) return false;
    if (this.state.currentChapter.id !== chapter.id) return false;
    const p = this.player;
    if (!p) return false;
    const s = p.state;
    return s === 'playing' || s === 'paused' || s === 'prepared' || s === 'completed';
  }

  /** 封面变化时预取融合色并缓存,让播放页入场时瞬时显示而非灰色过渡 */
  private preFetchCoverColor(cover: string): void {
    if (!this.context) return;
    if (this.applyCachedCoverColor(cover)) return;
    // 异步取色不阻塞播放,立即启动
    (async () => {
      let palette: CoverColorPalette | null = null;
      try {
        if (cover.startsWith('http')) {
          palette = await ColorPickerUtils.pickPaletteFromUrl(cover);
        } else if (cover.startsWith('/')) {
          palette = await ColorPickerUtils.pickPaletteFromFile(cover);
        } else {
          palette = await ColorPickerUtils.pickPaletteFromRawfile(this.context!, cover);
        }
      } catch (e) {
        // 取色失败不影响播放,静默
      }
      if (palette && this.state && this.state.currentBook && this.state.currentBook.cover === cover) {
        this.applyCoverPalette(cover, palette);
        try {
          await WidgetUpdater.updatePlayerCard(this.state, true);
        } catch (_e) { /* 取色后的卡片刷新失败不影响播放 */ }
      }
    })();
  }

  private applyCachedCoverColor(cover: string): boolean {
    if (!cover || !this.state) return false;
    const palette = ColorPickerUtils.getPaletteCached(cover);
    if (palette) {
      this.applyCoverPalette(cover, palette);
      return true;
    }
    return false;
  }

  private applyCoverPalette(cover: string, palette: CoverColorPalette): void {
    if (!this.state) return;
    const theme = ColorPickerUtils.toAmbientTheme(palette);
    this.state.accentColor = theme.center;
    this.state.ambientCover = cover;
    this.state.ambientMainColor = theme.main;
    this.state.ambientTopColor = theme.top;
    this.state.ambientBottomColor = theme.bottom;
    this.state.ambientLeftColor = theme.left;
    this.state.ambientRightColor = theme.right;
    this.state.ambientCenterColor = theme.center;
    this.state.ambientDarkColor = theme.dark;
    this.state.hasAmbientColor = true;
  }

  /**
   * 切书/切章节前把上一进度落盘 + 给 UI 立即填上 savedDurationMs 兜底。
   * - 切到不同书: 把当前书 flush;再去 PreferenceService.getProgress(目标 bookId) 拿 durationMs 兜底
   * - 切到同书不同章: 把当前章 flush;saveDurationMs 用目标章节自身 chapter.duration
   */
  private async flushBeforeSwitch(targetBook: Book, targetChapter: Chapter): Promise<void> {
    if (!this.state) return;
    const curBookId = this.state.currentBook?.id ?? '';
    const bookChanged = curBookId !== targetBook.id;
    if (curBookId && bookChanged) {
      // 切书:先把当前书的进度落盘
      try { await this.persistHistory(); } catch (_e) { /* ignore */ }
    }
    // 切书(含冷启动首播)时恢复该书上次的倍速;同书切章保持当前倍速不变。
    // 必须 await getProgress 走持久化 store:冷启动后 progressMemo 为空,
    // getProgressSync 只读内存缓存会恒为 null,导致重启后倍速永远回落 1.0x。
    // 顺带把该书进度读进 memo,后面 savedDurationMs 兜底也能命中。
    // 真正下发到 AVPlayer 由 prepared 回调里的 state.speed 补回逻辑负责。
    if (bookChanged) {
      const saved = await PreferenceService.getProgress(targetBook.id);
      this.state.speed = this.normalizeSpeed(saved?.speed);
    }
    // savedDurationMs 兜底:让 Slider max 在 prepared 之前就有非 0 值,
    // 视觉上不再"从头加载"——立刻显示"当前位置/总时长"比例。
    // 优先级: ChapterCacheService 实测 > chapter.duration > 同书旧 PlayProgress
    let saved = 0;
    const cachedDurationSec = ChapterCacheService.getInstance().getChapterDuration(targetChapter.id);
    if (cachedDurationSec > 0) {
      saved = cachedDurationSec * 1000;
    } else if (targetChapter.duration && targetChapter.duration > 0) {
      saved = targetChapter.duration * 1000;
    } else {
      const memo = PreferenceService.getProgressSync(targetBook.id);
      if (memo && memo.chapterId === targetChapter.id && memo.durationMs > 0) {
        saved = memo.durationMs;
      }
    }
    this.state.savedDurationMs = saved;
  }

  /**
   * 同步判断目标章节是否走"快路径":
   * - source.type === 'file' / 'rawfile': 已经是本地文件,无需嗅探
   * - source.type === 'url' 且长期下载 / ChapterCacheService 已有文件 / 已解析 URL: 命中
   *
   * 命中时切书过程整体 ~300-600ms 就能 prepared,UI 不必显示 loading 圈,
   * 给用户"瞬间切换"的观感。
   */
  private isFastSwitchPath(book: Book, chapter: Chapter): boolean {
    if (chapter.source.type === 'file' || chapter.source.type === 'rawfile') return true;
    if (DownloadService.getInstance().getDownloadedFilePath(book.id, chapter)) return true;
    const cache = ChapterCacheService.getInstance();
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (cache.getAudioFilePath(book.id, chapter.id, pageUrl)) return true;
    if (cache.getAudioUrl(chapter.id)) return true;
    return false;
  }

  private async doPlayChapter(book: Book, chapter: Chapter, seekMs: number): Promise<void> {
    if (!this.state || !this.context) return;
    const myGen = ++this.playGen;
    // ★ 缓存命中→快路径,UI 不显示 loading 圈;否则常规路径,显示加载状态
    const fastPath = this.isFastSwitchPath(book, chapter);
    // 快路径不需要 WebView 嗅探，不调 cancelPending——避免把预加载正在跑的嗅探取消掉，
    // 导致后续慢路径章节的 URL 解析也被波及（WebView extractor 串行，cancel 会丢队列中的任务）。
    if (!fastPath) {
      try { getWebViewAudioExtractor().cancelPending(); } catch (_e) { /* ignore */ }
    }
    this.isApplying = true;
    try {
      // 0) 先停旧 player(避免新 URL 嗅探的几秒内旧音频还在响 + 旧 timeUpdate 污染 progressMs)
      // 注意:idle 也要 reset。退后台被系统回收 audio renderer 后,player.state 会停在 idle
      // 但 fdSrc/url 已失效,此时直接 applySource 设 url 不一定能驱动到 prepared,
      // 必须 reset 一次让状态机回到干净 idle。released 状态没法 reset,跳过即可。
      try {
        const cur = this.player;
        if (cur && cur.state !== 'released') {
          await cur.reset();
        }
      } catch (_e) { /* ignore */ }
      if (myGen !== this.playGen) {
        // 被新 playChapter 抢占，不清 isLoading——新的 doPlayChapter 会自己设
        return;
      }

      // 1) 翻 UI 状态
      this.state.currentBook = book;
      this.state.currentChapter = chapter;
      this.state.progressMs = seekMs;
      this.state.durationMs = 0;
      this.state.isPlaying = false;
      this.applyCachedCoverColor(book.cover);
      // 快路径:不显示 loading,UI 直接用 savedDurationMs + progressMs 撑住,
      // 等 prepared 回调把 durationMs/playing 翻新即可,观感"瞬间切换"
      this.state.isLoading = !fastPath;
      AVSessionService.getInstance().updateMetadata(book, chapter);
      // 早写 PlaybackStore:让正在等待的页面立刻看到"当前书已切换"
      PlaybackStore.getInstance().update(
        book.id, chapter.id,
        this.findChapterIndex(book, chapter),
        chapter.source?.value ?? '', false
      );

      // 2) 解析音频 URL
      await this.resolveAudioUrl(book, chapter);
      if (myGen !== this.playGen) {
        // 被抢占:如果新 gen 走的也是慢路径,它的 isLoading 已经是 true;
        // 如果新 gen 走快路径,它的 isLoading 已经是 false。
        // 这里不碰 isLoading,交给新 gen 管理。
        return;
      }
      // URL 解析失败兜底：cancelPending 可能把正在跑的 WebView 嗅探取消掉，
      // resolveAudioUrl 内部 catch 后不抛异常，chapter.source 仍是原始页面 URL。
      // 此时不能把页面 URL 当音频 URL 喂给 AVPlayer——player 会无限卡在 loading。
      if (chapter.source.type === 'url' && chapter.originSourceValue
        && chapter.source.value === chapter.originSourceValue) {
        hilog.warn(DOMAIN, TAG, 'resolveAudioUrl failed (source unchanged), aborting playback');
        this.state.isLoading = false;
        this.state.isPlaying = false;
        this.emitPlayFailed(book.id, chapter.id, '音频地址获取失败，请点击重试');
        return;
      }

      // 3) 装载
      const p = await this.ensurePlayer();
      if (myGen !== this.playGen) {
        return;
      }
      if (seekMs > 0) {
        this.pendingSeek = seekMs;
        this.resumeTargetMs = seekMs;
      }
      await this.applySource(p, chapter.source);
      this.triggerPreload(book, chapter);
    } catch (err) {
      if (myGen === this.playGen && this.state) {
        this.state.isLoading = false;
        this.state.isPlaying = false;
        const e = err as Error;
        const message = e?.message?.includes('超时') ? '音频地址获取超时，请点击重试' : '播放失败，请点击重试';
        this.emitPlayFailed(book.id, chapter.id, message);
      }
      throw err as Error;
    } finally {
      if (myGen === this.playGen) this.isApplying = false;
    }
  }

  /**
   * 把章节的 source.value（可能是页面 URL）解析成真实音频 URL。
   * - rawfile / file 类型：跳过
   * - 已经是直接音频 URL（缓存过 / 上次解析过）：跳过
   * - URL 类型 + 在线书源：调用 BookSourceService.getAudioUrl 解析
   *
   * 重要：如果上一次播放后 source.value 已经是临时签名 URL（如 api.aikeu.com 带 sign），
   * 重启后这条 URL 已过期，必须用 originSourceValue 里保存的章节页 URL 重新解析。
   */
  private async resolveAudioUrl(book: Book, chapter: Chapter): Promise<void> {
    if (chapter.source.type !== 'url') return;
    if (!book.sourceUrl) return;
    // 第一次解析，把当前的 source.value 备份成 originSourceValue（永远是章节页 URL）
    if (!chapter.originSourceValue) {
      chapter.originSourceValue = chapter.source.value;
    }
    const cache = ChapterCacheService.getInstance();
    // 1) 优先看长期下载文件，保证整本下载后离线播放稳定
    const downloadedPath = DownloadService.getInstance().getDownloadedFilePath(book.id, chapter);
    if (downloadedPath) {
      chapter.source = { type: 'file', value: downloadedPath };
      return;
    }
    // 2) 再看临时本地音频文件缓存（预加载到沙箱），最快路径，离线也能播
    const filePath = cache.getAudioFilePath(book.id, chapter.id, chapter.originSourceValue);
    if (filePath) {
      chapter.source = { type: 'file', value: filePath };
      return;
    }
    // 3) URL 缓存命中
    const cachedUrl = cache.getAudioUrl(chapter.id);
    if (cachedUrl) {
      chapter.source = { type: 'url', value: cachedUrl };
      // 顺手把这个章节的文件也缓到本地
      cache.ensureFileCached(book, chapter, cachedUrl);
      return;
    }
    // 4) 都没有，从书源解析
    try {
      const sources = await SourceDataService.getSources();
      const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
      if (!source) return;
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const audioUrl = await this.resolveAudioUrlWithTimeout(source, pageUrl, book.variables);
      if (audioUrl) {
        chapter.source = { type: 'url', value: audioUrl };
        // 把当前章节也下到本地
        cache.ensureFileCached(book, chapter, audioUrl);
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'resolveAudioUrl failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      throw new Error(e?.message || '音频地址获取失败');
    }
  }

  private async resolveAudioUrlWithTimeout(source: BookSource, pageUrl: string,
    variables?: Record<string, string>): Promise<string> {
    let timerId: number = -1;
    const timeoutMs = BookSourceService.getAudioResolveTimeoutMs(source, AUDIO_RESOLVE_TIMEOUT_MS);
    const timeout = new Promise<string>((_resolve, reject) => {
      timerId = setTimeout(() => reject(new Error('音频地址获取超时')), timeoutMs);
    });
    try {
      return await Promise.race([BookSourceService.getAudioUrl(source, pageUrl, variables), timeout]);
    } finally {
      if (timerId >= 0) clearTimeout(timerId);
    }
  }

  private emitPlayFailed(bookId: string, chapterId: string, message: string): void {
    emitter.emit(EVT_AUDIO_PLAY_FAILED, {
      data: { bookId, chapterId, message } as AudioPlayFailedPayload
    });
  }

  private async applySource(p: media.AVPlayer, src: AudioSource): Promise<void> {
    if (!this.context) return;

    this.closeCurrentFile();

    try {
      if (src.type === 'rawfile') {
        const fd = await this.context.resourceManager.getRawFd(src.value);
        p.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
      } else if (src.type === 'url') {
        if (!src.value || src.value.trim().length === 0) {
          hilog.error(DOMAIN, TAG, 'Empty URL provided');
          return;
        }
        if (!src.value.startsWith('http://') && !src.value.startsWith('https://')) {
          hilog.error(DOMAIN, TAG, 'Invalid URL scheme: %{public}s', src.value.substring(0, 50));
          return;
        }
        p.url = src.value;
      } else if (src.type === 'file') {
        // 沙箱文件用 fdSrc 播放（AVPlayer 对沙箱绝对路径不接受 file:// 形式）
        const f = await fileIo.open(src.value, fileIo.OpenMode.READ_ONLY);
        const stat = await fileIo.stat(f.fd);
        this.currentFile = f;
        p.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'applySource failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      this.closeCurrentFile();
    }
  }

  private closeCurrentFile(): void {
    if (this.currentFile) {
      try {
        fileIo.closeSync(this.currentFile);
      } catch (_e) { /* ignore */ }
      this.currentFile = null;
    }
  }

  /** AVSession pause 指令专用：直接暂停，不做 toggle */
  private async pauseFromSession(): Promise<void> {
    if (!this.player) return;
    if (this.player.state === 'playing') {
      // 立即设置暂停状态，让UI立即响应（乐观更新）
      if (this.state) {
        this.state.isPlaying = false;
        // 立即同步到 AVSession 和控制中心
        this.syncPlaybackState();
      }
      try {
        await this.player.pause();
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'pauseFromSession failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
  }

  async toggle(): Promise<void> {
    // 用户主动操作，清除焦点暂停标记
    this.pausedByFocus = false;
    this.cancelExternalMediaWatch();
    // 冷启动后从持久化状态恢复:player 还没装载音源时,先按 currentChapter + progressMs 起播续播
    if (!this.player || this.player.state === 'idle' || this.player.state === 'stopped') {
      if (this.state && this.state.currentBook && this.state.currentChapter) {
        // 立即翻 loading，避免用户点了 4s 没反应
        this.state.isLoading = true;
        await this.resumeFromState();
        return;
      }
    }
    const p = await this.ensurePlayer();
    if (p.state === 'playing') {
      // 立即设置暂停状态，让UI立即响应（乐观更新）
      if (this.state) {
        this.state.isPlaying = false;
        // 立即同步到 AVSession 和控制中心
        this.syncPlaybackState();
      }
      await p.pause();
    } else if (p.state === 'paused') {
      // 立即设置播放状态，让UI立即响应
      if (this.state) {
        this.state.isPlaying = true;
        // 立即同步到 AVSession 和控制中心
        this.syncPlaybackState();
      }
      await p.play();
    } else if (p.state === 'completed') {
      // completed 直接 play 在部分机型不会重置进度,先 seek 到 0 再 play
      p.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      if (this.state) {
        this.state.progressMs = 0;
        this.state.isPlaying = true;
      }
      await p.play();
    }
  }

  /** 按 state 中的 currentBook/currentChapter/progressMs 起播续播。url 类型 + 书源会先重解析地址。 */
  async resumeFromState(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    const seekMs = this.state.progressMs;
    // playChapterAndSeek 内部会做 URL 解析，这里不用重复
    await this.playChapterAndSeek(book, chapter, seekMs);
  }

  async seek(ms: number): Promise<void> {
    this.cancelExternalMediaWatch();
    const p = await this.ensurePlayer();
    // 同步先把 state.progressMs 推到目标位置,避免 UI 滑块回弹
    if (this.state) {
      this.state.progressMs = ms;
    }
    if (p.state === 'completed') {
      // completed 状态下需要先 seek + play 才能继续
      p.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
      await p.play();
    } else {
      p.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
    }
    this.syncPlaybackState();
  }

  async replayCurrent(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    await this.playChapterAndSeek(this.state.currentBook, this.state.currentChapter, 0);
  }

  setPlayMode(mode: PlayMode): void {
    if (!this.state) return;
    this.state.playMode = mode;
  }

  /** 归一化倍速:缺省/NaN/Infinity/非正数一律回 1.0,其余 clamp 到 AVPlayer 合法区间 [0.125, 4.0]。
   *  恢复持久化值和 setSpeed 走同一逻辑,防止反序列化出的脏数据被直接喂给 setPlaybackRate。 */
  private normalizeSpeed(speed: number | undefined): number {
    if (speed === undefined || !Number.isFinite(speed) || speed <= 0) return 1.0;
    return Math.min(4.0, Math.max(0.125, speed));
  }

  async setSpeed(speed: number): Promise<void> {
    const p = await this.ensurePlayer();
    // 连续(无级)倍速:用 setPlaybackRate,有效范围 [0.125, 4.0]。
    // 旧实现用 media.PlaybackSpeed 离散枚举,只能 0.75/1/1.25/1.75/2,无法无级调节。
    const rate = this.normalizeSpeed(speed);
    try {
      p.setPlaybackRate(rate);
    } catch (e) {
      // setPlaybackRate 仅在 prepared/playing/paused/completed 合法,其它状态会抛异常;
      // 忽略即可,prepared 时会在 stateChange 里重新应用 state.speed。
      hilog.warn(DOMAIN, TAG, 'setPlaybackRate failed: %{public}s', JSON.stringify(e));
    }
    if (this.state) this.state.speed = rate;
    this.syncPlaybackState();
    // 立即落盘该书倍速:slider 松手才调用,频率低;避免「改完没暂停就杀进程」丢记忆
    try { await this.persistHistory(); } catch (_e) { /* ignore */ }
  }

  setSleepTimer(minutes: number): void {
    this.cancelSleepTimer();
    if (!this.state) return;
    if (minutes <= 0) {
      this.state.sleepMinutes = 0;
      this.state.sleepRemainingMs = 0;
      return;
    }
    this.state.sleepMinutes = minutes;
    this.sleepEndTime = Date.now() + minutes * 60 * 1000;
    this.state.sleepRemainingMs = minutes * 60 * 1000;
    this.sleepTimer = setInterval(() => {
      if (!this.state) return;
      const remaining = this.sleepEndTime - Date.now();
      if (remaining <= 0) {
        this.state.sleepRemainingMs = 0;
        this.state.sleepMinutes = 0;
        this.cancelSleepTimer();
        this.pauseForSleep();
      } else {
        this.state.sleepRemainingMs = remaining;
      }
    }, 1000);
  }

  cancelSleepTimer(): void {
    if (this.sleepTimer >= 0) {
      clearInterval(this.sleepTimer);
      this.sleepTimer = -1;
    }
  }

  private async pauseForSleep(): Promise<void> {
    const p = await this.ensurePlayer();
    if (p.state === 'playing') {
      await p.pause();
    }
    // 睡眠暂停后 stopTick 停了 5s 强推,卡片容易卡在"播放中"。
    // 延迟 1.5s 再补推一次:给 FormExt 进程的 preferences 缓存足够的重载窗口,
    // 确保卡片能读到最新的 isPlaying=false。
    setTimeout(() => {
      this.syncPlaybackState();
    }, 1500);
  }

  async release(): Promise<void> {
    this.cancelExternalMediaWatch();
    this.cancelSleepTimer();
    this.stopTick();
    if (this.state) {
      this.state.isPlaying = false;
      this.state.isLoading = false;
      this.state.sleepMinutes = 0;
      this.state.sleepRemainingMs = 0;
      // 退出时先走最小卡片更新包,避免完整快照处理封面/取色拖慢"播放中 -> 暂停"状态翻转。
      try { await WidgetUpdater.optimisticSetPlaying(false); } catch (_e) { /* ignore */ }
      try { await this.persistHistory(); } catch (_e) { /* ignore */ }
      PlaybackStore.getInstance().setPlaying(false);
      await this.syncPlaybackStateNow(true);
    }
    if (this.player) {
      // 先移除事件监听器，避免 release 过程中回调触发对已释放资源的访问
      try { this.player.off('stateChange'); } catch (_e) { /* ignore */ }
      try { this.player.off('timeUpdate'); } catch (_e) { /* ignore */ }
      try { this.player.off('error'); } catch (_e) { /* ignore */ }
      try { this.player.off('audioInterrupt'); } catch (_e) { /* ignore */ }
      await this.player.release();
      this.player = null;
    }
    this.closeCurrentFile();
    if (this.context) {
      await BackgroundTaskService.stop(this.context);
    }
    await AVSessionService.getInstance().destroy();
    // 重置单例：让下次 getInstance() 创建全新实例，避免 readyPromise/playGen 等状态残留
    this.state = null;
    this.context = null;
    this.playGen = 0;
    this.isApplying = false;
    this.pendingSeek = 0;
    this.resumeTargetMs = 0;
    this.pausedByFocus = false;
    this.pausedByExternalMedia = false;
    this.lastProgressWriteAt = 0;
    this.lastPersistAt = 0;
    AudioService.instance = null;
  }

  /** 片尾跳过：检测当前播放位置是否到达片尾区域，到达则自动跳下一章 */
  private checkSkipOutro(ms: number): void {
    if (!this.state || !this.state.currentBook) return;
    const skipOutro = this.state.currentBook.skipOutro ?? 0;
    if (skipOutro <= 0) return;
    const p = this.player;
    if (!p || p.state !== 'playing') return;
    const duration = p.duration;
    if (duration <= 0) return;
    const outroStartMs = duration - skipOutro * 1000;
    if (outroStartMs <= 0) return;
    if (ms >= outroStartMs) {
      this.autoPlayNext();
    }
  }

  private autoPlayNext(): void {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const mode = this.state.playMode;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    if (idx < 0) return;

    if (mode === PlayMode.SingleLoop) {
      // 单集循环:重播当前章节
      this.playChapterAndSeek(this.state.currentBook, chapters[idx], 0);
      return;
    }
    if (idx < chapters.length - 1) {
      this.playChapter(this.state.currentBook, chapters[idx + 1]);
      return;
    }
    if (mode === PlayMode.ListLoop && chapters.length > 0) {
      // 列表循环:回到第一集
      this.playChapter(this.state.currentBook, chapters[0]);
    }
    // 顺序播放:停在最后一集
  }

  /**
   * 起播某章节并 seek 到指定位置。三态决策同 playChapter:
   * - 同书+同章节+player 已 prepared/playing/paused: 仅 seek(seekMs),不 reset
   * - 同书+不同章 / 不同书: await 落盘 → reset → 装载 → prepared 后 seek
   */
  async playChapterAndSeek(book: Book, chapter: Chapter, seekMs: number): Promise<void> {
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    this.cancelExternalMediaWatch();
    // ★ 同书+同章节+合理状态: 直接 seek,不 reset
    if (this.canReuseSameChapter(book, chapter)) {
      await this.seekAndPlaySameChapter(seekMs);
      return;
    }
    await this.flushBeforeSwitch(book, chapter);
    return this.doPlayChapter(book, chapter, seekMs);
  }

  /** 同书+同章节复用:仅 seek + 让它播 */
  private async seekAndPlaySameChapter(seekMs: number): Promise<void> {
    if (!this.state) return;
    const p = this.player;
    if (!p) return;
    this.state.progressMs = seekMs;
    if (seekMs > 0) {
      this.resumeTargetMs = seekMs;
    }
    try {
      if (p.state === 'playing') {
        p.seek(seekMs, media.SeekMode.SEEK_PREV_SYNC);
      } else if (p.state === 'paused' || p.state === 'prepared' || p.state === 'completed') {
        p.seek(seekMs, media.SeekMode.SEEK_PREV_SYNC);
        this.state.isPlaying = true;
        await p.play();
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'seekAndPlaySameChapter failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private triggerPreload(book: Book, chapter: Chapter): void {
    const idx = this.findChapterIndex(book, chapter);
    if (idx < 0) return;
    ChapterCacheService.getInstance().preloadAudioChapters(book, idx);
  }

  private findChapterIndex(book: Book, chapter: Chapter | null): number {
    if (!book || !chapter) return -1;
    return DataService.resolveChapterIndex(book, chapter.id, chapter.title);
  }

  /** 公开:供 AVSession / 卡片 callee 调用 */
  async playNext(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    if (idx >= 0 && idx < chapters.length - 1) {
      await this.playChapter(this.state.currentBook, chapters[idx + 1]);
    } else if (this.state.playMode === PlayMode.ListLoop && chapters.length > 0) {
      await this.playChapter(this.state.currentBook, chapters[0]);
    }
  }

  /** 公开:供 AVSession / 卡片 callee 调用 */
  async playPrevious(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    if (idx > 0) {
      await this.playChapter(this.state.currentBook, chapters[idx - 1]);
    }
  }

  /** 公开:供卡片 callee 直接暂停(不做 toggle) */
  async pause(): Promise<void> {
    this.cancelExternalMediaWatch();
    if (!this.player) return;
    if (this.player.state === 'playing') {
      // 立即设置暂停状态，让UI立即响应（乐观更新）
      if (this.state) {
        this.state.isPlaying = false;
        // 立即同步到 AVSession 和控制中心
        this.syncPlaybackState();
      }
      try {
        await this.player.pause();
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'pause failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
  }

  /** 公开:供卡片 callee 直接播放;未装载音源时按 state 起播续播 */
  async play(): Promise<void> {
    this.cancelExternalMediaWatch();
    if (!this.player || this.player.state === 'idle' || this.player.state === 'stopped') {
      if (this.state && this.state.currentBook && this.state.currentChapter) {
        await this.resumeFromState();
      }
      return;
    }
    if (this.player.state === 'paused') {
      if (this.state) {
        this.state.isPlaying = true;
      }
      try {
        await this.player.play();
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'play failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    } else if (this.player.state === 'completed') {
      this.player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      if (this.state) {
        this.state.progressMs = 0;
        this.state.isPlaying = true;
      }
      await this.player.play();
    }
  }
}
