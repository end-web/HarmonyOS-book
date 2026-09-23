// Real ArkTS rules/dispatcher; simulated HTTP/DOM and V8 in place of native QuickJS.
// DEVECO_HOME=<Release IDE> node scripts/test-local-rule-templates.cjs [text-source.json audio-source.json]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to a Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const prefix = 'service/rulesource/';
const modules = new Map();
const responses = new Map();
const requests = [];
const http = {
  getCookieSnapshot: async () => ({}), hydrateCookies: async () => {}, getCookieHeader: () => '',
  prepareRequest: (source, url, variables) => load(prefix + 'LocalRuleUrlAnalyzer').LocalRuleUrlAnalyzer.analyze(source, url, variables),
  fetch: async (source, address, variables = {}, keyword = '', page = 1) => {
    const plan = load(prefix + 'LocalRuleUrlAnalyzer').LocalRuleUrlAnalyzer.analyze(source, address, variables, keyword, page);
    requests.push(plan.url);
    assert.ok(responses.has(plan.url), `Unexpected request: ${plan.url}`);
    const value = responses.get(plan.url);
    return { ok: true, statusCode: 200, requestUrl: plan.url, headers: {}, resourceUrls: [],
      body: typeof value === 'string' ? value : JSON.stringify(value), errorMessage: '' };
  }
};
const stubs = {
  '@kit.ArkTS': { buffer: { from: Buffer.from }, util: {} },
  'utils/CharsetCodec': { CharsetCodec: {} },
  'service/CoverPrefetcher': { CoverPrefetcher: { registerHeaders() {} } },
  [prefix + 'LocalRuleSourceRepository']: { LocalRuleSourceRepository: { isInitialized: () => false } },
  [prefix + 'LocalRuleHttpClient']: { LocalRuleHttpClient: http },
  [prefix + 'LocalRuleQuickJsRuntime']: {
    LocalRuleQuickJsRequest: class {},
    LocalRuleQuickJsRuntime: { execute: async request => ({ success: true,
      value: await vm.runInNewContext(request.script, {}, { timeout: 2000 }) }) }
  },
  [prefix + 'LocalRuleScriptActions']: { LocalRuleScriptActions: { PREFIX: 'local-rule-action:' } },
  [prefix + 'LocalRuleBrowserActions']: { LocalRuleBrowserActions: { PREFIX: 'local-rule-browser:' } },
  [prefix + 'talebook/TalebookSourceIdentity']: { TalebookSourceIdentity: { isSourceUrl: () => false } },
  [prefix + 'talebook/TalebookSourceAdapter']: { TalebookSourceAdapter: {} },
  [prefix + 'LocalRuleWebRuntime']: {
    LocalRuleWebSelector: class {},
    LocalRuleWebExtractMode: { TEXT: 'text', HTML: 'html', OUTER_HTML: 'outerHtml', ATTRIBUTE: 'attribute' },
    LocalRuleWebRuntime: { instance: { select: async () => { throw new Error('DOM is outside this regression harness'); } } }
  }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const filename = path.join(root, name + '.ets');
  const module = { exports: {} };
  modules.set(name, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout, clearTimeout,
    ObservedV2: value => value, Trace: () => {},
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
const { LocalRuleSource } = load('model/LocalRuleSource');
const { LocalRuleStageExtractor: extractor } = load(prefix + 'LocalRuleStageExtractor');
const { LocalRuleDispatcher: dispatcher } = load(prefix + 'LocalRuleDispatcher');
const { LocalRuleUrlAnalyzer: urls } = load(prefix + 'LocalRuleUrlAnalyzer');
const { LocalRuleSourceImportParser: parser } = load(prefix + 'LocalRuleSourceImportParser');
const { LocalRuleMetadataText: metadataText } = load(prefix + 'LocalRuleMetadataText');
const origin = 'https://rules.example.com';
const bookUrl = origin + '/book/123456.html';

async function run() {
  for (const [input, expected] of [
    ['第一段</br>第二段<br />第三段', '第一段\n第二段\n第三段'],
    ['&lt;p&gt;简介&amp;nbsp;第一段&lt;/p&gt;&lt;p&gt;第二段&lt;/p&gt;', '简介 第一段\n\n第二段'],
    ['&amp;lt;br&amp;gt;正文&#x4E2D;&#25991;&#x1F4D6;', '正文中文📖'],
    ['<script>不应显示</script><style>.x{}</style><p>保留<b>内容</b></p>', '保留内容'],
    ['&ldquo;书名&rdquo;&mdash;作者&hellip;', '“书名”—作者…'],
    ['3 < 5，A & B，<未来世界>', '3 < 5，A & B，<未来世界>'],
    ['<p>&nbsp;暂无简介</p>', ''], ['&#x110000;&#xD800;', '��']
  ]) assert.equal(metadataText.intro(input), expected, `metadata: ${input}`);
  const directAudio = LocalRuleSource.descriptor(origin, 'Explicit direct audio');
  directAudio.bookSourceType = 1;
  const signedStream = origin + '/stream?sign=fixture';
  assert.equal(dispatcher.resolveDirectAudioRequest(directAudio, signedStream).audioUrl, signedStream,
    'An audio source without content extraction may use an extensionless signed URL');
  directAudio.ruleContent.content = '$.audioUrl';
  assert.equal(dispatcher.resolveDirectAudioRequest(directAudio, signedStream), undefined,
    'Configured content extraction remains active');
  directAudio.ruleContent.content = '';
  assert.equal(dispatcher.resolveDirectAudioRequest(directAudio, signedStream + ',{"webView":true}'), undefined,
    'Explicit browser requests must not be bypassed by direct audio');
  const source = LocalRuleSource.descriptor(origin, 'Template compatibility');
  const compatDocument = extractor.createDocument('', bookUrl);
  assert.equal(await extractor.extract(compatDocument, `<js>
    var stream = new Packages.java.io.ByteArrayOutputStream();
    stream.write([65, 255, 66], 0, 2); stream.write(256); stream.close();
    var first = stream.toByteArray(); first[0] = 0;
    var actual = stream.toByteArray(); var size = stream.size(); stream.reset();
    'bytes=' + JSON.stringify([actual, size, stream.size()]);</js>`, source), 'bytes=[[65,255,0],3,0]');
  assert.equal(await extractor.extract(compatDocument, `<js>
    var p = new javax.crypto.spec.GCMParameterSpec(128, [1,2,3,4], 1, 2);
    var copy = p.getIV(); copy[0] = 9;
    'params=' + JSON.stringify([p.getTLen(), p.getIV()]);</js>`, source), 'params=[128,[2,3]]');
  await assert.rejects(() => extractor.extract(compatDocument,
    '<js>new javax.crypto.spec.GCMParameterSpec(128,[1],0,2)</js>', source), /Invalid nonce range/);
  const { LocalRuleRegexCompat: regex } = load(prefix + 'LocalRuleRegexCompat');
  assert.equal(extractor.applyCleanup('广告\n中间\n结束 正文', '(?s)广告.*?结束'), ' 正文');
  assert.equal(extractor.applyCleanup('ABC abc', '(?i)abc##[$0]'), '[ABC] [abc]');
  assert.equal(extractor.applyCleanup('a.b [x]', String.raw`\Qa.b\E##保留`), '保留 [x]');
  assert.equal(extractor.applyCleanup(' a\t b\r\nc', String.raw`\h+|\R##/`), '/a/b/c');
  assert.equal(extractor.applyCleanup('汉字123', String.raw`\p{L}+##文字`), '文字123');
  assert.equal(extractor.applyCleanup('aaaa!', 'a++##A'), 'A!');
  assert.equal(extractor.applyCleanup('aaaa!', '(?>a+)##A'), 'A!');
  assert.equal(extractor.applyCleanup('ab', String.raw`(a)(b)##$2\$1`), 'b$1');
  assert.equal(regex.compile(String.raw`end\z`).test('end\n'), false);
  assert.equal(regex.compile(String.raw`end\Z`).test('end\n'), true);
  assert.equal(regex.compile('(?x)a  #comment\n b').test('ab'), true);
  assert.throws(() => regex.compile('(a++)+'), /嵌套重复/);
  assert.throws(() => regex.compile('a'.repeat(32769)), /32 KiB/);
  const regexDocument = extractor.createDocument('<item>12:第一章</item><item>34:第二章</item>', bookUrl);
  const captured = await extractor.selectList(regexDocument, String.raw`:<item>.*?</item>&&(\d+):([^<]+)`, source);
  assert.equal(captured.length, 2);
  assert.equal(await extractor.extract(captured[0], "$['$0']", source), '12:第一章');
  assert.equal(await extractor.extract(captured[1], "$['$1']", source), '34');
  assert.equal(await extractor.extract(captured[1], "$['$2']", source), '第二章');
  assert.equal(await extractor.extract(captured[1], '<js>result.$1 + ":" + result.$2</js>', source), '34:第二章');
  assert.equal((await extractor.selectList(regexDocument, ':not-matched', source)).length, 0);
  assert.equal((await extractor.selectList(extractor.createDocument('ab', bookUrl), ':^|$', source)).length, 2);
  assert.equal(await extractor.extract(extractor.createDocument('AB 12', bookUrl), '%(AB) (\\d+)', source), 'AB 12\nAB\n12');
  console.log('PASS: Java regex dialect, replacement groups, bounded conversion and typed chained regex lists');
  const document = extractor.createDocument(JSON.stringify({ bookStatus: 1, wordCount: 10,
    'book-id': 'keep-hyphen', 'a?b': 'keep-question', items: [{ enabled: true, name: 'kept' }] }), bookUrl);
  for (const [rule, expected] of [
    ["{{$.bookStatus == 1 ? '完结' : '连载'}}", '完结'],
    ["{{$.bookStatus == 0 ? '完结' : '连载'}}", '连载'],
    ['{{$.wordCount + 2}}', '12'], ['{{$.wordCount - 2}}', '8'],
    ['{{$.wordCount}}', '10'], ['{{$.book-id}}', 'keep-hyphen'],
    ["{{$['a?b']}}", 'keep-question'],
    ['{{$.items[?(@.enabled == true)].name}}', 'kept'],
    ['{{$.items[0:1].name}}', 'kept'], ['{{$.items[*].name}}', 'kept'],
    ['{{$.missing}}', ''], ['{{$.wordCount.toString()}}', '10']
  ]) assert.equal(await extractor.extract(document, rule, source), expected, rule);
  assert.equal(urls.bookId(bookUrl + '?page=2#toc'), '123456.html');
  assert.equal(urls.bookId(bookUrl + '?id=custom&book_id=preferred'), 'preferred');
  assert.equal(urls.bookId(origin + '/novel/abc123/'), 'abc123');
  assert.equal(urls.bookId(origin), '');
  assert.equal(urls.bookId('data:,123456'), '');
  assert.equal(urls.bookId(bookUrl + '?id=%ZZ'), '123456.html');

  // Exercise context before detail fields and persistence into the returned book.
  source.ruleBookInfo.name = '<js>book.bookUrl</js>';
  source.ruleBookInfo.intro = '<js>"简介&lt;br&gt;第二段&#x3002;"</js>';
  source.ruleBookInfo.wordCount = '<js>"123万字"</js>';
  source.ruleBookInfo.lastChapter = '<js>"第十二章"</js>';
  source.ruleBookInfo.updateTime = '<js>"2026-09-23 18:30"</js>';
  source.ruleBookInfo.tocUrl = '/book/indexList-{{id}}';
  responses.set(bookUrl, 'detail fixture');
  const info = await dispatcher.getBookInfo(source, bookUrl);
  assert.ok(info);
  assert.equal(info.name, bookUrl);
  assert.equal(info.intro, '简介\n第二段。');
  assert.equal(info.wordCount, '123万字');
  assert.equal(info.lastChapter, '第十二章');
  assert.equal(info.updateTime, '2026-09-23 18:30');
  assert.equal(info.tocUrl, origin + '/book/indexList-123456.html');
  assert.equal(info.variables.bookUrl, bookUrl);
  const custom = await dispatcher.getBookInfo(source, bookUrl, { id: 'explicit' });
  assert.equal(custom.tocUrl, origin + '/book/indexList-explicit');
  responses.set(bookUrl, '{"id":"json-id"}');
  const jsonInfo = await dispatcher.getBookInfo(source, bookUrl);
  assert.equal(jsonInfo.tocUrl, origin + '/book/indexList-json-id');
  responses.set(bookUrl, 'detail fixture');

  // Scripts produce chapter objects without a try/catch routing trick.
  source.bookSourceType = 1;
  source.ruleToc.chapterList = '<js>JSON.stringify([{name:"第一集",url:book.bookUrl.replace("/book/", "/tingshu/").replace(".html", "/700001.html")}])</js>';
  source.ruleToc.chapterName = '$.name';
  source.ruleToc.chapterUrl = '$.url';
  const chapters = await dispatcher.getBookToc(source, bookUrl, info.variables);
  assert.equal(chapters.length, 1);
  assert.equal(chapters[0].name, '第一集');
  const chapterUrl = origin + '/tingshu/123456/700001.html';
  assert.equal(chapters[0].url, chapterUrl);
  responses.set(chapterUrl, 'Loading');
  responses.set(origin + '/audio?id=123456', { audioUrl: origin + '/audio/episode.mp3' });
  // String.raw keeps the regular-expression escapes in the source script.
  source.ruleContent.content = String.raw`<js>var id=book.bookUrl.match(/book\/(\d+)/)[1]; JSON.parse(java.ajax('${origin}/audio?id='+id)).audioUrl;</js>`;
  const audio = await dispatcher.resolveContent(source, chapterUrl, chapters[0].variables);
  assert.equal(audio.audioUrl, origin + '/audio/episode.mp3');
  assert.equal(requests.filter(url => url === origin + '/audio?id=123456').length, 1);

  const mixed = LocalRuleSource.descriptor(origin + '/mixed', 'Declared media type');
  mixed.searchUrl = origin + '/mixed/search';
  mixed.ruleSearch.bookList = '$.books';
  mixed.ruleSearch.name = '$.name<js>source.put("type","audio"); result</js>';
  mixed.ruleSearch.bookUrl = '$.url';
  mixed.ruleSearch.updateTime = '$.updated';
  responses.set(mixed.searchUrl, { books: [{ name: '音频示例', url: '/stream', updated: '2026-09-23' }] });
  const mixedResults = await dispatcher.search(mixed, '示例');
  assert.equal(mixedResults[0].contentType, 'audio');
  assert.equal(mixedResults[0].updateTime, '2026-09-23');
  assert.equal(mixedResults[0].variables.__bookContentType, 'audio');
  const audioVariables = { ...mixedResults[0].variables, __sourceContentType: 'text' };
  assert.equal(dispatcher.resolveDirectAudioRequest(mixed, signedStream, audioVariables).audioUrl, signedStream,
    'A saved audio book retains its declared type after the discovery source changes mode');

  // Optional user definitions stay outside the repository; execute their original rules.
  const files = process.argv.slice(2);
  if (files.length) {
    assert.equal(files.length, 2, 'Supply text and audio definitions together');
    const text = parser.parse(fs.readFileSync(files[0], 'utf8')).sources[0];
    const listening = parser.parse(fs.readFileSync(files[1], 'utf8')).sources[0];
    assert.ok(text && listening);
    const item = extractor.createDocument('{"id":123456,"bookStatus":1}', text.bookSourceUrl);
    assert.equal(await extractor.extract(item, text.ruleSearch.status, text), '完结');
    const detailUrl = await extractor.extract(item, text.ruleSearch.bookUrl, text, {}, true);
    const detail = extractor.createDocument('<html></html>', detailUrl);
    assert.equal(await extractor.extract(detail, text.ruleBookInfo.tocUrl, text,
      { bookUrl: detailUrl }, true), text.bookSourceUrl + '/book/indexList-123456.html');
    const textChapter = text.bookSourceUrl + '/book/123456/700001.html';
    responses.set(text.bookSourceUrl + '/book/queryReadPage?bookId=123456&bookIndexId=700001',
      { code: 200, data: { content: '公开章节测试正文' } });
    assert.equal(await extractor.extract(extractor.createDocument('Loading', textChapter),
      text.ruleContent.content, text), '公开章节测试正文');
    const audioBook = listening.bookSourceUrl + '/book/123456.html';
    const html = '<a href="/tingshu/123456/700003.html" title="第3集">第3集 2026-09-19</a>';
    responses.set(audioBook, html);
    const list = await dispatcher.getBookToc(listening, audioBook, { bookUrl: audioBook });
    assert.equal(list.length, 3);
    assert.equal(list[0].name, '第1集');
    assert.equal(list[2].url, listening.bookSourceUrl + '/tingshu/123456/700003.html');
    responses.set(list[0].url, 'Loading');
    responses.set(listening.bookSourceUrl + '/api/act/getAudio?id=123456',
      { audioUrl: listening.bookSourceUrl + '/audio/public.mp3' });
    assert.equal((await dispatcher.resolveContent(listening, list[0].url, list[0].variables)).audioUrl,
      listening.bookSourceUrl + '/audio/public.mp3');
    console.log('PASS: both original definitions, text AJAX, inferred chapters, audio content fallback');
  }
  console.log('PASS: expressions, JSONPath preservation, URL IDs, explicit overrides, book/chapter context, AJAX replay');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
