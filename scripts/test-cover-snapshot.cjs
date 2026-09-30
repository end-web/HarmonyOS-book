// Exercise the actual snapshot coordinator with slow, failed and superseded GPU requests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/OneShotTransition.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
const exported = {};
const timers = new Map();
let timerId = 0;
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exported, FrameCallback: class {},
  WindowUtils: { vpToPx: value => value },
  setTimeout: callback => { timers.set(++timerId, callback); return timerId; },
  clearTimeout: id => timers.delete(id) });
const coordinator = exported.OneShotTransitionCoordinator.getInstance();
const requests = [];
const context = {
  getComponentUtils: () => ({ getRectangleById: () => ({
    size: { width: 1200, height: 1200 }, windowOffset: { x: 0, y: 0 },
    scale: { x: 1, y: 1, centerX: 0, centerY: 0 }, translate: { x: 0, y: 0 }
  }) }),
  getComponentSnapshot: () => ({ get: (_id, options) => new Promise((resolve, reject) => {
    requests.push({ resolve, reject, options });
  }) })
};
function bitmap() { return { released: false, release() { this.released = true; return Promise.resolve(); } }; }
async function run() {
  const slow = coordinator.captureAsync(context, 'slow', 'cover', 12);
  assert.equal(requests[0].options.scale, 0.5, 'snapshot is capped at 600 pixels');
  for (const timer of [...timers.values()]) timer();
  await slow;
  assert.equal(coordinator.claim('slow'), undefined, 'timeout lets navigation continue without a snapshot');
  const late = bitmap(); requests[0].resolve(late); await Promise.resolve();
  assert.equal(late.released, true, 'late pixel map is released');
  const first = coordinator.captureAsync(context, 'first', 'cover', 12);
  const second = coordinator.captureAsync(context, 'second', 'cover', 12);
  const stale = bitmap(); requests[1].resolve(stale); await first;
  assert.equal(stale.released, true, 'superseded capture cannot overwrite the latest entry');
  const current = bitmap(); requests[2].resolve(current); await second;
  assert.equal(coordinator.claim('second').snapshot, current);
  const failed = coordinator.captureAsync(context, 'failed', 'cover', 12);
  requests[3].reject(new Error('GPU capture failed')); await failed;
  assert.equal(coordinator.claim('failed'), undefined);
  console.log('PASS: bounded capture, late release, superseded requests and capture failure');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
