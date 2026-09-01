import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../main/ets/model/LocalRuleSource';
import {
  ShuShanApiBusinessError,
  ShuShanApiClient,
  ShuShanCatalogItemDto
} from '../main/ets/service/rulesource/shushan/ShuShanApiClient';
import { ShuShanSourceAdapter } from '../main/ets/service/rulesource/shushan/ShuShanSourceAdapter';
import { ShuShanRoute } from '../main/ets/service/rulesource/shushan/ShuShanSourceIdentity';

const SEARCH_RESPONSE_FIXTURE: string = '{"isSuccess":true,"error":"success","data":[' +
  '{"title":"小说结果","author":"作者甲","book_url":"novel-book",' +
  '"source":"番茄小说","tab":"novel","tags":"完结,玄幻"},' +
  '{"title":"听书结果","author":"主播乙","book_url":"audio-book",' +
  '"source":"番茄听书","tab":"audio","tags":"有声"}' +
  ']}';

const DETAIL_RESPONSE_FIXTURE: string = '{"code":200,"message":"请求成功","data":{' +
  '"title":"书山详情","author":"作者","book_url":"provider-book",' +
  '"bookid":"7659683388898413630","source":"番茄小说","tab":"novel"}}';

const CATALOG_RESPONSE_FIXTURE: string = '{"code":200,"message":"success","data":[' +
  '{"url":"book_id=1&item_id=9007199254740993","title":"第一章",' +
  '"cid":"9007199254740993","tag":"1000字","isVolume":false,"isVip":true,"isPay":false}' +
  ']}';

export default function shuShanSourceAdapterTest() {
  describe('ShuShanSourceAdapter', () => {
    it('maps novel and audio search items without network requests', 0, () => {
      const response = ShuShanApiClient.parseSearchResponse(SEARCH_RESPONSE_FIXTURE);
      const source = LocalRuleSource.descriptor('书山聚合', '书山聚合');
      const novel = ShuShanSourceAdapter.mapSearchItem(source, response.items[0]);
      const audio = ShuShanSourceAdapter.mapSearchItem(source, response.items[1]);
      expect(novel !== undefined).assertTrue();
      expect(audio !== undefined).assertTrue();
      if (novel !== undefined && audio !== undefined) {
        expect(novel.contentType).assertEqual('text');
        expect(novel.completed).assertTrue();
        expect(audio.contentType).assertEqual('audio');
        expect(ShuShanRoute.parse(novel.bookUrl).bookUrl).assertEqual('novel-book');
        expect(ShuShanRoute.parse(audio.bookUrl).provider).assertEqual('番茄听书');
      }
    });

    it('keeps detail book id and catalog chapter id as strings', 0, () => {
      const detail = ShuShanApiClient.parseDetailResponse(DETAIL_RESPONSE_FIXTURE).detail;
      expect(detail.bookId).assertEqual('7659683388898413630');
      expect(detail.bookUrl).assertEqual('provider-book');

      const catalog = ShuShanApiClient.parseCatalogResponse(CATALOG_RESPONSE_FIXTURE);
      expect(catalog.items.length).assertEqual(1);
      expect(catalog.items[0].chapterId).assertEqual('9007199254740993');
      expect(catalog.items[0].isVip).assertTrue();
    });

    it('builds Fanqie novel content request parameters', 0, () => {
      const route = ShuShanRoute.parse(ShuShanRoute.chapter(
        'novel', '番茄小说', 'provider-book', 'book-1', '书名',
        'book_id=book-1&item_id=item-1', '9007199254740993', ''));
      const request = ShuShanApiClient.createContentRequest(route);
      expect(request.path).assertEqual('/content');
      expect(request.method).assertEqual('POST');
      expect(request.audio).assertFalse();
      expect(request.body !== undefined).assertTrue();
      if (request.body !== undefined) {
        expect(String(request.body['book_id'])).assertEqual('book-1');
        expect(String(request.body['item_id'])).assertEqual('item-1');
        expect(String(request.body['cid'])).assertEqual('9007199254740993');
        expect(String(request.body['version'])).assertEqual('12');
      }
    });

    it('builds Fanqie and Shuqi direct audio requests', 0, () => {
      const fanqie = ShuShanRoute.parse(ShuShanRoute.chapter(
        'audio', '番茄听书', 'provider-book', 'book-1', '书名',
        'book_id=book-1&item_id=item-1', '1', ''));
      const fanqieRequest = ShuShanApiClient.createContentRequest(fanqie);
      expect(fanqieRequest.method).assertEqual('GET');
      expect(fanqieRequest.audio).assertTrue();
      expect(fanqieRequest.path).assertEqual('/audio?tone_id=1&item_ids=item-1');

      const shuqi = ShuShanRoute.parse(ShuShanRoute.chapter(
        'audio', '书旗听书', 'provider-book', 'book-2', '书名',
        'item_ids=item-2', '2', ''));
      const shuqiRequest = ShuShanApiClient.createContentRequest(shuqi);
      expect(shuqiRequest.method).assertEqual('GET');
      expect(shuqiRequest.path)
        .assertEqual('/audio?bookid=book-2&item_ids=item-2&tone_id=yifei');
    });

    it('keeps audio catalog chapters that only provide cid', 0, () => {
      const route = ShuShanRoute.parse(ShuShanRoute.catalog(
        'audio', '喜马拉雅', 'provider-book', '', '斗破苍穹', ''));
      const item = new ShuShanCatalogItemDto();
      item.title = '第一章';
      item.chapterId = '9007199254740993';
      const mapped = ShuShanSourceAdapter.mapCatalogItem(route, item);
      expect(mapped !== undefined).assertTrue();
      if (mapped !== undefined) {
        const chapterRoute = ShuShanRoute.parse(mapped.url);
        expect(chapterRoute.chapterId).assertEqual('9007199254740993');
        expect(chapterRoute.chapterUrl).assertEqual('cid=9007199254740993');
        const request = ShuShanApiClient.createContentRequest(chapterRoute);
        expect(request.body !== undefined).assertTrue();
        if (request.body !== undefined) {
          expect(String(request.body['cid'])).assertEqual('9007199254740993');
          expect(String(request.body['url'])).assertEqual('provider-book');
        }
      }
    });

    it('accepts plain text and safely decodes standard Base64 text', 0, async () => {
      const plain = await ShuShanApiClient.parseContentResponse(
        '{"code":200,"data":{"content":"第一章\\n这是正文。"}}');
      expect(plain.content).assertContain('这是正文');

      const encoded = await ShuShanApiClient.parseContentResponse(
        '{"code":200,"data":{"content":"56ys5LiA56ugCui/meaYr+ato+aWh+OAgg=="}}');
      expect(encoded.content).assertEqual('第一章\n这是正文。');
    });

    it('rejects pseudo encrypted gibberish instead of exposing it as text', 0, async () => {
      let thrown = false;
      let code = 0;
      const gibberish = 'AbCd=EfGhIjKlMnOpQrStUvWxYz0123456789+/'.repeat(4);
      try {
        await ShuShanApiClient.normalizeContent(gibberish);
      } catch (error) {
        thrown = true;
        if (error instanceof ShuShanApiBusinessError) code = error.code;
      }
      expect(thrown).assertTrue();
      expect(code).assertEqual(401);
    });

    it('extracts the real main_url from an audio response', 0, () => {
      const response = ShuShanApiClient.parseAudioResponse(
        '{"status":0,"code":0,"data":[' +
        '{"main_url":"https://cdn.example.com/audio/001.mp3?token=signed"}]}');
      expect(response.audioUrl)
        .assertEqual('https://cdn.example.com/audio/001.mp3?token=signed');
      expect(ShuShanApiClient.isHttpMediaUrl(response.audioUrl)).assertTrue();
    });
  });
}
