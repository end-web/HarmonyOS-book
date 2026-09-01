import { describe, it, expect } from '@ohos/hypium';
import {
  OnlineTextMeasuredLine,
  OnlineTextPageNavigator,
  OnlineTextPage,
  OnlineTextPaginator
} from '../main/ets/service/text/OnlineTextPaginator';

export default function onlineTextPaginatorTest() {
  describe('OnlineTextPaginator', () => {
    it('keeps page offsets continuous and covers the complete chapter', 0, () => {
      const content = 'abcdefghij';
      const lines: OnlineTextMeasuredLine[] = [
        OnlineTextMeasuredLine.of(0, 10),
        OnlineTextMeasuredLine.of(2, 10),
        OnlineTextMeasuredLine.of(4, 10),
        OnlineTextMeasuredLine.of(6, 10),
        OnlineTextMeasuredLine.of(8, 10)
      ];
      const pages = OnlineTextPaginator.paginateMeasuredLines(content, lines, 20);
      expect(pages.length).assertEqual(3);
      expect(pages[0].startOffset).assertEqual(0);
      expect(pages[0].endOffset).assertEqual(pages[1].startOffset);
      expect(pages[1].endOffset).assertEqual(pages[2].startOffset);
      expect(pages[2].endOffset).assertEqual(content.length);
      expect(pages[0].text + pages[1].text + pages[2].text).assertEqual(content);
    });

    it('restores the page containing a saved character offset', 0, () => {
      const content = 'abcdefghij';
      const pages: OnlineTextPage[] = [
        OnlineTextPage.of(content, 0, 4),
        OnlineTextPage.of(content, 4, 8),
        OnlineTextPage.of(content, 8, 10)
      ];
      expect(OnlineTextPaginator.pageIndexForOffset(pages, 3)).assertEqual(0);
      expect(OnlineTextPaginator.pageIndexForOffset(pages, 4)).assertEqual(1);
      expect(OnlineTextPaginator.pageIndexForOffset(pages, 100)).assertEqual(2);
    });

    it('normalizes common html chapter bodies without merging paragraphs', 0, () => {
      const content = '<p>第一段&nbsp;正文</p><div>第二段</div><br/>第三段';
      const normalized = OnlineTextPaginator.normalizeContent(content);
      expect(normalized).assertContain('第一段 正文');
      expect(normalized).assertContain('\n第二段');
      expect(normalized).assertContain('\n第三段');
    });

    it('returns a stable empty page for an empty chapter', 0, () => {
      const lines: OnlineTextMeasuredLine[] = [];
      const pages = OnlineTextPaginator.paginateMeasuredLines('', lines, 100);
      expect(pages.length).assertEqual(1);
      expect(pages[0].startOffset).assertEqual(0);
      expect(pages[0].endOffset).assertEqual(0);
      expect(pages[0].text).assertEqual('');
    });

    it('moves within a chapter before crossing chapter boundaries', 0, () => {
      const next = OnlineTextPageNavigator.next(2, 1, 4, 6);
      expect(next.chapterIndex).assertEqual(2);
      expect(next.pageIndex).assertEqual(2);
      expect(next.openLastPage).assertFalse();
      const previous = OnlineTextPageNavigator.previous(2, 2);
      expect(previous.chapterIndex).assertEqual(2);
      expect(previous.pageIndex).assertEqual(1);
    });

    it('opens the first or last page when crossing chapters', 0, () => {
      const next = OnlineTextPageNavigator.next(2, 3, 4, 6);
      expect(next.chapterIndex).assertEqual(3);
      expect(next.pageIndex).assertEqual(0);
      expect(next.openLastPage).assertFalse();
      const previous = OnlineTextPageNavigator.previous(2, 0);
      expect(previous.chapterIndex).assertEqual(1);
      expect(previous.openLastPage).assertTrue();
    });

    it('does not move beyond the beginning or end of the book', 0, () => {
      const beginning = OnlineTextPageNavigator.previous(0, 0);
      expect(beginning.moved).assertFalse();
      expect(beginning.chapterIndex).assertEqual(0);
      expect(beginning.pageIndex).assertEqual(0);
      const end = OnlineTextPageNavigator.next(5, 3, 4, 6);
      expect(end.moved).assertFalse();
      expect(end.chapterIndex).assertEqual(5);
      expect(end.pageIndex).assertEqual(3);
    });
  });
}
