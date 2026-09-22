// Runs the real ArkTS service with temporary disk files and simulated HarmonyOS APIs.
// Usage: node scripts/test-stats-persistence.cjs [StatsService.ets]
// Requires DEVECO_HOME (or DEVECO_PATH) to point to the installed IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = process.argv[2] || path.join(__dirname, '../entry/src/main/ets/service/StatsService.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-stats-test-'));
const primaryPath = path.join(root, 'preferences.json');
const snapshotPath = path.join(root, 'listening_stats_v3.json');
const context = { filesDir: root };
const book = { bookId: 'audio-fixture', title: 'Statistics fixture' };
let now = new Date(2026, 8, 13, 23, 59, 50).getTime();
let failPrimaryRead = false;
let failPrimaryWrite = false;
let failSnapshotWrite = false;
let failInitialization = false;
let passed = 0;

class TestDate extends Date {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
}

function newProcess() {
  const handles = new Map();
  let nextFd = 0;
  const fileIo = {
    OpenMode: { CREATE: 1, TRUNC: 2, READ_WRITE: 4 },
    access: async name => fs.existsSync(name),
    readText: async name => fs.promises.readFile(name, 'utf8'),
    open: async name => {
      if (failSnapshotWrite) throw new Error('Snapshot storage unavailable');
      const fd = ++nextFd;
      handles.set(fd, await fs.promises.open(name, 'w'));
      return { fd };
    },
    write: async (fd, data) => handles.get(fd).write(data),
    fsync: async fd => handles.get(fd).sync(),
    close: async file => { const fd = typeof file === 'number' ? file : file.fd; await handles.get(fd).close(); handles.delete(fd); },
    rename: async (from, to) => fs.promises.rename(from, to)
  };
  const preferences = {
    getPreferences: async () => {
      if (failInitialization) throw new Error('Initialization unavailable');
      let memory = fs.existsSync(primaryPath) ? JSON.parse(fs.readFileSync(primaryPath, 'utf8')) : {};
      return {
        get: async (key, fallback) => {
          if (failPrimaryRead) throw new Error('Primary read unavailable');
          return memory[key] ?? fallback;
        },
        put: async (key, value) => {
          if (failPrimaryWrite) throw new Error('Primary write unavailable');
          memory[key] = value;
        },
        flush: async () => fs.promises.writeFile(primaryPath, JSON.stringify(memory))
      };
    }
  };
  const modules = {
    '@kit.ArkData': { preferences },
    '@kit.CoreFileKit': { fileIo },
    '@kit.BasicServicesKit': { emitter: { emit() {} } }
  };
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, Date: TestDate, Error, Promise, Set, Map,
    console: process.env.STATS_TEST_VERBOSE ? console : { warn() {}, error() {} },
    require: name => {
      if (!modules[name]) throw new Error(`Unexpected dependency: ${name}`);
      return modules[name];
    }
  }, { filename: source });
  return module.exports.StatsService;
}

async function check(name, test) {
  await test();
  passed++;
  console.log(`PASS ${name}`);
}

(async () => {
  let service = newProcess();
  await service.init(context);
  await check('concurrent increments are all retained', async () => {
    await Promise.all(Array.from({ length: 12 }, () => service.addListenSeconds(10, book)));
    assert.equal((await service.getSummary()).totalSeconds, 120);
  });
  await check('midnight starts a new day without resetting lifetime totals', async () => {
    const beforeMidnight = service.addListenSeconds(10, book);
    now = new Date(2026, 8, 14, 0, 0, 5).getTime();
    const afterMidnight = service.addListenSeconds(20, book);
    await Promise.all([beforeMidnight, afterMidnight]);
    const summary = await service.getSummary();
    assert.equal(summary.totalSeconds, 150);
    assert.equal(summary.todaySeconds, 20);
    assert.equal((await service.getBookStats())[0].days.find(day => day.day === '2026-09-13').listenSeconds, 130);
  });
  await check('a new process restores persisted records and summary', async () => {
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getStatsBundle(2)).summary.totalSeconds, 150);
    const copy = await service.getBookStats();
    copy[0].listenSeconds = 0;
    copy[0].days[0].listenSeconds = 0;
    assert.equal((await service.getSummary()).totalSeconds, 150);
  });
  await check('corrupt primary records recover from the independent snapshot', async () => {
    const primary = JSON.parse(fs.readFileSync(primaryPath, 'utf8'));
    primary.book_usage_records_v2 = '{broken';
    fs.writeFileSync(primaryPath, JSON.stringify(primary));
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 150);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 160);
  });
  await check('failed primary reads and writes retain the newest disk snapshot', async () => {
    failPrimaryRead = true;
    failPrimaryWrite = true;
    service = newProcess();
    await service.init(context);
    await service.addListenSeconds(10, book);
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 170);
    failPrimaryRead = false;
    failPrimaryWrite = false;
    await service.flush();
  });
  await check('failed writes retry cached increments without blocking later work', async () => {
    failSnapshotWrite = true;
    failPrimaryWrite = true;
    await assert.rejects(service.addListenSeconds(10, book));
    assert.equal((await service.getSummary()).totalSeconds, 180);
    failSnapshotWrite = false;
    failPrimaryWrite = false;
    await service.flush();
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 180);
  });
  await check('lifetime totals outlive daily-detail retention', async () => {
    now = new Date(2029, 8, 14, 0, 0, 0).getTime();
    assert.equal((await service.getSummary()).totalSeconds, 180);
    assert.equal((await service.getSummary()).todaySeconds, 0);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 190);
  });
  await check('explicit deletion and clearing do not resurrect snapshot data', async () => {
    await service.removeBookStats([book.bookId]);
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 0);
    await service.addListenSeconds(10, book);
    await service.clearBookStats();
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getBookStats()).length, 0);
  });
  await check('initialization retries after an error', async () => {
    service = newProcess();
    failInitialization = true;
    await assert.rejects(service.init(context));
    failInitialization = false;
    await service.init(context);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 10);
  });
  await check('legacy records migrate without changing existing cumulative hours', async () => {
    now = new Date(2026, 8, 14, 0, 0, 5).getTime();
    const legacy = [{ bookId: book.bookId, title: book.title, listenSeconds: 28800,
      updatedAt: new Date(2026, 8, 13).getTime(), days: [{ day: '2026-09-13', listenSeconds: 28800 }] }];
    fs.unlinkSync(snapshotPath);
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: JSON.stringify(legacy) }));
    service = newProcess();
    await service.init(context);
    assert.equal(service.getCachedStatsBundle(1).summary.totalSeconds, 28800);
    assert.equal(JSON.parse(fs.readFileSync(snapshotPath, 'utf8')).records[0].listenSeconds, 28800);
  });
  await check('unreadable primary and snapshot are never replaced with zeroes', async () => {
    const primary = fs.readFileSync(primaryPath, 'utf8');
    const snapshot = fs.readFileSync(snapshotPath, 'utf8');
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: 'invalid' }));
    fs.writeFileSync(snapshotPath, 'invalid');
    service = newProcess();
    await assert.rejects(service.init(context));
    await assert.rejects(service.addListenSeconds(10, book));
    assert.equal(fs.readFileSync(snapshotPath, 'utf8'), 'invalid');
    assert.equal(JSON.parse(fs.readFileSync(primaryPath, 'utf8')).book_usage_records_v2, 'invalid');
    fs.writeFileSync(primaryPath, primary);
    fs.writeFileSync(snapshotPath, snapshot);
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 28800);
  });
  await check('backup skips one corrupt statistics record without initializing or rewriting the original stores', async () => {
    const primary = JSON.stringify({ book_usage_revision_v3: 1, book_usage_records_v2: JSON.stringify([
      { bookId: 'valid', title: 'Valid', listenSeconds: 80, updatedAt: now, days: [] }, null, { title: 'No id' }
    ]) });
    const durable = JSON.stringify({ version: 1, revision: 2, records: [null,
      { bookId: 'newer', title: 'Newer', listenSeconds: 90, updatedAt: now, days: [] }, { bookId: 123 }
    ] });
    fs.writeFileSync(primaryPath, primary);
    fs.writeFileSync(snapshotPath, durable);
    const exporting = newProcess();
    const records = await exporting.exportBackupStats(context);
    assert.equal(records.length, 1);
    assert.equal(records[0].bookId, 'newer');
    assert.equal(records[0].listenSeconds, 90);
    assert.equal(fs.readFileSync(primaryPath, 'utf8'), primary);
    assert.equal(fs.readFileSync(snapshotPath, 'utf8'), durable);
    assert.equal(exporting.getCachedStatsBundle(1), undefined);
    fs.unlinkSync(snapshotPath);
    assert.equal((await newProcess().exportBackupStats(context))[0].bookId, 'valid');
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: 'invalid' }));
    await assert.rejects(newProcess().exportBackupStats(context), /could not be read/);
  });
  console.log(`${passed} statistics persistence checks passed (real temporary files, simulated platform APIs).`);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => {
  const resolvedRoot = path.resolve(root);
  if (path.dirname(resolvedRoot) !== path.resolve(os.tmpdir()) ||
      !path.basename(resolvedRoot).startsWith('hsda-stats-test-')) throw new Error('Invalid test cleanup path');
  fs.rmSync(resolvedRoot, { recursive: true, force: true });
});
