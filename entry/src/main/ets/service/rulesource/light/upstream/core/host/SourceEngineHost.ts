import { BookSource } from '../../model/data/Book';
import { BookSourceRuntimePersistence } from '../book/BookSourceRuntimeStore';

/** All ports are trusted application code. Never expose them to a source script. */
export interface SourceCookieJar {
  getCookie(url: string): string;
  getCookieValue(url: string, name: string): string;
  setCookies(url: string, value: string): void;
  replaceCookies(url: string, value: string): void;
  removeCookie(url: string, name?: string): void;
  copyCookies(from: string, to: string): void;
  saveAsync(): void;
  saveSync(): void;
  clearAll(): void;
}

export interface SourceRateWaiter {
  isCancelled(): boolean;
  wait(ms: number): Promise<void>;
}

/** Selects the next waiter; the engine alone owns the source's frequency window. */
export interface SourceRequestScheduler {
  isCancelled(source: BookSource | null): boolean;
  priority(source: BookSource | null): number;
  enqueue(key: string, source: BookSource, cancelCheck?: () => boolean): SourceRateWaiter;
  first(key: string, waiter: SourceRateWaiter): boolean;
  remove(key: string, waiter: SourceRateWaiter): void;
}

export interface SourceScriptExecutor {
  /** True only for independent, bounded contexts; ArkWeb controllers must stay serial. */
  concurrent: boolean;
  forceFullScripts: boolean;
  allowSynchronousQuickJs: boolean;
  evaluate(script: string, sourceUrl: string, timingId: number): Promise<string>;
}

export interface SourceWebSession {
  run<T>(sourceUrl: string, action: () => Promise<T>): Promise<T>;
}

export interface SourceExecutionState {
  bindSource(source: BookSource, target: BookSource): void;
  setError(source: BookSource, message: string): void;
  getError(source: BookSource): string;
}

export interface SourceDiagnostics {
  id(source: BookSource | null): number;
  end(id: number, stage: string, startedAt: number, details?: string): void;
}

export interface SourceEngineHostAdapter {
  cookies?: (sourceUrl: string) => SourceCookieJar;
  persistence?: (source: BookSource) => BookSourceRuntimePersistence;
  scripts?: SourceScriptExecutor;
  web?: SourceWebSession;
  requests?: SourceRequestScheduler;
  state?: SourceExecutionState;
  diagnostics?: SourceDiagnostics;
}

class DefaultRateWaiter implements SourceRateWaiter {
  private cancelCheck?: () => boolean;
  constructor(cancelCheck?: () => boolean) { this.cancelCheck = cancelCheck; }
  isCancelled(): boolean { return !!this.cancelCheck?.(); }
  wait(ms: number): Promise<void> { return new Promise<void>(resolve => setTimeout(resolve, ms)); }
}

/** Install once during startup, before executing sources. No mutable "current source". */
export class SourceEngineHost {
  private static adapter: SourceEngineHostAdapter = {};
  private static waiterOwners = new WeakMap<SourceRateWaiter, SourceRequestScheduler>();

  static install(adapter: SourceEngineHostAdapter): void { this.adapter = adapter; }
  static cookies(sourceUrl: string): SourceCookieJar | undefined { return this.adapter.cookies?.(sourceUrl); }
  static persistence(source: BookSource): BookSourceRuntimePersistence | undefined {
    return this.adapter.persistence?.(source);
  }
  static scriptExecutor(): SourceScriptExecutor | undefined { return this.adapter.scripts; }
  static async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    const executor = this.adapter.scripts;
    if (!executor) throw new Error('Source script executor is not installed');
    return executor.evaluate(script, sourceUrl, timingId);
  }
  static async withWeb<T>(sourceUrl: string, action: () => Promise<T>): Promise<T> {
    const session = this.adapter.web;
    return session ? session.run(sourceUrl, action) : action();
  }
  static bindSource(source: BookSource, target: BookSource): void {
    this.adapter.state?.bindSource(source, target);
  }
  static setError(source: BookSource, message: string): void {
    if (this.adapter.state) this.adapter.state.setError(source, message);
    else AppStorage.setOrCreate('bookSourceStageLastError', message);
  }
  static getError(source: BookSource): string {
    return this.adapter.state ? this.adapter.state.getError(source) :
      AppStorage.get<string>('bookSourceStageLastError') || '';
  }
  static id(source: BookSource | null): number { return this.adapter.diagnostics?.id(source) || 0; }
  static end(id: number, stage: string, startedAt: number, details: string = ''): void {
    this.adapter.diagnostics?.end(id, stage, startedAt, details);
  }
  static isCancelled(source: BookSource | null): boolean {
    return this.adapter.requests?.isCancelled(source) || false;
  }
  static priority(source: BookSource | null): number { return this.adapter.requests?.priority(source) ?? 1; }
  static enqueue(key: string, source: BookSource, cancelCheck?: () => boolean): SourceRateWaiter {
    const scheduler = this.adapter.requests;
    if (!scheduler) return new DefaultRateWaiter(cancelCheck);
    const waiter = scheduler.enqueue(key, source, cancelCheck);
    this.waiterOwners.set(waiter, scheduler);
    return waiter;
  }
  static first(key: string, waiter: SourceRateWaiter): boolean {
    return this.waiterOwners.get(waiter)?.first(key, waiter) ?? true;
  }
  static remove(key: string, waiter: SourceRateWaiter): void {
    try { this.waiterOwners.get(waiter)?.remove(key, waiter); }
    finally { this.waiterOwners.delete(waiter); }
  }
}
