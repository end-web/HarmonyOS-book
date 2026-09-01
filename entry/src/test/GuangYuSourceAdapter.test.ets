import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';
import {
  GuangYuApiBusinessError,
  GuangYuApiClient
} from '../main/ets/service/rulesource/guangyu/GuangYuApiClient';
import { GuangYuAuthService } from '../main/ets/service/rulesource/guangyu/GuangYuAuthService';
import { RuleSourceAccountService } from '../main/ets/service/rulesource/RuleSourceAccountService';
import { NativeRuleSourceDispatcher } from '../main/ets/service/rulesource/NativeRuleSourceDispatcher';
import { GuangYuSourceAdapter } from '../main/ets/service/rulesource/guangyu/GuangYuSourceAdapter';
import {
  GuangYuRoute,
  GuangYuRouteKind,
  GuangYuSourceIdentity
} from '../main/ets/service/rulesource/guangyu/GuangYuSourceIdentity';

const GUANG_YU_SOURCE_FIXTURE: string = '[{' +
  '"bookSourceName":"光遇聚合测试源","bookSourceUrl":"光遇聚合","bookSourceType":0,' +
  '"searchUrl":"<js>return BaseUrl()</js>",' +
  '"loginUi":[{"name":"邮箱"}],"loginCheckJs":"java.getCookie(\\"qttoken\\")",' +
  '"jsLib":"function BaseUrl(){return \\"http://127.0.0.1\\"}",' +
  '"ruleSearch":{"bookList":"$.data[*]","name":"$.book_name","bookUrl":"$.book_url"}' +
  '}]';

const SEARCH_RESPONSE_FIXTURE: string = '{"code":0,"msg":"ok","data":[' +
  '{"book_name":"小说结果","book_id":"novel-1","source":"番茄","tab":"小说"},' +
  '{"book_name":"听书结果","book_id":"audio-1","source":"有声库","tab":"听书"}' +
  ']}';

const DETAIL_RESPONSE_FIXTURE: string = '{"code":0,"data":{' +
  '"book_name":"听书详情","book_id":"audio-1","source":"有声库","tab":"听书",' +
  '"book_tts":"可选音色","book_tts_dice":{"主播甲":17,"主播乙":"42"}' +
  '}}';

const CATALOG_RESPONSE_FIXTURE: string = '{"code":0,"data":[' +
  '{"title":"第一章","item_id":"9007199254740993","source":"有声库","tab":"听书"},' +
  '{"title":"第二章","item_id":7,"source":"有声库","tab":"听书"}' +
  ']}';

export default function guangYuSourceAdapterTest() {
  describe('GuangYuSourceAdapter', () => {
    it('round trips opaque book catalog and chapter routes', 0, () => {
      const book = GuangYuRoute.parse(GuangYuRoute.book(' 小说 ', '起点/中文网', 'book id?#'));
      expect(book.kind).assertEqual(GuangYuRouteKind.BOOK);
      expect(book.tab).assertEqual('小说');
      expect(book.provider).assertEqual('起点/中文网');
      expect(book.bookId).assertEqual('book id?#');

      const catalog = GuangYuRoute.parse(
        GuangYuRoute.catalog('听书', '有声/库', 'audio-1', ' 17 '));
      expect(catalog.kind).assertEqual(GuangYuRouteKind.CATALOG);
      expect(catalog.tab).assertEqual('听书');
      expect(catalog.provider).assertEqual('有声/库');
      expect(catalog.bookId).assertEqual('audio-1');
      expect(catalog.toneId).assertEqual('17');

      const chapter = GuangYuRoute.parse(
        GuangYuRoute.chapter('听书', '有声/库', 'audio-1', 'chapter/第一章', '42'));
      expect(chapter.kind).assertEqual(GuangYuRouteKind.CHAPTER);
      expect(chapter.itemId).assertEqual('chapter/第一章');
      expect(chapter.toneId).assertEqual('42');
    });

    it('keeps novel and audio type on each parsed search item', 0, () => {
      const response = GuangYuApiClient.parseSearchResponse(SEARCH_RESPONSE_FIXTURE);
      expect(response.items.length).assertEqual(2);
      expect(GuangYuSourceIdentity.contentType(response.items[0].tab)).assertEqual('text');
      expect(GuangYuSourceIdentity.contentType(response.items[1].tab)).assertEqual('audio');
    });

    it('parses detail tone options and catalog item ids as strings', 0, () => {
      const detail = GuangYuApiClient.parseDetailResponse(DETAIL_RESPONSE_FIXTURE).detail;
      expect(detail.bookTts).assertEqual('可选音色');
      expect(detail.toneOptions['主播甲']).assertEqual('17');
      expect(detail.toneOptions['主播乙']).assertEqual('42');
      expect(GuangYuSourceAdapter.detailToneId('4')).assertEqual('4');
      expect(GuangYuSourceAdapter.detailToneId('42')).assertEqual('42');
      expect(GuangYuSourceAdapter.detailToneId('')).assertEqual('4');

      const catalog = GuangYuApiClient.parseCatalogResponse(CATALOG_RESPONSE_FIXTURE);
      expect(catalog.items.length).assertEqual(2);
      expect(catalog.items[0].itemId).assertEqual('9007199254740993');
      expect(catalog.items[1].itemId).assertEqual('7');
    });

    it('accepts a media URL with surrounding whitespace for normalization', 0, () => {
      const response = GuangYuApiClient.parseContentResponse(
        '{"code":0,"title":"第一章","content":"  https://cdn.example.com/audio/001.mp3?token=signed  \\n"}');
      expect(GuangYuApiClient.isHttpMediaUrl(response.content)).assertTrue();
      expect(response.content.trim()).assertEqual('https://cdn.example.com/audio/001.mp3?token=signed');
    });

    it('matches GuangYu review and god options for novel content requests', 0, () => {
      const reviewSources: string[] = [
        '番茄', '七猫', '塔读', 'QQ阅读', 'svip_QQ阅读', '书旗', 'svip_书旗'
      ];
      for (const source of reviewSources) {
        const reviewRequest = GuangYuApiClient.createContentRequest(GuangYuRoute.parse(
          GuangYuRoute.chapter('小说', source, 'review-book', 'review-chapter', '4')));
        expect(reviewRequest.path).assertEqual('/content?review=1');
      }

      const godSources: string[] = ['番茄', '七猫', 'svip_书旗'];
      for (const source of godSources) {
        const godRequest = GuangYuApiClient.createContentRequest(GuangYuRoute.parse(
          GuangYuRoute.chapter('小说', source, 'god-book', 'god-chapter', '4')));
        expect(godRequest.body.god).assertTrue();
      }

      const fanQieRoute = GuangYuRoute.parse(
        GuangYuRoute.chapter('小说', '番茄', 'novel-1', 'chapter-1', '4'));
      const fanQieRequest = GuangYuApiClient.createContentRequest(fanQieRoute);
      expect(fanQieRequest.path).assertEqual('/content?review=1');
      expect(fanQieRequest.body.item_id).assertEqual('chapter-1');
      expect(fanQieRequest.body.source).assertEqual('番茄');
      expect(fanQieRequest.body.tab).assertEqual('小说');
      expect(fanQieRequest.body.tone_id).assertEqual('4');
      expect(fanQieRequest.body.variable).assertEqual('{"custom":""}');
      expect(fanQieRequest.body.version).assertEqual('26.8.28');
      expect(fanQieRequest.body.god).assertTrue();

      const taDuRequest = GuangYuApiClient.createContentRequest(GuangYuRoute.parse(
        GuangYuRoute.chapter('小说', '塔读', 'novel-2', 'chapter-2', '4')));
      expect(taDuRequest.path).assertEqual('/content?review=1');
      expect(taDuRequest.body.god).assertFalse();

      const regularRequest = GuangYuApiClient.createContentRequest(GuangYuRoute.parse(
        GuangYuRoute.chapter('小说', '起点', 'novel-3', 'chapter-3', '4')));
      expect(regularRequest.path).assertEqual('/content');
      expect(regularRequest.body.god).assertFalse();
    });

    it('keeps audio content requests on the plain endpoint without god mode', 0, () => {
      const request = GuangYuApiClient.createContentRequest(GuangYuRoute.parse(
        GuangYuRoute.chapter('听书', '番茄', 'audio-1', 'track-1', '17')));
      expect(request.path).assertEqual('/content');
      expect(request.body.god).assertFalse();
      expect(request.body.tone_id).assertEqual('17');
      expect(request.body.variable).assertEqual('{"custom":"17"}');
    });

    it('keeps the server message when a successful content response is empty', 0, () => {
      const withMessage = GuangYuApiClient.parseContentResponse(
        '{"code":0,"msg":"请先登录后重试","content":"\\n"}');
      expect(GuangYuSourceAdapter.contentErrorMessage(withMessage)).assertEqual('请先登录后重试');

      const withoutMessage = GuangYuApiClient.parseContentResponse(
        '{"code":0,"content":"\\n"}');
      expect(GuangYuSourceAdapter.contentErrorMessage(withoutMessage)).assertEqual('光遇聚合内容为空');
    });

    it('throws a business error when the API code is not zero', 0, () => {
      let thrown = false;
      let code = 0;
      let message = '';
      try {
        GuangYuApiClient.parseContentResponse('{"code":1008,"msg":"今日次数已用完","content":"ignored"}');
      } catch (error) {
        thrown = true;
        if (error instanceof GuangYuApiBusinessError) {
          code = error.code;
          message = error.message;
        }
      }
      expect(thrown).assertTrue();
      expect(code).assertEqual(1008);
      expect(message).assertEqual('今日次数已用完');
    });

    it('stops health retries and normalizes GuangYu rate limit errors', 0, () => {
      const rateLimitError = new GuangYuApiBusinessError(
        -1, GuangYuApiClient.businessErrorMessage(-1, '您的访问速度过快！普通用户限制为 3 次/30 秒'));
      expect(rateLimitError.message).assertEqual('光遇聚合访问过快，请等待 30 秒后再试');
      expect(GuangYuSourceAdapter.isNonRetryableHealthError(rateLimitError)).assertTrue();
      expect(NativeRuleSourceDispatcher.isNonRetryableHealthError('光遇聚合', rateLimitError)).assertTrue();
      expect(NativeRuleSourceDispatcher.usesSingleContentHealthCheck('光遇聚合')).assertTrue();
      expect(NativeRuleSourceDispatcher.usesSingleContentHealthCheck('书山聚合')).assertFalse();
    });

    it('imports the native GuangYu source without marking it incompatible', 0, () => {
      const report = LocalRuleSourceImportParser.parse(GUANG_YU_SOURCE_FIXTURE);
      expect(report.sources.length).assertEqual(1);
      expect(report.unsupportedCount).assertEqual(0);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].enabled).assertTrue();
    });

    it('recognizes the qttoken produced by embedded web login', 0, () => {
      const validHeaders: string[] = [
        'cf_clearance=verified; qttoken=abcdefghijk=signature; deviceId=device-1'
      ];
      const invalidHeaders: string[] = ['qttoken=short; deviceId=device-1'];
      expect(GuangYuAuthService.hasWebLoginCookie(validHeaders)).assertTrue();
      expect(GuangYuAuthService.hasWebLoginCookie(invalidHeaders)).assertFalse();
      expect(GuangYuAuthService.hasWebLoginCookie([])).assertFalse();
    });

    it('keeps the main account login separate from registration', 0, () => {
      expect(RuleSourceAccountService.usesWebLogin('光遇聚合')).assertFalse();
      expect(GuangYuApiClient.preferredHost()).assertEqual('https://v1.gyks.cf');
      expect(GuangYuAuthService.webLoginUrl()).assertEqual('https://v1.gyks.cf/login');
      expect(GuangYuAuthService.registrationUrl()).assertEqual('https://v1.gyks.cf/register');
      const loginUrls = GuangYuAuthService.webLoginUrls();
      expect(loginUrls.length).assertEqual(7);
      expect(loginUrls[0]).assertEqual('https://v1.gyks.cf/login');
      expect(loginUrls[6]).assertEqual('https://v7.gyks.cf/login');
    });
  });
}
