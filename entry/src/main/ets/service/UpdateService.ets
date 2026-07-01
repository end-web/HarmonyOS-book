/**
 * UpdateService - GitHub Releases 检查更新
 *
 * 形态约束:本 App 手动签名分发、未上架应用市场,普通应用拿不到 INSTALL_BUNDLE
 * 系统权限,无法在应用内直接安装 HAP。因此这里只做「检查 + 跳转 GitHub 下载」,
 * 由用户自行用 hdc / 开发者模式安装。将来上架应用市场后应改用 StoreKit.checkAppUpdate。
 *
 * 网络:直连 api.github.com 国内多半连不上,RELEASE_ENDPOINTS 后面的反代是兜底,
 * 逐个尝试谁先成功用谁;全部失败时手动检查会提示网络异常,启动静默检查则静默忽略。
 */

import { bundleManager, common, OpenLinkOptions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HttpClient } from './http/HttpClient';

const STORE_NAME = 'listenbook_update';
const KEY_LAST_CHECK = 'last_check_ms';
const KEY_CACHED_INFO = 'cached_update_info';
/** 静默检查节流:两次联网检查至少间隔 24h */
const SILENT_INTERVAL = 24 * 60 * 60 * 1000;

const OWNER = 'end-web';
const REPO = 'HarmonyOS-book';

/**
 * 检查更新候选端点,逐个尝试。
 * [0] 直连 GitHub API(准,但国内多半超时);
 * [1][2] 公共反代兜底(服务不稳,失效时可自行替换成可用的 api.github.com 反代)。
 */
const RELEASE_ENDPOINTS: string[] = [
  `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
  `https://gh-proxy.com/https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
  `https://ghfast.top/https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
];

/** GitHub Release API 关心的字段 */
interface GithubRelease {
  tag_name?: string;
  name?: string;
  body?: string;
  html_url?: string;
}

export interface UpdateInfo {
  hasUpdate: boolean;
  currentVersion: string;
  latestVersion: string;
  /** release 说明(更新日志),原样文本 */
  notes: string;
  /** GitHub release 页面 URL,跳转下载用 */
  releaseUrl: string;
  checkedAt: number;
}

export class UpdateService {
  private static store: preferences.Preferences | null = null;

  private static async ensureStore(context: common.BaseContext): Promise<preferences.Preferences> {
    if (UpdateService.store) return UpdateService.store;
    UpdateService.store = await preferences.getPreferences(context, { name: STORE_NAME });
    return UpdateService.store;
  }

  /** 本地版本名(versionName),失败兜底 '0.0.0' */
  static getCurrentVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      return info.versionName || '0.0.0';
    } catch (_e) {
      return '0.0.0';
    }
  }

  /** 语义化版本比较:a>b→1, a==b→0, a<b→-1。忽略前缀 v 与非数字后缀(如 -beta)。 */
  private static compareVersion(a: string, b: string): number {
    const pa = UpdateService.normalize(a);
    const pb = UpdateService.normalize(b);
    const n = Math.max(pa.length, pb.length);
    for (let i = 0; i < n; i++) {
      const x = i < pa.length ? pa[i] : 0;
      const y = i < pb.length ? pb[i] : 0;
      if (x > y) return 1;
      if (x < y) return -1;
    }
    return 0;
  }

  private static normalize(v: string): number[] {
    const cleaned = (v || '').trim().replace(/^[vV]/, '');
    // 取主版本段:遇到非「数字/点」即截断(1.2.0-beta → 1.2.0)
    const main = cleaned.split(/[^0-9.]/)[0];
    return main.split('.').map((s) => {
      const n = parseInt(s, 10);
      return isNaN(n) ? 0 : n;
    });
  }

  /**
   * 拉取最新 release 与本地版本比对。
   * @returns UpdateInfo;网络全部失败返回 null(手动检查据此提示网络异常)。
   */
  static async checkUpdate(context: common.BaseContext): Promise<UpdateInfo | null> {
    const current = UpdateService.getCurrentVersion();
    const headers: Record<string, string> = {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'ListenBook-UpdateChecker',
    };
    let raw = '';
    for (const url of RELEASE_ENDPOINTS) {
      try {
        const body = await HttpClient.get(url, headers);
        if (body && body.indexOf('tag_name') >= 0) {
          raw = body;
          break;
        }
      } catch (_e) {
        // 试下一个端点
      }
    }
    if (!raw) return null;

    let release: GithubRelease;
    try {
      release = JSON.parse(raw) as GithubRelease;
    } catch (_e) {
      return null;
    }
    const tag = release.tag_name || release.name || '';
    if (!tag) return null;

    const info: UpdateInfo = {
      hasUpdate: UpdateService.compareVersion(tag, current) > 0,
      currentVersion: current,
      latestVersion: tag.replace(/^[vV]/, ''),
      notes: release.body || '',
      releaseUrl: release.html_url || `https://github.com/${OWNER}/${REPO}/releases/latest`,
      checkedAt: Date.now(),
    };
    try {
      const s = await UpdateService.ensureStore(context);
      await s.put(KEY_LAST_CHECK, info.checkedAt);
      await s.put(KEY_CACHED_INFO, JSON.stringify(info));
      await s.flush();
    } catch (_e) { /* ignore */ }
    return info;
  }

  /** 上次检查缓存的结果(红点/离线展示用) */
  static async getCachedInfo(context: common.BaseContext): Promise<UpdateInfo | null> {
    try {
      const s = await UpdateService.ensureStore(context);
      const raw = await s.get(KEY_CACHED_INFO, '') as string;
      if (!raw) return null;
      return JSON.parse(raw) as UpdateInfo;
    } catch (_e) {
      return null;
    }
  }

  /** 启动静默检查:距上次检查 >24h 才联网;失败静默忽略。 */
  static async silentCheck(context: common.BaseContext): Promise<void> {
    try {
      const s = await UpdateService.ensureStore(context);
      const last = await s.get(KEY_LAST_CHECK, 0) as number;
      if (Date.now() - last < SILENT_INTERVAL) return;
      await UpdateService.checkUpdate(context);
    } catch (_e) { /* ignore */ }
  }

  /** 拉起系统默认浏览器打开 release 页面(appLinkingOnly=false → 无匹配应用时走浏览器) */
  static async openReleasePage(context: common.UIAbilityContext, url: string): Promise<void> {
    const opts: OpenLinkOptions = { appLinkingOnly: false };
    await context.openLink(url, opts);
  }
}
