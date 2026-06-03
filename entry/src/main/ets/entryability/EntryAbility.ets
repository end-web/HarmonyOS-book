import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, AppStorageV2 } from '@kit.ArkUI';
import { rpc } from '@kit.IPCKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { WidgetUpdater } from '../service/WidgetUpdater';
import { DataService } from '../service/DataService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { registerBuiltInSources } from '../service/builtin';

const DOMAIN = 0x0000;
const TAG = 'ListenBook';

/** 卡片 -> EntryAbility 的路由参数,通过 AppStorage + emitter 透传给 Index 页 */
export const KEY_WIDGET_ROUTE = 'widget_route_pending';
export const EVT_WIDGET_ROUTE = 'app.widget.route';

export interface WidgetRoute {
  target: string;
  bookId?: string;
  ts: number;
}

/** call 事件 RPC 返回的占位 Parcelable(必须返回,否则发送方会异常) */
class AckParcelable implements rpc.Parcelable {
  marshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.writeInt(1);
    return true;
  }
  unmarshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.readInt();
    return true;
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    WidgetUpdater.setContext(this.context);
    // 注册内置源（与用户订阅源同列出现）
    registerBuiltInSources();
    // 章节音频文件缓存的沙箱根目录
    ChapterCacheService.getInstance().setContext(this.context);
    PreferenceService.init(this.context).then(async () => {
      this.restoreColorMode();
      const preloadCount = await PreferenceService.getPreloadChapters();
      ChapterCacheService.getInstance().setPreloadCount(preloadCount);
      // 提前把 PlayerState 还原到全局 AppStorage,这样卡片 call 进来时
      // AudioService 已经有 currentBook/Chapter,play() 才能正常工作
      await this.bootstrapAudioService();
      // 启动时把 lastPlayed 推一份到卡片,避免冷启动卡片显示空态。
      // 这里(主进程)允许写回 preferences,FormExt 那边的 seed 路径只在内存里用,不写盘
      const snap = await WidgetUpdater.seedAndPersistFromLastPlayed();
      if (snap) {
        await WidgetUpdater.pushSnapshotToCards();
      }
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'PreferenceService init failed: %{public}s', JSON.stringify(err));
    });
    this.registerCallee();
    this.consumeWidgetWant(want);
  }

  /** 卡片 router 跳转 / 已存活时的拉起,统一在 onNewWant 处理 */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.consumeWidgetWant(want);
  }

  /**
   * 卡片可能在 PlayerPage 没打开过的情况下就发 call 事件,
   * 此时 AudioService 还没 bind state,play() 就是 no-op。
   * 这里在 EntryAbility 启动时就把 lastPlayed 还原到全局 PlayerState,
   * 并 bind 给 AudioService,让卡片冷启动也能直接续播。
   */
  private async bootstrapAudioService(): Promise<void> {
    try {
      const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
      AudioService.getInstance().bind(state, this.context);
      // 已经有书就不覆盖(用户已在 App 内播放过)
      if (state.currentBook && state.currentChapter) return;
      const last = await PreferenceService.getLastPlayed();
      if (!last) return;
      const book = await DataService.getBookById(this.context, last.bookId);
      if (!book || !book.chapters || book.chapters.length === 0) return;
      const chapter = book.chapters.find((c) => c.id === last.chapterId)
        ?? (last.chapterTitle ? book.chapters.find((c) => c.title === last.chapterTitle) : undefined);
      if (!chapter) return;
      state.currentBook = book;
      state.currentChapter = chapter;
      state.progressMs = last.progressMs;
      state.durationMs = last.durationMs ?? 0;
      state.isPlaying = false;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'bootstrapAudioService failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    } finally {
      // 不管 lastPlayed 有没有恢复都要 markReady，否则 callee 会一直等
      AudioService.getInstance().markReady();
    }
  }

  private consumeWidgetWant(want: Want): void {
    const params = want.parameters;
    if (!params) return;
    const from = params['from'] as string | undefined;
    if (from !== 'widget') return;
    const target = (params['target'] as string | undefined) ?? 'home';
    const bookId = params['bookId'] as string | undefined;
    const route: WidgetRoute = { target, bookId, ts: Date.now() };
    AppStorage.setOrCreate<WidgetRoute>(KEY_WIDGET_ROUTE, route);
    emitter.emit(EVT_WIDGET_ROUTE, { data: { target, bookId: bookId ?? '', ts: route.ts } });
    hilog.info(DOMAIN, TAG, 'widget route -> target=%{public}s bookId=%{public}s ts=%{public}d',
      target, bookId ?? '', route.ts);
  }

  private registerCallee(): void {
    try {
      this.callee.on('play', (_data: rpc.MessageSequence) => {
        hilog.info(DOMAIN, TAG, 'callee play');
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().play();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee play failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('pause', (_data: rpc.MessageSequence) => {
        hilog.info(DOMAIN, TAG, 'callee pause');
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().pause();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee pause failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('next', (_data: rpc.MessageSequence) => {
        hilog.info(DOMAIN, TAG, 'callee next');
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().playNext();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee next failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('prev', (_data: rpc.MessageSequence) => {
        hilog.info(DOMAIN, TAG, 'callee prev');
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().playPrevious();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee prev failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'registerCallee failed: code=%{public}d msg=%{public}s',
        e?.code ?? 0, e?.message ?? '');
    }
  }

  private async restoreColorMode(): Promise<void> {
    const mode = await PreferenceService.getColorMode();
    if (mode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      try {
        this.context.getApplicationContext().setColorMode(mode);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Restore colorMode failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  onDestroy(): void {
    try {
      this.callee.off('play');
      this.callee.off('pause');
      this.callee.off('next');
      this.callee.off('prev');
    } catch (_e) { /* ignore */ }
    AudioService.getInstance().release().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'AudioService release failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    WindowUtils.setupImmersive(windowStage, this.context.config.colorMode).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Immersive setup failed: %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  /** 系统深浅色切换时,同步状态栏字色,避免深色模式下黑字看不见 */
  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      WindowUtils.updateColorMode(newConfig.colorMode);
    }
  }

  onWindowStageDestroy(): void {
  }

  /**
   * 退后台时立即把进度落盘:鸿蒙官方建议在 onBackground 主动 flush,
   * 避免被系统强杀前丢掉最近 5s tick 之间的进度。
   */
  async onBackground(): Promise<void> {
    try {
      await AudioService.getInstance().flushHistory();
      hilog.info(DOMAIN, TAG, 'onBackground flushHistory done');
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'onBackground flushHistory failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /**
   * 回前台时校准 AVPlayer 健康度。
   * 退后台 + paused 后,系统可能在 1~2s 内回收 audio renderer,把 player 带到 idle
   * 但 fdSrc/url 已失效——再点播放就只能干等。这里主动 reset 到干净 idle,
   * 让用户点 ▶ 时 doPlayChapter 能走完整的 reset → applySource 路径。
   */
  async onForeground(): Promise<void> {
    try {
      await AudioService.getInstance().ensureHealthy();
      hilog.info(DOMAIN, TAG, 'onForeground ensureHealthy done');
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'onForeground ensureHealthy failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }
}
