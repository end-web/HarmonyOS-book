/**
 * JSExecutor - JavaScript 执行器
 *
 * 通过 HTTP 调用 Node.js 代理服务执行 JavaScript 代码
 * 代理服务地址：http://localhost:3737
 */

import { HttpClient } from '../http/HttpClient';

export interface JSExecutorConfig {
  host?: string;
  port?: number;
  timeout?: number;
}

export interface JSEvalRequest {
  code: string;
  context?: Record<string, Object>;
  timeout?: number;
}

export interface JSEvalResponse {
  success: boolean;
  result?: Object;
  error?: string;
}

export class JSExecutor {
  private baseUrl: string;
  private timeout: number;

  constructor(config: JSExecutorConfig = {}) {
    const host = config.host || 'localhost';
    const port = config.port || 3737;
    this.baseUrl = `http://${host}:${port}`;
    this.timeout = config.timeout || 5000;
  }

  /**
   * 执行 JavaScript 代码
   */
  async eval(code: string, context: Record<string, Object> = {}): Promise<Object | null> {
    const request: JSEvalRequest = {
      code,
      context,
      timeout: this.timeout,
    };

    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      const responseBody = await HttpClient.post(
        `${this.baseUrl}/eval`,
        request,
        headers,
      );

      const response: JSEvalResponse = JSON.parse(responseBody) as JSEvalResponse;

      if (!response.success) {
        throw new Error(response.error || 'JS 执行失败');
      }

      return response.result !== undefined ? response.result : null;
    } catch (error) {
      console.error('[JSExecutor] 执行失败:', error);
      const e = error as Error;
      throw new Error(e.message || 'JS 执行失败');
    }
  }

  /**
   * 健康检查
   */
  async health(): Promise<boolean> {
    try {
      await HttpClient.get(`${this.baseUrl}/health`);
      return true;
    } catch {
      return false;
    }
  }
}

/**
 * 全局单例
 */
let globalExecutor: JSExecutor | null = null;

export function getJSExecutor(config?: JSExecutorConfig): JSExecutor {
  if (!globalExecutor) {
    globalExecutor = new JSExecutor(config);
  }
  return globalExecutor;
}
