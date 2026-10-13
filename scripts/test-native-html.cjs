// Execute the actual ArkTS source using the installed Release SDK compiler.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const filename = path.resolve(__dirname, '../entry/src/main/ets/service/rulesource/native/NativeHtmlParser.ets');
const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  fileName: 'NativeHtmlParser.ts', compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
});
const moduleResult = { exports: {} };
vm.runInNewContext(output.outputText, { exports: moduleResult.exports, Map, Set, Error }, { filename });
const { NativeHtmlParser: Parser } = moduleResult.exports;
const doc = Parser.parse(`<!doctype html><META name=keywords content="花颜策,有声书">
<ul class="qm-pic-txt"><li><div class=pic><a href='/album/1-20.html'><img src="/cover.jpg?x=1&amp;y=2"></a></div>
<h3 class=s-tit>花颜<span>策</span>&nbsp;&#128214;</h3><p class=s-txt>主播：小王<p class=s-txt>作者：西子情
<p class=s-tags>言情<p class=s-des>介绍 &lt;b&gt;片段&lt;/b&gt;</ul>
<div id=book_intro><dl><dd>第一段<br>第二段<script>window.fake='<a href="evil">坏</a>';</script><style>.x{}</style></dl></div>
<div class=sub-cols><span>分类</span><span>类别：言情</span><span>更新：今天</span></div>
<ul id=playlist><li><a href='/play/1-20-0.html'>第一集</a><li><a href='/play/1-20-1.html'>第二集</a></ul>`);
const list = doc.select('.qm-pic-txt li');
assert.equal(list.length, 1);
assert.equal(doc.select('.s-tit', list[0])[0].text(), '花颜策\u00a0📖');
assert.equal(doc.select('.s-txt', list[0])[0].text(), '主播：小王');
assert.equal(doc.select('.s-tags', list[0])[0].text(), '言情');
assert.equal(doc.select('.pic a', list[0])[0].attribute('HREF'), '/album/1-20.html');
assert.equal(doc.select('.pic img', list[0])[0].attribute('src'), '/cover.jpg?x=1&y=2');
assert.equal(doc.select('meta[name=keywords]')[0].attribute('content'), '花颜策,有声书');
assert.equal(doc.select('#book_intro dd')[0].text(), '第一段第二段');
assert.equal(doc.select('.sub-cols span')[1].text(), '类别：言情');
assert.equal(doc.select('#playlist > li > a').map(n => n.text()).join('|'), '第一集|第二集');
assert.equal(doc.select('#playlist a, a[href="/play/1-20-0.html"]').length, 2);
assert.equal(doc.select('img[src]')[0].innerHtml(), '');
assert.equal(doc.select('.s-tit')[0].innerHtml(), '花颜<span>策</span>&nbsp;&#128214;');
assert.equal(doc.select('#book_intro a').length, 0);
assert.equal(doc.select('.qm-pic-txt', list[0]).length, 0);
assert.equal(Parser.parse('<div data-x="a,b > c"><b>x</b></div>').select('[data-x="a,b > c"] > b')[0].text(), 'x');
assert.equal(Parser.parse('<textarea>&lt;a&gt;one</textarea><title>x &amp; y</title>').select('textarea')[0].text(), '<a>one');
assert.equal(Parser.parse('<p>one<div>two</div>').select('p')[0].text(), 'one');
assert.equal(Parser.parse('<ul><li>outer<ul><li>inner</li></ul><li>second</ul>').select('ul > li').length, 3);
assert.equal(Parser.parse('<div>A<!-- fake --><br>B<img>C</div>').select('div')[0].text(), 'ABC');
assert.equal(Parser.parse('<div>A < 2 and &bogus; &amp; B</div>').select('div')[0].text(), 'A < 2 and &bogus; & B');
assert.equal(Parser.parse('<div><script>bad</scripted>still bad</SCRIPT>ok</div>').select('div')[0].text(), 'ok');
assert.equal(Parser.parse('<script>abc</ScRiPt/><p>x</p>').select('p')[0].text(), 'x');
assert.equal(Parser.parse('İ<script>bad</script><p>ok</p>').select('p')[0].text(), 'ok');
assert.equal(Parser.parse('<table><tr><td>one<tr><td>two</table>').select('table > tr').length, 2);
assert.equal(Parser.decodeEntities('&#x1f600; &#0; &#xD800; &#1114112; &#wat;'), '😀 � � � &#wat;');
// A farther matching ancestor must remain available if the nearest candidate fails.
assert.equal(Parser.parse('<a><b><i><b><c></c></b></i></b></a>').select('a > b c').length, 1);
for (const selector of ['', 'a:first-child', 'a + b', 'a ~ b', '[x^=a]', 'a,', '>a', 'a >', 'a,,b', '.x\\:y', 'a > > b']) {
  assert.throws(() => doc.select(selector), /CSS/);
}
assert.throws(() => Parser.parse('x'.repeat(4 * 1024 * 1024 + 1)), /预算/);
assert.throws(() => Parser.parse('<div>'.repeat(257)), /嵌套/);
assert.throws(() => Parser.parse('<br>'.repeat(50001)), /节点/);
assert.throws(() => Parser.parse(`<div ${Array.from({ length: 129 }, (_, i) => `x${i}=a`).join(' ')}>`), /属性/);
assert.throws(() => doc.select('div '.repeat(17)), /16 层/);

// Explicit native protocol fixture; offsets are UTF-16, including astral and Turkish characters.
const pieces = [
  { raw: 'İ📖', type: 'text' },
  { raw: '<div id="native">', type: 'open', name: 'div', attributes: [{ name: 'id', value: 'native' }] },
  { raw: '<!--native skips comments-->' },
  { raw: '<p class="s-tit">', type: 'open', name: 'p', attributes: [{ name: 'class', value: 's-tit' }] },
  { raw: '章节&amp;📖', type: 'text' },
  { raw: '<p>', type: 'open', name: 'p' },
  { raw: '<a href="/play?x=1&amp;y=2">', type: 'open', name: 'a', attributes: [{ name: 'href', value: '/play?x=1&amp;y=2' }] },
  { raw: '第一集', type: 'text' },
  { raw: '</a>', type: 'close', name: 'a' },
  { raw: '<img src="a.jpg">', type: 'open', name: 'img', attributes: [{ name: 'src', value: 'a.jpg' }] },
  { raw: '<script>', type: 'open', name: 'script' },
  { raw: '<a>evil</a>', type: 'text' },
  { raw: '</script>', type: 'close', name: 'script' },
  { raw: '</div>', type: 'close', name: 'div' },
  { raw: '<textarea>', type: 'open', name: 'textarea' },
  { raw: '<b>&lt;x&gt;</b>', type: 'text' },
  { raw: '</textarea>', type: 'close', name: 'textarea' }
];
let tokenHtml = '';
const tokens = [];
for (const piece of pieces) {
  const start = tokenHtml.length;
  tokenHtml += piece.raw;
  if (!piece.type) continue;
  const token = { type: piece.type, start, end: tokenHtml.length };
  if (piece.type === 'text') token.text = piece.raw;
  else token.name = piece.name;
  if (piece.type === 'open') {
    token.attributes = piece.attributes || [];
    token.selfClosing = false;
  }
  tokens.push(token);
}
const nativeDoc = Parser.parseTokens(tokenHtml, JSON.stringify({ tokens, error: '' }));
const fallbackDoc = Parser.parse(tokenHtml);
for (const selector of ['#native', 'p', '.s-tit', 'p > a', 'img[src]', 'textarea']) {
  const nativeNodes = nativeDoc.select(selector);
  const fallbackNodes = fallbackDoc.select(selector);
  assert.equal(nativeNodes.length, fallbackNodes.length);
  nativeNodes.forEach((node, index) => {
    assert.equal(node.text(), fallbackNodes[index].text());
    assert.equal(node.innerHtml(), fallbackNodes[index].innerHtml());
    assert.equal(node.attribute('href'), fallbackNodes[index].attribute('href'));
  });
}
assert.equal(nativeDoc.select('a')[0].attribute('href'), '/play?x=1&y=2');
assert.equal(nativeDoc.select('textarea')[0].text(), '<b><x></b>');
for (const bad of [null, [], { tokens: null, error: '' }, { tokens: [null], error: '' },
  { tokens: [{ type: 'text', start: 0, end: 3, text: 'wrong' }], error: '' },
  { tokens: [{ type: 'text', start: -1, end: 3, text: 'İ📖' }], error: '' },
  { tokens: [{ type: 'text', start: 0, end: 7, text: 'İ📖' }], error: '' },
  { tokens: [], error: 'native budget exceeded' }]) {
  assert.throws(() => Parser.parseTokens(tokenHtml, JSON.stringify(bad)), /HTML/);
}
console.log('native HTML: sample selectors, malformed input, inert scripts, entities, budgets and native-token parity passed');
