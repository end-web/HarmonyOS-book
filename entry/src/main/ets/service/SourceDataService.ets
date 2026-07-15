/**
 * 内置音频源数据入口。
 *
 * 应用不再读取或保存用户规则源，调用方始终只能获得已注册的内置音频源。
 */
import { BookSource } from '../model/BookSource';
import { BuiltInSourceRegistry } from './builtin/BuiltInSourceRegistry';

export class SourceDataService {
  static getSources(): Promise<BookSource[]> {
    return Promise.resolve(BuiltInSourceRegistry.materialize());
  }

  static async getEnabledSources(): Promise<BookSource[]> {
    return SourceDataService.getSources();
  }
}
