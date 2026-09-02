import { LocalRuleSource, LocalRuleSourceCookie } from '../../model/LocalRuleSource';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../http/HttpClient';
import { LocalRuleExecutionLimits, LocalRuleFetchResult, LocalRuleRequestPlan } from './LocalRuleRuntimeTypes';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { LocalRuleUrlAnalyzer } from './LocalRuleUrlAnalyzer';

/** 在共享 HttpClient 外增加本地规则源专属的协议、状态码和响应预算。 */
export class LocalRuleHttpClient {
  private static cookieJars: Map<string, Record<string, string>> = new Map<string, Record<string, string>>();
  private static hydratedSources: Set<string> = new Set<string>();

  static async fetch(source: LocalRuleSource, rawAddress: string,
    variables: Record<string, string> = {}, keyword: string = '', page: number = 1): Promise<LocalRuleFetchResult> {
    let plan: LocalRuleRequestPlan;
    try {
      if (source.enabledCookieJar) {
        await LocalRuleHttpClient.hydrateCookies(source.bookSourceUrl);
      }
      plan = LocalRuleHttpClient.prepareRequest(source, rawAddress, variables, keyword, page);
    } catch (error) {
      return LocalRuleFetchResult.failed('', LocalRuleHttpClient.errorMessage(error));
    }
    const result = await LocalRuleHttpClient.execute(plan);
    if (source.enabledCookieJar && result.ok) {
      try {
        await LocalRuleHttpClient.captureCookies(source, plan.url, result.headers);
      } catch (_error) {
        // Cookie 持久化失败不能覆盖已经成功的内容请求。
      }
    }
    return result;
  }

  /** 生成与 fetch 完全一致的最终请求，但不建立网络连接。 */
  static prepareRequest(source: LocalRuleSource, rawAddress: string,
    variables: Record<string, string> = {}, keyword: string = '', page: number = 1): LocalRuleRequestPlan {
    const plan = LocalRuleUrlAnalyzer.analyze(source, rawAddress, variables, keyword, page);
    if (source.enabledCookieJar) LocalRuleHttpClient.applyCookies(source, plan);
    if (source.enabledCookieJar) LocalRuleHttpClient.applyVariableCookies(variables, plan);
    LocalRuleHttpClient.validateHeaders(plan.headers);
    return plan;
  }

  static async execute(plan: LocalRuleRequestPlan): Promise<LocalRuleFetchResult> {
    try {
      LocalRuleHttpClient.validateHeaders(plan.headers);
      const requestOptions: HttpRequestOptions = {
        method: plan.method,
        headers: plan.headers,
        body: plan.body,
        timeout: plan.timeoutMs,
        charset: plan.charset,
        retry: plan.retry
      };
      const response: HttpResponse = await HttpClient.request(plan.url, requestOptions);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return LocalRuleFetchResult.failed(plan.url, `HTTP ${response.statusCode}`, response.statusCode);
      }
      if (response.body.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) {
        return LocalRuleFetchResult.failed(plan.url,
          `响应超过 ${LocalRuleExecutionLimits.MAX_RESPONSE_CHARS} 字符`, response.statusCode);
      }
      const result = new LocalRuleFetchResult();
      result.ok = true;
      result.statusCode = response.statusCode;
      result.requestUrl = plan.url;
      result.headers = response.headers;
      result.body = response.body;
      return result;
    } catch (error) {
      return LocalRuleFetchResult.failed(plan.url, LocalRuleHttpClient.errorMessage(error));
    }
  }

  static async hydrateCookies(sourceUrl: string): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0 || LocalRuleHttpClient.hydratedSources.has(normalizedUrl)) return;
    try {
      const cookies: LocalRuleSourceCookie[] =
        await LocalRuleSourceRepository.listCookies(normalizedUrl);
      LocalRuleHttpClient.removeCachedSource(normalizedUrl);
      for (const cookie of cookies) {
        const jar = LocalRuleHttpClient.cookieHeaderToJar(cookie.cookieHeader);
        if (Object.keys(jar).length > 0) {
          LocalRuleHttpClient.cookieJars.set(
            LocalRuleHttpClient.cookieKey(normalizedUrl, cookie.origin), jar);
        }
      }
      LocalRuleHttpClient.hydratedSources.add(normalizedUrl);
    } catch (_error) {
      // 仓库尚未初始化时继续无 Cookie 请求，后续请求会再次尝试恢复。
    }
  }

  static async getStoredCookieHeader(sourceUrl: string, requestUrl: string): Promise<string> {
    await LocalRuleHttpClient.hydrateCookies(sourceUrl);
    const origin = LocalRuleHttpClient.requestOrigin(requestUrl);
    if (origin.length === 0) return '';
    const jar = LocalRuleHttpClient.cookieJars.get(
      LocalRuleHttpClient.cookieKey(sourceUrl.trim(), origin));
    return jar === undefined ? '' : LocalRuleHttpClient.serializeJar(jar);
  }

  /** 接收内嵌登录页抓取到的完整 Cookie Header，并立即供规则请求使用。 */
  static async saveWebCookies(sourceUrl: string, requestUrl: string,
    cookieHeader: string): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    const origin = LocalRuleHttpClient.requestOrigin(requestUrl);
    if (normalizedUrl.length === 0 || origin.length === 0) {
      throw new Error('网页登录 Cookie 作用域无效');
    }
    await LocalRuleHttpClient.hydrateCookies(normalizedUrl);
    const jar = LocalRuleHttpClient.cookieHeaderToJar(cookieHeader);
    const key = LocalRuleHttpClient.cookieKey(normalizedUrl, origin);
    if (Object.keys(jar).length === 0) {
      LocalRuleHttpClient.cookieJars.delete(key);
      await LocalRuleSourceRepository.clearCookie(normalizedUrl, origin);
      return;
    }
    LocalRuleHttpClient.cookieJars.set(key, jar);
    const cookie = LocalRuleSourceCookie.of(
      normalizedUrl, origin, LocalRuleHttpClient.serializeJar(jar));
    await LocalRuleSourceRepository.saveCookie(cookie);
    LocalRuleHttpClient.hydratedSources.add(normalizedUrl);
  }

  static async clearCookies(sourceUrl: string, requestUrl: string = ''): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) return;
    const origin = LocalRuleHttpClient.requestOrigin(requestUrl);
    if (origin.length > 0) {
      LocalRuleHttpClient.cookieJars.delete(LocalRuleHttpClient.cookieKey(normalizedUrl, origin));
      await LocalRuleSourceRepository.clearCookie(normalizedUrl, origin);
    } else {
      LocalRuleHttpClient.removeCachedSource(normalizedUrl);
      await LocalRuleSourceRepository.clearCookies(normalizedUrl);
    }
    LocalRuleHttpClient.hydratedSources.add(normalizedUrl);
  }

  static clearCookieCacheBatch(sourceUrls: string[]): void {
    for (const sourceUrl of sourceUrls) {
      const normalizedUrl = sourceUrl.trim();
      if (normalizedUrl.length > 0) LocalRuleHttpClient.removeCachedSource(normalizedUrl);
    }
  }

  static getSessionHeaders(source: LocalRuleSource, requestUrl: string,
    variables: Record<string, string> = {}): Record<string, string> {
    const plan = new LocalRuleRequestPlan();
    plan.url = requestUrl;
    plan.headers = LocalRuleUrlAnalyzer.parseHeaders(variables['__header'] ?? source.header);
    if (source.enabledCookieJar) LocalRuleHttpClient.applyCookies(source, plan);
    if (source.enabledCookieJar) LocalRuleHttpClient.applyVariableCookies(variables, plan);
    return plan.headers;
  }

  static getCookieHeader(source: LocalRuleSource, requestUrl: string): string {
    const headers = LocalRuleHttpClient.getSessionHeaders(source, requestUrl);
    const names = Object.keys(headers);
    for (const name of names) {
      if (name.toLowerCase() === 'cookie') return headers[name] ?? '';
    }
    return '';
  }

  private static applyCookies(source: LocalRuleSource, plan: LocalRuleRequestPlan): void {
    if (LocalRuleHttpClient.hasHeader(plan.headers, 'cookie')) return;
    const origin = LocalRuleHttpClient.requestOrigin(plan.url);
    if (!origin) return;
    const jar = LocalRuleHttpClient.cookieJars.get(
      LocalRuleHttpClient.cookieKey(source.bookSourceUrl, origin));
    const cookieHeader = jar === undefined ? '' : LocalRuleHttpClient.serializeJar(jar);
    if (cookieHeader.length > 0) plan.headers['Cookie'] = cookieHeader;
  }

  private static applyVariableCookies(variables: Record<string, string>, plan: LocalRuleRequestPlan): void {
    const scriptCookie = variables['__cookie'] ?? '';
    if (scriptCookie.trim().length === 0) return;
    const names = Object.keys(plan.headers);
    for (const name of names) {
      if (name.toLowerCase() !== 'cookie') continue;
      plan.headers[name] = LocalRuleHttpClient.mergeCookieHeaders(plan.headers[name] ?? '', scriptCookie);
      return;
    }
    plan.headers['Cookie'] = scriptCookie;
  }

  private static async captureCookies(source: LocalRuleSource, requestUrl: string,
    headers: Record<string, string>): Promise<void> {
    const origin = LocalRuleHttpClient.requestOrigin(requestUrl);
    if (!origin) return;
    const setCookieValues: string[] = [];
    const headerNames = Object.keys(headers);
    for (const name of headerNames) {
      if (name.toLowerCase() === 'set-cookie') {
        const value = headers[name] ?? '';
        if (value) setCookieValues.push(...value.split(new RegExp('\\r?\\n', 'g')));
      }
    }
    if (setCookieValues.length === 0) return;
    const jarKey = LocalRuleHttpClient.cookieKey(source.bookSourceUrl, origin);
    if (!LocalRuleHttpClient.cookieJars.has(jarKey) && LocalRuleHttpClient.cookieJars.size >= 64) {
      LocalRuleHttpClient.cookieJars.clear();
      LocalRuleHttpClient.hydratedSources.clear();
    }
    const existing = LocalRuleHttpClient.cookieJars.get(jarKey);
    const jar: Record<string, string> = existing ?? {};
    for (const rawHeader of setCookieValues) {
      const cookieLines = rawHeader.split(new RegExp(',(?=\\s*[A-Za-z0-9_\\-]+\\s*=)', 'g'));
      for (const cookieLine of cookieLines) {
        LocalRuleHttpClient.captureCookieLine(jar, cookieLine);
      }
    }
    const cookieHeader = LocalRuleHttpClient.serializeJar(jar);
    if (cookieHeader.length === 0) {
      LocalRuleHttpClient.cookieJars.delete(jarKey);
      await LocalRuleSourceRepository.clearCookie(source.bookSourceUrl, origin);
    } else {
      LocalRuleHttpClient.cookieJars.set(jarKey, jar);
      await LocalRuleSourceRepository.saveCookie(
        LocalRuleSourceCookie.of(source.bookSourceUrl, origin, cookieHeader));
    }
    LocalRuleHttpClient.hydratedSources.add(source.bookSourceUrl.trim());
  }

  private static mergeCookieHeaders(primary: string, secondary: string): string {
    const values: Record<string, string> = {};
    const headers: string[] = [primary, secondary];
    for (const header of headers) {
      const parts = header.split(';');
      for (const part of parts) {
        const item = part.trim();
        const separator = item.indexOf('=');
        if (separator <= 0) continue;
        const name = item.substring(0, separator).trim();
        const value = item.substring(separator + 1).trim();
        if (name && value) values[name] = value;
      }
    }
    const output: string[] = [];
    const names = Object.keys(values);
    for (const name of names) output.push(`${name}=${values[name] ?? ''}`);
    return output.join('; ');
  }

  private static captureCookieLine(jar: Record<string, string>, line: string): void {
    const firstPart = line.split(';')[0].trim();
    const separator = firstPart.indexOf('=');
    if (separator <= 0) return;
    const name = firstPart.substring(0, separator).trim();
    const value = firstPart.substring(separator + 1).trim();
    if (!new RegExp('^[A-Za-z0-9_\\-]+$').test(name) || name.length > 128 || value.length > 4096) return;
    const lowerLine = line.toLowerCase();
    if (!value || lowerLine.includes('max-age=0')) {
      jar[name] = '';
      return;
    }
    if (Object.keys(jar).length < 50 || jar[name] !== undefined) jar[name] = value;
  }

  private static cookieHeaderToJar(cookieHeader: string): Record<string, string> {
    const jar: Record<string, string> = {};
    const parts = cookieHeader.split(';');
    for (const part of parts) {
      const item = part.trim();
      const separator = item.indexOf('=');
      if (separator <= 0) continue;
      const name = item.substring(0, separator).trim();
      const value = item.substring(separator + 1).trim();
      if (!new RegExp('^[A-Za-z0-9_\\-]+$').test(name) || name.length > 128 ||
        value.length === 0 || value.length > 4096) continue;
      if (Object.keys(jar).length < 50 || jar[name] !== undefined) jar[name] = value;
    }
    return jar;
  }

  private static serializeJar(jar: Record<string, string>): string {
    const pairs: string[] = [];
    const names = Object.keys(jar);
    for (const name of names) {
      const value = jar[name] ?? '';
      if (name.length > 0 && value.length > 0) pairs.push(`${name}=${value}`);
    }
    return pairs.join('; ');
  }

  private static cookieKey(sourceUrl: string, origin: string): string {
    return `${sourceUrl.trim()}\n${origin}`;
  }

  private static removeCachedSource(sourceUrl: string): void {
    const prefix = `${sourceUrl.trim()}\n`;
    const keys: string[] = [];
    LocalRuleHttpClient.cookieJars.forEach((_value: Record<string, string>, key: string): void => {
      if (key.startsWith(prefix)) keys.push(key);
    });
    for (const key of keys) LocalRuleHttpClient.cookieJars.delete(key);
    LocalRuleHttpClient.hydratedSources.delete(sourceUrl.trim());
  }

  private static hasHeader(headers: Record<string, string>, expectedName: string): boolean {
    const keys = Object.keys(headers);
    for (const key of keys) {
      if (key.toLowerCase() === expectedName.toLowerCase()) return true;
    }
    return false;
  }

  static requestOrigin(url: string): string {
    const schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return '';
    const scheme = url.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') return '';
    const start = schemeEnd + 3;
    let end = url.length;
    const slash = url.indexOf('/', start);
    const query = url.indexOf('?', start);
    const hash = url.indexOf('#', start);
    if (slash >= 0) end = Math.min(end, slash);
    if (query >= 0) end = Math.min(end, query);
    if (hash >= 0) end = Math.min(end, hash);
    const authority = url.substring(start, end).trim().toLowerCase();
    if (authority.length === 0 || authority.includes(' ') || authority.includes('\\')) return '';
    return `${scheme}://${authority}`;
  }

  private static validateHeaders(headers: Record<string, string>): void {
    const keys = Object.keys(headers);
    for (const key of keys) {
      const value = headers[key] ?? '';
      if (!key.trim() || key.includes(':') || key.includes('\r') || key.includes('\n') ||
        value.includes('\r') || value.includes('\n')) {
        throw new Error('请求头包含非法字符');
      }
    }
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '规则源网络请求失败';
    return String(error || '规则源网络请求失败');
  }
}
