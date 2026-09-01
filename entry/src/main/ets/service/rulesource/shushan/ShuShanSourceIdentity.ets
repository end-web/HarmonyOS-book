import { BookSource } from '../../../model/BookSource';

export const SHU_SHAN_SOURCE_URL: string = '书山聚合';
export const SHU_SHAN_SOURCE_VERSION: string = '5.42';

const BOOK_PREFIX: string = 'ss://book/';
const CATALOG_PREFIX: string = 'ss://catalog/';
const CHAPTER_PREFIX: string = 'ss://chapter/';

export class ShuShanRouteKind {
  static readonly INVALID: number = 0;
  static readonly BOOK: number = 1;
  static readonly CATALOG: number = 2;
  static readonly CHAPTER: number = 3;
}

/** 书山专用内部路由；只保存内容定位信息，不携带 token 或临时媒体地址。 */
export class ShuShanRoute {
  kind: number = ShuShanRouteKind.INVALID;
  tab: string = '';
  provider: string = '';
  bookUrl: string = '';
  bookId: string = '';
  title: string = '';
  chapterUrl: string = '';
  chapterId: string = '';
  toneId: string = '';

  static book(tab: string, provider: string, bookUrl: string, title: string): string {
    return `${BOOK_PREFIX}${ShuShanRoute.encode(tab)}/${ShuShanRoute.encode(provider)}/` +
      `${ShuShanRoute.encode(bookUrl)}/${ShuShanRoute.encode(title)}`;
  }

  static catalog(tab: string, provider: string, bookUrl: string, bookId: string,
    title: string, toneId: string): string {
    return `${CATALOG_PREFIX}${ShuShanRoute.encode(tab)}/${ShuShanRoute.encode(provider)}/` +
      `${ShuShanRoute.encode(bookUrl)}/${ShuShanRoute.encode(bookId)}/` +
      `${ShuShanRoute.encode(title)}/${ShuShanRoute.encode(toneId)}`;
  }

  static chapter(tab: string, provider: string, bookUrl: string, bookId: string,
    title: string, chapterUrl: string, chapterId: string, toneId: string): string {
    return `${CHAPTER_PREFIX}${ShuShanRoute.encode(tab)}/${ShuShanRoute.encode(provider)}/` +
      `${ShuShanRoute.encode(bookUrl)}/${ShuShanRoute.encode(bookId)}/` +
      `${ShuShanRoute.encode(title)}/${ShuShanRoute.encode(chapterUrl)}/` +
      `${ShuShanRoute.encode(chapterId)}/${ShuShanRoute.encode(toneId)}`;
  }

  static parse(value: string): ShuShanRoute {
    const route = new ShuShanRoute();
    let rawPayload = '';
    let expectedParts = 0;
    if (value.startsWith(BOOK_PREFIX)) {
      route.kind = ShuShanRouteKind.BOOK;
      rawPayload = value.substring(BOOK_PREFIX.length);
      expectedParts = 4;
    } else if (value.startsWith(CATALOG_PREFIX)) {
      route.kind = ShuShanRouteKind.CATALOG;
      rawPayload = value.substring(CATALOG_PREFIX.length);
      expectedParts = 6;
    } else if (value.startsWith(CHAPTER_PREFIX)) {
      route.kind = ShuShanRouteKind.CHAPTER;
      rawPayload = value.substring(CHAPTER_PREFIX.length);
      expectedParts = 8;
    } else {
      return route;
    }

    const parts = rawPayload.split('/');
    if (parts.length !== expectedParts) return new ShuShanRoute();
    try {
      route.tab = decodeURIComponent(parts[0]);
      route.provider = decodeURIComponent(parts[1]);
      route.bookUrl = decodeURIComponent(parts[2]);
      if (route.kind === ShuShanRouteKind.BOOK) {
        route.title = decodeURIComponent(parts[3]);
      } else {
        route.bookId = decodeURIComponent(parts[3]);
        route.title = decodeURIComponent(parts[4]);
        if (route.kind === ShuShanRouteKind.CATALOG) {
          route.toneId = decodeURIComponent(parts[5]);
        } else {
          route.chapterUrl = decodeURIComponent(parts[5]);
          route.chapterId = decodeURIComponent(parts[6]);
          route.toneId = decodeURIComponent(parts[7]);
        }
      }
    } catch (_error) {
      return new ShuShanRoute();
    }
    if (route.tab.length === 0 || route.provider.length === 0 || route.bookUrl.length === 0 ||
      route.title.length === 0) {
      return new ShuShanRoute();
    }
    return route;
  }

  private static encode(value: string): string {
    return encodeURIComponent(value.trim());
  }
}

export class ShuShanSourceIdentity {
  static isSourceUrl(sourceUrl: string | undefined): boolean {
    return (sourceUrl ?? '').trim() === SHU_SHAN_SOURCE_URL;
  }

  static isSource(source: BookSource): boolean {
    return ShuShanSourceIdentity.isSourceUrl(source.bookSourceUrl);
  }

  static contentType(tab: string): 'audio' | 'text' {
    const normalized = tab.trim().toLowerCase();
    if (normalized === '听书' || normalized === '有声' || normalized === 'audio') return 'audio';
    return 'text';
  }
}
