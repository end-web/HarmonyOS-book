import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { PreferenceService } from '../service/PreferenceService';
import { WidgetUpdater, WIDGET_PLAYER } from '../service/WidgetUpdater';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_PlayerForm';

/**
 * 听书卡片 FormExtensionAbility:
 * - onAddForm: 必须同步返回初始 binding;真实快照通过 onUpdateForm 异步推送
 * - onRemoveForm: 从 preference 删除 formId
 * - onUpdateForm: 系统刷新触发,重新读快照
 */
export default class PlayerFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string ?? '';
    // 异步把 formId 入库 + 推真实快照(不阻塞返回)
    this.persistAndPushAsync(formId).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'persistAndPushAsync failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    // 初始空态字段必须与后续推送字段名/类型一致,避免 LocalStorageProp 类型不匹配
    const empty: Record<string, Object> = {
      'hasBook': 0,
      'bookId': '',
      'bookTitle': '没有正在播放的书',
      'author': '',
      'cover': '',
      'imgName': '',
      'chapterTitle': '点击挑一本',
      'isPlaying': 0,
      'bgColor': ''
    };
    return formBindingData.createFormBindingData(empty);
  }

  private async persistAndPushAsync(formId: string): Promise<void> {
    if (!formId) return;
    // FormExt 与主进程隔离,preferences 缓存不会跨进程同步,
    // 每次回调先抛掉本进程缓存重新打开,才能读到主进程最新写入的快照
    await PreferenceService.invalidateCache(this.context);
    await PreferenceService.init(this.context);
    WidgetUpdater.setContext(this.context);
    await PreferenceService.addWidgetFormId(WIDGET_PLAYER, formId);
    let snap = await PreferenceService.getWidgetPlayerSnapshot();
    if (!snap) {
      snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
    }
    if (!snap) return;
    try {
      await WidgetUpdater.pushPlayerSnapshotToForm(formId, snap);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'first push failed: %{public}s', e?.message ?? JSON.stringify(err));
    }
  }

  onRemoveForm(formId: string): void {
    PreferenceService.invalidateCache(this.context).then(() => {
      return PreferenceService.init(this.context);
    }).then(() => {
      return PreferenceService.removeWidgetFormId(WIDGET_PLAYER, formId);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'onRemoveForm failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onUpdateForm(formId: string, _wantParams?: Record<string, Object>): void {
    // 同 onAddForm:每次系统触发刷新前先抛掉本进程 preferences 缓存,
    // 否则 FormExt 复用 10s 内会一直读到陈旧的 isPlaying,卡片显示与主进程播放状态错位
    PreferenceService.invalidateCache(this.context).then(() => {
      return PreferenceService.init(this.context);
    }).then(async () => {
      WidgetUpdater.setContext(this.context);
      let snap = await PreferenceService.getWidgetPlayerSnapshot();
      if (!snap) {
        snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
      }
      if (!snap) return;
      await WidgetUpdater.pushPlayerSnapshotToForm(formId, snap);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'onUpdateForm failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onFormEvent(formId: string, message: string): void {
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
