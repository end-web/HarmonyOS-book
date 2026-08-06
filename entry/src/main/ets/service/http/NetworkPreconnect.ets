/**
 * NetworkPreconnect - 冷启网络预建链服务
 *
 * 应用冷启动时与高频固定域名提前建立 TCP/TLS 连接，与首屏业务逻辑并行，
 * 使后续同一 rcp session 对该域名的真实请求跳过 DNS/TCP/TLS 握手（省 ~400-700ms）。
 *
 * 预建链只在"启动时可预测固定域名"时有意义；动态生成/依赖用户输入的 URL 无法命中。
 * 本应用的高频源域名分两类：
 *  - 固定域名（欢FM 站点 + 静态 CDN 三镜像）：onCreate 立即预建，不依赖配置。
 *  - 云源主机（默认 121.196.223.85 或用户自定义）：地址存 Preferences，需等
 *    PreferenceService 就绪后用真实值预建，避免用默认值导致自定义云源预建失效。
 *
 * 复用前提由 HttpClient.preconnect 保证：与 request() 共用同一 sharedSession。
 */
import { HttpClient } from './HttpClient';
import { DEFAULT_SERVER_AUDIO_API_BASE } from '../builtin/ServerAudioConfig';

const HUAN_FM_SITE = 'https://www.tingyou.fm';
const HUAN_CDN_BASES: string[] = [
  'https://json.tingyou8.vip',
  'https://json.hgeuz.cn',
  'https://json.fmfm.pro',
];

export class NetworkPreconnect {
  private static fixedWarmed: boolean = false;
  private static cloudWarmedOrigin: string = '';

  /** 从 URL 提取原始主机（scheme + authority），不含路径。 */
  private static originOf(url: string): string {
    const m = /^(https?:\/\/[^/]+)/.exec(url);
    return m ? m[1] : url;
  }

  /**
   * 冷启动立即预建固定域名（欢FM 站点 + CDN 镜像）。
   * fire-and-forget：任何失败都不影响主流程；去重避免重复拉起。
   */
  static prewarmBuiltIns(): void {
    if (NetworkPreconnect.fixedWarmed) return;
    NetworkPreconnect.fixedWarmed = true;
    HttpClient.preconnect(HUAN_FM_SITE);
    for (let i = 0; i < HUAN_CDN_BASES.length; i++) {
      HttpClient.preconnect(HUAN_CDN_BASES[i]);
    }
  }

  /**
   * 在 PreferenceService 就绪后调用，用真实云源地址建链。
   * 若与已建链主机相同则跳过（也避免与 prewarmCustomHost 重复建链）。
   */
  static prewarmCloud(cloudApiBase?: string): void {
    const base = cloudApiBase && cloudApiBase.length > 0
      ? cloudApiBase : DEFAULT_SERVER_AUDIO_API_BASE;
    const origin = NetworkPreconnect.originOf(base);
    if (origin.length === 0) return;
    if (NetworkPreconnect.cloudWarmedOrigin === origin) return;
    NetworkPreconnect.cloudWarmedOrigin = origin;
    HttpClient.preconnect(origin);
  }

  /**
   * 用户切换云源地址后，对新 API 主机补一次预建链。
   * origin 去重保证与 prewarmCloud 共用同一段记录，避免重复建链。
   */
  static prewarmCustomHost(customUrl: string): void {
    if (!customUrl || customUrl.length === 0) return;
    const origin = NetworkPreconnect.originOf(customUrl);
    if (origin.length === 0) return;
    if (NetworkPreconnect.cloudWarmedOrigin === origin) return;
    NetworkPreconnect.cloudWarmedOrigin = origin;
    HttpClient.preconnect(origin);
  }
}