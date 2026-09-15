import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookIdentity } from '../../utils/BookIdentity';

class CachedTextChapter {
  version: number = 1;
  key: string = '';
  content: string = '';
}

/** 正文按章节落盘，不随进程退出丢失；损坏或缺失时由调用方重新获取。 */
export class OnlineTextContentCache {
  private static writeChain: Promise<void> = Promise.resolve();
  private static readonly MAX_FILE_BYTES: number = 8 * 1024 * 1024;

  static key(sourceUrl: string, bookUrl: string, chapterUrl: string): string {
    return JSON.stringify([sourceUrl, bookUrl, chapterUrl]);
  }

  private static path(context: common.Context, key: string): string {
    return `${context.cacheDir}/online_text_content/${BookIdentity.onlineTextBookId(key, '')}.json`;
  }

  static async read(context: common.Context, key: string): Promise<string | undefined> {
    try {
      const path = OnlineTextContentCache.path(context, key);
      const stat = await fileIo.stat(path);
      if (stat.size <= 0 || stat.size > OnlineTextContentCache.MAX_FILE_BYTES) return undefined;
      const record: CachedTextChapter = JSON.parse(await fileIo.readText(path));
      // 校验完整身份，哈希碰撞也不能返回另一本书/另一个来源的正文。
      if (record !== null && record.version === 1 && record.key === key &&
        typeof record.content === 'string' && record.content.trim().length > 0) {
        return record.content;
      }
    } catch (_e) { /* 缺失、损坏或读取失败均回退在线获取 */ }
    return undefined;
  }

  static write(context: common.Context, key: string, content: string): Promise<void> {
    if (content.trim().length === 0) return Promise.resolve();
    const record = new CachedTextChapter();
    record.key = key;
    record.content = content;
    const bytes = buffer.from(JSON.stringify(record), 'utf-8').buffer;
    if (bytes.byteLength > OnlineTextContentCache.MAX_FILE_BYTES) return Promise.resolve();
    const task = OnlineTextContentCache.writeChain.then(async (): Promise<void> => {
      const dir = `${context.cacheDir}/online_text_content`;
      try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
      const path = OnlineTextContentCache.path(context, key);
      const temp = path + '.tmp';
      let file: fileIo.File | null = null;
      try {
        file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE |
          fileIo.OpenMode.TRUNC);
        let offset = 0;
        while (offset < bytes.byteLength) {
          const written = await fileIo.write(file.fd, bytes.slice(offset));
          if (written <= 0) throw new Error('正文缓存写入未完成');
          offset += written;
        }
        await fileIo.fsync(file.fd);
        await fileIo.close(file);
        file = null;
        await fileIo.moveFile(temp, path);
      } finally {
        if (file !== null) {
          try { await fileIo.close(file); } catch (_e) { /* ignore */ }
        }
        try { await fileIo.unlink(temp); } catch (_e) { /* 已移动或未创建 */ }
      }
    }).catch((): void => {
      hilog.warn(0x0000, 'OnlineTextContentCache', 'chapter cache write failed');
    });
    OnlineTextContentCache.writeChain = task;
    return task;
  }
}
