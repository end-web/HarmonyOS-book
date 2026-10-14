export enum QuickJsRuntimeMode {
  OFF = 'off',
  SHADOW = 'shadow',
  CANARY = 'canary',
  PREFER_QUICKJS = 'prefer-quickjs'
}

export class QuickJsObservationContext {
  sourceUrl: string = '';
  sourceName: string = '';
  stage: string = '';
  field: string = '';
}

export interface QuickJsShadowSubmitter {
  submit(expression: string, variablesJson: string, legacyValue: string,
    fingerprint: string, sample: number, observation: QuickJsObservationContext | null): boolean;
}

export class QuickJsAsyncExecutionResult {
  success: boolean = false;
  value: string = '';
  error: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
}

export interface QuickJsAsyncSubmitter {
  execute(expression: string, variablesJson: string, timeoutMs: number): Promise<QuickJsAsyncExecutionResult>;
}

/** Process-local gate. A native self-test must pass before source code can reach QuickJS. */
export class QuickJsRuntimeStatus {
  private static healthy: boolean = false;
  private static mode: QuickJsRuntimeMode = QuickJsRuntimeMode.SHADOW;
  private static shadowSubmitter: QuickJsShadowSubmitter | null = null;
  private static asyncSubmitter: QuickJsAsyncSubmitter | null = null;

  static markSelfTest(passed: boolean): void {
    QuickJsRuntimeStatus.healthy = passed;
  }

  static isHealthy(): boolean {
    return QuickJsRuntimeStatus.healthy;
  }

  static getMode(): QuickJsRuntimeMode {
    return QuickJsRuntimeStatus.mode;
  }

  static setMode(mode: QuickJsRuntimeMode): void {
    QuickJsRuntimeStatus.mode = mode;
  }

  static setShadowSubmitter(submitter: QuickJsShadowSubmitter | null): void {
    QuickJsRuntimeStatus.shadowSubmitter = submitter;
  }

  static getShadowSubmitter(): QuickJsShadowSubmitter | null {
    return QuickJsRuntimeStatus.shadowSubmitter;
  }

  static setAsyncSubmitter(submitter: QuickJsAsyncSubmitter | null): void {
    QuickJsRuntimeStatus.asyncSubmitter = submitter;
  }

  static getAsyncSubmitter(): QuickJsAsyncSubmitter | null {
    return QuickJsRuntimeStatus.asyncSubmitter;
  }
}
