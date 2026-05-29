/**
 * CookieManager - Cookie 管理器
 *
 * 双重职责：
 *  1) 书源 JS 规则中 cookie.xxx 方法（按 url 整段保存）
 *  2) HttpClient 自动 cookie jar：按 (host, path) 维度持久化每个 cookie
 */

interface CookieEntry {
  name: string;
  value: string;
  path: string;
  expiresAt: number;  // 0 = session
  secure: boolean;
}

interface ParsedSetCookie {
  host: string;
  entry: CookieEntry;
}

class CookieManagerImpl {
  // 旧接口：整段字符串按域名存（书源 JS 用）
  private rawCookies: Map<string, string> = new Map();

  // 新接口：按 host → cookie name → entry
  private jar: Map<string, Map<string, CookieEntry>> = new Map();

  // ---------------- 旧接口（书源 JS） ----------------

  removeCookie(url: string): void {
    const domain = this.extractDomain(url);
    this.rawCookies.delete(domain);
    this.jar.delete(domain);
  }

  getCookie(url: string): string {
    const domain = this.extractDomain(url);
    const raw = this.rawCookies.get(domain);
    if (raw) return raw;
    return this.getCookieHeader(url);
  }

  setCookie(url: string, cookie: string): void {
    const domain = this.extractDomain(url);
    this.rawCookies.set(domain, cookie);
  }

  // ---------------- HttpClient cookie jar ----------------

  /** 请求前：把该 host 已存的 cookie 拼成 "name=value; name2=value2" */
  getCookieHeader(url: string): string {
    const domain = this.extractDomain(url);
    const path = this.extractPath(url);
    const now = Date.now();
    const items: string[] = [];

    // 当前域 + 父域（subdomain 共享）
    for (const host of this.jar.keys()) {
      if (!this.hostMatches(domain, host)) continue;
      const map = this.jar.get(host);
      if (!map) continue;
      for (const entry of map.values()) {
        if (entry.expiresAt > 0 && entry.expiresAt < now) continue;
        if (!path.startsWith(entry.path || '/')) continue;
        items.push(`${entry.name}=${entry.value}`);
      }
    }
    return items.join('; ');
  }

  /** 响应后：把响应头里的 Set-Cookie 解析进 jar。支持多 cookie（鸿蒙 header 会用 \n 或逗号拼接） */
  acceptResponseCookies(url: string, headers: Record<string, string>): void {
    if (!headers) return;
    let raw: string | undefined = undefined;
    for (const k of Object.keys(headers)) {
      if (k.toLowerCase() === 'set-cookie') {
        raw = headers[k];
        break;
      }
    }
    if (!raw) return;
    const domain = this.extractDomain(url);

    // 多个 Set-Cookie 用 \n 分隔（鸿蒙）；保险起见也按 ", " 分一下，但要避开 expires 中的逗号
    const lines = this.splitSetCookieHeader(raw);
    for (const line of lines) {
      const parsed = this.parseSetCookie(line, domain);
      if (!parsed) continue;
      const host = parsed.host;
      let map = this.jar.get(host);
      if (!map) {
        map = new Map<string, CookieEntry>();
        this.jar.set(host, map);
      }
      map.set(parsed.entry.name, parsed.entry);
    }
  }

  // ---------------- 工具 ----------------

  private hostMatches(reqHost: string, cookieHost: string): boolean {
    if (reqHost === cookieHost) return true;
    if (cookieHost.startsWith('.')) {
      // .example.com 匹配 sub.example.com
      return reqHost.endsWith(cookieHost) || reqHost === cookieHost.substring(1);
    }
    return false;
  }

  private splitSetCookieHeader(raw: string): string[] {
    // 优先按 \n 切；否则尝试按"逗号 + 空格 + 字母="切（避开 expires 里的逗号）
    if (raw.includes('\n')) return raw.split('\n').map((s) => s.trim()).filter((s) => s.length > 0);
    const parts: string[] = [];
    let buf = '';
    let i = 0;
    while (i < raw.length) {
      if (raw[i] === ',' && /\s/.test(raw[i + 1] || '')) {
        // 看下一段是否是 "name=" 形式
        const ahead = raw.substring(i + 1).replace(/^\s+/, '');
        if (/^[\w\-!#$%&'*+.^`|~]+=/.test(ahead)) {
          parts.push(buf.trim());
          buf = '';
          i = raw.indexOf(ahead[0], i + 1);
          continue;
        }
      }
      buf += raw[i];
      i++;
    }
    if (buf.trim()) parts.push(buf.trim());
    return parts;
  }

  private parseSetCookie(line: string, defaultHost: string): ParsedSetCookie | null {
    // name=value; Domain=...; Path=/; Expires=...; Max-Age=...; Secure; HttpOnly; SameSite=...
    const segs = line.split(';').map((s) => s.trim()).filter((s) => s.length > 0);
    if (segs.length === 0) return null;
    const eq = segs[0].indexOf('=');
    if (eq < 0) return null;
    const name = segs[0].substring(0, eq).trim();
    const value = segs[0].substring(eq + 1).trim();
    if (!name) return null;

    let host = defaultHost;
    let path = '/';
    let expiresAt = 0;
    let secure = false;

    for (let i = 1; i < segs.length; i++) {
      const seg = segs[i];
      const lower = seg.toLowerCase();
      if (lower.startsWith('domain=')) {
        host = seg.substring(7).trim().replace(/^\./, '');
        // legacy: cookies with explicit Domain are scoped to subdomains via leading dot
        host = '.' + host;
      } else if (lower.startsWith('path=')) {
        path = seg.substring(5).trim() || '/';
      } else if (lower.startsWith('expires=')) {
        const t = Date.parse(seg.substring(8).trim());
        if (!Number.isNaN(t)) expiresAt = t;
      } else if (lower.startsWith('max-age=')) {
        const sec = parseInt(seg.substring(8).trim(), 10);
        if (!Number.isNaN(sec)) expiresAt = Date.now() + sec * 1000;
      } else if (lower === 'secure') {
        secure = true;
      }
    }

    const entry: CookieEntry = { name, value, path, expiresAt, secure };
    const result: ParsedSetCookie = { host, entry };
    return result;
  }

  private extractDomain(url: string): string {
    const match = url.match(/^https?:\/\/([^\/]+)/);
    if (!match) return url;
    const hostport = match[1];
    return hostport.split(':')[0];
  }

  private extractPath(url: string): string {
    const match = url.match(/^https?:\/\/[^\/]+(\/[^?#]*)/);
    return match ? match[1] : '/';
  }

  clear(): void {
    this.rawCookies.clear();
    this.jar.clear();
  }
}

let globalManager: CookieManagerImpl | null = null;

export function getCookieManager(): CookieManagerImpl {
  if (!globalManager) {
    globalManager = new CookieManagerImpl();
  }
  return globalManager;
}
