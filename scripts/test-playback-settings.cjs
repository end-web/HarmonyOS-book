const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function compile(source, dependencies = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, { module, exports: module.exports, require: name => dependencies[name] || {}, setTimeout });
  return module.exports;
}
(async () => {
  const disk = new Map(), memory = new Map();
  let failFlush = false;
  const store = { get: async (k, v) => memory.get(k) ?? v, put: async (k, v) => memory.set(k, v),
    flush: async () => { if (failFlush) throw new Error('disk full'); for (const [k, v] of memory) disk.set(k, v); } };
  const source = fs.readFileSync(path.join(root, 'service/PreferenceService.ets'), 'utf8');
  const dependencies = { '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } } };
  const prefs = compile(source, dependencies).PreferenceService;
  prefs.ensureStore = async () => store;
  await prefs.setSearchConcurrency(3); await prefs.setPreloadChapters(7);
  assert.equal(await prefs.getSearchConcurrency(), 3);
  assert.equal(await prefs.getPreloadChapters(), 7);
  failFlush = true;
  await assert.rejects(prefs.setSearchConcurrency(12)); await assert.rejects(prefs.setPreloadChapters(0));
  assert.equal(await prefs.getSearchConcurrency(), 3); assert.equal(await prefs.getPreloadChapters(), 7);
  await assert.rejects(prefs.setSearchConcurrency(0)); await assert.rejects(prefs.setPreloadChapters(51));
  const cold = compile(source, dependencies).PreferenceService;
  cold.ensureStore = async () => ({ get: async (k, v) => disk.get(k) ?? v });
  assert.equal(await cold.getSearchConcurrency(), 3); assert.equal(await cold.getPreloadChapters(), 7);
  const page = fs.readFileSync(path.join(root, 'pages/SearchPage.ets'), 'utf8');
  const methods = page.slice(page.indexOf('  private async searchSources('), page.indexOf('  private async searchOneSource('));
  const { SearchQueue } = compile(`export class SearchQueue { searchGen = 1; ${methods} }`);
  for (const limit of [1, 3, 6, 12]) {
    let active = 0, peak = 0, completed = 0;
    const queue = new SearchQueue();
    queue.searchOneSource = async () => { active++; peak = Math.max(peak, active);
      await new Promise(resolve => setTimeout(resolve, 2)); active--; completed++; };
    await queue.searchSources(Array.from({ length: 15 }, (_, id) => ({ id })), 'test', 1, new Set(), limit);
    assert.equal(peak, limit); assert.equal(completed, 15);
  }
  console.log('PASS persisted settings, failed-write rollback, restart recovery and real search queue limits 1/3/6/12');
})().catch(error => { console.error(error); process.exitCode = 1; });
