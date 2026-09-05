import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { LocalRuleDispatcher } from '../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRuleStageExtractor } from '../main/ets/service/rulesource/LocalRuleStageExtractor';
import { LocalRuleJsonPath } from '../main/ets/service/rulesource/LocalRuleJsonPath';
import { LocalRuleScriptRuntime } from '../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleUrlAnalyzer } from '../main/ets/service/rulesource/LocalRuleUrlAnalyzer';

const JSON_SOURCE: string = '[{' +
  '"bookSourceName":"示例 API","bookSourceUrl":"https://api.example.com","bookSourceType":0,' +
  '"searchUrl":"/search?keyword={{key}}&page={{page}}",' +
  '"ruleSearch":{"bookList":"$.data.books[*]","name":"$.title",' +
  '"author":"$.author","bookUrl":"/book/{{$.id}}"},' +
  '"ruleBookInfo":{"tocUrl":"/book/{{$.id}}/chapters"},' +
  '"ruleToc":{"chapterList":"$.data.chapters[*]","chapterName":"$.title",' +
  '"chapterUrl":"/chapter/{{$.id}}"},"ruleContent":{"content":"$.data.content"}}]';

const AIJJXS_SOURCE: string = '[{' +
  '"bookSourceGroup":"小说","bookSourceName":"久久小说网","bookSourceType":0,' +
  '"bookSourceUrl":"https://www.aijjxs.com","enabled":true,"enabledCookieJar":true,' +
  '"header":"{\\"User-Agent\\":\\"Mozilla/5.0 Chrome/120.0.0.0 Mobile Safari/537.36\\"}",' +
  '"searchUrl":"https://www.aijjxs.com/e/search/index.php,' +
  '{\\"method\\":\\"POST\\",\\"body\\":\\"keyboard={{key}}&show=title,writer\\"}",' +
  '"ruleSearch":{"author":"@text##.*作者：","bookList":"div.searchTopic",' +
  '"bookUrl":"a.searchtitle@href","name":"a.searchtitle@text"},' +
  '"ruleBookInfo":{"author":".kv a@text","coverUrl":".pic img@src",' +
  '"intro":".intro-panel .desc@text","kind":".kv p:contains(分类)@text##.*：",' +
  '"name":"article.panel h3@text##《|》","tocUrl":"a:contains(在线阅读)@href"},' +
  '"ruleToc":{"chapterList":"ul.chapter-list li a","chapterName":"@text",' +
  '"chapterUrl":"@href"},"ruleContent":{"content":"#view_content_txt@html"}}]';

export default function localRuleRuntimeTest() {
  describe('LocalRuleRuntime', () => {
    it('imports a structured JSON source and expands its search URL', 0, () => {
      const report = LocalRuleSourceImportParser.parse(JSON_SOURCE);
      expect(report.sources.length).assertEqual(1);
      const source = report.sources[0];
      expect(source.validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      const variables: Record<string, string> = {};
      const plan = LocalRuleUrlAnalyzer.analyze(source, source.searchUrl, variables, '三体', 2);
      expect(plan.url).assertEqual('https://api.example.com/search?keyword=%E4%B8%89%E4%BD%93&page=2');
    });

    it('normalizes string, array and object source groups without object placeholders', 0, () => {
      const stringGroup = LocalRuleSourceImportParser.parse(JSON_SOURCE.replace(
        '"bookSourceName"', '"bookSourceGroup":"小说,精品","bookSourceName"')).sources[0];
      const arrayGroup = LocalRuleSourceImportParser.parse(JSON_SOURCE.replace(
        '"bookSourceName"', '"bookSourceGroup":["听书","精品"],"bookSourceName"')).sources[0];
      const objectGroup = LocalRuleSourceImportParser.parse(JSON_SOURCE.replace(
        '"bookSourceName"', '"bookSourceGroup":{"name":"有声","label":"备用"},"bookSourceName"')).sources[0];
      const invalidGroup = LocalRuleSourceImportParser.parse(JSON_SOURCE.replace(
        '"bookSourceName"', '"bookSourceGroup":"[object Object]","bookSourceName"')).sources[0];
      expect(stringGroup.bookSourceGroup).assertEqual('小说,精品');
      expect(arrayGroup.bookSourceGroup).assertEqual('听书 · 精品');
      expect(objectGroup.bookSourceGroup).assertEqual('有声 · 备用');
      expect(invalidGroup.bookSourceGroup).assertEqual('');
    });

    it('imports the aijjxs source and builds its POST search request', 0, () => {
      const report = LocalRuleSourceImportParser.parse(AIJJXS_SOURCE);
      expect(report.sources.length).assertEqual(1);
      const source: LocalRuleSource = report.sources[0];
      expect(source.bookSourceName).assertEqual('久久小说网');
      expect(source.ruleSearch.bookList).assertEqual('div.searchTopic');
      expect(source.ruleBookInfo.tocUrl).assertEqual('a:contains(在线阅读)@href');
      expect(source.ruleToc.chapterList).assertEqual('ul.chapter-list li a');
      expect(source.ruleContent.content).assertEqual('#view_content_txt@html');

      const variables: Record<string, string> = {};
      const plan = LocalRuleUrlAnalyzer.analyze(source, source.searchUrl, variables, '斗破苍穹', 1);
      expect(plan.url).assertEqual('https://www.aijjxs.com/e/search/index.php');
      expect(plan.method).assertEqual('POST');
      expect(String(plan.body)).assertEqual(
        'keyboard=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&show=title,writer');
      expect(plan.headers['User-Agent']).assertContain('Chrome/120.0.0.0');

      const ampersandPlan = LocalRuleUrlAnalyzer.analyze(
        source, source.searchUrl, variables, 'A&B', 1);
      expect(String(ampersandPlan.body)).assertEqual('keyboard=A%26B&show=title,writer');
      const plusPlan = LocalRuleUrlAnalyzer.analyze(
        source, source.searchUrl, variables, 'C++', 1);
      expect(String(plusPlan.body)).assertEqual('keyboard=C%2B%2B&show=title,writer');
    });

    it('keeps the aijjxs detail toc and content extraction contract', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(AIJJXS_SOURCE).sources[0];
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('a:contains(在线阅读)'))
        .assertEqual('a:contains(在线阅读)');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('ul.chapter-list li a'))
        .assertEqual('ul.chapter-list li a');
      expect(LocalRuleUrlAnalyzer.resolveUrl(
        'https://www.aijjxs.com/txt/13054.html', '/read/13054/'))
        .assertEqual('https://www.aijjxs.com/read/13054');
      expect(LocalRuleUrlAnalyzer.resolveUrl(
        'https://www.aijjxs.com/read/13054/', '/read/11/13054/2.html'))
        .assertEqual('https://www.aijjxs.com/read/11/13054/2.html');
      expect(LocalRuleStageExtractor.applyCleanup('《斗破苍穹之无上巅峰》', '《|》'))
        .assertEqual('斗破苍穹之无上巅峰');
      const detailDocument = LocalRuleStageExtractor.createDocument(
        '{"headings":["《斗破苍穹之无上巅峰》","内容简介","下载与说明"]}',
        'https://www.aijjxs.com/txt/13054.html');
      const variables: Record<string, string> = {};
      const detailName = await LocalRuleStageExtractor.extractFirst(
        detailDocument, '$.headings[*]##《|》', source, variables);
      expect(detailName).assertEqual('斗破苍穹之无上巅峰');
      const content = LocalRuleStageExtractor.stripHtml(
        '<p>萧炎，斗气大陆上的巅峰存在。</p><p>第一章飞升</p>');
      expect(content).assertEqual('萧炎，斗气大陆上的巅峰存在。\n\n第一章飞升');
      expect(source.ruleSearch.bookUrl).assertEqual('a.searchtitle@href');
    });

    it('extracts JSON list fields and resolves element URL templates', 0, async () => {
      const report = LocalRuleSourceImportParser.parse(JSON_SOURCE);
      const source: LocalRuleSource = report.sources[0];
      const payload = '{"data":{"books":[{"id":"42","title":"三体","author":"刘慈欣"}]}}';
      const document = LocalRuleStageExtractor.createDocument(payload,
        'https://api.example.com/search?keyword=test');
      const variables: Record<string, string> = {};
      const elements = await LocalRuleStageExtractor.selectList(
        document, source.ruleSearch.bookList, source, variables);
      expect(elements.length).assertEqual(1);
      const name = await LocalRuleStageExtractor.extract(
        elements[0], source.ruleSearch.name, source, variables);
      const bookUrl = await LocalRuleStageExtractor.extract(
        elements[0], source.ruleSearch.bookUrl, source, variables, true);
      expect(name).assertEqual('三体');
      expect(bookUrl).assertEqual('https://api.example.com/book/42');
    });

    it('expands zero-based page expressions used by search endpoints', 0, () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      source.searchUrl = '/search?keyword={{key}}&page={{page-1}}&next={{pageIndex+2}}';
      const variables: Record<string, string> = {};
      const plan = LocalRuleUrlAnalyzer.analyze(source, source.searchUrl, variables, '三体', 1);
      expect(plan.url).assertEqual(
        'https://api.example.com/search?keyword=%E4%B8%89%E4%BD%93&page=0&next=3');
    });

    it('flattens a JSON array selected directly as a book list', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const document = LocalRuleStageExtractor.createDocument(
        '{"bookList":[{"bookId":1,"bookName":"三体"},{"bookId":2,"bookName":"球状闪电"}]}',
        'https://api.example.com/search');
      const variables: Record<string, string> = {};
      const elements = await LocalRuleStageExtractor.selectList(
        document, '$.bookList', source, variables);
      expect(elements.length).assertEqual(2);
      const firstName = await LocalRuleStageExtractor.extract(
        elements[0], '$.bookName', source, variables);
      const secondName = await LocalRuleStageExtractor.extract(
        elements[1], '$.bookName', source, variables);
      expect(firstName).assertEqual('三体');
      expect(secondName).assertEqual('球状闪电');
    });

    it('normalizes legacy Legado CSS selectors', 0, () => {
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('a.0')).assertEqual('a:eq(0)');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('class.divbox tag.a.1'))
        .assertEqual('.divbox a:eq(1)');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('id.section-list tag.li tag.a'))
        .assertEqual('#section-list li a');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('.module ul li'))
        .assertEqual('.module ul li');
    });

    it('quotes unquoted CSS attribute values containing colons', 0, () => {
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('meta[property=og:image]'))
        .assertEqual('meta[property="og:image"]');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('meta[property=og:title]'))
        .assertEqual('meta[property="og:title"]');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector('meta[property="og:image"]'))
        .assertEqual('meta[property="og:image"]');
      expect(LocalRuleStageExtractor.normalizeLegacyCssSelector("meta[property='og:title']"))
        .assertEqual("meta[property='og:title']");
    });

    it('keeps script-dependent sources enabled for the isolated compatibility runtime', 0, () => {
      const value = JSON_SOURCE.replace('"ruleContent":{', '"jsLib":"java.ajax(url)","ruleContent":{');
      const report = LocalRuleSourceImportParser.parse(value);
      expect(report.sources.length).assertEqual(1);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].enabled).assertTrue();
    });

    it('runs ordinary code when jsLib only defines unused Java compatibility functions', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      source.jsLib = 'function legacyCipher(){return Packages.javax.crypto.Cipher.getInstance("AES");}';
      const variables: Record<string, string> = {};
      const value = await LocalRuleScriptRuntime.evaluate(
        '', 'local-rule', '"ok"', source, variables);
      expect(value).assertEqual('ok');
    });

    it('keeps unavailable platform references inert inside guarded branches', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const variables: Record<string, string> = {};
      const value = await LocalRuleScriptRuntime.evaluate(
        '', 'local-rule', 'typeof Packages.java.io === "undefined" && typeof Packages.java.lang.Runtime === "undefined" ' +
        '&& typeof fetch === "undefined" && typeof XMLHttpRequest === "undefined" ? "sandboxed" : "exposed"',
        source, variables);
      expect(value).assertEqual('sandboxed');
    });

    it('allows dynamic code inside the bounded QuickJS sandbox', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const variables: Record<string, string> = {};
      const value = await LocalRuleScriptRuntime.evaluate(
        '', 'local-rule', 'Function("return 1")()', source, variables);
      expect(value).assertEqual('1');
    });

    it('provides raw JSON and common Legado script globals', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const variables: Record<string, string> = {};
      variables['key'] = '三体';
      variables['page'] = '3';
      variables['title'] = '测试标题';
      const value = await LocalRuleScriptRuntime.evaluate(
        '{"name":"book"}', 'https://api.example.com/search',
        'var data=JSON.parse(result); data.name+"|"+(src===result)+"|"+key+"|"+page+"|"+url+"|"+title',
        source, variables);
      expect(value).assertEqual('book|true|三体|3|https://api.example.com/search|测试标题');
    });

    it('returns the completion value of multi statement scripts', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const variables: Record<string, string> = {};
      const value = await LocalRuleScriptRuntime.evaluate(
        '', 'local-rule', 'var first=20; var second=22; first+second', source, variables);
      expect(value).assertEqual('42');
    });

    it('evaluates JavaScript template expressions in source addresses', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const variables: Record<string, string> = {};
      const value = await LocalRuleScriptRuntime.resolveAddress(
        '/search?offset={{(page-1)*20}}&site={{source.getKey()}}', source, variables, '三体', 3);
      expect(value).assertEqual(
        '/search?offset=40&site=https://api.example.com');
    });

    it('accepts compact rule groups and source templates', 0, () => {
      const value = '[{' +
        '"bookSourceName":"紧凑规则","bookSourceUrl":"https://compact.example.com",' +
        '"searchUrl":"{{source.bookSourceUrl}}/search?q={{key}}",' +
        '"ruleSearch":"@{bookList=$.data[*];name=$.title;bookUrl=/book/{{$.id}}}",' +
        '"ruleBookInfo":"@{name=$.title;tocUrl=/toc/{{$.id}}}",' +
        '"ruleToc":"@{chapterList=$.items[*];chapterName=$.name;chapterUrl=$.url}",' +
        '"ruleContent":"@{content=$.content}"' +
        '}]';
      const report = LocalRuleSourceImportParser.parse(value);
      expect(report.sources.length).assertEqual(1);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].ruleSearch.bookList).assertEqual('$.data[*]');
      expect(report.sources[0].ruleSearch.bookUrl).assertEqual('/book/{{$.id}}');
      expect(report.sources[0].ruleContent.content).assertEqual('$.content');
    });

    it('keeps login extensions and non-search capabilities enabled', 0, () => {
      const value = '[{' +
        '"bookSourceName":"详情型漫画源","bookSourceUrl":"custom+https://comic.example.com",' +
        '"bookSourceType":2,"enabled":true,"loginUrl":"https://comic.example.com/login",' +
        '"loginUi":"[{\\"name\\":\\"账号\\"}]","loginCheckJs":"function check(){return true}",' +
        '"ruleBookInfo":{"name":"h1@text","tocUrl":"a.read@href"},' +
        '"ruleToc":{"chapterList":".chapters a","chapterName":"@text","chapterUrl":"@href"},' +
        '"ruleContent":{"content":".images@html"}' +
        '}]';
      const report = LocalRuleSourceImportParser.parse(value);
      expect(report.sources.length).assertEqual(1);
      expect(report.unsupportedCount).assertEqual(0);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].enabled).assertTrue();
      expect(report.sources[0].canExecute()).assertTrue();
      expect(report.sources[0].isSearchEnabled()).assertFalse();
      expect(report.sources[0].isText()).assertTrue();
    });

    it('supports JSONPath slices with omitted and negative bounds', 0, () => {
      const payload = '{"items":[0,1,2,3,4,5]}';
      const stepped = LocalRuleJsonPath.queryPayload(payload, '$.items[1:5:2]');
      expect(stepped.length).assertEqual(2);
      expect(LocalRuleJsonPath.valueToString(stepped[0])).assertEqual('1');
      expect(LocalRuleJsonPath.valueToString(stepped[1])).assertEqual('3');

      const negative = LocalRuleJsonPath.queryPayload(payload, '$.items[-4:-1]');
      expect(negative.length).assertEqual(3);
      expect(LocalRuleJsonPath.valueToString(negative[0])).assertEqual('2');
      expect(LocalRuleJsonPath.valueToString(negative[2])).assertEqual('4');

      const head = LocalRuleJsonPath.queryPayload(payload, '$.items[:3]');
      const tail = LocalRuleJsonPath.queryPayload(payload, '$.items[3:]');
      expect(head.length).assertEqual(3);
      expect(tail.length).assertEqual(3);
      expect(LocalRuleJsonPath.valueToString(tail[0])).assertEqual('3');

      const reverse = LocalRuleJsonPath.queryPayload(payload, '$.items[::-1]');
      expect(reverse.length).assertEqual(6);
      expect(LocalRuleJsonPath.valueToString(reverse[0])).assertEqual('5');
      expect(LocalRuleJsonPath.valueToString(reverse[5])).assertEqual('0');

      const reverseStep = LocalRuleJsonPath.queryPayload(payload, '$.items[5:0:-2]');
      expect(reverseStep.length).assertEqual(3);
      expect(LocalRuleJsonPath.valueToString(reverseStep[1])).assertEqual('3');

      const quotedProperty = LocalRuleJsonPath.queryPayload('{"a:b":[7]}', "$['a:b'][0]");
      expect(quotedProperty.length).assertEqual(1);
      expect(LocalRuleJsonPath.valueToString(quotedProperty[0])).assertEqual('7');
    });

    it('supports JSONPath logical comparison existence and regex filters', 0, () => {
      const payload = '{"items":[' +
        '{"id":1,"name":"科幻","score":8,"active":true},' +
        '{"id":2,"name":"小说精选","score":12,"active":true,"tag":"hot"},' +
        '{"id":3,"name":"NOVEL","score":30,"active":false,"blocked":true},' +
        '{"id":4,"name":"小说合集","score":22,"active":false}' +
        ']}';
      const combined = LocalRuleJsonPath.queryPayload(payload,
        '$.items[?((@.score >= 10 && @.active == true) || (@.name =~ /小说/i && !@.blocked))].id');
      expect(combined.length).assertEqual(2);
      expect(LocalRuleJsonPath.valueToString(combined[0])).assertEqual('2');
      expect(LocalRuleJsonPath.valueToString(combined[1])).assertEqual('4');

      const existing = LocalRuleJsonPath.queryPayload(payload, '$.items[?(@.tag)].id');
      expect(existing.length).assertEqual(1);
      expect(LocalRuleJsonPath.valueToString(existing[0])).assertEqual('2');

      const compared = LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score != 12 && @.score < 10)].id');
      expect(compared.length).assertEqual(1);
      expect(LocalRuleJsonPath.valueToString(compared[0])).assertEqual('1');

      const bounded = LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score > 8 && @.score <= 22)].id');
      expect(bounded.length).assertEqual(2);
      expect(LocalRuleJsonPath.valueToString(bounded[0])).assertEqual('2');
      expect(LocalRuleJsonPath.valueToString(bounded[1])).assertEqual('4');
    });

    it('persists @put values and resolves @get in the same rule context', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const document = LocalRuleStageExtractor.createDocument(
        '{"id":"book-42","title":"三体"}', 'https://api.example.com/book/42');
      const variables: Record<string, string> = {};
      const title = await LocalRuleStageExtractor.extract(
        document, '@put:{bookId:$.id}$.title', source, variables);
      const bookId = await LocalRuleStageExtractor.extract(
        document, '@get:{bookId}', source, variables);
      const chapterUrl = await LocalRuleStageExtractor.extract(
        document, '/chapter/@get:{bookId}/{{$.id}}', source, variables, true);
      expect(title).assertEqual('三体');
      expect(bookId).assertEqual('book-42');
      expect(chapterUrl).assertEqual('https://api.example.com/chapter/book-42/book-42');
    });

    it('accepts loose URL options and inline request headers', 0, () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      const address = '/search@Header:{"X-Trace":"inline"}@End,' +
        "{method:'POST',body:'q={{searchKeyRaw}}',headers:{Referer:'https://api.example.com/'},}";
      const variables: Record<string, string> = {};
      const plan = LocalRuleUrlAnalyzer.analyze(source, address, variables, '三体', 1);
      expect(plan.method).assertEqual('POST');
      expect(String(plan.body)).assertEqual('q=%E4%B8%89%E4%BD%93');
      expect(plan.headers['Referer']).assertEqual('https://api.example.com/');
      expect(plan.headers['X-Trace']).assertEqual('inline');
    });

    it('keeps structured request body keywords unescaped', 0, () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      source.header = '{"Referer":"{{baseUrl}}"}';
      const address = '/search,{"method":"POST","body":{' +
        '"searchTerms":"{{key}}","pageNum":"{{page}}"}}';
      const variables: Record<string, string> = {};
      const plan = LocalRuleUrlAnalyzer.analyze(source, address, variables, '斗破苍穹', 1);
      expect(plan.url).assertEqual('https://api.example.com/search');
      expect(JSON.stringify(plan.body)).assertEqual('{"searchTerms":"斗破苍穹","pageNum":"1"}');
      expect(plan.headers['Referer']).assertEqual('https://api.example.com/search');
    });

    it('returns local audio direct links without fetching them as chapter content', 0, async () => {
      const source = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      source.bookSourceType = 1;
      source.enabledCookieJar = false;
      source.header = '{"User-Agent":"RuleSourceTest"}';
      const address = 'https://cdn.example.com/audio/001.MP3?token=signed,' +
        '{"headers":{"Referer":"https://api.example.com/book/42"}}';
      const result = await LocalRuleDispatcher.resolveContent(source, address, {});
      expect(result.audioUrl).assertEqual('https://cdn.example.com/audio/001.MP3?token=signed');
      expect(result.requestHeaders['User-Agent']).assertEqual('RuleSourceTest');
      expect(result.requestHeaders['Referer']).assertEqual('https://api.example.com/book/42');
      expect(result.content).assertEqual('');
    });

    it('only bypasses GET audio extensions found in the URL path for audio sources', 0, () => {
      const audioSource = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      audioSource.bookSourceType = 1;
      audioSource.enabledCookieJar = false;
      const textSource = LocalRuleSourceImportParser.parse(JSON_SOURCE).sources[0];
      textSource.enabledCookieJar = false;
      const queryOnly = LocalRuleDispatcher.resolveDirectAudioRequest(
        audioSource, 'https://api.example.com/play?file=chapter.mp3', {});
      const hostOnly = LocalRuleDispatcher.resolveDirectAudioRequest(audioSource, 'https://chapter.mp3', {});
      const postAudio = LocalRuleDispatcher.resolveDirectAudioRequest(audioSource,
        'https://cdn.example.com/chapter.mp3,{"method":"POST","body":"token=1"}', {});
      const textAudio = LocalRuleDispatcher.resolveDirectAudioRequest(
        textSource, 'https://cdn.example.com/chapter.mp3', {});
      expect(queryOnly === undefined).assertTrue();
      expect(hostOnly === undefined).assertTrue();
      expect(postAudio === undefined).assertTrue();
      expect(textAudio === undefined).assertTrue();
    });

    it('returns no JSONPath results for invalid slices and filters', 0, () => {
      const payload = '{"items":[{"score":8},{"score":12}]}';
      expect(LocalRuleJsonPath.queryPayload(payload, '$.items[0:2:0]').length).assertEqual(0);
      expect(LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score >>> 10)]').length).assertEqual(0);
      expect(LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score >= 10 && )]').length).assertEqual(0);
      expect(LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score =~ /[/i)]').length).assertEqual(0);
      expect(LocalRuleJsonPath.queryPayload(payload,
        '$.items[?(@.score =~ /8/ii)]').length).assertEqual(0);
    });
  });
}
