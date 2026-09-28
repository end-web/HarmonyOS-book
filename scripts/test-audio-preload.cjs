// Real cache/import services with controlled transfers and file metadata.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const sizes = new Map();
const transfers = [];
const events = [];
class Transfer {
  cancelled = false;
  download(options) {
    this.options = options;
    transfers.push(this);
    return new Promise((resolve, reject) => { this.resolve = resolve; this.reject = reject; });
  }
  finish(bytes) { sizes.set(this.options.finalPath, bytes); this.resolve(bytes); }
  cancel() { this.cancelled = true; this.reject(new Error('cancelled')); }
}
const modules = new Map();
const invalidated = [];
const imports = [];
let importFailure = false;
let storedChapters = [];
const source = { bookSourceUrl: 'https://source.invalid', isLocked: false };
const locked = { bookSourceUrl: 'https://locked.invalid', isLocked: true };
const stubs = {
  '@kit.CoreFileKit': { fileIo: {
    statSync: filename => { if (!sizes.has(filename)) throw new Error('missing'); return { size: sizes.get(filename) }; },
    utimes() {}, listFile: async () => [], unlink: async filename => sizes.delete(filename),
    unlinkSync: filename => sizes.delete(filename)
  } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } },
  '@kit.BasicServicesKit': { emitter: { emit: event => events.push(event) } },
  '@kit.MediaKit': { media: {} },
  'service/PreferenceService': { PreferenceService: { chapterStep: () => 1 } },
  'service/AudioDownloadTransport': { AudioDownloadTransport: Transfer },
  'service/BookSourceService': { BookSourceService: { invalidateAudioTocs: urls => invalidated.push([...urls]),
    resolveAudioRequest: async () => { throw new Error('Cached files must not resolve source requests'); } } },
  'service/SourceDataService': { SourceDataService: { invalidateLocalSources() {} } },
  'service/DataService': { DataService: { invalidateSourceCaches: async (urls, beforeInvalidate) => {
    if (beforeInvalidate) beforeInvalidate('stored-book', storedChapters);
    invalidated.push([...urls]); return ['book'];
  } } },
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: {
    getAll: async () => [source, locked], upsertImportedBatch: async values => {
      if (importFailure) throw new Error('transaction failed');
      imports.push(values); return values.filter(item => item.bookSourceUrl !== locked.bookSourceUrl).length;
    }
  } }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  const filename = path.join(root, name + '.ets');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout, clearTimeout,
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
(async () => {
  const { ChapterCacheService } = load('service/ChapterCacheService');
  const cache = ChapterCacheService.getInstance();
  cache.setContext({ cacheDir: '/cache' });
  const chapters = [0, 1].map(index => ({ id: `book-c${index}`, index: index + 1, title: `episode ${index}`,
    duration: 0, source: { type: 'url', value: `https://source.invalid/chapter/${index}` } }));
  const book = { id: 'book', sourceUrl: source.bookSourceUrl, chapters };
  cache.audioCache.set(chapters[0].id, { resolvedUrl: 'https://cdn.invalid/audio.mp3', headers: {} });
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), false, 'A resolved URL is not a complete cache');
  const first = cache.downloadFile(book, chapters[0], 'https://cdn.invalid/first.mp3');
  const duplicate = cache.downloadFile(book, chapters[0], 'https://cdn.invalid/first.mp3');
  assert.equal(first, duplicate, 'One transfer per chapter');
  const second = cache.downloadFile(book, chapters[1], 'https://cdn.invalid/second.mp3');
  assert.equal(transfers.length, 2);
  cache.suspendPreload(chapters[0].id);
  assert.equal(transfers[0].cancelled, false, 'Switching keeps target transfer');
  assert.equal(transfers[1].cancelled, true, 'Other transfers release network capacity');
  const waiting = cache.waitForAudioFile(book, chapters[0]);
  transfers[0].finish(6 * 1024 * 1024);
  assert.ok(await waiting);
  await Promise.all([first, second]);
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), true);
  assert.equal(cache.isAudioChapterCached(book, chapters[1]), false);
  assert.ok(events.includes('app.chapter.cache.updated'));
  assert.equal(transfers.length, 2, 'Playing a complete cache does not start a fresh transfer');
  cache.resumePreload();
  console.log('PASS complete-file status, files above 5 MiB, transfer coalescing and selected preload reuse');

  const { SearchCache } = load('utils/SearchCache');
  // Reimport after a cold start must remove files absent from the in-memory cache.
  cache.fileCache.clear();
  storedChapters = [{ ...chapters[0], id: 'stored-book-c0' }];
  const legacy = cache.legacyAudioFilePath(book.id, chapters[0].id);
  const stored = cache.audioFilePath('stored-book', storedChapters[0].source.value);
  const storedLegacy = cache.legacyAudioFilePath('stored-book', storedChapters[0].id);
  const unrelated = cache.audioFilePath('other-book', 'https://other.invalid/chapter');
  for (const filename of [legacy, stored, storedLegacy, unrelated]) sizes.set(filename, 6000);
  SearchCache.put({ ...book, title: 'book', cover: '', variables: { old: 'yes' } });
  SearchCache.put({ ...book, id: 'locked-book', sourceUrl: locked.bookSourceUrl, cover: '', chapters: chapters.slice() });
  const { LocalRuleSourceImportService } = load('service/rulesource/LocalRuleSourceImportService');
  assert.equal(await LocalRuleSourceImportService.importSources([source, locked,
    { bookSourceUrl: 'https://new.invalid' }]), 2);
  assert.deepEqual(invalidated, [[source.bookSourceUrl], [source.bookSourceUrl]]);
  assert.equal(SearchCache.get('book').chapters.length, 0);
  assert.equal(SearchCache.get('locked-book').chapters.length, 2);
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), false);
  for (const filename of [legacy, stored, storedLegacy]) assert.equal(sizes.has(filename), false);
  assert.equal(sizes.has(unrelated), true, 'Other sources retain their audio files');
  importFailure = true;
  await assert.rejects(LocalRuleSourceImportService.importSources([source]), /transaction failed/);
  assert.equal(invalidated.length, 2, 'Failed transactions never reset content caches');
  console.log('PASS source overwrite resets only unlocked existing sources after a successful transaction');
})().catch(error => { console.error(error); process.exitCode = 1; });
