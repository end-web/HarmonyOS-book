import { http } from '@kit.NetworkKit';
import { url } from '@kit.ArkTS';
import { DownloadPolicy } from './DownloadPolicy';

/** 滚动窗口时长不等于节目时长，HLS 直播必须依据清单判定。 */
export class LiveAudioService {
  static isLivePlaylist(text: string): boolean {
    return text.trimStart().startsWith('#EXTM3U') && /#EXTINF:/.test(text) && !/#EXT-X-ENDLIST/.test(text);
  }

  static async isLive(audioUrl: string, headers: Record<string, string>): Promise<boolean> {
    if (!DownloadPolicy.isHls(audioUrl, '')) return false;
    let address = audioUrl;
    for (let depth = 0; depth < 2; depth++) {
      const request = http.createHttp();
      try {
        const response = await request.request(address, {
          method: http.RequestMethod.GET, header: headers,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 3000, readTimeout: 3000, maxLimit: 128 * 1024
        });
        if (response.responseCode !== 200 || typeof response.result !== 'string') return false;
        const text = response.result;
        if (LiveAudioService.isLivePlaylist(text)) return true;
        if (!text.includes('#EXT-X-STREAM-INF:')) return false;
        const child = text.split(/\r?\n/).find((line: string): boolean =>
          line.trim().length > 0 && !line.trim().startsWith('#'));
        if (!child) return false;
        address = new url.URL(child.trim(), address).toString();
        if (!DownloadPolicy.isHttpUrl(address)) return false;
      } catch (_error) {
        return false;
      } finally {
        request.destroy();
      }
    }
    return false;
  }
}
