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
  [prefix + 'tingyou/TingYouSourceAdapter']: { TingYouSourceAdapter: { canResolveBook: () => false, canResolve: () => false } },
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
const origin = 'https://rules.example.com';
const bookUrl = origin + '/book/123456.html';

async function run() {
  const source = LocalRuleSource.descriptor(origin, 'Template compatibility');
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
  source.ruleBookInfo.tocUrl = '/book/indexList-{{id}}';
  responses.set(bookUrl, 'detail fixture');
  const info = await dispatcher.getBookInfo(source, bookUrl);
  assert.ok(info);
  assert.equal(info.name, bookUrl);
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
