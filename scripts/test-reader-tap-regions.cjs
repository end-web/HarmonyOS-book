// Real tap policy, touch tracker and Preferences persistence with platform adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const TouchType = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
const cache = new Map();
const mocks = {
  '@kit.ArkData': { preferences: { getPreferences: async () => ({
    getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), flush: async () => {}
  }) } }
};
function load(filename) {
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, TouchType, require: name => name.startsWith('.') ?
    load(path.resolve(path.dirname(filename), name + '.ets')) : mocks[name] || {} }, { filename });
  return exports;
}
const { ReaderTapPolicy: policy, ReaderTouchTracker: Tracker } = load(path.join(root, 'utils/ReaderTapPolicy.ets'));
const tracker = new Tracker();
const event = (type, x, y, fingers = 1) => ({ type,
  touches: Array.from({ length: fingers }, () => ({ x, y })), changedTouches: [{ x, y }] });
tracker.update(event(TouchType.Down, 100, 100));
tracker.update(event(TouchType.Move, 103, 102));
tracker.update(event(TouchType.Up, 103, 102, 0));
assert.equal(tracker.canTap(), true, 'small finger jitter remains a tap');
tracker.update(event(TouchType.Down, 100, 100));
tracker.update(event(TouchType.Move, 100, 125));
tracker.update(event(TouchType.Up, 100, 100, 0));
assert.equal(tracker.canTap(), false, 'returning to start after scrolling cannot open toolbar');
tracker.update(event(TouchType.Down, 100, 100));
tracker.update(event(TouchType.Down, 100, 100, 2));
tracker.update(event(TouchType.Up, 100, 100, 0));
assert.equal(tracker.canTap(), false, 'multi-touch is not a tap');
tracker.update(event(TouchType.Down, 100, 100));
tracker.update(event(TouchType.Cancel, 100, 100));
assert.equal(tracker.canTap(), false);
tracker.update(event(TouchType.Down, 100, 100));
tracker.cancel();
assert.equal(tracker.canTap(), false, 'native scrolling/pan cancels tap');
const layout = '321012210';
assert.equal(policy.resolve(policy.DEFAULT, 150, 150, 300, 300, 60, 10, 20, 20), 0);
assert.equal(policy.resolve(policy.DEFAULT, 260, 150, 300, 300, 60, 10, 20, 20), 1);
assert.equal(policy.resolve(policy.DEFAULT, 280, 150, 300, 300, 60, 10, 20, 20), 2);
assert.equal(policy.resolve('000111222', 150, 45, 300, 300, 33, 33, 10, 20), 1);
assert.equal(policy.percent(90, 60), 30);
assert.equal(policy.percent(-2), 5);
for (let i = 0; i < 9; i++) {
  assert.equal(policy.resolve(layout, (i % 3) * 100 + 50, Math.floor(i / 3) * 100 + 50, 300, 300), Number(layout[i]));
}
assert.equal(policy.resolve(layout, -1, 0, 300, 300), 3, 'camera inset excluded');
assert.equal(policy.resolve(layout, 300, 0, 300, 300), 3);
assert.equal(policy.normalize('000000000'), policy.DEFAULT);
assert.equal(policy.cycle('000010000', 4), '000010000', 'last toolbar entry remains reachable');
assert.equal(policy.normalize('broken'), policy.DEFAULT);
(async () => {
  const { TextReadingSettingsService: settings } = load(path.join(root, 'service/text/TextReadingSettingsService.ets'));
  const initial = await settings.get({});
  assert.equal(initial.tapRegions, policy.DEFAULT, 'old preferences get default regions');
  initial.tapRegions = layout;
  initial.tapLeftPercent = 60; initial.tapRightPercent = 10;
  initial.showHeader = false; initial.showFooter = false; initial.showBookName = false;
  await settings.save({}, initial);
  assert.equal((await settings.get({})).tapRegions, layout, 'custom regions survive reload');
  const restored = await settings.get({});
  assert.equal(restored.tapLeftPercent, 60); assert.equal(restored.tapRightPercent, 10);
  assert.equal(restored.showHeader, false); assert.equal(restored.showFooter, false);
  assert.equal(restored.showBookName, false);
  values.set('tap_regions', 'bad');
  assert.equal((await settings.get({})).tapRegions, policy.DEFAULT);
  console.log('reader tap regions: movement, cancellation, mapping and persistence passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
