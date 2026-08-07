import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book } from '../model/Book';
import { PreferenceBackupSnapshot, PreferenceService } from './PreferenceService';
import { BookUsageStats, StatsService } from './StatsService';
import { DataService } from './DataService';

const BACKUP_DIR: string = 'backup';
const BACKUP_FILE: string = 'listenbook_state.json';
const BACKUP_VERSION: number = 1;

class AppBackupSnapshot {
  version: number = BACKUP_VERSION;
  exportedAt: number = 0;
  preferences: PreferenceBackupSnapshot = new PreferenceBackupSnapshot();
  stats: BookUsageStats[] = [];
  books: Book[] = [];
}

export class AppBackupService {
  private static backupDir(context: common.Context): string {
    return `${context.filesDir}/${BACKUP_DIR}`;
  }

  private static backupPath(context: common.Context): string {
    return `${AppBackupService.backupDir(context)}/${BACKUP_FILE}`;
  }

  static async createSnapshot(context: common.Context): Promise<void> {
    await PreferenceService.init(context);
    await StatsService.init(context);
    DataService.setContext(context);
    const snapshot = new AppBackupSnapshot();
    snapshot.exportedAt = Date.now();
    snapshot.preferences = await PreferenceService.exportBackupSnapshot();
    snapshot.stats = (await StatsService.getBookStats())
      .filter((item: BookUsageStats) => !item.bookId.startsWith('import_'));
    snapshot.books = await DataService.exportBackupBookShells();

    const dir = AppBackupService.backupDir(context);
    try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
    const path = AppBackupService.backupPath(context);
    const tmp = path + '.tmp';
    const file = await fileIo.open(tmp,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, JSON.stringify(snapshot));
      try { await fileIo.fsync(file.fd); } catch (_e) { /* 部分文件系统不支持 */ }
    } finally {
      await fileIo.close(file);
    }
    await fileIo.moveFile(tmp, path);
  }

  static async restoreSnapshot(context: common.Context): Promise<boolean> {
    const path = AppBackupService.backupPath(context);
    let exists = false;
    try { exists = await fileIo.access(path); } catch (_e) { exists = false; }
    if (!exists) return false;
    const raw = await fileIo.readText(path);
    if (!raw) return false;
    const snapshot = JSON.parse(raw) as AppBackupSnapshot;
    if (!snapshot || snapshot.version !== BACKUP_VERSION || !snapshot.preferences) return false;

    await PreferenceService.init(context);
    await StatsService.init(context);
    DataService.setContext(context);
    await PreferenceService.restoreBackupSnapshot(snapshot.preferences);
    await StatsService.restoreBackupStats(Array.isArray(snapshot.stats) ? snapshot.stats : []);
    await DataService.restoreBackupBookShells(Array.isArray(snapshot.books) ? snapshot.books : []);
    return true;
  }
}
