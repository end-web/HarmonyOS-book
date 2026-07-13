import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DownloadNotification';
const NOTIFICATION_ID = 20260713;

export interface DownloadNotificationSummary {
  title: string;
  detail: string;
  progressPercent: number;
  status: 'downloading' | 'paused' | 'completed' | 'failed';
}

export class DownloadNotificationService {
  private static ctx: common.Context | null = null;
  private static permissionRequest: Promise<void> | null = null;
  private static slotSetup: Promise<void> | null = null;

  static setContext(ctx: common.Context): void {
    DownloadNotificationService.ctx = ctx;
  }

  static async requestPermission(): Promise<void> {
    try {
      if (await notificationManager.isNotificationEnabled()) return;
      if (!DownloadNotificationService.permissionRequest) {
        DownloadNotificationService.permissionRequest = DownloadNotificationService.requestPermissionInternal();
      }
      await DownloadNotificationService.permissionRequest;
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'request permission failed: %{public}s', e?.message ?? JSON.stringify(err));
    }
  }

  private static async requestPermissionInternal(): Promise<void> {
    const ctx = DownloadNotificationService.ctx as common.UIAbilityContext;
    if (ctx) await notificationManager.requestEnableNotification(ctx);
  }

  static async publish(summary: DownloadNotificationSummary): Promise<void> {
    try {
      if (!await notificationManager.isNotificationEnabled()) return;
      await DownloadNotificationService.ensureSlot();
      const progress = Math.max(0, Math.min(100, Math.round(summary.progressPercent)));
      const launchAgent = await DownloadNotificationService.createLaunchAgent();
      const request = DownloadNotificationService.createRequest(summary, progress, launchAgent);
      let supportsTemplate = false;
      try {
        supportsTemplate = await notificationManager.isSupportTemplate('downloadTemplate');
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'template check failed, using basic notification: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
      if (supportsTemplate) {
        const templateRequest = DownloadNotificationService.createRequest(summary, progress, launchAgent);
        templateRequest.template = {
          name: 'downloadTemplate',
          data: {
            title: summary.title as Object,
            fileName: summary.detail as Object,
            progressValue: progress as Object
          }
        };
        try {
          await notificationManager.publish(templateRequest);
          return;
        } catch (err) {
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'template publish failed, retrying basic notification: %{public}s',
            e?.message ?? JSON.stringify(err));
        }
      }
      await notificationManager.publish(request);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'publish failed: %{public}s', e?.message ?? JSON.stringify(err));
    }
  }

  private static createRequest(summary: DownloadNotificationSummary,
    progress: number, launchAgent?: WantAgent): notificationManager.NotificationRequest {
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isAlertOnce: true,
      tapDismissed: summary.status !== 'downloading',
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: summary.title,
          text: `${summary.detail} · ${progress}%`
        }
      }
    };
    if (launchAgent) request.wantAgent = launchAgent;
    if (summary.status === 'completed') request.autoDeletedTime = Date.now() + 5000;
    return request;
  }

  private static async createLaunchAgent(): Promise<WantAgent | undefined> {
    const ctx = DownloadNotificationService.ctx as common.UIAbilityContext;
    if (!ctx) return undefined;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name,
          parameters: {
            from: 'download_notification',
            target: 'downloads'
          }
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: NOTIFICATION_ID,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(wantAgentInfo);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'create launch agent failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      return undefined;
    }
  }

  private static async ensureSlot(): Promise<void> {
    if (!DownloadNotificationService.slotSetup) {
      DownloadNotificationService.slotSetup = DownloadNotificationService.setupSlot();
    }
    await DownloadNotificationService.slotSetup;
  }

  private static async setupSlot(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'add notification slot failed: %{public}s', e?.message ?? JSON.stringify(err));
    }
  }

  static async cancel(): Promise<void> {
    try {
      await notificationManager.cancel(NOTIFICATION_ID);
    } catch (_e) {
      // Notification may not exist or permission may be disabled.
    }
  }
}
