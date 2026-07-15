interface Envelope<T> {
  code: string;
  data: T;
  requestId: string;
  serverTime: number;
}

export class ApiError extends Error {
  constructor(public readonly code: string, public readonly status: number) {
    super(code);
  }
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    credentials: 'same-origin',
    ...init,
    headers: {
      Accept: 'application/json',
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
      ...init?.headers
    }
  });
  const payload = await response.json() as Envelope<T>;
  if (!response.ok || payload.code === 'INTERNAL_ERROR') throw new ApiError(payload.code || 'REQUEST_FAILED', response.status);
  return payload.data;
}

export function formatError(error: unknown): string {
  if (!(error instanceof ApiError)) return '请求失败，请稍后重试';
  const labels: Record<string, string> = {
    INVALID_ADMIN_PASSWORD: '密码不正确',
    ADMIN_AUTH_REQUIRED: '登录已过期',
    ONLY_AUDIO_SOURCE_ALLOWED: '文件中包含非音频书源',
    INVALID_SOURCE_IDENTITY: '书源缺少名称或地址',
    SOURCE_PRIVATE_NETWORK_DENIED: '书源包含不允许的内网地址',
    IMPORT_URL_REQUIRES_HTTPS: '远程书源地址必须使用 HTTPS',
    SOURCE_DELETE_DENIED: '系统来源不能删除',
    SOURCE_NOT_FOUND: '来源不存在'
  };
  return labels[error.code] ?? error.code;
}
