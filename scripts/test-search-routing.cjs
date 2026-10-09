// DEVECO_HOME=<Release IDE> <Release IDE>/tools/node/node scripts/test-search-routing.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const pages = path.join(__dirname, '../entry/src/main/ets/pages');
const index = fs.readFileSync(path.join(pages, 'Index.ets'), 'utf8');
const main = fs.readFileSync(path.join(pages, 'MainPage.ets'), 'utf8');
const start = index.indexOf('  private resolveParam(');
const end = index.indexOf('  private syncReaderWindowMode(', start);
assert.ok(start >= 0 && end > start, 'read the actual route parameter resolver');
const searchRoute = index.match(/else if \(name === 'search'\) \{\s*(SearchPage\([^\n]+\))/);
const homeSearch = main.match(/onSearchTap: \(\) => (this\.navStack\.pushPathByName\('search', [^\n]+\))/);
assert.ok(searchRoute && homeSearch, 'read the actual search destination and home entry');
const code = ts.transpileModule(`
class RouteProbe {
  navStack = { pushPathByName: (name, param) => this.open(name, param) };
  ${index.slice(start, end)}
  open(name, param) { ${searchRoute[1]} }
  tapHomeSearch() { ${homeSearch[1]} }
}
exports.probe = new RouteProbe();
`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
const exportsObject = {};
let keyword;
vm.runInNewContext(code, {
  exports: exportsObject,
  SearchPage: options => { keyword = options.initialKeyword; }
});
const probe = exportsObject.probe;
probe.tapHomeSearch();
assert.equal(keyword, '', 'home search opens without a prefilled keyword');
for (const param of [null, undefined, {}, '', 'legacy', { keyword: null }, { keyword: 123 }]) {
  probe.open('search', param);
  assert.equal(keyword, '', 'absent or invalid keywords use the empty default');
}
probe.open('search', { keyword: '科幻' });
assert.equal(keyword, '科幻', 'category search preserves its prefilled keyword');
assert.equal(probe.resolveParam({ uri: 'file://books/test.epub' }, 'uri'), 'file://books/test.epub');
assert.equal(probe.resolveParam({ bookIds: 'book-1,book-2' }, 'bookIds'), 'book-1,book-2');
console.log('PASS: home search, absent/invalid route parameters, category keyword and shared route fields');
