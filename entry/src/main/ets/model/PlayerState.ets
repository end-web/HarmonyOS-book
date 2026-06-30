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
  /** 正在解析音频 URL / 装载音源 / 等待 prepared 的过渡状态。UI 在此期间显示 loading 图标。 */
  @Trace isLoading: boolean = false;
  @Trace progressMs: number = 0;
  @Trace durationMs: number = 0;
  /**
   * prepared 之前的兜底时长(从 PlayProgress / chapter.duration 读到的值)。
   * 切书后 durationMs 在 prepared 前为 0,Slider max=1 会让进度条停在最左,
   * 视觉上像"从头加载"。用 savedDurationMs 撑住,prepared 后被真实 durationMs 覆盖。
   */
  @Trace savedDurationMs: number = 0;
  @Trace speed: number = 1.0;
  @Trace accentColor: string = '#2A7C8C';
  @Trace ambientCover: string = '';
  @Trace ambientMainColor: string = '#2A7C8C';
  @Trace ambientTopColor: string = '#324B5F';
  @Trace ambientBottomColor: string = '#17191D';
  @Trace ambientLeftColor: string = '#2B5960';
  @Trace ambientRightColor: string = '#5F4330';
  @Trace ambientCenterColor: string = '#2A7C8C';
  @Trace ambientDarkColor: string = '#111315';
  @Trace hasAmbientColor: boolean = false;
  @Trace sleepMinutes: number = 0;
  @Trace sleepRemainingMs: number = 0;
  @Trace playMode: PlayMode = PlayMode.Sequence;

  reset(): void {
    this.currentBook = null;
    this.currentChapter = null;
    this.isPlaying = false;
    this.isLoading = false;
    this.progressMs = 0;
    this.durationMs = 0;
    this.savedDurationMs = 0;
    this.ambientCover = '';
    this.ambientMainColor = '#2A7C8C';
    this.ambientTopColor = '#324B5F';
    this.ambientBottomColor = '#17191D';
    this.ambientLeftColor = '#2B5960';
    this.ambientRightColor = '#5F4330';
    this.ambientCenterColor = '#2A7C8C';
    this.ambientDarkColor = '#111315';
    this.hasAmbientColor = false;
  }
}

export const PLAYER_STATE_KEY = 'global_player_state';
