import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { LocalRuleDispatcher } from '../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRuleStageExtractor } from '../main/ets/service/rulesource/LocalRuleStageExtractor';
import { LocalRuleJsonPath } from '../main/ets/service/rulesource/LocalRuleJsonPath';
import { LocalRuleUrlAnalyzer } from '../main/ets/service/rulesource/LocalRuleUrlAnalyzer';

const JSON_SOURCE: string = '[{' +
  '"bookSourceName":"示例 API","bookSourceUrl":"https://api.example.com","bookSourceType":0,' +
  '"searchUrl":"/search?keyword={{key}}&page={{page}}",' +
  '"ruleSearch":{"bookList":"$.data.books[*]","name":"$.title",' +
  '"author":"$.author","bookUrl":"/book/{{$.id}}"},' +
  '"ruleBookInfo":{"tocUrl":"/book/{{$.id}}/chapters"},' +
  '"ruleToc":{"chapterList":"$.data.chapters[*]","chapterName":"$.title",' +
  '"chapterUrl":"/chapter/{{$.id}}"},"ruleContent":{"content":"$.data.content"}}]';

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

    it('keeps script-dependent sources enabled for the isolated compatibility runtime', 0, () => {
      const value = JSON_SOURCE.replace('"ruleContent":{', '"jsLib":"java.ajax(url)","ruleContent":{');
      const report = LocalRuleSourceImportParser.parse(value);
      expect(report.sources.length).assertEqual(1);
      expect(report.sources[0].validationStatus).assertEqual(LocalRuleSourceStatus.UNCHECKED);
      expect(report.sources[0].enabled).assertTrue();
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
