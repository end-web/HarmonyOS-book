import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../main/ets/model/LocalRuleSource';
import { LocalRuleScriptRuntime } from '../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleStageExtractor } from '../main/ets/service/rulesource/LocalRuleStageExtractor';
import { LocalRuleUrlAnalyzer } from '../main/ets/service/rulesource/LocalRuleUrlAnalyzer';
import { LocalRuleHttpClient } from '../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleDispatcher } from '../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRulePanelService } from '../main/ets/service/rulesource/LocalRulePanelService';
import { LocalRuleRequestSession } from '../main/ets/service/rulesource/LocalRuleRequestSession';

export default function localRuleCompatibilityTest() {
  describe('LocalRuleCompatibility', () => {
    const source = LocalRuleSource.descriptor('https://compatibility.invalid', 'Compatibility');
    const evaluate = async (code: string, content: string = ''): Promise<string> =>
      LocalRuleScriptRuntime.evaluate(content, source.bookSourceUrl, code, source, {});

    it('decodes data payloads without interpreting payload JSON as options', 0, async () => {
      const response = await LocalRuleHttpClient.fetch(source, 'data:application/json,{"books":[{"id":1}]}');
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('{"books":[{"id":1}]}');
      expect((await LocalRuleHttpClient.fetch(source, 'data:;base64,5Lmm5rqQ,{"charset":"utf-8"}')).body)
        .assertEqual('书源');
      expect((await LocalRuleHttpClient.fetch(source, 'data:,%E4%B9%A6%E6%BA%90+test')).body).assertEqual('书源+test');
      expect((await LocalRuleHttpClient.fetch(source, 'data:;base64,%%%')).ok).assertFalse();
    });

    it('executes only explicit data request options', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source,
        'data:,ignored,{"type":"request","url":"https://example.com/api","method":"POST","body":"a=1"}');
      expect(plan.inlineBody === undefined).assertTrue();
      expect(plan.url).assertEqual('https://example.com/api');
      expect(plan.method).assertEqual('POST');
      expect(String(plan.body)).assertEqual('a=1');
      expect(LocalRuleUrlAnalyzer.analyze(source, '/redirect,{"redirect":false}').followRedirects).assertFalse();
    });

    it('preserves binary Base64 and common Android Java aliases', 0, async () => {
      expect(await evaluate('java.hexEncodeToString(android.util.Base64.decode("AP+A/g==",0))')).assertEqual('00ff80fe');
      expect(await evaluate('new java.lang.String(java.util.Base64.getDecoder().decode("5Lmm5rqQ"),"UTF-8").toString()'))
        .assertEqual('书源');
      expect(await evaluate('java.base64UrlEncode([255,254,253])+"|"+java.hexEncodeToString(java.base64Decode("__79"))'))
        .assertEqual('__79|fffefd');
    });

    it('applies declarative session values without cookie header injection', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source, 'https://example.com/read?token=a%2Bb&bad=x%3By%3Dz,' +
        '{"headers":{"Cookie":"device=existing"},"session":{"queryCookies":{"auth":"token","unsafe":"bad"},' +
        '"generatedCookies":{"device":"@uuid"},"referer":"origin"}}');
      expect(LocalRuleRequestSession.apply(plan)).assertEqual('device=existing; auth=a+b');
      expect(plan.headers['Referer']).assertEqual('https://example.com/');
    });

    it('preserves JSON structure when search keywords contain quotes or backslashes', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source,
        '/search,{"method":"POST","body":{"query":"{{key}}","nested":["{{key}}"],"page":1}}', {}, 'a"b\\c', 1);
      expect(JSON.stringify(plan.body)).assertEqual('{"query":"a\\"b\\\\c","nested":["a\\"b\\\\c"],"page":1}');
    });

    it('transforms response bodies in the bounded runtime', 0, async () => {
      const transform = LocalRuleSource.descriptor('https://transform.invalid', 'Transform');
      transform.jsLib = 'function titleOf(value){return JSON.parse(value).title;}';
      const response = await LocalRuleHttpClient.fetch(transform,
        'data:application/json,%7B%22title%22%3A%22Book%22%7D,{"bodyJs":"titleOf(result)"}');
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('Book');
    });

    it('matches standard SHA and HMAC vectors through bounded actions', 0, async () => {
      expect(await evaluate('java.sha256("abc")')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await evaluate('java.hmacSha256("The quick brown fox jumps over the lazy dog","key")'))
        .assertEqual('f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
      expect(await evaluate('java.hexEncodeToString(java.security.MessageDigest.getInstance("SHA-1").digest("abc".getBytes()))'))
        .assertEqual('a9993e364706816aba3e25717850c26c9cd0d89d');
    });

    it('matches the NIST AES CBC vector through Cipher aliases', 0, async () => {
      expect(await evaluate('var cipher=javax.crypto.Cipher.getInstance("AES/CBC/NoPadding");' +
        'cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(java.hexDecode("2b7e151628aed2a6abf7158809cf4f3c"),"AES"),' +
        'new IvParameterSpec(java.hexDecode("000102030405060708090a0b0c0d0e0f")));' +
        'java.hexEncodeToString(cipher.doFinal(java.hexDecode("6bc1bee22e409f96e93d7e117393172a")))'))
        .assertEqual('7649abac8119b246cee98e9b12e9197d');
      expect(await evaluate('createSymmetricCrypto("AES/CBC/PKCS5Padding","0123456789abcdef","fedcba9876543210")' +
        '.decryptBase64ToString(createSymmetricCrypto("AES/CBC/PKCS5Padding","0123456789abcdef","fedcba9876543210").encryptBase64("书源"))'))
        .assertEqual('书源');
    });

    it('supports collection and form URL encoding semantics', 0, async () => {
      expect(await evaluate('var m=new java.util.HashMap();m.put("title","book");var a=new java.util.ArrayList();' +
        'a.add(m.get("title"));new java.lang.StringBuilder().append(a.get(0)).append(a.size()).toString()')).assertEqual('book1');
      expect(await evaluate('java.urlEncode("A B+C&")+"|"+java.urlDecode("A+B%2BC%26")')).assertEqual('A+B%2BC%26|A B+C&');
    });

    it('formats epoch zero and freezes Date constructors during action replay', 0, async () => {
      expect(await evaluate('java.timeFormatUTC(0,"yyyy-MM-dd HH:mm:ss.SSS",8)')).assertEqual('1970-01-01 08:00:00.000');
      expect(await evaluate('var started=new Date().getTime();java.sha256(String(started));String(started===Date.now())')).assertEqual('true');
    });

    it('converts Chinese text and chapter numerals without changing title words', 0, async () => {
      expect(await evaluate('java.t2s("繁體閱讀小說")+"|"+java.s2t("简体阅读小说")'))
        .assertEqual('繁体阅读小说|簡體閱讀小說');
      expect(await evaluate('java.toNumChapter("第一千零二十三章 一生所爱")')).assertEqual('第1023章 一生所爱');
      expect(await evaluate('java.toNumChapter("第两万零六回")')).assertEqual('第20006回');
    });

    it('evaluates full JSONPath inside scripts and preserves list methods', 0, async () => {
      expect(await evaluate('java.getStringList("$.items[*].name").size()+"|"+java.getStringList("$.items[*].name").get(1)',
        '{"items":[{"name":"one"},{"name":"two"}]}')).assertEqual('2|two');
      expect(await evaluate('java.setContent("{\\"name\\":\\"changed\\"}");java.getString("$.name")')).assertEqual('changed');
    });

    it('evaluates field templates with quoted braces and JavaScript calls', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"count":12}', source.bookSourceUrl);
      expect(await LocalRuleStageExtractor.extract(document,
        '{{JSON.stringify({suffix:"}}",count:java.getString("$.count")})}}', source, {}))
        .assertEqual('{"suffix":"}}","count":"12"}');
    });

    it('resolves relative JSON paths and trailing put directives in detail rules', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"data":[{"name":"Book","id":42}]}', source.bookSourceUrl);
      const initialized = await LocalRuleStageExtractor.extract(document, 'data[0]', source, {});
      const current = LocalRuleStageExtractor.createDocument(initialized, source.bookSourceUrl);
      const variables: Record<string, string> = {};
      expect(await LocalRuleStageExtractor.extract(current, 'name@put:{book_id:id}', source, variables)).assertEqual('Book');
      expect(variables['book_id']).assertEqual('42');
      expect(await LocalRuleStageExtractor.extract(current, 'https://example.com/toc?id=@get:{book_id}', source, variables, true))
        .assertEqual('https://example.com/toc?id=42');
    });

    it('applies a trailing JSON selector before expanding script arrays', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"data":[{"name":"one","id":1},{"name":"two","id":2}]}', source.bookSourceUrl);
      const items = await LocalRuleStageExtractor.selectList(document,
        '<js>JSON.stringify(JSON.parse(result).data)</js>$[*]', source, {});
      expect(items.length).assertEqual(2);
      expect(await LocalRuleStageExtractor.extract(items[0], 'name', source, {})).assertEqual('one');
      expect(await LocalRuleStageExtractor.extract(items[1], 'id', source, {})).assertEqual('2');
    });

    it('runs an inline JSON source through search detail toc and content', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://inline.invalid', 'Inline');
      const contentUrl = 'data:,chapter%20body';
      const toc: Record<string, string>[] = [{ 'title': 'Chapter', 'url': contentUrl }];
      const tocUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(toc));
      const detail: Record<string, string> = { 'name': 'Book', 'toc': tocUrl };
      const detailUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(detail));
      const search: Record<string, string>[] = [{ 'name': 'Book', 'url': detailUrl }];
      fixture.searchUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(search));
      fixture.ruleSearch.bookList = '$';
      fixture.ruleSearch.name = '$.name';
      fixture.ruleSearch.bookUrl = '$.url';
      fixture.ruleBookInfo.name = '$.name';
      fixture.ruleBookInfo.tocUrl = '$.toc';
      fixture.ruleToc.chapterList = '$';
      fixture.ruleToc.chapterName = '$.title';
      fixture.ruleToc.chapterUrl = '$.url';
      fixture.ruleContent.content = '@text';
      const books = await LocalRuleDispatcher.searchForHealthCheck(fixture, 'Book');
      expect(books.length).assertEqual(1);
      const info = await LocalRuleDispatcher.getBookInfo(fixture, books[0].bookUrl, books[0].variables);
      expect(info !== null).assertTrue();
      if (info === null) return;
      const chapters = await LocalRuleDispatcher.getBookToc(fixture, info.tocUrl, info.variables);
      expect(chapters.length).assertEqual(1);
      expect(await LocalRuleDispatcher.getContent(fixture, chapters[0].url, chapters[0].variables)).assertEqual('chapter body');
    });

    it('rejects audio error text instead of constructing a successful relative address', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://audio.invalid', 'Audio');
      fixture.bookSourceType = 1;
      fixture.ruleContent.content = '@js:"获取音频失败：token expired"';
      expect((await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture')).audioUrl).assertEqual('');
      fixture.ruleContent.content = '@js:java.base64Encode("https://audio.invalid/play.mp3?token=fixture")';
      expect((await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture')).audioUrl)
        .assertEqual('https://audio.invalid/play.mp3?token=fixture');
      fixture.ruleContent.content = '@js:\'https://audio.invalid/play.mp3,{"headers":{"X-Audio":"signed"}}\'';
      const signed = await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture');
      expect(signed.audioUrl).assertEqual('https://audio.invalid/play.mp3');
      expect(signed.requestHeaders['X-Audio']).assertEqual('signed');
    });

    it('normalizes nested discovery groups and labelled control values', 0, () => {
      const panel = LocalRulePanelService.parse('[{"title":"Library","children":[{"title":"Popular","url":"/hot"}]},' +
        '{"title":"Sort","type":"select","chars":[{"label":"Recent","value":"new"},{"label":"Popular","value":"hot"}]}]');
      expect(panel.entries.length).assertEqual(2);
      expect(panel.entries[1].url).assertEqual('/hot');
      expect(panel.controls[0].options[0]).assertEqual('Recent');
      expect(panel.controls[0].value).assertEqual('new');
      expect(panel.controls[0].optionValues[1]).assertEqual('hot');
    });

    it('loads login functions and routes browser actions without exposing platform APIs', 0, async () => {
      const login = LocalRuleSource.descriptor('https://login.invalid', 'Login');
      login.loginUrl = '@js:function openLogin(){java.startBrowser("https://login.invalid/account");}';
      login.loginUi = '[{"title":"Sign in","type":"button","action":"openLogin()"}]';
      login.loginCheckJs = 'false';
      const panel = await LocalRulePanelService.load(login, true);
      const action = await LocalRulePanelService.act(login, panel.controls[0], panel.controls, true);
      expect(action.browserUrl).assertEqual('https://login.invalid/account');
      let failed = false;
      try { await LocalRulePanelService.checkLogin(login, ''); } catch (_error) { failed = true; }
      expect(failed).assertTrue();
    });
  });
}
