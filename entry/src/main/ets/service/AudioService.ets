import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { Book, Chapter, AudioSource } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { PlayerState, PlayMode } from '../model/PlayerState';
import { PreferenceService } from './PreferenceService';
import { BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { AVSessionService, AVSessionCallbacks } from './AVSessionService';
import { BackgroundTaskService } from './BackgroundTaskService';
import { ChapterCacheService } from './ChapterCacheService';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Audio';

/** 播放历史落盘后广播的事件名,书架等页面订阅以实时刷新进度文案 */
export const EVT_HISTORY_UPDATED = 'app.history.updated';

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
  /** 是否为短暂 duck 类打断（只有 duck 打断恢复时才自动续播） */
  private wasDuckedInterrupt: boolean = false;
  private idleTimer: number = -1;
  private static readonly IDLE_TIMEOUT_MS: number = 5 * 60 * 1000;
  /** 节流写入 progressMs 的最近一次时间戳。AVPlayer timeUpdate ~100ms 一次,
   *  但 progressMs 是 @Trace,会触发全局 V2 级联重渲染,降到 500ms 一次足够 UI 用 */
  private lastProgressWriteAt: number = 0;
  private static readonly PROGRESS_WRITE_INTERVAL_MS: number = 500;

  static getInstance(): AudioService {
    if (!AudioService.instance) {
      AudioService.instance = new AudioService();
    }
    return AudioService.instance;
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

  private async playNext(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = chapters.findIndex((c) => c.id === this.state!.currentChapter!.id);
    if (idx >= 0 && idx < chapters.length - 1) {
      await this.playChapter(this.state.currentBook, chapters[idx + 1]);
    } else if (this.state.playMode === PlayMode.ListLoop && chapters.length > 0) {
      await this.playChapter(this.state.currentBook, chapters[0]);
    }
  }

  private async playPrevious(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = chapters.findIndex((c) => c.id === this.state!.currentChapter!.id);
    if (idx > 0) {
      await this.playChapter(this.state.currentBook, chapters[idx - 1]);
    }
  }

  private syncPlaybackState(): void {
    if (!this.state) return;
    AVSessionService.getInstance().updatePlaybackState(
      this.state.isPlaying,
      this.state.progressMs,
      this.state.speed,
      this.state.durationMs
    );
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player) {
      return this.player;
    }
    const p = await media.createAVPlayer();
    p.on('stateChange', (newState: media.AVPlayerState) => {
      hilog.info(DOMAIN, TAG, 'AVPlayer state -> %{public}s', newState);
      if (!this.state) return;
      if (newState === 'initialized') {
        p.prepare();
      } else if (newState === 'prepared') {
        this.state.durationMs = p.duration;
        hilog.info(DOMAIN, TAG, 'prepared, duration=%{public}d', p.duration);
        // prepared 即上报一次 playbackState,让控制中心能立刻拿到 duration 渲染进度条
        AVSessionService.getInstance().updateMetadataDuration(p.duration);
        this.syncPlaybackState();
        if (this.pendingSeek > 0) {
          p.seek(this.pendingSeek, media.SeekMode.SEEK_PREV_SYNC);
          this.pendingSeek = 0;
        }
        // 立即设置播放状态，让UI立即响应
        this.state.isPlaying = true;
        p.play();
      } else if (newState === 'playing') {
        this.state.isPlaying = true;
        this.stopIdleTimer();
        AVSessionService.getInstance().reactivate();
        this.startTick();
        this.syncPlaybackState();
        if (this.context) {
          BackgroundTaskService.start(this.context);
        }
      } else if (newState === 'paused') {
        this.state.isPlaying = false;
        if (!this.pausedByFocus) {
          this.recordPause();
        }
        this.stopTick();
        this.syncPlaybackState();
      } else if (newState === 'completed') {
        this.state.isPlaying = false;
        this.recordPause();
        this.stopTick();
        this.syncPlaybackState();
        this.autoPlayNext();
      }
    });
    p.on('timeUpdate', (ms: number) => {
      if (!this.state) return;
      // 节流:跳进度 / 暂停 / 切章节时立即写,正常播放每 500ms 写一次,
      // 避免 100ms 级 @Trace 抖动导致 V2 全局级联重绘
      const now = Date.now();
      const force = !this.state.isPlaying || Math.abs(ms - this.state.progressMs) > 1500;
      if (force || now - this.lastProgressWriteAt >= AudioService.PROGRESS_WRITE_INTERVAL_MS) {
        this.state.progressMs = ms;
        this.lastProgressWriteAt = now;
      }
    });
    p.on('error', (err: object) => {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      this.stopTick();
    });
    p.on('audioInterrupt', (event: audio.InterruptEvent) => {
      this.handleInterrupt(event);
    });
    this.applyInterruptMode(p);
    this.player = p;
    return p;
  }

  private handleInterrupt(event: audio.InterruptEvent): void {
    hilog.info(DOMAIN, TAG, 'audioInterrupt forceType=%{public}d hintType=%{public}d',
      event.forceType, event.hintType);
    if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        this.pausedByFocus = true;
        this.wasDuckedInterrupt = false;
        this.recordPause();
        if (this.state) {
          this.state.isPlaying = false;
        }
        this.stopTick();
        this.syncPlaybackState();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.pausedByFocus = false;
        this.wasDuckedInterrupt = false;
        this.recordPause();
        if (this.state) {
          this.state.isPlaying = false;
        }
        this.stopTick();
        this.syncPlaybackState();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
        this.wasDuckedInterrupt = true;
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
        this.wasDuckedInterrupt = false;
      }
    } else if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
        if (this.autoResume && this.pausedByFocus && this.wasDuckedInterrupt) {
          this.pausedByFocus = false;
          this.wasDuckedInterrupt = false;
          this.resumeFromInterrupt();
        } else {
          this.pausedByFocus = false;
          this.wasDuckedInterrupt = false;
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

  private recordPause(): void {
    this.startIdleTimer();
  }

  private startIdleTimer(): void {
    this.stopIdleTimer();
    this.idleTimer = setTimeout(() => {
      hilog.info(DOMAIN, TAG, 'Idle timeout reached, deactivating AVSession');
      AVSessionService.getInstance().deactivate();
    }, AudioService.IDLE_TIMEOUT_MS);
  }

  private stopIdleTimer(): void {
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
  }

  private startTick(): void {
    this.stopTick();
    this.timer = setInterval(() => {
      this.persistHistory();
    }, 5000);
  }

  private stopTick(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async persistHistory(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const book = this.state.currentBook;
    const chapterId = this.state.currentChapter.id;
    const progressMs = this.state.progressMs;
    await PreferenceService.upsertHistory({
      bookId: book.id,
      chapterId,
      progressMs,
      updatedAt: Date.now()
    });
    await PreferenceService.setLastPlayed(book.id, chapterId, progressMs);
    await DataService.upsertCachedBook(book);
    emitter.emit(EVT_HISTORY_UPDATED, { data: { bookId: book.id } });
  }

  /** 主动把当前进度立刻落盘,供 PlayerPage 退出 / 暂停等场景调用 */
  async flushHistory(): Promise<void> {
    await this.persistHistory();
  }

  async playChapter(book: Book, chapter: Chapter): Promise<void> {
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    if (this.isApplying) {
      hilog.warn(DOMAIN, TAG, 'playChapter ignored, another applySource in progress');
      return;
    }
    this.isApplying = true;
    try {
      const p = await this.ensurePlayer();
      if (p.state !== 'idle' && p.state !== 'released') {
        await p.reset();
      }
      this.state.currentBook = book;
      this.state.currentChapter = chapter;
      this.state.progressMs = 0;
      this.state.durationMs = 0;
      AVSessionService.getInstance().updateMetadata(book, chapter);
      await this.applySource(p, chapter.source);
      this.triggerPreload(book, chapter);
    } finally {
      this.isApplying = false;
    }
  }

  private async applySource(p: media.AVPlayer, src: AudioSource): Promise<void> {
    if (!this.context) return;
    hilog.info(DOMAIN, TAG, 'applySource type=%{public}s value=%{public}s',
      src.type, src.value ? src.value.substring(0, 200) : '');

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
      try {
        this.startIdleTimer();
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
    // 冷启动后从持久化状态恢复:player 还没装载音源时,先按 currentChapter + progressMs 起播续播
    if (!this.player || this.player.state === 'idle' || this.player.state === 'stopped') {
      if (this.state && this.state.currentBook && this.state.currentChapter) {
        await this.resumeFromState();
        return;
      }
    }
    const p = await this.ensurePlayer();
    if (p.state === 'playing') {
      await p.pause();
    } else if (p.state === 'paused') {
      this.stopIdleTimer();
      // 立即设置播放状态，让UI立即响应
      if (this.state) {
        this.state.isPlaying = true;
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
    if (chapter.source.type === 'url' && book.sourceUrl) {
      try {
        const sourcesJson = await PreferenceService.getBookSources();
        const sources = JSON.parse(sourcesJson) as BookSource[];
        const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
        if (source) {
          const audioUrl = await BookSourceService.getAudioUrl(source, chapter.source.value);
          chapter.source = { type: 'url', value: audioUrl };
        }
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'resumeFromState getAudioUrl failed: %{public}s',
          e && e.message ? e.message : JSON.stringify(err));
      }
    }
    await this.playChapterAndSeek(book, chapter, seekMs);
  }

  async seek(ms: number): Promise<void> {
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

  async setSpeed(speed: number): Promise<void> {
    const p = await this.ensurePlayer();
    let target: media.PlaybackSpeed | null = null;
    if (speed === 0.75) target = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    else if (speed === 1) target = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    else if (speed === 1.25) target = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    else if (speed === 1.75) target = media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    else if (speed === 2) target = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    if (target !== null) {
      p.setSpeed(target);
      if (this.state) this.state.speed = speed;
      this.syncPlaybackState();
    }
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
  }

  async release(): Promise<void> {
    this.stopTick();
    this.stopIdleTimer();
    if (this.player) {
      await this.player.release();
      this.player = null;
    }
    this.closeCurrentFile();
    if (this.context) {
      await BackgroundTaskService.stop(this.context);
    }
    await AVSessionService.getInstance().destroy();
  }

  private autoPlayNext(): void {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const mode = this.state.playMode;
    const chapters = this.state.currentBook.chapters;
    const idx = chapters.findIndex((c) => c.id === this.state!.currentChapter!.id);
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

  async playChapterAndSeek(book: Book, chapter: Chapter, seekMs: number): Promise<void> {
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    if (this.isApplying) {
      hilog.warn(DOMAIN, TAG, 'playChapterAndSeek ignored, another applySource in progress');
      return;
    }
    this.isApplying = true;
    try {
      const p = await this.ensurePlayer();
      if (p.state !== 'idle' && p.state !== 'released') {
        await p.reset();
      }
      this.state.currentBook = book;
      this.state.currentChapter = chapter;
      this.state.progressMs = seekMs;
      this.state.durationMs = 0;
      this.pendingSeek = seekMs;
      AVSessionService.getInstance().updateMetadata(book, chapter);
      await this.applySource(p, chapter.source);
      this.triggerPreload(book, chapter);
    } finally {
      this.isApplying = false;
    }
  }

  private triggerPreload(book: Book, chapter: Chapter): void {
    const idx = book.chapters.findIndex((c) => c.id === chapter.id);
    if (idx < 0) return;
    ChapterCacheService.getInstance().preloadAudioChapters(book, idx);
  }
}
