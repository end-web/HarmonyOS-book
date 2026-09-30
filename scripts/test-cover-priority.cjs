const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const mocks = {};
function load(relative) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, relative + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require: name => mocks[name] || {}, console });
  return exports;
}
const { BookCoverPolicy: policy } = load('utils/BookCoverPolicy');
mocks['./BookCoverPolicy'] = mocks['../utils/BookCoverPolicy'] = { BookCoverPolicy: policy };
const { SearchCache: cache } = load('utils/SearchCache');
const { DataService: data } = load('service/DataService');
const create = (cover = 'thumb.jpg') => ({ id: 'book', sourceUrl: 'source', bookUrl: '/book',
  cover, title: 'Book', author: '', narrator: '', category: '', intro: '', totalDuration: 0,
  chapterCount: 0, rating: 0, tags: [], chapters: [] });
const detail = create();
policy.setDetail(detail, 'detail.jpg');
detail.chapters = [{ id: 'book-c0' }];
detail.chapterCount = 1;
cache.put(detail);
const freshSearch = create('new-thumb.jpg');
cache.put(freshSearch);
assert.equal(freshSearch.cover, 'detail.jpg', 'search must not downgrade a known detail cover');
assert.equal(freshSearch.coverFromDetail, true);
assert.equal(freshSearch.coverFallback, 'new-thumb.jpg');
assert.equal(freshSearch.chapters.length, 1, 'existing chapter preservation remains intact');
const stored = JSON.parse(JSON.stringify(data.slimBook(freshSearch)));
assert.equal(stored.coverFromDetail, true, 'metadata shell retains provenance across restart');
assert.equal(stored.coverFallback, 'new-thumb.jpg');
cache.clear();
const afterRestart = create('cold-thumb.jpg');
policy.merge(afterRestart, stored);
assert.equal(afterRestart.cover, 'detail.jpg', 'disk restore preserves detail cover priority');
assert.equal(afterRestart.coverFallback, 'cold-thumb.jpg');
const updated = create('new-detail.jpg');
policy.setDetail(updated, 'new-detail.jpg');
policy.merge(updated, stored);
assert.equal(updated.cover, 'new-detail.jpg', 'new detail URL may replace old signed/expired URL');
assert.equal(updated.coverFallback, 'new-thumb.jpg');
policy.setDetail(updated, '');
assert.equal(updated.cover, 'new-detail.jpg', 'missing detail cover does not erase usable cover');
const otherSource = create('other.jpg');
otherSource.sourceUrl = 'other';
policy.merge(otherSource, stored);
assert.equal(otherSource.cover, 'other.jpg', 'do not reuse another source cover');
const legacy = create('old.jpg');
const fresh = create('fresh.jpg');
policy.merge(fresh, legacy);
assert.equal(fresh.cover, 'fresh.jpg', 'unclassified legacy cover does not lock out updates');
const missing = create('');
policy.merge(missing, stored);
assert.equal(missing.cover, 'detail.jpg');
assert.equal(missing.coverFallback, 'new-thumb.jpg');
const equal = create('same.jpg');
policy.setDetail(equal, 'same.jpg');
assert.equal(equal.coverFromDetail, true);
assert.equal(equal.coverFallback, undefined, 'same URL is not a useful fallback');
console.log('Cover priority regression passed: search, persistence, restore, updates, source isolation, legacy data');
