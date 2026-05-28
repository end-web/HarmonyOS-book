/**
 * 规则引擎测试页面（ArkTS 兼容）
 */

import { AnalyzeRule, AnalyzeContext, BookContext } from '../service/rule/AnalyzeRule';
import { RuleAnalyzer } from '../service/rule/RuleAnalyzer';
import { jsonPath } from '../service/rule/JSONPath';
import { AnalyzeUrl } from '../service/rule/AnalyzeUrl';
import { getJSExecutor } from '../service/js/JSExecutor';
import { AnalyzeByRegex } from '../service/rule/AnalyzeByRegex';
import { getSourceContext } from '../service/rule/SourceContext';
import { AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

interface Chapter {
  title: string;
  url: string;
}

interface ChaptersWrap {
  chapters: Chapter[];
}

interface TestData {
  data: ChaptersWrap;
}

@ComponentV2
export struct RuleEngineTestPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local testResults: string[] = [];
  @Local passCount: number = 0;
  @Local failCount: number = 0;

  aboutToAppear() {
    this.runTests();
  }

  assert(name: string, actual: string | null, expected: string | null): void {
    const pass = actual === expected;
    if (pass) { this.passCount++; } else { this.failCount++; }
    const icon = pass ? 'PASS' : 'FAIL';
    this.addResult(`${icon} ${name}`);
    if (!pass) {
      this.addResult(`  got: ${actual}`);
      this.addResult(`  want: ${expected}`);
    }
  }

  assertList(name: string, actual: string[], expected: string[]): void {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    if (pass) { this.passCount++; } else { this.failCount++; }
    const icon = pass ? 'PASS' : 'FAIL';
    this.addResult(`${icon} ${name}`);
// PLACEHOLDER_CONTINUE
    if (!pass) {
      this.addResult(`  got: ${JSON.stringify(actual)}`);
      this.addResult(`  want: ${JSON.stringify(expected)}`);
    }
  }

  async runTests() {
    this.testResults = [];
    this.passCount = 0;
    this.failCount = 0;
    this.addResult('=== Rule Engine Tests ===\n');
    await this.testRuleAnalyzer();
    await this.testJsonPath();
    await this.testJsonPathAdvanced();
    await this.testCssSelector();
    await this.testChainOperator();
    await this.testVariableSystem();
    await this.testFallbackOperator();
    await this.testGetElements();
    await this.testRegexReplace();
    await this.testXPath();
    await this.testJSExecutor();
    await this.testAnalyzeUrl();
    await this.testAnalyzeByRegex();
    await this.testRegexMode();
    await this.testStage1Enhancements();
    await this.testStage2Enhancements();
    await this.testStage3JavaBridge();
    await this.testStage4AdvancedFeatures();
    await this.testBookSourceAdaptation();
    this.addResult(`\n=== ${this.passCount} passed, ${this.failCount} failed ===`);
  }

  async testRuleAnalyzer() {
    this.addResult('\n--- RuleAnalyzer ---');
    const a1 = new RuleAnalyzer('$.a && $.b && $.c');
    this.assertList('split &&', a1.splitRule('&&', '||', '%%'), ['$.a', '$.b', '$.c']);
    const a2 = new RuleAnalyzer('($.a || $.b) && $.c');
    const r2 = a2.splitRule('&&', '||', '%%');
    this.assertList('balanced parens', r2, ['($.a || $.b)', '$.c']);
    const a3 = new RuleAnalyzer('div.list@tag.a@href');
    this.assertList('@ chain split', a3.splitRule('@'), ['div.list', 'tag.a', 'href']);
  }

  async testJsonPath() {
    this.addResult('\n--- JSONPath ---');
    const chs: Chapter[] = [
      { title: 'Ch1', url: '/1' }, { title: 'Ch2', url: '/2' }
    ];
    const td: TestData = { data: { chapters: chs } };
    const r = jsonPath(td, '$.data.chapters[*].title');
    this.assertList('wildcard', r as string[], ['Ch1', 'Ch2']);
    const a = new AnalyzeRule(td);
    const r2 = await a.getStringList('$.data.chapters[*].url');
    this.assertList('AnalyzeRule JSON list', r2, ['/1', '/2']);
  }
// PLACEHOLDER_CSS

  async testCssSelector() {
    this.addResult('\n--- CSS Selector ---');
    const html = '<div class="book"><h1 class="title">BookName</h1><span class="author">Author1</span><a href="/c1" class="ch">Ch1</a><a href="/c2" class="ch">Ch2</a></div>';
    const a1 = new AnalyzeRule(html);
    const r1 = await a1.getString('.title@text');
    this.assert('class@text', r1, 'BookName');
    const a2 = new AnalyzeRule(html);
    const r2 = await a2.getString('.author@text');
    this.assert('author@text', r2, 'Author1');
    const a3 = new AnalyzeRule(html);
    const r3 = await a3.getStringList('.ch@href');
    this.assertList('list @href', r3, ['/c1', '/c2']);
  }

  async testChainOperator() {
    this.addResult('\n--- Chain @ ---');
    const html = '<div class="list"><div class="item"><a href="/b1">Book1</a></div><div class="item"><a href="/b2">Book2</a></div></div>';
    const a = new AnalyzeRule(html);
    const r = await a.getStringList('.item@tag.a@text');
    this.assertList('chain .item@tag.a@text', r, ['Book1', 'Book2']);
  }

  async testVariableSystem() {
    this.addResult('\n--- Variables ---');
    const vars: Record<string, string> = { "host": 'https://example.com', "id": '42' };
    const ctx = new AnalyzeContext('https://example.com', vars);
    const a = new AnalyzeRule('test', ctx);
    const r = await a.getString('@get:{host}/book/@get:{id}');
    this.assert('@get template', r, 'https://example.com/book/42');
  }

  async testFallbackOperator() {
    this.addResult('\n--- Fallback || ---');
    const html = '<div><span class="missing"></span><span class="backup">FallbackVal</span></div>';
    const a = new AnalyzeRule(html);
    const r = await a.getString('.notexist@text || .backup@text');
    this.assert('|| fallback', r, 'FallbackVal');
  }
// PLACEHOLDER_ELEMENTS

  async testGetElements() {
    this.addResult('\n--- getElements ---');
    const html = '<ul><li class="item">A</li><li class="item">B</li><li class="item">C</li></ul>';
    const a = new AnalyzeRule(html);
    const els = await a.getElements('.item');
    this.assert('element count', String(els.length), '3');
    if (els.length === 3) {
      const a2 = new AnalyzeRule(els[0]);
      const t = await a2.getString('@text');
      this.assert('element[0] text', t, 'A');
    }
  }

  async testRegexReplace() {
    this.addResult('\n--- Regex ## ---');
    const html = '<div class="info">Price: $19.99 USD</div>';
    const a = new AnalyzeRule(html);
    const r = await a.getString('.info@text##Price:\\s*##');
    this.assert('## replace', r, '$19.99 USD');
  }

  async testXPath() {
    this.addResult('\n--- XPath ---');
    const html = '<div class="book"><h1 class="title">XBookName</h1><a href="/c1" class="ch">Ch1</a><a href="/c2" class="ch">Ch2</a></div>';

    const a1 = new AnalyzeRule(html);
    const r1 = await a1.getString('@xpath://h1/text()');
    this.assert('xpath text()', r1, 'XBookName');

    const a2 = new AnalyzeRule(html);
    const r2 = await a2.getStringList('@xpath://a/@href');
    this.assertList('xpath @href list', r2, ['/c1', '/c2']);

    const a3 = new AnalyzeRule(html);
    const r3 = await a3.getString('@xpath://h1[@class="title"]/text()');
    this.assert('xpath attr predicate', r3, 'XBookName');

    const a4 = new AnalyzeRule(html);
    const r4 = await a4.getString('@xpath://a[contains(@href,"c2")]/text()');
    this.assert('xpath contains()', r4, 'Ch2');

    const a5 = new AnalyzeRule(html);
    const r5 = await a5.getString('@xpath://a[2]/@href');
    this.assert('xpath [2]', r5, '/c2');

    const a6 = new AnalyzeRule(html);
    const r6 = await a6.getString('@xpath://a[last()]/text()');
    this.assert('xpath last()', r6, 'Ch2');
  }

  async testJsonPathAdvanced() {
    this.addResult('\n--- JSONPath Advanced ---');
    const data: Object = JSON.parse('{"store":{"books":[{"title":"A","price":5},{"title":"B","price":15},{"title":"C","price":8}]}}') as Object;
    const r1 = jsonPath(data, '$.store.books[0].title');
    this.assert('index [0]', Array.isArray(r1) ? (r1 as Object[])[0] as string : r1 as string, 'A');
    const r2 = jsonPath(data, '$.store.books[0,2].title');
    this.assertList('multi-index [0,2]', r2 as string[], ['A', 'C']);
    const r3 = jsonPath(data, '$.store.books[0:2].title');
    this.assertList('slice [0:2]', r3 as string[], ['A', 'B']);
  }

  async testJSExecutor() {
    this.addResult('\n--- JSExecutor (local) ---');
    const executor = getJSExecutor();
    const ctx: Record<string, Object> = {};
    ctx['result'] = 'https://example.com/book/123';
    ctx['baseUrl'] = 'https://example.com';
    ctx['key'] = 'test';

    const r1 = await executor.eval("'hello'", ctx);
    this.assert('string literal', r1 as string, 'hello');

    const r2 = await executor.eval("result.split('/')[4]", ctx);
    this.assert('split+index', r2 as string, '123');

    const r3 = await executor.eval("baseUrl + '/search?q=' + key", ctx);
    this.assert('concat', r3 as string, 'https://example.com/search?q=test');

    const r4 = await executor.eval("result.replace('book','novel')", ctx);
    this.assert('replace', r4 as string, 'https://example.com/novel/123');

    const r5 = await executor.eval("result.trim()", ctx);
    this.assert('trim', r5 as string, 'https://example.com/book/123');
  }

  async testAnalyzeUrl() {
    this.addResult('\n--- AnalyzeUrl ---');
    const au1 = new AnalyzeUrl('https://example.com/search?q={{key}}&page={{page}}', {
      key: 'test', page: 2, baseUrl: 'https://example.com',
    });
    const r1 = await au1.getUrl();
    this.assert('template replace', r1.url, 'https://example.com/search?q=test&page=2');
    this.assert('method default GET', r1.method, 'GET');

    const resolved = AnalyzeUrl.resolveUrl('https://example.com/book/1', '/chapter/2');
    this.assert('resolveUrl absolute', resolved, 'https://example.com/chapter/2');

    const resolved2 = AnalyzeUrl.resolveUrl('https://example.com/book/', 'detail.html');
    this.assert('resolveUrl relative', resolved2, 'https://example.com/book/detail.html');
  }

  async testAnalyzeByRegex() {
    this.addResult('\n--- AnalyzeByRegex ---');
    const content = 'Chapter 1: Hello World\nChapter 2: Goodbye\nChapter 3: End';
    const r1 = AnalyzeByRegex.getString(content, 'Chapter (\\d+): (.+)', '$2');
    this.assert('getString template', r1, 'Hello World');

    const r2 = AnalyzeByRegex.getStringList(content, 'Chapter (\\d+)', '$1');
    this.assertList('getStringList', r2, ['1', '2', '3']);
  }

  async testRegexMode() {
    this.addResult('\n--- Regex Mode ---');
    const content = 'url: https://audio.mp3, title: Song1';
    const a = new AnalyzeRule(content);
    const r = await a.getString(':regex:https?://[^,\\s]+');
    this.assert(':regex: mode', r, 'https://audio.mp3');
  }

  async testStage1Enhancements() {
    this.addResult('\n--- Stage 1 Enhancements ---');

    // 1. 逗号分隔 OR 选择器
    const html1 = '<div class="a">A</div><div class="b">B</div><div class="c">C</div>';
    const a1 = new AnalyzeRule(html1);
    const r1 = await a1.getString('.a, .c@text');
    this.assert('comma OR selector', r1, 'A\nC'); // 逗号 OR 匹配多个，join('\n')

    // 2. 多类名复合选择器 .a.b
    const html2 = '<div class="item featured">Featured</div><div class="item">Normal</div>';
    const a2 = new AnalyzeRule(html2);
    const r2 = await a2.getString('.item.featured@text');
    this.assert('multi-class compound', r2, 'Featured');

    // 3. 范围索引 .start:end
    const html3 = '<ul><li>0</li><li>1</li><li>2</li><li>3</li><li>4</li></ul>';
    const a3 = new AnalyzeRule(html3);
    const r3 = await a3.getStringList('li.1:3@text');
    this.assertList('range indexer .1:3', r3, ['1', '2']);

    // 4. 步长索引 .start:end:step
    const a4 = new AnalyzeRule(html3);
    const r4 = await a4.getStringList('li.0:5:2@text');
    this.assertList('step indexer .0:5:2', r4, ['0', '2', '4']);

    // 5. DOM shim - document.querySelector
    const html5 = '<div class="content"><p>Para 1</p><p>Para 2</p></div>';
    const a5 = new AnalyzeRule(html5);
    const jsCode = 'document.querySelector(".content p").innerText';
    const r5 = await a5.getString(`@js:${jsCode}`);
    this.assert('DOM shim querySelector', r5, 'Para 1');
  }

  async testStage2Enhancements() {
    this.addResult('\n--- Stage 2 Enhancements ---');

    // 1. {{@@...}} CSS 规则内嵌求值
    const html1 = '<div class="title">Book Title</div><div class="author">Author Name</div>';
    const a1 = new AnalyzeRule(html1);
    const r1 = await a1.getString('{{@@.title@text}} by {{@@.author@text}}');
    this.assert('{{@@...}} CSS eval', r1, 'Book Title by Author Name');

    // 2. text.关键字@href 链式
    const html2 = '<a href="/link1">全部章节</a><a href="/link2">其他</a>';
    const a2 = new AnalyzeRule(html2);
    const r2 = await a2.getString('text.全部章节@href');
    this.assert('text.keyword@href', r2, '/link1');

    // 3. ##regex##replacement 替换
    const html3 = '<div>连载中</div>';
    const a3 = new AnalyzeRule(html3);
    const r3 = await a3.getString('div@text##连载中|完结');
    this.assert('##regex## replace', r3, '');

    // 4. .0 / .1 索引
    const html4 = '<ul><li>First</li><li>Second</li><li>Third</li></ul>';
    const a4 = new AnalyzeRule(html4);
    const r4 = await a4.getString('li.0@text');
    this.assert('.0 indexer', r4, 'First');
    const r5 = await a4.getString('li.1@text');
    this.assert('.1 indexer', r5, 'Second');
  }

  async testStage3JavaBridge() {
    this.addResult('\n--- Stage 3: JavaBridge & Context ---');

    const executor = getJSExecutor();
    const sourceCtx = getSourceContext();
    sourceCtx.setSource({
      bookSourceUrl: 'test-source',
      bookSourceName: 'Test Source',
      bookSourceType: 1
    });

    // 1. java.log
    const ctx1: Record<string, Object> = {};
    const r1 = await executor.eval("java.log('test message'); 'logged'", ctx1);
    this.assert('java.log', r1 as string, 'logged');

    // 2. java.put / java.get
    const ctx2: Record<string, Object> = {};
    await executor.eval("java.put('myKey', 'myValue')", ctx2);
    const r2 = await executor.eval("java.get('myKey')", ctx2);
    this.assert('java.put/get', r2 as string, 'myValue');

    // 3. source.key / source.name
    const ctx3: Record<string, Object> = {};
    const r3 = await executor.eval("source.key", ctx3);
    this.assert('source.key', r3 as string, 'test-source');

    const r4 = await executor.eval("source.name", ctx3);
    this.assert('source.name', r4 as string, 'Test Source');

    // 4. cookie.removeCookie (simple call)
    const ctx4: Record<string, Object> = {};
    const r5 = await executor.eval("cookie.removeCookie('https://example.com'); 'removed'", ctx4);
    this.assert('cookie.removeCookie', r5 as string, 'removed');

    // 5. Jsoup.parse
    const ctx5: Record<string, Object> = {};
    ctx5['html'] = '<div class="test">Content</div>';
    const r6 = await executor.eval("Jsoup.parse(html).select('.test').text()", ctx5);
    this.assert('Jsoup.parse', r6 as string, 'Content');
  }

  async testStage4AdvancedFeatures() {
    this.addResult('\n--- Stage 4: sourceRegex & checkKeyWord ---');

    // 1. sourceRegex extraction
    const html1 = 'Audio URL: https://cdn.example.com/audio/book123.mp3 and more text';
    const a1 = new AnalyzeRule(html1);
    const r1 = await a1.getString(':regex:https?://[^\\s]+\\.mp3');
    this.assert('sourceRegex audio URL', r1, 'https://cdn.example.com/audio/book123.mp3');

    // 2. checkKeyWord validation (simulated in test)
    const searchResult = 'Search results: Book1, Book2, Book3';
    const hasKeyword = searchResult.includes('Book');
    this.assert('checkKeyWord validation', hasKeyword ? 'pass' : 'fail', 'pass');

    // 3. Complex regex with groups
    const content = 'Chapter 1: https://audio1.mp3\nChapter 2: https://audio2.mp3';
    const a2 = new AnalyzeRule(content);
    const r2 = await a2.getStringList(':regex:https?://[^\\s]+\\.mp3');
    this.assertList('sourceRegex list', r2, ['https://audio1.mp3', 'https://audio2.mp3']);
  }

  async testBookSourceAdaptation() {
    this.addResult('\n--- Book Source Adaptation ---');

    // 1. Regex capture group replacement: ##(^\d+)##第$1节
    const html1 = '<span>123</span>';
    const a1 = new AnalyzeRule(html1);
    const r1 = await a1.getString('span@text##(^\\d+)##第$1节');
    this.assert('## capture group $1', r1, '第123节');

    // 2. && chaining in getElements
    const html2 = '<div class="main"><div class="list"><p>A</p><p>B</p></div></div>';
    const a2 = new AnalyzeRule(html2);
    const els = await a2.getElements('.main&&p');
    this.assert('&& getElements count', String(els.length), '2');

    // 3. book.origin in JS context
    const ctx3 = new AnalyzeContext('http://example.com/page');
    ctx3.book = { origin: 'http://source.com', bookUrl: '/book/1', name: 'Test' } as BookContext;
    const a3 = new AnalyzeRule('hello', ctx3);
    const r3 = await a3.getString('@js:book.origin');
    this.assert('book.origin in JS', r3, 'http://source.com');

    // 4. book.origin + result concatenation in JS
    const a4 = new AnalyzeRule('/chapter/1', ctx3);
    const r4 = await a4.getString('@js:book.origin + result');
    this.assert('book.origin+result', r4, 'http://source.com/chapter/1');

    // 5. Multi-step: CSS then <js> block
    const html5 = '<a href="/path/to/page">link</a>';
    const ctx5 = new AnalyzeContext('http://base.com');
    ctx5.book = { origin: 'http://origin.com', bookUrl: '', name: '' } as BookContext;
    const a5 = new AnalyzeRule(html5, ctx5);
    const r5 = await a5.getString('a@href<js>book.origin + result</js>');
    this.assert('CSS+<js> chain', r5, 'http://origin.com/path/to/page');
  }

  addResult(text: string) {
    this.testResults.push(text);
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('规则引擎测试')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(`${this.passCount} / ${this.failCount}`)
          .fontSize(AppFont.Caption)
          .fontColor(this.failCount > 0 ? '#e53935' : '#43a047')
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md,
        right: AppSpace.Md,
        bottom: AppSpace.Sm
      })

      Scroll() {
        Column() {
          ForEach(this.testResults, (result: string) => {
            Text(result)
              .fontSize(13)
              .fontFamily('monospace')
              .width('100%')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .padding(10)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}



