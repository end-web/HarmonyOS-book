import { LocalRuleSource } from '../../model/LocalRuleSource';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { LocalRuleExecutionLimits, LocalRuleRequestPlan } from './LocalRuleRuntimeTypes';

class LocalRuleUrlParts {
  address: string = '';
  options: Record<string, Object> = {};
}

/** 只分析声明式 URL，不执行脚本、Cookie 表达式或 WebView 请求。 */
export class LocalRuleUrlAnalyzer {
  static analyze(source: LocalRuleSource, rawAddress: string,
    variables: Record<string, string> = {}, keyword: string = '', page: number = 1): LocalRuleRequestPlan {
    const expanded = LocalRuleUrlAnalyzer.expandTemplate(rawAddress.trim(), source, variables, keyword, page);
    const parts = LocalRuleUrlAnalyzer.splitOptions(expanded);
    const plan = new LocalRuleRequestPlan();
    let address = parts.address.trim();
    const inlineHeaders: Record<string, string> = {};

    const headerStart = address.indexOf('@Header:');
    if (headerStart >= 0) {
      const headerEnd = address.indexOf('@End', headerStart + 8);
      if (headerEnd > headerStart) {
        const parsedHeaders = LocalRuleUrlAnalyzer.parseHeaders(
          address.substring(headerStart + 8, headerEnd));
        const headerNames = Object.keys(parsedHeaders);
        for (const name of headerNames) inlineHeaders[name] = parsedHeaders[name] ?? '';
        address = address.substring(0, headerStart) + address.substring(headerEnd + 4);
      }
    }

    if (address.startsWith('@')) {
      address = address.substring(1);
      const bodyIndex = address.indexOf('?');
      if (bodyIndex >= 0) {
        plan.body = address.substring(bodyIndex + 1);
        address = address.substring(0, bodyIndex);
      }
      plan.method = 'POST';
    }

    plan.url = LocalRuleUrlAnalyzer.resolveUrl(source.bookSourceUrl, address);
    LocalRuleUrlAnalyzer.assertHttpUrl(plan.url);
    plan.headers = LocalRuleUrlAnalyzer.parseHeaders(source.header);
    plan.timeoutMs = LocalRuleUrlAnalyzer.clamp(source.respondTime,
      LocalRuleExecutionLimits.MIN_TIMEOUT_MS, LocalRuleExecutionLimits.MAX_TIMEOUT_MS);
    LocalRuleUrlAnalyzer.applyOptions(plan, parts.options, source, variables, keyword, page);
    const inlineNames = Object.keys(inlineHeaders);
    for (const name of inlineNames) plan.headers[name] = inlineHeaders[name] ?? '';
    plan.url = LocalRuleUrlAnalyzer.encodeUrlCharacters(plan.url, plan.charset, false);
    if (typeof plan.body === 'string' && !plan.rawBody &&
      !LocalRuleUrlAnalyzer.looksLikeStructuredBody(plan.body)) {
      plan.body = LocalRuleUrlAnalyzer.encodeUrlCharacters(plan.body, plan.charset, true);
    }
    return plan;
  }

  static resolveUrl(baseUrl: string, value: string): string {
    const raw = LocalRuleUrlAnalyzer.decodeHtmlEntities(value.trim());
    if (!raw || raw.startsWith('#')) return '';
    const lower = raw.toLowerCase();
    if (lower.startsWith('javascript:') || lower.startsWith('file:') || lower.startsWith('data:') ||
      lower.startsWith('content:') || lower.startsWith('ftp:')) return '';
    if (lower.startsWith('http://') || lower.startsWith('https://')) return raw;

    const cleanBase = baseUrl.trim();
    const baseLower = cleanBase.toLowerCase();
    if (!baseLower.startsWith('http://') && !baseLower.startsWith('https://')) return '';
    if (raw.startsWith('//')) {
      return `${baseLower.startsWith('https://') ? 'https' : 'http'}:${raw}`;
    }

    if (raw.startsWith('?')) {
      return LocalRuleUrlAnalyzer.stripUrlSuffix(cleanBase) + raw;
    }
    const baseOrigin = LocalRuleUrlAnalyzer.origin(cleanBase);
    if (!baseOrigin) return '';
    if (raw.startsWith('/')) {
      return LocalRuleUrlAnalyzer.normalizePath(baseOrigin + raw);
    }

    const basePath = LocalRuleUrlAnalyzer.stripUrlSuffix(cleanBase);
    const lastSlash = basePath.lastIndexOf('/');
    const directory = lastSlash >= baseOrigin.length ? basePath.substring(0, lastSlash + 1) : `${baseOrigin}/`;
    return LocalRuleUrlAnalyzer.normalizePath(directory + raw);
  }

  static parseHeaders(headerText: string): Record<string, string> {
    const headers: Record<string, string> = {};
    const text = headerText.trim();
    if (!text) return headers;
    try {
      const value = JSON.parse(text) as Object;
      if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
        const record = value as Record<string, Object>;
        const keys = Object.keys(record);
        for (const key of keys) {
          const item = record[key];
          if (item !== undefined && item !== null && typeof item !== 'object') {
            headers[key] = String(item);
          }
        }
        return headers;
      }
    } catch (_error) {
      // 继续兼容逐行 Header 格式。
    }

    const lines = text.split(new RegExp('\r?\n', 'g'));
    for (const line of lines) {
      const separator = line.indexOf(':');
      if (separator <= 0) continue;
      const name = line.substring(0, separator).trim();
      const value = line.substring(separator + 1).trim();
      if (name && value) headers[name] = value;
    }
    return headers;
  }

  static expandTemplate(template: string, source: LocalRuleSource,
    variables: Record<string, string>, keyword: string, page: number): string {
    let output = template;
    const encodedKeyword = encodeURIComponent(keyword);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{key}}', encodedKeyword);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{searchKey}}', encodedKeyword);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{keyword}}', encodedKeyword);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{searchKeyRaw}}', keyword);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{page}}', String(Math.max(1, page)));
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{pageIndex}}', String(Math.max(1, page)));
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{source.bookSourceUrl}}', source.bookSourceUrl);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{source.bookSourceName}}', source.bookSourceName);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{source.bookSourceGroup}}', source.bookSourceGroup);
    output = LocalRuleUrlAnalyzer.replaceAll(output, '{{source.bookSourceComment}}', source.bookSourceComment);

    const keys = Object.keys(variables);
    for (const key of keys) {
      const value = variables[key] ?? '';
      output = LocalRuleUrlAnalyzer.replaceAll(output, `{{${key}}}`, value);
    }
    return output;
  }

  static safeLogUrl(value: string): string {
    const queryIndex = value.indexOf('?');
    const clean = queryIndex >= 0 ? value.substring(0, queryIndex) : value;
    return clean.length > 160 ? clean.substring(0, 160) : clean;
  }

  private static applyOptions(plan: LocalRuleRequestPlan, options: Record<string, Object>,
    source: LocalRuleSource, variables: Record<string, string>, keyword: string, page: number): void {
    const methodValue = options['method'];
    if (methodValue !== undefined && methodValue !== null) {
      plan.method = String(methodValue).trim().toUpperCase();
    }
    if (plan.method !== 'GET' && plan.method !== 'POST') {
      throw new Error(`不支持的请求方法：${plan.method}`);
    }

    const charsetValue = options['charset'];
    if (charsetValue !== undefined && charsetValue !== null) {
      plan.charset = String(charsetValue).trim().toLowerCase() || 'utf-8';
    }
    const retryValue = options['retry'];
    if (retryValue !== undefined && retryValue !== null) {
      const retry = Number(retryValue);
      if (Number.isFinite(retry)) {
        plan.retry = LocalRuleUrlAnalyzer.clamp(Math.trunc(retry), 0, LocalRuleExecutionLimits.MAX_RETRY);
      }
    }
    const headersValue = options['headers'];
    if (headersValue !== undefined && headersValue !== null) {
      if (typeof headersValue === 'string') {
        const optionHeaders = LocalRuleUrlAnalyzer.parseHeaders(headersValue);
        const keys = Object.keys(optionHeaders);
        for (const key of keys) plan.headers[key] = optionHeaders[key] ?? '';
      } else if (typeof headersValue === 'object' && !Array.isArray(headersValue)) {
        const optionHeaders = headersValue as Record<string, Object>;
        const keys = Object.keys(optionHeaders);
        for (const key of keys) {
          const item = optionHeaders[key];
          if (item !== undefined && item !== null && typeof item !== 'object') {
            plan.headers[key] = String(item);
          }
        }
      }
    }

    const rawBodyValue = options['rawBody'];
    if (rawBodyValue !== undefined && rawBodyValue !== null) {
      plan.rawBody = String(rawBodyValue).trim().toLowerCase() !== 'false';
    }

    const bodyValue = options['body'];
    if (bodyValue !== undefined && bodyValue !== null) {
      if (typeof bodyValue === 'object') {
        const bodyJson = JSON.stringify(bodyValue);
        const expandedJson = LocalRuleUrlAnalyzer.expandTemplate(bodyJson, source, variables, keyword, page);
        plan.body = JSON.parse(expandedJson) as Object;
      } else {
        plan.body = LocalRuleUrlAnalyzer.expandTemplate(String(bodyValue), source, variables, keyword, page);
      }
    }
    if (plan.method === 'GET') plan.body = undefined;
  }

  private static splitOptions(value: string): LocalRuleUrlParts {
    const parts = new LocalRuleUrlParts();
    parts.address = value;
    const end = value.length - 1;
    if (end < 1 || value.charAt(end) !== '}') return parts;

    let depth = 0;
    let quote = '';
    let escaped = false;
    let objectStart = -1;
    for (let i = end; i >= 0; i--) {
      const character = value.charAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '}') depth++;
      if (character === '{') {
        depth--;
        if (depth === 0) {
          objectStart = i;
          break;
        }
      }
    }
    if (objectStart <= 0) return parts;
    let commaIndex = objectStart - 1;
    while (commaIndex >= 0 && new RegExp('\\s').test(value.charAt(commaIndex))) commaIndex--;
    if (commaIndex < 0 || value.charAt(commaIndex) !== ',') return parts;
    try {
      const parsed = LocalRuleUrlAnalyzer.parseLooseObject(value.substring(objectStart));
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return parts;
      parts.address = value.substring(0, commaIndex).trim();
      parts.options = parsed as Record<string, Object>;
    } catch (_error) {
      // P0 只接受标准 JSON 选项，解析失败时保留原 URL，随后协议校验会给出明确错误。
    }
    return parts;
  }

  private static assertHttpUrl(url: string): void {
    const lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw new Error('规则源请求仅允许 HTTP 或 HTTPS');
    }
    if (url.length > LocalRuleExecutionLimits.MAX_URL_CHARS) {
      throw new Error(`请求地址超过 ${LocalRuleExecutionLimits.MAX_URL_CHARS} 字符`);
    }
    const authorityStart = url.indexOf('://') + 3;
    const authorityEndCandidate = url.indexOf('/', authorityStart);
    const authorityEnd = authorityEndCandidate >= 0 ? authorityEndCandidate : url.length;
    const authority = url.substring(authorityStart, authorityEnd);
    if (!authority || authority.includes('@')) throw new Error('请求地址主机无效或包含凭据');
  }

  private static origin(value: string): string {
    const schemeEnd = value.indexOf('://');
    if (schemeEnd <= 0) return '';
    const authorityStart = schemeEnd + 3;
    const slash = value.indexOf('/', authorityStart);
    return slash >= 0 ? value.substring(0, slash) : value;
  }

  private static stripUrlSuffix(value: string): string {
    const queryIndex = value.indexOf('?');
    const hashIndex = value.indexOf('#');
    let index = -1;
    if (queryIndex >= 0 && hashIndex >= 0) index = Math.min(queryIndex, hashIndex);
    else index = Math.max(queryIndex, hashIndex);
    return index >= 0 ? value.substring(0, index) : value;
  }

  private static normalizePath(value: string): string {
    const suffixIndex = LocalRuleUrlAnalyzer.firstSuffixIndex(value);
    const pathPart = suffixIndex >= 0 ? value.substring(0, suffixIndex) : value;
    const suffix = suffixIndex >= 0 ? value.substring(suffixIndex) : '';
    const origin = LocalRuleUrlAnalyzer.origin(pathPart);
    if (!origin) return '';
    const path = pathPart.substring(origin.length);
    const segments = path.split('/');
    const normalized: string[] = [];
    for (const segment of segments) {
      if (!segment || segment === '.') continue;
      if (segment === '..') {
        if (normalized.length > 0) normalized.pop();
      } else {
        normalized.push(segment);
      }
    }
    return `${origin}/${normalized.join('/')}${suffix}`;
  }

  private static firstSuffixIndex(value: string): number {
    const query = value.indexOf('?');
    const hash = value.indexOf('#');
    if (query < 0) return hash;
    if (hash < 0) return query;
    return Math.min(query, hash);
  }

  private static replaceAll(value: string, marker: string, replacement: string): string {
    return value.split(marker).join(replacement);
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    if (!Number.isFinite(value)) return minimum;
    return Math.min(maximum, Math.max(minimum, value));
  }

  private static decodeHtmlEntities(value: string): string {
    return value.replace(new RegExp('&amp;', 'gi'), '&')
      .replace(new RegExp('&#38;', 'g'), '&')
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'");
  }

  private static parseLooseObject(value: string): Object {
    try {
      return JSON.parse(value) as Object;
    } catch (_strictError) {
      let normalized = value.trim();
      normalized = normalized.replace(
        new RegExp('([,{]\\s*)([A-Za-z_$][A-Za-z0-9_$-]*)(\\s*:)', 'g'), '$1"$2"$3');
      normalized = normalized.replace(new RegExp("'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'", 'g'),
        (_match: string, body: string): string => `"${body.replace(new RegExp('"', 'g'), '\\"')}"`);
      normalized = normalized.replace(new RegExp(',\\s*([}\\]])', 'g'), '$1');
      return JSON.parse(normalized) as Object;
    }
  }

  private static encodeUrlCharacters(value: string, charset: string, form: boolean): string {
    let output = '';
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      const code = value.charCodeAt(index);
      if (character === '%' && index + 2 < value.length &&
        new RegExp('^[0-9A-Fa-f]{2}$').test(value.substring(index + 1, index + 3))) {
        output += value.substring(index, index + 3);
        index += 3;
        continue;
      }
      if (code < 128) {
        if (character === ' ') output += form ? '+' : '%20';
        else output += character;
      } else {
        output += CharsetCodec.encodeUriForCharset(character, charset);
      }
      index++;
    }
    return output;
  }

  private static looksLikeStructuredBody(value: string): boolean {
    const clean = value.trim();
    return (clean.startsWith('{') && clean.endsWith('}')) ||
      (clean.startsWith('[') && clean.endsWith(']'));
  }
}
