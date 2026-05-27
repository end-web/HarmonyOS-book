/**
 * 规则引擎测试页面（ArkTS 兼容）
 */

import { AnalyzeRule, AnalyzeContext } from '../service/rule/AnalyzeRule';
import { RuleAnalyzer } from '../service/rule/RuleAnalyzer';
import { jsonPath } from '../service/rule/JSONPath';
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
    await this.testCssSelector();
    await this.testChainOperator();
    await this.testVariableSystem();
    await this.testFallbackOperator();
    await this.testGetElements();
    await this.testRegexReplace();
    await this.testXPath();
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



