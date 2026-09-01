import {
  GuangYuAccountState,
  GuangYuAuthResult,
  GuangYuAuthService
} from './guangyu/GuangYuAuthService';
import { GuangYuSourceIdentity } from './guangyu/GuangYuSourceIdentity';
import {
  ShuShanAccountState,
  ShuShanAuthResult,
  ShuShanAuthService
} from './shushan/ShuShanAuthService';
import { ShuShanSourceIdentity } from './shushan/ShuShanSourceIdentity';

export class RuleSourceAccountState {
  loggedIn: boolean = false;
  accountLabel: string = '';
}

export class RuleSourceAuthResult {
  success: boolean = false;
  message: string = '';
  accountLabel: string = '';
}

/** 给账号页面提供稳定契约，凭据处理仍由各专用源自己的服务负责。 */
export class RuleSourceAccountService {
  static supports(sourceUrl: string | undefined): boolean {
    return GuangYuSourceIdentity.isSourceUrl(sourceUrl) ||
      ShuShanSourceIdentity.isSourceUrl(sourceUrl);
  }

  static usesWebLogin(sourceUrl: string | undefined): boolean {
    return false;
  }

  static webLoginUrl(sourceUrl: string): string {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuAuthService.webLoginUrl();
    }
    return '';
  }

  static webLoginUrls(sourceUrl: string): string[] {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuAuthService.webLoginUrls();
    }
    return [];
  }

  static async saveWebLogin(sourceUrl: string, cookieHeaders: string[]): Promise<boolean> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuAuthService.saveWebSession(cookieHeaders);
    }
    return false;
  }

  static async getState(sourceUrl: string): Promise<RuleSourceAccountState> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      const state: GuangYuAccountState = await GuangYuAuthService.getState();
      return RuleSourceAccountService.mapState(state.loggedIn, state.accountLabel);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      const state: ShuShanAccountState = await ShuShanAuthService.getState();
      return RuleSourceAccountService.mapState(state.loggedIn, state.accountLabel);
    }
    throw new Error('当前书源不支持账号登录');
  }

  static async login(sourceUrl: string, email: string,
    password: string): Promise<RuleSourceAuthResult> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      const result: GuangYuAuthResult = await GuangYuAuthService.login(email, password);
      return RuleSourceAccountService.mapResult(result.success, result.message, result.accountLabel);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      const result: ShuShanAuthResult = await ShuShanAuthService.login(email, password);
      return RuleSourceAccountService.mapResult(result.success, result.message, result.accountLabel);
    }
    return RuleSourceAccountService.failed('当前书源不支持账号登录');
  }

  static async logout(sourceUrl: string): Promise<void> {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      await GuangYuAuthService.logout();
      return;
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      await ShuShanAuthService.logout();
      return;
    }
    throw new Error('当前书源不支持账号登录');
  }

  static registrationUrl(sourceUrl: string): string {
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      return GuangYuAuthService.registrationUrl();
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      return ShuShanAuthService.registrationUrl();
    }
    return '';
  }

  private static mapState(loggedIn: boolean, accountLabel: string): RuleSourceAccountState {
    const state = new RuleSourceAccountState();
    state.loggedIn = loggedIn;
    state.accountLabel = accountLabel;
    return state;
  }

  private static mapResult(success: boolean, message: string,
    accountLabel: string): RuleSourceAuthResult {
    const result = new RuleSourceAuthResult();
    result.success = success;
    result.message = message;
    result.accountLabel = accountLabel;
    return result;
  }

  private static failed(message: string): RuleSourceAuthResult {
    return RuleSourceAccountService.mapResult(false, message, '');
  }
}
