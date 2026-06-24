/**
 * 内置源注册入口
 *
 * 启动时调用 registerBuiltInSources() 一次。
 * 之后 SourceDataService.getSources() 会自动包含所有内置源。
 */

import { BuiltInSourceRegistry } from './BuiltInSourceRegistry';

import { TingYouFM } from './sources/TingYouFM';
import { Maoyan } from './sources/Maoyan';
import { Api69TextBuiltInSource } from './sources/Api69TextBuiltInSource';

let registered = false;

export function registerBuiltInSources(): void {
  if (registered) {
    return;
  }
  registered = true;

  // 天下书音(m.shuyinfm.com)线路已失效,改用听友FM(www.tingyou.fm)
  BuiltInSourceRegistry.register(TingYouFM);
  BuiltInSourceRegistry.register(Maoyan);
  BuiltInSourceRegistry.register(new Api69TextBuiltInSource());

}
