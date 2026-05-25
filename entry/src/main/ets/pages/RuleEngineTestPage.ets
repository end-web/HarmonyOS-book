/**
 * 规则引擎测试页面（ArkTS 兼容）
 */

import { AnalyzeRule } from '../service/rule/AnalyzeRule';
import { RuleAnalyzer } from '../service/rule/RuleAnalyzer';
import { jsonPath } from '../service/rule/JSONPath';

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

interface TemplateVars extends Record<string, Object> {
  baseUrl: string;
  bookId: string;
}

@Entry
@ComponentV2
struct RuleEngineTestPage {
  @Local testResults: string[] = [];

  aboutToAppear() {
    this.runTests();
  }

  async runTests() {
    this.testResults = [];
    this.addResult('=== 规则引擎测试 ===\n');

    this.addResult('测试 1: RuleAnalyzer 分割');
    const analyzer1 = new RuleAnalyzer('$.a && $.b && $.c');
    const result1 = analyzer1.splitRule('&&');
    this.addResult(`输入: $.a && $.b && $.c`);
    this.addResult(`输出: ${JSON.stringify(result1)}`);
    this.addResult(`期望: ["$.a", "$.b", "$.c"]`);
    this.addResult(JSON.stringify(result1) === JSON.stringify(['$.a', '$.b', '$.c']) ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 2: 括号平衡');
    const analyzer2 = new RuleAnalyzer('($.a || $.b) && $.c');
    const result2 = analyzer2.splitRule('&&', '||');
    this.addResult(`输入: ($.a || $.b) && $.c`);
    this.addResult(`输出: ${JSON.stringify(result2)}`);
    this.addResult(`期望: ["($.a || $.b)", "$.c"]`);
    this.addResult(JSON.stringify(result2) === JSON.stringify(['($.a || $.b)', '$.c']) ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 3: JSONPath 解析');
    const chapters: Chapter[] = [
      { title: '第一章', url: '/chapter/1' },
      { title: '第二章', url: '/chapter/2' },
      { title: '第三章', url: '/chapter/3' },
    ];
    const testData: TestData = { data: { chapters } };
    const result3 = jsonPath(testData, '$.data.chapters[*].title');
    this.addResult(`输入: $.data.chapters[*].title`);
    this.addResult(`输出: ${JSON.stringify(result3)}`);
    this.addResult(`期望: ["第一章", "第二章", "第三章"]`);
    this.addResult(JSON.stringify(result3) === JSON.stringify(['第一章', '第二章', '第三章']) ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 4: AnalyzeRule - JSONPath');
    const analyzer4 = new AnalyzeRule(testData);
    const result4 = await analyzer4.getStringList('$.data.chapters[*].title');
    this.addResult(`输入: $.data.chapters[*].title`);
    this.addResult(`输出: ${JSON.stringify(result4)}`);
    this.addResult(`期望: ["第一章", "第二章", "第三章"]`);
    this.addResult(JSON.stringify(result4) === JSON.stringify(['第一章', '第二章', '第三章']) ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 5: 模板变量替换');
    const vars: TemplateVars = { baseUrl: 'https://example.com', bookId: '123' };
    const analyzer5 = new AnalyzeRule('', { variables: vars });
    const result5 = await analyzer5.getString('{{baseUrl}}/book/{{bookId}}');
    this.addResult(`输入: {{baseUrl}}/book/{{bookId}}`);
    this.addResult(`输出: ${result5}`);
    this.addResult(`期望: https://example.com/book/123`);
    this.addResult(result5 === 'https://example.com/book/123' ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 6: CSS 选择器');
    const htmlContent = `
      <html>
        <body>
          <div class="book">
            <h1 class="title">测试书名</h1>
            <div class="author">作者：张三</div>
            <a href="/chapter/1" class="chapter">第一章</a>
            <a href="/chapter/2" class="chapter">第二章</a>
          </div>
        </body>
      </html>
    `;
    const analyzer6 = new AnalyzeRule(htmlContent);
    const result6 = await analyzer6.getString('.title@text');
    this.addResult(`输入: .title@text`);
    this.addResult(`输出: ${result6}`);
    this.addResult(`期望: 测试书名`);
    this.addResult(result6 === '测试书名' ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('测试 7: CSS 选择器列表');
    const analyzer7 = new AnalyzeRule(htmlContent);
    const result7 = await analyzer7.getStringList('.chapter@href');
    this.addResult(`输入: .chapter@href`);
    this.addResult(`输出: ${JSON.stringify(result7)}`);
    this.addResult(`期望: ["/chapter/1", "/chapter/2"]`);
    this.addResult(JSON.stringify(result7) === JSON.stringify(['/chapter/1', '/chapter/2']) ? '✓ 通过\n' : '✗ 失败\n');

    this.addResult('=== 测试完成 ===');
  }

  addResult(text: string) {
    this.testResults.push(text);
  }

  build() {
    Column() {
      Text('规则引擎测试')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 20 })

      Scroll() {
        Column() {
          ForEach(this.testResults, (result: string) => {
            Text(result)
              .fontSize(14)
              .fontFamily('monospace')
              .width('100%')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#f5f5f5')
      .padding(10)
    }
    .width('100%')
    .height('100%')
  }
}
