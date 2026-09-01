/**
 * NetworkPreconnect - 冷启网络预建链服务
 *
 * 应用冷启动时与高频固定域名提前建立 TCP/TLS 连接，与首屏业务逻辑并行，
 * 使后续同一 rcp session 对该域名的真实请求跳过 DNS/TCP/TLS 握手（省 ~400-700ms）。
 *
 * 预建链只在"启动时可预测固定域名"时有意义；动态生成/依赖用户输入的 URL 无法命中。
 * 本应用只对欢FM站点和静态 CDN 镜像预建链。
 *
 * 复用前提由 HttpClient.preconnect 保证：与 request() 共用同一 sharedSession。
 */
import { HttpClient } from './HttpClient';

const HUAN_FM_SITE = 'https://www.tingyou.fm';
const HUAN_CDN_BASES: string[] = [
  'https://json.tingyou8.vip',
  'https://json.hgeuz.cn',
  'https://json.fmfm.pro',
];

export class NetworkPreconnect {
  private static fixedWarmed: boolean = false;

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
}
