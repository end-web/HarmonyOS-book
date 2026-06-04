/**
 * SourceContext - 书源上下文（书源 JS 规则中的 source.xxx 访问）
 *
 * 支持：
 *  - source.key - 书源 URL（bookSourceUrl）
 *  - source.name - 书源名称
 *  - source.type - 书源类型（0=文本，1=音频）
 *  - source.getVariable() - 获取源变量（JSON 字符串）
 *  - source.setVariable(v) - 设置源变量
 */

import { SourceVariableStore } from '../SourceVariableStore';

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

  /**
   * source.getVariable() - 获取源变量
   * 返回存储的 JSON 字符串（Legado 约定）
   */
  getVariable(): string {
    if (!this.currentSource) return '';
    try {
      const vars = SourceVariableStore.getSourceVariables(this.currentSource.bookSourceUrl);
      return JSON.stringify(vars);
    } catch {
      return '';
    }
  }

  /**
   * source.setVariable(v) - 设置源变量
   * v 是 JSON 字符串（Legado 约定）
   */
  setVariable(v: string): void {
    if (!this.currentSource) return;
    try {
      const parsed = JSON.parse(v) as Record<string, Object>;
      const keys = Object.keys(parsed);
      for (const k of keys) {
        SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, k, parsed[k]);
      }
    } catch {
      // 如果不是 JSON，按单值存储
      SourceVariableStore.setSourceVariable(this.currentSource.bookSourceUrl, '_value', v);
    }
  }
}

let globalContext: SourceContextImpl | null = null;

export function getSourceContext(): SourceContextImpl {
  if (!globalContext) {
    globalContext = new SourceContextImpl();
  }
  return globalContext;
}
