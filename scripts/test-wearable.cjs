// Real wearable library and account logic; platform substitutes do not replace device validation.
// DEVECO_HOME=<Release IDE> node scripts/test-wearable.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

function load(relative, modules = {}, globals = {}) {
  const filename = path.join(__dirname, '../entry/src/main/ets', relative);
  const source = fs.readFileSync(filename, 'utf8')
    .replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, console,
    require: name => { assert.ok(modules[name], `Unexpected import: ${name}`); return modules[name]; },
    ...globals
  }, { filename });
  return module.exports;
}

const identity = load('utils/BookIdentity.ets');
let sources = [], searchCalls = 0, active = 0, maxActive = 0, tocCalls = 0;
let favorites = [], downloads = [], httpCalls = 0, destroyed = 0, importCalls = 0, invalidations = 0;
let response = { responseCode: 200, result: 'source-json' }, transportError = false;
const bookCache = new Map();
function hit(source, type = 'audio') {
  return { name: '测试书', author: '作者', coverUrl: '', bookUrl: '/book/1', intro: '', kind: '',
    contentType: type, sourceName: source.bookSourceUrl, sourceUrl: source.bookSourceUrl };
}
const { WearableLibraryService: library } = load('service/wearable/WearableLibraryService.ets', {
  '../../utils/BookIdentity': identity,
  '../BookSourceService': { BookSourceService: {
    searchBooks: async source => {
      searchCalls++; active++; maxActive = Math.max(maxActive, active);
      await new Promise(resolve => setImmediate(resolve));
      active--;
      if (source.bookSourceUrl === 'broken') throw Error('network failure');
      return [hit(source), hit(source), hit(source, 'text')];
    },
    loadAudioBook: async book => { tocCalls++; return book; }
  } },
  '../DataService': { DataService: { getBookById: async (_context, id) => bookCache.get(id) } },
  '../DownloadStore': { DownloadStore: { getBooksSync: () => downloads } },
  '../PreferenceService': { PreferenceService: { getFavorites: async () => favorites } },
  '../SourceDataService': { SourceDataService: {
    getEnabledSources: async () => sources,
    invalidateLocalSources: () => invalidations++
  } },
  '../rulesource/LocalRuleSourceImportParser': { LocalRuleSourceImportParser: {
    parse: text => ({ sources: text === 'source-json' ? ['parsed-rule'] : [] })
  } },
  '../rulesource/LocalRuleSourceImportService': { LocalRuleSourceImportService: {
    importSources: async rows => { importCalls++; assert.equal(rows[0], 'parsed-rule'); return 1; }
  } },
  '@kit.NetworkKit': { http: {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      request: async (_address, options) => {
        httpCalls++;
        assert.ok(options.maxLimit <= 2 * 1024 * 1024, 'bound downloaded import before parsing');
        if (transportError) throw Error('offline');
        return response;
      },
      destroy: () => destroyed++
    })
  } }
});

let cachedAccount = null, accountSupported = true, authMode = 'success', loginRequest = null, authCalls = 0;
class HwAccount {
  unionID = ''; openID = ''; nickName = ''; avatarFile = ''; loginAt = 0;
  static isValid(value) { return !!value?.unionID && !!value.openID && value.loginAt > 0; }
}
class HuaweiIDProvider {
  createAuthorizationWithHuaweiIDRequest() { return {}; }
  async getHuaweiIDState() { return { state: authMode === 'revoked' ? 'UNAUTHORIZED' : 'AUTHORIZED' }; }
}
class AuthenticationController {
  async executeRequest(request) {
    authCalls++; loginRequest = request;
    if (authMode === 'revoked') throw { code: 1001502002 };
    return { state: authMode === 'bad-state' ? 'wrong-state' : request.state,
      data: { openID: 'validated-open-id', unionID: 'validated-union-id', nickName: '同一账号' } };
  }
}
const { AuthService } = load('service/AuthService.ets', {
  '@kit.AccountKit': { authentication: { HuaweiIDProvider, AuthenticationController,
    IdType: { OPEN_ID: 1 }, State: { AUTHORIZED: 'AUTHORIZED', UNAUTHORIZED: 'UNAUTHORIZED', UNLOGGED_IN: 'UNLOGGED_IN' } } },
  '@kit.ArkTS': { util: { generateRandomUUID: () => 'request-random-state' } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  './PreferenceService': { HwAccount, PreferenceService: {
    ensureReady: async () => {}, getHwAccount: async () => cachedAccount,
    setHwAccount: async value => { cachedAccount = value; }, clearHwAccount: async () => { cachedAccount = null; }
  } },
  './AccountAvatarService': { AccountAvatarService: {
    download: async () => '', remove: async () => {}, localUri: async () => ''
  } }
}, { canIUse: () => accountSupported });

(async () => {
  assert.equal((await library.search('book', 1, () => false)).books.length, 0);
  assert.equal(searchCalls, 0, 'no sources must not start a built-in search');
  sources = Array.from({ length: 8 }, (_, i) => ({ bookSourceUrl: `source-${i}`, bookSourceType: 1 }));
  sources.push({ bookSourceUrl: 'broken', bookSourceType: 1 }, { bookSourceUrl: 'text-only', bookSourceType: 0 });
  const found = await library.search('book', 1, () => false);
  assert.equal(found.books.length, 8, 'deduplicate within a source, keep different source identities');
  assert.equal(found.failedCount, 1, 'one failed source must preserve remaining results');
  assert.equal(searchCalls, 9, 'skip sources declared as text-only');
  assert.equal(maxActive, 6, 'retain the existing six-source concurrency bound');
  const callsBeforeCancel = searchCalls;
  await library.search('book', 1, () => true);
  assert.equal(searchCalls, callsBeforeCancel, 'cancelled searches cannot schedule a new batch');

  const book = found.books[0];
  book.chapters = [{ id: 'chapter', source: { type: 'url', value: 'https://example.test/chapter' } }];
  bookCache.set(book.id, book);
  bookCache.set('text', { id: 'text', contentType: 'text', chapters: [] });
  favorites = ['missing', 'text']; downloads = [{ bookId: book.id }];
  assert.equal((await library.shelf({}))[0].id, book.id, 'downloaded books remain visible without a favorite');
  assert.equal(await library.openBook(book), book);
  assert.equal(tocCalls, 0, 'cached chapter catalogs must open without a network request');

  await assert.rejects(library.importSource('http://example.test/rules'));
  assert.equal(httpCalls, 0);
  assert.equal(await library.importSource('https://example.test/rules'), 1);
  assert.equal(importCalls, 1); assert.equal(invalidations, 1);
  response = { responseCode: 200, result: 'invalid' };
  await assert.rejects(library.importSource('https://example.test/rules'));
  transportError = true;
  await assert.rejects(library.importSource('https://example.test/rules'));
  assert.equal(destroyed, 3, 'release network request on success, parse failure and transport failure');
  assert.equal(importCalls, 1, 'invalid downloads must not alter installed sources');

  const auth = new AuthService();
  assert.equal(await auth.restoreSharedAccount({}), true);
  assert.equal(loginRequest.forceAuthorization, false, 'watch startup must not force an authorization dialog');
  assert.equal(auth.openID, 'validated-open-id');
  const callsAfterLogin = authCalls;
  assert.equal(await auth.restoreSharedAccount({}), true);
  assert.equal(authCalls, callsAfterLogin, 'valid cached authorization does not log in again');
  authMode = 'revoked';
  assert.equal(await auth.restoreSharedAccount({}), false);
  assert.equal(auth.isLoggedIn, false, 'revoked identity cannot remain signed in');
  assert.equal(cachedAccount, null);
  authMode = 'bad-state';
  assert.equal(await auth.restoreSharedAccount({}), false);
  assert.equal(cachedAccount, null, 'mismatched response state cannot persist an account');
  authMode = 'success';
  await auth.login({});
  assert.equal(loginRequest.forceAuthorization, true, 'existing explicit phone login keeps its behavior');
  accountSupported = false;
  const unavailable = new AuthService();
  assert.equal(await unavailable.restoreSharedAccount({}), false);
  assert.equal(unavailable.isLoggedIn, false);
  console.log('PASS wearable library, offline catalog, bounded import and shared account authorization');
})().catch(error => { console.error(error); process.exitCode = 1; });
