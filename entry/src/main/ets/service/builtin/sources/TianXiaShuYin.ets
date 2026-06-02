/**
 * TianXiaShuYin - 天下书音 (https://m.shuyinfm.com)
 * 来源：用户提供的 Legado JSON 规则。
 *
 * - 搜索：POST /e/search/index.php，body=keyboard=<key>&show=...
 * - 详情页：HTML 解析 author/cover/intro
 * - 章节：HTML #playlist li a
 * - 音频：章节页的 audio src 由 JS 注入 → WebView 嗅探
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInCategoryTab, BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock
} from '../IBuiltInSource';
import { fetchDoc, fetchText, JElement, JsoupUtil, FetchOptions, Opts } from '../BuiltInContext';
import { getWebViewAudioExtractor } from '../WebViewAudioExtractor';

const TAG = 'TianXia';
const BASE = 'https://m.shuyinfm.com';
const UA = 'Mozilla/5.0 (Linux; Android 9; MIX 2 Build/PKQ1.190118.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/80.0.3987.99 Mobile Safari/537.36';

const ALBUM_PATTERN = /\/album\/[\w-]+\.html/i;

function txHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  h['User-Agent'] = UA;
  h['Referer'] = BASE + '/';
  return h;
}

function tabsOf(arr: string[][]): BuiltInCategoryTab[] {
  const out: BuiltInCategoryTab[] = [];
  for (const t of arr) out.push(new BuiltInCategoryTab(t[0], t[1]));
  return out;
}

const NOVEL_CATS: string[][] = [
  ['言情', '/listinfo-1-1.html'],
  ['玄幻', '/listinfo-2-1.html'],
  ['恐怖', '/listinfo-5-1.html'],
  ['穿越', '/listinfo-7-1.html'],
  ['都市', '/listinfo-8-1.html'],
  ['历史', '/listinfo-16-1.html'],
  ['悬疑', '/listinfo-33-1.html'],
  ['文学', '/listinfo-38-1.html'],
  ['推理', '/listinfo-39-1.html'],
  ['军事', '/listinfo-40-1.html'],
  ['职场', '/listinfo-41-1.html'],
  ['反腐', '/listinfo-56-1.html'],
  ['人物', '/listinfo-58-1.html'],
  ['修真', '/listinfo-60-1.html'],
  ['网游', '/listinfo-63-1.html'],
  ['武侠', '/listinfo-92-1.html'],
];

const PINGSHU_CATS: string[][] = [
  ['单田芳', '/listinfo-42-1.html'],
  ['刘兰芳', '/listinfo-43-1.html'],
  ['田连元', '/listinfo-44-1.html'],
  ['袁阔成', '/listinfo-45-1.html'],
  ['连丽如', '/listinfo-46-1.html'],
  ['张少佐', '/listinfo-47-1.html'],
  ['郭德纲', '/listinfo-57-1.html'],
];

const DRAMA_CATS: string[][] = [
  ['耽美剧', '/listinfo-10-1.html'],
  ['爱情剧', '/listinfo-12-1.html'],
  ['古风剧', '/listinfo-51-1.html'],
  ['现代剧', '/listinfo-54-1.html'],
];

/** 在 element 内找第一个 href 匹配 /album/X.html 的 a */
function findAlbumLink(it: JElement): JElement | null {
  const links = it.select('a');
  for (const a of links) {
    const h = a.attr('href');
    if (h && ALBUM_PATTERN.test(h)) return a;
  }
  return null;
}

function parseList(doc: JElement): BuiltInBook[] {
  const items = doc.select('ul.book-ol > li.book-li');
  const out: BuiltInBook[] = [];
  for (const it of items) {
    const a = findAlbumLink(it);
    if (!a) continue;
    const bookUrl = a.absUrl('href');
    if (!bookUrl) continue;
    const img = it.selectFirst('img');
    const cover = img ? (img.attr('data-original') || img.absUrl('src')) : '';
    const titleEl = it.selectFirst('h4');
    let title = titleEl ? titleEl.text() : '';
    if (!title) title = a.text();
    const metaEl = it.selectFirst('.book-meta');
    const author = metaEl ? metaEl.text() : '';
    const introEl = it.selectFirst('p');
    const intro = introEl ? introEl.text() : '';
    const b = new BuiltInBook(cover, bookUrl, title, author, '');
    b.intro = intro;
    out.push(b);
  }
  return out;
}

/** 解析首页另一种小卡片布局：ul.list-ul > li.list-li（封面 + 书名 + 主播，无简介） */
function parseListLi(container: JElement): BuiltInBook[] {
  const items = container.select('ul.list-ul > li.list-li');
  const out: BuiltInBook[] = [];
  for (const it of items) {
    const a = findAlbumLink(it);
    if (!a) continue;
    const bookUrl = a.absUrl('href');
    if (!bookUrl) continue;
    const img = it.selectFirst('img');
    const cover = img ? (img.attr('data-original') || img.absUrl('src')) : '';
    const titleEl = it.selectFirst('figcaption.list-name');
    const title = titleEl ? titleEl.text() : a.text();
    const authorEl = it.selectFirst('p.module-slide-author');
    const author = authorEl ? authorEl.text() : '';
    out.push(new BuiltInBook(cover, bookUrl, title, author, ''));
  }
  return out;
}

class TianXiaShuYinClass implements IBuiltInSource {
  readonly id: string = 'tianxiashuyin_shuyinfm';
  readonly name: string = '天下书音';
  readonly url: string = BASE;
  readonly desc: string = '推荐指数:5星 ⭐⭐⭐⭐⭐\n来源：m.shuyinfm.com';
  readonly searchable: boolean = true;

  async search(keywords: string, _page: number): Promise<BuiltInSearchResult> {
    const url = `${BASE}/e/search/index.php`;
    const body = `keyboard=${encodeURIComponent(keywords)}&show=title,newstext,player,playadmin,movietime,filetype`;
    const opts: FetchOptions = Opts.post(body);
    opts.headers = txHeaders();
    opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    try {
      const html = await fetchText(url, opts);
      hilog.info(0, TAG, 'search %{public}s html len=%{public}d', keywords, html.length);
      const doc = JsoupUtil.parse(html, BASE);
      const books = parseList(doc);
      hilog.info(0, TAG, 'search parsed %{public}d books', books.length);
      return new BuiltInSearchResult(books, 1);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'search failed: %{public}s', msg);
      return new BuiltInSearchResult([], 1);
    }
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    return [
      new BuiltInCategoryMenu('小说', tabsOf(NOVEL_CATS)),
      new BuiltInCategoryMenu('评书', tabsOf(PINGSHU_CATS)),
      new BuiltInCategoryMenu('广播剧', tabsOf(DRAMA_CATS)),
    ];
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    const fullUrl = url.indexOf('http') === 0 ? url : BASE + url;
    const doc = await fetchDoc(fullUrl, Opts.withHeaders(txHeaders()));
    // 1) 先尝试 ul.book-ol > li.book-li(分类列表页 listinfo-N-1.html)
    let books = parseList(doc);
    // 2) 兜底:首页/榜单页用 ul.list-ul > li.list-li(如 indextop.html / xinpian.html)
    if (books.length === 0) {
      books = parseListLi(doc);
    }
    hilog.info(0, TAG, 'getCategoryList url=%{public}s books=%{public}d', fullUrl, books.length);
    const m = fullUrl.match(/-(\d+)\.html/);
    const cur = m ? parseInt(m[1], 10) : 1;
    let nextUrl = '';
    // 仅 listinfo-N-X.html 这类分页 URL 才有下一页;首页/榜单页式 URL 不分页
    if (books.length >= 10 && m) {
      nextUrl = fullUrl.replace(/-(\d+)\.html/, `-${cur + 1}.html`);
    }
    const total = nextUrl ? cur + 1 : cur;
    return new BuiltInCategory(books, cur, total, url, nextUrl);
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _full: boolean): Promise<BuiltInBookDetail> {
    hilog.info(0, TAG, 'getBookDetail bookUrl=%{public}s loadEpisodes=%{public}d', bookUrl, loadEpisodes ? 1 : 0);

    let doc: JElement;
    try {
      doc = await fetchDoc(bookUrl, Opts.withHeaders(txHeaders()));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'fetch detail failed: %{public}s', msg);
      return new BuiltInBookDetail([], '');
    }

    const introEl = doc.selectFirst('.book-des');
    const intro = introEl ? introEl.text() : '';
    if (!loadEpisodes) return new BuiltInBookDetail([], intro);

    // 1) 先在当前页直接找 #playlist
    let items = doc.select('#playlist li a');
    let from = 'detail#playlist';

    // 2) 没有 → 找"立即播放/开始播放/在线收听"的 a 跳转
    if (items.length === 0) {
      const allA = doc.select('a');
      const triggerKeys = ['立即播放', '开始播放', '在线收听', '播放', '收听'];
      let playUrl = '';
      for (const a of allA) {
        const t = a.text();
        for (const k of triggerKeys) {
          if (t.indexOf(k) >= 0) {
            const h = a.absUrl('href');
            if (h && h.indexOf(BASE) === 0) { playUrl = h; break; }
          }
        }
        if (playUrl) break;
      }
      // 3) 兜底：根据 album URL 推 play URL 形式
      // /album/X-Y.html 可能映射到 /audio/X-Y-0.html 或 /play/X-Y-1-1.html 等
      const candidatePlayUrls: string[] = [];
      const m = bookUrl.match(/\/album\/([\w-]+)\.html/i);
      if (m) {
        const slug = m[1];
        candidatePlayUrls.push(`${BASE}/audio/${slug}-0.html`);
        candidatePlayUrls.push(`${BASE}/audio-${slug}-0.html`);
        candidatePlayUrls.push(`${BASE}/play/${slug}-1-1.html`);
        candidatePlayUrls.push(`${BASE}/play-${slug}-1-1.html`);
      }
      const tryUrls = playUrl ? [playUrl, ...candidatePlayUrls] : candidatePlayUrls;
      hilog.info(0, TAG, 'detail no #playlist, try URLs (%{public}d)', tryUrls.length);

      for (const u of tryUrls) {
        try {
          hilog.info(0, TAG, 'try playUrl=%{public}s', u);
          const playDoc = await fetchDoc(u, Opts.withHeaders(txHeaders()));
          items = playDoc.select('#playlist li a');
          if (items.length === 0) {
            // 也试 .playlist > li > a / .playlist a
            items = playDoc.select('.playlist > li > a');
          }
          if (items.length > 0) {
            from = `playPage:${u}`;
            break;
          } else {
            hilog.info(0, TAG, 'playUrl=%{public}s no #playlist (loaded len=%{public}d)', u, playDoc.outerHtml().length);
          }
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          hilog.warn(0, TAG, 'playUrl=%{public}s failed: %{public}s', u, msg);
        }
      }
    }

    hilog.info(0, TAG, 'toc items=%{public}d from=%{public}s', items.length, from);

    const episodes: BuiltInEpisode[] = [];
    for (const a of items) {
      const t = a.text().trim();
      const u = a.absUrl('href');
      if (!u) continue;
      // 只保留站内播放页链接（必须是 https?://m.shuyinfm.com/audio... 之类）
      if (u.indexOf(BASE) !== 0) continue;
      // 排除导航（不带数字的链接，例如 /listinfo-1-1.html / /index.html）
      if (!/audio[\/\-]/i.test(u) && !/play[\/\-]/i.test(u)) continue;
      episodes.push(new BuiltInEpisode(t || `第${episodes.length + 1}集`, u));
    }
    hilog.info(0, TAG, 'final episodes=%{public}d (after url filter)', episodes.length);
    return new BuiltInBookDetail(episodes, intro);
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    hilog.info(0, TAG, 'getAudioUrl chapter=%{public}s', chapterUrl);
    try {
      const expr = '(function(){var a=document.querySelector("audio[id*=audio], audio");return a?(a.src||a.getAttribute("src")||""):"";})()';
      const v = await getWebViewAudioExtractor().extract(chapterUrl, expr, 3000);
      const cleaned = v ? v.replace(/['"]/g, '') : '';
      hilog.info(0, TAG, 'getAudioUrl result=%{public}s', cleaned || '(empty)');
      return cleaned || chapterUrl;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getAudioUrl failed: %{public}s', msg);
      return chapterUrl;
    }
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = UA;
    h['Referer'] = BASE + '/';
    return h;
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    try {
      const doc = await fetchDoc(BASE + '/', Opts.withHeaders(txHeaders()));
      // 首页结构：div.list / div.module 各包一个 h2.module-title-h + ul.list-ul 或 ul.book-ol
      const containers = doc.select('div.list, div.module');
      hilog.info(0, TAG, 'home containers=%{public}d', containers.length);
      const blocks: HomeBlock[] = [];
      for (const c of containers) {
        const titleEl = c.selectFirst('h2.module-title-h');
        if (!titleEl) continue;
        const title = titleEl.text().trim();
        if (!title) continue;
        const moreEl = c.selectFirst('.more a');
        const moreUrl = moreEl ? moreEl.absUrl('href') : '';

        // book-ol：带简介的大卡片
        let books: BuiltInBook[] = parseList(c);
        let layout = 'grid';
        if (books.length === 0) {
          // list-ul：封面+书名+主播的小卡片，横向滚动
          books = parseListLi(c);
          layout = 'horizontal';
        }
        if (books.length === 0) continue;
        blocks.push(new HomeBlock(title, books, moreUrl, layout));
      }
      hilog.info(0, TAG, 'home blocks=%{public}d', blocks.length);
      return blocks;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0, TAG, 'getHomeBlocks failed: %{public}s', msg);
      return [];
    }
  }
}

export const TianXiaShuYin: IBuiltInSource = new TianXiaShuYinClass();
