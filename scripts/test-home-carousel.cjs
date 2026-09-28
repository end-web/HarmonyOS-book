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
carouselInstance.books = Array.from({ length: 6 }, (_, i) => ({ sourceUrl: 'source', bookUrl: String(i) }));
carouselInstance.selectedIndex = 4;
carouselInstance.aboutToAppear();
carouselInstance.indexedMotions.forEach(item => item.setPosition(0));
carouselInstance.restorePortraitMotions();
assert.equal(carouselInstance.selectedIndex, 4, 'rotation preserves the selected book');
for (const [index, expected] of [[3, -1], [4, 0], [5, 1], [0, 1]]) {
  assert.equal(carouselInstance.indexedMotions[index].position, expected, 'restore neighbors around current page');
}
carouselInstance.books = carouselInstance.books.slice(0, 2);
carouselInstance.selectedIndex = 1;
carouselInstance.restorePortraitMotions();
assert.equal(carouselInstance.indexedMotions[0].position, -1, 'two-book mode does not wrap');
carouselInstance.resetSelection();
assert.equal(carouselInstance.selectedIndex, 0, 'source refresh still returns to first book');
console.log('PASS: node rebinding, repeated rotations, current-page perspective, two-book mode and source refresh');
