// Run the paginator's pure Hypium cases with the installed SDK transpiler.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src');
function load(relative, mocks = {}) {
  const filename = path.join(root, relative);
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (!(name in mocks)) throw new Error(`Unexpected dependency: ${name}`);
    return mocks[name];
  } }, { filename });
  return exports;
}
const paginator = load('main/ets/service/text/OnlineTextPaginator.ets', { '@kit.ArkGraphics2D': {} });
let passed = 0;
load('test/OnlineTextPaginator.test.ets', {
  '../main/ets/service/text/OnlineTextPaginator': paginator,
  '@ohos/hypium': {
    describe: (_name, fn) => fn(),
    it: (name, _level, fn) => { fn(); passed++; console.log(`PASS ${name}`); },
    expect: value => ({
      assertEqual: expected => assert.equal(value, expected),
      assertContain: expected => assert.ok(value.includes(expected)),
      assertTrue: () => assert.equal(value, true),
      assertFalse: () => assert.equal(value, false)
    })
  }
}).default();
const { SpeechTextHighlighter } = load('main/ets/service/text/SpeechTextHighlighter.ets');
const source = '甲乙\n\n\u3000\u00A0\n丙丁';
const displayed = paginator.OnlineTextIndentedContent.fromNormalized(source);
const range = SpeechTextHighlighter.displayRange(displayed.text, source, source.indexOf('丙'), source.length);
assert.equal(displayed.text.substring(range.start, range.end), '丙丁');
console.log(`PASS ${passed} paginator cases and speech highlighting across collapsed blank paragraphs`);

// The graphics engine owns wrapping/justification. Rendering must keep its complete paragraph,
// even when a page ends in the middle of a paragraph or continuous mode shows a single line.
const built = [];
const graphicsText = {
  TextAlign: { LEFT: 0, RIGHT: 1, CENTER: 2, JUSTIFY: 3 },
  WordBreak: { BREAK_WORD: 0 }, BreakStrategy: { GREEDY: 0 },
  FontCollection: { getGlobalInstance: () => ({}) },
  ParagraphBuilder: class {
    constructor(style) { this.style = style; }
    pushStyle() {}
    addText(text) { this.text = text; }
    popStyle() {}
    build() {
      const paragraph = { text: this.text, style: this.style, layoutSync(width) { this.width = width; },
        getLineMetrics: () => [
          { startIndex: 0, height: 20, baseline: 15, ascent: 15, descent: 5 },
          { startIndex: 4, height: 20, baseline: 35, ascent: 15, descent: 5 },
          { startIndex: 8, height: 20, baseline: 55, ascent: 15, descent: 5 }
        ] };
      built.push(paragraph);
      return paragraph;
    }
  }
};
const native = load('main/ets/service/text/OnlineTextPaginator.ets', { '@kit.ArkGraphics2D': { text: graphicsText } });
for (const [alignment, expected] of [['justify', 3], ['start', 0], ['center', 2], ['end', 1]]) {
  const pages = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9, '', 400, alignment);
  assert.equal(pages.length, 3);
  const paragraph = built.at(-1);
  assert.equal(paragraph.style.align, expected);
  assert.equal(paragraph.text, '\u3000\u3000甲乙丙丁戊己庚辛壬癸');
  pages.forEach((page, index) => {
    assert.equal(page.paragraph, paragraph, 'all slices retain original paragraph geometry');
    assert.equal(page.layoutTop, index * 20);
    assert.equal(page.layoutHeight, 20);
    assert.equal(page.displayStart, index * 4);
  });
  assert.equal(pages[1].startOffset, 2, 'saved positions exclude display indentation');
  assert.equal(pages[2].endOffset, 10);
}
console.log('PASS four alignments retain complete paragraph layout for page and scroll slices');

const paletteModule = load('main/ets/model/ReaderTheme.ets');
const highlighter = load('main/ets/service/text/SpeechTextHighlighter.ets');
let paintedColor;
const paints = [];
const ranges = [];
const page = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9)[1];
page.paragraph.updateColor = color => { paintedColor = color; };
page.paragraph.getTextLines = () => [0, 1, 2].map(index => ({
  paint: (_canvas, x, y) => paints.push({ index, x, y, color: paintedColor })
}));
page.paragraph.getRectsForRange = range => {
  ranges.push(range);
  return [{ rect: { left: 0, right: 100, top: 20, bottom: 40 } }];
};
graphicsText.RectWidthStyle = { TIGHT: 0 };
graphicsText.RectHeightStyle = { TIGHT: 0 };
let frameInvalidations = 0;
const nodeModule = load('main/ets/service/text/ReaderParagraphNode.ets', {
  '@kit.ArkGraphics2D': { text: graphicsText, drawing: {
    ClipOp: { INTERSECT: 0 }, Brush: class { setColor() {} }
  } },
  '@ohos.arkui.node': { FrameNode: class { invalidate() { frameInvalidations++; } getRenderNode() { return { invalidate() {} }; } }, NodeController: class {} },
  './OnlineTextPaginator': native,
  './SpeechTextHighlighter': highlighter,
  '../../model/ReaderTheme': paletteModule
});
const controller = new nodeModule.ReaderParagraphNodeController();
const nativeRange = new highlighter.SpeechHighlightRange();
nativeRange.start = 0; nativeRange.end = 2;
const palette = paletteModule.ReaderPalette.of('#FFFFFF', '#112233', '#555555', false);
controller.update(page, nativeRange, palette);
const node = controller.makeNode({});
const clips = [];
node.onDraw({ canvas: {
  save() {}, restore() {}, clipRect(rect) { clips.push(rect); },
  attachBrush() {}, detachBrush() {}, drawRect() {}
} });
assert.equal(paints.length, 2, 'base paragraph and inverted speech highlight are painted');
assert.equal(paints[0].index, 1, 'scroll row paints only its own line, not the complete chapter');
assert.equal(paints[1].index, 1, 'highlight redraws only that same line');
assert.equal(paints[0].x, 0, 'native lines already retain horizontal alignment');
assert.equal(paints[0].y, -page.layoutTop, 'native line coordinates remain relative to the original paragraph');
assert.equal(clips[0].bottom, 20, 'only the current row is visible');
assert.equal(ranges[0].start, page.displayStart, 'highlight uses full paragraph display coordinates');
assert.equal(paints[1].color.red, 255);
assert.equal(paintedColor.red, 17, 'shared paragraph color is restored before another row paints');
const nextPage = native.OnlineTextPaginator.paginate('甲乙丙丁戊己庚辛壬癸', 100, 20, 18, 1.9)[2];
const invalidationsBeforeTurn = frameInvalidations;
controller.update(nextPage, new highlighter.SpeechHighlightRange(), palette);
assert.equal(frameInvalidations, invalidationsBeforeTurn + 1, 'page turn schedules FrameNode.onDraw on the mounted node');
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[0].index, 2, 'the same mounted node now paints the next page');
controller.update(page, new highlighter.SpeechHighlightRange(), palette);
paints.length = 0;
node.onDraw({ canvas: { save() {}, restore() {}, clipRect() {} } });
assert.equal(paints[0].index, 1, 'previous page / canceled preview redraws the original page');
console.log('PASS native paragraph clipping and speech highlight preserve measured geometry');

const cacheText = '缓存复用验证甲乙丙丁戊己庚辛壬癸';
const beforeBuilds = built.length;
const cachedPages = native.OnlineTextPaginator.paginate(cacheText, 120, 20, 18, 1.9);
for (let height = 1; height <= 40; height++) {
  const resized = native.OnlineTextPaginator.paginate(cacheText, 120, height, 18, 1.9);
  assert.equal(resized[0].paragraph, cachedPages[0].paragraph);
  assert.equal(resized[0].layoutKey, cachedPages[0].layoutKey);
}
assert.equal(built.length, beforeBuilds + 1, 'page/scroll/height changes share one native measurement');
const wider = native.OnlineTextPaginator.paginate(cacheText, 150, 20, 18, 1.9);
assert.notEqual(wider[0].paragraph, cachedPages[0].paragraph);
assert.equal(built.length, beforeBuilds + 2);
native.OnlineTextPaginator.invalidateLayouts();
native.OnlineTextPaginator.paginate(cacheText, 120, 20, 18, 1.9);
assert.equal(built.length, beforeBuilds + 3, 'system font changes discard old native layouts');
const existingNode = controller.node;
controller.update(cachedPages[0], new highlighter.SpeechHighlightRange(), palette);
assert.equal(controller.node, existingNode, 'reflow updates the mounted node without rebuilding it');
console.log('PASS one measurement across 40 viewport changes, cache invalidation and native node reuse');
