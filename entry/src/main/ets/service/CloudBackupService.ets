import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AuthService } from './AuthService';
import { AppBackupService, AppBackupSnapshot } from './AppBackupService';

export enum CloudBackupErrorCode {
  UNAVAILABLE = 1,
  NETWORK,
  BATTERY,
  CLOUD_FULL,
  LOCAL_FULL,
  HOT,
  SERVER,
  TIMEOUT,
  CANCELLED,
  ACCOUNT_CHANGED,
  NO_BACKUP,
  INVALID_BACKUP,
  LOCAL_FAILURE,
  RESTORE_FAILED
}

export class CloudBackupError extends Error {
  code: CloudBackupErrorCode;

  constructor(code: CloudBackupErrorCode) {
    super('Cloud backup operation failed');
    this.code = code;
  }
}

export enum CloudBackupPhase {
  IDLE = 0,
  PREPARING,
  SYNCING,
  DOWNLOADING,
  CONFIRMING,
  RESTORING
}

export class CloudBackupInfo {
  exportedAt: number = 0;
  bookCount: number = 0;
  sourceCount: number = 0;

  constructor(snapshot: AppBackupSnapshot) {
    this.exportedAt = snapshot.exportedAt;
    this.bookCount = snapshot.preferences.favorites.length;
    this.sourceCount = snapshot.ruleSources?.length ?? 0;
  }
}

const SYNC_TIMEOUT_MS: number = 120000;
const MAX_BACKUP_BYTES: number = 32 * 1024 * 1024;
// Stat.location 是位标记：1 本地、2 云端、3 两者都有（API 11 起）。
const LOCATION_CLOUD: number = 2;
const LOCATION_LOCAL_AND_CLOUD: number = 3;

/** 使用系统账号的应用云文件目录；不依赖开发者云存储、密钥或业务服务器。 */
@ObservedV2
export class CloudBackupService {
  private static singleton: CloudBackupService = new CloudBackupService();

  static get instance(): CloudBackupService {
    return CloudBackupService.singleton;
  }

  @Trace busy: boolean = false;
  @Trace phase: CloudBackupPhase = CloudBackupPhase.IDLE;
  @Trace lastBackupAt: number = 0;
  private cancelled: boolean = false;
  private cancelTransfer: (() => void) | null = null;

  /** 只读取已经同步成功的本地元数据，进入页面不会自动上传用户数据。 */
  async refresh(context: common.Context): Promise<void> {
    if (this.busy) return;
    this.lastBackupAt = 0;
    const accountId = AuthService.instance.openID;
    if (!AuthService.instance.isLoggedIn || !accountId) return;
    try {
      const path = await this.cloudPath(context, accountId);
      if (!await fileIo.access(path)) return;
      const stat = await fileIo.stat(path);
      const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(path));
      if (stat.location !== LOCATION_LOCAL_AND_CLOUD ||
        (state !== cloudSync.FileState.UPLOAD_SUCCESS && state !== cloudSync.FileState.INITIAL_AFTER_DOWNLOAD)) return;
      const snapshot = await AppBackupService.readSnapshot(path);
      if (!this.busy && AuthService.instance.openID === accountId && AuthService.instance.isLoggedIn) {
        this.lastBackupAt = snapshot.exportedAt;
      }
    } catch (_error) { /* 云空间未就绪或本机尚无该备份时保持未知，手动操作会给出具体错误。 */ }
  }

  async backup(context: common.Context): Promise<void> {
    const accountId = this.begin();
    const staging = `${context.cacheDir}/cloud_backup_upload.json`;
    try {
      await this.assertAccount(context, accountId);
      const path = await this.cloudPath(context, accountId);
      // 先检查云服务可用性，再生成、放入用户明确要求上传的快照。
      await this.sync(context, accountId);
      this.phase = CloudBackupPhase.PREPARING;
      await AppBackupService.createSnapshot(context, staging, true);
      const snapshot = await AppBackupService.readSnapshot(staging);
      await this.assertAccount(context, accountId);
      await fileIo.copyFile(staging, `${path}.pending`);
      await this.assertAccount(context, accountId);
      await fileIo.moveFile(`${path}.pending`, path);
      await this.sync(context, accountId);
      await this.assertAccount(context, accountId);
      // FileSync.start 仅触发同步；完成事件后还要核对本次文件已上传。
      if (cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(path)) !== cloudSync.FileState.UPLOAD_SUCCESS) {
        throw new CloudBackupError(CloudBackupErrorCode.SERVER);
      }
      this.lastBackupAt = snapshot.exportedAt;
    } catch (error) {
      throw this.normalizeError(error);
    } finally {
      await this.removeLocal(staging);
      await this.removeLocal(`${staging}.tmp`);
      this.end();
    }
  }

  async restore(context: common.Context, confirm: (info: CloudBackupInfo) => Promise<boolean>): Promise<boolean> {
    const accountId = this.begin();
    const staging = `${context.cacheDir}/cloud_backup_restore.json`;
    try {
      await this.assertAccount(context, accountId);
      const path = await this.cloudPath(context, accountId);
      await this.sync(context, accountId);
      await this.assertAccount(context, accountId);
      if (!await fileIo.access(path)) throw new CloudBackupError(CloudBackupErrorCode.NO_BACKUP);
      const stat = await fileIo.stat(path);
      const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(path));
      if ((stat.location & LOCATION_CLOUD) === 0 ||
        (state !== cloudSync.FileState.UPLOAD_SUCCESS && state !== cloudSync.FileState.INITIAL_AFTER_DOWNLOAD)) {
        throw new CloudBackupError(CloudBackupErrorCode.SERVER);
      }
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_BACKUP_BYTES) {
        throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
      }
      if (stat.location === LOCATION_CLOUD) {
        await this.download(context, accountId, fileUri.getUriFromPath(path));
      }
      await this.assertAccount(context, accountId);
      await fileIo.copyFile(path, staging);
      let snapshot: AppBackupSnapshot;
      try {
        snapshot = await AppBackupService.readSnapshot(staging);
      } catch (_error) {
        throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
      }
      this.lastBackupAt = snapshot.exportedAt;
      this.phase = CloudBackupPhase.CONFIRMING;
      if (!await confirm(new CloudBackupInfo(snapshot))) return false;
      await this.assertAccount(context, accountId);
      this.phase = CloudBackupPhase.PREPARING;
      // 放在 filesDir，不进入云目录，失败后仍保留恢复前的本机快照。
      await AppBackupService.createSnapshot(context, `${context.filesDir}/backup/before_cloud_restore.json`, true);
      await this.assertAccount(context, accountId);
      this.phase = CloudBackupPhase.RESTORING;
      try {
        if (!await AppBackupService.restoreSnapshot(context, staging, true)) {
          throw new Error('Empty backup');
        }
      } catch (_error) {
        throw new CloudBackupError(CloudBackupErrorCode.RESTORE_FAILED);
      }
      return true;
    } catch (error) {
      throw this.normalizeError(error);
    } finally {
      await this.removeLocal(staging);
      this.end();
    }
  }

  cancel(): void {
    if (!this.busy || this.phase === CloudBackupPhase.RESTORING) return;
    this.cancelled = true;
    this.cancelTransfer?.();
  }

  private begin(): string {
    AuthService.instance.beginDataOperation();
    this.busy = true;
    this.cancelled = false;
    this.phase = CloudBackupPhase.PREPARING;
    return AuthService.instance.openID;
  }

  private end(): void {
    this.cancelTransfer = null;
    this.busy = false;
    this.phase = CloudBackupPhase.IDLE;
    AuthService.instance.endDataOperation();
  }

  private async cloudPath(context: common.Context, accountId: string): Promise<string> {
    if (!context.cloudFileDir) throw new CloudBackupError(CloudBackupErrorCode.UNAVAILABLE);
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(accountId) });
    const result = await digest.digest();
    let accountKey = '';
    for (const byte of result.data) accountKey += byte.toString(16).padStart(2, '0');
    // 系统账号云空间本身隔离，再按授权账号区分文件，防止系统换号后的旧缓存误恢复。
    return `${context.cloudFileDir}/listenbook_${accountKey}.json`;
  }

  private async assertAccount(context: common.Context, accountId: string): Promise<void> {
    if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
    await AuthService.instance.restore(context);
    if (!AuthService.instance.isLoggedIn || AuthService.instance.openID !== accountId) {
      this.lastBackupAt = 0;
      throw new CloudBackupError(CloudBackupErrorCode.ACCOUNT_CHANGED);
    }
    if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
  }

  private async sync(context: common.Context, accountId: string): Promise<void> {
    this.phase = CloudBackupPhase.SYNCING;
    const task = new cloudSync.FileSync();
    let success = false;
    try {
      await new Promise<void>((resolve, reject) => {
        let done = false;
        let timeout: number = -1;
        let accountCheck: number = -1;
        const finish = (error: CloudBackupError | null): void => {
          if (done) return;
          done = true;
          clearTimeout(timeout);
          clearInterval(accountCheck);
          try { task.off('progress', onProgress); } catch (_error) { }
          this.cancelTransfer = null;
          if (error) reject(error);
          else resolve();
        };
        const onProgress = (progress: cloudSync.SyncProgress): void => {
          if (progress.error !== cloudSync.ErrorType.NO_ERROR) {
            finish(this.syncError(progress.error));
          } else if (progress.state === cloudSync.SyncState.COMPLETED) {
            finish(null);
          } else if (progress.state === cloudSync.SyncState.UPLOAD_FAILED ||
            progress.state === cloudSync.SyncState.DOWNLOAD_FAILED) {
            finish(new CloudBackupError(CloudBackupErrorCode.SERVER));
          } else if (progress.state === cloudSync.SyncState.STOPPED) {
            finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
          }
        };
        this.cancelTransfer = (): void => finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
        timeout = setTimeout(() => finish(new CloudBackupError(CloudBackupErrorCode.TIMEOUT)), SYNC_TIMEOUT_MS);
        accountCheck = setInterval(() => {
          this.assertAccount(context, accountId).catch((error: CloudBackupError) => finish(error));
        }, 5000);
        try {
          task.on('progress', onProgress);
          task.start().catch((error: BusinessError) => finish(this.normalizeError(error)));
        } catch (error) {
          finish(this.normalizeError(error));
        }
      });
      success = true;
    } finally {
      if (!success) {
        try { await task.stop(); } catch (_error) { }
      }
    }
  }

  private async download(context: common.Context, accountId: string, uri: string): Promise<void> {
    this.phase = CloudBackupPhase.DOWNLOADING;
    const task = new cloudSync.CloudFileCache();
    let success = false;
    try {
      await new Promise<void>((resolve, reject) => {
        let done = false;
        let timeout: number = -1;
        let accountCheck: number = -1;
        const finish = (error: CloudBackupError | null): void => {
          if (done) return;
          done = true;
          clearTimeout(timeout);
          clearInterval(accountCheck);
          try { task.off('progress', onProgress); } catch (_error) { }
          this.cancelTransfer = null;
          if (error) reject(error);
          else resolve();
        };
        const onProgress = (progress: cloudSync.DownloadProgress): void => {
          if (progress.uri !== uri) return;
          if (progress.state === cloudSync.State.COMPLETED) finish(null);
          else if (progress.state === cloudSync.State.STOPPED) {
            finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
          } else if (progress.state === cloudSync.State.FAILED) {
            const code = progress.error === cloudSync.DownloadErrorType.NETWORK_UNAVAILABLE
              ? CloudBackupErrorCode.NETWORK : progress.error === cloudSync.DownloadErrorType.LOCAL_STORAGE_FULL
                ? CloudBackupErrorCode.LOCAL_FULL : CloudBackupErrorCode.SERVER;
            finish(new CloudBackupError(code));
          }
        };
        this.cancelTransfer = (): void => finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
        timeout = setTimeout(() => finish(new CloudBackupError(CloudBackupErrorCode.TIMEOUT)), SYNC_TIMEOUT_MS);
        accountCheck = setInterval(() => {
          this.assertAccount(context, accountId).catch((error: CloudBackupError) => finish(error));
        }, 5000);
        try {
          task.on('progress', onProgress);
          task.start(uri).catch((error: BusinessError) => finish(this.normalizeError(error)));
        } catch (error) {
          finish(this.normalizeError(error));
        }
      });
      success = true;
    } finally {
      if (!success) {
        try { await task.stop(uri); } catch (_error) { }
      }
    }
  }

  private syncError(error: cloudSync.ErrorType): CloudBackupError {
    let code = CloudBackupErrorCode.SERVER;
    if (error === cloudSync.ErrorType.NETWORK_UNAVAILABLE || error === cloudSync.ErrorType.WIFI_UNAVAILABLE) {
      code = CloudBackupErrorCode.NETWORK;
    } else if (error === cloudSync.ErrorType.BATTERY_LEVEL_LOW || error === cloudSync.ErrorType.BATTERY_LEVEL_WARNING) {
      code = CloudBackupErrorCode.BATTERY;
    } else if (error === cloudSync.ErrorType.CLOUD_STORAGE_FULL) code = CloudBackupErrorCode.CLOUD_FULL;
    else if (error === cloudSync.ErrorType.LOCAL_STORAGE_FULL) code = CloudBackupErrorCode.LOCAL_FULL;
    else if (error === cloudSync.ErrorType.DEVICE_TEMPERATURE_TOO_HIGH) code = CloudBackupErrorCode.HOT;
    return new CloudBackupError(code);
  }

  private normalizeError(error: BusinessError | CloudBackupError): CloudBackupError {
    if (error instanceof CloudBackupError) return error;
    const code = error.code;
    if (code === 22400001 || code === 201 || code === 801 || code === 13900012 || code === 13600001) {
      return new CloudBackupError(CloudBackupErrorCode.UNAVAILABLE);
    }
    if (code === 22400002) return new CloudBackupError(CloudBackupErrorCode.NETWORK);
    if (code === 22400003) return new CloudBackupError(CloudBackupErrorCode.BATTERY);
    if (code === 13900028) return new CloudBackupError(CloudBackupErrorCode.LOCAL_FULL);
    return new CloudBackupError(CloudBackupErrorCode.LOCAL_FAILURE);
  }

  private async removeLocal(path: string): Promise<void> {
    try { await fileIo.unlink(path); } catch (_error) { }
  }
}
