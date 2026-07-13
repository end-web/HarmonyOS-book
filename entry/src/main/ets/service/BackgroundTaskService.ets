import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_BgTask';
const AUDIO_MODE = 'audioPlayback';
const DATA_TRANSFER_MODE = 'dataTransfer';
/** 系统取消/挂起后最短重申间隔，避免 tight loop */
const REASSERT_MIN_INTERVAL_MS = 1500;

export class BackgroundTaskService {
  private static running: boolean = false;
  private static requestedModes: Set<string> = new Set();
  private static syncPromise: Promise<void> = Promise.resolve();
  private static context: common.UIAbilityContext | null = null;
  private static listenersBound: boolean = false;
  private static lastReassertAt: number = 0;
  private static reassertTimer: number = -1;

  private static readonly onCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    const reason = info?.reason ?? -1;
    hilog.warn(DOMAIN, TAG, 'continuousTaskCancel id=%{public}d reason=%{public}d modes=%{public}s',
      info?.id ?? -1, reason, BackgroundTaskService.modeSnapshot());
    // 系统已取消长时任务，本地必须立刻认为未在跑，否则后续只会走 update 失败路径
    BackgroundTaskService.running = false;
    BackgroundTaskService.scheduleReassert('cancel');
  };

  private static readonly onSuspend = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    const reason = info?.suspendReason ?? -1;
    hilog.warn(DOMAIN, TAG, 'continuousTaskSuspend id=%{public}d reason=%{public}d modes=%{public}s',
      info?.continuousTaskId ?? -1, reason, BackgroundTaskService.modeSnapshot());
    // 挂起后进程可能被冻结；标记未运行并尝试重申，尤其 dataTransfer 低速场景
    BackgroundTaskService.running = false;
    BackgroundTaskService.scheduleReassert('suspend');
  };

  private static readonly onActive = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    hilog.info(DOMAIN, TAG, 'continuousTaskActive id=%{public}d modes=%{public}s',
      info?.id ?? -1, BackgroundTaskService.modeSnapshot());
    if (BackgroundTaskService.requestedModes.size > 0) {
      BackgroundTaskService.running = true;
    }
  };

  static start(context: common.UIAbilityContext): Promise<void> {
    return BackgroundTaskService.setMode(context, AUDIO_MODE, true);
  }

  static stop(context: common.UIAbilityContext): Promise<void> {
    return BackgroundTaskService.setMode(context, AUDIO_MODE, false);
  }

  static startDataTransfer(context: common.UIAbilityContext): Promise<void> {
    return BackgroundTaskService.setMode(context, DATA_TRANSFER_MODE, true);
  }

  static stopDataTransfer(context: common.UIAbilityContext): Promise<void> {
    return BackgroundTaskService.setMode(context, DATA_TRANSFER_MODE, false);
  }

  /**
   * 下载仍有进度/队列时调用：若长时任务已被系统取消，重新申请。
   * 失败只记日志，不抛到业务层。
   */
  static ensure(context?: common.UIAbilityContext | null): Promise<void> {
    if (context) BackgroundTaskService.context = context;
    const ctx = BackgroundTaskService.context;
    if (!ctx || BackgroundTaskService.requestedModes.size === 0) return Promise.resolve();
    if (BackgroundTaskService.running) return Promise.resolve();
    return BackgroundTaskService.queueSync(ctx);
  }

  static isRunning(): boolean {
    return BackgroundTaskService.running;
  }

  static hasMode(mode: string): boolean {
    return BackgroundTaskService.requestedModes.has(mode);
  }

  private static setMode(context: common.UIAbilityContext, mode: string, enabled: boolean): Promise<void> {
    BackgroundTaskService.context = context;
    BackgroundTaskService.bindListeners();
    if (enabled) {
      BackgroundTaskService.requestedModes.add(mode);
    } else {
      BackgroundTaskService.requestedModes.delete(mode);
    }
    return BackgroundTaskService.queueSync(context);
  }

  private static queueSync(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.syncPromise = BackgroundTaskService.syncPromise.then(async (): Promise<void> => {
      await BackgroundTaskService.sync(context);
    }).catch((err: Error): void => {
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    return BackgroundTaskService.syncPromise;
  }

  private static bindListeners(): void {
    if (BackgroundTaskService.listenersBound) return;
    BackgroundTaskService.listenersBound = true;
    try {
      backgroundTaskManager.on('continuousTaskCancel', BackgroundTaskService.onCancel);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskCancel failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    try {
      backgroundTaskManager.on('continuousTaskSuspend', BackgroundTaskService.onSuspend);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskSuspend failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    try {
      backgroundTaskManager.on('continuousTaskActive', BackgroundTaskService.onActive);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskActive failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private static scheduleReassert(from: string): void {
    if (BackgroundTaskService.requestedModes.size === 0) return;
    const ctx = BackgroundTaskService.context;
    if (!ctx) return;
    const now = Date.now();
    const wait = Math.max(0, REASSERT_MIN_INTERVAL_MS - (now - BackgroundTaskService.lastReassertAt));
    if (BackgroundTaskService.reassertTimer >= 0) {
      clearTimeout(BackgroundTaskService.reassertTimer);
      BackgroundTaskService.reassertTimer = -1;
    }
    BackgroundTaskService.reassertTimer = setTimeout((): void => {
      BackgroundTaskService.reassertTimer = -1;
      BackgroundTaskService.lastReassertAt = Date.now();
      hilog.info(DOMAIN, TAG, 'reassert continuous task from %{public}s modes=%{public}s',
        from, BackgroundTaskService.modeSnapshot());
      BackgroundTaskService.queueSync(ctx).catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, 'reassert failed: %{public}s', err?.message ?? JSON.stringify(err));
      });
    }, wait) as number;
  }

  private static modeSnapshot(): string {
    return Array.from(BackgroundTaskService.requestedModes).join(',');
  }

  private static async sync(context: common.UIAbilityContext): Promise<void> {
    const modes: string[] = Array.from(BackgroundTaskService.requestedModes);
    try {
      if (modes.length === 0) {
        if (!BackgroundTaskService.running) return;
        try {
          await backgroundTaskManager.stopBackgroundRunning(context);
        } catch (err) {
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning: %{public}s',
            e?.message ?? JSON.stringify(err));
        }
        BackgroundTaskService.running = false;
        return;
      }

      if (BackgroundTaskService.running) {
        try {
          await backgroundTaskManager.updateBackgroundRunning(context, modes);
          hilog.info(DOMAIN, TAG, 'updateBackgroundRunning ok modes=%{public}s', modes.join(','));
          return;
        } catch (err) {
          // update 失败多半是任务已被系统取消，回退到重新 start
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'updateBackgroundRunning failed, fallback start: %{public}s',
            e?.message ?? JSON.stringify(err));
          BackgroundTaskService.running = false;
        }
      }

      await BackgroundTaskService.startRunning(context, modes);
    } catch (err) {
      BackgroundTaskService.running = false;
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s modes=%{public}s',
        e?.message ?? JSON.stringify(err), modes.join(','));
    }
  }

  private static async startRunning(context: common.UIAbilityContext, modes: string[]): Promise<void> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: {
          from: 'continuous_task'
        }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent = await wantAgent.getWantAgent(wantAgentInfo);
    await backgroundTaskManager.startBackgroundRunning(context, modes, agent);
    BackgroundTaskService.running = true;
    hilog.info(DOMAIN, TAG, 'startBackgroundRunning ok modes=%{public}s', modes.join(','));
  }
}
