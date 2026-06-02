/**
 * 书源调试页面
 */

import { SourceDebugger, DebugStep } from '../utils/SourceDebugger';
import { SourceDataService } from '../service/SourceDataService';
import { BookSource } from '../model/BookSource';
import { AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct SourceDebugPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local sources: BookSource[] = [];
  @Local selectedSourceIndex: number = 0;
  @Local keyword: string = '斗罗大陆';
  @Local debugOutput: string = '';
  @Local isDebugging: boolean = false;

  aboutToAppear(): void {
    this.loadSources();
  }

  private async loadSources(): Promise<void> {
    try {
      const allSources = await SourceDataService.getSources();
      this.sources = allSources.filter(s => s.enabled !== false);
    } catch (e) {
      this.debugOutput = `加载书源失败: ${e}`;
    }
  }

  private async runDebug(): Promise<void> {
    if (this.sources.length === 0) {
      this.debugOutput = '没有可用的书源';
      return;
    }

    this.isDebugging = true;
    this.debugOutput = '开始调试...\n\n';

    try {
      const source = this.sources[this.selectedSourceIndex];
      this.debugOutput += `书源: ${source.bookSourceName}\n`;
      this.debugOutput += `类型: ${source.bookSourceType === 1 ? '音频' : '文本'}\n`;
      this.debugOutput += `关键词: ${this.keyword}\n\n`;

      const steps = await SourceDebugger.debugSearch(source, this.keyword);
      this.debugOutput += SourceDebugger.formatDebugSteps(steps);

      const successCount = steps.filter(s => s.success).length;
      const totalCount = steps.length;
      this.debugOutput += `\n总结: ${successCount}/${totalCount} 步骤成功`;
    } catch (e) {
      this.debugOutput += `\n调试失败: ${e}`;
    } finally {
      this.isDebugging = false;
    }
  }

  private async testAllSources(): Promise<void> {
    if (this.sources.length === 0) {
      this.debugOutput = '没有可用的书源';
      return;
    }

    this.isDebugging = true;
    this.debugOutput = `测试所有书源 (共 ${this.sources.length} 个)...\n\n`;

    try {
      const results = await SourceDebugger.testAllSources(this.keyword);

      let successCount = 0;
      let failCount = 0;

      results.forEach((steps, sourceName) => {
        const lastStep = steps[steps.length - 1];
        if (lastStep && lastStep.success) {
          successCount++;
          this.debugOutput += `✓ ${sourceName}\n`;
        } else {
          failCount++;
          this.debugOutput += `✗ ${sourceName}: ${lastStep?.error || '未知错误'}\n`;
        }
      });

      this.debugOutput += `\n总结: ${successCount} 成功, ${failCount} 失败`;
    } catch (e) {
      this.debugOutput += `\n测试失败: ${e}`;
    } finally {
      this.isDebugging = false;
    }
  }

  build() {
    Column() {
      // 标题栏
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('书源调试')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary')])
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md,
        right: AppSpace.Md,
        bottom: AppSpace.Sm
      })

      // 控制区
      Column({ space: AppSpace.Sm }) {
        // 书源选择
        Row({ space: AppSpace.Sm }) {
          Text('书源:')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
          Select(this.sources.map(s => ({ value: s.bookSourceName })))
            .selected(this.selectedSourceIndex)
            .value(this.sources[this.selectedSourceIndex]?.bookSourceName || '无')
            .onSelect((index: number) => {
              this.selectedSourceIndex = index;
            })
            .layoutWeight(1)
        }
        .width('100%')

        // 关键词输入
        Row({ space: AppSpace.Sm }) {
          Text('关键词:')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
          TextInput({ text: !!this.keyword, placeholder: '输入搜索关键词' })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.keyword = value;
            })
        }
        .width('100%')

        // 按钮组
        Row({ space: AppSpace.Sm }) {
          Button('调试当前书源')
            .onClick(() => this.runDebug())
            .enabled(!this.isDebugging && this.sources.length > 0)
            .layoutWeight(1)
          Button('测试所有书源')
            .onClick(() => this.testAllSources())
            .enabled(!this.isDebugging && this.sources.length > 0)
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding(AppSpace.Md)
      .backgroundColor($r('sys.color.comp_background_primary'))

      // 输出区
      Scroll() {
        Text(this.debugOutput || '点击按钮开始调试')
          .fontSize(13)
          .fontFamily('monospace')
          .width('100%')
          .padding(AppSpace.Md)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      if (this.isDebugging) {
        Row() {
          LoadingProgress()
            .width(24)
            .height(24)
          Text('调试中...')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ left: AppSpace.Sm })
        }
        .width('100%')
        .padding(AppSpace.Md)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
