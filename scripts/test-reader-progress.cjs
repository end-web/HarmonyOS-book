// Exercise real reader methods with deterministic page layouts and an in-memory Preferences adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const events = new EventEmitter();
const mocks = {
  '@kit.BasicServicesKit': { emitter: events },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkData': { preferences: { getPreferences: async () => ({
    getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value),
    flush: async () => {}
  }) } }
};
function compile(relative, source) {
  const filename = path.join(root, relative + '.ets');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source ?? fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require: name => mocks[name] || {}, setTimeout, clearTimeout }, { filename });
  return exports;
}
mocks['./ReaderTheme'] = compile('model/ReaderTheme');
const model = compile('model/TextReading');
mocks['../model/TextReading'] = model;
mocks['../../model/TextReading'] = model;
mocks['../service/text/OnlineTextPaginator'] = compile('service/text/OnlineTextPaginator');
const { TextReadingProgressService: progress } = compile('service/text/TextReadingProgressService');
mocks['../service/text/TextReadingProgressService'] = { TextReadingProgressService: progress };
let source = fs.readFileSync(path.join(root, 'pages/ReaderPage.ets'), 'utf8');
source = source.slice(0, source.indexOf('  private readerTabStyle(')) + '\n}';
source = source.replace('@ComponentV2', '').replace('export struct', 'export class')
  .replace(/@(Param|Local)\s+/g, '');
const { ReaderPage } = compile('pages/ReaderPage', source);
const { TextReadingPosition, PageTurnMode } = model;
const content = '文'.repeat(300);
const pages = starts => starts.map((startOffset, index) => ({
  startOffset, endOffset: starts[index + 1] ?? content.length,
  text: content.slice(startOffset, starts[index + 1] ?? content.length)
}));
const normal = pages([0, 100, 200]);
const expanded = pages([0, 110, 220]);
function reader() {
  // Skip ArkUI construction, retaining the actual progress, load, reflow and turn methods.
  const page = Object.create(ReaderPage.prototype);
  Object.assign(page, {
    context: {}, book: { id: 'test-book', chapters: [{ title: '第一章' }, { title: '第二章' }] },
    pageTurnMode: PageTurnMode.Cover, currentResourceIndex: 0, currentChapterTitle: '第一章',
    onlineTextContent: content, onlineTextPages: normal, onlineTextPageIndex: 1,
    onlineTextTurnSerial: 0, onlineTextLoadSerial: 0, onlineTextTurnPreview: null,
    onlineTextTurnConfirmed: false, onlineTextTurnLoading: false, leaving: false,
    currentPosition: TextReadingPosition.atChar('test-book', 0, '', 100, 1, '第一章'),
    isOnlineTextBook: () => true, paginateOnlineTextContent: () => expanded,
    prefetchAdjacentOnlineTextChapters() {}, getOnlineTextChapterContent: async () => content
  });
  return page;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const page = reader();
  for (let repeat = 0; repeat < 3; repeat++) {
    page.paginateOnlineTextContent = () => expanded;
    page.repaginateOnlineText();
    assert.equal(page.currentPosition.charOffset, 100, 'temporary viewport must preserve the reading anchor');
    page.saveProgress();
    await tick();
    assert.equal((await progress.get({}, 'test-book')).charOffset, 100, 'background save must keep the confirmed character');
    page.paginateOnlineTextContent = () => normal;
    page.repaginateOnlineText();
    assert.equal(page.onlineTextPageIndex, 1, 'returning to the same viewport must restore the same page');
  }

  const reopened = reader();
  const saved = await progress.get({}, 'test-book');
  await reopened.loadOnlineTextChapter(saved.resourceIndex, saved.charOffset, saved.pageOffset, false, true);
  assert.equal(reopened.currentPosition.charOffset, 100, 'initial loading must preserve saved offset until layout settles');
  reopened.paginateOnlineTextContent = () => normal;
  reopened.repaginateOnlineText();
  assert.equal(reopened.onlineTextPageIndex, 1, 'reopening with an interim layout must not move back a page');

  const confirmed = reader();
  confirmed.onlineTextTurnPreview = { chapterIndex: 1, pageIndex: 1, content, pages: normal };
  confirmed.onlineTextTurnConfirmed = true;
  confirmed.repaginateOnlineText();
  assert.equal(confirmed.currentResourceIndex, 1, 'confirmed cross-chapter turn must survive reflow before animation finishes');
  assert.equal(confirmed.currentPosition.charOffset, 100);
  confirmed.paginateOnlineTextContent = () => normal;
  confirmed.repaginateOnlineText();
  assert.equal(confirmed.onlineTextPageIndex, 1);

  const cancelled = reader();
  cancelled.onlineTextTurnPreview = { chapterIndex: 1, pageIndex: 1, content, pages: normal };
  cancelled.repaginateOnlineText();
  assert.equal(cancelled.currentResourceIndex, 0, 'unconfirmed drag must keep the original chapter');
  assert.equal(cancelled.currentPosition.charOffset, 100);

  page.onlineTextPageIndex = 2;
  page.updateOnlineTextPosition(true);
  await tick();
  assert.equal((await progress.get({}, 'test-book')).charOffset, 200, 'a deliberate turn must advance the saved anchor');
  console.log('PASS: repeated Home/layout restoration, saved-position reload, confirmed cross-chapter turn, cancelled drag, deliberate page turn');
})().catch(error => { console.error(error); process.exitCode = 1; });
