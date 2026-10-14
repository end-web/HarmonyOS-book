/**
 * Cooperative main-thread scheduling primitives.
 *
 * These helpers do not move CPU work to another thread. They keep the ArkUI event loop responsive
 * while a legacy synchronous pipeline is being migrated to Worker/TaskPool execution.
 */
export class CooperativeCancellationToken {
  private cancelledValue: boolean = false;
  private cancelReasonValue: string = '';

  cancel(reason: string = '任务已取消'): void {
    this.cancelledValue = true;
    this.cancelReasonValue = reason || '任务已取消';
  }

  isCancelled(): boolean {
    return this.cancelledValue;
  }

  reason(): string {
    return this.cancelReasonValue || '任务已取消';
  }

  throwIfCancelled(): void {
    if (this.cancelledValue) throw new Error(this.reason());
  }
}

export class CooperativeTimeSlice {
  private readonly budgetMs: number;
  private sliceStartedAt: number = Date.now();
  private operationCount: number = 0;

  constructor(budgetMs: number = 6) {
    this.budgetMs = Math.max(1, Math.min(Math.round(budgetMs), 12));
  }

  elapsedMs(): number {
    return Math.max(0, Date.now() - this.sliceStartedAt);
  }

  async checkpoint(token: CooperativeCancellationToken | null = null,
    force: boolean = false): Promise<boolean> {
    if (token) token.throwIfCancelled();
    this.operationCount++;
    if (!force && this.elapsedMs() < this.budgetMs) return false;
    await CooperativeScheduler.yieldToEventLoop();
    this.sliceStartedAt = Date.now();
    if (token) token.throwIfCancelled();
    return true;
  }

  operations(): number {
    return this.operationCount;
  }
}

export class CooperativeScheduler {
  static readonly DEFAULT_UI_SLICE_MS: number = 6;
  static readonly SLOW_OPERATION_MS: number = 16;
  static readonly DANGEROUS_OPERATION_MS: number = 50;

  static createTimeSlice(budgetMs: number = CooperativeScheduler.DEFAULT_UI_SLICE_MS): CooperativeTimeSlice {
    return new CooperativeTimeSlice(budgetMs);
  }

  static async yieldToEventLoop(): Promise<void> {
    // A zero-delay timer may be coalesced into the same native timer task on HarmonyOS and does
    // not reliably reset the foreground watchdog. One millisecond creates a real scheduling gap.
    await new Promise<void>((resolve) => setTimeout(resolve, 1));
  }

  static async yieldToNextUiFrame(): Promise<void> {
    // Long catalog batches can keep promise continuations inside one native uv_timer_task even
    // though they contain short zero/one-millisecond yields. Crossing a frame boundary gives
    // ArkUI and the foreground watchdog an observable scheduling gap.
    await new Promise<void>((resolve) => setTimeout(resolve, 16));
  }

  static reportSynchronousOperation(label: string, elapsedMs: number, detail: string = ''): void {
    if (elapsedMs < CooperativeScheduler.SLOW_OPERATION_MS) return;
    const suffix = detail ? ` ${detail}` : '';
    if (elapsedMs >= CooperativeScheduler.DANGEROUS_OPERATION_MS) {
      console.warn(`[MainThreadGuard] dangerous ${label}: ${elapsedMs}ms${suffix}`);
    } else {
      console.info(`[MainThreadGuard] slow ${label}: ${elapsedMs}ms${suffix}`);
    }
  }
}
