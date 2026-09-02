import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { BookInfo, HomeBlockSection, SearchResult } from '../../../model/BookSource';
import { JsonArr, JsonObj } from '../../builtin/JsonValue';
import { LocalRuleContentResult } from '../LocalRuleRuntimeTypes';
import { TingYouApiClient } from './TingYouApiClient';
import { TingYouChapterAddress, TingYouSourceIdentity } from './TingYouSourceIdentity';

const TINGYOU_RECOMMENDS_PATH: string = 'homepage/recommends';
const TINGYOU_THRILLER_PATH: string = 'types/14/popular/p1';

class TingYouSearchResult implements SearchResult {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  contentType: 'audio' | 'text' = 'audio';
  completed: boolean | undefined = undefined;
  lastChapter: string = '';
  wordCount: string = '';
  sourceName: string = '';
  sourceUrl: string = '';
  variables: Record<string, string> = {};
}

class TingYouBookInfo implements BookInfo {
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  completed: boolean | undefined = undefined;
  wordCount: string = '';
  lastChapter: string = '';
  tocUrl: string = '';
  variables: Record<string, string> = {};
}

class TingYouHomeBlock implements HomeBlockSection {
  title: string = '';
  books: SearchResult[] = [];
  moreUrl: string = '';
  layout: string = 'horizontal';
  sourceName: string = '';
  sourceUrl: string = '';
}

export class TingYouCategoryResult {
  books: SearchResult[] = [];
  nextUrl: string = '';
}

/** 只为已导入听友音频源补充站点加密接口能力。 */
export class TingYouSourceAdapter {
  static canResolveBook(source: LocalRuleSource, bookUrl: string): boolean {
    return source.isAudio() && TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl) &&
      TingYouSourceIdentity.parseAlbumId(bookUrl) !== undefined;
  }

  static async getBookInfo(source: LocalRuleSource, bookUrl: string): Promise<BookInfo | null> {
    if (!TingYouSourceAdapter.canResolveBook(source, bookUrl)) return null;
    const albumId = TingYouSourceIdentity.parseAlbumId(bookUrl);
    if (albumId === undefined) return null;
    const data = await TingYouApiClient.getPublicData(`album_info/${albumId}`);
    if (data === undefined) return null;

    return TingYouSourceAdapter.mapAlbumInfo(data, albumId);
  }

  static mapAlbumInfo(data: JsonObj, albumId: number): BookInfo | null {
    if (!Number.isSafeInteger(albumId) || albumId <= 0) return null;

    const info = new TingYouBookInfo();
    info.name = data.getString('title', '').trim();
    info.author = data.getString('author', '').trim() || data.getString('teller', '').trim();
    info.coverUrl = data.getString('cover_url', '').trim();
    info.intro = TingYouSourceAdapter.sanitizeIntro(data.getString('synopsis', '').trim() ||
      data.getString('description', '').trim() || data.getString('intro', '').trim());
    info.kind = data.getString('type', '').trim() || data.getString('cat', '').trim();
    if (data.has('status')) info.completed = data.getInt('status', 1) === 0;
    const count = Math.max(0, data.getInt('count', 0));
    info.wordCount = count > 0 ? String(count) : '';
    info.tocUrl = `https://tingyou.fm/albums/${albumId}`;
    info.variables['albumId'] = String(albumId);
    return info.name.length > 0 ? info : null;
  }

  static canResolve(source: LocalRuleSource, chapterUrl: string): boolean {
    return source.isAudio() && TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl) &&
      TingYouSourceIdentity.parseChapterAddress(chapterUrl) !== undefined;
  }

  static async resolveContent(source: LocalRuleSource,
    chapterUrl: string): Promise<LocalRuleContentResult> {
    if (!source.isAudio() || !TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl)) {
      throw new Error('当前导入书源不是听友音频源');
    }
    const address: TingYouChapterAddress | undefined =
      TingYouSourceIdentity.parseChapterAddress(chapterUrl);
    if (address === undefined) throw new Error('听友章节地址格式无效');
    const result = new LocalRuleContentResult();
    result.audioUrl = await TingYouApiClient.resolvePlayUrl(address);
    return result;
  }

  static async getAudioUrl(source: LocalRuleSource, chapterUrl: string): Promise<string> {
    const result = await TingYouSourceAdapter.resolveContent(source, chapterUrl);
    return result.audioUrl;
  }

  static async getHomeBlocks(source: LocalRuleSource): Promise<HomeBlockSection[]> {
    TingYouSourceAdapter.requireImportedSource(source);
    const data = await TingYouApiClient.getPublicData('homepage');
    if (data === undefined) return [];
    const blocks: HomeBlockSection[] = [];
    TingYouSourceAdapter.appendBlock(blocks, source, '最近更新',
      TingYouSourceAdapter.mapBooks(source, data.getArr('recent_updates')), '', 'featured');
    TingYouSourceAdapter.appendBlock(blocks, source, '精品推荐',
      TingYouSourceAdapter.mapBooks(source, data.getArr('recommends')),
      TINGYOU_RECOMMENDS_PATH, 'horizontal');
    const thriller = await TingYouSourceAdapter.getCategory(source, TINGYOU_THRILLER_PATH);
    TingYouSourceAdapter.appendBlock(blocks, source, '恐怖惊悚',
      thriller.books.slice(0, 12), TINGYOU_THRILLER_PATH, 'horizontal');
    return blocks;
  }

  static async getCategory(source: LocalRuleSource, rawPath: string): Promise<TingYouCategoryResult> {
    TingYouSourceAdapter.requireImportedSource(source);
    const result = new TingYouCategoryResult();
    const path = rawPath.trim().replace(new RegExp('^/+', 'g'), '');
    if (path === TINGYOU_RECOMMENDS_PATH) {
      const homepage = await TingYouApiClient.getPublicData('homepage');
      if (homepage !== undefined) {
        result.books = TingYouSourceAdapter.mapBooks(source, homepage.getArr('recommends'));
      }
      return result;
    }
    if (!new RegExp('^types/[0-9]+/[A-Za-z_-]+/p[0-9]+$').test(path)) {
      throw new Error('听友分类地址无效');
    }
    const data = await TingYouApiClient.getPublicData(path);
    if (data === undefined) return result;
    result.books = TingYouSourceAdapter.mapBooks(source, data.getArr('data'));
    const page = Math.max(1, data.getInt('page', 1));
    const pages = Math.max(page, data.getInt('pages', page));
    if (page < pages && result.books.length > 0) {
      result.nextUrl = path.replace(new RegExp('p[0-9]+$'), `p${page + 1}`);
    }
    return result;
  }

  private static appendBlock(output: HomeBlockSection[], source: LocalRuleSource,
    title: string, books: SearchResult[], moreUrl: string, layout: string): void {
    if (books.length === 0) return;
    const block = new TingYouHomeBlock();
    block.title = title;
    block.books = books;
    block.moreUrl = moreUrl;
    block.layout = layout;
    block.sourceName = source.bookSourceName;
    block.sourceUrl = source.bookSourceUrl;
    output.push(block);
  }

  private static mapBooks(source: LocalRuleSource, values: JsonArr): SearchResult[] {
    const output: SearchResult[] = [];
    for (let index = 0; index < values.length(); index++) {
      const item = TingYouSourceAdapter.mapBook(source, values.getObj(index));
      if (item !== undefined) output.push(item);
    }
    return output;
  }

  private static mapBook(source: LocalRuleSource, value: JsonObj): SearchResult | undefined {
    const albumId = value.getString('id', '').trim();
    const title = value.getString('title', '').trim();
    if (!new RegExp('^[0-9]+$').test(albumId) || title.length === 0) return undefined;
    const result = new TingYouSearchResult();
    result.name = title;
    result.author = value.getString('author', '').trim() || value.getString('teller', '').trim();
    result.coverUrl = value.getString('cover_url', '').trim();
    result.bookUrl = `https://tingyou.fm/albums/${albumId}`;
    result.intro = TingYouSourceAdapter.sanitizeIntro(
      value.getString('description', '').trim() || value.getString('synopsis', '').trim() ||
        value.getString('intro', '').trim());
    result.kind = value.getString('category_name', '').trim() || value.getString('type', '').trim() ||
      value.getString('cat', '').trim();
    if (value.has('status')) result.completed = value.getInt('status', 1) === 0;
    const count = Math.max(0, value.getInt('count', 0));
    result.wordCount = count > 0 ? String(count) : '';
    result.sourceName = source.bookSourceName;
    result.sourceUrl = source.bookSourceUrl;
    return result;
  }

  private static sanitizeIntro(value: string): string {
    const clean = value.trim();
    const compact = clean.replace(new RegExp('\\s+', 'g'), '');
    const placeholders: string[] = ['=.=','==', '暂无', '暂无简介', '暂无介绍', '无'];
    return placeholders.includes(compact) ? '' : clean;
  }

  private static requireImportedSource(source: LocalRuleSource): void {
    if (!source.isAudio() || !TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl)) {
      throw new Error('首页数据只对已导入的听友音频源可用');
    }
  }
}
