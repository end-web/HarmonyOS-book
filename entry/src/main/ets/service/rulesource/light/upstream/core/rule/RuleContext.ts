export class RuleContext {
  // Keys come from source rules. A prototype-free table keeps names such as `constructor` or
  // `__proto__` ordinary variables instead of resolving to members of Object.prototype.
  private vars: Record<string, string> = Object.create(null) as Record<string, string>;

  put(key: string, value: string): void {
    this.vars[key] = value;
  }

  get(key: string): string {
    return this.vars[key] || '';
  }

  has(key: string): boolean {
    return key in this.vars;
  }

  loadFromJson(json: string): void {
    try {
      const obj = JSON.parse(json) as Record<string, string>;
      // Only an object is a variable table; a bare string or array would be spread into index keys.
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) Object.assign(this.vars, obj);
    } catch (_) {}
  }

  toJson(): string {
    return JSON.stringify(this.vars);
  }

  toRecord(): Record<string, string> {
    return { ...this.vars };
  }

  /**
   * Return only state that must survive between rule stages.
   *
   * Source metadata and jsLib are seeded again for every execution. Persisting them in every
   * search item used to duplicate a 100-300 KiB jsLib dozens of times per source, producing very
   * large transient heaps during concurrent search/change-source operations.
   */
  toPersistentJson(): string {
    return JSON.stringify(this.toPersistentRecord());
  }

  toPersistentRecord(): Record<string, string> {
    const result: Record<string, string> = {};
    for (const key of Object.keys(this.vars)) {
      if (this.isSeededSourceKey(key)) continue;
      result[key] = this.vars[key] || '';
    }
    return result;
  }

  private isSeededSourceKey(key: string): boolean {
    return key === 'source.bookSourceUrl' || key === 'bookSourceUrl' ||
      key === 'source.bookSourceName' || key === 'bookSourceName' ||
      key === 'source.bookSourceGroup' || key === 'bookSourceGroup' ||
      key === 'source.bookSourceComment' || key === 'bookSourceComment' ||
      key === 'source.jsLib' || key === 'jsLib' || key === 'source.variable';
  }
}
