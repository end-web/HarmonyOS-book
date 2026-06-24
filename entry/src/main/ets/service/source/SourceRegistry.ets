/**
 * SourceRegistry - 源注册表
 *
 * 管理所有 JSON 配置源的加载和查询
 */

import { SourceDefinition } from './SourceDefinition';
import { SourceEngine } from './SourceEngine';
import { Api69TextSource } from './registry/Api69TextSource';

interface SourceRegistryEntry {
  definition: SourceDefinition;
  engine: SourceEngine;
}

class SourceRegistryClass {
  private sources: Map<string, SourceRegistryEntry> = new Map();

  constructor() {
    this.loadBuiltInSources();
  }

  private loadBuiltInSources(): void {
    // 加载 69 书吧 APP API 文本源
    this.register(Api69TextSource);

    // 后续其他源在这里添加：
    // this.register(biquConfig as SourceDefinition);
    // this.register(tingyouConfig as SourceDefinition);
  }

  register(def: SourceDefinition): void {
    const engine = new SourceEngine(def);
    this.sources.set(def.id, { definition: def, engine });
  }

  getEngine(sourceId: string): SourceEngine | undefined {
    return this.sources.get(sourceId)?.engine;
  }

  getDefinition(sourceId: string): SourceDefinition | undefined {
    return this.sources.get(sourceId)?.definition;
  }

  getAllDefinitions(): SourceDefinition[] {
    return Array.from(this.sources.values()).map(e => e.definition);
  }

  has(sourceId: string): boolean {
    return this.sources.has(sourceId);
  }
}

export const SourceRegistry = new SourceRegistryClass();
