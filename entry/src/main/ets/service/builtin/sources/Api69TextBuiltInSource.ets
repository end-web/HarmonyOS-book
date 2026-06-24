/**
 * Api69TextBuiltInSource - 69书吧文本源（IBuiltInSource 实现）
 *
 * 通过 SourceEngine 调用 JSON 配置源，适配为 IBuiltInSource 接口
 */

import { IBuiltInSource, BuiltInBook, BuiltInSearchResult, BuiltInBookDetail, BuiltInEpisode, BuiltInCategoryMenu, BuiltInCategory, HomeBlock, CatBuilder } from '../IBuiltInSource';
import { SourceRegistry } from '../../source/SourceRegistry';
import { SourceEngine } from '../../source/SourceEngine';

export class Api69TextBuiltInSource implements IBuiltInSource {
  readonly id: string = 'api69_text';
  readonly name: string = '69书吧 APP API';
  readonly url: string = 'https://app.novelapis.com';
  readonly desc: string = '文本源。基于 APP JSON API。';
  readonly searchable: boolean = true;
  readonly sourceType: number = 0; // 文本源

  private getEngine(): SourceEngine {
    const engine = SourceRegistry.getEngine(this.id);
    if (!engine) throw new Error(`源引擎未注册: ${this.id}`);
    return engine;
  }

  async search(keywords: string, page: number): Promise<BuiltInSearchResult> {
    const engine = this.getEngine();
    return await engine.search(keywords, page);
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    const engine = this.getEngine();
    const def = engine.getDefinition();

    if (!def.category?.menus) return [];

    const menus: BuiltInCategoryMenu[] = [];
    for (const menu of def.category.menus) {
      const tabs = menu.tabs.map(t => [t.title, t.url]);
      menus.push(CatBuilder.menu(menu.title, tabs));
    }
    return menus;
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    const engine = this.getEngine();
    return await engine.getCategoryList(url);
  }

  async getBookDetail(bookUrl: string, loadEpisodes: boolean, loadFullPages: boolean): Promise<BuiltInBookDetail> {
    const engine = this.getEngine();
    return await engine.getBookDetail(bookUrl, loadEpisodes, loadFullPages);
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    throw new Error('文本源不支持获取音频URL');
  }

  async getTextContent(chapterUrl: string, nextChapterUrl?: string): Promise<string> {
    const engine = this.getEngine();
    return await engine.getTextContent(chapterUrl, nextChapterUrl);
  }

  getAudioHeaders(audioUrl: string): Record<string, string> {
    return {};
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    const engine = this.getEngine();
    return await engine.getHomeBlocks();
  }
}
