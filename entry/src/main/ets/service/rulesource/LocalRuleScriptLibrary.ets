import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleHttpClient } from './LocalRuleHttpClient';

class LocalRuleLibraryCache {
  code: string = '';
  expires: number = 0;
}

export class LocalRuleScriptLibrary {
  private static cache: Map<string, LocalRuleLibraryCache> = new Map<string, LocalRuleLibraryCache>();

  static async load(source: LocalRuleSource, variables: Record<string, string>): Promise<string> {
    const definition = source.jsLib.trim();
    let urls: string[] = [];
    if (new RegExp('^https?://[^\\s]+$').test(definition)) urls = [definition];
    else if (definition.startsWith('[')) {
      try {
        const values: Object[] = JSON.parse(definition);
        if (Array.isArray(values) && values.every(value => typeof value === 'string' && new RegExp('^https?://[^\\s]+$').test(String(value)))) {
          urls = values.map(value => String(value));
        }
      } catch (_error) { /* Inline libraries may begin with an array expression. */ }
    }
    if (urls.length === 0) return source.jsLib;
    if (urls.length > 8) throw new Error('远程 JS 库数量超过 8 个');
    const code: string[] = [];
    let total = 0;
    for (const address of urls) {
      const cacheKey = JSON.stringify([source.bookSourceUrl, address, variables['__header'] ?? source.header,
        variables['__sourceLoginHeader'] ?? '', await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl, address)]);
      let cached = LocalRuleScriptLibrary.cache.get(cacheKey);
      if (cached === undefined || cached.expires < Date.now()) {
        const response = await LocalRuleHttpClient.fetch(source, address, variables);
        if (!response.ok) throw new Error(`远程 JS 库请求失败：${response.errorMessage}`);
        if (response.body.length > 2 * 1024 * 1024) throw new Error('远程 JS 库超过 2 MiB');
        cached = new LocalRuleLibraryCache();
        cached.code = response.body;
        cached.expires = Date.now() + 5 * 60 * 1000;
        if (LocalRuleScriptLibrary.cache.size >= 8) LocalRuleScriptLibrary.cache.clear();
        LocalRuleScriptLibrary.cache.set(cacheKey, cached);
      }
      total += cached.code.length;
      if (total > 2 * 1024 * 1024) throw new Error('JS 库总长度超过 2 MiB');
      code.push(cached.code);
    }
    return code.join('\n;\n');
  }
}
