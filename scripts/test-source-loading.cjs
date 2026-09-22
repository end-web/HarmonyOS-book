// Real rule services + headless Chromium DOM. No npm dependencies or network requests.
// DEVECO_HOME=<Release IDE> node scripts/test-source-loading.cjs [--benchmark]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawn } = require('node:child_process');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const browserPath = [process.env.CHROME_PATH,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => p && fs.existsSync(p));
if (!browserPath) throw new Error('Set CHROME_PATH to Chrome/Edge for the DOM regression');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const normalized = value => JSON.parse(JSON.stringify(value));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'listenbook-source-loading-'));
const browser = spawn(browserPath, ['--headless=new', '--disable-gpu', '--no-first-run',
  '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${temp}`, 'about:blank'],
{ windowsHide: true, stdio: 'ignore' });
let socket;
let sessionId;
let commandId = 0;
let bridgeCalls = 0;
const pending = new Map();
function send(method, params = {}, session = sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++commandId;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params, sessionId: session }));
  });
}
async function connect() {
  const portFile = path.join(temp, 'DevToolsActivePort');
  for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await delay(100);
  assert(fs.existsSync(portFile), 'Headless browser must start');
  const [port, endpoint] = fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/);
  socket = new WebSocket(`ws://127.0.0.1:${port}${endpoint}`);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const call = pending.get(message.id);
    if (!call) return;
    clearTimeout(call.timer);
    pending.delete(message.id);
    if (message.error) call.reject(new Error(message.error.message));
    else call.resolve(message.result);
  });
  const target = await send('Target.createTarget', { url: 'about:blank' });
  const attached = await send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
  sessionId = attached.sessionId;
}
const modules = new Map();
let sourceRevision = 0;
let loginRevision = 0;
let responseHtml = '';
let responseFetch;
let exploreCalls = 0;
let categoryResponse = async url => ({ books: [{ bookUrl: url, name: url }] });
const stubs = {
  '@kit.ArkWeb': { webview: {} },
  '@kit.BasicServicesKit': {},
  '@kit.ArkTS': { buffer: { from: Buffer.from }, util: {} },
  'service/WebEngineGate': { WebEngineGate: { instance: {} } },
  'service/CoverPrefetcher': { CoverPrefetcher: {} },
  'service/rulesource/LocalRuleScriptRuntime': { LocalRuleScriptRuntime: {
    hasScript: rule => /^(?:@?js:)|<\/?js>/i.test(rule.trim()),
    standaloneCode: rule => /^(?:@?js:)/i.test(rule.trim()) ? rule.trim().replace(/^@?js:/i, '') : '',
    evaluate: async () => { throw new Error('Script rules must use the ordinary execution path'); }
  } },
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: {
    isInitialized: () => false, getLoginRevision: () => loginRevision
  } },
  'service/rulesource/LocalRuleHttpClient': { LocalRuleHttpClient: {
    fetch: async (_source, url) => responseFetch ? responseFetch(url) : ({ ok: true, body: responseHtml, requestUrl: url })
  } },
  'service/rulesource/tingyou/TingYouSourceAdapter': { TingYouSourceAdapter: {} },
  'service/rulesource/tingyou/TingYouSourceIdentity': { TingYouSourceIdentity: { isSourceUrl: () => false } },
  'service/rulesource/talebook/TalebookSourceAdapter': { TalebookSourceAdapter: {} },
  'service/rulesource/talebook/TalebookSourceIdentity': { TalebookSourceIdentity: { isSourceUrl: () => false } },
  'service/SourceDataService': { SourceDataService: { getInvalidationCounter: () => sourceRevision } },
  'service/PreferenceService': { PreferenceService: {} },
  'service/BookSourceService': { BookSourceService: {
    getExploreBooksByUrl: async (_source, url) => { exploreCalls++; return categoryResponse(url); }
  } },
  'service/rulesource/LocalRulePanelService': { LocalRulePanelService: {
    load: async () => ({ entries: [{ title: '第一类', url: '/slow' }, { title: '第二类', url: '/fast' }] })
  } }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const filename = path.join(root, `${name}.ets`);
  let text = fs.readFileSync(filename, 'utf8');
  if (name.endsWith('/LocalRuleWebRuntime')) text = text.slice(0, text.indexOf('/** MainPage'));
  const compiled = ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  }).outputText;
  const module = { exports: {} };
  modules.set(name, module);
  vm.runInNewContext(compiled, { module, exports: module.exports, console, Map, Set, WeakMap, Error,
    URL, Date, JSON, setTimeout, clearTimeout, encodeURIComponent, decodeURIComponent,
    ObservedV2: value => value, Trace: () => {},
    require: id => load(id.startsWith('.') ? path.posix.normalize(path.posix.join(path.posix.dirname(name), id)) : id)
  }, { filename });
  return module.exports;
}
async function testDom() {
  const { LocalRuleWebRuntime } = load('service/rulesource/LocalRuleWebRuntime');
  const { LocalRuleStageExtractor: extractor } = load('service/rulesource/LocalRuleStageExtractor');
  const { LocalRuleDispatcher: dispatcher } = load('service/rulesource/LocalRuleDispatcher');
  const { LocalRuleSource } = load('model/LocalRuleSource');
  const runtime = LocalRuleWebRuntime.instance;
  runtime.setController({ runJavaScript: async expression => {
    bridgeCalls++;
    const result = await send('Runtime.evaluate', { expression, returnByValue: true });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  } });
  const source = LocalRuleSource.descriptor('https://fixture.invalid/', '书听 FM 目录规则');
  source.ruleToc.chapterList = '#playlist>ul li';
  source.ruleToc.chapterName = 'a@text';
  source.ruleToc.chapterUrl = 'a@href';
  const count = 1024;
  responseHtml = '<div id="playlist"><ul>' + Array.from({ length: count }, (_, i) =>
    `<li><a href="/play/${i}">第 ${i + 1} 章 &amp; 标题</a></li>`).join('') + '</ul></div>';
  const before = bridgeCalls;
  const start = performance.now();
  const batches = [];
  let finished = false;
  const chapters = await dispatcher.getBookToc(source, 'https://fixture.invalid/book/1', {}, items => {
    assert.equal(finished, false, 'Visible chapters must arrive before completion');
    batches.push(items);
  });
  finished = true;
  const optimizedMs = performance.now() - start;
  const optimizedCalls = bridgeCalls - before;
  assert.equal(chapters.length, count);
  assert.equal(chapters[1023].url, 'https://fixture.invalid/play/1023');
  assert.equal(chapters[1023].name, '第 1024 章 & 标题');
  assert.equal(chapters[1023].variables.chapterIndex, '1023');
  assert.equal(optimizedCalls, 33, 'One list call plus 32 bounded batches');
  assert.equal(batches[0].length, 16, 'First sixteen chapters are delivered immediately');
  assert.deepEqual(normalized(batches.flat()), normalized(chapters), 'Batches preserve IDs/order/variables without duplicates');
  console.log(`PASS: ${count} chapters, ${optimizedCalls} DOM bridge calls, ${optimizedMs.toFixed(0)} ms (Chromium fixture)`);
  if (process.argv.includes('--benchmark')) {
    const prefetch = extractor.prefetchHtmlFields;
    extractor.prefetchHtmlFields = async () => {};
    const oldBefore = bridgeCalls;
    const oldStart = performance.now();
    try {
      const baseline = await dispatcher.getBookToc(source, 'https://fixture.invalid/book/1');
      const baselineMs = performance.now() - oldStart;
      assert.deepEqual(normalized(chapters), normalized(baseline));
      assert.equal(bridgeCalls - oldBefore, 2049);
      console.log(`PASS: identical to sequential output; baseline ${baselineMs.toFixed(0)} ms, 2049 calls`);
    } finally { extractor.prefetchHtmlFields = prefetch; }
  }
  const html = '<section><a href="/one"> 一 &amp; 二 </a><a href="/two">三</a>' +
    '<script>globalThis.__unsafeRule = true</script></section>';
  const documents = [extractor.createDocument(html, 'https://fixture.invalid/book/1')];
  const rules = ['a.0@text', 'a:last@href', '@xpath://a/@href', 'a@text##三##四',
    'a@text@put:{saved:a.0@text}'];
  await extractor.prefetchHtmlFields(documents, rules);
  const variables = {};
  for (const rule of rules) {
    const result = await extractor.extract(documents[0], rule, source, variables);
    const original = await extractor.extract(extractor.createDocument(html, documents[0].baseUrl), rule, source, {});
    assert.equal(result, original, `Batch preserves ${rule}`);
  }
  assert.equal(variables.saved, '一 & 二');
  const inert = await send('Runtime.evaluate', { expression: 'globalThis.__unsafeRule === undefined', returnByValue: true });
  assert.equal(inert.result.value, true);
  await assert.rejects(runtime.selectBatch(new Array(33).fill('<a>x</a>'), []), /预算/);
  const oversized = extractor.createDocument(`<a>${'x'.repeat(129 * 1024)}</a>`, 'https://fixture.invalid/');
  await extractor.prefetchHtmlFields([oversized], ['a@text']);
  assert.equal(oversized.htmlFields.size, 0);
  assert.equal((await extractor.extract(oversized, 'a@text', source, {})).length, 129 * 1024);
  console.log('PASS: CSS/XPath, regex, variable order, inert HTML and budget fallback');
  const fullHtml = responseHtml;
  source.ruleToc.nextTocUrl = 'a.next@href';
  responseFetch = async url => {
    if (url.endsWith('/page2')) throw new Error('page two failed');
    return { ok: true, body: fullHtml + '<a class="next" href="/page2">next</a>', requestUrl: url };
  };
  const partial = [];
  await assert.rejects(dispatcher.getBookToc(source, 'https://fixture.invalid/book/1', {},
    items => partial.push(...items)), /page two failed/);
  assert.equal(partial.length, 1024, 'Earlier pages remain usable when a later page fails');
  responseFetch = undefined;
  source.ruleToc.nextTocUrl = '';
  console.log('PASS: first batch before completion; failed later page does not masquerade as a complete TOC');
}
async function testHome() {
  const { HomeSourceService: home } = load('service/rulesource/HomeSourceService');
  const { LocalRuleSource } = load('model/LocalRuleSource');
  const source = LocalRuleSource.descriptor('https://home.invalid/', '首页测试');
  source.enabledExplore = true;
  source.exploreUrl = 'fixture';
  const slow = deferred();
  const firstContent = deferred();
  categoryResponse = async url => url === '/slow' ? slow.promise : { books: [{ bookUrl: url, name: url }] };
  const request = home.loadHome(source, false, content => {
    if (content.blocks.length) firstContent.resolve(content.blocks.map(block => block.title));
  });
  assert.deepEqual(normalized(await firstContent.promise), ['第二类']);
  const duplicate = home.loadHome(source);
  assert.equal(exploreCalls, 2);
  slow.resolve({ books: [{ bookUrl: '/slow', name: '慢分类' }] });
  const result = await request;
  assert.equal(await duplicate, result);
  assert.deepEqual(normalized(result.blocks.map(block => block.title)), ['第一类', '第二类']);
  await home.loadHome(source);
  assert.equal(exploreCalls, 2, 'Switching back reuses source cache');
  await home.loadHome(source, true);
  assert.equal(exploreCalls, 4, 'Explicit refresh bypasses cache');
  sourceRevision++;
  await home.loadHome(source);
  assert.equal(exploreCalls, 6, 'Definition change invalidates cache');
  loginRevision++;
  await home.loadHome(source);
  assert.equal(exploreCalls, 8, 'Login change invalidates cache');
  sourceRevision++;
  categoryResponse = async url => {
    if (url === '/slow') throw new Error('fixture failure');
    return { books: [{ bookUrl: url, name: url }] };
  };
  assert.equal((await home.loadHome(source)).blocks.length, 1);
  sourceRevision++;
  categoryResponse = async () => { throw new Error('fixture failure'); };
  await assert.rejects(home.loadHome(source), /fixture failure/);
  const failures = exploreCalls;
  await assert.rejects(home.loadHome(source), /fixture failure/);
  assert.equal(exploreCalls, failures + 2, 'Failures must remain retryable');
  console.log('PASS: progressive home, in-flight reuse, source cache, refresh, invalidation and isolated failures');
}
async function testDetailCache() {
  const page = fs.readFileSync(path.join(root, 'pages/BookDetailPage.ets'), 'utf8');
  const start = page.indexOf('  private async findBookById(');
  const end = page.indexOf('  private async loadTocFromSource(', start);
  const compiled = ts.transpileModule(`export class Detail { ${page.slice(start, end)} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const exports = {};
  let cached;
  let stored;
  let reads = 0;
  let diskFailure = false;
  vm.runInNewContext(compiled, { exports, SearchCache: { get: () => cached },
    BookSourceService: { pendingAudioBook: () => undefined },
    DataService: { getBookById: async () => {
      reads++;
      if (diskFailure) throw new Error('disk failure');
      return stored;
    } }, DownloadStore: { getBook: async () => undefined }, DownloadService: {}, Error });
  const detail = new exports.Detail();
  detail.getUIContext = () => ({ getHostContext: () => ({}) });
  detail.needsAudioTocLoad = value => !value.chapters.length || (value.chapters.length === 1 && value.chapterCount > 1);
  cached = { id: 'book', title: '最新标题', intro: '最新简介', chapterCount: 2, chapters: [] };
  stored = { chapters: [{ id: 'c1' }, { id: 'c2' }], chapterCount: 2, variables: { key: 'toc-context' } };
  const book = await detail.findBookById('book');
  assert.equal(book, cached);
  assert.equal(book.intro, '最新简介');
  assert.equal(book.chapters, stored.chapters);
  assert.equal(book.variables.key, 'toc-context');
  await detail.findBookById('book');
  assert.equal(reads, 1, 'Complete memory cache avoids disk');
  cached = { id: 'new-book', chapters: [], chapterCount: 0 };
  diskFailure = true;
  assert.equal(await detail.findBookById('new-book'), cached, 'Disk failure keeps online loading available');
  console.log('PASS: detail restores saved TOC without losing metadata; complete cache and disk-failure fallback');
}
async function testAudioLoad() {
  const saved = [];
  const homeFacade = stubs['service/BookSourceService'];
  delete stubs['service/BookSourceService'];
  stubs['service/DataService'] = { DataService: { upsertCachedBook: async book => {
    saved.push({ count: book.chapters.length, complete: book.tocComplete });
  } } };
  stubs['service/DownloadPolicy'] = { DownloadPolicy: {} };
  stubs['service/rulesource/NativeRuleSourceDispatcher'] = { NativeRuleSourceDispatcher: { isSource: () => false } };
  stubs['model/TextReading'] = { TextSourceError: Error };
  const { BookSourceService: service } = load('service/BookSourceService');
  const { SearchCache: cache } = load('utils/SearchCache');
  const { LocalRuleSource } = load('model/LocalRuleSource');
  const source = LocalRuleSource.descriptor('https://fixture.invalid/', '渐进目录');
  source.ruleToc.chapterList = '#playlist>ul li';
  source.ruleToc.chapterName = 'a@text';
  source.ruleToc.chapterUrl = 'a@href';
  stubs['service/rulesource/LocalRuleSourceRepository'].LocalRuleSourceRepository.getByUrl = async () => source;
  service.getBookInfo = async () => null;
  const makeBook = id => ({ id, title: '测试书', author: '', narrator: '', cover: '', category: '', intro: '',
    totalDuration: 0, chapterCount: 0, rating: 0, tags: [], chapters: [], bookUrl: 'https://fixture.invalid/book/1',
    sourceUrl: source.bookSourceUrl, chaptersDescending: true });
  const first = deferred();
  const request = service.loadAudioBook(makeBook('progressive'), book => {
    if (book.chapters.length) first.resolve(book);
  });
  const playable = await first.promise;
  const playerChapters = playable.chapters;
  assert.equal(playable.tocComplete, false);
  assert.equal(playable.chapters.length, 16);
  assert.equal(saved.length, 0, 'No partial catalog saved');
  assert.equal(cache.get('progressive'), playable, 'Player receives canonical growing book');
  const reentered = service.loadAudioBook(makeBook('progressive'), () => {});
  const completed = await request;
  assert.equal(await reentered, completed, 'Reentry joins the same task');
  assert.equal(completed.chapters, playerChapters, 'Early player retains the growing chapter array');
  assert.equal(playerChapters.length, 1024);
  assert.equal(completed.tocComplete, true);
  assert.equal(completed.chaptersDescending, true);
  assert.deepEqual(saved, [{ count: 1024, complete: true }]);
  assert.equal(service.pendingAudioBook('progressive'), undefined);
  source.ruleToc.nextTocUrl = 'a.next@href';
  responseFetch = async url => {
    if (url.endsWith('/page2')) throw new Error('page two failed');
    return { ok: true, body: responseHtml + '<a class="next" href="/page2">next</a>', requestUrl: url };
  };
  await assert.rejects(service.loadAudioBook(makeBook('failure'), () => {}), /page two failed/);
  assert.equal(cache.get('failure').tocComplete, false);
  assert.equal(saved.length, 1, 'Failed partial TOC never persisted');
  responseFetch = undefined;
  source.ruleToc.nextTocUrl = '';
  await service.loadAudioBook(makeBook('failure'), () => {});
  assert.equal(saved.length, 2, 'Failed task can be retried');
  stubs['service/BookSourceService'] = homeFacade;
  console.log('PASS: playable partial catalog, reentry coalescing, canonical array growth, complete-only persistence and retry');
}
(async () => {
  try {
    await connect();
    await testDom();
    await testHome();
    await testDetailCache();
    await testAudioLoad();
  } finally {
    if (socket) {
      try { await send('Browser.close', {}, undefined); } catch (_) { /* Browser may close before replying. */ }
      socket.close();
    }
    browser.kill();
    await delay(200);
    fs.rmSync(temp, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
