import { z } from 'zod';
import { assertPublicImportUrl } from './utils.js';

const requestSchema = z.object({
  content: z.string().max(2_000_000).optional(),
  url: z.string().url().max(2000).optional(),
  enabled: z.boolean().default(false),
  testKeyword: z.string().trim().max(100).default('')
}).refine((value) => Boolean(value.content || value.url), '需要提供书源 JSON 或远程地址');

export type SourceImportRequest = z.infer<typeof requestSchema>;

export function collectSources(value: unknown, output: Record<string, unknown>[]): void {
  if (typeof value === 'string') {
    collectSources(JSON.parse(value) as unknown, output);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectSources(item, output);
    return;
  }
  if (!value || typeof value !== 'object') return;
  const object = value as Record<string, unknown>;
  if (object.bookSourceUrl || object.bookSourceName) {
    output.push(object);
    return;
  }
  for (const key of ['data', 'sources', 'bookSources', 'list']) {
    if (object[key] !== undefined) collectSources(object[key], output);
  }
}

export function validateAudioSource(source: Record<string, unknown>): Record<string, unknown> {
  if (Number(source.bookSourceType) !== 1) throw new Error('ONLY_AUDIO_SOURCE_ALLOWED');
  const name = String(source.bookSourceName ?? '').trim();
  const sourceUrl = String(source.bookSourceUrl ?? '').trim();
  if (!name || !sourceUrl) throw new Error('INVALID_SOURCE_IDENTITY');
  let parsed: URL;
  try { parsed = new URL(sourceUrl); } catch { throw new Error('INVALID_SOURCE_URL'); }
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('INVALID_SOURCE_PROTOCOL');
  const serialized = JSON.stringify(source).toLowerCase();
  const denied = ['127.0.0.1', 'localhost', '0.0.0.0', '169.254.169.254', 'file://', 'content://'];
  if (denied.some((token) => serialized.includes(token)) ||
    /https?:\/\/(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(serialized)) {
    throw new Error('SOURCE_PRIVATE_NETWORK_DENIED');
  }
  return { ...source, bookSourceName: name, bookSourceUrl: sourceUrl, bookSourceType: 1 };
}

async function downloadSource(urlValue: string): Promise<string> {
  const url = await assertPublicImportUrl(urlValue);
  const response = await fetch(url, {
    headers: { Accept: 'application/json,text/plain;q=0.9', 'User-Agent': 'JianHuanSourceAdmin/1.0' },
    signal: AbortSignal.timeout(10000),
    redirect: 'error'
  });
  if (!response.ok) throw new Error(`IMPORT_HTTP_${response.status}`);
  const declaredSize = Number(response.headers.get('content-length') ?? 0);
  if (declaredSize > 2_000_000) throw new Error('IMPORT_FILE_TOO_LARGE');
  const text = await response.text();
  if (text.length > 2_000_000) throw new Error('IMPORT_FILE_TOO_LARGE');
  return text;
}

export async function parseSourceImport(input: unknown): Promise<{ request: SourceImportRequest; sources: Record<string, unknown>[] }> {
  const request = requestSchema.parse(input);
  const content = request.content ?? await downloadSource(request.url!);
  const parsed = parseAudioSourceContent(content, 200);
  return { request, sources: parsed.sources };
}

export interface ParsedAudioSourceContent {
  sources: Record<string, unknown>[];
  total: number;
  rejected: number;
  rejectedCodes: string[];
}

/**
 * 解析大批量书源时采用“单条容错”：一个坏源不能阻断其它源同步。
 * 手动导入仍通过 maxSources=200 限制请求体规模，定时目录同步可使用更大上限。
 */
export function parseAudioSourceContent(content: string, maxSources = 200): ParsedAudioSourceContent {
  const output: Record<string, unknown>[] = [];
  collectSources(JSON.parse(content) as unknown, output);
  if (output.length === 0) throw new Error('NO_SOURCE_FOUND');
  if (output.length > maxSources) throw new Error('TOO_MANY_SOURCES');

  const valid: Record<string, unknown>[] = [];
  const seen = new Set<string>();
  const rejectedCodes: string[] = [];
  for (const item of output) {
    try {
      const source = validateAudioSource(item);
      const sourceUrl = String(source.bookSourceUrl);
      if (seen.has(sourceUrl)) continue;
      seen.add(sourceUrl);
      valid.push(source);
    } catch (error) {
      rejectedCodes.push(error instanceof Error ? error.message : 'INVALID_SOURCE');
    }
  }
  if (valid.length === 0 && rejectedCodes.length > 0) {
    throw new Error(rejectedCodes[0]);
  }
  return {
    sources: valid,
    total: output.length,
    rejected: output.length - valid.length,
    rejectedCodes
  };
}
