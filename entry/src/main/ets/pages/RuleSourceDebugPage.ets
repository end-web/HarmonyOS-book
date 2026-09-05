import { LocalRuleSource } from '../model/LocalRuleSource';
import { BookSourceService } from '../service/BookSourceService';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { promptAction } from '@kit.ArkUI';

interface DebugLog {
  timestamp: number;
  level: 'info' | 'success' | 'warning' | 'error';
  stage: string;
  message: string;
  detail: string;
}

interface DebugResult {
  success: boolean;
  data?: Record<string, Object>;
  error?: string;
  logs: DebugLog[];
}

interface SearchResultPreview {
  name: string;
  author: string;
  bookUrl: string;
  coverUrl: string;
  intro: string;
}

interface DebugReport {
  sourceUrl: string;
  sourceName: string;
  stage: string;
  keyword: string;
  testUrl: string;
  logs: DebugLog[];
  result: DebugResult | null;
  exportedAt: string;
}

interface BookInfoPreview {
  name: string;
  author: string;
  coverUrl: string;
  intro: string;
  tocUrl: string;
}

interface ChapterPreview {
  name: string;
  url: string;
  duration: string;
}

interface ContentPreview {
  content: string;
  audioUrl: string;
}

interface AudioInfoData extends Record<string, Object> {
  audioInfo: object;
}

interface AudioUrlData extends Record<string, Object> {
  audioUrl: string;
}

interface TextContentData extends Record<string, Object> {
  content: string;
}

interface SearchPreviewsData extends Record<string, Object> {
  previews: Object[];
}

@ComponentV2
export struct RuleSourceDebugPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local source: LocalRuleSource | null = null;
  @Local isLoading: boolean = false;
  @Local isRunning: boolean = false;
  @Local currentStage: string = 'search';
  @Local keyword: string = '我的';
  @Local testUrl: string = '';
  @Local debugLogs: DebugLog[] = [];
  @Local debugResult: DebugResult | null = null;
  @Local showExportDialog: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSource();
  }

  private async loadSource(): Promise<void> {
    this.isLoading = true;
    try {
      const loaded = await LocalRuleSourceRepository.findByUrl(this.sourceUrl);
      this.source = loaded || null;
      if (!this.source) {
        promptAction.showToast({ message: '书源不存在' });
        this.navStack.pop();
      }
    } catch (error) {
      promptAction.showToast({ message: '加载书源失败' });
      this.navStack.pop();
    } finally {
      this.isLoading = false;
    }
  }

  private addLog(level: string, stage: string, message: string, detail: string = ''): void {
    const logLevel = level as 'info' | 'success' | 'warning' | 'error';
    this.debugLogs.push({
      timestamp: Date.now(),
      level: logLevel,
      stage,
      message,
      detail
    });
    // 自动滚动到底部
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  private clearLogs(): void {
    this.debugLogs = [];
    this.debugResult = null;
  }

  private async runDebug(): Promise<void> {
    if (!this.source) return;
    if (this.isRunning) return;

    this.clearLogs();
    this.isRunning = true;

    try {
      if (this.currentStage === 'search') {
        await this.debugSearch();
      } else if (this.currentStage === 'detail') {
        await this.debugDetail();
      } else if (this.currentStage === 'toc') {
        await this.debugToc();
      } else if (this.currentStage === 'content') {
        await this.debugContent();
      } else if (this.currentStage === 'full') {
        await this.debugFullChain();
      }
    } catch (error) {
      this.addLog('error', this.currentStage, '调试失败', `${error}`);
    } finally {
      this.isRunning = false;
    }
  }

  private async debugSearch(): Promise<void> {
    this.addLog('info', 'search', '开始搜索调试', `关键词: ${this.keyword}`);

    if (!this.source?.searchUrl) {
      this.addLog('error', 'search', '缺少搜索地址配置');
      return;
    }

    try {
      const results = await BookSourceService.searchBooks(this.source, this.keyword);

      if (results.length > 0) {
        this.addLog('success', 'search', `搜索成功，找到 ${results.length} 本书`);
        const previews: SearchResultPreview[] = results.slice(0, 10).map(r => {
          const preview: SearchResultPreview = {
            name: r.name,
            author: r.author,
            bookUrl: r.bookUrl,
            coverUrl: r.coverUrl,
            intro: r.intro
          };
          return preview;
        });
        const data: SearchPreviewsData = { previews: previews as Object[] };
        this.debugResult = {
          success: true,
          data: data,
          logs: this.debugLogs
        };
      } else {
        this.addLog('warning', 'search', '搜索无结果');
      }
    } catch (error) {
      this.addLog('error', 'search', '搜索失败', `${error}`);
    }
  }

  private async debugDetail(): Promise<void> {
    if (!this.testUrl) {
      this.addLog('error', 'detail', '请输入详情页URL');
      return;
    }

    this.addLog('info', 'detail', '开始详情页调试', `URL: ${this.testUrl}`);

    try {
      // 这里需要使用实际的详情页解析方法
      this.addLog('warning', 'detail', '详情页调试功能开发中');
      this.debugResult = {
        success: false,
        error: '详情页解析功能暂未完全实现',
        logs: this.debugLogs
      };
    } catch (error) {
      this.addLog('error', 'detail', '详情页解析失败', `${error}`);
    }
  }

  private async debugToc(): Promise<void> {
    if (!this.testUrl) {
      this.addLog('error', 'toc', '请输入书籍URL');
      return;
    }

    this.addLog('info', 'toc', '开始目录调试', `URL: ${this.testUrl}`);

    try {
      // 这里需要使用实际的目录解析方法
      this.addLog('warning', 'toc', '目录调试功能开发中');
      this.debugResult = {
        success: false,
        error: '目录解析功能暂未完全实现',
        logs: this.debugLogs
      };
    } catch (error) {
      this.addLog('error', 'toc', '目录解析失败', `${error}`);
    }
  }

  private async debugContent(): Promise<void> {
    if (!this.testUrl) {
      this.addLog('error', 'content', '请输入章节URL');
      return;
    }

    this.addLog('info', 'content', '开始正文/音频调试', `URL: ${this.testUrl}`);

    try {
      if (this.source!.bookSourceType === 1) {
        // 音频
        const audioInfo = await BookSourceService.getAudioUrl(this.source!, this.testUrl, undefined);
        if (audioInfo && typeof audioInfo === 'object') {
          this.addLog('success', 'content', '音频地址解析成功');
          const data: AudioInfoData = { audioInfo: audioInfo };
          this.debugResult = {
            success: true,
            data: data,
            logs: this.debugLogs
          };
        } else if (typeof audioInfo === 'string' && audioInfo.length > 0) {
          this.addLog('success', 'content', '音频地址解析成功');
          const data: AudioUrlData = { audioUrl: audioInfo };
          this.debugResult = {
            success: true,
            data: data,
            logs: this.debugLogs
          };
        } else {
          this.addLog('error', 'content', '音频地址解析失败');
        }
      } else {
        // 正文
        this.addLog('warning', 'content', '正文调试功能开发中');
        const data: TextContentData = { content: '正文解析功能暂未完全实现' };
        this.debugResult = {
          success: false,
          error: '正文解析功能暂未完全实现',
          logs: this.debugLogs
        };
      }
    } catch (error) {
      this.addLog('error', 'content', '解析失败', `${error}`);
    }
  }

  private async debugFullChain(): Promise<void> {
    this.addLog('info', 'full', '开始全链路调试', `关键词: ${this.keyword}`);

    // 1. 搜索
    await this.debugSearch();
    if (this.debugLogs.some(log => log.stage === 'search' && log.level === 'error')) {
      this.addLog('error', 'full', '全链路调试终止：搜索失败');
      return;
    }

    // 等待一下
    await new Promise<void>((resolve: (value: void) => void) => {
      setTimeout(() => resolve(), 1000);
    });

    // 2. 尝试获取搜索结果的第一本书URL
    try {
      const results = await BookSourceService.searchBooks(this.source!, this.keyword);
      if (results.length > 0) {
        this.testUrl = results[0].bookUrl;
        this.addLog('info', 'full', '使用第一本书继续测试', `书名: ${results[0].name}`);
      } else {
        this.addLog('error', 'full', '全链路调试终止：无搜索结果');
        return;
      }
    } catch (_) {
      this.addLog('error', 'full', '全链路调试终止：无法获取书籍');
      return;
    }

    this.addLog('success', 'full', '全链路调试完成（详情和目录功能开发中）');
  }

  private exportReport(): void {
    const report: DebugReport = {
      sourceUrl: this.source?.bookSourceUrl ?? '',
      sourceName: this.source?.bookSourceName ?? '',
      stage: this.currentStage,
      keyword: this.keyword,
      testUrl: this.testUrl,
      logs: this.debugLogs,
      result: this.debugResult,
      exportedAt: new Date().toISOString()
    };

    const reportText = JSON.stringify(report, null, 2);

    // 这里可以添加文件导出逻辑
    promptAction.showToast({ message: '调试报告已生成（控制台输出）' });
    console.log('[Debug Report]', reportText);
  }

  private generateDebugReport(): string {
    const report: DebugReport = {
      sourceUrl: this.source?.bookSourceUrl ?? '',
      sourceName: this.source?.bookSourceName ?? '',
      stage: this.currentStage,
      keyword: this.keyword,
      testUrl: this.testUrl,
      logs: this.debugLogs,
      result: this.debugResult,
      exportedAt: new Date().toISOString()
    };
    return JSON.stringify(report, null, 2);
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
            .onClick(() => this.navStack.pop())

          Text('书源调试')
            .fontSize(AppFont.TitleL)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .margin({ left: AppSpace.Xs })

          Text('导出')
            .fontSize(AppFont.Body)
            .fontColor(this.debugLogs.length > 0 ? AppColor.Brand : $r('sys.color.font_tertiary'))
            .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
            .enabled(this.debugLogs.length > 0)
            .onClick(() => this.exportReport())
        }
        .width('100%')
        .height(56)
        .padding({
          top: WindowUtils.getStatusBarHeightVp(),
          left: AppSpace.Xs,
          right: AppSpace.Md
        })
        .backgroundColor($r('sys.color.background_primary'))

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(AppColor.Brand)
            Text('加载中...')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: AppSpace.Xs })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: AppSpace.Md }) {
              // 书源信息
              this.SourceInfoCard()

              // 调试阶段选择
              this.StageSelector()

              // 输入参数
              this.InputCard()

              // 执行按钮
              Button(this.isRunning ? '运行中...' : '开始调试')
                .width('100%')
                .height(44)
                .fontSize(AppFont.Body)
                .backgroundColor(this.isRunning ? $r('sys.color.comp_background_tertiary') : AppColor.Brand)
                .enabled(!this.isRunning)
                .onClick(() => this.runDebug())

              // 调试日志
              if (this.debugLogs.length > 0) {
                this.LogsCard()
              }

              // 调试结果
              if (this.debugResult !== null) {
                this.ResultCard()
              }
            }
            .width('100%')
            .padding({
              left: AppSpace.Md,
              right: AppSpace.Md,
              top: AppSpace.Md,
              bottom: AppSpace.Md + WindowUtils.getSafeAreaInsets().bottom
            })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .scrollable(ScrollDirection.Vertical)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .hideTitleBar(true)
  }

  @Builder
  SourceInfoCard() {
    Column({ space: 6 }) {
      Text(this.source?.bookSourceName || '未知书源')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Text(this.source?.bookSourceUrl || '')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`类型: ${this.source?.bookSourceType === 1 ? '音频' : this.source?.bookSourceType === 0 ? '文本' : '其他'}`)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(AppRadius.Md)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StageSelector() {
    Column({ space: AppSpace.Xs }) {
      Text('调试阶段')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row({ space: AppSpace.Xs }) {
        this.StageButton('搜索', 'search')
        this.StageButton('详情', 'detail')
        this.StageButton('目录', 'toc')
        this.StageButton('正文', 'content')
        this.StageButton('全链路', 'full')
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(AppRadius.Md)
  }

  @Builder
  StageButton(label: string, stage: string) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.currentStage === stage ? AppColor.Brand : $r('sys.color.font_secondary'))
      .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .borderRadius(AppRadius.Sm)
      .backgroundColor(this.currentStage === stage ? AppColor.BrandSoft :
        $r('sys.color.comp_background_secondary'))
      .onClick(() => {
        if (!this.isRunning) {
          this.currentStage = stage;
          this.clearLogs();
        }
      })
  }

  @Builder
  InputCard() {
    Column({ space: AppSpace.Sm }) {
      if (this.currentStage === 'search' || this.currentStage === 'full') {
        Column({ space: 4 }) {
          Text('搜索关键词')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')

          TextInput({ text: $$this.keyword, placeholder: '请输入搜索关键词' })
            .width('100%')
            .height(44)
            .fontSize(AppFont.Body)
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .borderRadius(AppRadius.Xs)
            .enabled(!this.isRunning)
        }
      }

      if (this.currentStage === 'detail' || this.currentStage === 'toc' || this.currentStage === 'content') {
        Column({ space: 4 }) {
          Text(this.currentStage === 'detail' ? '详情页URL' :
            this.currentStage === 'toc' ? '书籍URL' : '章节URL')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')

          TextInput({ text: $$this.testUrl, placeholder: '请输入URL' })
            .width('100%')
            .height(44)
            .fontSize(AppFont.Body)
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .borderRadius(AppRadius.Xs)
            .enabled(!this.isRunning)
        }
      }
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(AppRadius.Md)
  }

  @Builder
  LogsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('调试日志')
          .fontSize(AppFont.Caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Text('清空')
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .onClick(() => this.clearLogs())
      }
      .width('100%')
      .padding(AppSpace.Md)

      Divider()
        .color($r('sys.color.comp_divider'))

      Scroll(this.scroller) {
        Column({ space: 0 }) {
          ForEach(this.debugLogs, (log: DebugLog, index: number) => {
            Column({ space: 4 }) {
              Row({ space: AppSpace.Xs }) {
                Text(this.formatTime(log.timestamp))
                  .fontSize(10)
                  .fontColor($r('sys.color.font_tertiary'))

                Text(`[${log.stage}]`)
                  .fontSize(10)
                  .fontColor(this.getLogLevelColor(log.level))
                  .fontWeight(FontWeight.Medium)
              }

              Text(log.message)
                .fontSize(AppFont.Caption)
                .fontColor(this.getLogLevelColor(log.level))
                .width('100%')

              if (log.detail) {
                Text(log.detail)
                  .fontSize(10)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .padding(AppSpace.Sm)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(index % 2 === 0 ? Color.Transparent : $r('sys.color.comp_background_secondary'))
          }, (log: DebugLog) => `${log.timestamp}-${log.stage}-${log.message}`)
        }
        .width('100%')
      }
      .height(300)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(AppRadius.Md)
  }

  @Builder
  ResultCard() {
    Column({ space: AppSpace.Xs }) {
      Text('调试结果')
        .fontSize(AppFont.Caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Scroll() {
        Text(this.debugResult ? JSON.stringify(this.debugResult, null, 2) : '')
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .width('100%')
          .lineHeight(16)
      }
      .height(200)
      .scrollBar(BarState.Auto)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .borderRadius(AppRadius.Xs)
      .padding(AppSpace.Sm)
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius(AppRadius.Md)
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  private getLogLevelColor(level: 'info' | 'success' | 'warning' | 'error'): ResourceStr {
    switch (level) {
      case 'success':
        return '#168A5B';
      case 'warning':
        return '#E89725';
      case 'error':
        return '#D03050';
      default:
        return $r('sys.color.font_secondary');
    }
  }
}
