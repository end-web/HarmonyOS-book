import { fileIo } from '@kit.CoreFileKit';

const MIGRATION_SUFFIX = '.legacy_migrate';

export class StorageMigrationService {
  /** 已存在的源文件迁移失败时阻止业务写入空数据；源文件始终保留供重试。 */
  static async migrateFileChecked(sourcePath: string, destinationPath: string): Promise<void> {
    if (await StorageMigrationService.migrateFile(sourcePath, destinationPath)) return;
    if (await fileIo.access(sourcePath)) throw new Error('Resource storage migration failed');
  }

  static async migrateFile(sourcePath: string, destinationPath: string): Promise<boolean> {
    let sourceSize = 0;
    try {
      const sourceStat = await fileIo.stat(sourcePath);
      if (sourceStat.isDirectory()) return false;
      sourceSize = sourceStat.size;
    } catch (_e) {
      return false;
    }

    try {
      const destinationStat = await fileIo.stat(destinationPath);
      if (!destinationStat.isDirectory() && (destinationStat.size > 0 || sourceSize === 0)) {
        try { await fileIo.unlink(sourcePath); } catch (_e) {}
        return true;
      }
    } catch (_e) {}

    // 先复制到目标目录的临时文件并校验，发布成功后才删除源文件。
    const temporaryPath = destinationPath + MIGRATION_SUFFIX;
    try {
      await fileIo.copyFile(sourcePath, temporaryPath);
      const temporaryStat = await fileIo.stat(temporaryPath);
      if (temporaryStat.isDirectory() || temporaryStat.size !== sourceSize) {
        try { await fileIo.unlink(temporaryPath); } catch (_e) {}
        return false;
      }
      await fileIo.moveFile(temporaryPath, destinationPath);
      const destinationStat = await fileIo.stat(destinationPath);
      if (destinationStat.isDirectory() || destinationStat.size !== sourceSize) {
        try { await fileIo.unlink(destinationPath); } catch (_e) {}
        return false;
      }
      try { await fileIo.unlink(sourcePath); } catch (_e) {}
      return true;
    } catch (_e) {
      try { await fileIo.unlink(temporaryPath); } catch (_ignored) {}
      return false;
    }
  }

  static async migrateDirectory(sourceDir: string, destinationDir: string, strict: boolean = false): Promise<void> {
    try {
      const sourceStat = await fileIo.stat(sourceDir);
      if (!sourceStat.isDirectory()) return;
    } catch (error) {
      if (strict && await fileIo.access(sourceDir)) throw new Error('Resource storage migration failed');
      return;
    }
    if (!await StorageMigrationService.ensureDirectory(destinationDir)) {
      if (strict) throw new Error('Resource storage directory unavailable');
      return;
    }

    let names: string[] = [];
    try {
      names = await fileIo.listFile(sourceDir);
    } catch (error) {
      if (strict) throw new Error('Resource storage migration failed');
      return;
    }
    for (const name of names) {
      const sourcePath = `${sourceDir}/${name}`;
      const destinationPath = `${destinationDir}/${name}`;
      try {
        const sourceStat = await fileIo.stat(sourcePath);
        if (sourceStat.isDirectory()) {
          await StorageMigrationService.migrateDirectory(sourcePath, destinationPath, strict);
        } else {
          await StorageMigrationService.migrateFileChecked(sourcePath, destinationPath);
        }
      } catch (error) { if (strict) throw new Error('Resource storage migration failed'); }
    }
    await StorageMigrationService.removeDirectoryIfEmpty(sourceDir);
  }

  static async migrateFilesWithPrefix(sourceDir: string, destinationDir: string, prefix: string,
    strict: boolean = false): Promise<void> {
    if (!prefix) return;
    if (!await StorageMigrationService.ensureDirectory(destinationDir)) {
      if (strict) throw new Error('Resource storage directory unavailable');
      return;
    }
    let names: string[] = [];
    try {
      names = await fileIo.listFile(sourceDir);
    } catch (error) {
      if (strict && await fileIo.access(sourceDir)) throw new Error('Resource storage migration failed');
      return;
    }
    for (const name of names) {
      if (!name.startsWith(prefix)) continue;
      const sourcePath = `${sourceDir}/${name}`;
      const destinationPath = `${destinationDir}/${name}`;
      try {
        const sourceStat = await fileIo.stat(sourcePath);
        if (!sourceStat.isDirectory()) {
          if (strict) await StorageMigrationService.migrateFileChecked(sourcePath, destinationPath);
          else await StorageMigrationService.migrateFile(sourcePath, destinationPath);
        }
      } catch (error) { if (strict) throw new Error('Resource storage migration failed'); }
    }
  }

  private static async ensureDirectory(dir: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(dir);
      return stat.isDirectory();
    } catch (_e) {}
    try {
      await fileIo.mkdir(dir);
      return true;
    } catch (_e) {
      return false;
    }
  }

  private static async removeDirectoryIfEmpty(dir: string): Promise<void> {
    try {
      const names = await fileIo.listFile(dir);
      if (names.length === 0) await fileIo.rmdir(dir);
    } catch (_e) {}
  }
}
