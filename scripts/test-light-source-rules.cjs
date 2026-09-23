// Real rule parser/runtime, cached DOM field values and V8 instead of native QuickJS.
// DEVECO_HOME=<Release IDE> node scripts/test-light-source-rules.cjs [source.json]
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
const stubs = {
  '@kit.ArkTS': { buffer: { from: Buffer.from }, util: { TextDecoder: {
    create: charset => ({ decodeToString: bytes => new TextDecoder(charset).decode(bytes) })
  } } },
  'utils/CharsetCodec': { CharsetCodec: {} },
  [prefix + 'LocalRuleSourceRepository']: { LocalRuleSourceRepository: { isInitialized: () => false } },
  [prefix + 'LocalRuleHttpClient']: { LocalRuleHttpClient: {
    getCookieSnapshot: async () => ({}), hydrateCookies: async () => {}, getCookieHeader: () => '',
    fetch: async () => { throw new Error('These fields must not issue network requests'); }
  } },
  [prefix + 'LocalRuleQuickJsRuntime']: {
    LocalRuleQuickJsRequest: class {},
    LocalRuleQuickJsRuntime: { execute: async request => ({ success: true,
      value: vm.runInNewContext(request.script, {}, { timeout: 2000 }) }) }
  },
  [prefix + 'LocalRuleScriptActions']: { LocalRuleScriptActions: { PREFIX: 'local-rule-action:' } },
  [prefix + 'LocalRuleBrowserActions']: { LocalRuleBrowserActions: { PREFIX: 'local-rule-browser:' } },
  [prefix + 'LocalRuleWebRuntime']: {
    LocalRuleWebSelector: class {},
    LocalRuleWebExtractMode: { TEXT: 'text', HTML: 'html', OUTER_HTML: 'outerHtml', ATTRIBUTE: 'attribute' },
    LocalRuleWebRuntime: { instance: { select: async (_html, selector) => {
      throw new Error(`DOM field was not prepared: ${selector}`);
    } } }
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
    ObservedV2: value => value, Trace: () => {}, require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
const { LocalRuleSource } = load('model/LocalRuleSource');
const { LocalRuleStageExtractor: extractor } = load(prefix + 'LocalRuleStageExtractor');
const { LocalRuleUrlAnalyzer: urls } = load(prefix + 'LocalRuleUrlAnalyzer');
const { LocalRuleSourceImportParser: parser } = load(prefix + 'LocalRuleSourceImportParser');
const origin = 'https://rules.example.com';
function html(fields) {
  const document = extractor.createDocument('<article>fixture</article>', origin + '/book/1.html');
  for (const [key, value] of Object.entries(fields)) document.htmlFields.set(key, value);
  return document;
}
async function run() {
  const source = LocalRuleSource.descriptor(origin, 'Light source compatibility');
  const importDefinition = { bookSourceUrl: origin, bookSourceName: 'Import default', exploreUrl: '推荐::/books' };
  assert.equal(parser.parse(JSON.stringify(importDefinition)).sources[0].enabledExplore, true);
  assert.equal(parser.parse(JSON.stringify({ ...importDefinition, enabledExplore: false })).sources[0].enabledExplore, false);
  assert.equal(parser.parse(JSON.stringify({ ...importDefinition, exploreUrl: '' })).sources[0].enabledExplore, false);
  for (const [page, expected] of [[1, '/category/'], [2, '/category/index_2.html'], [5, '/category/index_5.html']]) {
    assert.equal(urls.analyze(source, '/category/<,index_{{page}}.html>', {}, '', page).url, origin + expected);
  }
  assert.equal(urls.analyze(source, '/<first,second,page_{{page}}>', {}, '', 2).url, origin + '/second');
  assert.equal(urls.analyze(source, '/<first,second,page_{{page}}>', {}, '', 9).url, origin + '/page_9');
  const inline = urls.analyze(source, 'data:text/html,<p>a,b</p>');
  assert.equal(inline.inlineBody, '<p>a,b</p>');
  assert.equal(urls.analyze(source, '/save,{"method":"POST","body":"value=<a,b>"}').body, 'value=<a,b>');
  assert.equal(urls.resolveUrl(origin + '/category/', './?page=2'), origin + '/category/?page=2');
  assert.equal(urls.analyze(source, '/search,{"method":"POST","body":"q={{key}}"}', {}, 'a b&c').body, 'q=a+b%26c');

  for (const [selector, expected] of [['span.mr-4.1', 'span.mr-4:eq(1)'], ['.meta.2', '.meta:eq(2)'],
    ['div.card.active.-1', 'div.card.active:eq(-1)'], ['tag.a.0', 'a:eq(0)']]) {
    assert.equal(extractor.normalizeLegacyCssSelector(selector), expected);
  }
  const doc = html({ 'h2@text': ['目录导航'], 'a:eq(1)@text': ['测试书_测试作者【完结】'], 'a@text': ['不应选中_作者【连载】'] });
  const json = extractor.createDocument('{"book_id":7,"data":{"list":[{"name":"书名"}]}}', origin);
  for (const rule of ['.data.list[0].name', '@json:data.list[0].name', '@.data.list[0].name']) {
    assert.equal(await extractor.extract(json, rule, source), '书名', rule);
  }
  assert.equal(await extractor.extract(json, '/book/{$.book_id}/{{$.data.list[0].name}}', source), '/book/7/书名');
  assert.equal(await extractor.extract(json, "/book/{$['book_id']}", source), '/book/7');
  assert.equal((await extractor.selectList(json, '@json:data.list[*]', source)).length, 1);
  assert.equal(await extractor.extract(json, '$.data<js>result.list[0]</js>$.name', source), '书名');
  const capture = 'result.match(/^([^_]+)_/)[1]';
  const branches = `h2@text<js>${capture}</js>||a:eq(1)@text<js>${capture}</js>||a@text<js>${capture}</js>`;
  assert.equal(await extractor.extract(doc, branches, source), '测试书');
  assert.equal(await extractor.extract(doc, 'h2@text<js>result.match(/missing/)[0]</js>', source), '');
  assert.equal(await extractor.extract(doc, 'h2@text<js>result.match(/(导航)/)[1]</js>', source), '导航');
  assert.equal(await extractor.extract(doc, '<js>""</js>||<js>"fallback"</js>', source), 'fallback');
  assert.equal(await extractor.extract(doc, '<js>"a||b"</js>||<js>"wrong"</js>', source), 'a||b');
  assert.equal(await extractor.extract(doc, '<js>/a||b/.source</js>||<js>"wrong"</js>', source), 'a||b');
  assert.equal(await extractor.extract(doc, '<js>"a"</js>&&<js>"b"</js>', source), 'a\nb');
  assert.equal(await extractor.extract(doc, 'h2@text@js:result || "fallback"', source), '目录导航');
  assert.equal(await extractor.extract(doc, 'h2@text<js>result.replace(/导航/, "内容")</js><js>result + "!"</js>', source), '目录内容!');
  await assert.rejects(() => extractor.extract(doc,
    '<js>throw new Error("visible failure")</js>||<js>"must not hide error"</js>', source), /visible failure/);
  const list = await extractor.selectList(doc, '<js>[]</js>||<js>["kept"]</js>', source);
  assert.equal(list.length, 1);
  assert.equal(list[0].payload, 'kept');

  const { LocalRuleScriptRuntime: runtime } = load(prefix + 'LocalRuleScriptRuntime');
  const mediaVariables = {};
  await runtime.evaluate('', origin, "source.put('type','audio');'ok';", source, mediaVariables);
  assert.equal(mediaVariables.__sourceContentType, 'audio');
  const http = stubs[prefix + 'LocalRuleHttpClient'].LocalRuleHttpClient;
  let requests = 0;
  http.fetch = async () => {
    requests++;
    return { ok: true, statusCode: 200, body: 'response', requestUrl: origin,
      headers: { 'X-Request-Id': 'abc', 'Content-Type': 'text/plain' }, errorMessage: '' };
  };
  const headerResult = await runtime.evaluate('', origin, `const response=java.get('${origin}',{});
    const headers=response.headers();JSON.stringify([headers.get('X-REQUEST-ID'),headers.get('absent'),
      headers.names().size(),headers.names().get(0),response.headers('x-request-id')]);`, source, {});
  assert.deepEqual(JSON.parse(headerResult), ['abc', null, 2, 'X-Request-Id', ['abc']]);
  assert.equal(requests, 1, 'A replay must not repeat the same request');
  http.fetch = async () => {
    requests++;
    return { ok: false, statusCode: 0, body: '', requestUrl: origin,
      headers: {}, errorMessage: 'fixture timeout' };
  };
  assert.equal(await runtime.evaluate('', origin,
    `const response=JSON.parse(java.ajax('${origin}/optional'));response.code===599?'optional fallback':response.data;`, source, {}), 'optional fallback');
  assert.equal(requests, 2);
  await assert.rejects(() => runtime.evaluate('', origin,
    `const response=JSON.parse(java.ajax('${origin}/required'));if(response.code===599)throw new Error(response.message);response.data;`, source, {}), /fixture timeout/);

  if (process.argv[2]) {
    const original = parser.parse(fs.readFileSync(process.argv[2], 'utf8')).sources[0];
    assert.ok(original, 'Original definition must import');
    const article = html({ 'header h2 a@text': ['测试书_测试作者【完结】'], 'span.note@text': ['[现代言情] 小说简介：公开简介'],
      'p.auth-span@text': ['2026-09-22'], 'header h2 a@href': ['/book/1.html'] });
    assert.equal(await extractor.extract(article, original.ruleSearch.name, original), '测试书');
    assert.equal(await extractor.extract(article, original.ruleSearch.author, original), '测试作者');
    assert.equal(await extractor.extract(article, original.ruleSearch.status, original), '完结');
    assert.equal(await extractor.extract(article, original.ruleSearch.kind, original), '现代言情');
    assert.equal(await extractor.extract(article, original.ruleSearch.intro, original), '公开简介');
    const alternate = html({ 'header h2 a@text': ['导航'], 'a:eq(1)@text': ['备选书_作者乙【连载】'], 'a@text': [] });
    assert.equal(await extractor.extract(alternate, original.ruleExplore.name, original), '备选书');
    const content = html({ '#text@html': [], '.book_con@html': [],
      'article.article-content@html': ['<p>公开测试正文</p><div class="pagination2">下一页</div>'] });
    assert.equal(await extractor.extract(content, original.ruleContent.content, original), '<p>公开测试正文</p>');
    console.log('PASS: original source import, metadata scripts, alternate cards and content cleanup');
  }
  console.log('PASS: page alternatives, script groups, bounded match compatibility, visible errors and compound CSS indexes');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
