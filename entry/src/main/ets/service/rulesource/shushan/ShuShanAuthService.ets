import { buffer } from '@kit.ArkTS';
import { LocalRuleSourceSession } from '../../../model/LocalRuleSource';
import { JsonObj } from '../../builtin/JsonValue';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../http/HttpClient';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { ShuShanApiClient } from './ShuShanApiClient';
import { SHU_SHAN_SOURCE_URL } from './ShuShanSourceIdentity';

const DEFAULT_HOST: string = 'https://v1.vossc.com';
const HEALTH_PATH: string = '/api/get_config';
const SOURCE_ACCESS_TOKEN: string = 'SHUSAN_READ_2025';
const HEALTH_TIMEOUT_MS: number = 5000;
const LOGIN_TIMEOUT_MS: number = 10000;
const LOGOUT_TIMEOUT_MS: number = 5000;
const MAX_RESPONSE_BYTES: number = 64 * 1024;
const MAX_EMAIL_LENGTH: number = 320;
const MAX_PASSWORD_LENGTH: number = 1024;
const MIN_API_KEY_LENGTH: number = 10;
const MAX_API_KEY_LENGTH: number = 4096;

export class ShuShanAccountState {
  loggedIn: boolean = false;
  accountLabel: string = '';
}

export class ShuShanAuthResult {
  success: boolean = false;
  message: string = '';
  accountLabel: string = '';
}

/** 书山聚合账号会话。密码仅提交一次，不写日志、书源 JSON 或本地数据库。 */
export class ShuShanAuthService {
  private static loginInProgress: boolean = false;
  private static preferredHost: string = '';

  static async getState(): Promise<ShuShanAccountState> {
    const state = new ShuShanAccountState();
    try {
      const session = await LocalRuleSourceRepository.getSession(SHU_SHAN_SOURCE_URL);
      if (session !== undefined && ShuShanAuthService.isValidApiKey(session.token)) {
        state.loggedIn = true;
        state.accountLabel = session.accountLabel;
      }
    } catch (_error) {
      // 会话缺失或损坏按未登录处理，不能影响书源管理和匿名小说内容。
    }
    return state;
  }

  static async login(email: string, password: string): Promise<ShuShanAuthResult> {
    const normalizedEmail = email.trim();
    const invalidInput = ShuShanAuthService.validateInput(normalizedEmail, password);
    if (invalidInput.length > 0) return ShuShanAuthService.failed(invalidInput);
    if (ShuShanAuthService.loginInProgress) {
      return ShuShanAuthService.failed('登录请求正在处理中，请稍候');
    }

    ShuShanAuthService.loginInProgress = true;
    try {
      const host = await ShuShanAuthService.selectHealthyHost();
      if (host.length === 0) {
        return ShuShanAuthService.failed('暂时无法连接书山聚合登录服务，请稍后重试');
      }
      const deviceId = await ShuShanApiClient.getOrCreateDeviceId();
      const headers: Record<string, string> = {};
      headers['Accept'] = 'application/json';
      headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
      headers['X-Novel-Token'] = SOURCE_ACCESS_TOKEN;
      const requestBody = `email=${encodeURIComponent(normalizedEmail)}` +
        `&password=${encodeURIComponent(password)}`;
      const options: HttpRequestOptions = {
        method: 'POST',
        headers: headers,
        body: requestBody,
        timeout: LOGIN_TIMEOUT_MS,
        charset: 'utf-8',
        retry: 0
      };
      // 凭据禁止重试或跨线路重放，只提交给健康探测选中的这一条线路。
      const response = await HttpClient.request(host + '/login', options);
      return await ShuShanAuthService.handleLoginResponse(response, normalizedEmail, deviceId);
    } catch (_error) {
      return ShuShanAuthService.failed('登录失败，请检查网络后重试');
    } finally {
      ShuShanAuthService.loginInProgress = false;
    }
  }

  static async logout(): Promise<void> {
    let rawApiKey = '';
    try {
      const session = await LocalRuleSourceRepository.getSession(SHU_SHAN_SOURCE_URL);
      if (session !== undefined && ShuShanAuthService.isValidApiKey(session.token)) {
        rawApiKey = session.token;
      }
    } catch (_error) {
      rawApiKey = '';
    }

    const deviceId = await ShuShanApiClient.getOrCreateDeviceId();
    if (rawApiKey.length > 0) {
      await ShuShanAuthService.notifyServerLogout(rawApiKey, deviceId);
    }
    const anonymousSession = LocalRuleSourceSession.of(SHU_SHAN_SOURCE_URL, '', deviceId, '');
    await LocalRuleSourceRepository.saveSession(anonymousSession);
  }

  static registrationUrl(): string {
    const host = ShuShanAuthService.isAllowedHost(ShuShanAuthService.preferredHost)
      ? ShuShanAuthService.preferredHost : DEFAULT_HOST;
    return host + '/user_login';
  }

  private static async selectHealthyHost(): Promise<string> {
    const hosts = ShuShanApiClient.hosts();
    const cached = ShuShanAuthService.preferredHost;
    if (ShuShanAuthService.isAllowedHost(cached) && await ShuShanAuthService.probeHost(cached)) {
      return cached;
    }

    const tasks: Promise<boolean>[] = [];
    for (const host of hosts) {
      tasks.push(ShuShanAuthService.probeHost(host));
    }
    const healthy: boolean[] = await Promise.all<boolean>(tasks);
    for (let index = 0; index < hosts.length; index++) {
      if (healthy[index]) {
        ShuShanAuthService.preferredHost = hosts[index];
        return hosts[index];
      }
    }
    return '';
  }

  private static async probeHost(host: string): Promise<boolean> {
    if (!ShuShanAuthService.isAllowedHost(host)) return false;
    const headers: Record<string, string> = {};
    headers['Accept'] = 'application/json';
    headers['X-Novel-Token'] = SOURCE_ACCESS_TOKEN;
    const options: HttpRequestOptions = {
      method: 'GET',
      headers: headers,
      timeout: HEALTH_TIMEOUT_MS,
      charset: 'utf-8',
      retry: 0
    };
    try {
      const response = await HttpClient.request(host + HEALTH_PATH, options);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
        !ShuShanAuthService.hasBoundedBody(response.body) || response.body.trim().length === 0) {
        return false;
      }
      JSON.parse(response.body) as Object;
      return true;
    } catch (_error) {
      return false;
    }
  }

  private static async notifyServerLogout(rawApiKey: string, deviceId: string): Promise<void> {
    const host = ShuShanAuthService.isAllowedHost(ShuShanAuthService.preferredHost)
      ? ShuShanAuthService.preferredHost : DEFAULT_HOST;
    const headers: Record<string, string> = {};
    headers['Accept'] = 'application/json';
    headers['Content-Type'] = 'application/json';
    headers['X-Novel-Token'] = SOURCE_ACCESS_TOKEN;
    headers['X-Api-Key'] = buffer.from(rawApiKey, 'utf-8').toString('base64');
    headers['X-Device-Type'] = 'android';
    headers['X-Device-Id'] = deviceId;
    const options: HttpRequestOptions = {
      method: 'POST',
      headers: headers,
      timeout: LOGOUT_TIMEOUT_MS,
      charset: 'utf-8',
      retry: 0
    };
    try {
      await HttpClient.request(host + '/api/logout', options);
    } catch (_error) {
      // 与原书源一致：服务端退出失败也要清除本地凭据。
    }
  }

  private static async handleLoginResponse(response: HttpResponse, accountLabel: string,
    deviceId: string): Promise<ShuShanAuthResult> {
    if (!ShuShanAuthService.hasBoundedBody(response.body)) {
      return ShuShanAuthService.failed('登录服务响应过大，已拒绝处理');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return ShuShanAuthService.failed(`登录失败：服务返回 HTTP ${response.statusCode}`);
    }

    let parsed: Object;
    try {
      parsed = JSON.parse(response.body) as Object;
    } catch (_error) {
      return ShuShanAuthService.failed('登录服务返回了无效数据');
    }
    const root = new JsonObj(parsed);
    if (root.getInt('code', -1) !== 200) {
      const serverMessage = ShuShanAuthService.responseMessage(root);
      return ShuShanAuthService.failed(serverMessage.length > 0
        ? `登录失败：${serverMessage}` : '登录失败，请检查账号或密码');
    }
    const apiKey = root.getObj('data').getObj('user').getString('api_key');
    if (!ShuShanAuthService.isValidApiKey(apiKey)) {
      return ShuShanAuthService.failed('登录服务未返回有效 API key');
    }

    // 保存服务端原始 api_key；Base64 仅由 API 客户端在构造请求头时完成。
    const session = LocalRuleSourceSession.of(SHU_SHAN_SOURCE_URL, apiKey, deviceId, accountLabel);
    try {
      await LocalRuleSourceRepository.saveSession(session);
    } catch (_error) {
      return ShuShanAuthService.failed('登录成功，但会话保存失败');
    }
    const result = new ShuShanAuthResult();
    result.success = true;
    result.message = '登录成功';
    result.accountLabel = accountLabel;
    return result;
  }

  private static responseMessage(root: JsonObj): string {
    let message = root.getString('message').trim();
    if (message.length === 0) message = root.getString('msg').trim();
    if (message.length === 0) message = root.getObj('data').getString('message').trim();
    return ShuShanAuthService.safeMessage(message);
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

  private static isValidApiKey(apiKey: string): boolean {
    return apiKey.length >= MIN_API_KEY_LENGTH && apiKey.length <= MAX_API_KEY_LENGTH &&
      !apiKey.includes('\r') && !apiKey.includes('\n') && !apiKey.includes(';');
  }

  private static isAllowedHost(host: string): boolean {
    const hosts = ShuShanApiClient.hosts();
    for (const allowed of hosts) {
      if (host === allowed && host.startsWith('https://')) return true;
    }
    return false;
  }

  private static safeMessage(value: string): string {
    let output = '';
    for (let index = 0; index < value.length && output.length < 160; index++) {
      const character = value.charAt(index);
      output += character === '\r' || character === '\n' ? ' ' : character;
    }
    return output.trim();
  }

  private static failed(message: string): ShuShanAuthResult {
    const result = new ShuShanAuthResult();
    result.message = message;
    return result;
  }
}
