/**
 * TingYouFM - 听友FM (https://www.tingyou.fm)
 *
 * Nuxt SPA + 加密 API（协议见 TingYouCrypto / reference_tingyou_fm_protocol 记忆）：
 * - 静态 GET（CDN，无需鉴权）：album_info/<id>、album_chapters/<id>、homepage
 * - 动态 POST（www.tingyou.fm/api/，需 guest Bearer token）：search、play_token
 * - guest token：先试原生 POST /api/me；被 bot 拦时用隐藏 WebView 读 localStorage.auth
 * - 响应 XChaCha20 解密 / 请求 AES-GCM 加密，统一走 TingYouCrypto
 * - 音频：play_token 返回的 play_url 是无 DRM 的签名 M4A，AVPlayer 直接可播
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInCategoryTab, BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock
} from '../IBuiltInSource';
import { HttpClient } from '../../http/HttpClient';
import { JsonObj, JsonArr } from '../BuiltInContext';
import { TingYouCrypto } from '../TingYouCrypto';
import { getWebViewAudioExtractor } from '../WebViewAudioExtractor';

const TAG = 'TingYouFM';
const SITE = 'https://www.tingyou.fm';
const API = SITE + '/api';
/** 静态 JSON CDN（三镜像，依次兜底） */
const CDN_BASES: string[] = [
  'https://json.tingyou8.vip/tyfm/json_v1',
  'https://json.hgeuz.cn/tyfm/json_v1',
  'https://json.fmfm.pro/tyfm/json_v1',
];
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
/** 章节播放标识：tingyou://play/<albumId>/<chapterIdx> */
const PLAY_SCHEME = 'tingyou://play/';

function baseHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  h['User-Agent'] = UA;
  h['Referer'] = SITE + '/';
  h['Origin'] = SITE;
  return h;
}

/** 把接口里的一本书 JsonObj 映射成 BuiltInBook */
function jsonToBook(o: JsonObj): BuiltInBook | null {
  const id = o.getString('id', '');
  if (!id) return null;
  const cover = o.getString('cover_url', '');
  const title = o.getString('title', '');
  let author = o.getString('author', '');
  const teller = o.getString('teller', '');
  if (!author) author = teller;
  const b = new BuiltInBook(cover, id, title, author, teller);
  b.intro = o.getString('description', '') || o.getString('synopsis', '');
  b.status = o.getString('type', '');
  b.completed = o.getInt('status', 0) === 1;
  return b;
}

function parseBookArray(arr: JsonArr): BuiltInBook[] {
  const out: BuiltInBook[] = [];
  for (let i = 0; i < arr.length(); i++) {
    const b = jsonToBook(arr.getObj(i));
    if (b) out.push(b);
  }
  return out;
}

class TingYouFMClass implements IBuiltInSource {
  readonly id: string = 'tingyou_fm';
  readonly name: string = '听友FM';
  readonly url: string = SITE;
  readonly desc: string = '推荐指数:5星 ⭐⭐⭐⭐⭐\n来源：www.tingyou.fm';
  readonly searchable: boolean = true;
  readonly sourceType: number = 1;

  /** guest 会话 token（不含 "Bearer " 前缀） */
  private token: string = '';

  /* ─────────────── token 与 API 基础设施 ─────────────── */

  /** 获取 guest token：内存缓存 → 原生 /api/me → WebView 读 localStorage */
  private async ensureToken(force: boolean): Promise<string> {
    if (this.token && !force) return this.token;
    this.token = '';

    // 1) 原生 POST /api/me（空 body）
    try {
      const headers = baseHeaders();
      headers['X-Payload-Version'] = '1';
      const r = await HttpClient.request(`${API}/me`, { method: 'POST', headers, timeout: 15000 });
      if (r.statusCode === 200 && r.body) {
        const j = new JsonObj(JSON.parse(r.body) as Object);
        const payload = j.getString('payload', '');
        if (payload) {
          const dec = new JsonObj(JSON.parse(TingYouCrypto.decryptResponse(payload)) as Object);
          const t = dec.getString('auth_token', '');
          if (t) {
            this.token = t.replace(/^Bearer\s+/i, '');
            hilog.info(0, TAG, 'token via native /api/me');
            return this.token;
          }
        }
      }
    } catch (e) {
      hilog.warn(0, TAG, 'native /api/me failed: %{public}s', e instanceof Error ? e.message : String(e));
    }

    // 2) WebView 兜底：加载站点，读 localStorage.auth.authToken
    try {
      const expr = 'JSON.parse(localStorage.getItem("auth")||"{}").authToken||""';
      const v = await getWebViewAudioExtractor().extract(SITE + '/', expr, 3500);
      if (v) {
        this.token = v.replace(/^Bearer\s+/i, '');
        hilog.info(0, TAG, 'token via WebView');
        return this.token;
      }
    } catch (e) {
      hilog.warn(0, TAG, 'WebView token failed: %{public}s', e instanceof Error ? e.message : String(e));
    }
    return '';
  }

  /** 动态加密 POST：自动带 token，401 时刷新一次重试。bodyJson 为已序列化的 JSON 字符串 */
  private async apiPost(endpoint: string, bodyJson: string): Promise<JsonObj | null> {
    let token = await this.ensureToken(false);
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const hexBody = await TingYouCrypto.encryptRequest(bodyJson);
        const headers = baseHeaders();
        headers['X-Payload-Version'] = '1';
        headers['Content-Type'] = 'text/plain';
        if (token) headers['Authorization'] = 'Bearer ' + token;
        const r = await HttpClient.request(`${API}/${endpoint}`, { method: 'POST', headers, body: hexBody, timeout: 15000 });
        if (r.statusCode === 401) {
          token = await this.ensureToken(true);
          if (!token) return null;
          continue;
        }
        if (r.statusCode === 200 && r.body) {
          const j = new JsonObj(JSON.parse(r.body) as Object);
          const payload = j.getString('payload', '');
          if (payload) return new JsonObj(JSON.parse(TingYouCrypto.decryptResponse(payload)) as Object);
          return j;
        }
        return null;
      } catch (e) {
        hilog.error(0, TAG, 'apiPost %{public}s failed: %{public}s', endpoint, e instanceof Error ? e.message : String(e));
        return null;
      }
    }
    return null;
  }

  /** 静态加密 GET（CDN 镜像兜底）：返回解密后的 JsonObj */
  private async cdnGet(path: string): Promise<JsonObj | null> {
    for (const base of CDN_BASES) {
      try {
        const r = await HttpClient.request(`${base}/${path}`, { method: 'GET', headers: baseHeaders(), timeout: 15000 });
        if (r.statusCode === 200 && r.body) {
          const j = new JsonObj(JSON.parse(r.body) as Object);
          const payload = j.getString('payload', '');
          if (payload) return new JsonObj(JSON.parse(TingYouCrypto.decryptResponse(payload)) as Object);
        }
      } catch (e) {
        hilog.warn(0, TAG, 'cdnGet %{public}s @ %{public}s failed: %{public}s', path, base, e instanceof Error ? e.message : String(e));
      }
    }
    return null;
  }

  /* ─────────────── IBuiltInSource ─────────────── */

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const p = page < 1 ? 1 : page;
    const bodyJson = `{"keyword":${JSON.stringify(keywords)},"page":${p}}`;
    const obj = await this.apiPost('search', bodyJson);
    if (!obj) return new BuiltInSearchResult([], 1);
    const books = parseBookArray(obj.getArr('results'));
    const hasMore = obj.getInt('has_more', 0) === 1;
    return new BuiltInSearchResult(books, hasMore ? page + 1 : page);
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _full: boolean): Promise<BuiltInBookDetail> {
    const albumId = bookUrl.trim();
    if (!loadEpisodes) {
      const info = await this.cdnGet(`album_info/${albumId}`);
      const intro = info ? (info.getString('synopsis', '') || info.getString('description', '')) : '';
      return new BuiltInBookDetail([], intro);
    }
    // 章节列表
    const data = await this.cdnGet(`album_chapters/${albumId}`);
    if (!data) return new BuiltInBookDetail([], '');
    const chapters = data.getArr('chapters');
    const episodes: BuiltInEpisode[] = [];
    for (let i = 0; i < chapters.length(); i++) {
      const c = chapters.getObj(i);
      const idx = c.getInt('index', i + 1);
      const title = c.getString('title', '') || `第${idx}集`;
      episodes.push(new BuiltInEpisode(title, `${PLAY_SCHEME}${albumId}/${idx}`));
    }
    return new BuiltInBookDetail(episodes, '');
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    // tingyou://play/<albumId>/<chapterIdx>
    if (chapterUrl.indexOf(PLAY_SCHEME) !== 0) return chapterUrl;
    const rest = chapterUrl.substring(PLAY_SCHEME.length);
    const slash = rest.lastIndexOf('/');
    if (slash <= 0) return chapterUrl;
    const albumId = Number(rest.substring(0, slash));
    const chapterIdx = Number(rest.substring(slash + 1));
    if (!albumId || !chapterIdx) return chapterUrl;
    const bodyJson = `{"album_id":${albumId},"chapter_idx":${chapterIdx}}`;
    const obj = await this.apiPost('play_token', bodyJson);
    const url = obj ? obj.getString('play_url', '') : '';
    return url || chapterUrl;
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = UA;
    h['Referer'] = SITE + '/';
    return h;
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    const data = await this.cdnGet('homepage');
    if (!data) return [];
    const blocks: HomeBlock[] = [];
    const recommends = parseBookArray(data.getArr('recommends'));
    if (recommends.length > 0) blocks.push(new HomeBlock('精品推荐', recommends, '', 'grid'));
    const recent = parseBookArray(data.getArr('recent_updates'));
    if (recent.length > 0) blocks.push(new HomeBlock('最近更新', recent, '', 'horizontal'));
    return blocks;
  }

  /**
   * 分类菜单（来自站点 filters：有声小说 / 评书 两组，每组若干 type）。
   * tab.url = `types/<typeId>/comprehensive/p1`（与站点分类浏览一致）。
   */
  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    const data = await this.cdnGet('filters');
    if (!data) return [];
    const cats = data.getArr('categories');
    const menus: BuiltInCategoryMenu[] = [];
    for (let i = 0; i < cats.length(); i++) {
      const c = cats.getObj(i);
      const groupName = c.getString('name', '');
      const types = c.getArr('types');
      const tabs: BuiltInCategoryTab[] = [];
      for (let j = 0; j < types.length(); j++) {
        const t = types.getObj(j);
        const tid = t.getString('id', '');
        const tname = t.getString('name', '');
        if (tid && tname) tabs.push(new BuiltInCategoryTab(tname, `types/${tid}/comprehensive/p1`));
      }
      if (tabs.length > 0) menus.push(new BuiltInCategoryMenu(groupName, tabs));
    }
    return menus;
  }

  /**
   * 分类书单。url 形如 `types/<typeId>/comprehensive/p<N>`（也兼容只传 typeId）。
   * 返回 nextUrl 指向下一页，供上层循环加载。
   */
  async getCategoryList(url: string): Promise<BuiltInCategory> {
    const path = url.indexOf('types/') === 0 ? url : `types/${url}/comprehensive/p1`;
    const data = await this.cdnGet(path);
    if (!data) return new BuiltInCategory([], 1, 1, url, '');
    const books = parseBookArray(data.getArr('data'));
    const page = data.getInt('page', 1);
    const pages = data.getInt('pages', 1);
    const nextUrl = page < pages ? path.replace(/p\d+$/, `p${page + 1}`) : '';
    return new BuiltInCategory(books, page, pages, url, nextUrl);
  }
}

export const TingYouFM: IBuiltInSource = new TingYouFMClass();
