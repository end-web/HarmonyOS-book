import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter, AudioSource } from '../model/Book';
import { PlayerState } from '../model/PlayerState';
import { PreferenceService } from './PreferenceService';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Audio';

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

  static getInstance(): AudioService {
    if (!AudioService.instance) {
      AudioService.instance = new AudioService();
    }
    return AudioService.instance;
  }

  bind(state: PlayerState, context: common.UIAbilityContext): void {
    this.state = state;
    this.context = context;
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
        if (this.pendingSeek > 0) {
          p.seek(this.pendingSeek, media.SeekMode.SEEK_PREV_SYNC);
          this.pendingSeek = 0;
        }
        p.play();
      } else if (newState === 'playing') {
        this.state.isPlaying = true;
        this.startTick();
      } else if (newState === 'paused') {
        this.state.isPlaying = false;
        this.stopTick();
      } else if (newState === 'completed') {
        this.state.isPlaying = false;
        this.stopTick();
        this.autoPlayNext();
      }
    });
    p.on('timeUpdate', (ms: number) => {
      if (this.state) {
        this.state.progressMs = ms;
      }
    });
    p.on('error', (err: object) => {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      this.stopTick();
    });
    this.player = p;
    return p;
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
    const bookId = this.state.currentBook.id;
    const chapterId = this.state.currentChapter.id;
    const progressMs = this.state.progressMs;
    await PreferenceService.upsertHistory({
      bookId,
      chapterId,
      progressMs,
      updatedAt: Date.now()
    });
    await PreferenceService.setLastPlayed(bookId, chapterId, progressMs);
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
      await this.applySource(p, chapter.source);
    } finally {
      this.isApplying = false;
    }
  }

  private async applySource(p: media.AVPlayer, src: AudioSource): Promise<void> {
    if (!this.context) return;
    hilog.info(DOMAIN, TAG, 'applySource type=%{public}s value=%{public}s',
      src.type, src.value ? src.value.substring(0, 200) : '');

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
        p.url = 'file://' + src.value;
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'applySource failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  async toggle(): Promise<void> {
    const p = await this.ensurePlayer();
    if (p.state === 'playing') {
      await p.pause();
    } else if (p.state === 'paused' || p.state === 'completed') {
      await p.play();
    }
  }

  async seek(ms: number): Promise<void> {
    const p = await this.ensurePlayer();
    p.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
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
    if (this.player) {
      await this.player.release();
      this.player = null;
    }
  }

  private autoPlayNext(): void {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = chapters.findIndex((c) => c.id === this.state!.currentChapter!.id);
    if (idx >= 0 && idx < chapters.length - 1) {
      this.playChapter(this.state.currentBook, chapters[idx + 1]);
    }
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
      await this.applySource(p, chapter.source);
    } finally {
      this.isApplying = false;
    }
  }
}
