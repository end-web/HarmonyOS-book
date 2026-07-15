/**
 * 内置源注册入口
 *
 * 启动时调用 registerBuiltInSources() 一次。
 * 之后 SourceDataService.getSources() 会自动包含所有内置源。
 */

import { BuiltInSourceRegistry } from './BuiltInSourceRegistry';

import { ServerAudioSource } from './sources/ServerAudioSource';
import { TingYouFM } from './sources/TingYouFM';

let registered = false;

export function registerBuiltInSources(): void {
  if (registered) {
    return;
  }
  registered = true;

  BuiltInSourceRegistry.register(TingYouFM);
  BuiltInSourceRegistry.register(ServerAudioSource);
}
