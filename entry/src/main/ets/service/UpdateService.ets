/** 华为应用市场更新入口。App ID：6917615941058168740。 */
import { bundleManager, common, OpenLinkOptions, Want } from '@kit.AbilityKit';

const APP_BUNDLE_NAME: string = 'com.huan.listenbook';

export class UpdateService {
  static getCurrentVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      return info.versionName || '0.0.0';
    } catch (_e) {
      return '0.0.0';
    }
  }

  /** 鸿蒙应用详情链接使用包名，由应用市场判断可更新版本并安装。 */
  static async openAppGallery(context: common.UIAbilityContext): Promise<void> {
    const want: Want = {
      action: 'ohos.want.action.appdetail',
      uri: `store://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}`
    };
    try {
      await context.startAbility(want);
      return;
    } catch (_e) {
      // 无法拉起市场时使用官方 HTTPS 页面，仍不跳转第三方下载站。
    }
    const options: OpenLinkOptions = { appLinkingOnly: false };
    await context.openLink(`https://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}`, options);
  }
}
