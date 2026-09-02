import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../main/ets/model/LocalRuleSource';
import { JsonObj } from '../main/ets/service/builtin/JsonValue';
import { TingYouDeviceFingerprint } from
  '../main/ets/service/rulesource/tingyou/TingYouDeviceFingerprint';
import { TingYouSourceAdapter } from
  '../main/ets/service/rulesource/tingyou/TingYouSourceAdapter';
import { TingYouSourceIdentity } from
  '../main/ets/service/rulesource/tingyou/TingYouSourceIdentity';

export default function tingYouExternalSourceTest() {
  describe('TingYouExternalSource', () => {
    it('recognizes only imported TingYou hosts and valid chapter routes', 0, () => {
      expect(TingYouSourceIdentity.isSourceUrl('https://tingyou.fm')).assertTrue();
      expect(TingYouSourceIdentity.isSourceUrl('https://www.tingyou.fm/')).assertTrue();
      expect(TingYouSourceIdentity.isSourceUrl('https://tingyou.fm.example.com')).assertFalse();
      expect(TingYouSourceIdentity.isSourceUrl('https://tingyou.fm:443')).assertFalse();
      const address = TingYouSourceIdentity.parseChapterAddress(
        'https://tingyou.fm/audios/4111454221/1');
      expect(address !== undefined).assertTrue();
      expect(address?.albumId ?? 0).assertEqual(4111454221);
      expect(address?.chapterIndex ?? 0).assertEqual(1);
      expect(TingYouSourceIdentity.parseChapterAddress(
        'https://example.com/audios/4111454221/1') === undefined).assertTrue();
      expect(TingYouSourceIdentity.parseAlbumId(
        'https://tingyou.fm/albums/4111454221')).assertEqual(4111454221);
      expect(TingYouSourceIdentity.parseAlbumId(
        'https://www.tingyou.fm/albums/4111454221/?from=search')).assertEqual(4111454221);
      expect(TingYouSourceIdentity.parseAlbumId(
        'https://example.com/albums/4111454221') === undefined).assertTrue();
    });

    it('matches the verified DFP key and cookie vector', 0, async () => {
      const keyHex = await TingYouDeviceFingerprint.deriveKeyHexForDate('20260902');
      const cookie = await TingYouDeviceFingerprint.buildCookieForDate('20260902');
      expect(keyHex).assertEqual('28b7ff8202f413c795d2ada14b4751a6');
      expect(cookie).assertEqual(
        'dfp=f-c29eu:f-st5TBUScXWWEUSsRwO9kCLQ5dCbBkSgMQQYAFzaQ8Co=');
    });

    it('resolves audio only for an enabled TingYou audio rule source', 0, () => {
      const source = LocalRuleSource.descriptor('https://tingyou.fm', '听友FM');
      source.bookSourceType = 1;
      expect(TingYouSourceAdapter.canResolve(
        source, 'https://tingyou.fm/audios/4111454221/1')).assertTrue();
      source.bookSourceType = 0;
      expect(TingYouSourceAdapter.canResolve(
        source, 'https://tingyou.fm/audios/4111454221/1')).assertFalse();
    });

    it('maps album API category status and episode count independently', 0, () => {
      const payload = new JsonObj(JSON.parse('{"title":"测试专辑","author":"作者",' +
        '"teller":"演播者","cover_url":"https://file.tingyou8.vip/cover.jpeg",' +
        '"type":"恐怖惊悚","cat":"有声小说","status":0,"count":1502,' +
        '"synopsis":"=.="}') as Object);
      const info = TingYouSourceAdapter.mapAlbumInfo(payload, 7792611164);
      expect(info !== null).assertTrue();
      expect(info?.kind ?? '').assertEqual('恐怖惊悚');
      expect(info?.completed ?? false).assertTrue();
      expect(info?.wordCount ?? '').assertEqual('1502');
      expect(info?.author ?? '').assertEqual('作者');
      expect(info?.coverUrl ?? '').assertEqual('https://file.tingyou8.vip/cover.jpeg');
      expect(info?.intro ?? 'not-empty').assertEqual('');
      expect(info?.tocUrl ?? '').assertEqual('https://tingyou.fm/albums/7792611164');
    });
  });
}
