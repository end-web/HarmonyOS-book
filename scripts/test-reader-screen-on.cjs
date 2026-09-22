// Real reader keep-screen service, simulated window lifecycle and clock.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
const timers = new Map();
const calls = [];
let nextTimer = 0;
let listener;
const window = {
  WindowEventType: { WINDOW_SHOWN: 1, WINDOW_HIDDEN: 4 },
  getLastWindow: async () => ({
    on: (_, callback) => { listener = callback; },
    off: () => { listener = undefined; },
    setWindowKeepScreenOn: async value => { calls.push(value); }
  })
};
function load(file) {
  if (modules.has(file)) return modules.get(file);
  const exports = {};
  modules.set(file, exports);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, {
    exports, console,
    setTimeout: (callback, delay) => { timers.set(++nextTimer, { callback, delay }); return nextTimer; },
    clearTimeout: id => timers.delete(id),
    require: name => name === '@kit.ArkUI' ? { window } : name.startsWith('@') ? {} :
      load(path.resolve(path.dirname(file), name + '.ets'))
  }, { filename: file });
  return exports;
}
const settle = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
(async () => {
  const { ReaderScreenOnService } = load(path.join(root, 'service/text/ReaderScreenOnService.ets'));
  const service = new ReaderScreenOnService();
  service.setVisible(true);
  await service.init({});
  await settle();
  assert.deepEqual(calls, [], 'system mode does not change the window');
  service.configure(5);
  await settle();
  assert.equal(calls.at(-1), true);
  assert.equal([...timers.values()][0].delay, 300000);
  const oldTimer = [...timers.keys()][0];
  service.touch();
  assert.equal(timers.has(oldTimer), false, 'interaction resets inactivity countdown');
  const [id, timer] = [...timers.entries()][0];
  timers.delete(id); timer.callback();
  await settle();
  assert.equal(calls.at(-1), false, 'timeout releases keep-on');
  service.configure(-1);
  await settle();
  assert.equal(calls.at(-1), true);
  assert.equal(timers.size, 0, 'always-on has no timer');
  listener(4);
  await settle();
  assert.equal(calls.at(-1), false, 'background releases keep-on');
  listener(1);
  await settle();
  assert.equal(calls.at(-1), true, 'foreground restores selected mode');
  service.setVisible(false);
  await settle();
  assert.equal(calls.at(-1), false, 'covered reader releases keep-on');
  service.setVisible(true);
  service.configure(1);
  assert.equal([...timers.values()][0].delay, 60000);
  service.dispose();
  await settle();
  assert.equal(calls.at(-1), false);
  assert.equal(timers.size, 0);
  assert.equal(listener, undefined);
  console.log('PASS: system mode, timed release, interaction reset, always-on, foreground/background, cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
