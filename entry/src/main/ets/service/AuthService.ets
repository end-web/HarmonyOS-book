/**
 * AuthService - 华为账号登录(获取 UnionID/OpenID)
 *
 * 走「华为账号登录」场景(非一键登录):端侧 createLoginWithHuaweiIDRequest
 * 登录成功后 response.data 直接返回 unionID/openID,无需后端、无需申请权限。
 * 身份标识持久化到 PreferenceService,冷启动 restore() 恢复登录态。
 *
 * 前提(在 AGC 后台 + 工程配置完成,否则 executeRequest 报错):
 *  1. 手动签名 + AGC 配置应用公钥指纹(account-sign-fingerprints)
 *  2. entry/module.json5 配置 client_id metadata(account-client-id)
 */

import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PreferenceService, HwAccount } from './PreferenceService';

const TAG = 'AuthService';
const DOMAIN = 0x0000;

/** 华为账号登录常见错误码(用于 UI 友好提示) */
export enum HwAuthErrorCode {
  /** 用户未登录华为账号 */
  LOGIN_OUT = 1001502001,
  /** 网络异常 */
  NETWORK = 1001502005,
  /** 内部错误 */
  INTERNAL = 1001502009,
  /** 用户取消授权 */
  USER_CANCEL = 1001502012,
  /** 系统服务异常 */
  SYSTEM_SERVICE = 12300001,
  /** 重复请求 */
  REQUEST_REFUSE = 1001500002,
  /** 应用指纹证书校验失败(签名/指纹/client_id 未配好) */
  CERT_INVALID = 1001500001,
}

@ObservedV2
export class AuthService {
  private static _instance: AuthService | null = null;

  static get instance(): AuthService {
    if (!AuthService._instance) {
      AuthService._instance = new AuthService();
    }
    return AuthService._instance;
  }

  @Trace isLoggedIn: boolean = false;
  @Trace unionID: string = '';
  @Trace openID: string = '';
  @Trace loginAt: number = 0;
  /** 登录请求进行中:按钮 loading / 防重复点击 */
  @Trace logging: boolean = false;

  private restored: boolean = false;

  /** 冷启动从本地恢复登录态(幂等,仅生效一次) */
  async restore(): Promise<void> {
    if (this.restored) {
      return;
    }
    this.restored = true;
    const acc = await PreferenceService.getHwAccount();
    if (acc && acc.unionID) {
      this.unionID = acc.unionID;
      this.openID = acc.openID;
      this.loginAt = acc.loginAt;
      this.isLoggedIn = true;
    }
  }

  /**
   * 华为账号登录。成功返回身份标识并落盘;失败抛 BusinessError,由调用方按错误码提示。
   * @param context UIAbility 上下文(页面可用 this.getUIContext().getHostContext())
   */
  async login(context: common.Context): Promise<HwAccount> {
    if (this.logging) {
      throw new Error('login already in progress');
    }
    this.logging = true;
    try {
      const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
      // 账号未登录时强制拉起华为账号登录页
      request.forceLogin = true;
      // 防跨站请求伪造
      request.state = util.generateRandomUUID();

      const controller = new authentication.AuthenticationController(context);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;

      // 校验 state,防跨站
      if (response.state && request.state !== response.state) {
        throw new Error(`state mismatch, response state: ${response.state}`);
      }

      const credential = response.data;
      const unionID = credential?.unionID ?? '';
      const openID = credential?.openID ?? '';
      if (!unionID) {
        throw new Error('login response missing unionID');
      }

      const account: HwAccount = { unionID, openID, loginAt: Date.now() };
      await PreferenceService.setHwAccount(account);
      this.unionID = unionID;
      this.openID = openID;
      this.loginAt = account.loginAt;
      this.isLoggedIn = true;
      hilog.info(DOMAIN, TAG, 'Huawei ID login succeeded');
      return account;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `login failed, code=${err.code}, msg=${err.message}`);
      throw e as Error;
    } finally {
      this.logging = false;
    }
  }

  /** 退出登录:仅清除本地身份标识(华为账号本身不登出) */
  async logout(): Promise<void> {
    await PreferenceService.clearHwAccount();
    this.isLoggedIn = false;
    this.unionID = '';
    this.openID = '';
    this.loginAt = 0;
  }

  /** UI 展示用:中间打码的 UnionID */
  maskedId(): string {
    const id = this.unionID;
    if (id.length <= 10) {
      return id;
    }
    return `${id.substring(0, 6)}****${id.substring(id.length - 4)}`;
  }
}
