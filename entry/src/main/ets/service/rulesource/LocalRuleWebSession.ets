class LocalRuleWebSessionWaiter {
  id: number = 0;
  timer: number = 0;
  resolve: (id: number) => void = (_id: number): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
}

/** ArkWeb incognito cookies are process-wide. Login and rendering must hold the same lease. */
export class LocalRuleWebSession {
  private static sequence: number = 0;
  private static owner: number = 0;
  private static queue: LocalRuleWebSessionWaiter[] = [];

  static acquire(timeout: number): Promise<number> {
    if (LocalRuleWebSession.queue.length >= 32) return Promise.reject(new Error('网页会话等待任务过多'));
    const id = ++LocalRuleWebSession.sequence;
    if (LocalRuleWebSession.owner === 0) {
      LocalRuleWebSession.owner = id;
      return Promise.resolve(id);
    }
    return new Promise<number>((resolve, reject) => {
      const task = new LocalRuleWebSessionWaiter();
      task.id = id;
      task.resolve = resolve;
      task.reject = reject;
      task.timer = setTimeout(() => {
        LocalRuleWebSession.queue = LocalRuleWebSession.queue.filter(item => item !== task);
        reject(new Error('网页会话等待超时'));
      }, Math.max(1, timeout));
      LocalRuleWebSession.queue.push(task);
    });
  }

  static release(id: number): void {
    if (id === 0 || LocalRuleWebSession.owner !== id) return;
    LocalRuleWebSession.owner = 0;
    const next = LocalRuleWebSession.queue.shift();
    if (next === undefined) return;
    clearTimeout(next.timer);
    LocalRuleWebSession.owner = next.id;
    next.resolve(next.id);
  }
}
