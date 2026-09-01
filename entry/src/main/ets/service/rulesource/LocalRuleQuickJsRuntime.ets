import { JSBoundedExecutionResult, JSContext, JSRuntimeOptions } from '@devzeng/quickjs';
import { taskpool } from '@kit.ArkTS';

@Concurrent
function runBoundedQuickJs(script: string, sourceUrl: string, timeoutMs: number,
  maxPendingJobs: number, memoryLimitBytes: number, stackLimitBytes: number): string {
  const options = new JSRuntimeOptions();
  options.memoryLimitBytes = memoryLimitBytes;
  options.stackLimitBytes = stackLimitBytes;
  const context = new JSContext(options);
  try {
    const nativeResult: JSBoundedExecutionResult = context.evaluateBounded(
      script, sourceUrl, timeoutMs, maxPendingJobs);
    return `{"success":${nativeResult.success},"value":${JSON.stringify(nativeResult.value)},` +
      `"error":${JSON.stringify(nativeResult.error)},"timedOut":${nativeResult.timedOut},` +
      `"elapsedMs":${nativeResult.elapsedMs},"pendingJobs":${nativeResult.pendingJobs}}`;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error || 'QuickJS 执行失败');
    return `{"success":false,"value":"","error":${JSON.stringify(message)},` +
      `"timedOut":false,"elapsedMs":0,"pendingJobs":0}`;
  } finally {
    context.release();
  }
}

/** 单次 QuickJS 执行参数。所有预算还会在 native 调用前被收紧到安全范围。 */
export class LocalRuleQuickJsRequest {
  script: string = '';
  sourceUrl: string = 'local-rule';
  timeoutMs: number = 1000;
  maxPendingJobs: number = 8;
  memoryLimitBytes: number = 64 * 1024 * 1024;
  stackLimitBytes: number = 256 * 1024;
}

/** 与 QuickJS 类型解耦的结果，业务层不会获得 context 或原生 value handle。 */
export class LocalRuleQuickJsResult {
  success: boolean = false;
  value: string = '';
  errorMessage: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
  pendingJobs: number = 0;

  static failed(message: string): LocalRuleQuickJsResult {
    const result = new LocalRuleQuickJsResult();
    result.errorMessage = message;
    return result;
  }
}

/**
 * 不可信书源脚本的最小 QuickJS 门面。
 *
 * 每次调用在 taskpool 中创建独立 context，仅走原生 interrupt 支持的 evaluateBounded，
 * 并在 finally 中释放。
 * 此门面不提供 evaluateScript、JSValue、网络、Cookie、文件或数据库桥接能力。
 */
export class LocalRuleQuickJsRuntime {
  private static readonly MAX_SCRIPT_CHARS: number = 12 * 1024 * 1024;
  private static readonly MAX_SOURCE_URL_CHARS: number = 512;
  private static readonly MIN_TIMEOUT_MS: number = 1;
  private static readonly MAX_TIMEOUT_MS: number = 5000;
  private static readonly MAX_PENDING_JOBS: number = 32;
  private static readonly MIN_MEMORY_BYTES: number = 1024 * 1024;
  private static readonly MAX_MEMORY_BYTES: number = 64 * 1024 * 1024;
  private static readonly MIN_STACK_BYTES: number = 64 * 1024;
  private static readonly MAX_STACK_BYTES: number = 1024 * 1024;

  static async execute(request: LocalRuleQuickJsRequest): Promise<LocalRuleQuickJsResult> {
    if (request.script.trim().length === 0) {
      return LocalRuleQuickJsResult.failed('QuickJS 脚本不能为空');
    }
    if (request.script.length > LocalRuleQuickJsRuntime.MAX_SCRIPT_CHARS) {
      return LocalRuleQuickJsResult.failed('QuickJS 输入超过 12 MiB 执行预算');
    }

    const options = new JSRuntimeOptions();
    options.memoryLimitBytes = LocalRuleQuickJsRuntime.clamp(request.memoryLimitBytes,
      LocalRuleQuickJsRuntime.MIN_MEMORY_BYTES, LocalRuleQuickJsRuntime.MAX_MEMORY_BYTES);
    options.stackLimitBytes = LocalRuleQuickJsRuntime.clamp(request.stackLimitBytes,
      LocalRuleQuickJsRuntime.MIN_STACK_BYTES, LocalRuleQuickJsRuntime.MAX_STACK_BYTES);
    const timeoutMs = LocalRuleQuickJsRuntime.clamp(request.timeoutMs,
      LocalRuleQuickJsRuntime.MIN_TIMEOUT_MS, LocalRuleQuickJsRuntime.MAX_TIMEOUT_MS);
    const maxPendingJobs = LocalRuleQuickJsRuntime.clamp(request.maxPendingJobs,
      0, LocalRuleQuickJsRuntime.MAX_PENDING_JOBS);
    const sourceUrl = LocalRuleQuickJsRuntime.normalizeSourceUrl(request.sourceUrl);
    try {
      const execution: Promise<Object> = taskpool.execute(runBoundedQuickJs,
        request.script, sourceUrl, timeoutMs, maxPendingJobs,
        options.memoryLimitBytes, options.stackLimitBytes);
      return LocalRuleQuickJsRuntime.parseResult(String(await execution));
    } catch (error) {
      if (error instanceof Error) {
        return LocalRuleQuickJsResult.failed(error.message || 'QuickJS 执行失败');
      }
      return LocalRuleQuickJsResult.failed(String(error || 'QuickJS 执行失败'));
    }
  }

  private static parseResult(payload: string): LocalRuleQuickJsResult {
    try {
      const parsed = JSON.parse(payload) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return LocalRuleQuickJsResult.failed('QuickJS 返回格式无效');
      }
      const record = parsed as Record<string, Object>;
      const result = new LocalRuleQuickJsResult();
      result.success = record['success'] === true;
      result.value = String(record['value'] ?? '');
      result.errorMessage = String(record['error'] ?? '');
      result.timedOut = record['timedOut'] === true;
      result.elapsedMs = Number(record['elapsedMs'] ?? 0);
      result.pendingJobs = Number(record['pendingJobs'] ?? 0);
      return result;
    } catch (_error) {
      return LocalRuleQuickJsResult.failed('QuickJS 返回格式无效');
    }
  }

  private static normalizeSourceUrl(value: string): string {
    const normalized = value.trim() || 'local-rule';
    return normalized.substring(0, LocalRuleQuickJsRuntime.MAX_SOURCE_URL_CHARS);
  }

  private static clamp(value: number, minValue: number, maxValue: number): number {
    if (!Number.isFinite(value)) return minValue;
    return Math.max(minValue, Math.min(maxValue, Math.floor(value)));
  }
}
