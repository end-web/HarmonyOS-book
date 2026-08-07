import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppBackupService } from '../service/AppBackupService';

const DOMAIN: number = 0xFF00;
const TAG: string = 'ListenBook_Backup';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    try {
      await AppBackupService.createSnapshot(this.context);
      hilog.info(DOMAIN, TAG, 'Backup snapshot created');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Create backup failed: %{public}s',
        error?.message ?? JSON.stringify(err));
      throw error;
    }
  }

  async onRestore(_bundleVersion: BundleVersion): Promise<void> {
    try {
      const restored = await AppBackupService.restoreSnapshot(this.context);
      hilog.info(DOMAIN, TAG, 'Restore snapshot result: %{public}s', restored ? 'restored' : 'empty');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Restore backup failed: %{public}s',
        error?.message ?? JSON.stringify(err));
      throw error;
    }
  }
}
