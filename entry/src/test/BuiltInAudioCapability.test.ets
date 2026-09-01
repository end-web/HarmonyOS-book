import { describe, it, expect } from '@ohos/hypium';
import {
  BuiltInBookDetail, BuiltInCategory, BuiltInCategoryMenu, BuiltInSearchResult,
  HomeBlock, IBuiltInSource
} from '../main/ets/service/builtin/IBuiltInSource';
import { BuiltInDispatcher } from '../main/ets/service/builtin/BuiltInDispatcher';
import { BuiltInSourceRegistry } from '../main/ets/service/builtin/BuiltInSourceRegistry';
import { registerBuiltInSources } from '../main/ets/service/builtin';

class TestBuiltInAudioSource implements IBuiltInSource {
  readonly id: string;
  readonly name: string = 'Test audio source';
  readonly url: string = 'https://audio.test';
  readonly desc: string = 'test';
  readonly searchable: boolean = false;
  readonly audioResolveTimeoutMs?: number;
  prepareCalls: number = 0;

  constructor(id: string, timeoutMs?: number) {
    this.id = id;
    this.audioResolveTimeoutMs = timeoutMs;
  }

  async search(_keywords: string, _page: number): Promise<BuiltInSearchResult> {
    return new BuiltInSearchResult();
  }

  async getCategoryMenus(): Promise<BuiltInCategoryMenu[]> {
    return [];
  }

  async getCategoryList(url: string): Promise<BuiltInCategory> {
    return new BuiltInCategory([], 1, 1, url, '');
  }

  async getBookDetail(_bookUrl: string, _loadEpisodes: boolean,
    _loadFullPages: boolean): Promise<BuiltInBookDetail> {
    return new BuiltInBookDetail();
  }

  async prepareAudio(): Promise<void> {
    this.prepareCalls++;
  }

  async getAudioUrl(chapterUrl: string): Promise<string> {
    return chapterUrl;
  }

  getAudioHeaders(_audioUrl: string): Record<string, string> {
    return {};
  }

  async getHomeBlocks(): Promise<HomeBlock[]> {
    return [];
  }
}

export default function builtInAudioCapabilityTest() {
  describe('BuiltIn audio capability', () => {
    it('registers required production sources with unique stable identities', 0, () => {
      registerBuiltInSources();
      const sources = BuiltInSourceRegistry.all();

      expect(BuiltInSourceRegistry.get('huan_fm') !== undefined).assertTrue();
      expect(BuiltInSourceRegistry.isBuiltIn('builtin://eprendre/huan_fm')).assertTrue();
      expect(BuiltInSourceRegistry.all().length).assertEqual(1);

      const ids = new Set<string>();
      const urls = new Set<string>();
      for (const source of sources) {
        const sourceUrl = BuiltInSourceRegistry.toBookSource(source).bookSourceUrl;
        expect(ids.has(source.id)).assertFalse();
        expect(urls.has(sourceUrl)).assertFalse();
        ids.add(source.id);
        urls.add(sourceUrl);
      }
    });

    it('dispatches prewarming and source-specific timeout', 0, async () => {
      const plugin = new TestBuiltInAudioSource('test_audio_capability_timed', 35000);
      BuiltInSourceRegistry.register(plugin);
      const source = BuiltInSourceRegistry.toBookSource(plugin);

      await BuiltInDispatcher.prepareAudio(source.bookSourceUrl);

      expect(plugin.prepareCalls).assertEqual(1);
      expect(BuiltInDispatcher.getAudioResolveTimeoutMs(source, 15000)).assertEqual(35000);
    });

    it('keeps the fallback timeout when a source does not configure one', 0, () => {
      const plugin = new TestBuiltInAudioSource('test_audio_capability_default');
      BuiltInSourceRegistry.register(plugin);
      const source = BuiltInSourceRegistry.toBookSource(plugin);

      expect(BuiltInDispatcher.getAudioResolveTimeoutMs(source, 15000)).assertEqual(15000);
    });
  });
}
