/**
 * SourceVariableStore - 源级 / 书级变量持久化存储
 *
 * 为每个书源提供独立的 key-value 变量存储，持久化到 Preferences。
 * 用于支持 Legado 书源的 source.getVariable() / source.setVariable()
 * 以及 book.getVariable() / book.setVariable() 机制。
 *
 * 内存缓存 + 异步刷盘，避免频繁 IO。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'source_variables';
const TAG = 'SourceVariableStore';

export class SourceVariableStore {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  // 内存缓存：sourceUrl -> { key -> value }
  private static sourceCache: Map<string, Record<string, Object>> = new Map();
  // 内存缓存：bookId -> { key -> value }
  private static bookCache: Map<string, Record<string, Object>> = new Map();

  private static dirtySources: Set<string> = new Set();
  private static dirtyBooks: Set<string> = new Set();
  private static flushTimer: number = -1;

  static async init(context: common.BaseContext): Promise<void> {
    if (SourceVariableStore.store) return;
    if (SourceVariableStore.initPromise) return SourceVariableStore.initPromise;
    SourceVariableStore.initPromise = SourceVariableStore.doInit(context);
    return SourceVariableStore.initPromise;
  }

  private static async doInit(context: common.BaseContext): Promise<void> {
    try {
      const opts: preferences.Options = { name: STORE_NAME };
      SourceVariableStore.store = await preferences.getPreferences(context, opts);
    } catch (e) {
      console.error(`[${TAG}] init failed: ${e}`);
    }
  }

  private static ensureStore(): preferences.Preferences | null {
    if (!SourceVariableStore.store) {
      console.warn(`[${TAG}] store not initialized`);
    }
    return SourceVariableStore.store;
  }

  // ──────────── 源变量 ────────────

  static getSourceVariables(sourceUrl: string): Record<string, Object> {
    if (SourceVariableStore.sourceCache.has(sourceUrl)) {
      return SourceVariableStore.sourceCache.get(sourceUrl)!;
    }
    const store = SourceVariableStore.ensureStore();
    if (!store) return {};
    try {
      const raw = store.getSync(`sv_${sourceUrl}`, '') as string;
      if (raw) {
        const parsed = JSON.parse(raw) as Record<string, Object>;
        SourceVariableStore.sourceCache.set(sourceUrl, parsed);
        return parsed;
      }
    } catch (e) {
      console.error(`[${TAG}] getSourceVariables parse error: ${e}`);
    }
    const empty: Record<string, Object> = {};
    SourceVariableStore.sourceCache.set(sourceUrl, empty);
    return empty;
  }

  static getSourceVariable(sourceUrl: string, key: string): Object | undefined {
    const vars = SourceVariableStore.getSourceVariables(sourceUrl);
    return vars[key];
  }

  static setSourceVariable(sourceUrl: string, key: string, value: Object): void {
    const vars = SourceVariableStore.getSourceVariables(sourceUrl);
    vars[key] = value;
    SourceVariableStore.sourceCache.set(sourceUrl, vars);
    SourceVariableStore.dirtySources.add(sourceUrl);
    SourceVariableStore.scheduleFlush();
  }

  static removeSourceVariable(sourceUrl: string, key: string): void {
    const vars = SourceVariableStore.getSourceVariables(sourceUrl);
    if (vars[key] !== undefined) {
      vars[key] = '' as Object;
      SourceVariableStore.sourceCache.set(sourceUrl, vars);
      SourceVariableStore.dirtySources.add(sourceUrl);
      SourceVariableStore.scheduleFlush();
    }
  }

  // ──────────── 书级变量 ────────────

  static getBookVariables(bookId: string): Record<string, Object> {
    if (SourceVariableStore.bookCache.has(bookId)) {
      return SourceVariableStore.bookCache.get(bookId)!;
    }
    const store = SourceVariableStore.ensureStore();
    if (!store) return {};
    try {
      const raw = store.getSync(`bv_${bookId}`, '') as string;
      if (raw) {
        const parsed = JSON.parse(raw) as Record<string, Object>;
        SourceVariableStore.bookCache.set(bookId, parsed);
        return parsed;
      }
    } catch (e) {
      console.error(`[${TAG}] getBookVariables parse error: ${e}`);
    }
    const empty: Record<string, Object> = {};
    SourceVariableStore.bookCache.set(bookId, empty);
    return empty;
  }

  static getBookVariable(bookId: string, key: string): Object | undefined {
    const vars = SourceVariableStore.getBookVariables(bookId);
    return vars[key];
  }

  static setBookVariable(bookId: string, key: string, value: Object): void {
    const vars = SourceVariableStore.getBookVariables(bookId);
    vars[key] = value;
    SourceVariableStore.bookCache.set(bookId, vars);
    SourceVariableStore.dirtyBooks.add(bookId);
    SourceVariableStore.scheduleFlush();
  }

  static removeBookVariable(bookId: string, key: string): void {
    const vars = SourceVariableStore.getBookVariables(bookId);
    if (vars[key] !== undefined) {
      vars[key] = '' as Object;
      SourceVariableStore.bookCache.set(bookId, vars);
      SourceVariableStore.dirtyBooks.add(bookId);
      SourceVariableStore.scheduleFlush();
    }
  }

  // ──────────── 刷盘 ────────────

  private static scheduleFlush(): void {
    if (SourceVariableStore.flushTimer >= 0) return;
    const timerId = setTimeout(() => {
      SourceVariableStore.doFlush();
      SourceVariableStore.flushTimer = -1;
    }, 500);
    SourceVariableStore.flushTimer = timerId as number;
  }

  private static doFlush(): void {
    const store = SourceVariableStore.ensureStore();
    if (!store) return;
    try {
      for (const sourceUrl of SourceVariableStore.dirtySources) {
        const vars = SourceVariableStore.sourceCache.get(sourceUrl) || {};
        store.putSync(`sv_${sourceUrl}`, JSON.stringify(vars));
      }
      for (const bookId of SourceVariableStore.dirtyBooks) {
        const vars = SourceVariableStore.bookCache.get(bookId) || {};
        store.putSync(`bv_${bookId}`, JSON.stringify(vars));
      }
      SourceVariableStore.dirtySources.clear();
      SourceVariableStore.dirtyBooks.clear();
      store.flush();
    } catch (e) {
      console.error(`[${TAG}] flush error: ${e}`);
    }
  }
}
