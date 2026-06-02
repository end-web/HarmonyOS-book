/**
 * 内置源注册入口
 *
 * 启动时调用 registerBuiltInSources() 一次。
 * 之后 SourceDataService.getSources() 会自动包含所有内置源。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BuiltInSourceRegistry } from './BuiltInSourceRegistry';

import { TianXiaShuYin } from './sources/TianXiaShuYin';

let registered = false;

export function registerBuiltInSources(): void {
  if (registered) {
    hilog.info(0, 'BuiltInSrc', 'already registered, count=%{public}d', BuiltInSourceRegistry.all().length);
    return;
  }
  registered = true;

  BuiltInSourceRegistry.register(TianXiaShuYin);

  hilog.info(0, 'BuiltInSrc', 'registered done, count=%{public}d', BuiltInSourceRegistry.all().length);
}
