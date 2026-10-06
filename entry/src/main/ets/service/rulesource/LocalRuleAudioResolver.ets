import { buffer } from '@kit.ArkTS';
import { LocalRuleUrlAnalyzer } from './LocalRuleUrlAnalyzer';
import { LocalRuleRegexCompat } from './LocalRuleRegexCompat';
import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';

/** 只解释音频规则的返回值，不执行返回值中的脚本，也不扫描任意 JSON 字段。 */
export class LocalRuleAudioResolver {
  static isBaseUrlRule(rule: string): boolean {
    const code = rule.trim().replace(new RegExp('^<js>\\s*|\\s*</js>$', 'gi'), '')
      .replace(new RegExp('^@?js:\\s*', 'i'), '').replace(new RegExp(';\\s*$'), '').trim();
    return code === 'baseUrl' || code === 'String(baseUrl)';
  }

  static extract(value: string, baseUrl: string, depth: number = 0): string {
    const text = value.trim();
    if (!text || text.length > LocalRuleExecutionLimits.MAX_FIELD_CHARS || depth > 8) return '';
    if (new RegExp('^[\\[{"]').test(text)) {
      try {
        const parsed: Object = JSON.parse(text);
        if (typeof parsed === 'string') return LocalRuleAudioResolver.extract(parsed, baseUrl, depth + 1);
        if (Array.isArray(parsed)) {
          const items: Object[] = JSON.parse(text);
          for (const item of items.slice(0, 64)) {
            const candidate = LocalRuleAudioResolver.extract(JSON.stringify(item), baseUrl, depth + 1);
            if (candidate) return candidate;
          }
        } else if (parsed !== null && typeof parsed === 'object') {
          const fields: Record<string, Object> = JSON.parse(text);
          for (const key of ['audioUrl', 'audio_url', 'playUrl', 'play_url', 'playurl', 'listenUrl',
            'streamUrl', 'mediaUrl', 'main_url', 'mainUrl', 'src', 'file', 'path', 'url',
            'playInfo', 'decodedContent', 'content', 'data', 'result', 'payload', 'audio', 'media']) {
            const field = fields[key];
            if (field === undefined || field === null) continue;
            const candidate = LocalRuleAudioResolver.extract(JSON.stringify(field), baseUrl, depth + 1);
            if (candidate) return candidate;
          }
        }
        return '';
      } catch (_error) { /* 非 JSON 的规则结果继续按地址处理。 */ }
    }
    for (const line of text.split(new RegExp('\\r?\\n')).slice(0, 64)) {
      const candidate = LocalRuleAudioResolver.candidate(line, baseUrl);
      if (candidate) return candidate;
    }
    // HTML/脚本包装仅识别媒体属性及已知音频扩展名，避免把登录链接当音频。
    const decoded = LocalRuleAudioResolver.decode(text);
    const attribute = decoded.match(new RegExp('(?:src|audio_url|audioUrl|play_url|playUrl)\\s*[:=]\\s*["\x27]([^"\x27]+)["\x27]', 'i'));
    if (attribute !== null) {
      const candidate = LocalRuleAudioResolver.candidate(attribute[1], baseUrl);
      if (candidate) return candidate;
    }
    const media = decoded.match(new RegExp('(?:https?:)?//[^\\s"\x27<>\\\\]+?\\.(?:mp3|m4a|aac|ogg|opus|wav|flac|m3u8|mp4)(?:[?][^\\s"\x27<>\\\\]*)?', 'i'));
    return media === null ? '' : LocalRuleAudioResolver.candidate(media[0], baseUrl);
  }

  static candidate(value: string, baseUrl: string): string {
    let clean = LocalRuleAudioResolver.decode(value).trim()
      .replace(new RegExp('^url\\(\\s*|\\s*\\)$', 'gi'), '')
      .replace(new RegExp('^["\x27]|["\x27]$', 'g'), '').trim();
    if (!clean || clean.length > LocalRuleExecutionLimits.MAX_FIELD_CHARS) return '';
    if (new RegExp('^[A-Za-z0-9+/]{24,}={0,2}$').test(clean)) {
      const decoded = buffer.from(clean, 'base64').toString('utf-8');
      if (new RegExp('^https?://', 'i').test(decoded)) clean = decoded;
    }
    // URL 后的请求选项留给现有分析器，保留显式 headers 和签名参数。
    const address = clean.split(new RegExp(',\\s*\\{'))[0];
    if (new RegExp('[\\s<>"\x27{}]').test(address) ||
      new RegExp('^(?:javascript:|data:|file:|about:|blob:|#)', 'i').test(address)) return '';
    if (!new RegExp('^(?:https?://|//|/|\\./|\\.\\./|\\?)', 'i').test(address) &&
      !new RegExp('^[A-Za-z0-9._~-]+(?:/|\\?)[^\\s<>]+$').test(address) &&
      !new RegExp('^[^\\s<>]+\\.(?:mp3|m4a|aac|ogg|opus|wav|flac|m3u8|mp4|ape|wma)(?:[?#]|$)', 'i').test(address)) return '';
    const resolved = LocalRuleUrlAnalyzer.resolveUrl(baseUrl, clean);
    return new RegExp('^https?://', 'i').test(resolved) ? resolved : '';
  }

  static match(value: string, pattern: string): boolean {
    if (!new RegExp('^https?://', 'i').test(value)) return false;
    if (!pattern.trim()) return new RegExp('\\.(?:mp3|m4a|aac|ogg|opus|wav|flac|m3u8|mp4|ape|wma)(?:[?#]|$)', 'i').test(value);
    return LocalRuleAudioResolver.regex(pattern).test(value);
  }

  static fromBody(body: string, pattern: string, baseUrl: string): string {
    if (!pattern.trim()) return '';
    const match = LocalRuleAudioResolver.regex(pattern).exec(body);
    if (match === null) return '';
    // 捕获组可能只是扩展名，先尝试组，再尝试完整匹配。
    for (let index = 1; index < match.length; index++) {
      const candidate = LocalRuleAudioResolver.candidate(match[index] || '', baseUrl);
      if (candidate) return candidate;
    }
    return LocalRuleAudioResolver.candidate(match[0], baseUrl);
  }

  private static regex(pattern: string): RegExp {
    const literal = pattern.trim().match(new RegExp('^/([\\s\\S]+)/([gimsuy]*)$'));
    return literal === null ? LocalRuleRegexCompat.compile(pattern, 'i') :
      LocalRuleRegexCompat.compile(literal[1], literal[2].replace('g', '').replace('y', ''));
  }

  private static decode(value: string): string {
    return value.replace(new RegExp('&amp;', 'gi'), '&').replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'")
      .replace(new RegExp('\\\\u002f|\\\\x2f', 'gi'), '/').replace(new RegExp('\\\\u003a|\\\\x3a', 'gi'), ':')
      .replace(new RegExp('\\\\u0026|\\\\x26', 'gi'), '&').replace(new RegExp('\\\\u003d|\\\\x3d', 'gi'), '=')
      .replace(new RegExp('\\\\/', 'g'), '/');
  }
}
