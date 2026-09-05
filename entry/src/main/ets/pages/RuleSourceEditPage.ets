import { LocalRuleSource, LocalRuleSearchRule, LocalRuleBookInfoRule, LocalRuleTocRule, LocalRuleContentRule } from '../model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { promptAction } from '@kit.ArkUI';

interface FormFieldParams {
  label: string;
  value: string;
  placeholder?: string;
  multiline?: boolean;
  enabled?: boolean;
  onChange: (value: string) => void;
}

@Builder
function FormFieldBuilder(params: FormFieldParams) {
  Column({ space: 4 }) {
    Text(params.label)
      .fontSize(AppFont.Caption)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')

    if (params.multiline) {
      TextArea({ text: params.value, placeholder: params.placeholder || `请输入${params.label}` })
        .width('100%')
        .height(80)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs)
        .enabled(params.enabled !== false)
        .onChange((value: string) => params.onChange(value))
    } else {
      TextInput({ text: params.value, placeholder: params.placeholder || `请输入${params.label}` })
        .width('100%')
        .height(44)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs)
        .enabled(params.enabled !== false)
        .onChange((value: string) => params.onChange(value))
    }
  }
  .width('100%')
}

@ComponentV2
export struct RuleSourceEditPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local source: LocalRuleSource = new LocalRuleSource();
  @Local currentTab: number = 0;
  @Local isLoading: boolean = false;
  @Local isSaving: boolean = false;
  @Local hasUnsavedChanges: boolean = false;
  @Local showUnsavedDialog: boolean = false;
  @Local originalSnapshot: string = '';
  private isNewSource: boolean = true;

  aboutToAppear(): void {
    if (this.sourceUrl && this.sourceUrl.length > 0) {
      this.isNewSource = false;
      this.loadSource();
    } else {
      this.isNewSource = true;
      this.source = new LocalRuleSource();
      this.source.bookSourceType = 1; // 默认音频
      this.source.enabled = true;
      this.source.ruleSearch = new LocalRuleSearchRule();
      this.source.ruleBookInfo = new LocalRuleBookInfoRule();
      this.source.ruleToc = new LocalRuleTocRule();
      this.source.ruleContent = new LocalRuleContentRule();
      this.markSaved();
    }
  }

  private async loadSource(): Promise<void> {
    this.isLoading = true;
    try {
      const loaded = await LocalRuleSourceRepository.findByUrl(this.sourceUrl!);
      if (loaded) {
        this.source = loaded;
        this.markSaved();
      } else {
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

  private markSaved(): void {
    this.originalSnapshot = this.sourceSnapshot();
    this.hasUnsavedChanges = false;
  }

  private markChanged(): void {
    this.hasUnsavedChanges = this.sourceSnapshot() !== this.originalSnapshot;
  }

  private sourceSnapshot(): string {
    return JSON.stringify(this.source);
  }

  private async saveSource(): Promise<void> {
    if (!this.source.bookSourceUrl || this.source.bookSourceUrl.trim().length === 0) {
      promptAction.showToast({ message: '请输入书源地址' });
      return;
    }
    if (!this.source.bookSourceName || this.source.bookSourceName.trim().length === 0) {
      promptAction.showToast({ message: '请输入书源名称' });
      return;
    }

    this.isSaving = true;
    try {
      if (this.isNewSource) {
        await LocalRuleSourceRepository.insert(this.source);
      } else {
        await LocalRuleSourceRepository.update(this.source);
      }
      this.markSaved();
      promptAction.showToast({ message: '保存成功' });
      this.navStack.pop();
    } catch (error) {
      promptAction.showToast({ message: '保存失败' });
    } finally {
      this.isSaving = false;
    }
  }

  private requestBack(): boolean {
    if (this.hasUnsavedChanges) {
      this.showUnsavedDialog = true;
      return true;
    }
    this.navStack.pop();
    return true;
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 顶部标题栏
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
              .onClick(() => this.requestBack())

            Text(this.isNewSource ? '新建书源' : '编辑书源')
              .fontSize(AppFont.TitleL)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
              .margin({ left: AppSpace.Xs })

            if (!this.isLoading) {
              Text('保存')
                .fontSize(AppFont.Body)
                .fontColor(this.isSaving ? $r('sys.color.font_tertiary') : AppColor.Brand)
                .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
                .enabled(!this.isSaving)
                .onClick(() => this.saveSource())
            }
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
            // Tab栏
            Row() {
              this.TabButton('基本', 0)
              this.TabButton('搜索', 1)
              this.TabButton('详情', 2)
              this.TabButton('目录', 3)
              this.TabButton('正文', 4)
            }
            .width('100%')
            .height(44)
            .backgroundColor($r('sys.color.background_primary'))
            .borderWidth({ bottom: 0.5 })
            .borderColor($r('sys.color.comp_divider'))

            // 内容区域
            Scroll() {
              Column({ space: AppSpace.Md }) {
                if (this.currentTab === 0) {
                  this.BasicTab()
                } else if (this.currentTab === 1) {
                  this.SearchTab()
                } else if (this.currentTab === 2) {
                  this.InfoTab()
                } else if (this.currentTab === 3) {
                  this.TocTab()
                } else if (this.currentTab === 4) {
                  this.ContentTab()
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
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_secondary'))

        if (this.showUnsavedDialog) {
          this.UnsavedDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed(() => this.requestBack())
  }

  @Builder
  TabButton(label: string, index: number) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.currentTab === index ? AppColor.Brand : $r('sys.color.font_secondary'))
      .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .height('100%')
      .borderWidth({ bottom: this.currentTab === index ? 2 : 0 })
      .borderColor(AppColor.Brand)
      .onClick(() => {
        this.currentTab = index;
      })
  }

  @Builder
  BasicTab() {
    Column({ space: AppSpace.Md }) {
      FormFieldBuilder({
        label: '书源名称',
        value: this.source.bookSourceName,
        placeholder: '请输入书源名称',
        onChange: (value: string) => {
          this.source.bookSourceName = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书源地址',
        value: this.source.bookSourceUrl,
        placeholder: '请输入书源地址（URL）',
        enabled: this.isNewSource,
        onChange: (value: string) => {
          this.source.bookSourceUrl = value;
          this.markChanged();
        }
      })

      Column({ space: 4 }) {
        Text('书源类型')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')

        Row({ space: AppSpace.Xs }) {
          this.TypeButton('文本', 0)
          this.TypeButton('音频', 1)
          this.TypeButton('漫画', 2)
        }
        .width('100%')
      }

      FormFieldBuilder({
        label: '书源分组',
        value: this.source.bookSourceGroup,
        placeholder: '可选，如：玄幻、都市',
        onChange: (value: string) => {
          this.source.bookSourceGroup = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书源备注',
        value: this.source.bookSourceComment,
        placeholder: '可选，备注说明',
        onChange: (value: string) => {
          this.source.bookSourceComment = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '登录地址',
        value: this.source.loginUrl || '',
        placeholder: '可选，需要登录时填写',
        onChange: (value: string) => {
          this.source.loginUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: 'JS库',
        value: this.source.jsLib || '',
        placeholder: '可选，自定义JS函数',
        multiline: true,
        onChange: (value: string) => {
          this.source.jsLib = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '请求头（Header）',
        value: this.source.header || '',
        placeholder: '可选，JSON格式',
        multiline: true,
        onChange: (value: string) => {
          this.source.header = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '变量（Variable）',
        value: this.source.variable || '',
        placeholder: '可选，JSON格式',
        multiline: true,
        onChange: (value: string) => {
          this.source.variable = value;
          this.markChanged();
        }
      })

      Row() {
        Text('启用书源')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
          .selectedColor(AppColor.Brand)
          .onChange((isOn: boolean) => {
            this.source.enabled = isOn;
            this.markChanged();
          })
      }
      .width('100%')
      .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
    }
  }

  @Builder
  TypeButton(label: string, type: number) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.source.bookSourceType === type ? AppColor.Brand : $r('sys.color.font_secondary'))
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .borderRadius(AppRadius.Sm)
      .backgroundColor(this.source.bookSourceType === type ? AppColor.BrandSoft :
        $r('sys.color.comp_background_secondary'))
      .onClick(() => {
        this.source.bookSourceType = type;
        this.markChanged();
      })
  }

  @Builder
  SearchTab() {
    Column({ space: AppSpace.Md }) {
      Text('搜索规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '搜索地址',
        value: this.source.searchUrl || '',
        placeholder: '{{key}}为关键词占位符',
        onChange: (value: string) => {
          this.source.searchUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书籍列表规则',
        value: this.source.ruleSearch?.bookList || '',
        placeholder: '定位书籍列表的规则',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.bookList = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书名规则',
        value: this.source.ruleSearch?.name || '',
        placeholder: '提取书名',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.name = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '作者规则',
        value: this.source.ruleSearch?.author || '',
        placeholder: '提取作者',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.author = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '封面规则',
        value: this.source.ruleSearch?.coverUrl || '',
        placeholder: '提取封面URL',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.coverUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '简介规则',
        value: this.source.ruleSearch?.intro || '',
        placeholder: '提取简介',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.intro = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '分类规则',
        value: this.source.ruleSearch?.kind || '',
        placeholder: '提取分类',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.kind = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '详情页地址规则',
        value: this.source.ruleSearch?.bookUrl || '',
        placeholder: '提取详情页URL',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.bookUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '最新章节规则',
        value: this.source.ruleSearch?.lastChapter || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleSearch) this.source.ruleSearch = new LocalRuleSearchRule();
          this.source.ruleSearch.lastChapter = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  InfoTab() {
    Column({ space: AppSpace.Md }) {
      Text('详情规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '初始化规则',
        value: this.source.ruleBookInfo?.init || '',
        placeholder: '可选，预处理JS',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.init = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '书名规则',
        value: this.source.ruleBookInfo?.name || '',
        placeholder: '提取书名',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.name = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '作者规则',
        value: this.source.ruleBookInfo?.author || '',
        placeholder: '提取作者',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.author = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '封面规则',
        value: this.source.ruleBookInfo?.coverUrl || '',
        placeholder: '提取封面URL',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.coverUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '简介规则',
        value: this.source.ruleBookInfo?.intro || '',
        placeholder: '提取简介',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.intro = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '分类规则',
        value: this.source.ruleBookInfo?.kind || '',
        placeholder: '提取分类',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.kind = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '目录页地址规则',
        value: this.source.ruleBookInfo?.tocUrl || '',
        placeholder: '提取目录页URL',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.tocUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '最新章节规则',
        value: this.source.ruleBookInfo?.lastChapter || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleBookInfo) this.source.ruleBookInfo = new LocalRuleBookInfoRule();
          this.source.ruleBookInfo.lastChapter = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  TocTab() {
    Column({ space: AppSpace.Md }) {
      Text('目录规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      FormFieldBuilder({
        label: '章节列表规则',
        value: this.source.ruleToc?.chapterList || '',
        placeholder: '定位章节列表',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterList = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '章节名称规则',
        value: this.source.ruleToc?.chapterName || '',
        placeholder: '提取章节名',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterName = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '章节地址规则',
        value: this.source.ruleToc?.chapterUrl || '',
        placeholder: '提取章节URL',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.chapterUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '目录下一页规则',
        value: this.source.ruleToc?.nextTocUrl || '',
        placeholder: '可选，多页目录时使用',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.nextTocUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: 'VIP标记规则',
        value: this.source.ruleToc?.isVip || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.isVip = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '付费标记规则',
        value: this.source.ruleToc?.isPay || '',
        placeholder: '可选',
        onChange: (value: string) => {
          if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
          this.source.ruleToc.isPay = value;
          this.markChanged();
        }
      })

      if (this.source.bookSourceType === 1) {
        FormFieldBuilder({
          label: '音频时长规则',
          value: this.source.ruleToc?.duration || '',
          placeholder: '可选，提取时长',
          onChange: (value: string) => {
            if (!this.source.ruleToc) this.source.ruleToc = new LocalRuleTocRule();
            this.source.ruleToc.duration = value;
            this.markChanged();
          }
        })
      }
    }
  }

  @Builder
  ContentTab() {
    Column({ space: AppSpace.Md }) {
      Text(this.source.bookSourceType === 1 ? '音频规则' : '正文规则')
        .fontSize(AppFont.Body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      if (this.source.bookSourceType === 1) {
        FormFieldBuilder({
          label: '音频地址规则',
          value: this.source.ruleContent?.audioUrl || '',
          placeholder: '提取音频URL',
          onChange: (value: string) => {
            if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
            this.source.ruleContent.audioUrl = value;
            this.markChanged();
          }
        })
      } else {
        FormFieldBuilder({
          label: '正文内容规则',
          value: this.source.ruleContent?.content || '',
          placeholder: '提取正文',
          onChange: (value: string) => {
            if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
            this.source.ruleContent.content = value;
            this.markChanged();
          }
        })
      }

      FormFieldBuilder({
        label: '章节标题规则',
        value: this.source.ruleContent?.title || '',
        placeholder: '可选，重新提取标题',
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.title = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '正文下一页规则',
        value: this.source.ruleContent?.nextContentUrl || '',
        placeholder: '可选，分页正文时使用',
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.nextContentUrl = value;
          this.markChanged();
        }
      })

      FormFieldBuilder({
        label: '替换净化规则',
        value: this.source.ruleContent?.replaceRegex || '',
        placeholder: '可选，正则替换',
        multiline: true,
        onChange: (value: string) => {
          if (!this.source.ruleContent) this.source.ruleContent = new LocalRuleContentRule();
          this.source.ruleContent.replaceRegex = value;
          this.markChanged();
        }
      })
    }
  }

  @Builder
  UnsavedDialog() {
    Column() {
      Column({ space: AppSpace.Md }) {
        Text('保存修改？')
          .fontSize(AppFont.Body)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)

        Text('当前有未保存的修改，是否保存？')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)

        Button('保存并返回')
          .width('100%')
          .height(44)
          .fontSize(AppFont.Body)
          .backgroundColor(AppColor.Brand)
          .onClick(() => {
            this.showUnsavedDialog = false;
            this.saveSource();
          })

        Button('放弃修改')
          .width('100%')
          .height(44)
          .fontSize(AppFont.Body)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.showUnsavedDialog = false;
            this.navStack.pop();
          })

        Button('取消')
          .width('100%')
          .height(44)
          .fontSize(AppFont.Body)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.showUnsavedDialog = false;
          })
      }
      .width('85%')
      .padding(AppSpace.Lg)
      .backgroundColor($r('sys.color.background_primary'))
      .borderRadius(AppRadius.Md)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showUnsavedDialog = false;
    })
  }
}
