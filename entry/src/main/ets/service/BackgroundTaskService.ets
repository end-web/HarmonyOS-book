import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_BgTask';

export class BackgroundTaskService {
  private static running: boolean = false;

  static async start(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundTaskService.running) return;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      BackgroundTaskService.running = true;
      hilog.info(DOMAIN, TAG, 'Background task started');
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  static async stop(context: common.UIAbilityContext): Promise<void> {
    if (!BackgroundTaskService.running) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundTaskService.running = false;
      hilog.info(DOMAIN, TAG, 'Background task stopped');
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  static isRunning(): boolean {
    return BackgroundTaskService.running;
  }
}
