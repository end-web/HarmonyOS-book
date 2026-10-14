import { LocalRuleSource, LocalRuleSourceCookie } from '../../../model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { LocalRuleFetchResult, LocalRuleRequestPlan } from '../LocalRuleRuntimeTypes';
import { HttpClient, HttpRequestOptions } from '../../http/HttpClient';
import { LightSourceBridge } from './LightSourceBridge';

export class LightPersistedCookieRecord {
  url: string = '';
  cookie: string = '';
}

/** Encrypted persistence adapter. It contains no source rules or URL interpreter. */
export class LightSourceCookies {
  static async getStoredCookieRecords(sourceUrl: string): Promise<LightPersistedCookieRecord[]> {
    const state: Record<string, Object> = JSON.parse(await LocalRuleSourceRepository.readScriptState(sourceUrl) || '{}');
    const records: LightPersistedCookieRecord[] = JSON.parse(JSON.stringify(state['lightCookieRecords'] ?? []));
    return records.filter(record => LightSourceCookies.requestOrigin(record.url).length > 0 &&
      record.cookie.length > 0);
  }
  private static async syncCookieRecords(sourceUrl: string, requestUrl: string,
    jar: Record<string, string>): Promise<void> {
    if (!LocalRuleSourceRepository.isInitialized()) return;
    const state: Record<string, Object> = JSON.parse(await LocalRuleSourceRepository.readScriptState(sourceUrl) || '{}');
    const records = await LightSourceCookies.getStoredCookieRecords(sourceUrl);
    const origin = LightSourceCookies.requestOrigin(requestUrl);
    const output: LightPersistedCookieRecord[] = [];
    const known = new Set<string>();
    for (const record of records) {
      if (LightSourceCookies.requestOrigin(record.url) !== origin) { output.push(record); continue; }
      const path = /^https?:\/\/[^/?#]+([^?#]*)/i.exec(requestUrl)?.[1] || '/';
      const declaredPath = /;\s*path=([^;]*)/i.exec(record.cookie)?.[1] ||
        ((/^https?:\/\/[^/?#]+([^?#]*)/i.exec(record.url)?.[1] || '/').replace(/\/[^/]*$/, '') || '/');
      if (!(path === declaredPath || (path.startsWith(declaredPath) &&
        (declaredPath.endsWith('/') || path.charAt(declaredPath.length) === '/'))) ||
        (/;\s*secure(?:;|$)/i.test(record.cookie) && !requestUrl.startsWith('https:'))) {
        output.push(record); continue;
      }
      const name = record.cookie.substring(0, record.cookie.indexOf('=')).trim();
      if (jar[name] !== undefined) {
        record.cookie = `${name}=${jar[name]}` + record.cookie.substring(record.cookie.indexOf(';') >= 0 ?
          record.cookie.indexOf(';') : record.cookie.length);
        known.add(name);
        output.push(record);
      }
    }
    for (const name of Object.keys(jar)) {
      if (known.has(name)) continue;
      const record = new LightPersistedCookieRecord();
      record.url = origin + '/';
      record.cookie = `${name}=${jar[name]}; Path=/`;
      output.push(record);
    }
    state['lightCookieRecords'] = output;
    await LocalRuleSourceRepository.writeScriptState(sourceUrl, JSON.stringify(state));
  }
  static async execute(plan: LocalRuleRequestPlan): Promise<LocalRuleFetchResult> {
    const options: HttpRequestOptions = {method:plan.method,headers:plan.headers,body:plan.body,
      timeout:plan.timeoutMs,charset:plan.charset,retry:0,autoRedirect:plan.followRedirects};
    const response = await HttpClient.request(plan.url,options);
    const result = new LocalRuleFetchResult();
    result.requestUrl = response.url ?? plan.url;
    result.statusCode = response.statusCode;
    result.headers = response.headers;
    result.body = response.body;
    result.ok = response.statusCode >= 200 && response.statusCode < 400;
    result.errorMessage = result.ok ? '' : `HTTP ${response.statusCode}`;
    return result;
  }
  private static cookieJars: Map<string, Record<string, string>> = new Map();
  private static hydratedSources: Set<string> = new Set();
  static async hydrateCookies(sourceUrl: string): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0 || LightSourceCookies.hydratedSources.has(normalizedUrl)) return;
    try {
      const cookies: LocalRuleSourceCookie[] =
        await LocalRuleSourceRepository.listCookies(normalizedUrl);
      LightSourceCookies.removeCachedSource(normalizedUrl);
      for (const cookie of cookies) {
        const jar = LightSourceCookies.cookieHeaderToJar(cookie.cookieHeader);
        if (Object.keys(jar).length > 0) {
          LightSourceCookies.cookieJars.set(
            LightSourceCookies.cookieKey(normalizedUrl, cookie.origin), jar);
        }
      }
      LightSourceCookies.hydratedSources.add(normalizedUrl);
    } catch (_error) {
      // 仓库尚未初始化时继续无 Cookie 请求，后续请求会再次尝试恢复。
    }
  }

  static async getStoredCookieHeader(sourceUrl: string, requestUrl: string): Promise<string> {
    await LightSourceCookies.hydrateCookies(sourceUrl);
    const origin = LightSourceCookies.requestOrigin(requestUrl);
    if (origin.length === 0) return '';
    const jar = LightSourceCookies.cookieJars.get(
      LightSourceCookies.cookieKey(sourceUrl.trim(), origin));
    return jar === undefined ? '' : LightSourceCookies.serializeJar(jar);
  }

  static async getCookieSnapshot(sourceUrl: string): Promise<Record<string, string>> {
    await LightSourceCookies.hydrateCookies(sourceUrl);
    const result: Record<string, string> = {};
    const prefix = `${sourceUrl}\n`;
    LightSourceCookies.cookieJars.forEach((jar: Record<string, string>, key: string): void => {
      if (key.startsWith(prefix)) result[key.substring(prefix.length)] = LightSourceCookies.serializeJar(jar);
    });
    return result;
  }

  static async saveWebCookies(sourceUrl: string, requestUrl: string,
    cookieHeader: string, preserveRecords: boolean = false): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    const origin = LightSourceCookies.requestOrigin(requestUrl);
    if (normalizedUrl.length === 0 || origin.length === 0) {
      throw new Error('网页登录 Cookie 作用域无效');
    }
    await LightSourceCookies.hydrateCookies(normalizedUrl);
    const jar = LightSourceCookies.cookieHeaderToJar(cookieHeader);
    if (!preserveRecords) await LightSourceCookies.syncCookieRecords(normalizedUrl, requestUrl, jar);
    const key = LightSourceCookies.cookieKey(normalizedUrl, origin);
    if (Object.keys(jar).length === 0) {
      LightSourceCookies.cookieJars.delete(key);
      if (LocalRuleSourceRepository.isInitialized()) await LocalRuleSourceRepository.clearCookie(normalizedUrl, origin);
      return;
    }
    LightSourceCookies.cookieJars.set(key, jar);
    const cookie = LocalRuleSourceCookie.of(
      normalizedUrl, origin, LightSourceCookies.serializeJar(jar));
    if (LocalRuleSourceRepository.isInitialized()) await LocalRuleSourceRepository.saveCookie(cookie);
    LightSourceCookies.hydratedSources.add(normalizedUrl);
  }

  static async clearCookies(sourceUrl: string, requestUrl: string = ''): Promise<void> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) return;
    const origin = LightSourceCookies.requestOrigin(requestUrl);
    if (LocalRuleSourceRepository.isInitialized()) {
      const state: Record<string, Object> = JSON.parse(await LocalRuleSourceRepository.readScriptState(normalizedUrl) || '{}');
      const records = await LightSourceCookies.getStoredCookieRecords(normalizedUrl);
      state['lightCookieRecords'] = origin ? records.filter(record =>
        LightSourceCookies.requestOrigin(record.url) !== origin) : [];
      await LocalRuleSourceRepository.writeScriptState(normalizedUrl,JSON.stringify(state));
    }
    if (origin.length > 0) {
      LightSourceCookies.cookieJars.delete(LightSourceCookies.cookieKey(normalizedUrl, origin));
      await LocalRuleSourceRepository.clearCookie(normalizedUrl, origin);
    } else {
      LightSourceCookies.removeCachedSource(normalizedUrl);
      await LocalRuleSourceRepository.clearCookies(normalizedUrl);
    }
    LightSourceCookies.hydratedSources.add(normalizedUrl);
  }

  static clearCookieCacheBatch(sourceUrls: string[]): void {
    for (const sourceUrl of sourceUrls) {
      const normalizedUrl = sourceUrl.trim();
      if (normalizedUrl.length > 0) LightSourceCookies.removeCachedSource(normalizedUrl);
    }
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
      if (!new RegExp('^[A-Za-z0-9_.-]+$').test(name) || name.length > 128 ||
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
    LightSourceCookies.cookieJars.forEach((_value: Record<string, string>, key: string): void => {
      if (key.startsWith(prefix)) keys.push(key);
    });
    for (const key of keys) LightSourceCookies.cookieJars.delete(key);
    LightSourceCookies.hydratedSources.delete(sourceUrl.trim());
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
  static async fetch(source: LocalRuleSource, address: string): Promise<LocalRuleFetchResult> {
    return LightSourceBridge.fetch(source, address);
  }
  static getCookieHeader(source: LocalRuleSource, requestUrl: string): string {
    const jar = LightSourceCookies.cookieJars.get(LightSourceCookies.cookieKey(source.bookSourceUrl, LightSourceCookies.requestOrigin(requestUrl)));
    return jar === undefined ? '' : LightSourceCookies.serializeJar(jar);
  }
}
