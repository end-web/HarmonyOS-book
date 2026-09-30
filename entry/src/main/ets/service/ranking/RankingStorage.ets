import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';

/** 独立的小型缓存；故障不影响首页联网或既有书源库。 */
export class RankingStorage {
  static async read(context: common.Context, key: string): Promise<string> {
    if (!/^[a-z0-9-]+$/.test(key)) return '';
    try {
      const path = `${context.cacheDir}/ranking-${key}.json`;
      const stat = await fileIo.stat(path);
      if (stat.size <= 0 || stat.size > 3 * 1024 * 1024) return '';
      return await fileIo.readText(path);
    } catch (_error) { return ''; }
  }

  static async write(context: common.Context, key: string, content: string): Promise<void> {
    if (!/^[a-z0-9-]+$/.test(key) || content.length > 2 * 1024 * 1024) return;
    const path = `${context.cacheDir}/ranking-${key}.json`;
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(path + '.tmp', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const bytes: ArrayBuffer = buffer.from(content, 'utf-8').buffer;
      let offset = 0;
      while (offset < bytes.byteLength) {
        const written = await fileIo.write(file.fd, bytes.slice(offset));
        if (written <= 0) throw new Error('Ranking cache short write');
        offset += written;
      }
      await fileIo.close(file);
      file = undefined;
      await fileIo.moveFile(path + '.tmp', path);
    } catch (_error) {
      // 缓存不可写时，仍返回已经加载的榜单。
    } finally {
      if (file !== undefined) await fileIo.close(file).catch((): void => {});
    }
  }
}
