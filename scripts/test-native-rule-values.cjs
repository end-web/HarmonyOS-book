// Actual native rule classes, with only HarmonyOS platform APIs adapted for Node.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/rulesource');
const cache = new Map();
const ark = { buffer: { from: Buffer.from }, url: { URL: { parseURL: (value, base) => new URL(value, base) } }, util: {
  TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
  TextDecoder: { create: (encoding, options) => ({ decodeToString: bytes => new TextDecoder(encoding, options).decode(bytes) }) },
  Base64Helper: class { decodeSync(value) { return Buffer.from(value, 'base64'); } }
} };
const cryptography = { cryptoFramework: { createMd(algorithm) {
  const digest = crypto.createHash(algorithm.toLowerCase());
  return { async update(blob) { digest.update(blob.data); }, async digest() { return { data: digest.digest() }; } };
} } };
function load(filename) {
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} }; cache.set(filename, module);
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const localRequire = name => {
    if (name === '@kit.ArkTS') return ark;
    if (name === '@kit.CryptoArchitectureKit') return cryptography;
    if (!name.startsWith('.')) throw new Error(`Unexpected platform dependency: ${name}`);
    return load(path.resolve(path.dirname(filename), name + '.ets'));
  };
  const execute = vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename });
  execute(localRequire, module, module.exports);
  return module.exports;
}
const { NativeRuleSchema, NativeValue } = load(path.join(root, 'native/NativeRuleSchema.ets'));
const { NativeRuleValues, NativeValueContext } = load(path.join(root, 'native/NativeRuleValues.ets'));
const { NativeHtmlParser } = load(path.join(root, 'native/NativeHtmlParser.ets'));
const example = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../docs/examples/shuyinfm-native.json'), 'utf8'));
const parse = value => NativeRuleSchema.parse(JSON.stringify(value));
const value = raw => parse({ version: 1, detail: { fields: [{ name: 'name', value: raw }] } }).detail.fields[0].value;
async function run() {
  assert.equal(example.format, 'jianting.source');
  const definition = parse({ version: example.version, ...example.rules });
  assert.equal(definition.discover.length, 17);
  assert.equal(definition.search.request.method, 'POST');
  assert.equal(definition.toc.fields[1].value.kind, 'css');
  for (const invalid of [null, [], {version:2}, {version:1,jsLib:'x'}, {version:1,detail:{fields:[{name:'eval',value:{kind:'literal',value:''}}]}}, {version:1,headers:[{name:'A',value:{kind:'javascript',value:'x'}}]}, {version:1,headers:[{name:'A',value:{transforms:[{op:'eval'}]}}]}, {version:1,headers:[{name:'A',value:{kind:'template',value:'{{page - 1}}'}}]}, {version:1,headers:[{name:'A',value:{index:-1}}]}, {version:1,headers:[{name:'A',value:{required:'true'}}]}]) assert.throws(()=>parse(invalid));
  assert.throws(()=>value({transforms:[{op:'regexGroup',pattern:'(a+)+'}]}));
  assert.throws(()=>value({transforms:[{op:'regexGroup',pattern:'a+a+a+b'}]}));
  assert.throws(()=>value({transforms:[{op:'regexGroup',pattern:'\\d+\\d+x'}]}));
  assert.throws(()=>value({transforms:[{op:'regexGroup',pattern:'a?a?a?b'}]}));
  assert.throws(()=>value({transforms:Array.from({length:17},()=>({op:'trim'}))}));
  for (const list of [{kind:'css',value:'li',index:1},{kind:'css',value:'li',transforms:[{op:'trim'}]},{kind:'json',value:'$[*]'}]) {
    assert.throws(()=>parse({version:1,search:{format:'html',list,fields:[{name:'name',value:{kind:'literal',value:'a'}},{name:'bookUrl',value:{kind:'literal',value:'https://example.org'}}]}}));
  }
  assert.throws(()=>parse({version:1,detail:{list:{kind:'css',value:'li'}}}));
  const context = new NativeValueContext();
  context.baseUrl = 'https://www.shuyinfm.com/album/1-2.html';
  context.variables = new Map([['key','有 声&书'],['page0','0'],['chapterUrl','https://www.shuyinfm.com/play/1-245-8.html'],['timestamp','1800000000']]);
  context.html = NativeHtmlParser.parse('<section><ul id="playlist"><li><a href="/play/1-245-8.html">第一集 &amp; 试音</a></li></ul></section>');
  context.node = context.html.select('#playlist li a')[0];
  assert.equal(await NativeRuleValues.evaluate(definition.toc.fields[0].value, context),'第一集 & 试音');
  assert.equal(await NativeRuleValues.evaluate(definition.toc.fields[1].value, context),'https://www.shuyinfm.com/play/1-245-8.html');
  for (const binding of definition.content.bindings) context.variables.set(binding.name,await NativeRuleValues.evaluate(binding.value,context));
  assert.equal(context.variables.get('albumId'),'245');
  assert.equal(context.variables.get('movieId'),'9');
  const signatureTemplate = definition.content.bindings[2].value.value;
  const plain = NativeRuleValues.expand(signatureTemplate,context.variables);
  assert.equal(context.variables.get('signature'),crypto.createHash('md5').update(plain).digest('hex'));
  const address = new URL(await NativeRuleValues.evaluate(definition.content.request.url,context));
  assert.equal(address.searchParams.get('t'),'1800000000');
  assert.equal(address.searchParams.get('token'),context.variables.get('signature'));
  context.json = JSON.stringify({data:{SeriesUrl:'https://media.example/track.mp3'}});
  assert.equal(await NativeRuleValues.evaluate(definition.content.fields[0].value,context),'https://media.example/track.mp3');
  assert.equal(await NativeRuleValues.evaluate(value({kind:'variable',value:'key',transforms:[{op:'urlEncode'}]}),context),encodeURIComponent('有 声&书'));
  assert.equal(await NativeRuleValues.evaluate(value({kind:'literal',value:' YWJj ',transforms:[{op:'trim'},{op:'base64Decode'}]}),context),'abc');
  await assert.rejects(()=>NativeRuleValues.evaluate(value({kind:'template',value:'{{missing}}'}),context));
  await assert.rejects(()=>NativeRuleValues.evaluate(value({kind:'literal',value:'',required:true}),context));
  await assert.rejects(()=>NativeRuleValues.evaluate(value({kind:'literal',value:'123x',transforms:[{op:'add',amount:1}]}),context));
  await assert.rejects(()=>NativeRuleValues.evaluate(value({kind:'literal',value:'javascript:alert(1)',transforms:[{op:'resolveUrl'}]}),context));
  for (const address of ['签名错误','error','<html>错误</html>','{"error":"expired"}','https://example.org/a\nX']) {
    assert.throws(()=>NativeRuleValues.resolveUrl(address,context.baseUrl));
  }
  assert.equal(NativeRuleValues.resolveUrl('audio/1.mp3',context.baseUrl),'https://www.shuyinfm.com/album/audio/1.mp3');
  context.json = '{}';
  await assert.rejects(()=>NativeRuleValues.evaluate(definition.content.fields[0].value,context));
  const oversized = new NativeValue(); oversized.value = 'x'.repeat(NativeRuleSchema.MAX_VALUE_CHARS+1);
  await assert.rejects(()=>NativeRuleValues.evaluate(oversized,context));
  console.log('PASS native rule schema, extraction, signature binding, malformed input and budgets');
}
run().catch(error=>{ console.error(error);process.exitCode=1; });
