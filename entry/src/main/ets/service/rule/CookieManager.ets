/**
 * CookieManager - Cookie 管理器（书源 JS 规则中的 cookie.xxx 方法）
 *
 * 支持：
 *  - cookie.removeCookie(url) - 移除指定 URL 的 Cookie
 *  - cookie.getCookie(url) - 获取指定 URL 的 Cookie
 *  - cookie.setCookie(url, cookie) - 设置指定 URL 的 Cookie
 */

class CookieManagerImpl {
  private cookies: Map<string, string> = new Map();

  removeCookie(url: string): void {
    const domain = this.extractDomain(url);
    this.cookies.delete(domain);
    console.info(`[CookieManager] Removed cookie for ${domain}`);
  }

  getCookie(url: string): string {
    const domain = this.extractDomain(url);
    return this.cookies.get(domain) || '';
  }

  setCookie(url: string, cookie: string): void {
    const domain = this.extractDomain(url);
    this.cookies.set(domain, cookie);
    console.info(`[CookieManager] Set cookie for ${domain}`);
  }

  private extractDomain(url: string): string {
    try {
      // 简化的域名提取（ArkTS 不支持 URL 类）
      const match = url.match(/^https?:\/\/([^\/]+)/);
      return match ? match[1] : url;
    } catch {
      return url;
    }
  }

  clear(): void {
    this.cookies.clear();
  }
}

let globalManager: CookieManagerImpl | null = null;

export function getCookieManager(): CookieManagerImpl {
  if (!globalManager) {
    globalManager = new CookieManagerImpl();
  }
  return globalManager;
}
