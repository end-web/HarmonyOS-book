// Exercise the real background task service with reordered system callbacks.
// Run: DEVECO_HOME=<Release IDE> node scripts/test-background-playback.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = path.join(__dirname, '../entry/src/main/ets/service/BackgroundTaskService.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const flush = () => new Promise(resolve => setImmediate(resolve));

function fixture() {
  const listeners = new Map();
  const calls = [];
  let nextId = 0;
  const manager = {
    on(event, callback) { listeners.set(event, callback); },
    async startBackgroundRunning(_context, modes) {
      const id = ++nextId;
      calls.push({ action: 'start', id, modes: [...modes] });
      return { continuousTaskId: id, notificationId: id };
    },
    async updateBackgroundRunning(_context, modes) { calls.push({ action: 'update', modes: [...modes] }); },
    async stopBackgroundRunning() { calls.push({ action: 'stop' }); }
  };
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports,
    require(name) {
      if (name === '@kit.BackgroundTasksKit') return { backgroundTaskManager: manager };
      if (name === '@kit.AbilityKit') return { wantAgent: {
        OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 },
        getWantAgent: async () => ({})
      } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name === '../utils/PlatformCompat') return { PlatformCompat: { supports: () => false } };
      if (name === './DiagnosticLogService') return { DiagnosticLogService: { info() {}, failure() {} } };
      throw new Error(`Unexpected dependency: ${name}`);
    }
  }, { filename: source });
  return { service: module.exports.BackgroundTaskService, manager, calls,
    context: { abilityInfo: { bundleName: 'test.background', name: 'EntryAbility' } },
    emit: (event, info) => listeners.get(event)?.(info) };
}

test('late cancellation from an old task does not cancel resumed playback', async () => {
  const f = fixture();
  await f.service.start(f.context);
  await f.service.stop(f.context);
  f.service.resumeAfterUserAction();
  await f.service.start(f.context);
  f.emit('continuousTaskCancel', { id: 1, reason: 2 });
  assert.equal(f.service.isRunning(), true);
  assert.equal(f.calls.filter(call => call.action === 'start').length, 2);
});

test('a cancellation delivered before start resolves cannot resurrect the cancelled task', async () => {
  const f = fixture();
  let complete;
  f.manager.startBackgroundRunning = () => new Promise(resolve => { complete = resolve; });
  const starting = f.service.start(f.context);
  await flush();
  f.emit('continuousTaskCancel', { id: 7, reason: 2 });
  complete({ continuousTaskId: 7 });
  await starting;
  assert.equal(f.service.isRunning(), false);
  await f.service.ensure(f.context);
  assert.equal(f.service.isRunning(), false, 'Automatic work must respect system cancellation');
});

test('activation from a cancelled task cannot restore background eligibility', async () => {
  const f = fixture();
  await f.service.start(f.context);
  f.emit('continuousTaskCancel', { id: 1, reason: 1 });
  f.emit('continuousTaskActive', { id: 1 });
  assert.equal(f.service.isRunning(), false);
});

test('explicit pause also releases a suspended task', async () => {
  const f = fixture();
  await f.service.start(f.context);
  f.emit('continuousTaskSuspend', { continuousTaskId: 1, suspendReason: 1 });
  await f.service.stop(f.context);
  assert.equal(f.calls.filter(call => call.action === 'stop').length, 1);
  f.emit('continuousTaskActive', { id: 1 });
  assert.equal(f.service.isRunning(), false);
});

test('a real suspended task can resume and owners do not cancel each other', async () => {
  const f = fixture();
  await f.service.start(f.context);
  await f.service.startSpeech(f.context);
  await f.service.startDataTransfer(f.context, 'preload');
  await f.service.stopSpeech(f.context);
  assert.equal(f.service.isRunning(), true);
  f.emit('continuousTaskSuspend', { continuousTaskId: 1, suspendReason: 1 });
  assert.equal(f.service.isRunning(), false);
  f.emit('continuousTaskActive', { id: 1 });
  assert.equal(f.service.isRunning(), true);
  await f.service.stop(f.context);
  assert.deepEqual(f.calls.at(-1).modes, ['dataTransfer']);
  await f.service.stopDataTransfer(f.context, 'preload');
  assert.equal(f.service.isRunning(), false);
});

test('media session callers wait for activation, not merely native object creation', async () => {
  let activate;
  const session = { activate: () => new Promise(resolve => { activate = resolve; }) };
  const filename = path.join(path.dirname(source), 'AVSessionService.ets');
  const sessionCode = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(sessionCode, {
    module, exports: module.exports,
    require(name) {
      if (name === '@kit.AVSessionKit') return { avSession: {
        LoopMode: { LOOP_MODE_SEQUENCE: 0, LOOP_MODE_LIST: 1, LOOP_MODE_SINGLE: 2 },
        createAVSession: async () => session
      } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      return {};
    }
  }, { filename });
  const service = module.exports.AVSessionService.getInstance();
  service.registerCommands = service.configureMediaCenter = service.configureUrlCasting = () => {};
  service.setupLaunchAbility = async () => {};
  const first = service.init({});
  await flush();
  let ready = false;
  const waiting = service.ensureReady().then(() => { ready = true; });
  assert.equal(service.init({}), first);
  await flush();
  assert.equal(ready, false);
  activate();
  await Promise.all([first, waiting]);
  assert.equal(ready, true);
});
