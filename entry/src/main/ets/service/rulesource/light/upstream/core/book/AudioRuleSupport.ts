import { JavaRegexCompat } from '../rule/JavaRegexCompat';

/** The address part and the explicit request headers of a `url,{"headers":{...}}` rule value. */
export class AudioRequestOptions {
  url: string = '';
  headers: Record<string, string> = {};
}

/**
 * Pure helpers shared by the audio content chain, the WebView media sniffer and the player.
 * Nothing here is site specific: every value comes from the book source's own rules.
 */
export class AudioRuleSupport {
  private static readonly MEDIA_EXTENSIONS: string = 'aac|ape|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav|wma';
  /** Headers that authenticate against one site and must not follow the stream to another. */
  private static readonly SITE_BOUND_HEADERS: string[] = [
    'cookie', 'authorization', 'proxy-authorization', 'host', 'origin'
  ];
  private static readonly MAX_BODY_CANDIDATES: number = 8;

  static looksLikeMediaUrl(url: string): boolean {
    return new RegExp(`\\.(?:${this.MEDIA_EXTENSIONS})(?:[?#]|$)`, 'i').test(String(url || ''));
  }

  /**
   * `sourceRegex` is written for Android Legado, so it is a Java pattern unless it uses the
   * `/pattern/flags` literal form. Returns null when the pattern cannot be compiled.
   */
  static compileSourceRegex(rawPattern: string): RegExp | null {
    const pattern = String(rawPattern || '').trim();
    if (!pattern) return null;
    const literal = pattern.match(/^\/([\s\S]+)\/([dgimsuvy]*)$/);
    try {
      // A stateful (g/y) matcher would remember lastIndex between unrelated candidates.
      return literal ? JavaRegexCompat.compile(literal[1], literal[2].replace(/[gy]/g, '')) :
        JavaRegexCompat.compile(pattern, 'i');
    } catch (_) {
      return null;
    }
  }

  /** An empty or unusable pattern falls back to the known media file extensions. */
  static matchesSourceRegex(url: string, rawPattern: string): boolean {
    const value = String(url || '').trim();
    if (!/^https?:\/\//i.test(value)) return false;
    const regex = this.compileSourceRegex(rawPattern);
    return regex ? regex.test(value) : this.looksLikeMediaUrl(value);
  }

  /**
   * Applies `sourceRegex` to a response body. Capture groups come first because a pattern such as
   * `"play":"(.*?)"` selects the address with its group; the complete match is the last candidate.
   */
  static captureFromBody(body: string, rawPattern: string): string[] {
    const regex = this.compileSourceRegex(rawPattern);
    if (!regex || !body) return [];
    const match = regex.exec(body);
    if (!match) return [];
    const candidates: string[] = [];
    for (let index = 1; index < match.length && candidates.length < this.MAX_BODY_CANDIDATES; index++) {
      const group = String(match[index] || '').trim();
      if (group && !candidates.includes(group)) candidates.push(group);
    }
    const whole = String(match[0] || '').trim();
    if (whole && !candidates.includes(whole)) candidates.push(whole);
    return candidates;
  }

  /** Script of an `@webjs:` rule, which runs inside the rendered chapter page; '' for other rules. */
  static webJsCode(rawRule: string): string {
    const match = String(rawRule || '').trim().match(/^@webjs:([\s\S]*)$/i);
    return match ? match[1].trim() : '';
  }

  /**
   * Splits a rule value of the form `https://cdn/a.mp3,{"headers":{"Referer":"..."}}`.
   * Only explicit headers are read; any other option keeps its meaning for the request layer.
   */
  static splitRequestOptions(raw: string): AudioRequestOptions {
    const result = new AudioRequestOptions();
    let value = String(raw || '').trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      try { value = String(JSON.parse(value)).trim(); } catch (_) {}
    }
    result.url = value;
    const match = value.match(/^(\S+?)\s*,\s*(\{[\s\S]*\})$/);
    if (!match) return result;
    const options = this.parseOptionObject(match[2]);
    if (!options) return result;
    result.url = match[1];
    result.headers = this.headerRecord(options['headers'] ?? options['header']);
    return result;
  }

  /** Re-attaches explicit headers to an address so they survive as part of the rule value. */
  static joinRequestOptions(url: string, headers: Record<string, string>): string {
    return Object.keys(headers).length === 0 ? url : `${url},${JSON.stringify({ headers: headers })}`;
  }

  /**
   * A stream is frequently served by another site than the one the source logs in to. Source-level
   * credentials stay with the source's own site; Referer and User-Agent are kept because media
   * hosts commonly validate them.
   */
  static scopeHeadersToMediaHost(headers: Record<string, string>, sourceUrl: string,
    mediaUrl: string): Record<string, string> {
    const sourceSite = this.siteKey(sourceUrl);
    if (sourceSite && sourceSite === this.siteKey(mediaUrl)) return { ...headers };
    const scoped: Record<string, string> = {};
    for (const key of Object.keys(headers)) {
      if (!this.SITE_BOUND_HEADERS.includes(key.toLowerCase())) scoped[key] = headers[key];
    }
    return scoped;
  }

  /** Later maps win; a header name is matched case-insensitively so no duplicate is sent. */
  static mergeHeaders(base: Record<string, string>, overrides: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = { ...base };
    for (const key of Object.keys(overrides)) {
      for (const existing of Object.keys(merged)) {
        if (existing.toLowerCase() === key.toLowerCase()) delete merged[existing];
      }
      merged[key] = overrides[key];
    }
    return merged;
  }

  private static parseOptionObject(text: string): Record<string, Object> | null {
    for (const candidate of [text, text.replace(/[“”]/g, '"').replace(/'/g, '"')]) {
      try {
        const parsed = JSON.parse(candidate) as Object;
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as Record<string, Object>;
      } catch (_) {}
    }
    return null;
  }

  private static headerRecord(raw: Object | undefined): Record<string, string> {
    let value: Object | undefined | null = raw;
    if (typeof value === 'string') value = this.parseOptionObject(value);
    const headers: Record<string, string> = {};
    if (!value || typeof value !== 'object' || Array.isArray(value)) return headers;
    const record = value as Record<string, Object>;
    for (const key of Object.keys(record)) {
      const item = record[key];
      if (!key.trim() || item === undefined || item === null || typeof item === 'object') continue;
      const text = String(item).trim();
      if (text && !/[\r\n]/.test(text)) headers[key.trim()] = text;
    }
    return headers;
  }

  /** Registrable-domain approximation: `a.cdn.example.com` and `www.example.com` share a site. */
  private static siteKey(url: string): string {
    const match = String(url || '').trim().match(/^[a-z][a-z0-9+.-]*:\/\/(?:[^/?#@]*@)?(\[[^\]]+\]|[^/?#:]+)/i);
    if (!match) return '';
    const host = match[1].toLowerCase();
    if (host.startsWith('[') || /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return host;
    const labels = host.split('.').filter((label: string): boolean => label.length > 0);
    if (labels.length <= 2) return labels.join('.');
    const secondLevel = labels[labels.length - 2];
    const countryCode = labels[labels.length - 1].length === 2;
    const keep = countryCode && ['com', 'net', 'org', 'gov', 'edu', 'co', 'ac'].includes(secondLevel) ? 3 : 2;
    return labels.slice(-keep).join('.');
  }
}
