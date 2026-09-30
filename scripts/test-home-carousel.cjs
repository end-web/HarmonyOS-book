// Exercise the real carousel modifiers without a gesture after node replacement.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const file = path.resolve(__dirname, '../entry/src/main/ets/components/HomeCoverCarousel.ets');
const source = fs.readFileSync(file, 'utf8');
const modifiers = source.slice(0, source.indexOf('@ComponentV2'))
  .replace(/^import .*;\r?\n/gm, '')
  .replace('class HomeCoverLayer', 'export class HomeCoverLayer')
  .replace('class HomeCoverMotion', 'export class HomeCoverMotion');
// Include non-UI component logic to check restoration from a nonzero page.
const carousel = source.slice(source.indexOf('export struct HomeCoverCarousel'), source.indexOf('  @Builder\n') > 0
  ? source.indexOf('  @Builder\n') : source.indexOf('  @Builder\r\n'))
  .replace('export struct HomeCoverCarousel', 'export class HomeCoverCarousel')
  .replace(/@(Param|Local|Event)\s+/g, '')
  .replace(/@Monitor\([^\n]+\)\s*/g, '') + '\n}';
const code = ts.transpileModule(modifiers + carousel, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
class AttributeUpdater {}
class SwiperController { changeIndex() {} }
const exportsObject = {};
vm.runInNewContext(code, {
  exports: exportsObject, AttributeUpdater, SwiperController,
  OneShotTransitionCoordinator: { getInstance: () => ({ coverState: {} }) },
  OneShotTransitionIds: { nextSourceId: prefix => prefix },
  OneShotLayoutCallback: class { constructor(action) { this.onFrame = action; } },
  matrix4: { identity: () => ({ setPolyToPoly: geometry => geometry }) }
});
function node() {
  return {
    geometry: undefined, alpha: undefined, depth: undefined,
    transform3D(value) { this.geometry = value; return this; },
    opacity(value) { this.alpha = value; return this; },
    zIndex(value) { this.depth = value; return this; }
  };
}
const motion = new exportsObject.HomeCoverMotion();
motion.setGeometry(540, 80);
motion.setPosition(-1);
const first = node();
motion.initializeModifier(first);
for (let rotation = 0; rotation < 4; rotation++) {
  const replacement = node();
  motion.onComponentChanged(replacement);
  motion.layer.onComponentChanged(replacement);
  assert.deepEqual(replacement.geometry, first.geometry, 'replacement restores perspective without scrolling');
  assert.equal(replacement.alpha, 0.8);
  assert.equal(replacement.depth, 5, 'side cover stays behind the center');
}
motion.setPosition(0);
const center = node();
motion.onComponentChanged(center);
motion.layer.onComponentChanged(center);
assert.equal(center.alpha, 1);
assert.equal(center.depth, 10);
assert.equal(center.geometry.dst[0].y, 0);

const carouselInstance = new exportsObject.HomeCoverCarousel();
carouselInstance.getUIContext = () => ({ vp2px: value => value * 3 });
carouselInstance.books = Array.from({ length: 6 }, (_, i) => ({
  sourceUrl: 'source', bookUrl: String(i), coverUrl: `https://covers.example/${i}.jpg`
}));
let currentBackground = '';
carouselInstance.onCoverChange = cover => { currentBackground = cover; };
carouselInstance.selectedIndex = 4;
carouselInstance.aboutToAppear();
assert.equal(currentBackground, 'https://covers.example/4.jpg', 'initial background uses the current cover');
carouselInstance.indexedMotions.forEach(item => item.setPosition(0));
carouselInstance.restorePortraitMotions();
assert.equal(carouselInstance.selectedIndex, 4, 'rotation preserves the selected book');
assert.equal(currentBackground, 'https://covers.example/4.jpg', 'rotation preserves the background');
for (const [index, expected] of [[3, -1], [4, 0], [5, 1], [0, 1]]) {
  assert.equal(carouselInstance.indexedMotions[index].position, expected, 'restore neighbors around current page');
}
carouselInstance.books = carouselInstance.books.slice(0, 2);
carouselInstance.selectedIndex = 1;
carouselInstance.restorePortraitMotions();
assert.equal(carouselInstance.indexedMotions[0].position, -1, 'two-book mode does not wrap');
carouselInstance.resetSelection();
assert.equal(carouselInstance.selectedIndex, 0, 'source refresh still returns to first book');
assert.equal(currentBackground, 'https://covers.example/0.jpg', 'refresh synchronizes the first background');
carouselInstance.selectCover(1);
assert.equal(currentBackground, 'https://covers.example/0.jpg', 'scrolling does not start background decode/fade');
carouselInstance.finishCoverMotion();
assert.equal(currentBackground, 'https://covers.example/1.jpg', 'manual or automatic page change updates background');
let pendingFrame;
let opened = false;
carouselInstance.getUIContext = () => ({ vp2px: value => value * 3,
  postFrameCallback: frame => { pendingFrame = frame; } });
carouselInstance.selectCover(0);
carouselInstance.pendingOpen = () => { opened = true; };
carouselInstance.finishCoverMotion();
assert.equal(currentBackground, 'https://covers.example/1.jpg', 'detail entry does not start a competing background decode');
pendingFrame.onFrame();
assert.equal(opened, true, 'side-cover entry still opens after layout');
carouselInstance.resumeCover();
assert.equal(currentBackground, 'https://covers.example/0.jpg', 'returning home catches up to the selected background');
carouselInstance.books = [];
carouselInstance.resetSelection();
assert.equal(currentBackground, '', 'empty source clears the previous background');
console.log('PASS: node rebinding, repeated rotations, current-page perspective, two-book mode and source refresh');

const ratioExports = {};
const ratioSource = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils/CoverAspectRatio.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(ratioSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: ratioExports });
const ratios = ratioExports.CoverAspectRatio;
for (const [url, width, height] of [['square', 600, 600], ['portrait', 600, 900], ['wide', 900, 600]]) {
  ratios.remember(url, width, height);
  const ratio = ratios.get(url);
  const displayWidth = ratios.fittedWidth(ratio, 100, 130);
  const displayHeight = displayWidth / ratio;
  assert.ok(displayWidth <= 100 && displayHeight <= 130);
  assert.ok(Math.abs(displayWidth / displayHeight - width / height) < 1e-9,
    'detail must preserve the complete original aspect ratio');
}
ratios.remember('square', 0, 0);
assert.equal(ratios.get('square'), 1, 'invalid load event does not replace known dimensions');
assert.equal(ratios.get('missing'), 1, 'unloaded cover uses square placeholder');
console.log('PASS: original square, portrait and landscape cover proportions');
