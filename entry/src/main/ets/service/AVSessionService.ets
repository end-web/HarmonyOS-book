import { avSession } from '@kit.AVSessionKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../model/Book';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_AVSession';

export interface AVSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onPlayNext: () => void;
  onPlayPrevious: () => void;
  onFastForward: (ms: number) => void;
  onRewind: (ms: number) => void;
  onSeek: (ms: number) => void;
  onSetSpeed: (speed: number) => void;
  onSetLoopMode: (mode: avSession.LoopMode) => void;
  onCollection: () => void;
}

const REWIND_INTERVAL_MS: number = 10000;
const FAST_FORWARD_INTERVAL_MS: number = 30000;
const SUPPORTED_PLAY_SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
const SUPPORTED_LOOP_MODES: avSession.LoopMode[] = [
  avSession.LoopMode.LOOP_MODE_SEQUENCE,
  avSession.LoopMode.LOOP_MODE_LIST,
  avSession.LoopMode.LOOP_MODE_SINGLE
];
const MEDIA_CENTER_CONTROLS: avSession.AVMediaCenterControlType[] = [
  'playPrevious',
  'playNext',
  'toggleFavorite',
  'setSpeed',
  'setLoopMode'
];

export class AVSessionService {
  private static instance: AVSessionService | null = null;
  private session: avSession.AVSession | null = null;
  private context: common.UIAbilityContext | null = null;
  private coverCache: Map<string, image.PixelMap> = new Map();
  private initPromise: Promise<void> | null = null;
  private currentBook: Book | null = null;
  private currentChapter: Chapter | null = null;
  private currentMediaImage: string | image.PixelMap | undefined;
  private onPlay: (() => void) | null = null;
  private onPause: (() => void) | null = null;
  private onPlayNext: (() => void) | null = null;
  private onPlayPrevious: (() => void) | null = null;
  private onFastForward: ((ms: number) => void) | null = null;
  private onRewind: ((ms: number) => void) | null = null;
  private onSeek: ((ms: number) => void) | null = null;
  private onSetSpeed: ((speed: number) => void) | null = null;
  private onSetLoopMode: ((mode: avSession.LoopMode) => void) | null = null;
  private onCollection: (() => void) | null = null;

  static getInstance(): AVSessionService {
    if (!AVSessionService.instance) {
      AVSessionService.instance = new AVSessionService();
    }
    return AVSessionService.instance;
  }

  setCallbacks(cbs: AVSessionCallbacks): void {
    this.onPlay = cbs.onPlay;
    this.onPause = cbs.onPause;
    this.onPlayNext = cbs.onPlayNext;
    this.onPlayPrevious = cbs.onPlayPrevious;
    this.onFastForward = cbs.onFastForward;
    this.onRewind = cbs.onRewind;
    this.onSeek = cbs.onSeek;
    this.onSetSpeed = cbs.onSetSpeed;
    this.onSetLoopMode = cbs.onSetLoopMode;
    this.onCollection = cbs.onCollection;
  }

  init(context: common.UIAbilityContext): Promise<void> {
    if (this.session) return Promise.resolve();
    if (this.initPromise) return this.initPromise;
    this.context = context;
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.UIAbilityContext): Promise<void> {
    try {
      this.session = await avSession.createAVSession(context, 'ListenBook', 'audio');
      this.registerCommands();
      await this.configureMediaCenter();
      await this.session.activate();
      await this.setupLaunchAbility(context);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'AVSession init failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      this.initPromise = null;
    }
  }

  private async ensureReady(): Promise<boolean> {
    if (this.session) return true;
    if (this.initPromise) {
      await this.initPromise;
    }
    return this.session !== null;
  }

  private async setupLaunchAbility(context: common.UIAbilityContext): Promise<void> {
    if (!this.session) return;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await this.session.setLaunchAbility(agent);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setLaunchAbility failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private registerCommands(): void {
    if (!this.session) return;
    this.session.on('play', () => {
      this.onPlay?.();
    });
    this.session.on('pause', () => {
      this.onPause?.();
    });
    this.session.on('playNext', () => {
      this.onPlayNext?.();
    });
    this.session.on('playPrevious', () => {
      this.onPlayPrevious?.();
    });
    this.session.on('fastForward', (time?: number) => {
      this.onFastForward?.(this.normalizeSkipTime(time, FAST_FORWARD_INTERVAL_MS));
    });
    this.session.on('rewind', (time?: number) => {
      this.onRewind?.(this.normalizeSkipTime(time, REWIND_INTERVAL_MS));
    });
    this.session.on('seek', (timeMs: number) => {
      this.onSeek?.(timeMs);
    });
    this.session.on('setSpeed', (speed: number) => {
      this.onSetSpeed?.(speed);
    });
    this.session.on('setLoopMode', (mode: avSession.LoopMode) => {
      this.onSetLoopMode?.(mode);
    });
    this.session.on('toggleFavorite', () => {
      this.onCollection?.();
    });
  }

  private async configureMediaCenter(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.setSupportedPlaySpeeds(SUPPORTED_PLAY_SPEEDS);
    } catch (err) {
      this.logMediaCenterWarning('setSupportedPlaySpeeds', err);
    }
    try {
      await this.session.setSupportedLoopModes(SUPPORTED_LOOP_MODES);
    } catch (err) {
      this.logMediaCenterWarning('setSupportedLoopModes', err);
    }
    try {
      await this.session.setMediaCenterControlType(MEDIA_CENTER_CONTROLS);
    } catch (err) {
      this.logMediaCenterWarning('setMediaCenterControlType', err);
    }
  }

  async updateLoopMode(mode: avSession.LoopMode): Promise<void> {
    if (!await this.ensureReady() || !this.session) return;
    const playbackState: avSession.AVPlaybackState = { loopMode: mode };
    try {
      await this.session.setAVPlaybackState(playbackState);
    } catch (err) {
      this.logMediaCenterWarning('setAVPlaybackState.loopMode', err);
    }
  }

  private logMediaCenterWarning(operation: string, err: Object): void {
    const error = err as Error;
    hilog.warn(DOMAIN, TAG, '%{public}s failed: %{public}s', operation,
      error?.message ?? JSON.stringify(err));
  }

  private normalizeSkipTime(time: number | undefined, fallbackMs: number): number {
    if (time === undefined || !Number.isFinite(time) || time <= 0) return fallbackMs;
    return time;
  }

  async updateMetadata(book: Book, chapter: Chapter): Promise<void> {
    if (!await this.ensureReady() || !this.session) return;
    // mediaImage 只能传 PixelMap 或 http(s) URL;沙箱路径/rawfile 名称对 AVSession 服务不可读,
    // 必须先 decode 成 PixelMap,否则会触发 "get metaData failed"。
    let mediaImage: string | image.PixelMap | undefined;
    if (book.cover) {
      const pixelMap = await this.loadCover(book.cover);
      if (pixelMap) {
        mediaImage = pixelMap;
      } else if (book.cover.startsWith('http://') || book.cover.startsWith('https://')) {
        mediaImage = book.cover;
      } else {
        hilog.warn(DOMAIN, TAG, 'updateMetadata cover decode failed, mediaImage=undefined');
      }
    }
    this.currentBook = book;
    this.currentChapter = chapter;
    this.currentMediaImage = mediaImage;
    const metadata: avSession.AVMetadata = {
      assetId: `${book.id}_${chapter.id}`,
      title: chapter.title,
      artist: book.title,
      author: book.author,
      duration: chapter.duration > 0 ? chapter.duration * 1000 : undefined,
      mediaImage: mediaImage,
    };
    try {
      await this.session.setAVMetadata(metadata);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setAVMetadata failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      try {
        const fallback: avSession.AVMetadata = {
          assetId: `${book.id}_${chapter.id}`,
          title: chapter.title,
          artist: book.title,
        };
        await this.session.setAVMetadata(fallback);
      } catch (err2) {
        const e2 = err2 as Error;
        hilog.error(DOMAIN, TAG, 'setAVMetadata fallback also failed: %{public}s',
          e2?.message ?? JSON.stringify(err2));
      }
    }
  }

  /** AVPlayer prepared 后用真实 duration 刷新元数据,供胶囊/控制中心显示总时长 */
  async updateMetadataDuration(durationMs: number): Promise<void> {
    if (!await this.ensureReady() || !this.session) return;
    if (!this.currentBook || !this.currentChapter) return;
    if (durationMs <= 0) return;
    const book = this.currentBook;
    const chapter = this.currentChapter;
    const metadata: avSession.AVMetadata = {
      assetId: `${book.id}_${chapter.id}`,
      title: chapter.title,
      artist: book.title,
      author: book.author,
      duration: durationMs,
      mediaImage: this.currentMediaImage,
    };
    try {
      await this.session.setAVMetadata(metadata);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'updateMetadataDuration failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  async updatePlaybackState(isPlaying: boolean, progressMs: number, speed: number,
    durationMs: number, isFavorite: boolean = false): Promise<void> {
    if (!await this.ensureReady() || !this.session) return;
    let state: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    if (isPlaying) {
      state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    const playbackState: avSession.AVPlaybackState = {
      state: state,
      speed: speed,
      position: {
        elapsedTime: progressMs,
        updateTime: Date.now()
      },
      duration: durationMs > 0 ? durationMs : undefined,
      isFavorite: isFavorite
    };
    try {
      await this.session.setAVPlaybackState(playbackState);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setAVPlaybackState failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private async loadCover(cover: string): Promise<image.PixelMap | null> {
    if (this.coverCache.has(cover)) {
      return this.coverCache.get(cover)!;
    }
    try {
      let pixelMap: image.PixelMap | null = null;
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        pixelMap = await this.loadNetworkCover(cover);
      } else if (this.context) {
        pixelMap = await this.loadLocalCover(cover);
      }
      if (pixelMap) {
        if (this.coverCache.size > 20) {
          const firstKey: string | undefined = this.coverCache.keys().next().value;
          if (firstKey !== undefined) {
            const old = this.coverCache.get(firstKey);
            old?.release();
            this.coverCache.delete(firstKey);
          }
        }
        this.coverCache.set(cover, pixelMap);
      }
      return pixelMap;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadCover failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      return null;
    }
  }

  private async loadNetworkCover(url: string): Promise<image.PixelMap | null> {
    const httpClient = http.createHttp();
    try {
      const resp = await httpClient.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (resp.responseCode === 200 && resp.result) {
        const buf = resp.result as ArrayBuffer;
        const source = image.createImageSource(buf);
        const opts: image.DecodingOptions = {
          desiredSize: { width: 512, height: 512 }
        };
        const pixelMap = await source.createPixelMap(opts);
        source.release();
        return pixelMap;
      }
    } finally {
      httpClient.destroy();
    }
    return null;
  }

  private async loadLocalCover(path: string): Promise<image.PixelMap | null> {
    if (!this.context) return null;
    // 沙箱绝对路径:走 fileIo 读字节再 decode,createImageSource 对沙箱路径不稳定
    if (path.startsWith('/')) {
      try {
        const f = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
        try {
          const stat = await fileIo.stat(f.fd);
          if (stat.size <= 0) {
            return null;
          }
          const buf = new ArrayBuffer(stat.size);
          await fileIo.read(f.fd, buf);
          const source = image.createImageSource(buf);
          const opts: image.DecodingOptions = {
            desiredSize: { width: 512, height: 512 }
          };
          const pixelMap = await source.createPixelMap(opts);
          source.release();
          return pixelMap;
        } finally {
          await fileIo.close(f);
        }
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'loadLocalCover sandbox path failed: %{public}s',
          e?.message ?? JSON.stringify(err));
        return null;
      }
    }
    // rawfile 路径
    try {
      const rawData = await this.context.resourceManager.getRawFileContent(path);
      const buf = rawData.buffer as ArrayBuffer;
      const source = image.createImageSource(buf);
      const opts: image.DecodingOptions = {
        desiredSize: { width: 512, height: 512 }
      };
      const pixelMap = await source.createPixelMap(opts);
      source.release();
      return pixelMap;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadLocalCover rawfile failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      return null;
    }
  }

  /** 暂时停用 session（不销毁），控制中心不再显示播控卡片 */
  async deactivate(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.deactivate();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'deactivate failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /** 重新激活已 deactivate 的 session */
  async reactivate(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.activate();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'reactivate failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  async destroy(): Promise<void> {
    if (this.session) {
      try {
        await this.session.deactivate();
        await this.session.destroy();
      } catch (_e) { /* ignore */ }
      this.session = null;
    }
    this.coverCache.forEach((pm) => {
      pm.release();
    });
    this.coverCache.clear();
    // 重置单例状态，让下次 getInstance() 创建全新实例
    this.context = null;
    this.initPromise = null;
    this.currentBook = null;
    this.currentChapter = null;
    this.currentMediaImage = undefined;
    this.onPlay = null;
    this.onPause = null;
    this.onPlayNext = null;
    this.onPlayPrevious = null;
    this.onFastForward = null;
    this.onRewind = null;
    this.onSeek = null;
    AVSessionService.instance = null;
  }
}
