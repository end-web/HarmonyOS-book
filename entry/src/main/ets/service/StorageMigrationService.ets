import { fileIo } from '@kit.CoreFileKit';

const MIGRATION_SUFFIX = '.legacy_migrate';

export class StorageMigrationService {
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

    try {
      await fileIo.moveFile(sourcePath, destinationPath, 1);
      return true;
    } catch (_e) {}

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

  static async migrateDirectory(sourceDir: string, destinationDir: string): Promise<void> {
    try {
      const sourceStat = await fileIo.stat(sourceDir);
      if (!sourceStat.isDirectory()) return;
    } catch (_e) {
      return;
    }
    if (!await StorageMigrationService.ensureDirectory(destinationDir)) return;

    let names: string[] = [];
    try {
      names = await fileIo.listFile(sourceDir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      const sourcePath = `${sourceDir}/${name}`;
      const destinationPath = `${destinationDir}/${name}`;
      try {
        const sourceStat = await fileIo.stat(sourcePath);
        if (sourceStat.isDirectory()) {
          await StorageMigrationService.migrateDirectory(sourcePath, destinationPath);
        } else {
          await StorageMigrationService.migrateFile(sourcePath, destinationPath);
        }
      } catch (_e) {}
    }
    await StorageMigrationService.removeDirectoryIfEmpty(sourceDir);
  }

  static async migrateFilesWithPrefix(sourceDir: string, destinationDir: string, prefix: string): Promise<void> {
    if (!prefix || !await StorageMigrationService.ensureDirectory(destinationDir)) return;
    let names: string[] = [];
    try {
      names = await fileIo.listFile(sourceDir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      if (!name.startsWith(prefix)) continue;
      const sourcePath = `${sourceDir}/${name}`;
      const destinationPath = `${destinationDir}/${name}`;
      try {
        const sourceStat = await fileIo.stat(sourcePath);
        if (!sourceStat.isDirectory()) {
          await StorageMigrationService.migrateFile(sourcePath, destinationPath);
        }
      } catch (_e) {}
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
