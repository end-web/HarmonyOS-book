/**
 * Maoyan - 猫眼看书（优++）内置源（加密 API 客户端，文本电子书）
 *
 * 移植自用户提供的 Legado 书源「猫眼看书（优++）」。该源不是 HTML 爬取，而是加密 API：
 *  - 动态域名 api.<domain>.com（内置一批，逐个探活，跳过限频/失效）
 *  - 鉴权头：client-device = md5(aesKey)，Authorization = 内置 JWT（按 uType 选 key/jwt）
 *  - 列表/详情接口返回 { code, data }，正文接口返回 { code, content }
 *  - 章节 path 为 AES/CBC/PKCS7 密文（key=aesKey ASCII，iv="0123456789abcdef"），
 *    解密得 "http://api.x.com/realpath"，去掉域名前缀即真实正文路径
 *
 * 对照实现见 .claude/skills/run-book-source（Node harness，已实站验证：搜"深空彼岸"→1455 章→正文）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import {
  IBuiltInSource, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInSearchResult, BuiltInBook, BuiltInEpisode, HomeBlock
} from '../IBuiltInSource';
import { fetchJson, Opts, JsonObj, JsonArr } from '../BuiltInContext';
import { getJavaBridge } from '../../rule/JavaBridge';

const DBG = 0x9528;
const DT = 'MaoyanDbg';
const IV = '0123456789abcdef';
const DOMAIN_RE = /^https?:\/\/api\.[^/]+\.com/i;

/** uType=0 旧 aes，uType=1 新 aes */
const AES_KEY: string[] = ['f041c49714d39908', '4395daa50ad6baf7'];
const AUTH: string[] = [
  'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkubXl3ZWlwaW4uY29tXC9hdXRoXC90aGlyZCIsImlhdCI6MTcwNjg0NjM2NiwiZXhwIjoxODAwMTU4MzY2LCJuYmYiOjE3MDY4NDYzNjYsImp0aSI6IjRVbU5BZVpHQ1hvaGNpSEgiLCJzdWIiOjc3MDg5OSwicHJ2IjoiYTFjYjAzNzE4MDI5NmM2YTE5MzhlZjMwYjQzNzk0NjcyZGQwMTZjNSJ9.lOpKG-vWne5Ub8g6byvF53iQjldPUC1-BMoO-OuhOlA',
  'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkueGluZ2xpYW5nZ2xvYmFsLmNvbVwvYXV0aFwvdGhpcmQiLCJpYXQiOjE3MDY4NjA2NzcsImV4cCI6MTgwMDE3MjY3NywibmJmIjoxNzA2ODYwNjc3LCJqdGkiOiJxdXBGbWo5cnJRMHFoTFVIIiwic3ViIjozMjY4ODcsInBydiI6ImExY2IwMzcxODAyOTZjNmExOTM4ZWYzMGI0Mzc5NDY3MmRkMDE2YzUifQ.CQsDsiDJyyriPmJuT6A38KIvGgq6BEOMWl8H5plqArQ',
];

class Dom {
  host: string;
  uType: number;
  constructor(name: string, uType: number) {
    this.host = `http://api.${name}.com`;
    this.uType = uType;
  }
}

const DOMAINS: Dom[] = [
  new Dom('longchunbajiao', 0), new Dom('yybhsl', 0), new Dom('wzyjxf', 0), new Dom('zjlzgg', 0),
  new Dom('sxwlyhzp', 0), new Dom('anwaben', 0), new Dom('basusan', 0), new Dom('myweipin', 0),
  new Dom('lemiyigou', 0),
  new Dom('xingliangglobal', 1), new Dom('fangweicong', 1), new Dom('yuanxifayi', 1), new Dom('xqjcool', 1),
];

/** 上次成功的域名下标，下次从它开始（少撞限频/失效域） */
let lastGood = 0;

class PickResult {
  json: JsonObj;
  host: string;
  aesKey: string;
  constructor(json: JsonObj, host: string, aesKey: string) {
    this.json = json;
    this.host = host;
    this.aesKey = aesKey;
  }
}

function headersFor(uType: number): Record<string, string> {
  const h: Record<string, string> = {};
  h['client-device'] = getJavaBridge().md5Encode(AES_KEY[uType]);
  h['Authorization'] = AUTH[uType];
  h['client-version'] = '2.3.0';
  h['client-brand'] = 'HONOR';
  h['client-source'] = 'android';
  h['client-name'] = 'app.maoyankanshu.novel';
  h['User-Agent'] = 'okhttp/4.9.2';
  return h;
}

/** 逐个域名请求 path，返回首个 code==200 的响应（含 host 与 aesKey） */
async function pick(path: string): Promise<PickResult | null> {
  for (let n = 0; n < DOMAINS.length; n++) {
    const i = (lastGood + n) % DOMAINS.length;
    const d = DOMAINS[i];
    try {
      const json = await fetchJson(d.host + path, Opts.withHeaders(headersFor(d.uType)));
      const code = json.getInt('code', -1);
      if (code === 200) {
        lastGood = i;
        return new PickResult(json, d.host, AES_KEY[d.uType]);
      }
      // 4011 请勿频繁 / 其它 → 换下一个域名
    } catch (e) {
      // 域名失效/超时/非 JSON → 换下一个
    }
  }
  hilog.error(DBG, DT, 'pick all domains failed: %{public}s', path);
  return null;
}

/* ─────────── AES/CBC/PKCS7 解密（key/iv 为 ASCII 字节） ─────────── */

function strBytes(s: string): Uint8Array {
  const b = buffer.from(s, 'utf-8');
  const u = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) u[i] = b[i];
  return u;
}
function b64Bytes(s: string): Uint8Array {
  const b = buffer.from(s, 'base64');
  const u = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) u[i] = b[i];
  return u;
}
function bytesToStr(u: Uint8Array): string {
  return buffer.from(u).toString('utf-8');
}

async function aesDecryptStr(cipherB64: string, keyStr: string): Promise<string> {
  const gen = cryptoFramework.createSymKeyGenerator('AES128');
  const keyBlob: cryptoFramework.DataBlob = { data: strBytes(keyStr) };
  const symKey = await gen.convertKey(keyBlob);
  const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
  const ivSpec: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: strBytes(IV) } };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivSpec);
  const input: cryptoFramework.DataBlob = { data: b64Bytes(cipherB64) };
  const out = await cipher.doFinal(input);
  return bytesToStr(out.data);
}

/* ─────────── 工具 ─────────── */

function novelIdOf(bookUrl: string): string {
  const m = bookUrl.match(/\/novel\/([^/?#]+)/);
  return m ? m[1] : bookUrl.replace(/^\/+/, '');
}

class MaoyanClass implements IBuiltInSource {
  readonly id: string = 'maoyankanshu';
  readonly name: string = '猫眼看书';
  readonly url: string = 'http://download.yichnmedia.com';
  readonly desc: string = '文本小说源 · 加密 API\n来源：猫眼看书（优++）';
  readonly searchable: boolean = true;
  readonly sourceType: number = 0;

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const p = page <= 1 ? 1 : page;
    const path = `/search?keyword=${encodeURIComponent(keywords)}&page=${p}`;
    const res = await pick(path);
    if (!res) return new BuiltInSearchResult([], 1);
    const arr: JsonArr = res.json.getArr('data');
    const books: BuiltInBook[] = [];
    for (let i = 0; i < arr.length(); i++) {
      const o: JsonObj = arr.getObj(i);
      const novelId = o.getString('novelId');
      if (!novelId) continue;
      const title = o.getString('novelName');
      const author = o.getString('authorName');
      let cover = o.getString('cover');
      if (cover) cover = cover.replace(DOMAIN_RE, res.host);
      const book = new BuiltInBook(cover, `/novel/${novelId}`, title, author, '');
      book.intro = o.getString('summary');
      books.push(book);
    }
    hilog.info(DBG, DT, 'search [%{public}s] -> %{public}d', keywords, books.length);
    return new BuiltInSearchResult(books, 1);
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    const novelId = novelIdOf(bookUrl);
    // 详情
    let intro = '';
    const detail = await pick(`/novel/${novelId}`);
    if (detail) intro = detail.json.getObj('data').getString('summary');
    if (!loadEpisodes) return new BuiltInBookDetail([], intro);

    // 目录（章节 path 为 AES 密文，需解密）
    const res = await pick(`/novel/${novelId}/chapters`);
    if (!res) return new BuiltInBookDetail([], intro);
    const list: JsonArr = res.json.getObj('data').getArr('list');
    const episodes: BuiltInEpisode[] = [];
    for (let i = 0; i < list.length(); i++) {
      const o: JsonObj = list.getObj(i);
      const name = o.getString('chapterName');
      const enc = o.getString('path');
      if (!enc) continue;
      let realPath = '';
      try {
        const dec = await aesDecryptStr(enc, res.aesKey);
        realPath = dec.replace(DOMAIN_RE, '');
      } catch (e) {
        hilog.error(DBG, DT, 'decrypt fail ch=%{public}s err=%{public}s', name, (e as Error).message ?? '');
        continue;
      }
      if (realPath) episodes.push(new BuiltInEpisode(name, realPath, true));
    }
    hilog.info(DBG, DT, 'toc %{public}s -> %{public}d', novelId, episodes.length);
    return new BuiltInBookDetail(episodes, intro);
  }

  async getTextContent(chapterUrl: string, _nextChapterUrl?: string): Promise<string> {
    // 正文是静态 JSON 文件（如 /655/655791/70398.json），只有 content 字段、无 code，
    // 故逐域名取数、只要拿到非空 content 即可（不能用 code==200 网关）。
    for (let n = 0; n < DOMAINS.length; n++) {
      const i = (lastGood + n) % DOMAINS.length;
      const d = DOMAINS[i];
      try {
        const json = await fetchJson(d.host + chapterUrl, Opts.withHeaders(headersFor(d.uType)));
        let c = json.getString('content');
        if (!c) c = json.getObj('data').getString('content');
        if (c) { lastGood = i; return c; }
      } catch (e) {
        // 该域名失效/非 JSON → 换下一个
      }
    }
    hilog.error(DBG, DT, 'content empty: %{public}s', chapterUrl);
    return '';
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

export const Maoyan: IBuiltInSource = new MaoyanClass();
