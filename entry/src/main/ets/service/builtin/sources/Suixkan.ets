/**
 * Suixkan - 随心看 (https://m.suixkan.com)
 *
 * 文本电子书内置源。结构经真机/curl 实测分析:
 * - 搜索: GET /s/<page>.html?keyword=<key>
 *         书列表 .v-list-item(div, onclick="newWebView('/b/<id>.html', ...)") + 书名 .v-title
 * - 目录: 详情页 /b/<id>.html → 目录页 /c/<id>.html → .catalog_ls 内 <a href="/r/<book>/<chap>.html">
 * - 正文: /r/<book>/<chap>.html → 全部 <p>(容器类名混淆,直接取 p)
 */

import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock
} from '../IBuiltInSource';
import { fetchDoc, JElement, Opts, JsoupUtil } from '../BuiltInContext';

const BASE = 'https://m.suixkan.com';
const UA = 'Mozilla/5.0 (Linux; Android 11; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

function sxHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  h['User-Agent'] = UA;
  h['Referer'] = BASE + '/';
  return h;
}

function firstText(root: JElement, selector: string): string {
  const el = root.selectFirst(selector);
  return el ? el.text().trim() : '';
}

function normalizeUrl(url: string): string {
  return JsoupUtil.resolveUrl(BASE, url);
}

/** 从 onclick="newWebView('/b/228578.html', ...)" 提取书籍 URL;过滤 JS 模板 decoy */
function extractBookUrl(onclick: string): string {
  const m = onclick.match(/newWebView\(\s*'(\/b\/\d+\.html)'/);
  return m ? m[1] : '';
}

function parseSearchBooks(doc: JElement): BuiltInBook[] {
  const items = doc.select('.v-list-item');
  const out: BuiltInBook[] = [];
  const seen = new Set<string>();
  for (const it of items) {
    const rel = extractBookUrl(it.attr('onclick'));
    if (!rel) continue;
    const bookUrl = normalizeUrl(rel);
    const title = firstText(it, '.v-title');
    if (!title || seen.has(bookUrl)) continue;
    seen.add(bookUrl);
    const author = firstText(it, '.v-author');
    out.push(new BuiltInBook('', bookUrl, title, author, ''));
  }
  return out;
}

class SuixkanClass implements IBuiltInSource {
  readonly id: string = 'suixkan_m';
  readonly name: string = '随心看';
  readonly url: string = BASE;
  readonly desc: string = '文本小说源\n来源：m.suixkan.com';
  readonly searchable: boolean = true;
  readonly sourceType: number = 0;

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const p = page <= 1 ? 1 : page;
    const url = `${BASE}/s/${p}.html?keyword=${encodeURIComponent(keywords)}`;
    try {
      const doc = await fetchDoc(url, Opts.withHeaders(sxHeaders()));
      return new BuiltInSearchResult(parseSearchBooks(doc), 1);
    } catch (e) {
      console.error(`[Suixkan] search failed: ${e}`);
      return new BuiltInSearchResult([], 1);
    }
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    return [];
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    return new BuiltInCategory([], 1, 1, normalizeUrl(url), '');
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    const full = normalizeUrl(bookUrl);
    try {
      const doc = await fetchDoc(full, Opts.withHeaders(sxHeaders()));
      const intro = firstText(doc, '.content-intro');
      if (!loadEpisodes) {
        return new BuiltInBookDetail([], intro);
      }
      // 详情页 /b/<id>.html → 目录页 /c/<id>.html
      const m = full.match(/\/b\/(\d+)\.html/);
      const tocUrl = m ? `${BASE}/c/${m[1]}.html` : full;
      const tocDoc = await fetchDoc(tocUrl, Opts.withHeaders(sxHeaders()));
      const episodes: BuiltInEpisode[] = [];
      const seen = new Set<string>();
      const catalogs = tocDoc.select('.catalog_ls');
      for (const cat of catalogs) {
        const links = cat.select('a');
        for (const a of links) {
          const url = a.absUrl('href');
          const title = a.text().trim();
          if (!title || !url || seen.has(url)) continue;
          // 只要章节阅读页 /r/...,过滤目录页其它链接
          if (url.indexOf('/r/') < 0) continue;
          seen.add(url);
          episodes.push(new BuiltInEpisode(title, url, true));
        }
      }
      return new BuiltInBookDetail(episodes, intro);
    } catch (e) {
      console.error(`[Suixkan] detail failed: ${e}`);
      return new BuiltInBookDetail([], '');
    }
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    return chapterUrl;
  }

  async getTextContent(chapterUrl: string, _nextChapterUrl?: string): Promise<string> {
    const full = normalizeUrl(chapterUrl);
    try {
      const doc = await fetchDoc(full, Opts.withHeaders(sxHeaders()));
      const ps = doc.select('p');
      const out: string[] = [];
      for (const p of ps) {
        const t = p.text().trim();
        if (!t) continue;
        // 跳过站点导航条(同时含"女频""男频"是顶部导航,正文绝不会)
        if (t.indexOf('女频') >= 0 && t.indexOf('男频') >= 0) continue;
        // 跳过短控件类页脚(上一章/下一章/目录/书架/报错/书签)
        if (t.length <= 12 && (t.indexOf('上一章') >= 0 || t.indexOf('下一章') >= 0 ||
          t.indexOf('目录') >= 0 || t.indexOf('书架') >= 0 || t.indexOf('报错') >= 0 ||
          t.indexOf('书签') >= 0 || t.indexOf('首页') >= 0)) {
          continue;
        }
        out.push(t);
      }
      return out.join('\n');
    } catch (e) {
      console.error(`[Suixkan] content failed: ${e}`);
      return '';
    }
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    return sxHeaders();
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    return [];
  }
}

export const Suixkan: IBuiltInSource = new SuixkanClass();
