export class LocalRuleDiagnosticEvent {
  level: string = 'info';
  stage: string = '';
  message: string = '';
  detail: string = '';
}

class LocalRuleDiagnosticSession {
  cancelled: boolean = false;
  startedAt: number = Date.now();
  count: number = 0;
  samples: Set<string> = new Set<string>();
  observer: (event: LocalRuleDiagnosticEvent) => void = () => {};
}

/** Per-run diagnostics stay isolated from normal reading and other source tests. */
export class LocalRuleDiagnostics {
  private static sessions: Map<string, LocalRuleDiagnosticSession> = new Map<string, LocalRuleDiagnosticSession>();
  private static sequence: number = 0;

  static open(observer: (event: LocalRuleDiagnosticEvent) => void): Record<string, string> {
    const id = `${Date.now()}-${LocalRuleDiagnostics.sequence++}`;
    const session = new LocalRuleDiagnosticSession();
    session.observer = observer;
    LocalRuleDiagnostics.sessions.set(id, session);
    return { '__traceId': id };
  }

  static close(variables: Record<string, string>): void {
    LocalRuleDiagnostics.sessions.delete(variables['__traceId'] ?? '');
  }

  static cancel(variables: Record<string, string>): void {
    const session = LocalRuleDiagnostics.sessions.get(variables['__traceId'] ?? '');
    if (session !== undefined) session.cancelled = true;
  }

  static check(variables: Record<string, string>): void {
    const session = LocalRuleDiagnostics.sessions.get(variables['__traceId'] ?? '');
    if (session === undefined) return;
    if (session.cancelled) throw new Error('调试已停止');
    if (Date.now() - session.startedAt > 180000) throw new Error('调试超过三分钟执行预算');
  }

  static record(variables: Record<string, string>, level: string, message: string, detail: string = ''): void {
    const session = LocalRuleDiagnostics.sessions.get(variables['__traceId'] ?? '');
    if (session === undefined || session.cancelled || session.count >= 150) return;
    if (level === 'info') {
      if (session.count >= 120) return;
      const sample = `${variables['__debugStage'] ?? ''}:${message}:${detail}`;
      if (session.samples.has(sample)) return;
      session.samples.add(sample);
    }
    session.count++;
    const event = new LocalRuleDiagnosticEvent();
    event.level = level;
    event.stage = variables['__debugStage'] ?? '';
    event.message = message;
    event.detail = LocalRuleDiagnostics.redact(detail).substring(0, 2048);
    session.observer(event);
  }

  static redact(value: string): string {
    return value.replace(new RegExp('([?&](?:token|access_token|password|secret|sign|ss|dev_id|deviceId)=)[^&\\s"]*', 'gi'),
      '$1[redacted]').replace(new RegExp('("(?:authorization|cookie|set-cookie|token|password|secret|ss)"\\s*:\\s*")[^"]*', 'gi'),
      '$1[redacted]');
  }
}
