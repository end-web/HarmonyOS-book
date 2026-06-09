/**
 * 书源数据服务
 *
 * 内置源（builtin://...）由 BuiltInSourceRegistry 注入，与用户订阅源同列。
 * 内置源不会被持久化到 Preferences，每次启动通过 registry 现拼。
 */

import { BookSource, SourceSubscription } from '../model/BookSource';
import { PreferenceService } from './PreferenceService';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';

export class SourceDataService {
  private static cache: BookSource[] | null = null;
  private static disabledLoaded: boolean = false;

  /**
   * 获取所有书源（用户订阅 + 内置）
   */
  static async getSources(): Promise<BookSource[]> {
    if (SourceDataService.cache) return SourceDataService.cache;

    // 启动后第一次读，先把内置源的禁用状态注入到 Registry
    if (!SourceDataService.disabledLoaded) {
      try {
        const ids = await PreferenceService.getBuiltinDisabledIds();
        BuiltInSourceRegistry.setDisabledIds(ids);
      } catch { /* ignore */ }
      SourceDataService.disabledLoaded = true;
    }

    let userSources: BookSource[] = [];
    try {
      const json = await PreferenceService.getBookSources();
      const data: Object = JSON.parse(json) as Object;
      userSources = Array.isArray(data) ? data as BookSource[] : [];
    } catch {
      userSources = [];
    }
    // 过滤掉历史可能写入的 builtin 条目，避免重复；同时丢掉 bookSourceUrl 为空的脏数据
    const filtered: BookSource[] = [];
    for (const s of userSources) {
      if (!s || typeof s.bookSourceUrl !== 'string' || s.bookSourceUrl.length === 0) continue;
      if (BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) continue;
      filtered.push(s);
    }
    const builtIn = BuiltInSourceRegistry.materialize();
    SourceDataService.cache = filtered.concat(builtIn);
    return SourceDataService.cache;
  }

  /**
   * 保存书源列表（仅持久化非内置源；内置源的 enabled 状态写入单独的 disabledIds）
   */
  static async saveSources(sources: BookSource[]): Promise<void> {
    const userOnly: BookSource[] = [];
    const builtinDisabled: string[] = [];
    for (const s of sources) {
      if (!s || typeof s.bookSourceUrl !== 'string') continue;
      if (BuiltInSourceRegistry.isBuiltIn(s.bookSourceUrl)) {
        if (s.enabled === false) {
          const id = s.bookSourceUrl.substring('builtin://eprendre/'.length);
          builtinDisabled.push(id);
        }
      } else {
        userOnly.push(s);
      }
    }
    await PreferenceService.saveBookSources(JSON.stringify(userOnly));
    await PreferenceService.saveBuiltinDisabledIds(builtinDisabled);
    BuiltInSourceRegistry.setDisabledIds(builtinDisabled);
    // 重新拼缓存（用最新的 disabled 状态）
    const builtIn = BuiltInSourceRegistry.materialize();
    SourceDataService.cache = userOnly.concat(builtIn);
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
   * 更新单个书源（按原 bookSourceUrl 定位；若 url 改了则先按 originUrl 找再替换）。
   * 内置源不支持更新，传入会被忽略。
   */
  static async updateSource(originUrl: string, updated: BookSource): Promise<void> {
    if (BuiltInSourceRegistry.isBuiltIn(originUrl) || BuiltInSourceRegistry.isBuiltIn(updated.bookSourceUrl)) {
      return;
    }
    const existing = await SourceDataService.getSources();
    let replaced = false;
    const out: BookSource[] = [];
    for (const s of existing) {
      if (!replaced && s.bookSourceUrl === originUrl) {
        out.push(updated);
        replaced = true;
      } else {
        out.push(s);
      }
    }
    if (!replaced) out.push(updated);
    await SourceDataService.saveSources(out);
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

