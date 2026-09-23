// Real request/session/browser services with simulated platform I/O; no live websites or accounts.
// DEVECO_HOME=<Release IDE> node scripts/test-local-rule-sessions.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const prefix = 'service/rulesource/';
const modules = new Map();
const saved = new Map();
const requests = [];
let planFactory;
let respond = async () => ({ statusCode: 200, headers: {}, body: '<p>ok</p>' });
let scriptResult = '';
let leases = 0;
const stubs = {
  '@kit.ArkTS': { buffer: { from: Buffer.from }, url: { URL }, util: { generateRandomUUID: () => randomUUID() } },
  'utils/CharsetCodec': { CharsetCodec: {} },
  '@kit.ArkWeb': { webview: { WebCookieManager: {
    clearAllCookiesSync() {}, configCookieSync() {}, fetchCookieSync: () => ''
  } } },
  'service/WebEngineGate': { WebEngineGate: { instance: {} } },
  'service/http/HttpClient': { HttpClient: { request: async (url, options) => {
    requests.push({ url, headers: { ...options.headers } });
    return { ...await respond(url), url };
  } } },
  [prefix + 'LocalRuleSourceRepository']: { LocalRuleSourceRepository: {
    isInitialized: () => true, readScriptState: async () => '',
    listCookies: async sourceUrl => [...saved.values()].filter(cookie => cookie.sourceUrl === sourceUrl),
    saveCookie: async cookie => saved.set(cookie.sourceUrl + '\n' + cookie.origin, cookie),
    clearCookie: async (source, origin) => saved.delete(source + '\n' + origin), get: async () => ({})
  } },
  [prefix + 'LocalRuleDiagnostics']: { LocalRuleDiagnostics: { check() {}, record() {} } },
  [prefix + 'LocalRuleRequestLimiter']: { LocalRuleRequestLimiter: { acquire: async () => ({ release() {} }) } },
  [prefix + 'LocalRuleUrlAnalyzer']: { LocalRuleUrlAnalyzer: {
    analyze: () => planFactory(), parseHeaders: text => text ? JSON.parse(text) : {},
    origin: address => new URL(address).origin, resolveUrl: (base, address) => new URL(address, base).href
  } },
  [prefix + 'LocalRuleScriptRuntime']: { LocalRuleScriptRuntime: { evaluateBrowserSnapshot: async () => scriptResult } },
  [prefix + 'LocalRuleBrowserActions']: { LocalRuleBrowserActions: { PREFIX: 'local-rule-browser:' } },
  [prefix + 'LocalRuleScriptActions']: { LocalRuleScriptActions: { PREFIX: 'local-rule-action:' } },
  [prefix + 'LocalRuleQuickJsRuntime']: {
    LocalRuleQuickJsRequest: class {},
    LocalRuleQuickJsRuntime: { execute: async request => ({ success: true,
      value: vm.runInNewContext(request.script, {}, { timeout: 2000 }) }) }
  },
  [prefix + 'LocalRuleTlsTrustStore']: { LocalRuleTlsTrustStore: {} },
  [prefix + 'LocalRuleWebSession']: { LocalRuleWebSession: {
    acquire: async () => { leases++; return 1; }, release: () => { leases--; }
  } }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const filename = path.join(root, name + '.ets');
  const module = { exports: {} };
  modules.set(name, module);
  let sourceText = fs.readFileSync(filename, 'utf8');
  if (name.endsWith('/LocalRuleBrowserRuntime')) sourceText = sourceText.slice(0, sourceText.indexOf('@Component'));
  const code = ts.transpileModule(sourceText, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout, clearTimeout,
    ObservedV2: value => value, Trace: () => {},
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
const { LocalRuleRequestPlan } = load(prefix + 'LocalRuleRuntimeTypes');
const { LocalRuleSource } = load('model/LocalRuleSource');
const { LocalRuleHttpClient: http } = load(prefix + 'LocalRuleHttpClient');
const source = LocalRuleSource.descriptor('https://session.example', 'Declared session');
source.enabledCookieJar = false;
function makePlan(url = 'https://session.example/api?csrf=query') {
  const plan = new LocalRuleRequestPlan();
  plan.url = url;
  plan.headers = { Cookie: 'explicit=kept; csrf=explicit' };
  plan.session = { queryCookies: { csrf: 'csrf' }, generatedCookies: { 'visitor.id': '@uuid' }, referer: 'origin' };
  return plan;
}
async function run() {
  await http.saveWebCookies(source.bookSourceUrl, source.bookSourceUrl, 'stored=kept; csrf=stored');
  planFactory = makePlan;
  const firstResponse = await http.fetch(source, 'fixture');
  assert.equal(firstResponse.ok, true, firstResponse.errorMessage);
  const first = requests.at(-1).headers;
  assert.match(first.Cookie, /stored=kept/);
  assert.match(first.Cookie, /explicit=kept/);
  assert.match(first.Cookie, /csrf=query/);
  assert.equal(first.Referer, 'https://session.example/');
  const visitor = first.Cookie.match(/visitor\.id=([^;]+)/)[1];
  http.clearCookieCacheBatch([source.bookSourceUrl]);
  assert.equal((await http.fetch(source, 'fixture')).ok, true);
  assert.ok(requests.at(-1).headers.Cookie.includes('visitor.id=' + visitor), 'Explicit session survives jar disable and reload');
  const other = LocalRuleSource.descriptor('https://other-source.example', 'Isolated source');
  other.enabledCookieJar = false;
  assert.equal((await http.fetch(other, 'fixture')).ok, true);
  assert.ok(!requests.at(-1).headers.Cookie.includes(visitor), 'Different sources cannot share generated identities');
  planFactory = () => {
    const plan = new LocalRuleRequestPlan();
    plan.url = 'https://session.example/plain';
    return plan;
  };
  await http.fetch(source, 'fixture');
  assert.equal(requests.at(-1).headers.Cookie, undefined, 'Disabled jar stays off without explicit session');
  await http.saveWebCookies(source.bookSourceUrl, 'https://redirect.example', 'destination=own');
  planFactory = () => {
    const plan = makePlan();
    plan.headers.Authorization = 'test-only';
    plan.headers.Origin = source.bookSourceUrl;
    plan.headers.Host = 'session.example';
    return plan;
  };
  respond = async url => url.startsWith(source.bookSourceUrl)
    ? { statusCode: 302, headers: { Location: 'https://redirect.example/final' }, body: '' }
    : { statusCode: 200, headers: {}, body: 'ok' };
  assert.equal((await http.fetch(source, 'fixture')).ok, true);
  const redirected = requests.at(-1).headers;
  assert.equal(redirected.Cookie, 'destination=own');
  for (const name of ['Origin', 'Referer', 'Authorization', 'Host']) assert.equal(redirected[name], undefined);
  console.log('PASS: declared cookie precedence, disabled-jar persistence, source isolation and cross-origin redirect headers');

  const { LocalRuleBrowserRuntime } = load(prefix + 'LocalRuleBrowserRuntime');
  const browser = LocalRuleBrowserRuntime.instance;
  browser.attach({ clearSslCache() {}, setCustomUserAgent() {}, loadUrl() {}, stop() {} });
  browser.schedule = task => task.resolve(task.initial);
  browser.snapshot = async () => ({ html: '<p>rendered after action</p>', url: source.bookSourceUrl, state: '{}', media: [] });
  const plan = makePlan();
  plan.webJs = 'document.querySelector("button").click()';
  const initial = () => ({ ok: true, body: '<p>before</p>', requestUrl: source.bookSourceUrl, headers: {}, resourceUrls: [] });
  assert.equal((await browser.render(source, plan, initial(), {})).body, '<p>rendered after action</p>');
  scriptResult = 'explicit script output';
  assert.equal((await browser.render(source, plan, initial(), {})).body, scriptResult);
  assert.equal(leases, 0, 'Browser lease is released after both paths');
  console.log('PASS: empty webJs result falls back to current DOM; explicit output and lease cleanup preserved');

  // Exercise the real replay runtime: every evaluation gets a fresh VM, as with QuickJS.
  const runtimeStub = stubs[prefix + 'LocalRuleScriptRuntime'];
  delete stubs[prefix + 'LocalRuleScriptRuntime'];
  const runtime = load(prefix + 'LocalRuleScriptRuntime').LocalRuleScriptRuntime;
  runtimeStub.LocalRuleScriptRuntime.evaluateBrowserSnapshot = (...args) => runtime.evaluateBrowserSnapshot(...args);
  let clicks = 0;
  let waits = 0;
  let readyAfter = 2;
  let audioUrl = 'https://media.example/play?token=test';
  const sequences = new Set();
  stubs[prefix + 'LocalRuleBrowserActions'].LocalRuleBrowserActions.execute = async (_controller, address) => {
    const action = JSON.parse(address.slice('local-rule-browser:'.length));
    assert.ok(!sequences.has(action.sequence), 'A replayed action must not execute twice');
    sequences.add(action.sequence);
    let value;
    if (action.operation === 'query') value = [{ id: action.selector === '.root-audio' ? 1 : 2, epoch: 'fixture' }];
    else if (action.operation === 'read') value = waits >= readyAfter ? audioUrl : '';
    else if (action.operation === 'call') { assert.equal(action.name, 'click'); clicks++; value = null; }
    else if (action.operation === 'wait') { waits++; value = null; }
    else throw new Error('Unexpected action: ' + action.operation);
    return JSON.stringify({ value });
  };
  const script = `(function(){var a=document.querySelector('.root-audio');
    if(a&&a.src&&a.src.indexOf('blob:')!==0){return a.src}
    var p=document.querySelector('.play-btn');
    if(p&&!window.__tyauto){window.__tyauto=1;p.click()}return null})()`;
  planFactory = makePlan;
  respond = async () => ({ statusCode: 200, headers: {}, body: '<audio class="root-audio"></audio>' });
  const audio = await http.fetchWebAudio(source, 'fixture', script);
  assert.equal(audio.ok, true, audio.errorMessage);
  assert.equal(audio.body, audioUrl);
  assert.equal(clicks, 1, 'Waiting for media must not click the toggle again');
  assert.equal(waits, 2);
  assert.equal(leases, 0);
  sequences.clear(); clicks = 0; waits = 0; readyAfter = Infinity;
  const missing = await http.fetchWebAudio(source, 'fixture', script);
  assert.equal(missing.ok, false);
  assert.match(missing.errorMessage, /等待超时/);
  assert.equal(clicks, 1);
  assert.equal(waits, 9);
  assert.equal(leases, 0, 'Timeout releases the browser lease');
  for (const invalid of ['blob:fixture', 'javascript:alert(1)', '<html>not media</html>']) {
    sequences.clear(); waits = 0;
    const rejected = await http.fetchWebAudio(source, 'fixture', JSON.stringify(invalid));
    assert.equal(rejected.ok, false);
    assert.match(rejected.errorMessage, /HTTP\(S\)/);
    assert.equal(leases, 0);
  }
  assert.equal(await runtime.evaluateBrowserSnapshot(source, initial(),
    '[typeof fetch,typeof XMLHttpRequest,typeof WebSocket].join(",")', {}), 'undefined,undefined,undefined');
  console.log('PASS: explicit @webjs audio polling, action replay/click-once, timeout cleanup and HTTP(S)-only results');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
