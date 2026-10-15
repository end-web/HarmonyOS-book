// Run the actual ArkTS model/parser/codec with the Release IDE transpiler.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
function load(file) {
  if (!fs.existsSync(file) && file.endsWith('.ets')) file = file.slice(0, -4) + '.ts';
  if (modules.has(file)) return modules.get(file);
  const exports = {};
  modules.set(file, exports);
  const text = fs.readFileSync(file, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const code = ts.transpileModule(text, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => name === '@kit.ArkTS'
    ? { url: { URL: { parseURL: (value, base) => new URL(value, base) } } }
    : load(path.resolve(path.dirname(file), name + '.ets')) });
  return exports;
}
const { LocalRuleSourceImportParser: parser } = load(path.join(root, 'service/rulesource/LocalRuleSourceImportParser.ets'));
const { LocalRuleSourceCodec: codec } = load(path.join(root, 'service/rulesource/LocalRuleSourceCodec.ets'));
const { LocalRuleSource } = load(path.join(root, 'model/LocalRuleSource.ets'));
const definition = {
  bookSourceUrl: 'https://export.invalid', bookSourceName: '导出回归',
  header: { 'User-Agent': 'fixture' }, variable: { custom: '中文' },
  searchUrl: '/search?q={{key}}', ruleSearch: { bookList: '$.items', name: '$.name', bookUrl: '$.url', extension: 7 },
  futureRule: { value: true }
};
const input = JSON.stringify([definition]);
let sources = parser.parse(input).sources;
for (const key of ['enabled','enabledExplore','isLocked','isPinned','validationStatus','validationMessage']) {
  sources[0]['__ob_' + key] = sources[0][key];
  delete sources[0][key];
  Object.defineProperty(sources[0],key,{enumerable:false,
    get() { return this['__ob_' + key]; }, set(value) { this['__ob_' + key] = value; }});
}
const before = codec.exportBatch(sources);
assert.equal(before, input, 'unchanged definitions keep their fields and value types');
for (let cycle = 0; cycle < 5; cycle++) {
  sources[0].validationStatus = 2;
  sources[0].validationMessage = '测试失败'.repeat(2000);
  const exported = codec.exportBatch(sources);
  assert.equal(exported, input, 'test diagnostics and repeat imports must not grow the export');
  sources = parser.parse(exported).sources;
}
sources[0].bookSourceGroup = '新分组';
sources[0].enabled = false;
sources[0].ruleSearch.name = '';
sources[0].ruleSearch.author = '$.author';
const edited = JSON.parse(codec.exportBatch(sources))[0];
assert.deepEqual(edited.ruleSearch, { ...definition.ruleSearch, name: '', author: '$.author' });
assert.equal(edited.bookSourceGroup, '新分组');
assert.equal(edited.enabled, false);
assert.deepEqual(edited.header, definition.header);
const restored = parser.parse(JSON.stringify(edited)).sources[0];
assert.equal(restored.ruleSearch.name, '');
assert.equal(restored.ruleSearch.author, '$.author');
sources[0].enabledExplore = false;
sources[0].exploreUrl = '/explore';
assert.equal(parser.parse(codec.stringify(sources[0])).sources[0].enabledExplore, false,
  'adding discovery must preserve its disabled state');
for (const rule of ['@{bookList=$.items;name=$.name;author=$.author;bookUrl=$.url}', JSON.stringify(definition.ruleSearch)]) {
  const compact = { ...definition, ruleSearch: rule };
  const source = parser.parse(JSON.stringify(compact)).sources[0];
  assert.deepEqual(JSON.parse(codec.stringify(source)), compact);
  source.ruleSearch.name = '$.changed';
  assert.equal(parser.parse(codec.stringify(source)).sources[0].ruleSearch.name, '$.changed');
}
const legacy = parser.parse(JSON.stringify({ ...definition, locked: true,
  cookie: 'secret-cookie', session: { token: 'secret-token' }, rawSourceJson: 'old-copy' })).sources[0];
const safe = codec.stringify(legacy);
assert.ok(!safe.includes('secret-') && !safe.includes('rawSourceJson'));
assert.equal(parser.parse(safe).sources[0].isLocked, true);
legacy.isLocked = false;
assert.equal(parser.parse(codec.stringify(legacy)).sources[0].isLocked, false);
const created = LocalRuleSource.descriptor('https://new.invalid', '新书源');
created.ruleContent.content = '$.text';
created.exploreUrl = '/explore';
assert.equal(parser.parse(codec.stringify(created)).sources[0].ruleContent.content, '$.text');
assert.equal(parser.parse(codec.stringify(created)).sources[0].enabledExplore, false);
console.log(`PASS: unchanged/tested export ${Buffer.byteLength(input)} bytes; 5 stable round trips, edits, compact rules, extensions, credentials and new sources`);

const { NativeSourceDraft } = load(path.join(root, 'service/rulesource/NativeSourceDraft.ts'));
const nativeInput = {sourceFormat:'native',version:1,name:'原生测试',url:'https://native.test',type:'audio',
  enabled:true,search:{url:'/search',headers:{'X-Token':'keep'},list:'$.items',fields:{name:'$.name',bookUrl:'$.url'}},
  vars:[{key:'mode',label:'模式',options:['text','audio'],default:'audio',filter:true}],
  futureField:{nested:['unchanged',7,null]},toc:{url:'/toc',reverse:false,list:'$.chapters',fields:{title:'$.title',url:'$.url'}},
  content:{audio:'$.audio'},explore:{list:'$.items',fields:{name:'$.name',bookUrl:'$.url'}},
  login:{url:'https://native.test/login',cookies:['sid']}};
const draft = new NativeSourceDraft(JSON.stringify(nativeInput));
const field = (parent,key) => draft.fields(parent).find(item=>item.key===key);
assert.equal(draft.serialize(),JSON.stringify(nativeInput),'opening form must not materialize optional fields');
draft.edit(field('','name'),'修改原生名称');
draft.edit(field('/search/fields','name'),'$.title');
draft.edit(field('/toc','reverse'),'true');
draft.edit(field('/vars/0','filter'),'false');
draft.add('/search/headers','X-New','string');
draft.edit(field('/search/headers','X-New'),'token');
draft.add('/explore/menus','','object');
draft.edit(field('/explore/menus/0','title'),'新分类');
draft.edit(field('/explore/menus/0','url'),'/new');
draft.add('/vars/0/options','','string');
draft.edit(field('/vars/0/options','2'),'comic');
const secondOptionId = draft.stableKey('/vars/0/options/1');
draft.remove(field('/vars/0/options','0'));
assert.equal(draft.stableKey('/vars/0/options/0'),secondOptionId,'array node identity survives preceding removal');
draft.remove(field('/search/headers','X-New'));
draft.remove(field('','enabled'));
assert.equal(field('','enabled').value,'true','omitted enabled flag follows native default');
assert.throws(()=>draft.add('/search/headers','X-Token','string'));
assert.throws(()=>draft.add('/search/headers','__proto__','object'));
assert.throws(()=>draft.edit(field('','url'),'https://other.test'));
const result = JSON.parse(draft.serialize());
assert.equal(result.toc.reverse,true);
assert.equal(result.vars[0].filter,false);
assert.deepEqual(result.vars[0].options,['audio','comic']);
assert.deepEqual(result.futureField,nativeInput.futureField);
assert.deepEqual(result.search.headers,{'X-Token':'keep'});
assert.equal(result.explore.menus[0].title,'新分类');
const parsedNative = parser.parse(draft.serialize());
assert.equal(parsedNative.sources.length,1,parsedNative.message);
assert.equal(parsedNative.sources[0].engine,'light-native');
const exportedNative = JSON.parse(codec.stringify(parsedNative.sources[0]));
assert.equal(exportedNative.name,'修改原生名称');
assert.equal(exportedNative.search.fields.name,'$.title');
assert.deepEqual(exportedNative.futureField,nativeInput.futureField);
draft.edit(field('/content/comments','max'),'not-a-number');
assert.throws(()=>draft.serialize(),'invalid number cannot silently retain or save an old value');
draft.edit(field('/content/comments','max'),'10');
assert.equal(JSON.parse(draft.serialize()).content.comments.max,10);
draft.add('/search/headers','escaped/key~name','string');
draft.edit(field('/search/headers','escaped/key~name'),'preserved');
assert.equal(JSON.parse(draft.serialize()).search.headers['escaped/key~name'],'preserved');
console.log('PASS: native grouped fields, nested maps/arrays, stable item identities, type preservation, unknown fields, form/JSON round trip and validation');
