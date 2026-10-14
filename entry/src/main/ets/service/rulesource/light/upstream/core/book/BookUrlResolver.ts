import { HttpResponse } from '../http/HttpClient';

export class BookUrlResolver {
  /**
   * A book/list URL is a scalar field. Some HTML rules intentionally match more than one
   * descendant (for example `a@href` inside a result card). Android Legado consumes the first
   * match for URL fields; accepting the newline-joined value would pass several addresses to
   * Network Kit as one malformed URL.
   */
  static scalar(url: string): string {
    const value = (url || '').trim();
    if (!value) return '';
    const lineBreak = value.search(/[\r\n]/);
    return (lineBreak >= 0 ? value.substring(0, lineBreak) : value).trim();
  }

  static resolveScalar(url: string, base: string): string {
    return this.resolve(this.scalar(url), base);
  }

  static cleanBaseUrl(url: string): string {
    if (!url) return '';
    const hashIndex = url.indexOf('##');
    return (hashIndex >= 0 ? url.substring(0, hashIndex) : url).trim();
  }

  static effectiveBase(response: HttpResponse | null, requestUrl: string, fallbackUrl: string): string {
    const respUrl = this.cleanBaseUrl(response?.url || '');
    if (this.isHttpUrl(respUrl)) return respUrl;
    const req = this.cleanBaseUrl(requestUrl);
    if (this.isHttpUrl(req)) return req;
    return this.cleanBaseUrl(fallbackUrl);
  }

  static resolve(url: string, base: string): string {
    const value = (url || '').trim();
    if (!value || /^https?:\/\//i.test(value) || value.startsWith('data:')) return value;
    if (/^\/\/[A-Za-z0-9.-]+(?::\d+)?(?:[/?#]|$)/.test(value)) return 'https:' + value;

    const cleanBase = this.cleanBaseUrl(base);
    if (!cleanBase) return value;

    // A URL that starts with `?` is a query-only reference.  It keeps the
    // current document path and replaces its query string.  This is common
    // in catalogue pages such as `/read.php?name=...`, whose next chapter is
    // emitted as `?name=...&page=...`.  Treating it like a normal relative
    // path would derive the directory (`/`) and silently drop `read.php`.
    if (value.startsWith('?')) {
      const fragmentIndex = cleanBase.indexOf('#');
      const withoutFragment = fragmentIndex >= 0 ? cleanBase.substring(0, fragmentIndex) : cleanBase;
      const queryIndex = withoutFragment.indexOf('?');
      const documentPath = queryIndex >= 0 ? withoutFragment.substring(0, queryIndex) : withoutFragment;
      return documentPath + value;
    }

    // Fragment-only references keep the complete current URL and only add a
    // fragment.  They are not chapter pages, but handling them here avoids
    // turning `#page-2` into a sibling path when a source uses one.
    if (value.startsWith('#')) {
      const fragmentIndex = cleanBase.indexOf('#');
      const withoutFragment = fragmentIndex >= 0 ? cleanBase.substring(0, fragmentIndex) : cleanBase;
      return withoutFragment + value;
    }

    const origin = cleanBase.match(/^(https?:\/\/[^/?#]+)/i);
    if (value.startsWith('/')) {
      return origin ? this.normalizeDotSegments(origin[0] + value) : cleanBase + value;
    }

    const pathEnd = cleanBase.search(/[?#]/);
    const withoutQuery = pathEnd >= 0 ? cleanBase.substring(0, pathEnd) : cleanBase;
    // `https://example.com` has no path at all: its directory is the site root, and the host name
    // must not be mistaken for the last path segment.
    const baseDir = origin && withoutQuery.length === origin[0].length ? `${withoutQuery}/` :
      (withoutQuery.endsWith('/') ? withoutQuery : withoutQuery.replace(/\/[^/]*$/, '/'));
    return this.normalizeDotSegments(baseDir + value);
  }

  /** Collapses `.` and `..` in the path of an absolute HTTP(S) address; query and fragment stay as written. */
  private static normalizeDotSegments(url: string): string {
    const match = url.match(/^(https?:\/\/[^/?#]+)(\/[^?#]*)?([?#][\s\S]*)?$/i);
    if (!match || !match[2] || !/(?:^|\/)\.\.?(?:\/|$)/.test(match[2])) return url;
    const segments: string[] = [];
    const parts = match[2].split('/');
    for (let index = 1; index < parts.length; index++) {
      const part = parts[index];
      const last = index === parts.length - 1;
      if (part === '.') {
        if (last) segments.push('');
      } else if (part === '..') {
        if (segments.length > 0) segments.pop();
        if (last) segments.push('');
      } else {
        segments.push(part);
      }
    }
    return `${match[1]}/${segments.join('/')}${match[3] || ''}`;
  }

  static setVariableJson(raw: string, key: string, value: string): string {
    const data = this.parseVariableJson(raw);
    data[key] = value;
    return JSON.stringify(data);
  }

  static getVariableJson(raw: string, key: string): string {
    return this.parseVariableJson(raw)[key] || '';
  }

  private static isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private static parseVariableJson(raw: string): Record<string, string> {
    try {
      return JSON.parse(raw || '{}') as Record<string, string>;
    } catch (_) {
      return {};
    }
  }
}
