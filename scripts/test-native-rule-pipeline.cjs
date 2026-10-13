// Offline end-to-end native source import, dispatch and portable export.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const calls = [];
const warmedOrigins = [];
let bridgeCalls = 0;
const ark = { buffer: { from: Buffer.from }, url: { URL: class extends URL { static parseURL(value, base) { return new URL(value, base); } } }, util: {
  TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
  TextDecoder: { create: (encoding, options) => ({ decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes) }) },
  Base64Helper: class { decodeSync(value) { return Buffer.from(value, 'base64'); } }
} };
const cryptography = { cryptoFramework: { createMd(algorithm) {
  const digest = crypto.createHash(algorithm.toLowerCase());
  return { async update(blob) { digest.update(blob.data); }, async digest() { return { data: digest.digest() }; } };
} } };
const listing = '<ul class="qm-pic-txt"><li><div class="pic"><a href="/album/1-245.html"><img src="/cover.jpg"></a></div><h3 class="s-tit">花颜策</h3><p class="s-txt">主播：测试主播</p><span class="s-tags">言情</span><span class="s-name">小说</span><p class="s-des">简介 &amp; 介绍</p></li></ul>';
const detail = '<meta name="keywords" content="花颜策,有声"><dl><dt><img src="/cover.jpg"></dt></dl><div class="sub-tags">主播：测试主播</div><dl id="book_intro"><dd>内容介绍</dd></dl><div class="sub-cols"><span>状态：连载</span><span>类别：言情</span><span>更新：2026-10-01</span></div><ul id="playlist"><li><a href="/play/1-245-8.html">第九集</a></li><li><a href="/play/1-245-9.html">第十集</a></li></ul>';
const http = { LocalRuleHttpClient: {
  preconnectNative(origin) { warmedOrigins.push(origin); },
  async fetchNativePlan(_source, plan) {
    calls.push(JSON.parse(JSON.stringify(plan)));
    const address = new URL(plan.url);
    let body;
    if (address.pathname === '/e/search/index.php' || address.pathname.startsWith('/listinfo-')) body = listing;
    else if (address.pathname === '/album/1-245.html') body = detail;
    else if (address.hostname === 'm.mekui.com' && address.pathname === '/ecmsapi/index.php') body = JSON.stringify({ data: { SeriesUrl: 'https://media.example/audio.mp3' } });
    else throw new Error(`Unexpected fixture route: ${address.pathname}`);
    return { ok: true, statusCode: 200, requestUrl: plan.url, body, headers: {} };
  },
  async hydrateCookies() {}, getCookieHeader() { return ''; }
} };
function forbiddenModule(name) {
  return new Proxy({}, { get(_target, field) {
    return new Proxy(function () {}, { get() { return () => { bridgeCalls++; throw new Error(`Forbidden legacy bridge: ${name}.${String(field)}`); }; },
      apply() { bridgeCalls++; throw new Error(`Forbidden legacy bridge: ${name}`); } });
  } });
}
function load(filename) {
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} }; cache.set(filename, module);
  const source = fs.readFileSync(filename, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const localRequire = name => {
    if (name === '@kit.ArkTS') return ark;
    if (name === '@kit.CryptoArchitectureKit') return cryptography;
    if (name === '@kit.BasicServicesKit') return { deviceInfo: { sdkApiVersion: 20, deviceType: 'phone' } };
    if (name.endsWith('/LocalRuleHttpClient')) return http;
    if (name.endsWith('/CoverPrefetcher')) return { CoverPrefetcher: { registerHeaders() {} } };
    if (/LocalRule(?:Script|QuickJs|Browser|ArkWeb)/.test(name)) return forbiddenModule(name);
    if (!name.startsWith('.')) throw new Error(`Unexpected platform dependency: ${name}`);
    return load(path.resolve(path.dirname(filename), name + '.ets'));
  };
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename })(localRequire, module, module.exports);
  return module.exports;
}
const base = path.join(root, 'service/rulesource');
const { LocalRuleSourceImportParser: Parser } = load(path.join(base, 'LocalRuleSourceImportParser.ets'));
const { LocalRuleSourceCodec: Codec } = load(path.join(base, 'LocalRuleSourceCodec.ets'));
const { NativeSourceDefinition: Definition } = load(path.join(base, 'native/NativeSourceDefinition.ets'));
const { NativeRuleDispatcher: Dispatcher } = load(path.join(base, 'native/NativeRuleDispatcher.ets'));
const example = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../docs/examples/shuyinfm-native.json'), 'utf8'));
async function run() {
  const report = Parser.parse(JSON.stringify(example));
  assert.equal(report.sources.length, 1);
  assert.equal(report.unsupportedCount, 0);
  const source = report.sources[0];
  assert.equal(source.canExecute(), true);
  assert.equal(source.hasSearchCapability(), true);
  assert.equal(source.isAudio(), true);
  const categories = Definition.panel(source).entries;
  assert.equal(categories.length, 17);
  const books = await Dispatcher.search(source, '花颜 策&声', 1, {});
  assert.equal(books.length, 1);
  assert.equal(books[0].name, '花颜策');
  assert.equal(books[0].author, '测试主播');
  assert.equal(books[0].bookUrl, 'https://www.shuyinfm.com/album/1-245.html');
  assert.equal(calls[0].method, 'POST');
  assert.equal(new URLSearchParams(calls[0].body).get('keyboard'), '花颜 策&声');
  assert.equal(calls[0].headers['content-type'], 'application/x-www-form-urlencoded; charset=utf-8');
  const discovery = await Dispatcher.explore(source, categories[0].url, 2, {}, 20);
  assert.equal(discovery.books.length, 1);
  assert.equal(new URL(calls[1].url).pathname, '/listinfo-1-1.html');
  assert.equal(calls[1].method, 'GET');
  const info = await Dispatcher.detail(source, books[0].bookUrl, {});
  assert.equal(info.name, '花颜策');
  assert.equal(info.author, '测试主播');
  assert.equal(info.kind, '言情');
  assert.equal(info.tocUrl, books[0].bookUrl);
  const chapters = await Dispatcher.toc(source, info.tocUrl, {});
  assert.deepEqual(warmedOrigins, ['https://m.mekui.com'], 'detail/toc warm one origin without executing a signed request');
  assert.equal(chapters.length, 2);
  assert.equal(chapters[0].url, 'https://www.shuyinfm.com/play/1-245-8.html');
  assert.equal(chapters[0].url.includes('token='), false);
  const now = Date.now;
  try {
    Date.now = () => 1800000000000;
    const audio = await Dispatcher.content(source, chapters[0].url, chapters[0].variables);
    assert.equal(audio.audioUrl, 'https://media.example/audio.mp3');
    assert.equal(audio.requestHeaders.referer, 'https://www.shuyinfm.com/');
    const first = new URL(calls.at(-1).url);
    assert.equal(first.searchParams.get('t'), '1800000000');
    assert.equal(first.searchParams.get('id'), '245');
    assert.equal(first.searchParams.get('movieId'), '9');
    const template = example.rules.content.bindings[2].value.value;
    const signed = template.replace('{{albumId}}', '245').replace('{{movieId}}', '9').replace('{{timestamp}}', first.searchParams.get('t'));
    assert.equal(first.searchParams.get('token'), crypto.createHash('md5').update(signed).digest('hex'));
    Date.now = () => 1800000005000;
    await Dispatcher.content(source, chapters[0].url, chapters[0].variables);
    const second = new URL(calls.at(-1).url);
    assert.equal(second.searchParams.get('t'), '1800000005');
    assert.notEqual(second.searchParams.get('token'), first.searchParams.get('token'));
  } finally { Date.now = now; }
  source.bookSourceName = '导出名称';
  source.enabled = false;
  source.enabledExplore = false;
  source.isLocked = true;
  source.isPinned = true;
  source.customOrder = 7;
  const portable = JSON.parse(Codec.stringify(source));
  assert.equal(portable.source.name, '导出名称');
  assert.equal(portable.format, 'jianting.source');
  assert.equal(portable.version, 1);
  assert.deepEqual(Object.keys(portable).sort(), ['format', 'rules', 'settings', 'source', 'version']);
  assert.equal('version' in portable.rules, false);
  for (const field of ['nativeRulesJson', 'nativeSearch', 'nativeRulesValid', 'rawSourceJson']) assert.equal(field in portable, false);
  const restored = Parser.parse(JSON.stringify(portable)).sources[0];
  assert.equal(restored.canExecute(), true);
  assert.deepEqual(portable.settings, { enabled: false, discoveryEnabled: false, locked: true, pinned: true, order: 7 });
  assert.equal(restored.enabled, false);
  assert.equal(restored.enabledExplore, false);
  assert.equal(restored.isLocked, true);
  assert.deepEqual(Definition.rules(restored), Definition.rules(source));
  assert.equal(Definition.panel(restored).entries.length, 17);
  const separateDefinition = structuredClone(example);
  separateDefinition.source.id = 'https://identity.example/stable-source';
  separateDefinition.rules.search.request.url.value = '/e/search/index.php';
  const separateIdentity = Parser.parse(JSON.stringify(separateDefinition)).sources[0];
  assert.equal(separateIdentity.bookSourceUrl, 'https://identity.example/stable-source');
  assert.equal(separateIdentity.nativeBaseUrl, example.source.baseUrl);
  const separateBooks = await Dispatcher.search(separateIdentity, '花颜策', 1, {});
  assert.equal(separateBooks[0].sourceUrl, 'https://identity.example/stable-source');
  assert.equal(new URL(calls.at(-1).url).origin, new URL(example.source.baseUrl).origin);
  assert.equal(Parser.parse(JSON.stringify({ ...example, source: { ...example.source, id: '' } })).sources.length, 0);
  const beforeInvalid = calls.length;
  for (const variant of [
    { ...example, version: 2 },
    { ...example, rules: { ...example.rules, version: 2 } },
    { ...example, jsLib: 'throw new Error("must never run")' },
    { ...example, ruleToc: { chapterUrl: '<js>throw new Error("must never run")</js>' } },
    { ...example, searchUrl: 'https://legacy.example/search' },
    { ...example, rules: { ...example.rules, content: { format: 'text', fields: [{ name: 'content', value: { kind: 'javascript', value: '1' } }] } } },
    { ...example, source: { ...example.source, type: 'video' } },
    { ...example, settings: { enabled: 'yes' } }
  ]) {
    const invalid = Parser.parse(JSON.stringify(variant));
    assert.ok(invalid.unsupportedCount + invalid.rejectedCount > 0);
    for (const rejected of invalid.sources) {
      assert.equal(rejected.canExecute(), false);
      await assert.rejects(() => Dispatcher.content(rejected, chapters[0].url, {}));
    }
  }
  assert.equal(calls.length, beforeInvalid);
  assert.equal(bridgeCalls, 0);
  console.log('PASS native pipeline: import, 17 categories, search, discovery, detail, stable toc, fresh signatures, export, rejected scripts');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
