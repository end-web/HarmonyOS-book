// Exercise the actual transition coordinator with simulated window geometry and GPU completion.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/OneShotTransition.ets'), 'utf8')
  .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
const exportsObject = {};
let timerId = 0;
const timers = new Map();
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, {
  exports: exportsObject,
  require(name) {
    if (name === '@kit.ArkUI') return { FrameCallback: class {} };
    if (name === './WindowUtils') return { WindowUtils: { vpToPx: n => n * 3 } };
    throw new Error(`Unexpected dependency: ${name}`);
  },
  setTimeout(callback, delay) { timers.set(++timerId, { callback, delay }); return timerId; },
  clearTimeout(id) { timers.delete(id); }
});
const { OneShotRect, OneShotTransitionCoordinator, OneShotTransitionIds } = exportsObject;
const coordinator = OneShotTransitionCoordinator.getInstance();

function fixture() {
  const state = { y: 160, viewportWidth: 1080, missing: false, snapshotScale: 0,
    nodePositions: new Map(), capturedNode: '' };
  let complete;
  const pending = new Promise(resolve => { complete = resolve; });
  const pixelMap = { released: 0, release() { this.released++; return Promise.resolve(); } };
  const context = {
    vp2px: n => n * 3,
    getFrameNodeById(id) {
      if (state.missing) return null;
      return { getPositionToWindowWithTransform: () => id === OneShotTransitionIds.ROOT_NAVIGATION
        ? { x: 0, y: 24 } : { x: 16, y: state.nodePositions.get(id) ?? state.y } };
    },
    getComponentUtils: () => ({ getRectangleById(id) {
      return {
        // Raw layout is near the bottom; ancestor translate/scroll put the cover at y=160vp.
        windowOffset: { x: 48, y: 2100 }, translate: { x: 0, y: 12 },
        scale: { x: 1, y: 1, centerX: 0, centerY: 0 },
        size: id === OneShotTransitionIds.ROOT_NAVIGATION
          ? { width: state.viewportWidth, height: 2400 } : { width: 300, height: 420 }
      };
    } }),
    getComponentSnapshot: () => ({
      get(id, options) { state.capturedNode = id; state.snapshotScale = options.scale; return pending; },
      getSync() { throw new Error('Click must not synchronously read back GPU pixels'); }
    })
  };
  return { state, context, pixelMap, complete: () => complete(pixelMap) };
}

async function main() {
  // 同一本书的两个已挂载入口，书籍身份相同、实例和屏幕位置不同。
  const firstNode = OneShotTransitionIds.nextSourceId('home-row');
  const secondNode = OneShotTransitionIds.nextSourceId('home-row');
  assert.notEqual(firstNode, secondNode);
  for (const clicked of [secondNode, firstNode]) {
    const duplicate = fixture();
    duplicate.state.nodePositions.set(firstNode, 100);
    duplicate.state.nodePositions.set(secondNode, 600);
    const opening = coordinator.captureAsync(duplicate.context, 'same-book', clicked, 12);
    duplicate.complete();
    await opening;
    const selected = coordinator.claim('same-book');
    assert.equal(selected.sourceNodeId, clicked, 'return must retain the clicked instance');
    assert.equal(duplicate.state.capturedNode, clicked, 'snapshot must come from the clicked instance');
    assert.equal(selected.sourceRect.topPx, duplicate.state.nodePositions.get(clicked) * 3);
    OneShotTransitionCoordinator.releaseSnapshot(selected.snapshot);
  }
  const current = fixture();
  const rect = OneShotRect.measure(current.context, 'cover');
  assert.equal(rect.leftPx, 48);
  assert.equal(rect.topPx, 480, 'use transformed position, not raw layout or an extra own translate');
  assert.equal(rect.widthPx, 300, 'component size already uses px');
  current.state.missing = true;
  assert.equal(OneShotRect.measure(current.context, 'cover'), undefined);
  current.state.missing = false;
  current.state.y = NaN;
  assert.equal(OneShotRect.measure(current.context, 'cover'), undefined);

  const moving = fixture();
  const capture = coordinator.captureAsync(moving.context, 'moving', 'cover', 12);
  moving.state.y = 130;
  moving.complete();
  await capture;
  const payload = coordinator.claim('moving');
  assert.equal(payload.sourceRect.topPx, 390, 're-read position after GPU work during inertial scrolling');
  assert.equal(payload.viewportRect.topPx, 72, 'source and surface use the same window coordinate space');
  assert.equal(moving.state.snapshotScale, 1);
  OneShotTransitionCoordinator.releaseSnapshot(payload.snapshot);
  assert.equal(moving.pixelMap.released, 1);

  const slow = fixture();
  const slowCapture = coordinator.captureAsync(slow.context, 'slow', 'cover', 12);
  const timeout = [...timers.values()][0];
  assert.ok(timeout.delay <= 80, 'GPU waiting must be bounded');
  timeout.callback();
  await slowCapture;
  assert.equal(coordinator.claim('slow'), undefined, 'timeout allows normal navigation without a snapshot');
  slow.complete();
  await Promise.resolve();
  assert.equal(slow.pixelMap.released, 1, 'late GPU result must be released');

  const stale = fixture();
  const staleCapture = coordinator.captureAsync(stale.context, 'stale', 'cover', 12);
  coordinator.discardPending();
  stale.complete();
  await staleCapture;
  assert.equal(coordinator.claim('stale'), undefined);
  assert.equal(stale.pixelMap.released, 1, 'cancelled capture cannot overwrite a subsequent route');

  const resized = fixture();
  const resizedCapture = coordinator.captureAsync(resized.context, 'resized', 'cover', 12);
  resized.state.viewportWidth = 2400;
  resized.complete();
  await resizedCapture;
  assert.equal(coordinator.claim('resized'), undefined);
  assert.equal(resized.pixelMap.released, 1, 'window resize during capture falls back without mismatched geometry');
  assert.equal(timers.size, 0);
  console.log('PASS: duplicate-book instances, transformed geometry, moving source, missing node, snapshot timeout/cancellation/resize and release');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
