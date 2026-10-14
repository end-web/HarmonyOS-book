import { BookSource } from '../../model/data/Book';

/**
 * Parsed, read-only view of the small pieces of BookSource runtime state used by native features.
 * A source may keep large protocol caches in __legadoHarmonyRuntime; callers must never repeatedly
 * parse or recursively scan that payload on reader and interaction hot paths.
 */
export class BookSourceRuntimeSnapshot {
  readonly signature: string;
  private variableState: Record<string, Object> = {};
  private loginState: Record<string, Object> = {};
  private runtimeJavaState: Record<string, Object> = {};
  private runtimeSourceState: Record<string, Object> = {};
  private stringCache: Map<string, string> = new Map();

  constructor(source: BookSource, signature: string) {
    this.signature = signature;
    this.variableState = this.parseRecord(source.variable || '');
    this.loginState = this.parseRecord(source.loginInfo || '');
    const runtime = this.parseNestedRecord(this.loginState['__legadoHarmonyRuntime']);
    this.runtimeJavaState = this.parseNestedRecord(runtime['java']);
    this.runtimeSourceState = this.parseNestedRecord(runtime['source']);
  }

  getString(key: string): string {
    const normalizedKey = (key || '').trim();
    if (!normalizedKey) return '';
    const cached = this.stringCache.get(normalizedKey);
    if (cached !== undefined) return cached;

    // Runtime settings are ordinary direct java/source properties. Large protocol maps are also
    // direct properties, but are never traversed while resolving an unrelated setting.
    let value = this.directString(this.runtimeJavaState, normalizedKey) ||
      this.directString(this.runtimeSourceState, normalizedKey) ||
      this.deepString(this.variableState, normalizedKey, false) ||
      this.deepString(this.loginState, normalizedKey, true);
    value = value.trim();
    this.stringCache.set(normalizedKey, value);
    return value;
  }

  getRuntimeJavaValue(key: string): Object | null {
    const value = this.runtimeJavaState[key];
    return value === undefined || value === null ? null : value;
  }

  settingState(keys: string[]): number {
    for (const key of keys) {
      const state = BookSourceSettingValue.state(this.getString(key));
      if (state !== 0) return state;
    }
    return 0;
  }

  private directString(record: Record<string, Object>, key: string): string {
    const value = record[key];
    if (value === undefined || value === null || typeof value === 'object') return '';
    return String(value);
  }

  private deepString(value: Object, key: string, skipRuntime: boolean): string {
    if (!value || typeof value !== 'object') return '';
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const found = this.deepString(item, key, skipRuntime);
        if (found) return found;
      }
      return '';
    }
    const record = value as Record<string, Object>;
    const direct = this.directString(record, key);
    if (direct) return direct;
    for (const name of Object.keys(record)) {
      if (skipRuntime && name === '__legadoHarmonyRuntime') continue;
      const nested = record[name];
      if (nested && typeof nested === 'object') {
        const found = this.deepString(nested, key, skipRuntime);
        if (found) return found;
      }
    }
    return '';
  }

  private parseRecord(raw: string): Record<string, Object> {
    if (!raw) return {};
    try {
      const parsed = JSON.parse(raw) as Object;
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ?
        parsed as Record<string, Object> : {};
    } catch (_) {
      return {};
    }
  }

  private parseNestedRecord(value: Object | undefined): Record<string, Object> {
    let parsed: Object | undefined = value;
    if (typeof parsed === 'string') {
      try { parsed = JSON.parse(parsed || '{}') as Object; } catch (_) { return {}; }
    }
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ?
      parsed as Record<string, Object> : {};
  }
}

export class BookSourceRuntimeSnapshotStore {
  private static readonly MAX_SNAPSHOTS: number = 24;
  private static snapshots: Map<string, BookSourceRuntimeSnapshot> = new Map();

  static get(source: BookSource): BookSourceRuntimeSnapshot {
    const key = source.bookSourceUrl || source.bookSourceName || '__anonymous_source__';
    const signature = this.buildSignature(source);
    const cached = this.snapshots.get(key);
    if (cached && cached.signature === signature) return cached;
    const snapshot = new BookSourceRuntimeSnapshot(source, signature);
    this.snapshots.delete(key);
    this.snapshots.set(key, snapshot);
    while (this.snapshots.size > this.MAX_SNAPSHOTS) {
      const oldest = this.snapshots.keys().next().value as string | undefined;
      if (!oldest) break;
      this.snapshots.delete(oldest);
    }
    return snapshot;
  }

  static invalidate(sourceUrl: string): void {
    if (sourceUrl) this.snapshots.delete(sourceUrl);
  }

  private static buildSignature(source: BookSource): string {
    const login = source.loginInfo || '';
    const variable = source.variable || '';
    // lastUpdateTime is bookkeeping metadata and may be refreshed by cloud restore even when
    // the interaction state is unchanged. It must not invalidate durable chapter content.
    return `${this.textSignature(login)}:${this.textSignature(variable)}`;
  }

  private static textSignature(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `${value.length}:${(hash >>> 0).toString(16)}`;
  }
}

export class BookSourceSettingValue {
  static state(value: Object | string | undefined | null): number {
    const normalized = String(value ?? '').trim().toLowerCase();
    if (normalized === 'on' || normalized === 'true' || normalized === '1' || normalized === 'yes' ||
      normalized === 'enabled' || normalized === '开' || normalized === '开启' || normalized === '打开' ||
      normalized === '已开启' || normalized === '✅' || normalized === '☑' || normalized === '☑️') return 1;
    if (normalized === 'off' || normalized === 'false' || normalized === '0' || normalized === 'no' ||
      normalized === 'disabled' || normalized === '关' || normalized === '关闭' || normalized === '已关闭' ||
      normalized === '❌' || normalized === '🔳' || normalized === '☐') return -1;
    return 0;
  }
}
