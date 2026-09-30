// Exercise the real navigation coordinator, including release-before-proxy races.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/PlayerDragTransition.ets'), 'utf8')
  .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, {
  exports: exportsObject,
  require: name => name === './WindowUtils' ? { WindowUtils: { pxToVp: value => value } } : {
    OneShotTransitionCoordinator: { releaseSnapshot: () => {} }
  }
});
const drag = exportsObject.PlayerDragTransition.getInstance();
function origin() {
  const value = new exportsObject.PlayerDragOrigin();
  value.left = 294; value.top = 720; value.width = 56; value.height = 56;
  value.coverLeft = 297; value.coverTop = 723; value.coverWidth = 50; value.coverHeight = 50;
  value.viewportWidth = 366; value.viewportHeight = 800;
  return value;
}
function proxy() {
  return {
    progress: [], finished: 0, cancelled: 0,
    updateTransition(value) { this.progress.push(value); },
    finishTransition() { this.finished++; },
    cancelTransition() { this.cancelled++; }
  };
}

assert.equal(drag.begin(800, 30, origin()), false, 'downward swipe does not open the player');
assert.equal(drag.begin(0, -30, origin()), false, 'unmeasured viewport cannot begin a transition');

// A slow short drag rolls back; an immediate subsequent long drag must still work.
for (let i = 0; i < 3; i++) {
  assert.equal(drag.begin(800, -10, origin()), true);
  assert.equal(drag.state.frameX, 294, 'expansion starts at mini bar, not screen bottom');
  assert.equal(drag.state.frameY, 720);
  assert.equal(drag.state.frameWidth, 56);
  assert.equal(drag.state.radius, 28);
  assert.equal(drag.state.coverX, 297);
  const short = proxy();
  drag.attach(short);
  drag.end(-40, -80);
  drag.end(-400, -1000);
  assert.equal(short.cancelled, 1, 'cancel only once even after duplicate end events');
  assert.equal(short.finished, 0);
  drag.complete();
  assert.equal(drag.state.active, false);
  assert.equal(drag.begin(800, -10, origin()), true, 'cancelled gesture releases the entry lock');
  const long = proxy();
  drag.attach(long);
  drag.update(-400);
  assert.equal(long.progress.at(-1), 0.5, 'page progress follows the finger');
  drag.end(-400, -100);
  assert.equal(long.finished, 1);
  assert.equal(drag.begin(800, -10, origin()), false, 'settling cannot push a duplicate player');
  drag.complete();
}

// The finger can be released before Navigation finishes creating its proxy.
drag.begin(800, -10, origin());
drag.end(-50, -1200);
const earlyFling = proxy();
drag.attach(earlyFling);
assert.equal(earlyFling.finished, 1, 'fast upward fling survives delayed proxy creation');
assert.equal(earlyFling.progress[0], 50 / 800);
drag.complete();

drag.begin(800, -10, origin());
drag.cancel();
const interrupted = proxy();
drag.attach(interrupted);
assert.equal(interrupted.cancelled, 1, 'cancel-before-proxy restores the route once ready');
drag.complete();

drag.begin(800, -10, origin());
const reverse = proxy();
drag.attach(reverse);
drag.update(-2000);
assert.equal(reverse.progress.at(-1), 1);
drag.update(40);
assert.equal(reverse.progress.at(-1), 0);
drag.end(-300, 1000);
assert.equal(reverse.cancelled, 1, 'downward release returns to mini player');
drag.complete();
assert.equal(drag.state.sourceOpacity, 1, 'cancel restores original mini bar');
assert.equal(drag.state.contentOpacity, 1);
drag.begin(800, -10, origin());
drag.expandToPlayer({ leftPx: 24, topPx: 110, widthPx: 318, heightPx: 318 },
  { leftPx: 0, topPx: 40, widthPx: 366, heightPx: 800 });
assert.equal(drag.state.frameX, 0);
assert.equal(drag.state.frameY, 0);
assert.equal(drag.state.frameWidth, 366);
assert.equal(drag.state.frameHeight, 800);
assert.equal(drag.state.coverX, 24);
assert.equal(drag.state.coverY, 70, 'cover destination uses the same window coordinate origin');
drag.complete();
console.log('PASS: follow-finger progress, cancel/reopen, fling, reversal and delayed native proxy');
