import { BookSource } from './model/data/Book';
import { NativeSourceSpec, NativeSourceDefinition } from './core/nativesource/NativeSourceSpec';
export class NativeSourceService {
  static toBookSource(definition: NativeSourceDefinition, existing: BookSource | null = null): BookSource {
    const source = existing ? Object.assign(new BookSource(), existing) : new BookSource();
    source.bookSourceUrl = definition.url;
    source.bookSourceName = definition.name;
    source.bookSourceGroup = definition.group || '';
    source.bookSourceComment = definition.comment || '';
    source.bookSourceType = NativeSourceSpec.bookSourceType(definition);
    source.concurrentRate = definition.rate || '';
    source.header = definition.headers && Object.keys(definition.headers).length > 0 ?
      JSON.stringify(definition.headers) : '';
    source.jsLib = NativeSourceSpec.pack(definition);
    source.searchUrl = definition.search ? NativeSourceSpec.SEARCH_MARKER : '';
    source.exploreUrl = definition.explore ? NativeSourceSpec.EXPLORE_MARKER : '';
    // 登录页地址放进 loginUrl，列表上的登录状态角标和 Cookie 同步沿用现有逻辑。
    source.loginUrl = definition.login ? definition.login.url : '';
    source.loginUi = '';
    source.loginCheckJs = '';
    source.rawSourceJson = '';
    source.bookUrlPattern = '';
    if (!existing) {
      source.enabled = definition.enabled !== false;
      source.enabledExplore = definition.enabledExplore !== false;
    }
    source.lastUpdateTime = Date.now();
    return source;
  }

  static importObject(value: Object, existing: BookSource | null = null): BookSource {
    return NativeSourceService.toBookSource(NativeSourceSpec.fromObject(value), existing);
  }
}
