import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';

class SourceRequestWindow {
  starts: number[] = [];
  touchedAt: number = 0;
  active: number = 0;
}

export class LocalRuleRequestPermit {
  private bucket: SourceRequestWindow | undefined;

  constructor(bucket?: SourceRequestWindow) {
    this.bucket = bucket;
  }

  release(): void {
    if (this.bucket === undefined) return;
    this.bucket.active = Math.max(0, this.bucket.active - 1);
    this.bucket = undefined;
  }
}

/** Sliding request window; checking and reserving a slot happen without an await. */
export class LocalRuleRequestLimiter {
  private static windows: Map<string, SourceRequestWindow> = new Map<string, SourceRequestWindow>();

  static async acquire(sourceUrl: string, rate: string, timeoutMs: number,
    variables: Record<string, string>): Promise<LocalRuleRequestPermit> {
    const clean = rate.trim();
    if (!clean || clean === '0') return new LocalRuleRequestPermit();
    const match = new RegExp('^(\\d+)\\s*/\\s*(\\d+)$').exec(clean);
    const integer = new RegExp('^-?\\d+$').test(clean) ? Number(clean) : NaN;
    const concurrency = Number.isSafeInteger(integer) && integer < 0;
    const count = match !== null ? Number(match[1]) : concurrency ? -integer : 1;
    const windowMs = match !== null ? Number(match[2]) : concurrency ? 0 : integer;
    if (!Number.isSafeInteger(count) || count < 1 || !Number.isSafeInteger(windowMs) ||
      (!concurrency && windowMs < 1)) {
      LocalRuleDiagnostics.record(variables, 'warn', '忽略无法识别的请求频率配置');
      return new LocalRuleRequestPermit();
    }
    const startedAt = Date.now();
    let bucket = LocalRuleRequestLimiter.windows.get(sourceUrl);
    if (bucket === undefined) {
      LocalRuleRequestLimiter.windows.forEach((entry: SourceRequestWindow, key: string): void => {
        if (entry.active === 0 && startedAt - entry.touchedAt > 86400000) {
          LocalRuleRequestLimiter.windows.delete(key);
        }
      });
      bucket = new SourceRequestWindow();
      LocalRuleRequestLimiter.windows.set(sourceUrl, bucket);
    }
    while (true) {
      LocalRuleDiagnostics.check(variables);
      const now = Date.now();
      bucket.touchedAt = now;
      if (concurrency) {
        if (bucket.active < count) {
          bucket.active++;
          return new LocalRuleRequestPermit(bucket);
        }
      } else {
        bucket.starts = bucket.starts.filter((time: number): boolean => now - time < windowMs);
        if (bucket.starts.length < count) {
          bucket.starts.push(now);
          return new LocalRuleRequestPermit();
        }
      }
      const wait = concurrency ? 25 : Math.max(1, bucket.starts[0] + windowMs - now);
      if (now - startedAt + wait > timeoutMs) throw new Error('书源请求限流等待超时');
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, Math.min(wait, 250)); });
    }
  }
}
