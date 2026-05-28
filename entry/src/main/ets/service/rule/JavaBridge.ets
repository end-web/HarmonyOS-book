/**
 * JavaBridge - Legado Java 桥接（书源 JS 规则中的 java.xxx 方法）
 *
 * 支持：
 *  - java.get(key) / java.put(key, value) - 变量存取
 *  - java.connect(url) - HTTP GET 请求
 *  - java.ajax(url, options) - HTTP 请求（支持 POST）
 *  - java.getStrResponse() - 获取最后一次请求的响应
 *  - java.log(msg) - 日志输出
 */

import { HttpClient } from '../http/HttpClient';

interface AjaxOptions {
  method?: string;
  body?: string;
  headers?: Record<string, string>;
}

class JavaBridgeImpl {
  private variables: Record<string, string> = {};
  private lastResponse: string = '';

  get(key: string): string {
    return this.variables[key] || '';
  }

  put(key: string, value: string): void {
    this.variables[key] = value;
  }

  async connect(url: string): Promise<string> {
    try {
      const response = await HttpClient.get(url);
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] connect failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  async ajax(url: string, options?: AjaxOptions): Promise<string> {
    try {
      const method = options?.method?.toUpperCase() || 'GET';
      let response: string;
      if (method === 'POST') {
        const headers = options?.headers || { 'Content-Type': 'application/x-www-form-urlencoded' };
        response = await HttpClient.post(url, options?.body || '', headers);
      } else {
        response = await HttpClient.get(url);
      }
      this.lastResponse = response;
      return response;
    } catch (err) {
      console.error(`[JavaBridge] ajax failed: ${err}`);
      this.lastResponse = '';
      return '';
    }
  }

  getStrResponse(): string {
    return this.lastResponse;
  }

  log(message: string): void {
    console.info(`[JavaBridge] ${message}`);
  }

  /**
   * java.webView(html, url, js) - Legado: 通过 webview 渲染并执行 js
   * 当前实现：暂不渲染 webview，直接返回输入 html（书源依赖动态渲染时可能不工作）
   */
  async webView(html: string, _url?: string, _js?: string): Promise<string> {
    return html || '';
  }

  /**
   * java.timeFormat(timestamp) - 时间戳格式化（当前简单返回 ISO）
   */
  timeFormat(ts: number): string {
    try {
      return new Date(ts).toISOString();
    } catch {
      return String(ts);
    }
  }

  setVariables(vars: Record<string, string>): void {
    this.variables = vars;
  }

  getVariables(): Record<string, string> {
    return this.variables;
  }
}

let globalBridge: JavaBridgeImpl | null = null;

export function getJavaBridge(): JavaBridgeImpl {
  if (!globalBridge) {
    globalBridge = new JavaBridgeImpl();
  }
  return globalBridge;
}
