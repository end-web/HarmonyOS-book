/**
 * BuiltInSourceRegistry - 内置源注册表
 *
 * - 把每个 IBuiltInSource 实例 wrap 成一个合成 BookSource（bookSourceUrl = builtin://eprendre/<id>）
 * - 提供 lookup(bookSourceUrl) 取回原插件实例
 * - 内存缓存"最近搜索结果"，让详情页能拿到 cover/title/intro 等元数据（因为详情接口不传这些）
 */

import { BookSource, SearchRule, TocRule, ContentRule, BookInfoRule, ExploreRule } from '../../model/BookSource';
import { IBuiltInSource, BuiltInBook } from './IBuiltInSource';

/** 合成 BookSource 的 URL 前缀 */
export const BUILTIN_SCHEME = 'builtin://eprendre/';

const sourcesById: Map<string, IBuiltInSource> = new Map();
const bookMetaCache: Map<string, BuiltInBook> = new Map();
/** 内置源 ID → 是否禁用（true=禁用） */
const disabledIds: Set<string> = new Set();

/* ─────────── 帮助函数：构造空 Rule（避免 obj-literal 报错） ─────────── */

class EmptySearchRule implements SearchRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
}

class EmptyTocRule implements TocRule {
  chapterList: string = '';
  chapterName: string = '';
  chapterUrl: string = '';
}

class EmptyContentRule implements ContentRule {
  content: string = '';
}

class EmptyBookInfoRule implements BookInfoRule {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  tocUrl: string = '';
}

class EmptyExploreRule implements ExploreRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
}

class BuiltInBookSource implements BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: number = 1;
  bookSourceGroup: string = '内置·eprendre';
  bookSourceComment: string;
  enabled: boolean = true;
  enabledExplore: boolean = true;
  searchUrl: string;
  exploreUrl: string = '__builtin__';
  header: string = '';
  respondTime: number = 0;
  customOrder: number = 0;
  weight: number = 0;
  ruleSearch: SearchRule = new EmptySearchRule();
  ruleToc: TocRule = new EmptyTocRule();
  ruleContent: ContentRule = new EmptyContentRule();
  ruleBookInfo: BookInfoRule = new EmptyBookInfoRule();
  ruleExplore: ExploreRule = new EmptyExploreRule();

  constructor(s: IBuiltInSource, customOrder: number, enabled: boolean) {
    this.bookSourceUrl = BUILTIN_SCHEME + s.id;
    this.bookSourceName = s.name;
    this.bookSourceComment = s.desc;
    this.searchUrl = s.searchable ? '__builtin__' : '';
    this.customOrder = customOrder;
    this.enabled = enabled;
  }
}

export class BuiltInSourceRegistry {
  static register(s: IBuiltInSource): void {
    sourcesById.set(s.id, s);
  }

  static get(id: string): IBuiltInSource | undefined {
    return sourcesById.get(id);
  }

  /** 根据合成 bookSourceUrl 查回插件实例 */
  static getByUrl(bookSourceUrl: string | undefined | null): IBuiltInSource | undefined {
    if (!bookSourceUrl || typeof bookSourceUrl !== 'string') return undefined;
    if (!bookSourceUrl.startsWith(BUILTIN_SCHEME)) return undefined;
    const id = bookSourceUrl.substring(BUILTIN_SCHEME.length);
    return sourcesById.get(id);
  }

  static all(): IBuiltInSource[] {
    return Array.from(sourcesById.values());
  }

  /** 是否是内置源 */
  static isBuiltIn(bookSourceUrl: string | undefined | null): boolean {
    if (!bookSourceUrl || typeof bookSourceUrl !== 'string') return false;
    return bookSourceUrl.startsWith(BUILTIN_SCHEME);
  }

  /** 把内置源全部 materialize 成合成 BookSource */
  static materialize(): BookSource[] {
    const list: BookSource[] = [];
    let order = -1000;
    for (const s of BuiltInSourceRegistry.all()) {
      const enabled = !disabledIds.has(s.id);
      list.push(new BuiltInBookSource(s, order++, enabled));
    }
    return list;
  }

  static toBookSource(s: IBuiltInSource, customOrder: number = 0): BookSource {
    const enabled = !disabledIds.has(s.id);
    return new BuiltInBookSource(s, customOrder, enabled);
  }

  /** 设置禁用列表（启动时由 SourceDataService 注入） */
  static setDisabledIds(ids: string[]): void {
    disabledIds.clear();
    for (const id of ids) disabledIds.add(id);
  }

  /** 切换某个内置源的启用状态 */
  static setBuiltinEnabled(bookSourceUrl: string, enabled: boolean): void {
    if (!BuiltInSourceRegistry.isBuiltIn(bookSourceUrl)) return;
    const id = bookSourceUrl.substring(BUILTIN_SCHEME.length);
    if (enabled) disabledIds.delete(id);
    else disabledIds.add(id);
  }

  static getDisabledIds(): string[] {
    return Array.from(disabledIds);
  }

  // ─────────── 元信息缓存 ───────────

  static cacheBookMeta(book: BuiltInBook): void {
    if (book.bookUrl) {
      bookMetaCache.set(book.bookUrl, book);
      if (bookMetaCache.size > 500) {
        const it = bookMetaCache.keys().next();
        if (!it.done && it.value !== undefined) {
          bookMetaCache.delete(it.value as string);
        }
      }
    }
  }

  static getBookMeta(bookUrl: string): BuiltInBook | undefined {
    return bookMetaCache.get(bookUrl);
  }
}
