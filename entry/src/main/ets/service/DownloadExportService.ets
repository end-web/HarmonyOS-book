import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { DownloadBookRecord, DownloadChapterRecord } from './DownloadStore';

export interface DownloadExportResult {
  exportedCount: number;
  failedCount: number;
}

export class DownloadExportService {
  static async exportBook(context: common.UIAbilityContext, record: DownloadBookRecord):
    Promise<DownloadExportResult> {
    const chapters = record.chapters
      .filter((chapter: DownloadChapterRecord) => chapter.status === 'completed' && chapter.filePath.length > 0)
      .sort((a: DownloadChapterRecord, b: DownloadChapterRecord) => a.chapterIndex - b.chapterIndex);
    if (chapters.length === 0) return { exportedCount: 0, failedCount: 0 };

    const options = new picker.DocumentSaveOptions();
    options.newFileNames = chapters.map((chapter: DownloadChapterRecord) =>
      DownloadExportService.buildFileName(chapter));
    const targetUris = await new picker.DocumentViewPicker(context).save(options);
    let exportedCount = 0;
    let failedCount = 0;
    const count = Math.min(chapters.length, targetUris.length);
    for (let index = 0; index < count; index++) {
      try {
        await DownloadExportService.copyFile(chapters[index].filePath, targetUris[index]);
        exportedCount++;
      } catch (_e) {
        failedCount++;
      }
    }
    failedCount += chapters.length - count;
    return { exportedCount, failedCount };
  }

  private static async copyFile(sourcePath: string, targetUri: string): Promise<void> {
    let source: fileIo.File | null = null;
    let target: fileIo.File | null = null;
    try {
      source = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
      target = await fileIo.open(targetUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(source.fd, target.fd);
    } catch (error) {
      const cause = error as Error;
      throw new Error(cause?.message ?? JSON.stringify(error));
    } finally {
      if (source) await DownloadExportService.closeSafely(source);
      if (target) await DownloadExportService.closeSafely(target);
    }
  }

  private static async closeSafely(file: fileIo.File): Promise<void> {
    try {
      await fileIo.close(file);
    } catch (_e) {
      // The primary copy error is more useful than a secondary close failure.
    }
  }

  private static buildFileName(chapter: DownloadChapterRecord): string {
    const index = Math.max(0, chapter.chapterIndex).toString().padStart(4, '0');
    const title = DownloadExportService.sanitizeName(chapter.title) || `chapter_${index}`;
    const extension = DownloadExportService.fileExtension(chapter.filePath);
    return `${index}_${title}${extension}`;
  }

  private static sanitizeName(value: string): string {
    return value.replace(/[\\/:*?"<>|]/g, '_').replace(/[. ]+$/g, '').slice(0, 80);
  }

  private static fileExtension(path: string): string {
    const lastSlash = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    const lastDot = path.lastIndexOf('.');
    if (lastDot <= lastSlash || path.length - lastDot > 8) return '.mp3';
    return path.slice(lastDot).toLowerCase();
  }
}
