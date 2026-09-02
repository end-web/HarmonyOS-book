export class TingYouChapterAddress {
  albumId: number = 0;
  chapterIndex: number = 0;

  static of(albumId: number, chapterIndex: number): TingYouChapterAddress {
    const value = new TingYouChapterAddress();
    value.albumId = albumId;
    value.chapterIndex = chapterIndex;
    return value;
  }
}

/** 听友适配仅绑定明确的站点主机和章节地址，不能由书源名称触发。 */
export class TingYouSourceIdentity {
  static isSourceUrl(sourceUrl: string | undefined): boolean {
    if (sourceUrl === undefined) return false;
    return TingYouSourceIdentity.isTingYouHost(
      TingYouSourceIdentity.httpHost(sourceUrl.trim()));
  }

  static parseChapterAddress(chapterUrl: string): TingYouChapterAddress | undefined {
    const clean = chapterUrl.trim();
    if (clean.length === 0) return undefined;
    let route = '';
    const lower = clean.toLowerCase();
    const playPrefix = 'tingyou://play/';
    if (lower.startsWith(playPrefix)) {
      route = clean.substring(playPrefix.length);
    } else {
      const host = TingYouSourceIdentity.httpHost(clean);
      if (!TingYouSourceIdentity.isTingYouHost(host)) return undefined;
      const path = TingYouSourceIdentity.httpPath(clean);
      const audioPrefix = '/audios/';
      if (!path.toLowerCase().startsWith(audioPrefix)) return undefined;
      route = path.substring(audioPrefix.length);
    }

    const pieces = route.split('/');
    if (pieces.length !== 2 || !new RegExp('^[0-9]+$').test(pieces[0]) ||
      !new RegExp('^[0-9]+$').test(pieces[1])) return undefined;
    const albumId = Number(pieces[0]);
    const chapterIndex = Number(pieces[1]);
    if (!Number.isSafeInteger(albumId) || !Number.isSafeInteger(chapterIndex) ||
      albumId <= 0 || chapterIndex <= 0) return undefined;
    return TingYouChapterAddress.of(albumId, chapterIndex);
  }

  static parseAlbumId(bookUrl: string): number | undefined {
    const clean = bookUrl.trim();
    if (!TingYouSourceIdentity.isTingYouHost(TingYouSourceIdentity.httpHost(clean))) return undefined;
    let path = TingYouSourceIdentity.httpPath(clean);
    const prefix = '/albums/';
    if (!path.toLowerCase().startsWith(prefix)) return undefined;
    path = path.substring(prefix.length);
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    if (!new RegExp('^[0-9]+$').test(path)) return undefined;
    const albumId = Number(path);
    return Number.isSafeInteger(albumId) && albumId > 0 ? albumId : undefined;
  }

  static toPlayUrl(address: TingYouChapterAddress): string {
    return `tingyou://play/${address.albumId}/${address.chapterIndex}`;
  }

  private static httpHost(value: string): string {
    const schemeEnd = value.indexOf('://');
    if (schemeEnd <= 0) return '';
    const scheme = value.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') return '';
    const authorityStart = schemeEnd + 3;
    let authorityEnd = value.length;
    const slash = value.indexOf('/', authorityStart);
    const query = value.indexOf('?', authorityStart);
    const hash = value.indexOf('#', authorityStart);
    if (slash >= 0) authorityEnd = Math.min(authorityEnd, slash);
    if (query >= 0) authorityEnd = Math.min(authorityEnd, query);
    if (hash >= 0) authorityEnd = Math.min(authorityEnd, hash);
    const authority = value.substring(authorityStart, authorityEnd).trim().toLowerCase();
    if (authority.includes('@') || authority.includes(':')) return '';
    return authority;
  }

  private static httpPath(value: string): string {
    const schemeEnd = value.indexOf('://');
    if (schemeEnd <= 0) return '';
    const pathStart = value.indexOf('/', schemeEnd + 3);
    if (pathStart < 0) return '';
    let pathEnd = value.length;
    const query = value.indexOf('?', pathStart);
    const hash = value.indexOf('#', pathStart);
    if (query >= 0) pathEnd = Math.min(pathEnd, query);
    if (hash >= 0) pathEnd = Math.min(pathEnd, hash);
    return value.substring(pathStart, pathEnd);
  }

  private static isTingYouHost(host: string): boolean {
    return host === 'tingyou.fm' || host === 'www.tingyou.fm';
  }
}
