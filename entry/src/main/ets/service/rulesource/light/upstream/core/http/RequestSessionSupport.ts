import { CookieStore } from './CookieStore';

export interface RequestSessionConfig {
  queryCookies: Record<string, string>;
  generatedCookies: Record<string, string>;
  referer: string;
}

/**
 * Applies source-declared session rules to one HTTP(S) destination.
 *
 * The implementation intentionally has no site registry or host-specific defaults. Cookie reads
 * and writes always use the request URL, so a session rule cannot silently reuse another domain's
 * cookie jar.
 */
export class RequestSessionSupport {
  static emptyConfig(): RequestSessionConfig {
    return { queryCookies: {}, generatedCookies: {}, referer: '' };
  }

  static parseConfig(value: Object | null | undefined): RequestSessionConfig {
    const config = this.emptyConfig();
    if (!value || typeof value !== 'object' || Array.isArray(value)) return config;
    const raw = value as Record<string, Object>;
    config.queryCookies = this.parseQueryCookies(raw['queryCookies']);
    config.generatedCookies = this.parseStringMap(raw['generatedCookies']);
    if (raw['referer'] !== undefined && raw['referer'] !== null) {
      config.referer = String(raw['referer']).trim();
    }
    return config;
  }

  static apply(requestUrl: string, headers: Record<string, string>, config: RequestSessionConfig,
    sourceUrl: string = ''): void {
    const cleanUrl = (requestUrl || '').trim();
    if (!/^https?:\/\//i.test(cleanUrl) || !config) return;
    if (Object.keys(config.queryCookies || {}).length === 0 &&
      Object.keys(config.generatedCookies || {}).length === 0 && !config.referer) return;

    const cookieHeaderName = this.headerName(headers, 'cookie');
    let cookies = CookieStore.forSource(sourceUrl).getCookie(cleanUrl);
    if (cookieHeaderName) {
      // Explicit source headers have priority over values already stored for this destination.
      cookies = this.mergeCookies(cookies, String(headers[cookieHeaderName] || ''));
    }

    let cookieStoreChanged = false;
    for (const cookieName of Object.keys(config.queryCookies || {})) {
      if (!this.isCookieName(cookieName)) continue;
      const queryName = config.queryCookies[cookieName] || cookieName;
      const value = this.queryValue(cleanUrl, queryName);
      if (!value) continue;
      cookies = this.mergeCookies(cookies, `${cookieName}=${value}`);
      CookieStore.forSource(sourceUrl).setCookies(cleanUrl, `${cookieName}=${value}; Path=/`);
      cookieStoreChanged = true;
    }

    for (const cookieName of Object.keys(config.generatedCookies || {})) {
      if (!this.isCookieName(cookieName) || this.cookieValue(cookies, cookieName)) continue;
      const value = this.generatedValue(config.generatedCookies[cookieName], cleanUrl);
      if (!value) continue;
      cookies = this.mergeCookies(cookies, `${cookieName}=${value}`);
      CookieStore.forSource(sourceUrl).setCookies(cleanUrl, `${cookieName}=${value}; Max-Age=31536000; Path=/`);
      cookieStoreChanged = true;
    }

    if (cookies) headers[cookieHeaderName || 'Cookie'] = cookies;
    if (config.referer && !this.headerName(headers, 'referer')) {
      const referer = this.resolveReferer(config.referer, cleanUrl);
      if (referer) headers['Referer'] = referer;
    }
    if (cookieStoreChanged) CookieStore.forSource(sourceUrl).saveAsync();
  }

  private static parseQueryCookies(value: Object | undefined): Record<string, string> {
    const result: Record<string, string> = {};
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const name = String(item || '').trim();
        if (this.isCookieName(name)) result[name] = name;
      }
      return result;
    }
    if (typeof value === 'string') {
      for (const item of String(value).split(',')) {
        const name = item.trim();
        if (this.isCookieName(name)) result[name] = name;
      }
      return result;
    }
    return this.parseStringMap(value);
  }

  private static parseStringMap(value: Object | undefined): Record<string, string> {
    const result: Record<string, string> = {};
    if (!value || typeof value !== 'object' || Array.isArray(value)) return result;
    const source = value as Record<string, Object>;
    for (const key of Object.keys(source)) {
      const name = String(key || '').trim();
      if (this.isCookieName(name) && source[key] !== undefined && source[key] !== null) {
        result[name] = String(source[key]);
      }
    }
    return result;
  }

  private static generatedValue(template: string, requestUrl: string): string {
    const value = (template || '').trim();
    const timestamp = String(Date.now());
    const random = String(Math.floor(Math.random() * 1000000000));
    if (value === '@uuid') return this.uuid();
    if (value === '@timestamp_random') return `${timestamp}_${random}`;
    if (value === '@random') return random;
    return value
      .replace(/\{\{timestamp\}\}/g, timestamp)
      .replace(/\{\{random\}\}/g, random)
      .replace(/\{\{uuid\}\}/g, this.uuid())
      .replace(/\{\{origin\}\}/g, this.originOf(requestUrl))
      .replace(/\{\{url\}\}/g, requestUrl);
  }

  private static resolveReferer(rule: string, requestUrl: string): string {
    const value = (rule || '').trim();
    if (value.toLowerCase() === 'origin') return this.originOf(requestUrl);
    if (value.toLowerCase() === 'request') return requestUrl;
    return this.generatedValue(value, requestUrl);
  }

  private static originOf(url: string): string {
    const match = /^(https?:\/\/[^/?#]+)/i.exec(url || '');
    return match && match[1] ? `${match[1]}/` : '';
  }

  private static queryValue(url: string, name: string): string {
    if (!name) return '';
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = (url || '').match(new RegExp(`[?&]${escaped}=([^&#]*)`, 'i'));
    if (!match) return '';
    try {
      return decodeURIComponent(match[1].replace(/\+/g, '%20'));
    } catch (_) {
      return match[1];
    }
  }

  private static mergeCookies(primary: string, secondary: string): string {
    const values: Record<string, string> = {};
    for (const header of [primary || '', secondary || '']) {
      for (const part of header.split(';')) {
        const item = part.trim();
        const index = item.indexOf('=');
        if (index <= 0) continue;
        values[item.substring(0, index).trim()] = item.substring(index + 1).trim();
      }
    }
    return Object.keys(values).map((key: string) => `${key}=${values[key]}`).join('; ');
  }

  private static cookieValue(cookies: string, name: string): string {
    for (const part of (cookies || '').split(';')) {
      const item = part.trim();
      const index = item.indexOf('=');
      if (index > 0 && item.substring(0, index).trim() === name) {
        return item.substring(index + 1).trim();
      }
    }
    return '';
  }

  private static headerName(headers: Record<string, string>, name: string): string {
    const lower = (name || '').toLowerCase();
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === lower) return key;
    }
    return '';
  }

  private static isCookieName(value: string): boolean {
    return /^[A-Za-z0-9_.-]+$/.test(value || '');
  }

  private static uuid(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (item: string) => {
      const random = Math.floor(Math.random() * 16);
      const value = item === 'x' ? random : (random & 0x3) | 0x8;
      return value.toString(16);
    });
  }
}
