/**
 * 简·欢云源 - 服务端聚合音频源。
 *
 * App 只消费稳定的搜索、详情、章节和播放解析接口；阅读音频规则在服务器执行。
 * 欢 FM 仍由原实现独立直连，两者没有协议依赖。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BuiltInBook, BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu,
  BuiltInEpisode, BuiltInSearchResult, HomeBlock, IBuiltInSource
} from '../IBuiltInSource';
import { JsonArr, JsonObj } from '../JsonValue';
import { HttpClient } from '../../http/HttpClient';
import { ServerAudioConfig } from '../ServerAudioConfig';

const DOMAIN = 0x0000;
const TAG = 'ServerAudioSource';
const CHAPTER_SCHEME = 'jianhu://audio-chapter/';
const REQUEST_TIMEOUT_MS = 15000;

function apiHeaders(): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['Accept'] = 'application/json';
  return headers;
}

class ServerAudioSourceClass implements IBuiltInSource {
  readonly id: string = 'jianhu_server';
  readonly name: string = '简·欢云源';
  get url(): string {
    return ServerAudioConfig.peekApiBase();
  }
  readonly desc: string = '服务端聚合音频源；来源可在简·欢源控制台集中维护';
  readonly searchable: boolean = true;
  readonly audioResolveTimeoutMs: number = 40000;

  private audioHeadersByUrl: Map<string, Record<string, string>> = new Map();

  private async request(path: string, method: string = 'GET'): Promise<JsonObj> {
    const apiBase = await ServerAudioConfig.getApiBase();
    const response = await HttpClient.request(apiBase + path, {
      method,
      headers: apiHeaders(),
      timeout: REQUEST_TIMEOUT_MS,
      retry: 1
    });
    if (!response.body) {
      throw new Error(`云源响应为空: HTTP ${response.statusCode}`);
    }
    const root = new JsonObj(JSON.parse(response.body) as Object);
    const code = root.getString('code', 'INVALID_RESPONSE');
    if (response.statusCode < 200 || response.statusCode >= 300 || code !== 'OK') {
      throw new Error(`云源请求失败: ${code}`);
    }
    return root;
  }

  private toBook(value: JsonObj): BuiltInBook | null {
    const id = value.getString('id', '');
    const title = value.getString('title', '');
    if (!id || !title) return null;
    const narrator = value.getString('narrator', '');
    const author = value.getString('author', '') || narrator;
    const book = new BuiltInBook(value.getString('cover', ''), id, title, author, narrator);
    book.intro = value.getString('intro', '');
    book.status = value.getString('category', '');
    book.sourceName = value.getString('sourceName', '');
    return book;
  }

  private toBooks(values: JsonArr): BuiltInBook[] {
    const books: BuiltInBook[] = [];
    for (let i = 0; i < values.length(); i++) {
      const book = this.toBook(values.getObj(i));
      if (book) books.push(book);
    }
    return books;
  }

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const safePage = Math.max(1, page);
    const root = await this.request(`/audio-books/search?q=${encodeURIComponent(keywords)}&page=${safePage}`);
    const books = this.toBooks(root.getObj('data').getArr('items'));
    return new BuiltInSearchResult(books, books.length > 0 ? safePage + 1 : safePage);
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean,
    _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    const bookId = bookUrl.trim();
    if (!bookId) return new BuiltInBookDetail();
    if (!loadEpisodes) {
      const root = await this.request(`/audio-books/${encodeURIComponent(bookId)}`);
      return new BuiltInBookDetail([], root.getObj('data').getString('intro', ''));
    }

    const root = await this.request(`/audio-books/${encodeURIComponent(bookId)}/chapters`);
    const values = root.getArr('data');
    const episodes: BuiltInEpisode[] = [];
    for (let i = 0; i < values.length(); i++) {
      const chapter = values.getObj(i);
      const chapterId = chapter.getString('id', '');
      if (!chapterId) continue;
      const title = chapter.getString('title', '') || `第${i + 1}集`;
      const duration = Math.max(0, chapter.getInt('duration', 0));
      const episode = new BuiltInEpisode(title, CHAPTER_SCHEME + chapterId, true);
      episode.duration = duration;
      episodes.push(episode);
    }
    return new BuiltInBookDetail(episodes, '');
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    if (!chapterUrl.startsWith(CHAPTER_SCHEME)) return chapterUrl;
    const chapterId = chapterUrl.substring(CHAPTER_SCHEME.length).trim();
    if (!chapterId) throw new Error('云源章节标识为空');
    const root = await this.request(`/audio-chapters/${encodeURIComponent(chapterId)}/resolve`, 'POST');
    const data = root.getObj('data');
    const audioUrl = data.getString('url', '');
    if (!audioUrl.startsWith('http://') && !audioUrl.startsWith('https://')) {
      throw new Error('云源未返回有效音频地址');
    }

    const headers: Record<string, string> = {};
    const rawHeaders = data.getObj('headers').raw;
    for (const key of Object.keys(rawHeaders)) {
      const value = rawHeaders[key];
      if (value !== undefined && value !== null) headers[key] = String(value);
    }
    this.rememberAudioHeaders(audioUrl, headers);
    return audioUrl;
  }

  getAudioHeaders(audioUrl: string): Record<string, string> {
    return this.audioHeadersByUrl.get(audioUrl) ?? {};
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

  private rememberAudioHeaders(audioUrl: string, headers: Record<string, string>): void {
    this.audioHeadersByUrl.set(audioUrl, headers);
    if (this.audioHeadersByUrl.size <= 100) return;
    const oldest = this.audioHeadersByUrl.keys().next();
    if (!oldest.done && oldest.value !== undefined) {
      this.audioHeadersByUrl.delete(oldest.value as string);
    }
    hilog.debug(DOMAIN, TAG, 'trimmed resolved audio header cache');
  }
}

export const ServerAudioSource: IBuiltInSource = new ServerAudioSourceClass();
