import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { QuickJsObservationContext } from './QuickJsRuntimeStatus';

export type QuickJsValidationEvent = 'shadow-match' | 'shadow-mismatch' | 'shadow-failure';

export class QuickJsValidationSeed {
  sourceUrl: string = '';
  sourceName: string = '';
  stage: string = '';
  field: string = '';
  fingerprint: string = '';
  offlineStatus: string = '';
  routable: boolean = false;
}

export class QuickJsValidationCandidate extends QuickJsValidationSeed {
  offlineAt: number = 0;
  realMatches: number = 0;
  realMismatches: number = 0;
  realFailures: number = 0;
  lastSeenAt: number = 0;

  isOfflinePassed(): boolean { return this.offlineStatus === 'match'; }
  canEnterRealValidation(): boolean { return this.isOfflinePassed() && this.routable; }
  hasRealIssue(): boolean { return this.realMismatches > 0 || this.realFailures > 0; }
  isQualified(): boolean {
    return this.canEnterRealValidation() && this.realMatches >= QuickJsValidationStore.REAL_MATCH_THRESHOLD &&
      !this.hasRealIssue();
  }
}

export class QuickJsValidationSnapshot {
  active: boolean = false;
  startedAt: number = 0;
  updatedAt: number = 0;
  candidates: QuickJsValidationCandidate[] = [];
}

/**
 * Persists the promotion workflow without storing scripts, runtime bindings or result values.
 * Candidate identity is limited to source/stage/field and an irreversible expression fingerprint.
 */
export class QuickJsValidationStore {
  static readonly REAL_MATCH_THRESHOLD: number = 4;
  private static readonly STORE_NAME: string = 'quickjs_validation';
  private static readonly KEY_SNAPSHOT: string = 'snapshotV1';
  private static readonly MAX_CANDIDATES: number = 300;
  private static context: Context | null = null;
  private static state: QuickJsValidationSnapshot = new QuickJsValidationSnapshot();
  private static initialized: boolean = false;
  private static saveScheduled: boolean = false;

  static async initialize(context: Context): Promise<void> {
    QuickJsValidationStore.context = context;
    if (QuickJsValidationStore.initialized) return;
    const store = await preferences.getPreferences(context, QuickJsValidationStore.STORE_NAME);
    const raw = await store.get(QuickJsValidationStore.KEY_SNAPSHOT, '');
    if (typeof raw === 'string' && raw) QuickJsValidationStore.state = QuickJsValidationStore.parse(raw);
    QuickJsValidationStore.initialized = true;
    QuickJsValidationStore.publish();
  }

  static snapshot(): QuickJsValidationSnapshot {
    return QuickJsValidationStore.parse(JSON.stringify(QuickJsValidationStore.state));
  }

  static async saveRegression(context: Context, seeds: QuickJsValidationSeed[]): Promise<void> {
    QuickJsValidationStore.context = context;
    const previous = QuickJsValidationStore.state.candidates;
    const candidates: QuickJsValidationCandidate[] = [];
    const seen: Set<string> = new Set<string>();
    for (const seed of seeds.slice(0, QuickJsValidationStore.MAX_CANDIDATES)) {
      const key = QuickJsValidationStore.seedKey(seed);
      if (!seed.fingerprint || !seed.sourceUrl || seen.has(key)) continue;
      seen.add(key);
      const candidate = new QuickJsValidationCandidate();
      candidate.sourceUrl = seed.sourceUrl;
      candidate.sourceName = seed.sourceName;
      candidate.stage = seed.stage;
      candidate.field = seed.field;
      candidate.fingerprint = seed.fingerprint;
      candidate.offlineStatus = seed.offlineStatus;
      candidate.routable = seed.routable;
      candidate.offlineAt = Date.now();
      const existing = previous.find((item: QuickJsValidationCandidate): boolean =>
        QuickJsValidationStore.seedKey(item) === key);
      if (existing && seed.offlineStatus === 'match' && seed.routable) {
        candidate.realMatches = existing.realMatches;
        candidate.realMismatches = existing.realMismatches;
        candidate.realFailures = existing.realFailures;
        candidate.lastSeenAt = existing.lastSeenAt;
      }
      candidates.push(candidate);
    }
    QuickJsValidationStore.state.candidates = candidates;
    QuickJsValidationStore.state.active = false;
    QuickJsValidationStore.state.startedAt = 0;
    QuickJsValidationStore.state.updatedAt = Date.now();
    QuickJsValidationStore.publish();
    await QuickJsValidationStore.flush();
  }

  /** Removes candidates whose stored expressions no longer satisfy the bounded QuickJS contract. */
  static async removeRegressionCandidates(context: Context, seeds: QuickJsValidationSeed[]): Promise<void> {
    if (seeds.length === 0) return;
    QuickJsValidationStore.context = context;
    const removing: Set<string> = new Set<string>();
    for (const seed of seeds) removing.add(QuickJsValidationStore.seedKey(seed));
    QuickJsValidationStore.state.candidates = QuickJsValidationStore.state.candidates.filter(
      (item: QuickJsValidationCandidate): boolean => !removing.has(QuickJsValidationStore.seedKey(item)));
    if (!QuickJsValidationStore.state.candidates.some(
      (item: QuickJsValidationCandidate): boolean => item.canEnterRealValidation())) {
      QuickJsValidationStore.state.active = false;
      QuickJsValidationStore.state.startedAt = 0;
    }
    QuickJsValidationStore.state.updatedAt = Date.now();
    QuickJsValidationStore.publish();
    await QuickJsValidationStore.flush();
  }

  static async start(context: Context): Promise<boolean> {
    QuickJsValidationStore.context = context;
    if (!QuickJsValidationStore.state.candidates.some(
      (item: QuickJsValidationCandidate): boolean => item.canEnterRealValidation())) return false;
    QuickJsValidationStore.state.active = true;
    QuickJsValidationStore.state.startedAt = Date.now();
    QuickJsValidationStore.state.updatedAt = Date.now();
    QuickJsValidationStore.publish();
    await QuickJsValidationStore.flush();
    return true;
  }

  static async stop(context: Context): Promise<void> {
    QuickJsValidationStore.context = context;
    QuickJsValidationStore.state.active = false;
    QuickJsValidationStore.state.updatedAt = Date.now();
    QuickJsValidationStore.publish();
    await QuickJsValidationStore.flush();
  }

  static isValidationTarget(observation: QuickJsObservationContext | null, fingerprint: string): boolean {
    if (!QuickJsValidationStore.state.active || !observation) return false;
    const candidate = QuickJsValidationStore.find(observation, fingerprint);
    return !!candidate && candidate.canEnterRealValidation() && !candidate.hasRealIssue() && !candidate.isQualified();
  }

  static record(event: QuickJsValidationEvent, fingerprint: string,
    observation: QuickJsObservationContext | null): void {
    if (!QuickJsValidationStore.state.active || !observation) return;
    const candidate = QuickJsValidationStore.find(observation, fingerprint);
    if (!candidate || !candidate.canEnterRealValidation() || candidate.isQualified()) return;
    if (event === 'shadow-match') candidate.realMatches++;
    else if (event === 'shadow-mismatch') candidate.realMismatches++;
    else candidate.realFailures++;
    candidate.lastSeenAt = Date.now();
    QuickJsValidationStore.state.updatedAt = candidate.lastSeenAt;
    QuickJsValidationStore.publish();
    QuickJsValidationStore.scheduleSave();
  }

  static async clearRealProgress(context: Context): Promise<void> {
    QuickJsValidationStore.context = context;
    for (const candidate of QuickJsValidationStore.state.candidates) {
      candidate.realMatches = 0;
      candidate.realMismatches = 0;
      candidate.realFailures = 0;
      candidate.lastSeenAt = 0;
    }
    QuickJsValidationStore.state.active = false;
    QuickJsValidationStore.state.startedAt = 0;
    QuickJsValidationStore.state.updatedAt = Date.now();
    QuickJsValidationStore.publish();
    await QuickJsValidationStore.flush();
  }

  private static find(observation: QuickJsObservationContext,
    fingerprint: string): QuickJsValidationCandidate | null {
    return QuickJsValidationStore.state.candidates.find((item: QuickJsValidationCandidate): boolean =>
      item.sourceUrl === observation.sourceUrl && item.stage === observation.stage &&
      item.field === observation.field && item.fingerprint === fingerprint) || null;
  }

  private static seedKey(seed: QuickJsValidationSeed): string {
    return `${seed.sourceUrl}\n${seed.stage}\n${seed.field}\n${seed.fingerprint}`;
  }

  private static scheduleSave(): void {
    if (QuickJsValidationStore.saveScheduled || !QuickJsValidationStore.context) return;
    QuickJsValidationStore.saveScheduled = true;
    setTimeout((): void => {
      QuickJsValidationStore.saveScheduled = false;
      QuickJsValidationStore.flush().catch((): void => {});
    }, 300);
  }

  private static async flush(): Promise<void> {
    const context = QuickJsValidationStore.context;
    if (!context) return;
    const store = await preferences.getPreferences(context, QuickJsValidationStore.STORE_NAME);
    await store.put(QuickJsValidationStore.KEY_SNAPSHOT, JSON.stringify(QuickJsValidationStore.state));
    await store.flush();
  }

  private static publish(): void {
    AppStorage.setOrCreate('quickJsValidationRevision', Date.now());
  }

  private static parse(raw: string): QuickJsValidationSnapshot {
    const result = new QuickJsValidationSnapshot();
    try {
      const value = JSON.parse(raw || '{}') as Record<string, Object>;
      result.active = value['active'] === true;
      result.startedAt = Number(value['startedAt'] || 0);
      result.updatedAt = Number(value['updatedAt'] || 0);
      const entries = value['candidates'];
      if (Array.isArray(entries)) {
        for (const rawEntry of (entries as Record<string, Object>[]).slice(0,
          QuickJsValidationStore.MAX_CANDIDATES)) {
          const candidate = new QuickJsValidationCandidate();
          candidate.sourceUrl = String(rawEntry['sourceUrl'] || '');
          candidate.sourceName = String(rawEntry['sourceName'] || '');
          candidate.stage = String(rawEntry['stage'] || '');
          candidate.field = String(rawEntry['field'] || '');
          candidate.fingerprint = String(rawEntry['fingerprint'] || '');
          candidate.offlineStatus = String(rawEntry['offlineStatus'] || '');
          candidate.routable = rawEntry['routable'] === true;
          candidate.offlineAt = Number(rawEntry['offlineAt'] || 0);
          candidate.realMatches = Number(rawEntry['realMatches'] || 0);
          candidate.realMismatches = Number(rawEntry['realMismatches'] || 0);
          candidate.realFailures = Number(rawEntry['realFailures'] || 0);
          candidate.lastSeenAt = Number(rawEntry['lastSeenAt'] || 0);
          if (candidate.sourceUrl && candidate.fingerprint) result.candidates.push(candidate);
        }
      }
    } catch (_) {}
    return result;
  }
}
