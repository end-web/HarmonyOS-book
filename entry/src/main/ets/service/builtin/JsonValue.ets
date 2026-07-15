/** 轻量 JSON 访问器，避免业务代码反复进行空值和类型判断。 */
export class JsonObj {
  raw: Record<string, Object>;

  constructor(value: Object | null | undefined) {
    this.raw = value === undefined || value === null ? {} as Record<string, Object>
      : value as Record<string, Object>;
  }

  has(key: string): boolean {
    const value = this.raw[key];
    return value !== undefined && value !== null;
  }

  getString(key: string, fallback: string = ''): string {
    const value = this.raw[key];
    return value === undefined || value === null ? fallback : String(value);
  }

  optString(key: string, fallback: string = ''): string {
    return this.getString(key, fallback);
  }

  getInt(key: string, fallback: number = 0): number {
    const value = this.raw[key];
    if (value === undefined || value === null) return fallback;
    const parsed = Number(value);
    return Number.isNaN(parsed) ? fallback : Math.trunc(parsed);
  }

  optInt(key: string, fallback: number = 0): number {
    return this.getInt(key, fallback);
  }

  getObj(key: string): JsonObj {
    return new JsonObj(this.raw[key]);
  }

  getArr(key: string): JsonArr {
    return new JsonArr(this.raw[key]);
  }
}

export class JsonArr {
  raw: Object[];

  constructor(value: Object | null | undefined) {
    this.raw = Array.isArray(value) ? value as Object[] : [];
  }

  length(): number {
    return this.raw.length;
  }

  getObj(index: number): JsonObj {
    return new JsonObj(this.raw[index]);
  }

  getString(index: number, fallback: string = ''): string {
    const value = this.raw[index];
    return value === undefined || value === null ? fallback : String(value);
  }
}
