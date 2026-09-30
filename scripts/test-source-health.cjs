// Run with DEVECO_HOME pointing to the installed Release IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(file, dependencies = {}) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8')
    .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, ''), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { exports, console, Error, Map, Set,
    require: name => dependencies[name] || {} });
  return exports;
}
const model = compile('model/LocalRuleSource.ets');
const { LocalRuleSource, LocalRuleSourceStatus: status } = model;
let searchCalls = 0, exploreCalls = 0, contentCalls = 0;
let searchError = true, emptySearch = false, emptyExplore = false, paidOnly = false;
let cancel = false, cancelOnSearch = false, cancelOnExplore = false;
const candidate = { name: '示例', bookUrl: 'https://fixture/book', contentType: 'text', variables: {} };
const dispatcher = {
  searchForHealthCheck: async () => {
    searchCalls++;
    if (cancelOnSearch) cancel = true;
    if (searchError) throw new Error('搜索接口不可用');
    return emptySearch ? [] : [candidate];
  },
  explore: async () => {
    exploreCalls++;
    if (cancelOnExplore) cancel = true;
    return { books: emptyExplore ? [] : [candidate] };
  },
  resolveContent: async () => { contentCalls++; return { content: '实际正文' }; }
};
const { BookSourceService: service } = compile('service/BookSourceService.ets', {
  '../model/LocalRuleSource': model,
  './DownloadPolicy': compile('service/DownloadPolicy.ets'),
  './rulesource/LocalRuleDispatcher': { LocalRuleDispatcher: dispatcher },
  './rulesource/NativeRuleSourceDispatcher': { NativeRuleSourceDispatcher: {
    isSource: () => false, isNonRetryableHealthError: () => false
  } },
  './rulesource/talebook/TalebookSourceIdentity': { TalebookSourceIdentity: { isSourceUrl: () => false } },
  './rulesource/LocalRulePanelService': { LocalRulePanelService: {
    load: async () => ({ entries: [{ url: 'https://fixture/discover' }] })
  } },
  './rulesource/LocalRuleDiagnostics': { LocalRuleDiagnostics: { open: () => ({}), close() {} } }
});
// Isolate platform/detail requests, keeping health orchestration and chapter validation real.
service.getBookInfo = async () => ({ tocUrl: 'https://fixture/toc', variables: {} });
service.getBookToc = async () => [{ name: '第一章', url: 'https://fixture/chapter', isVip: paidOnly }];
service.resolveAudioRequest = async () => { contentCalls++; return { url: 'https://fixture/audio.mp3' }; };
function source() {
  const result = new LocalRuleSource();
  result.bookSourceUrl = 'https://fixture';
  result.enabled = false;
  result.enabledExplore = true;
  result.exploreUrl = 'https://fixture/discover';
  result.searchUrl = 'https://fixture/search';
  result.ruleSearch.bookList = '.books';
  result.ruleSearch.name = '.name';
  result.ruleSearch.bookUrl = 'a@href';
  return result;
}
async function run() {
  for (const method of ['testLocalSource', 'testLocalSourceAvailability']) {
    for (const type of ['text', 'audio']) {
      const item = source();
      item.bookSourceType = type === 'audio' ? 1 : 0;
      candidate.contentType = type;
      const result = await service[method](item, '测试');
      assert.equal(result.status, status.READY);
      assert.match(result.message, /部分可用.*搜索接口不可用/);
      assert.match(result.message, type === 'audio' ? /音频/ : /正文/);
      assert.equal(item.enabled, false);
      assert.equal(item.enabledExplore, true);
    }
    candidate.contentType = 'text';
    const missingSearch = source();
    missingSearch.searchUrl = '';
    const before = searchCalls;
    assert.equal((await service[method](missingSearch, '测试')).status, status.READY);
    assert.equal(searchCalls, before, 'missing search rules must bypass search');
    emptyExplore = true;
    const failed = await service[method](source(), '测试');
    assert.equal(failed.status, status.FAILED);
    assert.match(failed.message, /搜索接口不可用.*发现\/阅读未通过/);
    emptyExplore = false;
    paidOnly = true;
    const contentBefore = contentCalls;
    assert.equal((await service[method](source(), '测试')).status, status.FAILED);
    assert.equal(contentCalls, contentBefore, 'fallback must not sample paid chapters');
    paidOnly = false;
    const disabled = source();
    disabled.enabledExplore = false;
    const exploresBefore = exploreCalls;
    assert.equal((await service[method](disabled, '测试')).status, status.FAILED);
    assert.equal(exploreCalls, exploresBefore);
    searchError = false;
    emptySearch = true;
    const empty = await service[method](source(), '测试');
    assert.equal(empty.status, status.READY);
    assert.match(empty.message, /暂无匹配/);
    assert.equal(exploreCalls, exploresBefore);
    emptySearch = false;
    assert.equal((await service[method](source(), '测试')).status, status.READY);
    assert.equal(exploreCalls, exploresBefore, 'successful search must not add discovery requests');
    searchError = true;
  }
  cancelOnSearch = true;
  const beforeCancel = exploreCalls;
  await assert.rejects(service.testLocalSourceAvailability(source(), '测试', () => cancel), /已取消/);
  assert.equal(exploreCalls, beforeCancel);
  cancelOnSearch = false;
  cancel = false;
  cancelOnExplore = true;
  await assert.rejects(service.testLocalSourceAvailability(source(), '测试', () => cancel), /已取消/);
  console.log('PASS: single/bulk health fallback, text/audio, missing rules, empty discovery, paid chapters, disabled discovery, empty/successful search and cancellation');
}
async function testDebug() {
  const diagnosticsModule = compile('service/rulesource/LocalRuleDiagnostics.ets');
  const diagnostics = diagnosticsModule.LocalRuleDiagnostics;
  let failedSearch = true, empty = false, stop = false, audio = false;
  const calls = [];
  const { LocalRuleDebugService: debug } = compile('service/rulesource/LocalRuleDebugService.ets', {
    './LocalRuleDiagnostics': diagnosticsModule,
    './NativeRuleSourceDispatcher': { NativeRuleSourceDispatcher: { isSource: () => false } },
    './LocalRulePanelService': { LocalRulePanelService: {
      load: async () => { calls.push('panel'); return { entries: [{ url: '/empty' }, { url: '/books' }] }; }
    } },
    './LocalRuleDispatcher': { LocalRuleDispatcher: {
      searchForHealthCheck: async (_source, _keyword, _page, vars) => {
        calls.push('search');
        if (stop) diagnostics.cancel(vars);
        if (failedSearch) throw new Error('搜索请求失败：HTTP 400');
        return [candidate];
      },
      explore: async (_source, url) => {
        calls.push(url);
        return { books: empty || url === '/empty' ? [] : [candidate] };
      },
      getBookInfo: async () => { calls.push('detail'); return { name: '示例', tocUrl: '/toc' }; },
      getBookToc: async () => {
        calls.push('toc');
        const free = { url: '/free', variables: { chapterToken: 'fixture' } };
        return failedSearch ? [{ url: '/paid', isPay: true }, free] : [free];
      },
      resolveContent: async (_source, url, vars) => {
        calls.push(url);
        assert.equal(vars.chapterToken, 'fixture');
        return { title: '章节', content: audio ? '' : '实际正文', audioUrl: audio ? 'https://fixture/a.mp3' : '' };
      }
    } }
  });
  async function execute(stage) {
    calls.length = 0;
    const logs = [];
    const vars = diagnostics.open(event => logs.push(event));
    try { return { result: await debug.run(source(), stage, '我的', '', vars), logs }; }
    finally { diagnostics.close(vars); }
  }
  for (const type of ['text', 'audio']) {
    candidate.contentType = type;
    audio = type === 'audio';
    const { result, logs } = await execute('full');
    assert.equal(result.success, true);
    assert.match(result.data, /部分可用.*\n搜索未通过：搜索请求失败：HTTP 400/);
    assert.deepEqual(calls, ['search', 'panel', '/empty', '/books', 'detail', 'toc', '/free']);
    assert.ok(logs.some(event => event.stage === 'search' && event.level === 'warn'));
    assert.ok(logs.some(event => event.stage === 'content' && event.level === 'success'));
  }
  assert.equal((await execute('search')).result.success, false);
  assert.deepEqual(calls, ['search'], 'search-only debugging must keep its original scope');
  empty = true;
  const failed = (await execute('full')).result;
  assert.equal(failed.success, false);
  assert.match(failed.error, /HTTP 400.*未提取到书籍/);
  empty = false;
  stop = true;
  assert.match((await execute('full')).result.error, /调试已停止/);
  assert.deepEqual(calls, ['search'], 'cancelled search must not fall back');
  stop = false;
  failedSearch = false;
  assert.equal((await execute('full')).result.success, true);
  assert.equal(calls.includes('panel'), false);
  console.log('PASS: debug full-chain HTTP 400 fallback, text/audio, category fallback, public chapter variables, search-only scope, combined errors and cancellation');
}
run().then(testDebug).catch(error => { console.error(error); process.exitCode = 1; });
