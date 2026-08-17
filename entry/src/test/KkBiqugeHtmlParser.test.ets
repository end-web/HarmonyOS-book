import { describe, it, expect } from '@ohos/hypium';
import { KkBiqugeHtmlParser } from '../main/ets/service/text/KkBiqugeHtmlParser';

export default function kkBiqugeHtmlParserTest() {
  describe('KkBiqugeHtmlParser', () => {
    it('extracts the complete nested chapter body and resolves a relative next page', 0, () => {
      const html = '<div id="chaptercontent"><div id="booktxt">第一段<br/><div><p>第二段</p></div>第三段</div></div>' +
        '<a href="67606563_2.html" class="block" id="next_url"> 下一页</a>';
      const content = KkBiqugeHtmlParser.parseContent('第一章',
        'http://www.kkbiquge.net/166_166806/67606563.html', html).content;
      expect(content).assertContain('第一段');
      expect(content).assertContain('第二段');
      expect(content).assertContain('第三段');
      expect(KkBiqugeHtmlParser.nextContentUrl(
        'http://www.kkbiquge.net/166_166806/67606563.html', html))
        .assertEqual('http://www.kkbiquge.net/166_166806/67606563_2.html');
    });

    it('does not treat the next chapter link as a content page', 0, () => {
      const html = '<div id="booktxt">最后一页</div>' +
        '<a id="next_url" href="/166_166806/67606564.html">下一章</a>';
      expect(KkBiqugeHtmlParser.nextContentUrl(
        'http://www.kkbiquge.net/166_166806/67606563_2.html', html)).assertEqual('');
    });
  });
}
