/** A persistent HTTP URL with a local-only source reference. Never send the fragment to HTTP. */
export class SourceCoverUrl {
  static readonly MARKER = '#source-cover-v1=';

  static wrap(url: string, source: string): string {
    if (!/^https?:\/\//i.test(url) || !source) return url;
    return url.split('#')[0] + this.MARKER + encodeURIComponent(source);
  }

  static isEncoded(raw: string): boolean { return raw.includes(this.MARKER); }

  static source(raw: string): string {
    if (raw.length > 8192) throw new Error('Cover URL too long');
    const index = raw.indexOf(this.MARKER);
    if (index < 0) return '';
    const source = decodeURIComponent(raw.substring(index + this.MARKER.length));
    if (!/^https?:\/\//i.test(source)) throw new Error('Invalid cover source');
    return source;
  }

  static address(raw: string): string {
    const url = raw.split('#')[0];
    if (!/^https?:\/\//i.test(url)) throw new Error('Invalid cover address');
    return url;
  }
}
