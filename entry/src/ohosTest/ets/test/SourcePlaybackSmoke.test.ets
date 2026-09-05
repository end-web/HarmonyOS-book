import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../../../main/ets/model/LocalRuleSource';
import { LocalRuleDispatcher } from '../../../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRuleSourceImportParser } from '../../../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { HttpClient } from '../../../main/ets/service/http/HttpClient';

export default function sourcePlaybackSmokeTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const chapterUrl = parameters['-s playbackChapterUrl'] ?? parameters['playbackChapterUrl'] ?? '';
  const keyword = parameters['-s playbackKeyword'] ?? parameters['playbackKeyword'] ?? '';
  if (!chapterUrl && !keyword) return;
  describe('SourcePlaybackSmoke', () => {
    it('loads the resolved audio and advances playback before and after pause', 0, async () => {
      const sourceUrl = parameters['-s playbackSourceUrl'] ?? parameters['playbackSourceUrl'] ?? '';
      const importUrl = parameters['-s playbackImportUrl'] ?? parameters['playbackImportUrl'] ?? '';
      let source = LocalRuleSource.descriptor(sourceUrl, 'Playback fixture');
      source.bookSourceType = 1;
      if (importUrl) {
        const response = await HttpClient.get(importUrl);
        const imported = LocalRuleSourceImportParser.parse(response).sources.find(item => item.bookSourceUrl === sourceUrl);
        expect(imported !== undefined).assertTrue();
        if (imported === undefined) return;
        source = imported;
      }
      let target = chapterUrl;
      let variables: Record<string, string> = {};
      if (keyword) {
        const books = await LocalRuleDispatcher.searchForHealthCheck(source, keyword);
        expect(books.length > 0).assertTrue();
        if (books.length === 0) return;
        const book = books[0];
        const info = await LocalRuleDispatcher.getBookInfo(source, book.bookUrl, book.variables ?? {});
        expect(info !== null).assertTrue();
        if (info === null) return;
        const chapters = await LocalRuleDispatcher.getBookToc(source, info.tocUrl || book.bookUrl, info.variables ?? {});
        const chapter = chapters.find(item => !item.isVolume && item.url.length > 0);
        expect(chapter !== undefined).assertTrue();
        if (chapter === undefined) return;
        target = chapter.url;
        variables = chapter.variables ?? {};
      }
      const result = await LocalRuleDispatcher.resolveContent(source, target, variables);
      expect(new RegExp('^https?://').test(result.audioUrl)).assertTrue();
      const player = await media.createAVPlayer();
      let timer = -1;
      try {
        const prepared = new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
          timer = setTimeout(() => { reject(new Error('Audio preparation timed out')); }, 30000);
          player.on('error', (error: BusinessError) => { reject(new Error(`AVPlayer ${error.code}: ${error.message}`)); });
          player.on('stateChange', (state: media.AVPlayerState) => {
            if (state === 'initialized') player.prepare().catch((error: Error) => { reject(error); });
            if (state === 'prepared') resolve();
          });
        });
        await player.setMediaSource(media.createMediaSourceWithUrl(result.audioUrl, result.requestHeaders));
        await prepared;
        clearTimeout(timer);
        expect(player.duration > 0).assertTrue();
        player.setVolume(0);
        await player.play();
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 1600); });
        const position = player.currentTime;
        expect(position > 0).assertTrue();
        await player.pause();
        await player.play();
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 1100); });
        expect(player.currentTime > position).assertTrue();
        abilityDelegatorRegistry.getAbilityDelegator().printSync(
          `[PlaybackSmoke] duration=${player.duration} position=${player.currentTime} resume=true\n`);
      } finally {
        clearTimeout(timer);
        await player.release();
      }
    });
  });
}
