/**
 * CacheService - 书源 JS 缓存 API
 *
 * 为 JS 沙箱提供 cache.get / cache.put / cache.delete
 * 以及 cache.putMemory / cache.getFromMemory 内存缓存。
 *
 * 持久化缓存存储在 Preferences，内存缓存仅在会话内有效。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'js_cache';
const TAG = 'CacheService';

class CacheServiceImpl {
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;

  // 内存缓存（会话级，不持久化）
  private memoryCache: Map<string, Object> = new Map();

  async init(context: common.BaseContext): Promise<void> {
    if (this.store) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.BaseContext): Promise<void> {
    try {
      const opts: preferences.Options = { name: STORE_NAME };
      this.store = await preferences.getPreferences(context, opts);
    } catch (e) {
      console.error(`[${TAG}] init failed: ${e}`);
    }
  }

  // ──────────── 持久化缓存 ────────────

  get(key: string): string {
    if (!this.store) return '';
    try {
      return this.store.getSync(key, '') as string;
    } catch {
      return '';
    }
  }

  put(key: string, value: string): void {
    if (!this.store) return;
    try {
      this.store.putSync(key, value);
      this.store.flush();
    } catch (e) {
      console.error(`[${TAG}] put error: ${e}`);
    }
  }

  delete(key: string): void {
    if (!this.store) return;
    try {
      this.store.deleteSync(key);
      this.store.flush();
    } catch (e) {
      console.error(`[${TAG}] delete error: ${e}`);
    }
  }

  // ──────────── 内存缓存 ────────────

  getFromMemory(key: string): Object {
    return this.memoryCache.get(key) || 0;
  }

  putMemory(key: string, value: Object): void {
    this.memoryCache.set(key, value);
  }

  clearMemory(): void {
    this.memoryCache.clear();
  }
}

let globalCacheService: CacheServiceImpl | null = null;

export function getCacheService(): CacheServiceImpl {
  if (!globalCacheService) {
    globalCacheService = new CacheServiceImpl();
  }
  return globalCacheService;
}
