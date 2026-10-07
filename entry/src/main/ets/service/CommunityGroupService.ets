import { common, sendableContextManager, Want, OpenLinkOptions } from '@kit.AbilityKit';

/**
 * 简听交流群入口:群号与打开方式集中一处,供"我的"和"关于"复用。
 * 优先用 QQ 群资料 scheme 直接拉起 QQ;QQ 未安装或系统未匹配时,退回 QQ 官方加群分享页。
 */
export class CommunityGroupService {
  static readonly GROUP_NUMBER: string = '602330717';

  private static readonly GROUP_SCHEME: string =
    'mqqapi://card/show_pslcard?src_type=internal&version=1&uin=' + CommunityGroupService.GROUP_NUMBER +
    '&card_type=group&source=qrcode';

  /** 兜底地址:QQ 官方加群分享页(浏览器打开),与群号对应的原始分享链接。 */
  private static readonly GROUP_SHARE_URL: string = 'https://qm.qq.com/q/dzljNVMPJu';

  /** 打开交流群;返回 false 表示宿主上下文缺失或 QQ、浏览器都不可用。 */
  static async open(hostContext: common.Context | undefined): Promise<boolean> {
    if (hostContext === undefined) {
      return false;
    }
    if (await CommunityGroupService.openGroupCard(hostContext)) {
      return true;
    }
    return CommunityGroupService.openSharePage(hostContext);
  }

  private static async openGroupCard(hostContext: common.Context): Promise<boolean> {
    try {
      const context = sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(hostContext));
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: CommunityGroupService.GROUP_SCHEME
      };
      await context.startAbility(want);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private static async openSharePage(hostContext: common.Context): Promise<boolean> {
    try {
      const context = sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(hostContext));
      const options: OpenLinkOptions = { appLinkingOnly: false };
      await context.openLink(CommunityGroupService.GROUP_SHARE_URL, options);
      return true;
    } catch (_error) {
      return false;
    }
  }
}
