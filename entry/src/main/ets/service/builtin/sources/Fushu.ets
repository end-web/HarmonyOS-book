/**
 * Fushu - 福书网[分页] (https://www.fushucun.com) 内置源（文本电子书）
 *
 * 移植自用户提供的 Legado 书源「🔥 福书网[分页]」。福书村是帝国CMS(EmpireCMS)耽美/言情站，
 * 特点：
 *  - 搜索是 GBK + POST 到 /e/search/index.php（keyboard 需按 GBK percent-encode）
 *  - 详情页用 <select name="titleselect"> 列出本书的"分页"，每页当一个章节（[分页]）
 *  - 正文在 <td id="text"> … <p align="center"> 之间
 *
 * 对照实现见 .claude/skills/run-book-source（Node harness，已实站验证：搜"掉马"→详情→分页→正文）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock
} from '../IBuiltInSource';
import { fetchText, FetchOptions, JsoupUtil, encodeUri } from '../BuiltInContext';

const BASE = 'https://www.fushucun.com';
const DBG = 0x9529;
const DT = 'FushuDbg2';

function searchOptions(keywords: string): FetchOptions {
  const o = new FetchOptions();
  o.method = 'POST';
  o.charset = 'gbk';
  // keyboard 必须按 GBK percent-encode；show=title 仅按书名搜
  o.body = `keyboard=${encodeUri(keywords, 'gbk')}&show=title&classid=`;
  return o;
}

/** 从 <td id="text"> … <p align="center"> 截取正文 HTML（退化用 </td>） */
function extractContentHtml(html: string): string {
  let m = html.match(/<td id="text">([\s\S]*?)<p align="center"/i);
  if (!m) m = html.match(/<td id="text">([\s\S]*?)<\/td>/i);
  return m ? m[1] : '';
}

/** HTML 片段 → 纯文本（保留段落换行） */
function htmlToText(html: string): string {
  let s = html;
  s = s.replace(/<br\s*\/?>(\s*)/gi, '\n');
  s = s.replace(/<\/(p|div|li|tr|h\d)>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = s.replace(/&nbsp;|&#160;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'")
    .replace(/&mdash;/gi, '——').replace(/&ldquo;/gi, '“').replace(/&rdquo;/gi, '”');
  // 清理：去掉「《书名》作者…」「文案：」「简介：」等行（对应 legado replaceRegex）
  s = s.replace(/.*》作者.*/g, '').replace(/[\t ]*文案：/g, '').replace(/[\t ]*简介：/g, '');
  s = s.replace(/\n{3,}/g, '\n\n').replace(/[\t ]+\n/g, '\n').trim();
  return s;
}

class FushuClass implements IBuiltInSource {
  readonly id: string = 'fushucun';
  readonly name: string = '福书网[分页]';
  readonly url: string = BASE;
  readonly desc: string = '文本小说源 · 耽美/言情\n来源：www.fushucun.com（GBK/分页）';
  readonly searchable: boolean = true;
  readonly sourceType: number = 0;

  async search(keywords: string, _page: number): Promise<BuiltInSearchResult> {
    try {
      const html = await fetchText(`${BASE}/e/search/index.php`, searchOptions(keywords));
      const doc = JsoupUtil.parse(html, BASE);
      const lis = doc.select('.article-list li');
      const books: BuiltInBook[] = [];
      const seen = new Set<string>();
      for (const li of lis) {
        const a = li.selectFirst('a');
        if (!a) continue;
        const bookUrl = a.absUrl('href');
        const title = a.attr('title') || a.text().trim();
        if (!bookUrl || !title || seen.has(bookUrl)) continue;
        seen.add(bookUrl);
        // title 形如 "书名（分类）——作者"
        const parts = title.split('——');
        const name = parts[0].trim();
        const author = parts.length > 1 ? parts[1].trim() : '';
        const kindEl = li.selectFirst('span');
        const book = new BuiltInBook('', bookUrl, name, author, '');
        book.intro = kindEl ? kindEl.text().trim() : '';
        books.push(book);
      }
      hilog.info(DBG, DT, 'search [%{public}s] -> %{public}d', keywords, books.length);
      return new BuiltInSearchResult(books, 1);
    } catch (e) {
      hilog.error(DBG, DT, 'search FAILED=%{public}s', (e as Error).message ?? JSON.stringify(e));
      return new BuiltInSearchResult([], 1);
    }
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    try {
      const html = await fetchText(bookUrl, new FetchOptions());
      const doc = JsoupUtil.parse(html, BASE);
      // 简介：#text 区域文本（尽力而为）
      let intro = '';
      const introEl = doc.selectFirst('#text');
      if (introEl) {
        const t = introEl.text().trim();
        intro = t.length > 400 ? t.substring(0, 400) : t;
      }
      if (!loadEpisodes) return new BuiltInBookDetail([], intro);

      // 目录 = <select name="titleselect"> 的每个 <option>（每页一个"章节"）
      const options = doc.select('select[name="titleselect"] option');
      const episodes: BuiltInEpisode[] = [];
      const seen = new Set<string>();
      for (let i = 0; i < options.length; i++) {
        const op = options[i];
        const url = op.absUrl('value') || op.attr('value');
        if (!url || seen.has(url)) continue;
        seen.add(url);
        const text = op.text().trim();
        const pm = text.match(/\((\d+)\)\s*$/);
        const name = pm ? `第${pm[1]}页` : (i === 0 ? '第1页' : text);
        episodes.push(new BuiltInEpisode(name, url, true));
      }
      hilog.info(DBG, DT, 'toc %{public}s -> %{public}d', bookUrl, episodes.length);
      return new BuiltInBookDetail(episodes, intro);
    } catch (e) {
      hilog.error(DBG, DT, 'detail FAILED=%{public}s', (e as Error).message ?? JSON.stringify(e));
      return new BuiltInBookDetail([], '');
    }
  }

  async getTextContent(chapterUrl: string, _nextChapterUrl?: string): Promise<string> {
    try {
      const html = await fetchText(chapterUrl, new FetchOptions());
      const block = extractContentHtml(html);
      const text = htmlToText(block);
      if (!text) hilog.error(DBG, DT, 'content empty: %{public}s', chapterUrl);
      return text;
    } catch (e) {
      hilog.error(DBG, DT, 'content FAILED=%{public}s', (e as Error).message ?? JSON.stringify(e));
      return '';
    }
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    return chapterUrl;
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    return {};
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    return [];
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    return new BuiltInCategory([], 1, 1, url, '');
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    return [];
  }
}

export const Fushu: IBuiltInSource = new FushuClass();
