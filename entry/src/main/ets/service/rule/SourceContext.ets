/**
 * SourceContext - 书源上下文（书源 JS 规则中的 source.xxx 访问）
 *
 * 支持：
 *  - source.key - 书源 URL（bookSourceUrl）
 *  - source.name - 书源名称
 *  - source.type - 书源类型（0=文本，1=音频）
 *  - source.getVariable() - 获取源变量（JSON 字符串）
 *  - source.setVariable(v) - 设置源变量
 *  - source.login() - 执行登录 JS
 *  - source.getLoginHeader() / source.putLoginHeader(h) - 登录头存取
 *  - source.getLoginInfo() / source.putLoginInfo(info) - 登录信息存取（AES 加密）
 *  - source.removeLoginHeader() / source.removeLoginInfo() - 清除登录数据
 *  - source.evalJS(js) - 在源上下文中执行 JS
 *  - source.put(k, v) / source.get(k) - 通用键值存储
 */

import { SourceVariableStore } from '../SourceVariableStore';
import { getCookieManager } from './CookieManager';
import { getJSExecutor } from '../js/JSExecutor';

export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType?: number;
  bookSourceComment?: string;
  loginUrl?: string;
  loginCheckJs?: string;
  header?: string;
  jsLib?: string;
}

// 登录回调（由 UI 层注册，用于触发登录 UI）
type LoginCallback = (source: BookSource) => Promise<boolean>;

class SourceContextImpl {
  private currentSource: BookSource | null = null;
  private static loginCallback: LoginCallback | null = null;

  static setLoginCallback(cb: LoginCallback | null): void {
    SourceContextImpl.loginCallback = cb;
  }

  setSource(source: BookSource): void {
    this.currentSource = source;
  }

  get key(): string {
    return this.currentSource?.bookSourceUrl || '';
  }

  get name(): string {
    return this.currentSource?.bookSourceName || '';
  }

  get type(): number {
    return this.currentSource?.bookSourceType || 0;
  }

  getSource(): BookSource | null {
    return this.currentSource;
  }

  /**
   * source.getVariable() - 获取源变量
   * 返回存储的 JSON 字符串（Legado 约定）
   */
  getVariable(): string {
    if (!this.currentSource) return '';
    try {
      const vars = SourceVariableStore.getSourceVariables(this.currentSource.bookSourceUrl);
      return JSON.stringify(vars);
    } catch {
      return '';
    }
  }

  /**
   * source.setVariable(v) - 设置源变量
   * v 是 JSON 字符串（Legado 约定）
   */
  setVariable(v: string): void {
    if (!this.currentSource) return;
    try {
      const parsed = JSON.parse(v) as Record<string, Object>;
      const keys = Object.keys(parsed);
      for (const k of keys) {
        SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, k, parsed[k]);
      }
    } catch {
      // 如果不是 JSON，按单值存储
      SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, '_value', v);
    }
  }

  // ──────────── 登录相关 ────────────

  /**
   * source.login() - 触发登录流程
   * 调用 UI 层注册的登录回调
   */
  async login(): Promise<boolean> {
    if (!this.currentSource) return false;
    if (!SourceContextImpl.loginCallback) {
      console.warn('[SourceContext] login: no login callback registered');
      return false;
    }
    try {
      return await SourceContextImpl.loginCallback(this.currentSource);
    } catch (e) {
      console.error(`[SourceContext] login error: ${e}`);
      return false;
    }
  }

  /**
   * source.getLoginHeader() - 获取已保存的登录头（JSON 字符串）
   */
  getLoginHeader(): string {
    if (!this.currentSource) return '';
    try {
      const vars = SourceVariableStore.getSourceVariables(this.currentSource.bookSourceUrl);
      const header = vars['_loginHeader'];
      return typeof header === 'string' ? header : JSON.stringify(header || {});
    } catch {
      return '{}';
    }
  }

  /**
   * source.getLoginHeaderMap() - 获取已保存的登录头（对象）
   */
  getLoginHeaderMap(): Record<string, string> {
    try {
      return JSON.parse(this.getLoginHeader()) as Record<string, string>;
    } catch {
      return {};
    }
  }

  /**
   * source.putLoginHeader(header) - 保存登录头
   * 同时提取 Cookie 存入 CookieManager
   */
  putLoginHeader(header: string): void {
    if (!this.currentSource) return;
    try {
      SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, '_loginHeader', header);
      // 提取 Cookie 并存入 CookieManager
      try {
        const headerObj = JSON.parse(header) as Record<string, string>;
        const cookie = headerObj['Cookie'] || headerObj['cookie'];
        if (cookie) {
          const cm = getCookieManager();
          cm.setCookie(this.currentSource.bookSourceUrl, cookie);
        }
      } catch { /* header 可能不是 JSON */ }
    } catch (e) {
      console.error(`[SourceContext] putLoginHeader error: ${e}`);
    }
  }

  /**
   * source.removeLoginHeader() - 清除登录头
   */
  removeLoginHeader(): void {
    if (!this.currentSource) return;
    try {
      SourceVariableStore.removeSourceVariable(this.currentSource.bookSourceUrl, '_loginHeader');
    } catch { /* ignore */ }
  }

  /**
   * source.getLoginInfo() - 获取登录信息（AES 加密后的 JSON 字符串）
   */
  getLoginInfo(): string {
    if (!this.currentSource) return '';
    try {
      const vars = SourceVariableStore.getSourceVariables(this.currentSource.bookSourceUrl);
      const info = vars['_loginInfo'];
      return typeof info === 'string' ? info : JSON.stringify(info || {});
    } catch {
      return '{}';
    }
  }

  /**
   * source.getLoginInfoMap() - 获取登录信息（对象）
   */
  getLoginInfoMap(): Record<string, string> {
    try {
      return JSON.parse(this.getLoginInfo()) as Record<string, string>;
    } catch {
      return {};
    }
  }

  /**
   * source.putLoginInfo(info) - 保存登录信息
   */
  putLoginInfo(info: string): void {
    if (!this.currentSource) return;
    try {
      SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, '_loginInfo', info);
    } catch (e) {
      console.error(`[SourceContext] putLoginInfo error: ${e}`);
    }
  }

  /**
   * source.removeLoginInfo() - 清除登录信息
   */
  removeLoginInfo(): void {
    if (!this.currentSource) return;
    try {
      SourceVariableStore.removeSourceVariable(this.currentSource.bookSourceUrl, '_loginInfo');
    } catch { /* ignore */ }
  }

  // ──────────── 通用键值存储 ────────────

  /**
   * source.put(key, value) - 存储键值对
   */
  put(key: string, value: Object): void {
    if (!this.currentSource) return;
    try {
      SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, key, value);
    } catch { /* ignore */ }
  }

  /**
   * source.get(key) - 获取键值
   */
  get(key: string): string {
    if (!this.currentSource) return '';
    try {
      const vars = SourceVariableStore.getSourceVariables(this.currentSource.bookSourceUrl);
      const v = vars[key];
      if (v === undefined || v === null) return '';
      return typeof v === 'string' ? v : JSON.stringify(v);
    } catch {
      return '';
    }
  }

  /**
   * source.evalJS(js) - 在源上下文中执行 JS
   * 注意：这里只做简单委托，实际执行需要 JSExecutor
   */
  async evalJS(js: string): Promise<Object> {
    try {
      const executor = getJSExecutor();
      const ctx: Record<string, Object> = {};
      ctx['source'] = this as Object;
      ctx['baseUrl'] = this.currentSource?.bookSourceUrl || '' as Object;
      const result = await executor.eval(js, ctx);
      return result as Object;
    } catch (e) {
      console.error(`[SourceContext] evalJS error: ${e}`);
      return '' as Object;
    }
  }

  /**
   * source.getHeaderMap(hasLoginHeader) - 获取请求头（含可选登录头）
   */
  getHeaderMap(hasLoginHeader?: boolean): Record<string, string> {
    const headers: Record<string, string> = {};
    if (!this.currentSource) return headers;

    // 解析基础 header
    if (this.currentSource.header) {
      try {
        const h = JSON.parse(this.currentSource.header) as Record<string, string>;
        for (const k of Object.keys(h)) headers[k] = h[k];
      } catch { /* ignore */ }
    }

    // 合并登录头
    if (hasLoginHeader) {
      try {
        const loginHeader = this.getLoginHeaderMap();
        for (const k of Object.keys(loginHeader)) {
          if (!headers[k]) headers[k] = loginHeader[k];
        }
      } catch { /* ignore */ }
    }

    return headers;
  }
}

let globalContext: SourceContextImpl | null = null;

export function getSourceContext(): SourceContextImpl {
  if (!globalContext) {
    globalContext = new SourceContextImpl();
  }
  return globalContext;
}
