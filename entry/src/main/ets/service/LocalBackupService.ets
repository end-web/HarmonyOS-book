import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { AppBackupService, AppBackupSnapshot } from './AppBackupService';
import { AuthService } from './AuthService';

export enum LocalBackupErrorCode {
  INVALID_BACKUP = 1,
  TOO_LARGE,
  FILE_ACCESS,
  BACKUP_FAILED,
  RESTORE_FAILED,
  CANCELLED
}

export class LocalBackupError extends Error {
  code: LocalBackupErrorCode;

  constructor(code: LocalBackupErrorCode) {
    super('Local backup operation failed');
    this.code = code;
  }
}

export enum LocalBackupPhase {
  IDLE = 0,
  PREPARING,
  SELECTING,
  COPYING,
  CONFIRMING,
  RESTORING
}

const MAX_BACKUP_BYTES: number = 32 * 1024 * 1024;
const COPY_BUFFER_BYTES: number = 256 * 1024;

/** 无需登录。文件选择器的临时 URI 只在当前操作中使用，不持久化。 */
@ObservedV2
export class LocalBackupService {
  private static singleton: LocalBackupService = new LocalBackupService();
  @Trace busy: boolean = false;
  @Trace phase: LocalBackupPhase = LocalBackupPhase.IDLE;
  private cancelled: boolean = false;

  static get instance(): LocalBackupService {
    return LocalBackupService.singleton;
  }

  async backup(context: common.Context): Promise<AppBackupSnapshot | null> {
    this.begin();
    const staging = `${context.cacheDir}/local_backup_export.json`;
    try {
      await AppBackupService.createSnapshot(context, staging, true);
      const snapshot = await AppBackupService.readSnapshot(staging);
      this.checkCancelled();
      this.phase = LocalBackupPhase.SELECTING;
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`listenbook-backup-${snapshot.exportedAt}.json`];
      options.fileSuffixChoices = ['.json'];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      this.checkCancelled();
      if (uris.length === 0) return null;
      this.phase = LocalBackupPhase.COPYING;
      await this.copyFile(staging, uris[0]);
      return snapshot;
    } catch (error) {
      this.logFailure('export', error);
      if (error instanceof LocalBackupError) throw error;
      throw new LocalBackupError(this.phase === LocalBackupPhase.PREPARING ?
        LocalBackupErrorCode.BACKUP_FAILED : LocalBackupErrorCode.FILE_ACCESS);
    } finally {
      await this.removeLocal(staging);
      await this.removeLocal(`${staging}.tmp`);
      this.end();
    }
  }

  async restore(context: common.Context, confirm: (snapshot: AppBackupSnapshot) => Promise<boolean>): Promise<boolean> {
    this.begin();
    const staging = `${context.cacheDir}/local_backup_restore.json`;
    const safety = `${context.filesDir}/backup/before_local_restore.json`;
    try {
      this.phase = LocalBackupPhase.SELECTING;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json'];
      const uris = await new picker.DocumentViewPicker(context).select(options);
      this.checkCancelled();
      if (uris.length === 0) return false;
      this.phase = LocalBackupPhase.COPYING;
      await this.copyFile(uris[0], staging);
      let snapshot: AppBackupSnapshot;
      try {
        snapshot = await AppBackupService.readSnapshot(staging);
      } catch (_error) {
        throw new LocalBackupError(LocalBackupErrorCode.INVALID_BACKUP);
      }
      this.checkCancelled();
      this.phase = LocalBackupPhase.CONFIRMING;
      if (!await confirm(snapshot)) return false;
      this.checkCancelled();
      this.phase = LocalBackupPhase.PREPARING;
      // 先验证安全快照可读，再覆盖当前记录；此快照不进入系统或云备份。
      await AppBackupService.createSnapshot(context, safety, true);
      await AppBackupService.readSnapshot(safety);
      this.checkCancelled();
      this.phase = LocalBackupPhase.RESTORING;
      try {
        if (!await AppBackupService.restoreSnapshot(context, staging, true)) throw new Error('Missing backup');
      } catch (_error) {
        throw new LocalBackupError(LocalBackupErrorCode.RESTORE_FAILED);
      }
      return true;
    } catch (error) {
      this.logFailure('restore', error);
      if (error instanceof LocalBackupError) throw error;
      throw new LocalBackupError(this.phase === LocalBackupPhase.PREPARING ?
        LocalBackupErrorCode.BACKUP_FAILED : LocalBackupErrorCode.FILE_ACCESS);
    } finally {
      await this.removeLocal(staging);
      await this.removeLocal(`${safety}.tmp`);
      this.end();
    }
  }

  cancel(): void {
    if (this.busy && this.phase !== LocalBackupPhase.RESTORING) this.cancelled = true;
  }

  private begin(): void {
    AuthService.instance.beginDataOperation(false);
    this.busy = true;
    this.cancelled = false;
    this.phase = LocalBackupPhase.PREPARING;
  }

  private end(): void {
    this.busy = false;
    this.phase = LocalBackupPhase.IDLE;
    AuthService.instance.endDataOperation();
  }

  private checkCancelled(): void {
    if (this.cancelled) throw new LocalBackupError(LocalBackupErrorCode.CANCELLED);
  }

  private logFailure(operation: string, error: BusinessError): void {
    // 仅记录程序阶段、错误码及调用栈；不输出备份数据、外部 URI 或账号资料。
    const code = typeof error.code === 'number' ? error.code : 0;
    const stack = error.stack ?? '';
    console.error(`[LocalBackupService] ${operation} phase=${this.phase} code=${code} stack=${stack}`);
  }

  /** 按文件描述符顺序读写，兼容文档 URI，并处理短读、短写及文件增长。 */
  private async copyFile(source: string, target: string): Promise<void> {
    const input = await fileIo.open(source, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(input.fd);
      if (stat.size > MAX_BACKUP_BYTES) throw new LocalBackupError(LocalBackupErrorCode.TOO_LARGE);
      if (!stat.isFile() || stat.size <= 0) throw new LocalBackupError(LocalBackupErrorCode.INVALID_BACKUP);
      const output = await fileIo.open(target,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const buffer = new ArrayBuffer(COPY_BUFFER_BYTES);
        let total = 0;
        while (true) {
          this.checkCancelled();
          const length = await fileIo.read(input.fd, buffer, { length: buffer.byteLength });
          if (length === 0) break;
          if (length < 0 || length > buffer.byteLength) throw new LocalBackupError(LocalBackupErrorCode.FILE_ACCESS);
          total += length;
          if (total > MAX_BACKUP_BYTES) throw new LocalBackupError(LocalBackupErrorCode.TOO_LARGE);
          let written = 0;
          while (written < length) {
            const remaining = buffer.slice(written, length);
            const count = await fileIo.write(output.fd, remaining, { length: remaining.byteLength });
            if (count <= 0 || count > remaining.byteLength) throw new LocalBackupError(LocalBackupErrorCode.FILE_ACCESS);
            written += count;
          }
        }
        if (total !== stat.size) throw new LocalBackupError(LocalBackupErrorCode.INVALID_BACKUP);
        await fileIo.fsync(output.fd);
      } finally {
        await fileIo.close(output);
      }
    } finally {
      await fileIo.close(input);
    }
  }

  private async removeLocal(path: string): Promise<void> {
    try { await fileIo.unlink(path); } catch (_error) { /* 临时文件可能未创建。 */ }
  }
}
