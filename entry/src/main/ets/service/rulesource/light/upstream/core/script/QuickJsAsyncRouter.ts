import { QuickJsMigrationStore } from './QuickJsMigrationStore';
import { QuickJsObservationContext, QuickJsRuntimeMode, QuickJsRuntimeStatus } from './QuickJsRuntimeStatus';
import { QuickJsScriptRuntime, QuickJsShadowComparator } from './QuickJsScriptRuntime';

export type QuickJsLegacyEvaluator = () => Promise<string>;

/**
 * The authoritative async result router. Only pure expressions can enter QuickJS. All other
 * scripts, all host actions and every QuickJS failure continue through the supplied legacy path.
 */
export class QuickJsAsyncRouter {
  static async evaluate(expression: string, variables: Record<string, Object>,
    legacyEvaluator: QuickJsLegacyEvaluator, timeoutMs: number = 80,
    observation: QuickJsObservationContext | null = null): Promise<string> {
    const mode = QuickJsRuntimeStatus.getMode();
    const candidate = QuickJsRuntimeStatus.isHealthy() &&
      QuickJsScriptRuntime.isPureExpressionCandidate(expression);
    const fingerprint = QuickJsShadowComparator.fingerprint(expression);

    if (mode === QuickJsRuntimeMode.OFF || !candidate) return legacyEvaluator();
    if (mode === QuickJsRuntimeMode.SHADOW) {
      const legacyValue = await legacyEvaluator();
      QuickJsShadowComparator.compare(expression, variables, legacyValue, observation);
      return legacyValue;
    }

    const routeAllowed = !QuickJsMigrationStore.isCircuitOpen() &&
      (mode === QuickJsRuntimeMode.PREFER_QUICKJS ||
      (mode === QuickJsRuntimeMode.CANARY && QuickJsMigrationStore.isCanaryEligible(fingerprint)));
    if (!routeAllowed) return legacyEvaluator();

    const submitter = QuickJsRuntimeStatus.getAsyncSubmitter();
    if (!submitter) return legacyEvaluator();
    const quickResult = await submitter.execute(expression, JSON.stringify(variables), timeoutMs);
    if (quickResult.success && !quickResult.timedOut) {
      QuickJsMigrationStore.record('route-success', fingerprint, quickResult.elapsedMs);
      return quickResult.value;
    }
    QuickJsMigrationStore.record('route-fallback', fingerprint, quickResult.elapsedMs);
    return legacyEvaluator();
  }
}
