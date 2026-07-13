import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_BgTask';
const AUDIO_MODE = 'audioPlayback';
const DATA_TRANSFER_MODE = 'dataTransfer';

export class BackgroundTaskService {
  private static running: boolean = false;
  private static requestedModes: Set<string> = new Set();
  private static syncPromise: Promise<void> = Promise.resolve();

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

  static isRunning(): boolean {
    return BackgroundTaskService.running;
  }

  private static setMode(context: common.UIAbilityContext, mode: string, enabled: boolean): Promise<void> {
    if (enabled) {
      BackgroundTaskService.requestedModes.add(mode);
    } else {
      BackgroundTaskService.requestedModes.delete(mode);
    }
    BackgroundTaskService.syncPromise = BackgroundTaskService.syncPromise.then(async (): Promise<void> => {
      await BackgroundTaskService.sync(context);
    }).catch((err: Error): void => {
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    return BackgroundTaskService.syncPromise;
  }

  private static async sync(context: common.UIAbilityContext): Promise<void> {
    try {
      const modes: string[] = Array.from(BackgroundTaskService.requestedModes);
      if (modes.length === 0) {
        if (!BackgroundTaskService.running) return;
        await backgroundTaskManager.stopBackgroundRunning(context);
        BackgroundTaskService.running = false;
        return;
      }
      if (BackgroundTaskService.running) {
        await backgroundTaskManager.updateBackgroundRunning(context, modes);
        return;
      }
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
      await backgroundTaskManager.startBackgroundRunning(context, modes, agent);
      BackgroundTaskService.running = true;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }
}
