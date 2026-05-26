import { Book, Chapter } from './Book';

/**
 * 播放模式
 * - sequence: 顺序播放（最后一集结束后停止）
 * - listLoop: 列表循环（最后一集播完回到第一集）
 * - singleLoop: 单集循环（当前集循环重播）
 */
export enum PlayMode {
  Sequence = 0,
  ListLoop = 1,
  SingleLoop = 2
}

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
  @Trace playMode: PlayMode = PlayMode.Sequence;

  reset(): void {
    this.currentBook = null;
    this.currentChapter = null;
    this.isPlaying = false;
    this.progressMs = 0;
    this.durationMs = 0;
  }
}

export const PLAYER_STATE_KEY = 'global_player_state';

/**
 * 全局阅读状态（V2）
 * 文本阅读器写入当前正在阅读的书 / 章节，详情页据此高亮
 */
@ObservedV2
export class ReadingState {
  @Trace currentBookId: string = '';
  @Trace currentChapterId: string = '';

  set(bookId: string, chapterId: string): void {
    this.currentBookId = bookId;
    this.currentChapterId = chapterId;
  }
}

export const READING_STATE_KEY = 'global_reading_state';
