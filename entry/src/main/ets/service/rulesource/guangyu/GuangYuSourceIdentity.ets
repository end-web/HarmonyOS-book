import { BookSource } from '../../../model/BookSource';

export const GUANG_YU_SOURCE_URL: string = '光遇聚合';
export const GUANG_YU_SOURCE_VERSION: string = '26.8.28';

const BOOK_PREFIX: string = 'gy://book/';
const CATALOG_PREFIX: string = 'gy://catalog/';
const CHAPTER_PREFIX: string = 'gy://chapter/';

export class GuangYuRouteKind {
  static readonly INVALID: number = 0;
  static readonly BOOK: number = 1;
  static readonly CATALOG: number = 2;
  static readonly CHAPTER: number = 3;
}

/** 持久化到 Book/Chapter 的结构化路由，不携带 token 或临时媒体地址。 */
export class GuangYuRoute {
  kind: number = GuangYuRouteKind.INVALID;
  tab: string = '';
  provider: string = '';
  bookId: string = '';
  itemId: string = '';
  toneId: string = '4';

  static book(tab: string, provider: string, bookId: string): string {
    return `${BOOK_PREFIX}${GuangYuRoute.encode(tab)}/${GuangYuRoute.encode(provider)}/` +
      `${GuangYuRoute.encode(bookId)}`;
  }

  static catalog(tab: string, provider: string, bookId: string, toneId: string): string {
    return `${CATALOG_PREFIX}${GuangYuRoute.encode(tab)}/${GuangYuRoute.encode(provider)}/` +
      `${GuangYuRoute.encode(bookId)}/${GuangYuRoute.encode(toneId || '4')}`;
  }

  static chapter(tab: string, provider: string, bookId: string,
    itemId: string, toneId: string): string {
    return `${CHAPTER_PREFIX}${GuangYuRoute.encode(tab)}/${GuangYuRoute.encode(provider)}/` +
      `${GuangYuRoute.encode(bookId)}/${GuangYuRoute.encode(itemId)}/` +
      `${GuangYuRoute.encode(toneId || '4')}`;
  }

  static parse(value: string): GuangYuRoute {
    const route = new GuangYuRoute();
    let payload = '';
    let expectedParts = 0;
    if (value.startsWith(BOOK_PREFIX)) {
      route.kind = GuangYuRouteKind.BOOK;
      payload = value.substring(BOOK_PREFIX.length);
      expectedParts = 3;
    } else if (value.startsWith(CATALOG_PREFIX)) {
      route.kind = GuangYuRouteKind.CATALOG;
      payload = value.substring(CATALOG_PREFIX.length);
      expectedParts = 4;
    } else if (value.startsWith(CHAPTER_PREFIX)) {
      route.kind = GuangYuRouteKind.CHAPTER;
      payload = value.substring(CHAPTER_PREFIX.length);
      expectedParts = 5;
    } else {
      return route;
    }

    const parts = payload.split('/');
    if (parts.length !== expectedParts) return new GuangYuRoute();
    try {
      route.tab = decodeURIComponent(parts[0]);
      route.provider = decodeURIComponent(parts[1]);
      route.bookId = decodeURIComponent(parts[2]);
      if (route.kind === GuangYuRouteKind.CATALOG) {
        route.toneId = decodeURIComponent(parts[3]) || '4';
      } else if (route.kind === GuangYuRouteKind.CHAPTER) {
        route.itemId = decodeURIComponent(parts[3]);
        route.toneId = decodeURIComponent(parts[4]) || '4';
      }
    } catch (_error) {
      return new GuangYuRoute();
    }
    if (route.tab.length === 0 || route.provider.length === 0 || route.bookId.length === 0) {
      return new GuangYuRoute();
    }
    if (route.kind === GuangYuRouteKind.CHAPTER && route.itemId.length === 0) {
      return new GuangYuRoute();
    }
    return route;
  }

  private static encode(value: string): string {
    return encodeURIComponent(value.trim());
  }
}

export class GuangYuSourceIdentity {
  static isSourceUrl(sourceUrl: string | undefined): boolean {
    return (sourceUrl ?? '').trim() === GUANG_YU_SOURCE_URL;
  }

  static isSource(source: BookSource): boolean {
    return GuangYuSourceIdentity.isSourceUrl(source.bookSourceUrl);
  }

  static contentType(tab: string): 'audio' | 'text' {
    const normalized = tab.trim().toLowerCase();
    if (normalized === '听书' || normalized === '有声' || normalized === 'audio') return 'audio';
    return 'text';
  }
}
