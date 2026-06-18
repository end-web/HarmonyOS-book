/**
 * Biqu - 笔趣 (http://www.biqun.cc)
 *
 * 文本电子书内置源。规则来自用户提供的 Legado 书源：
 * 搜索/分类/详情/目录/正文都使用普通 HTML + CSS 解析，不依赖 WebView。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock, CatBuilder
} from '../IBuiltInSource';
import { fetchDoc, fetchText, JElement, Opts, JsoupUtil } from '../BuiltInContext';

const BASE = 'http://www.biqun.cc';
const DBG = 0x9527;
const DT = 'BiquDbg';
const UA = 'Mozilla/5.0 (Linux; Android 9) Mobile Safari/537.36';

function biquHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  h['User-Agent'] = UA;
  h['Referer'] = BASE + '/';
  return h;
}

function firstText(root: JElement, selector: string): string {
  const el = root.selectFirst(selector);
  return el ? el.text().trim() : '';
}

function firstAbs(root: JElement, selector: string, attr: string): string {
  const el = root.selectFirst(selector);
  return el ? el.absUrl(attr) : '';
}

function firstAttr(root: JElement, selector: string, attr: string): string {
  const el = root.selectFirst(selector);
  return el ? el.attr(attr) : '';
}

function normalizeUrl(url: string): string {
  return JsoupUtil.resolveUrl(BASE, url);
}

function parseBooks(doc: JElement): BuiltInBook[] {
  const items = doc.select('li');
  const out: BuiltInBook[] = [];
  const seen = new Set<string>();

  for (const it of items) {
    const nameEl = it.selectFirst('.novelname');
    if (!nameEl) continue;
    const bookUrl = nameEl.absUrl('href');
    const title = nameEl.text().trim();
    if (!bookUrl || !title || seen.has(bookUrl)) continue;
    seen.add(bookUrl);

    const cover = firstAbs(it, 'img', 'src');
    const author = firstText(it, 'span:nth-child(2) > a');
    const intro = firstText(it, '.intro');
    const last = firstText(it, '.last > a');
    const book = new BuiltInBook(cover, bookUrl, title, author, '');
    book.intro = intro;
    book.status = last;
    out.push(book);
  }
  return out;
}

function resolveNextUrl(url: string, booksCount: number): string {
  if (booksCount === 0) return '';
  const full = normalizeUrl(url);
  const m = full.match(/\/(\d+)\.html(?:[?#].*)?$/);
  if (!m) return '';
  const cur = parseInt(m[1], 10);
  if (Number.isNaN(cur)) return '';
  return full.replace(/\/(\d+)\.html(?:[?#].*)?$/, `/${cur + 1}.html`);
}

class BiquClass implements IBuiltInSource {
  readonly id: string = 'biqu_biqun_cc';
  readonly name: string = '笔趣';
  readonly url: string = BASE;
  readonly desc: string = '文本小说源\n来源：www.biqun.cc';
  readonly searchable: boolean = true;
  readonly sourceType: number = 0;

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const p = page <= 1 ? '' : `&page=${page}`;
    const url = `${BASE}/search/result.html?searchkey=${encodeURIComponent(keywords)}${p}`;
    hilog.info(DBG, DT, 'search url=%{public}s', url);
    try {
      const html = await fetchText(url, Opts.withHeaders(biquHeaders()));
      const m = html.match(/<title>([^<]*)<\/title>/i);
      const title = (m && m.length > 1) ? m[1] : '';
      const lower = html.toLowerCase();
      const is522 = lower.indexOf('522') >= 0 || lower.indexOf('timed out') >= 0;
      const challenge = lower.indexOf('just a moment') >= 0 || lower.indexOf('challenge-platform') >= 0 || lower.indexOf('cf-chl') >= 0;
      hilog.info(DBG, DT, 'len=%{public}d title=[%{public}s] is522=%{public}s challenge=%{public}s', html.length, title, String(is522), String(challenge));
      const doc = JsoupUtil.parse(html, url);
      const books = parseBooks(doc);
      hilog.info(DBG, DT, 'parsed books=%{public}d liCount=%{public}d', books.length, doc.select('li').length);
      return new BuiltInSearchResult(books, 1);
    } catch (e) {
      hilog.error(DBG, DT, 'search FAILED=%{public}s', (e as Error).message ?? JSON.stringify(e));
      return new BuiltInSearchResult([], 1);
    }
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    return [
      CatBuilder.menu('分类', [
        ['玄幻', '/category/xuanhuan/1.html'],
        ['修真', '/category/xiuzhen/1.html'],
        ['都市', '/category/dushi/1.html'],
        ['历史', '/category/lishi/1.html'],
        ['网游', '/category/wangyou/1.html'],
        ['科幻', '/category/kehuan/1.html'],
        ['悬疑', '/category/xuanyi/1.html'],
        ['同人', '/category/tongren/1.html'],
        ['轻小说', '/category/qing/1.html'],
        ['女生', '/category/nvsheng/1.html'],
        ['短篇', '/category/duanpian/1.html'],
        ['其他', '/category/qita/1.html'],
      ]),
      CatBuilder.menu('排行榜', [
        ['总点击榜', '/top/allvisit/1.html'],
        ['月点击榜', '/top/monthvisit/1.html'],
        ['周点击榜', '/top/weekvisit/1.html'],
        ['日点击榜', '/top/dayvisit/1.html'],
        ['推荐数榜', '/top/vote/1.html'],
        ['收藏数榜', '/top/mark/1.html'],
        ['下载数榜', '/top/down/1.html'],
        ['评论数榜', '/top/comment/1.html'],
        ['评分榜', '/top/star_score/1.html'],
        ['最新入库', '/top/postdate/1.html'],
      ]),
    ];
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    const fullUrl = normalizeUrl(url);
    try {
      const doc = await fetchDoc(fullUrl, Opts.withHeaders(biquHeaders()));
      const books = parseBooks(doc);
      const nextUrl = resolveNextUrl(fullUrl, books.length);
      const m = fullUrl.match(/\/(\d+)\.html/);
      const cur = m ? parseInt(m[1], 10) : 1;
      const total = nextUrl ? cur + 1 : cur;
      return new BuiltInCategory(books, cur, total, fullUrl, nextUrl);
    } catch (e) {
      console.error(`[Biqu] category failed: ${e}`);
      return new BuiltInCategory([], 1, 1, fullUrl, '');
    }
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    const fullUrl = normalizeUrl(bookUrl);
    try {
      const doc = await fetchDoc(fullUrl, Opts.withHeaders(biquHeaders()));
      const intro = firstText(doc, 'p');
      if (!loadEpisodes) {
        return new BuiltInBookDetail([], intro);
      }

      let tocDoc = doc;
      let items = tocDoc.select('.dirlist > li');
      if (items.length === 0) {
        const tocHref = firstAbs(doc, '.dirlist', 'href') || firstAttr(doc, '.dirlist', 'href');
        if (tocHref) {
          tocDoc = await fetchDoc(tocHref, Opts.withHeaders(biquHeaders()));
          items = tocDoc.select('.dirlist > li');
        }
      }

      const episodes: BuiltInEpisode[] = [];
      const seen = new Set<string>();
      for (const it of items) {
        const a = it.selectFirst('a');
        if (!a) continue;
        const title = a.text().trim();
        const url = a.absUrl('href');
        if (!title || !url || seen.has(url)) continue;
        seen.add(url);
        episodes.push(new BuiltInEpisode(title, url, true));
      }
      return new BuiltInBookDetail(episodes, intro);
    } catch (e) {
      console.error(`[Biqu] detail failed: ${e}`);
      return new BuiltInBookDetail([], '');
    }
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    return chapterUrl;
  }

  async getTextContent(chapterUrl: string, _nextChapterUrl?: string): Promise<string> {
    const fullUrl = normalizeUrl(chapterUrl);
    try {
      const doc = await fetchDoc(fullUrl, Opts.withHeaders(biquHeaders()));
      const paragraphs = doc.select('p');
      const out: string[] = [];
      for (const p of paragraphs) {
        const text = p.text().trim();
        if (!text) continue;
        out.push(text);
      }
      return out.join('\n');
    } catch (e) {
      console.error(`[Biqu] content failed: ${e}`);
      return '';
    }
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    return biquHeaders();
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    const menus = await this.getCategoryMenus();
    if (menus.length === 0 || menus[0].tabs.length === 0) return [];
    const cat = await this.getCategoryList(menus[0].tabs[0].url);
    return [new HomeBlock('笔趣 · 玄幻', cat.books.slice(0, 12), menus[0].tabs[0].url, 'horizontal')];
  }
}

export const Biqu: IBuiltInSource = new BiquClass();
