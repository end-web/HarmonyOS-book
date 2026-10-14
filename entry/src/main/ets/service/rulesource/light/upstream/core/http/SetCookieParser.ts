/**
 * Splits cookie text into single `name=value; attributes` records.
 *
 * Two shapes arrive here: one or more `Set-Cookie` values joined by commas (an HTTP response
 * header), and a `Cookie` request-header value such as `token=...; deviceId=...` that Legado
 * source scripts commonly pass to cookie.setCookie(). ArkWeb accepts exactly one RFC 6265
 * Set-Cookie value per write, so both must be taken apart without damaging attributes.
 */
export class SetCookieParser {
  static split(cookies: string): string[] {
    if (!cookies) return [];
    const values: string[] = [];
    for (const record of this.splitRecords(cookies)) {
      for (const value of this.splitCookieRecord(record)) {
        if (value) values.push(value);
      }
    }
    return values;
  }

  /**
   * A comma separates two cookies only when a `name=` pair follows it directly. The comma inside
   * `Expires=Thu, 01 Jan 2030 00:00:00 GMT` is followed by a date, never by a name.
   */
  private static splitRecords(cookies: string): string[] {
    const records: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < cookies.length; i++) {
      const ch = cookies.charAt(i);
      if (quote) {
        if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === ',' && this.startsWithCookiePair(cookies, i + 1)) {
        records.push(cookies.substring(start, i).trim());
        start = i + 1;
      }
    }
    records.push(cookies.substring(start).trim());
    return records;
  }

  private static startsWithCookiePair(text: string, from: number): boolean {
    let index = from;
    while (index < text.length && /\s/.test(text.charAt(index))) index++;
    const nameStart = index;
    while (index < text.length && /[A-Za-z0-9_.-]/.test(text.charAt(index))) index++;
    return index > nameStart && text.charAt(index) === '=';
  }

  /**
   * A second name/value pair in one record is not a cookie attribute; forwarding the whole string
   * makes ArkWeb reject it and silently loses the login token. Real Set-Cookie attributes stay
   * with their cookie, every additional cookie is emitted separately.
   */
  private static splitCookieRecord(record: string): string[] {
    const parts = this.splitOnSemicolons(record);
    const values: string[] = [];
    let current = '';
    for (const rawPart of parts) {
      const part = rawPart.trim();
      if (!part) continue;
      const separator = part.indexOf('=');
      const name = (separator >= 0 ? part.substring(0, separator) : part).trim().toLowerCase();
      if (!current) {
        current = part;
      } else if (this.isCookieAttribute(name, separator >= 0)) {
        current += `; ${part}`;
      } else if (separator > 0) {
        values.push(current);
        current = part;
      } else {
        current += `; ${part}`;
      }
    }
    if (current) values.push(current);
    return values;
  }

  private static splitOnSemicolons(value: string): string[] {
    const result: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      if (quote) {
        if (ch === quote && value.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === ';') {
        result.push(value.substring(start, i));
        start = i + 1;
      }
    }
    result.push(value.substring(start));
    return result;
  }

  private static isCookieAttribute(name: string, hasValue: boolean): boolean {
    if (hasValue) {
      return name === 'domain' || name === 'path' || name === 'expires' || name === 'max-age' ||
        name === 'samesite' || name === 'priority' || name === 'version' || name === 'comment';
    }
    return name === 'secure' || name === 'httponly' || name === 'partitioned';
  }
}
