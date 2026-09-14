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

  static parseCategoryPath(address: string, pageNumber: number = 1): string {
    let path = address.trim();
    if (new RegExp('^https?://', 'i').test(path)) {
      if (!TingYouSourceIdentity.isSourceUrl(path)) return '';
      path = TingYouSourceIdentity.httpPath(path);
    }
    path = path.split(new RegExp('[?#]'), 1)[0].replace(new RegExp('^/+|/+$', 'g'), '');
    // 导入源也会把分类、排序和分页放在首页 URL 的查询参数中。
    if (path.length === 0) return TingYouSourceIdentity.parseCategoryQuery(address, pageNumber);
    // 网站分类页使用 type ID，公开数据接口还需要排序方式和页码。
    if (new RegExp('^categories/[0-9]+$').test(path)) {
      const typeId: number = Number(path.substring('categories/'.length));
      if (!Number.isSafeInteger(typeId) || typeId <= 0) return '';
      const page: number = Number.isSafeInteger(pageNumber) && pageNumber > 0 ? pageNumber : 1;
      return `types/${typeId}/comprehensive/p${page}`;
    }
    return path === 'homepage/recommends' || new RegExp('^types/[0-9]+/[A-Za-z_-]+/p[0-9]+$').test(path)
      ? path : '';
  }

  private static parseCategoryQuery(address: string, pageNumber: number): string {
    const clean = address.split('#', 1)[0];
    const queryStart = clean.indexOf('?');
    if (queryStart < 0) return '';
    let typeId: string = '';
    let sort: string = 'comprehensive';
    let page: string = String(Number.isSafeInteger(pageNumber) && pageNumber > 0 ? pageNumber : 1);
    const seen = new Set<string>();
    for (const pair of clean.substring(queryStart + 1).split('&')) {
      const separator = pair.indexOf('=');
      if (separator < 0) continue;
      let name: string;
      let value: string;
      try {
        name = decodeURIComponent(pair.substring(0, separator));
        value = decodeURIComponent(pair.substring(separator + 1));
      } catch (_error) {
        return '';
      }
      if (name !== 'type' && name !== 'sort' && name !== 'page') continue;
      if (seen.has(name)) return '';
      seen.add(name);
      if (name === 'type') typeId = value;
      else if (name === 'sort') sort = value;
      else page = value;
    }
    if (!new RegExp('^[0-9]+$').test(typeId) || !Number.isSafeInteger(Number(typeId)) ||
      Number(typeId) <= 0 || !new RegExp('^[A-Za-z_-]+$').test(sort) ||
      !new RegExp('^[0-9]+$').test(page) || !Number.isSafeInteger(Number(page)) || Number(page) <= 0) return '';
    return `types/${Number(typeId)}/${sort}/p${Number(page)}`;
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
