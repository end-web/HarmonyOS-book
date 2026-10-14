/** Numeric correlation only: never log source URLs, script bodies, headers or content. */
export class LightSourceTiming {
  private static serial: number = 0;
  private static contexts = new WeakMap<Object, number>();
  static next(): number { return ++this.serial; }
  static bind(target: Object, id: number): void { if (id > 0) this.contexts.set(target, id); }
  static id(target: Object | null | undefined): number { return target ? this.contexts.get(target) || 0 : 0; }
  static copy(source: Object, target: Object): void { this.bind(target, this.id(source)); }
  static end(id: number, stage: string, startedAt: number, detail: string = ''): void {
    if (id <= 0) return;
    console.info(`[LightTiming] id=${id} stage=${stage} elapsedMs=${Math.max(0, Date.now() - startedAt)} ${detail}`);
  }
}
