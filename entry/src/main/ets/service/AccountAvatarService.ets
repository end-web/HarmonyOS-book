import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/** 华为头像链接会失效，独立缓存；不携带书源的 Cookie 或登录凭证。 */
export class AccountAvatarService {
  private static directory(context: common.Context): string {
    return `${context.cacheDir}/huawei_account`;
  }

  static async download(context: common.Context, uri: string): Promise<string> {
    if (!uri.startsWith('https://') || uri.length > 8192) return '';
    const client = http.createHttp();
    let avatarFile: string = '';
    try {
      const response = await client.request(uri, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: 10000,
        readTimeout: 10000,
        maxLimit: 2 * 1024 * 1024
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) ||
        response.result.byteLength === 0 || response.result.byteLength > 2 * 1024 * 1024) return '';
      const dir = AccountAvatarService.directory(context);
      if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
      avatarFile = `${util.generateRandomUUID()}.img`;
      const file = await fileIo.open(`${dir}/${avatarFile}`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        const written = await fileIo.write(file.fd, response.result);
        if (written !== response.result.byteLength) throw new Error('Incomplete avatar');
      } finally {
        await fileIo.close(file);
      }
      return avatarFile;
    } catch (_error) {
      await AccountAvatarService.remove(context, avatarFile);
      return ''; // 头像网络错误不阻止账号登录，页面保留占位图。
    } finally {
      client.destroy();
    }
  }

  static async localUri(context: common.Context, avatarFile: string): Promise<string> {
    if (!/^[a-f0-9-]{36}\.img$/.test(avatarFile)) return '';
    const path = `${AccountAvatarService.directory(context)}/${avatarFile}`;
    try {
      return await fileIo.access(path) ? fileUri.getUriFromPath(path) : '';
    } catch (_error) {
      return '';
    }
  }

  static async remove(context: common.Context, avatarFile: string): Promise<void> {
    if (!/^[a-f0-9-]{36}\.img$/.test(avatarFile)) return;
    try { await fileIo.unlink(`${AccountAvatarService.directory(context)}/${avatarFile}`); } catch (_error) { }
  }
}
