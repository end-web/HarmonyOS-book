import { Book, Chapter } from './Book';

/**
 * 全局播放状态（V2）
 * 通过 AppStorageV2 全局单例供任意页面订阅
 */
@ObservedV2
export class PlayerState {
  @Trace currentBook: Book | null = null;
  @Trace currentChapter: Chapter | null = null;
  @Trace isPlaying: boolean = false;
  @Trace progressMs: number = 0;
  @Trace durationMs: number = 0;
  @Trace speed: number = 1.0;
  @Trace accentColor: string = '#2A7C8C';
  @Trace sleepMinutes: number = 0;
  @Trace sleepRemainingMs: number = 0;

  reset(): void {
    this.currentBook = null;
    this.currentChapter = null;
    this.isPlaying = false;
    this.progressMs = 0;
    this.durationMs = 0;
  }
}

export const PLAYER_STATE_KEY = 'global_player_state';
