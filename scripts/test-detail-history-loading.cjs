// Exercise real page methods with deterministic navigation/network timing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages', name), 'utf8').replace(/\r\n/g, '\n');
function between(source, start, end) {
  const from = source.indexOf(start), to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, 'real page method boundaries exist');
  return source.slice(from, to);
}
function compile(source, mocks = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, ...mocks });
  return exports.Page;
}
const detail = read('BookDetailPage.ets');
const Detail = compile(`class Page {
  book = null; deferEntry = false; loadingDetail = false; loadingToc = false;
  isStartingPlay = false; lastHistory = null; textReadingProgress = null;
  calls = []; openTextReader(chapter) { this.calls.push(['read', chapter]); }
  startPlay(chapter) { this.calls.push(['play', chapter]); }
  ${between(detail, '  private openPrimaryAction(', '  private openTextReader(')}
  ${between(detail, '  private primaryCtaLabel()', '  @Builder\n  buildPrimaryCta()')}
} exports.Page = Page;`, { $r: name => name });

async function tick() { for (let i = 0; i < 8; i++) await Promise.resolve(); }
function historyHarness() {
  const timers = new Map(), requests = []; let serial = 0;
  const history = read('SessionHistoryPage.ets');
  const History = compile(`class Page {
    visible = false; loaded = false; loadGeneration = 0; entryTimer = -1;
    transitioning = false; transitionOffset = 0;
    loading = true; failed = false; count = 0; bookIds = '["book"]';
    records = { items: [], update(items) { this.items = items; } };
    ${between(history, '  aboutToDisappear()', '  private time(')}
  } exports.Page = Page;`, {
    setTimeout(fn) { timers.set(++serial, fn); return serial; },
    clearTimeout(id) { timers.delete(id); },
    NavigationOperation: { PUSH: 1, POP: 2 }, Curve: { FastOutSlowIn: 'curve' },
    WindowUtils: { getWindowWidthVp: () => 400 },
    ReadingSessionService: { list(ids, active) {
      return new Promise((resolve, reject) => requests.push({ ids, active, resolve, reject }));
    } }
  });
  return { page: new History(), timers, requests, runTimers() {
    const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn());
  } };
}

(async () => {
  for (const contentType of ['audio', 'text']) {
    const page = new Detail(); page.book = { contentType, chapters: [] };
    for (const stage of ['deferEntry', 'loadingDetail', 'loadingToc']) {
      page[stage] = true;
      assert.equal(page.primaryCtaLabel(), 'app.string.book_detail_loading_chapters');
      page.openPrimaryAction(); assert.equal(page.calls.length, 0);
      page[stage] = false;
    }
    page.openPrimaryAction(); assert.equal(page.calls.length, 0, 'Empty catalogs never navigate');
    const chapter = { id: 'chapter' }; page.book.chapters.push(chapter);
    page.loadingToc = true;
    const suffix = contentType === 'text' ? 'read' : 'listen';
    assert.equal(page.primaryCtaLabel(), `app.string.book_detail_start_${suffix}`);
    page.openPrimaryAction(chapter);
    assert.equal(page.calls[0][0], contentType === 'text' ? 'read' : 'play');
    assert.equal(page.calls[0][1], chapter);
    page.loadingDetail = true; page.openPrimaryAction(chapter);
    assert.equal(page.calls.length, 2, 'Metadata refresh must not block existing chapters');
    page.loadingDetail = false;
    page.deferEntry = true; page.openPrimaryAction(chapter);
    assert.equal(page.calls.length, 2, 'Transition guard is retained');
    page.deferEntry = false;
    page.loadingToc = false; page.tocFailed = true; page.openPrimaryAction(chapter);
    assert.equal(page.calls.length, 3, 'A later catalog failure keeps loaded chapters usable');
    page.lastHistory = {}; page.textReadingProgress = {};
    assert.equal(page.primaryCtaLabel(), `app.string.book_detail_continue_${suffix}`);
    page.isStartingPlay = true; page.openPrimaryAction(); assert.equal(page.calls.length, 3);
    page.isStartingPlay = false; page.book = null; page.openPrimaryAction();
    assert.equal(page.calls.length, 3);
  }
  console.log('PASS detail: first chapters immediately read/play, background loading and later failure retain actions, empty/transition/duplicate guards');

  const h = historyHarness();
  const transition = h.page.historyTransition(1, true)[0];
  assert.equal(h.page.transitionOffset, 400);
  h.page.onPageShown(); h.runTimers();
  assert.equal(h.requests.length, 0, 'no history work during the real transition');
  transition.event(); assert.equal(h.page.transitionOffset, 0);
  transition.onTransitionEnd();
  h.page.onPageShown(); h.page.onPageShown();
  assert.equal(h.timers.size, 1); assert.equal(h.requests.length, 0);
  h.page.stopLoading(); h.runTimers(); assert.equal(h.requests.length, 0);
  h.page.onPageShown(); h.runTimers();
  const old = h.requests[0]; assert.equal(old.active(), true);
  h.page.stopLoading(); assert.equal(old.active(), false);
  h.page.onPageShown(); h.runTimers();
  h.requests[1].resolve([{ id: 'new' }]); await tick();
  old.resolve([{ id: 'old' }, { id: 'old2' }]); await tick();
  assert.equal(h.page.count, 1); assert.equal(h.page.records.items[0].id, 'new');
  assert.equal(h.page.loading, false);
  h.page.stopLoading(); h.page.onPageShown(); assert.equal(h.timers.size, 0);

  const retry = historyHarness(); retry.page.onPageShown(); retry.runTimers();
  retry.requests[0].reject(new Error('unavailable')); await tick();
  assert.equal(retry.page.failed, true); assert.equal(retry.page.loading, false);
  const work = retry.page.load(); retry.requests[1].resolve([]); await work;
  assert.equal(retry.page.failed, false); assert.equal(retry.page.loaded, true);
  console.log('PASS history page: deferred loading, navigation cancellation, stale response isolation, retained list, retry');
})().catch(error => { console.error(error); process.exitCode = 1; });
