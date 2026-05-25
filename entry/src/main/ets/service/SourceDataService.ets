/**
 * 书源数据服务
 */

import { BookSource, SourceSubscription } from '../model/BookSource';
import { PreferenceService } from './PreferenceService';

export class SourceDataService {
  private static cache: BookSource[] | null = null;

  /**
   * 获取所有书源
   */
  static async getSources(): Promise<BookSource[]> {
    if (SourceDataService.cache) return SourceDataService.cache;

    try {
      const json = await PreferenceService.getBookSources();
      const data: Object = JSON.parse(json) as Object;
      SourceDataService.cache = Array.isArray(data) ? data as BookSource[] : [];
      return SourceDataService.cache;
    } catch {
      return [];
    }
  }

  /**
   * 保存书源列表
   */
  static async saveSources(sources: BookSource[]): Promise<void> {
    await PreferenceService.saveBookSources(JSON.stringify(sources));
    SourceDataService.cache = sources;
  }

  /**
   * 添加书源
   */
  static async addSources(newSources: BookSource[]): Promise<void> {
    const existing = await SourceDataService.getSources();
    const merged = existing.concat(newSources);
    await SourceDataService.saveSources(merged);
  }

  /**
   * 删除书源
   */
  static async removeSource(sourceUrl: string): Promise<void> {
    const existing = await SourceDataService.getSources();
    const filtered = existing.filter((s) => s.bookSourceUrl !== sourceUrl);
    await SourceDataService.saveSources(filtered);
  }

  /**
   * 获取已启用的书源
   */
  static async getEnabledSources(): Promise<BookSource[]> {
    const all = await SourceDataService.getSources();
    return all.filter((s) => s.enabled);
  }

  /**
   * 获取订阅列表
   */
  static async getSubscriptions(): Promise<SourceSubscription[]> {
    try {
      const json = await PreferenceService.getSourceSubscriptions();
      const data: Object = JSON.parse(json) as Object;
      return Array.isArray(data) ? data as SourceSubscription[] : [];
    } catch {
      return [];
    }
  }

  /**
   * 保存订阅列表
   */
  static async saveSubscriptions(subs: SourceSubscription[]): Promise<void> {
    await PreferenceService.saveSourceSubscriptions(JSON.stringify(subs));
  }
}

