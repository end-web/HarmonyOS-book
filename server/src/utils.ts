import { createHash, randomUUID } from 'node:crypto';
import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';

export function stableId(prefix: string, ...parts: string[]): string {
  const digest = createHash('sha256').update(parts.join('\u001f')).digest('base64url').slice(0, 24);
  return `${prefix}_${digest}`;
}

export function requestId(): string {
  return `req_${randomUUID().replaceAll('-', '').slice(0, 20)}`;
}

export function cleanText(input: unknown, maxLength = 4000): string {
  const value = Array.isArray(input) ? input.join(', ') : String(input ?? '');
  return value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<br\s*\/?\s*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/\r/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
    .slice(0, maxLength);
}

export function firstString(value: unknown): string {
  if (Array.isArray(value)) return cleanText(value[0] ?? '');
  return cleanText(value);
}

export function audioFormat(url: string): string {
  const pathname = new URL(url).pathname.toLowerCase();
  if (pathname.endsWith('.m3u8')) return 'hls';
  const match = pathname.match(/\.([a-z0-9]{2,5})$/);
  return match?.[1] ?? 'audio';
}

export function assertAudioUrl(value: string): string {
  const url = new URL(value.trim());
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('UNSUPPORTED_AUDIO_PROTOCOL');
  }
  return url.toString();
}

export async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, code = 'SOURCE_TIMEOUT'): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(code)), timeoutMs);
      })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function isPrivateAddress(address: string): boolean {
  if (address === '::1' || address === '0.0.0.0' || address === '::') return true;
  if (address.startsWith('fc') || address.startsWith('fd') || address.startsWith('fe80:')) return true;
  if (isIP(address) !== 4) return false;
  const octets = address.split('.').map(Number);
  const [a = 0, b = 0] = octets;
  return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
    (a === 100 && b >= 64 && b <= 127);
}

export async function assertPublicImportUrl(input: string): Promise<URL> {
  const url = new URL(input);
  if (url.protocol !== 'https:') throw new Error('IMPORT_URL_REQUIRES_HTTPS');
  if (!url.hostname || url.username || url.password) throw new Error('INVALID_IMPORT_URL');
  const addresses = await lookup(url.hostname, { all: true });
  if (addresses.length === 0 || addresses.some((entry) => isPrivateAddress(entry.address))) {
    throw new Error('IMPORT_URL_NOT_PUBLIC');
  }
  return url;
}

export async function mapLimit<T, R>(items: T[], limit: number, task: (item: T) => Promise<R>): Promise<R[]> {
  const output = new Array<R>(items.length);
  let cursor = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      const item = items[index];
      if (item !== undefined) output[index] = await task(item);
    }
  });
  await Promise.all(workers);
  return output;
}

export function errorCode(error: unknown): string {
  if (!(error instanceof Error)) return 'SOURCE_ERROR';
  const message = error.message.toUpperCase();
  if (message.includes('TIMEOUT') || message.includes('ABORT')) return 'SOURCE_TIMEOUT';
  if (message.includes('HTTP_4')) return 'SOURCE_REJECTED';
  if (message.includes('HTTP_5')) return 'SOURCE_UPSTREAM_ERROR';
  if (message.includes('UNSUPPORTED')) return 'SOURCE_RULE_UNSUPPORTED';
  if (message.includes('EMPTY')) return 'SOURCE_EMPTY';
  return 'SOURCE_ERROR';
}
