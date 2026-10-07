// Real GuangYu services and imported source scripts; isolated storage/HTTP and V8 in place of QuickJS.
// DEVECO_HOME=<Release IDE> node scripts/test-guangyu-compat.cjs [source.json]
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
const stubs = { 'service/http/HttpClient': {HttpClient:{}}, '@kit.PerformanceAnalysisKit': {hilog:{warn(){}}},
  'service/SourceDataService': { SourceDataService: { invalidateLocalSources() {} } },
  '@kit.ArkTS': { buffer: { from: Buffer.from, byteLength: Buffer.byteLength }, util: { generateRandomUUID: () => 'test-device-id', TextDecoder: {
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
const repo = stubs[prefix + 'LocalRuleSourceRepository'].LocalRuleSourceRepository;
let state = '';
let session;
let loginStatus = '';
const cookies = new Map();
repo.isInitialized = () => true;
repo.readScriptState = async () => state;
repo.writeScriptState = async (_source, value) => { state = value; };
repo.getSession = async () => session;
repo.saveSession = async value => { session = value; loginStatus = value.token ? 'valid' : 'saved'; };
repo.getLoginStatus = async () => loginStatus;
repo.setLoginStatus = async (_source, value) => { loginStatus = value; };
const http = stubs[prefix + 'LocalRuleHttpClient'].LocalRuleHttpClient;
http.getStoredCookieHeader = async (_source, origin) => cookies.get(origin) || '';
http.getCookieSnapshot = async () => Object.fromEntries(cookies);
http.saveWebCookies = async (_source, origin, value) => cookies.set(origin, value);
http.clearCookies = async (_source, origin) => cookies.delete(origin);
const { LocalRuleSourceImportParser: parser } = load(prefix + 'LocalRuleSourceImportParser');
const { LocalRuleScriptRuntime: runtime } = load(prefix + 'LocalRuleScriptRuntime');
const { LocalRulePanelService: panels } = load(prefix + 'LocalRulePanelService');
const { GuangYuSettings: settings } = load(prefix + 'guangyu/GuangYuSettings');
const { GuangYuApiClient: api } = load(prefix + 'guangyu/GuangYuApiClient');
const { GuangYuAuthService: auth } = load(prefix + 'guangyu/GuangYuAuthService');
const { GuangYuRoute: route, GuangYuRouteKind: kind } = load(prefix + 'guangyu/GuangYuSourceIdentity');
const { GuangYuSourceAdapter: adapter } = load(prefix + 'guangyu/GuangYuSourceAdapter');
const definition = process.argv[2] ? fs.readFileSync(process.argv[2], 'utf8') : JSON.stringify({
 bookSourceUrl:'光遇聚合',bookSourceName:'光遇测试',enabledExplore:true,exploreUrl:'推荐::https://v1.qingtian618.com/get_discover?page={{page}}',
 jsLib:"function getVariable(k){const v=JSON.parse(source.getVariable()||'{}');return v[k]||'';}function setVariable(k,v){const o=JSON.parse(source.getVariable()||'{}');o[k]=v;source.setVariable(JSON.stringify(o));}",
 loginUi:JSON.stringify([{name:'书源设置',type:'button',action:'getHtmlSettings()'}])
});
const source = parser.parse(definition).sources[0];
repo.get = async () => source;
let fetchedAddress = '';
http.fetch = async (_source,address) => {
 fetchedAddress=address;
 const data=address.includes('config.json')?{version:'20260926',hosts:api.hosts(),'小说':['番茄','七猫'],'听书':['番茄']}:
 address.includes('discovestyle')?{code:0,data:[{title:'推荐',url:'http://v1.qingtian618.com/get_discover?page={{page}}'}]}:
 {code:0,data:[{book_name:'公开测试书',book_id:'book-1',source:'番茄',tab:'小说'}]};
 return {ok:true,statusCode:200,requestUrl:address,headers:{},body:JSON.stringify(data)};
};
async function run() {
 for(const url of [route.book('小说','番茄','1'),route.catalog('听书','番茄','1','7'),route.chapter('小说','番茄','1','2','4')]) {
  assert.notEqual(route.parse(url).kind,kind.INVALID);
 }
 const upstream='https://example.com/book/1?x=a%20b';
 assert.equal(route.parse(route.chapter('小说','番茄','1','2','4',upstream)).upstreamUrl,upstream);
 assert.equal(route.parse('gy://chapter/a/b/c/d/4/javascript%3Aalert(1)').kind,kind.INVALID);
 const discovery=await panels.load(source,false);
 assert.ok(discovery.entries.some(x=>x.url),'original discovery must yield book categories');
 const login=await panels.load(source,true);
 const action=login.controls.find(x=>x.action==='getHtmlSettings()');
 const opened=await panels.act(source,action,login.controls,true);
 assert.ok(opened.panel);
 const mode=opened.panel.controls.find(x=>x.title==='搜索模式');mode.value='听书';
 const audio=opened.panel.controls.find(x=>x.title==='听书');audio.value='番茄,七猫';
 await panels.act(source,mode,opened.panel.controls,true);
 assert.equal((await settings.load()).mode,'听书');
 assert.equal((await settings.load()).audioSources,'番茄,七猫');
 let requested='';
 stubs['service/http/HttpClient'].HttpClient.request=async(address) => {
  requested=address;
  return {statusCode:200,body:JSON.stringify({code:0,data:[]}),headers:{}};
 };
 await adapter.search(source,'t:测试@番茄',2);
 assert.ok(requested.includes('source='+encodeURIComponent('番茄')));
 assert.ok(requested.includes('tab='+encodeURIComponent('听书')));
 assert.ok(requested.includes('page=2'));
 stubs['service/http/HttpClient'].HttpClient.request=async(_address,options) => {
  assert.equal(options.body.tone_id,'voice-42');
  assert.equal(JSON.parse(options.body.variable).custom,'voice-42');
  return {statusCode:200,body:JSON.stringify({code:0,content:'https://media.example.com/public.mp3'}),headers:{}};
 };
 assert.equal((await adapter.resolveContent(route.chapter('听书','番茄','book','chapter','4'),'voice-42')).audioUrl,
  'https://media.example.com/public.mp3');
 session={token:'fixture-token-long-enough',deviceId:'fixture-device',accountLabel:'fixture'};
 loginStatus='valid';
 cookies.set(api.hosts()[0],'verification=kept');
 await auth.syncScriptSession();
 assert.ok(cookies.get(api.hosts()[0]).includes('verification=kept'));
 for(const host of api.hosts())assert.ok(cookies.get(host).includes('qttoken=fixture-token-long-enough'));
 const explored=await adapter.explore(source,'http://v1.qingtian618.com/get_discover?page={{page}}',1,{},20);
 assert.ok(fetchedAddress.startsWith('https://'));
 assert.equal(explored.books.length,1);
 assert.equal(route.parse(explored.books[0].bookUrl).kind,kind.BOOK);
 await auth.logout();
 assert.equal(session.token,'');
 assert.equal(loginStatus,'signedOut');
 assert.equal(cookies.size,0);
 console.log('PASS: imported panel/settings, targeted search, discovery routes, upstream routes and session/logout consistency');
}
run().catch(error=>{console.error(error.message);process.exitCode=1;});
