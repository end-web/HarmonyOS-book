import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';
import {
  ShuShanRoute,
  ShuShanRouteKind,
  ShuShanSourceIdentity
} from '../main/ets/service/rulesource/shushan/ShuShanSourceIdentity';

const SHU_SHAN_SOURCE_FIXTURE: string = '[{' +
  '"bookSourceName":"书山聚合测试源","bookSourceUrl":"书山聚合","bookSourceType":0,' +
  '"searchUrl":"<js>return getServerHost()</js>",' +
  '"loginUi":[{"name":"邮箱"},{"name":"密码"}],' +
  '"jsLib":"function getServerHost(){return \\"https://v1.vossc.com\\"}",' +
  '"ruleSearch":{"bookList":"$.data","name":"$.title","bookUrl":"$.book_url"}' +
  '}]';

export default function shuShanSourceIdentityTest() {
  describe('ShuShanSourceIdentity', () => {
    it('matches only the exact normalized source identifier', 0, () => {
      expect(ShuShanSourceIdentity.isSourceUrl('书山聚合')).assertTrue();
      expect(ShuShanSourceIdentity.isSourceUrl('  书山聚合  ')).assertTrue();
      expect(ShuShanSourceIdentity.isSourceUrl('书山聚合源')).assertFalse();
      expect(ShuShanSourceIdentity.isSourceUrl(undefined)).assertFalse();
    });

    it('round trips book catalog and chapter routes', 0, () => {
      const bookUrl = 'https://example.com/book/1?a=b';
      const book = ShuShanRoute.parse(ShuShanRoute.book('novel', '番茄小说', bookUrl, '测试 书'));
      expect(book.kind).assertEqual(ShuShanRouteKind.BOOK);
      expect(book.tab).assertEqual('novel');
      expect(book.provider).assertEqual('番茄小说');
      expect(book.bookUrl).assertEqual(bookUrl);
      expect(book.title).assertEqual('测试 书');

      const catalog = ShuShanRoute.parse(
        ShuShanRoute.catalog('audio', '番茄听书', bookUrl, '9007199254740993', '测试 书', '1'));
      expect(catalog.kind).assertEqual(ShuShanRouteKind.CATALOG);
      expect(catalog.tab).assertEqual('audio');
      expect(catalog.bookId).assertEqual('9007199254740993');
      expect(catalog.toneId).assertEqual('1');

      const chapter = ShuShanRoute.parse(
        ShuShanRoute.chapter('audio', '番茄听书', bookUrl, '9007199254740993',
          '测试 书', 'https://example.com/chapter/1?item_id=42', '42', '1'));
      expect(chapter.kind).assertEqual(ShuShanRouteKind.CHAPTER);
      expect(chapter.chapterUrl).assertEqual('https://example.com/chapter/1?item_id=42');
      expect(chapter.chapterId).assertEqual('42');
      expect(chapter.toneId).assertEqual('1');
    });

    it('rejects malformed internal routes', 0, () => {
      expect(ShuShanRoute.parse('https://example.com/book').kind).assertEqual(ShuShanRouteKind.INVALID);
      expect(ShuShanRoute.parse('ss://book/novel/provider').kind).assertEqual(ShuShanRouteKind.INVALID);
      expect(ShuShanRoute.parse('ss://chapter/audio/provider/%E0%A4%A').kind)
        .assertEqual(ShuShanRouteKind.INVALID);
    });

    it('imports the native ShuShan source without marking it incompatible', 0, () => {
      const report = LocalRuleSourceImportParser.parse(SHU_SHAN_SOURCE_FIXTURE);
      expect(report.sources.length).assertEqual(1);
      expect(report.unsupportedCount).assertEqual(0);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].enabled).assertTrue();
    });
  });
}
