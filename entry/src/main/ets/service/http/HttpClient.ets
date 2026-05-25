/**
 * HttpClient - HTTP 请求封装（ArkTS 兼容）
 */

import http from '@ohos.net.http';

export interface HttpRequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | Object;
  timeout?: number;
}

export interface HttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

const POOL: http.HttpRequest[] = [];
const MAX_POOL_SIZE = 5;
const DEFAULT_TIMEOUT = 30000;

function getRequestMethod(method: string): http.RequestMethod {
  const m = method.toUpperCase();
  if (m === 'POST') return http.RequestMethod.POST;
  if (m === 'PUT') return http.RequestMethod.PUT;
  if (m === 'DELETE') return http.RequestMethod.DELETE;
  return http.RequestMethod.GET;
}

function getHttpRequest(): http.HttpRequest {
  const r = POOL.pop();
  if (r) return r;
  return http.createHttp();
}

function returnHttpRequest(request: http.HttpRequest): void {
  if (POOL.length < MAX_POOL_SIZE) {
    POOL.push(request);
  } else {
    request.destroy();
  }
}

export class HttpClient {
  static async request(url: string, options: HttpRequestOptions = {}): Promise<HttpResponse> {
    const httpRequest = getHttpRequest();

    try {
      const headers: Record<string, string> = options.headers || {};
      const requestOptions: http.HttpRequestOptions = {
        method: getRequestMethod(options.method || 'GET'),
        header: headers,
        readTimeout: options.timeout || DEFAULT_TIMEOUT,
        connectTimeout: options.timeout || DEFAULT_TIMEOUT,
      };

      if (options.body && options.method !== 'GET') {
        if (typeof options.body === 'string') {
          requestOptions.extraData = options.body;
        } else {
          requestOptions.extraData = JSON.stringify(options.body);
          headers['Content-Type'] = 'application/json';
        }
      }

      const response = await httpRequest.request(url, requestOptions);

      const result: HttpResponse = {
        statusCode: response.responseCode,
        headers: response.header as Record<string, string>,
        body: response.result as string,
      };
      return result;
    } finally {
      returnHttpRequest(httpRequest);
    }
  }

  static async get(url: string, headers?: Record<string, string>): Promise<string> {
    const response = await HttpClient.request(url, { method: 'GET', headers });
    return response.body;
  }

  static async post(url: string, body?: string | Object, headers?: Record<string, string>): Promise<string> {
    const response = await HttpClient.request(url, { method: 'POST', body, headers });
    return response.body;
  }

  static clearPool(): void {
    for (const r of POOL) {
      r.destroy();
    }
    POOL.length = 0;
  }
}
