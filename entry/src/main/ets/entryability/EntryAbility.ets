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
import { StatsService } from '../service/StatsService';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { registerBuiltInSources } from '../service/builtin';
import { SourceVariableStore } from '../service/SourceVariableStore';
import { getCacheService } from '../service/CacheService';
import { JavaBridgeImpl } from '../service/rule/JavaBridge';
import { deviceInfo } from '@kit.BasicServicesKit';

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
    // 缓存书改用文件持久化,注入 context 供 filesDir 读写
    DataService.setContext(this.context);

    // 关键修复:限时初始化,避免后台恢复时阻塞过久导致系统 watchdog 杀进程
    this.initServicesWithTimeout().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Service initialization failed: %{public}s', err?.message ?? JSON.stringify(err));
      // 即使失败也要 markReady,避免 callee 永久等待
      AudioService.getInstance().markReady();
    });

    this.registerCallee();
    this.consumeWidgetWant(want);
  }

  /**
   * 带超时保护的服务初始化。
   * 从状态栏/小组件唤起时,系统期望快速响应。
   * 如果初始化超过 5s,放弃恢复上次播放状态,但仍标记 ready,避免卡死。
   */
  private async initServicesWithTimeout(): Promise<void> {
    const INIT_TIMEOUT_MS = 5000;
    const timeoutPromise = new Promise<void>((_, reject) => {
      setTimeout(() => reject(new Error('Initialization timeout')), INIT_TIMEOUT_MS);
    });

    try {
      await Promise.race([
        this.initServicesCore(),
        timeoutPromise
      ]);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'Init services timeout or failed: %{public}s', e?.message ?? '');
      // 注意:bootstrapAudioService 的 finally 块已保证 markReady() 被调用,
      // 这里无需重复调用。但为防止 initServicesCore 在超时前就失败(未进入 bootstrap),
      // 仍需确保 markReady 至少被调用一次
      // TODO: 更优雅的方案是让 AudioService.markReady() 具有幂等性
    }
  }

  private async initServicesCore(): Promise<void> {
    const startTime = Date.now();
    hilog.info(DOMAIN, TAG, 'initServicesCore: start');

    await PreferenceService.init(this.context);
    hilog.info(DOMAIN, TAG, 'initServicesCore: PreferenceService ready, elapsed=%{public}dms', Date.now() - startTime);

    try {
      await StatsService.init(this.context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'StatsService init failed: %{public}s', JSON.stringify(e));
    }

    this.restoreColorMode();
    // 初始化源变量存储和缓存服务
    try {
      await SourceVariableStore.init(this.context);
      const cacheService = getCacheService();
      await cacheService.init(this.context);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'SourceVariableStore/CacheService init failed: %{public}s', JSON.stringify(e));
    }
    // 设置设备标识（用于 java.androidId()）
    try {
      JavaBridgeImpl.setDeviceId(deviceInfo.ODID || '');
    } catch {
      // ignore
    }
    const preloadCount = await PreferenceService.getPreloadChapters();
    ChapterCacheService.getInstance().setPreloadCount(preloadCount);
    // 提前把 PlayerState 还原到全局 AppStorage,这样卡片 call 进来时
    // AudioService 已经有 currentBook/Chapter,play() 才能正常工作
    await this.bootstrapAudioService();
    hilog.info(DOMAIN, TAG, 'initServicesCore: AudioService bootstrapped, elapsed=%{public}dms', Date.now() - startTime);

    // 启动时把 lastPlayed 推一份到卡片,避免冷启动卡片显示空态。
    // 这里(主进程)允许写回 preferences,FormExt 那边的 seed 路径只在内存里用,不写盘
    const snap = await WidgetUpdater.seedAndPersistFromLastPlayed();
    if (snap) {
      await WidgetUpdater.pushSnapshotToCards();
    }

    hilog.info(DOMAIN, TAG, 'initServicesCore: complete, total=%{public}dms', Date.now() - startTime);
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
   *
   * 关键:无论成功失败都必须调 markReady(),否则 callee 会永久等待导致卡死。
   */
  private async bootstrapAudioService(): Promise<void> {
    const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
    AudioService.getInstance().bind(state, this.context);

    try {
      // 已经有书就不覆盖(用户已在 App 内播放过)
      if (state.currentBook && state.currentChapter) {
        return;
      }

      // 防御:如果 PreferenceService 初始化超时,getLastPlayed 会抛异常,提前检查避免错误日志泛滥
      // 这种情况下放弃恢复上次播放,但仍让 AudioService 处于可用状态(用户可手动选书)
      try {
        const last = await PreferenceService.getLastPlayed();
        if (!last) {
          return;
        }

        // 防御:getBookById 可能因为文件损坏/过大而失败,加超时保护
        const book = await Promise.race([
          DataService.getBookById(this.context, last.bookId),
          new Promise<undefined>((res) => setTimeout(() => res(undefined), 2000))
        ]);

        if (!book || !book.chapters || book.chapters.length === 0) {
          return;
        }

        const chapter = book.chapters.find((c) => c.id === last.chapterId)
          ?? (last.chapterTitle ? book.chapters.find((c) => c.title === last.chapterTitle) : undefined);
        if (!chapter) {
          return;
        }

        // 独立 KV 为权威:贴回跳过头尾,纠正冷启动缓存书壳可能丢失的 skip
        // (放在赋值前,让 checkSkipOutro / skipIntro 首次起播就用到正确值)
        await PreferenceService.applySkipConfig(book);
        state.currentBook = book;
        state.currentChapter = chapter;
        state.progressMs = last.progressMs;
        state.durationMs = last.durationMs ?? 0;
        const progress = await PreferenceService.getProgress(last.bookId);
        state.speed = this.normalizeSpeed(progress?.speed ?? last.speed);
        state.isPlaying = false;
      } catch (prefErr) {
        // PreferenceService 未就绪或读取失败,记录但不影响 AudioService 启动
        const e = prefErr as Error;
        hilog.warn(DOMAIN, TAG, 'bootstrapAudioService: restore lastPlayed failed: %{public}s',
          e?.message ?? JSON.stringify(prefErr));
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'bootstrapAudioService failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    } finally {
      // 不管 lastPlayed 有没有恢复都要 markReady，否则 callee 会一直等
      AudioService.getInstance().markReady();
    }
  }

  private normalizeSpeed(speed: number | undefined): number {
    if (speed === undefined || !Number.isFinite(speed) || speed <= 0) return 1.0;
    return Math.min(4.0, Math.max(0.125, speed));
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
  }

  private registerCallee(): void {
    try {
      this.callee.on('play', (_data: rpc.MessageSequence) => {
        // 乐观更新:立即翻转卡片图标，不等 AVPlayer
        WidgetUpdater.optimisticSetPlaying(true).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'optimistic play push failed: %{public}s', err?.message ?? '');
        });
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().play();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee play failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('pause', (_data: rpc.MessageSequence) => {
        // 乐观更新:立即翻转卡片图标，不等 AVPlayer
        WidgetUpdater.optimisticSetPlaying(false).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'optimistic pause push failed: %{public}s', err?.message ?? '');
        });
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().pause();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee pause failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('next', (_data: rpc.MessageSequence) => {
        AudioService.getInstance().whenReady().then(() => {
          return AudioService.getInstance().playNext();
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee next failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('prev', (_data: rpc.MessageSequence) => {
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

  async onDestroy(): Promise<void> {
    try {
      this.callee.off('play');
      this.callee.off('pause');
      this.callee.off('next');
      this.callee.off('prev');
    } catch (_e) { /* ignore */ }
    try {
      await AudioService.getInstance().release();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AudioService release failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
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
   *
   * 关键:从状态栏/小组件唤起时 onForeground 可能比 onCreate 的异步初始化早执行,
   * 此时 AudioService 还没 bind,必须先 whenReady 再调 ensureHealthy,
   * 否则会访问到未初始化的 player 触发崩溃。
   */
  async onForeground(): Promise<void> {
    try {
      // 等待 bootstrapAudioService 完成(带超时保护,避免初始化卡死时永久阻塞前台回调)
      // 超时设为 5 秒,与 onCreate 的总超时时间对齐,避免初始化刚好超时时这里也超时
      await AudioService.getInstance().whenReady(5000);
      await AudioService.getInstance().ensureHealthy();
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'onForeground ensureHealthy failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }
}
