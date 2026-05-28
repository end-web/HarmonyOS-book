/**
 * HttpResult - HTTP 响应包装（模拟 Legado 的 Response 对象）
 *
 * 用于 loginCheckJs 中的 result.body() 调用
 */

export class HttpResult {
  private responseBody: string;
  private statusCode: number;

  constructor(body: string, statusCode: number = 200) {
    this.responseBody = body;
    this.statusCode = statusCode;
  }

  body(): string {
    return this.responseBody;
  }

  code(): number {
    return this.statusCode;
  }

  isSuccessful(): boolean {
    return this.statusCode >= 200 && this.statusCode < 300;
  }

  toString(): string {
    return this.responseBody;
  }
}
