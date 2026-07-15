export class AsyncSingleFlight<T> {
  private inFlight: Promise<T> | null = null;

  run(task: () => Promise<T>): Promise<T> {
    if (this.inFlight) return this.inFlight;
    const current = this.execute(task);
    this.inFlight = current;
    return current;
  }

  private async execute(task: () => Promise<T>): Promise<T> {
    // Defer task execution until run() has stored the Promise, so a synchronous
    // throw cannot leave a rejected Promise permanently assigned to inFlight.
    await Promise.resolve();
    try {
      return await task();
    } finally {
      this.inFlight = null;
    }
  }
}
