/** 内置源与本地规则源的只读聚合入口。 */
import { BookSource } from '../model/BookSource';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';

export class SourceDataService {
  private static localSourceUrls: Set<string> = new Set();
  private static localSourcesByUrl: Map<string, LocalRuleSource> = new Map<string, LocalRuleSource>();

  static async getSources(): Promise<BookSource[]> {
    const builtIns: BookSource[] = BuiltInSourceRegistry.materialize();
    try {
      const localSources = await LocalRuleSourceRepository.getAll();
      const accepted = SourceDataService.acceptLocalSources(localSources);
      return builtIns.concat(accepted);
    } catch (error) {
      console.warn(`[SourceDataService] local rules unavailable: ${SourceDataService.errorMessage(error)}`);
      SourceDataService.localSourceUrls.clear();
      return builtIns;
    }
  }

  static async getEnabledSources(): Promise<BookSource[]> {
    const builtIns: BookSource[] = BuiltInSourceRegistry.materialize();
    try {
      const localSources = await LocalRuleSourceRepository.getAll();
      const accepted = SourceDataService.acceptLocalSources(localSources);
      const enabled: BookSource[] = [];
      for (const source of accepted) {
        if (source.isSearchEnabled()) enabled.push(source);
      }
      return builtIns.concat(enabled);
    } catch (error) {
      console.warn(`[SourceDataService] enabled local rules unavailable: ${SourceDataService.errorMessage(error)}`);
      return builtIns;
    }
  }

  /** 单源热路径：内置源只查内存注册表，本地规则源才访问独立数据库。 */
  static async getSourceByUrl(sourceUrl: string): Promise<BookSource | undefined> {
    const builtIn = BuiltInSourceRegistry.getByUrl(sourceUrl);
    if (builtIn !== undefined) return BuiltInSourceRegistry.toBookSource(builtIn);
    const cached = SourceDataService.localSourcesByUrl.get(sourceUrl);
    if (cached !== undefined) return cached;
    try {
      const localSource = await LocalRuleSourceRepository.getByUrl(sourceUrl);
      if (localSource === undefined || !SourceDataService.acceptLocalSource(localSource)) return undefined;
      SourceDataService.localSourcesByUrl.set(sourceUrl, localSource);
      SourceDataService.localSourceUrls.add(sourceUrl);
      return localSource;
    } catch (error) {
      console.warn(`[SourceDataService] source lookup failed: ${SourceDataService.errorMessage(error)}`);
      return undefined;
    }
  }

  /** 书源导入、更新、启停或删除后调用；下次读取会回到数据库最新定义。 */
  static invalidateLocalSources(sourceUrl: string = ''): void {
    if (sourceUrl.length > 0) {
      SourceDataService.localSourcesByUrl.delete(sourceUrl);
      SourceDataService.localSourceUrls.delete(sourceUrl);
      return;
    }
    SourceDataService.localSourcesByUrl.clear();
    SourceDataService.localSourceUrls.clear();
  }

  static isLocalRuleSource(sourceUrl: string): boolean {
    return SourceDataService.localSourceUrls.has(sourceUrl);
  }

  private static acceptLocalSources(sources: LocalRuleSource[]): LocalRuleSource[] {
    const accepted: LocalRuleSource[] = [];
    SourceDataService.localSourceUrls.clear();
    SourceDataService.localSourcesByUrl.clear();
    for (const source of sources) {
      if (!SourceDataService.acceptLocalSource(source)) continue;
      SourceDataService.localSourceUrls.add(source.bookSourceUrl);
      SourceDataService.localSourcesByUrl.set(source.bookSourceUrl, source);
      accepted.push(source);
    }
    return accepted;
  }

  private static acceptLocalSource(source: LocalRuleSource): boolean {
    return source.bookSourceUrl.length > 0 && !source.bookSourceUrl.startsWith('builtin://');
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}
