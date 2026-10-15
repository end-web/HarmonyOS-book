const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const exportsObject = {};
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/ChapterCacheCodec.ts'), 'utf8'), {
  compilerOptions: {target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}
}).outputText;
vm.runInNewContext(code, {exports:exportsObject});
const {ChapterCacheCodec: codec} = exportsObject;
const revision = 'definition'.repeat(8192);
const sample = {id:'chapter-1',index:0,title:'中文 [ { \\"quoted" } ]',duration:12,
  source:{type:'url',value:'https://book.test/chapter'},originSourceValue:'https://book.test/chapter',
  variables:{token:'keep',nested:'{"a":[1,2]}',__audioTocDefinition:revision}};
const expected = {...sample,variables:{token:'keep',nested:'{"a":[1,2]}'}};
assert.deepEqual(JSON.parse(JSON.stringify(codec.parse(JSON.stringify([sample])))), [expected]);
assert.deepEqual(JSON.parse(codec.stringify(sample)), expected);
assert.equal(sample.variables.__audioTocDefinition, revision, 'write does not mutate live state');
assert.equal(codec.parse(' \n [] \t').length,0);
for (const bad of ['{}','[','[{}','[{},]','[{}]x','[{},null]','[{},','[{"x":"unterminated}]']) {
  assert.throws(() => codec.parse(bad), undefined, bad);
}
const legacy = '[' + Array.from({length:256},(_,i)=>JSON.stringify({...sample,id:`c${i}`})).join(',') + ']';
const restored = codec.parse(legacy);
assert.equal(restored.length,256);
const compact = '['+restored.map(c=>codec.stringify(c)).join(',')+']';
assert.ok(compact.length < legacy.length / 100, 'old repeated definitions are removed on read and write');
assert.equal(codec.parse(compact)[255].id,'c255');
console.log(`PASS: legacy directory ${legacy.length} -> ${compact.length} chars; escaped strings, malformed input, source variables and non-mutating writes`);
