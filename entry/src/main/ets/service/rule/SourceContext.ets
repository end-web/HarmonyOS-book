/**
 * SourceContext - 书源上下文（书源 JS 规则中的 source.xxx 访问）
 *
 * 支持：
 *  - source.key - 书源 URL（bookSourceUrl）
 *  - source.name - 书源名称
 *  - source.type - 书源类型（0=文本，1=音频）
 */

export interface BookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType?: number;
}

class SourceContextImpl {
  private currentSource: BookSource | null = null;

  setSource(source: BookSource): void {
    this.currentSource = source;
  }

  get key(): string {
    return this.currentSource?.bookSourceUrl || '';
  }

  get name(): string {
    return this.currentSource?.bookSourceName || '';
  }

  get type(): number {
    return this.currentSource?.bookSourceType || 0;
  }

  getSource(): BookSource | null {
    return this.currentSource;
  }
}

let globalContext: SourceContextImpl | null = null;

export function getSourceContext(): SourceContextImpl {
  if (!globalContext) {
    globalContext = new SourceContextImpl();
  }
  return globalContext;
}
