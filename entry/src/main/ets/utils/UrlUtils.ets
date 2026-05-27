/**
 * URL 工具函数
 */

export interface UrlConfig {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}

/**
 * 解析 URL 配置字符串
 * 格式：url,{method:POST,headers:{...},body:...}
 */
export function parseUrlConfig(urlWithConfig: string): UrlConfig {
  if (!urlWithConfig || !urlWithConfig.includes(',{')) {
    return { url: urlWithConfig };
  }

  const commaIndex = urlWithConfig.indexOf(',{');
  const url = urlWithConfig.substring(0, commaIndex);
  const configStr = urlWithConfig.substring(commaIndex + 1);

  try {
    const config = JSON.parse(configStr) as Record<string, Object>;
    return {
      url,
      method: config.method as string,
      headers: config.headers as Record<string, string>,
      body: config.body as string,
    };
  } catch {
    return { url: urlWithConfig };
  }
}

/**
 * 解析相对 URL
 */
export function resolveUrl(base: string, relative: string): string {
  if (!relative) return '';

  // 已经是完整 URL
  if (relative.startsWith('http://') || relative.startsWith('https://')) {
    return relative;
  }

  // 绝对路径
  if (relative.startsWith('/')) {
    const match = base.match(/^(https?:\/\/[^\/]+)/);
    return match ? match[1] + relative : relative;
  }

  // 相对路径
  const match = base.match(/^(https?:\/\/[^\/]+)(.*)/);
  if (!match) return relative;

  const host = match[1];
  const path = match[2];
  const basePath = path.endsWith('/') ? path : path.substring(0, path.lastIndexOf('/') + 1);

  return host + basePath + relative;
}
