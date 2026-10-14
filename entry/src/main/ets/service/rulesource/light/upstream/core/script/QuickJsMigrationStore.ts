import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { QuickJsRuntimeMode, QuickJsRuntimeStatus } from './QuickJsRuntimeStatus';

export type QuickJsMigrationEvent = 'shadow-match' | 'shadow-mismatch' | 'shadow-failure' |
  'route-success' | 'route-fallback';

export class QuickJsFingerprintStats {
  fingerprint: string = '';
  shadowMatches: number = 0;
  shadowMismatches: number = 0;
  shadowFailures: number = 0;
  routedSuccesses: number = 0;
  routedFallbacks: number = 0;
  lastElapsedMs: number = 0;
  updatedAt: number = 0;
}

export class QuickJsMigrationSnapshot {
  mode: string = QuickJsRuntimeMode.SHADOW;
  selfTestPassed: boolean = false;
  selfTestAt: number = 0;
  shadowMatches: number = 0;
  shadowMismatches: number = 0;
  shadowFailures: number = 0;
  routedSuccesses: number = 0;
  routedFallbacks: number = 0;
  consecutiveRouteFailures: number = 0;
  circuitOpenUntil: number = 0;
  fingerprints: QuickJsFingerprintStats[] = [];
}

/** Persistent privacy-safe migration report. It stores hashes and counters, never source code or values. */
export class QuickJsMigrationStore {
  private static readonly STORE_NAME: string = 'quickjs_migration';
  private static readonly KEY_SNAPSHOT: string = 'snapshotV1';
  private static readonly CANARY_MATCH_THRESHOLD: number = 4;
  private static readonly CIRCUIT_FAILURE_THRESHOLD: number = 3;
  private static readonly CIRCUIT_OPEN_MS: number = 5 * 60 * 1000;
  private static context: Context | null = null;
  private static state: QuickJsMigrationSnapshot = new QuickJsMigrationSnapshot();
  private static initialized: boolean = false;
  private static saveScheduled: boolean = false;

  static async initialize(context: Context): Promise<void> {
    QuickJsMigrationStore.context = context;
    if (QuickJsMigrationStore.initialized) return;
    const store = await preferences.getPreferences(context, QuickJsMigrationStore.STORE_NAME);
    const raw = await store.get(QuickJsMigrationStore.KEY_SNAPSHOT, '');
    if (typeof raw === 'string' && raw) QuickJsMigrationStore.state = QuickJsMigrationStore.parse(raw);
    QuickJsMigrationStore.initialized = true;
    QuickJsRuntimeStatus.setMode(QuickJsMigrationStore.parseMode(QuickJsMigrationStore.state.mode));
    QuickJsMigrationStore.publish();
  }

  static snapshot(): QuickJsMigrationSnapshot {
    return QuickJsMigrationStore.parse(JSON.stringify(QuickJsMigrationStore.state));
  }

  static async setMode(context: Context, mode: QuickJsRuntimeMode): Promise<void> {
    QuickJsMigrationStore.context = context;
    QuickJsMigrationStore.state.mode = mode;
    QuickJsRuntimeStatus.setMode(mode);
    QuickJsMigrationStore.publish();
    await QuickJsMigrationStore.flush();
  }

  static recordSelfTest(passed: boolean): void {
    QuickJsMigrationStore.state.selfTestPassed = passed;
    QuickJsMigrationStore.state.selfTestAt = Date.now();
    QuickJsMigrationStore.publish();
    QuickJsMigrationStore.scheduleSave();
  }

  static isCanaryEligible(fingerprint: string): boolean {
    if (QuickJsMigrationStore.state.circuitOpenUntil > Date.now()) return false;
    const item = QuickJsMigrationStore.find(fingerprint);
    return !!item && item.shadowMatches >= QuickJsMigrationStore.CANARY_MATCH_THRESHOLD &&
      item.shadowMismatches === 0 && item.shadowFailures === 0;
  }

  static isCircuitOpen(): boolean {
    return QuickJsMigrationStore.state.circuitOpenUntil > Date.now();
  }

  static record(event: QuickJsMigrationEvent, fingerprint: string, elapsedMs: number = 0): void {
    const item = QuickJsMigrationStore.getOrCreate(fingerprint);
    item.lastElapsedMs = Math.max(0, elapsedMs);
    item.updatedAt = Date.now();
    if (event === 'shadow-match') {
      item.shadowMatches++;
      QuickJsMigrationStore.state.shadowMatches++;
    } else if (event === 'shadow-mismatch') {
      item.shadowMismatches++;
      QuickJsMigrationStore.state.shadowMismatches++;
    } else if (event === 'shadow-failure') {
      item.shadowFailures++;
      QuickJsMigrationStore.state.shadowFailures++;
    } else if (event === 'route-success') {
      item.routedSuccesses++;
      QuickJsMigrationStore.state.routedSuccesses++;
      QuickJsMigrationStore.state.consecutiveRouteFailures = 0;
    } else {
      item.routedFallbacks++;
      QuickJsMigrationStore.state.routedFallbacks++;
      QuickJsMigrationStore.state.consecutiveRouteFailures++;
      if (QuickJsMigrationStore.state.consecutiveRouteFailures >=
        QuickJsMigrationStore.CIRCUIT_FAILURE_THRESHOLD) {
        QuickJsMigrationStore.state.circuitOpenUntil = Date.now() + QuickJsMigrationStore.CIRCUIT_OPEN_MS;
        QuickJsMigrationStore.state.consecutiveRouteFailures = 0;
      }
    }
    QuickJsMigrationStore.trim();
    QuickJsMigrationStore.publish();
    QuickJsMigrationStore.scheduleSave();
  }

  static async clearDiagnostics(context: Context): Promise<void> {
    const mode = QuickJsRuntimeStatus.getMode();
    QuickJsMigrationStore.state = new QuickJsMigrationSnapshot();
    QuickJsMigrationStore.state.mode = mode;
    QuickJsMigrationStore.context = context;
    QuickJsMigrationStore.publish();
    await QuickJsMigrationStore.flush();
  }

  private static find(fingerprint: string): QuickJsFingerprintStats | null {
    return QuickJsMigrationStore.state.fingerprints.find(
      (item: QuickJsFingerprintStats): boolean => item.fingerprint === fingerprint) || null;
  }

  private static getOrCreate(fingerprint: string): QuickJsFingerprintStats {
    const existing = QuickJsMigrationStore.find(fingerprint);
    if (existing) return existing;
    const item = new QuickJsFingerprintStats();
    item.fingerprint = fingerprint;
    QuickJsMigrationStore.state.fingerprints.push(item);
    return item;
  }

  private static trim(): void {
    if (QuickJsMigrationStore.state.fingerprints.length <= 128) return;
    QuickJsMigrationStore.state.fingerprints.sort(
      (a: QuickJsFingerprintStats, b: QuickJsFingerprintStats): number => b.updatedAt - a.updatedAt);
    QuickJsMigrationStore.state.fingerprints = QuickJsMigrationStore.state.fingerprints.slice(0, 128);
  }

  private static scheduleSave(): void {
    if (QuickJsMigrationStore.saveScheduled || !QuickJsMigrationStore.context) return;
    QuickJsMigrationStore.saveScheduled = true;
    setTimeout(() => {
      QuickJsMigrationStore.saveScheduled = false;
      QuickJsMigrationStore.flush().catch(() => {});
    }, 400);
  }

  private static async flush(): Promise<void> {
    const context = QuickJsMigrationStore.context;
    if (!context) return;
    const store = await preferences.getPreferences(context, QuickJsMigrationStore.STORE_NAME);
    await store.put(QuickJsMigrationStore.KEY_SNAPSHOT, JSON.stringify(QuickJsMigrationStore.state));
    await store.flush();
  }

  private static publish(): void {
    AppStorage.setOrCreate('quickJsMigrationRevision', Date.now());
  }

  private static parseMode(value: string): QuickJsRuntimeMode {
    if (value === QuickJsRuntimeMode.OFF) return QuickJsRuntimeMode.OFF;
    if (value === QuickJsRuntimeMode.CANARY) return QuickJsRuntimeMode.CANARY;
    if (value === QuickJsRuntimeMode.PREFER_QUICKJS) return QuickJsRuntimeMode.PREFER_QUICKJS;
    return QuickJsRuntimeMode.SHADOW;
  }

  private static parse(raw: string): QuickJsMigrationSnapshot {
    const result = new QuickJsMigrationSnapshot();
    try {
      const value = JSON.parse(raw || '{}') as Record<string, Object>;
      result.mode = String(value['mode'] || QuickJsRuntimeMode.SHADOW);
      result.selfTestPassed = value['selfTestPassed'] === true;
      result.selfTestAt = Number(value['selfTestAt'] || 0);
      result.shadowMatches = Number(value['shadowMatches'] || 0);
      result.shadowMismatches = Number(value['shadowMismatches'] || 0);
      result.shadowFailures = Number(value['shadowFailures'] || 0);
      result.routedSuccesses = Number(value['routedSuccesses'] || 0);
      result.routedFallbacks = Number(value['routedFallbacks'] || 0);
      result.consecutiveRouteFailures = Number(value['consecutiveRouteFailures'] || 0);
      result.circuitOpenUntil = Number(value['circuitOpenUntil'] || 0);
      const entries = value['fingerprints'];
      if (Array.isArray(entries)) {
        for (const rawEntry of entries as Record<string, Object>[]) {
          const item = new QuickJsFingerprintStats();
          item.fingerprint = String(rawEntry['fingerprint'] || '');
          item.shadowMatches = Number(rawEntry['shadowMatches'] || 0);
          item.shadowMismatches = Number(rawEntry['shadowMismatches'] || 0);
          item.shadowFailures = Number(rawEntry['shadowFailures'] || 0);
          item.routedSuccesses = Number(rawEntry['routedSuccesses'] || 0);
          item.routedFallbacks = Number(rawEntry['routedFallbacks'] || 0);
          item.lastElapsedMs = Number(rawEntry['lastElapsedMs'] || 0);
          item.updatedAt = Number(rawEntry['updatedAt'] || 0);
          if (item.fingerprint) result.fingerprints.push(item);
        }
      }
    } catch (_) {}
    return result;
  }
}
