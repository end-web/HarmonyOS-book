import { buffer } from '@kit.ArkTS';
import { LocalRuleSourceSession } from '../../../model/LocalRuleSource';
import { JsonObj } from '../../builtin/JsonValue';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../http/HttpClient';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { GuangYuApiClient } from './GuangYuApiClient';
import { GUANG_YU_SOURCE_URL } from './GuangYuSourceIdentity';

const LOGIN_TIMEOUT_MS: number = 10000;
const MAX_RESPONSE_BYTES: number = 64 * 1024;
const MAX_EMAIL_LENGTH: number = 320;
const MAX_PASSWORD_LENGTH: number = 1024;
const MIN_TOKEN_LENGTH: number = 11;
const MAX_TOKEN_LENGTH: number = 4096;
const MAX_DEVICE_ID_LENGTH: number = 256;
const MAX_WEB_COOKIE_HEADER_LENGTH: number = 64 * 1024;

class GuangYuLoginRequestBody {
  register_email: string = '';
  password: string = '';
}

export class GuangYuAccountState {
  loggedIn: boolean = false;
  accountLabel: string = '';
}

export class GuangYuAuthResult {
  success: boolean = false;
  message: string = '';
  accountLabel: string = '';
}

/** 光遇聚合账号会话。密码只用于单次登录请求，不写日志或本地存储。 */
export class GuangYuAuthService {
  private static loginInProgress: boolean = false;

  static async getState(): Promise<GuangYuAccountState> {
    const state = new GuangYuAccountState();
    try {
      const session = await LocalRuleSourceRepository.getSession(GUANG_YU_SOURCE_URL);
      if (session !== undefined && GuangYuAuthService.isValidToken(session.token)) {
        state.loggedIn = true;
        state.accountLabel = session.accountLabel;
      }
    } catch (_error) {
      // 会话缺失或损坏按未登录处理，不能影响内置源和书源管理页。
    }
    return state;
  }

  static async login(email: string, password: string): Promise<GuangYuAuthResult> {
    const normalizedEmail = email.trim();
    const invalidInput = GuangYuAuthService.validateInput(normalizedEmail, password);
    if (invalidInput.length > 0) return GuangYuAuthService.failed(invalidInput);
    if (GuangYuAuthService.loginInProgress) {
      return GuangYuAuthService.failed('登录请求正在处理中，请稍候');
    }

    GuangYuAuthService.loginInProgress = true;
    try {
      const host = GuangYuApiClient.preferredHost();
      const deviceId = await GuangYuApiClient.getOrCreateDeviceId();
      const body = new GuangYuLoginRequestBody();
      body.register_email = normalizedEmail;
      body.password = password;
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';
      headers['Cookie'] = `qttoken=;deviceId=${deviceId};`;
      const options: HttpRequestOptions = {
        method: 'POST',
        headers: headers,
        body: body,
        timeout: LOGIN_TIMEOUT_MS,
        charset: 'utf-8',
        retry: 0
      };
      // 密码只提交给当前线路，禁止自动跨线路重放。
      const response = await HttpClient.request(host + '/login_api', options);
      return await GuangYuAuthService.handleLoginResponse(response, normalizedEmail, deviceId);
    } catch (_error) {
      return GuangYuAuthService.failed('登录失败，请检查网络后重试');
    } finally {
      GuangYuAuthService.loginInProgress = false;
    }
  }

  static async logout(): Promise<void> {
    const deviceId = await GuangYuApiClient.getOrCreateDeviceId();
    const anonymousSession = LocalRuleSourceSession.of(GUANG_YU_SOURCE_URL, '', deviceId, '');
    await LocalRuleSourceRepository.saveSession(anonymousSession);
  }

  static registrationUrl(): string {
    return 'https://v1.gyks.cf/register';
  }

  static webLoginUrl(): string {
    return 'https://v1.gyks.cf/login';
  }

  static webLoginUrls(): string[] {
    const urls: string[] = [];
    const hosts = GuangYuApiClient.hosts();
    for (const host of hosts) urls.push(host + '/login');
    return urls;
  }

  /** 将 ArkWeb 网页会话转换为原生 API 客户端使用的主书源会话。 */
  static async saveWebSession(cookieHeaders: string[]): Promise<boolean> {
    const token = GuangYuAuthService.cookieValue(cookieHeaders, 'qttoken');
    if (!GuangYuAuthService.hasWebLoginCookie(cookieHeaders)) return false;

    let deviceId = GuangYuAuthService.cookieValue(cookieHeaders, 'deviceId');
    if (!GuangYuAuthService.isValidDeviceId(deviceId)) {
      deviceId = await GuangYuApiClient.getOrCreateDeviceId();
    }
    const session = LocalRuleSourceSession.of(GUANG_YU_SOURCE_URL, token, deviceId, '');
    await LocalRuleSourceRepository.saveSession(session);
    return true;
  }

  static hasWebLoginCookie(cookieHeaders: string[]): boolean {
    return GuangYuAuthService.isValidToken(
      GuangYuAuthService.cookieValue(cookieHeaders, 'qttoken'));
  }

  private static async handleLoginResponse(response: HttpResponse, accountLabel: string,
    deviceId: string): Promise<GuangYuAuthResult> {
    if (!GuangYuAuthService.hasBoundedBody(response.body)) {
      return GuangYuAuthService.failed('登录服务响应过大，已拒绝处理');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return GuangYuAuthService.failed(`登录失败：服务返回 HTTP ${response.statusCode}`);
    }

    let parsed: Object;
    try {
      parsed = JSON.parse(response.body) as Object;
    } catch (_error) {
      return GuangYuAuthService.failed('登录服务返回了无效数据');
    }
    const root = new JsonObj(parsed);
    const code = root.getInt('code', -1);
    if (code !== 0) {
      const serverMessage = GuangYuAuthService.safeMessage(root.getString('msg'));
      return GuangYuAuthService.failed(serverMessage.length > 0
        ? `登录失败：${serverMessage}` : '登录失败，请检查账号或密码');
    }
    const tokenValue = root.raw['key'];
    if (typeof tokenValue !== 'string' || !GuangYuAuthService.isValidToken(tokenValue)) {
      return GuangYuAuthService.failed('登录服务未返回有效 token');
    }

    const session = LocalRuleSourceSession.of(
      GUANG_YU_SOURCE_URL, tokenValue, deviceId, accountLabel);
    try {
      await LocalRuleSourceRepository.saveSession(session);
    } catch (_error) {
      return GuangYuAuthService.failed('登录成功，但会话保存失败');
    }
    const result = new GuangYuAuthResult();
    result.success = true;
    result.message = '登录成功';
    result.accountLabel = accountLabel;
    return result;
  }

  private static validateInput(email: string, password: string): string {
    if (email.length === 0 || password.length === 0) return '请输入邮箱和密码';
    if (email.length > MAX_EMAIL_LENGTH) return '邮箱长度超出限制';
    if (password.length > MAX_PASSWORD_LENGTH) return '密码长度超出限制';
    const atIndex = email.indexOf('@');
    if (atIndex <= 0 || atIndex >= email.length - 1) return '请输入正确的邮箱地址';
    if (email.includes('\r') || email.includes('\n')) return '邮箱包含非法字符';
    return '';
  }

  private static hasBoundedBody(body: string): boolean {
    return buffer.byteLength(body, 'utf-8') <= MAX_RESPONSE_BYTES;
  }

  private static isValidToken(token: string): boolean {
    return token.length >= MIN_TOKEN_LENGTH && token.length <= MAX_TOKEN_LENGTH &&
      !token.includes('\r') && !token.includes('\n') && !token.includes(';');
  }

  private static isValidDeviceId(deviceId: string): boolean {
    return deviceId.length > 0 && deviceId.length <= MAX_DEVICE_ID_LENGTH &&
      !deviceId.includes('\r') && !deviceId.includes('\n') && !deviceId.includes(';');
  }

  private static cookieValue(cookieHeaders: string[], expectedName: string): string {
    const lowerExpectedName = expectedName.toLowerCase();
    for (const header of cookieHeaders) {
      if (header.length === 0 || header.length > MAX_WEB_COOKIE_HEADER_LENGTH ||
        header.includes('\r') || header.includes('\n')) {
        continue;
      }
      const pairs = header.split(';');
      for (const rawPair of pairs) {
        const pair = rawPair.trim();
        const separator = pair.indexOf('=');
        if (separator <= 0) continue;
        const name = pair.substring(0, separator).trim().toLowerCase();
        if (name !== lowerExpectedName) continue;
        return pair.substring(separator + 1).trim();
      }
    }
    return '';
  }

  private static safeMessage(value: string): string {
    let output = '';
    for (let index = 0; index < value.length && output.length < 160; index++) {
      const character = value.charAt(index);
      output += character === '\r' || character === '\n' ? ' ' : character;
    }
    return output.trim();
  }

  private static failed(message: string): GuangYuAuthResult {
    const result = new GuangYuAuthResult();
    result.message = message;
    return result;
  }
}
