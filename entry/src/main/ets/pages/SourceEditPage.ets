/**
 * 书源编辑页
 *
 * 把 BookSource 嵌套规则 flatten 成 EditEntity 列表，分组用 Tabs（基本/搜索/发现/详情/目录/正文），
 * 每条一个多行 TextArea。保存时把 entities 写回 BookSource 整条覆盖。
 *
 * 入口: SourcePage 列表项点击 → navStack.pushPathByName('sourceEdit', sourceUrl)
 * 内置源(builtin://)进入只读视图，不能保存。
 *
 * 参考 Legado: BookSourceEditActivity / BookSourceEditViewModel
 */

import { BookSource, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/BookSource';
import { SourceDataService } from '../service/SourceDataService';
import { BuiltInSourceRegistry } from '../service/builtin/BuiltInSourceRegistry';
import { AppColor, AppFont, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_SOURCES_CHANGED } from './SourcePage';

/** 字段类型：text 单行，textarea 多行（规则字段都用多行），bool 开关 */
type FieldType = 'text' | 'textarea' | 'bool';

@ObservedV2
class EditEntity {
  key: string = '';
  label: string = '';
  hint: string = '';
  type: FieldType = 'text';
  @Trace value: string = '';
  @Trace boolValue: boolean = false;

  static of(key: string, label: string, value: string | undefined, type: FieldType = 'textarea', hint: string = ''): EditEntity {
    const e = new EditEntity();
    e.key = key;
    e.label = label;
    e.value = value === undefined || value === null ? '' : String(value);
    e.type = type;
    e.hint = hint;
    return e;
  }

  static ofBool(key: string, label: string, value: boolean | undefined): EditEntity {
    const e = new EditEntity();
    e.key = key;
    e.label = label;
    e.type = 'bool';
    e.boolValue = !!value;
    return e;
  }
}

const TAB_BASIC = 0;
const TAB_SEARCH = 1;
const TAB_EXPLORE = 2;
const TAB_INFO = 3;
const TAB_TOC = 4;
const TAB_CONTENT = 5;
const TAB_NAMES: string[] = ['基本', '搜索', '发现', '详情', '目录', '正文'];

@ComponentV2
export struct SourceEditPage {
  @Param navStack: NavPathStack = new NavPathStack();
  /** 路由参数：要编辑的 bookSourceUrl；空字符串表示新建 */
  @Param sourceUrl: string = '';

  @Local activeTab: number = 0;
  @Local source: BookSource | null = null;
  @Local readonly: boolean = false;
  @Local saving: boolean = false;

  @Local basicEntities: EditEntity[] = [];
  @Local searchEntities: EditEntity[] = [];
  @Local exploreEntities: EditEntity[] = [];
  @Local infoEntities: EditEntity[] = [];
  @Local tocEntities: EditEntity[] = [];
  @Local contentEntities: EditEntity[] = [];

  aboutToAppear(): void {
    this.loadSource();
  }

  private async loadSource(): Promise<void> {
    try {
      if (!this.sourceUrl) {
        // 新建空书源
        this.source = SourceEditPage.emptySource();
        this.readonly = false;
        this.inflateEntities(this.source);
        return;
      }
      const all = await SourceDataService.getSources();
      const found = all.find(s => s.bookSourceUrl === this.sourceUrl) || null;
      this.source = found || SourceEditPage.emptySource();
      this.readonly = BuiltInSourceRegistry.isBuiltIn(this.sourceUrl);
      this.inflateEntities(this.source);
    } catch (e) {
      this.source = SourceEditPage.emptySource();
      this.inflateEntities(this.source);
    }
  }

  /** 把书源字段 flatten 到各 Tab 的 EditEntity 列表 */
  private inflateEntities(s: BookSource): void {
    const sr = s.ruleSearch;
    const er = s.ruleExplore;
    const ir = s.ruleBookInfo;
    const tr = s.ruleToc;
    const cr = s.ruleContent;

    const basic: EditEntity[] = [];
    basic.push(EditEntity.ofBool('enabled', '启用书源', s.enabled));
    basic.push(EditEntity.ofBool('enabledExplore', '启用发现', s.enabledExplore));
    basic.push(EditEntity.ofBool('enabledCookieJar', '启用 Cookie Jar', s.enabledCookieJar));
    basic.push(EditEntity.of('bookSourceUrl', '书源地址 (URL)*', s.bookSourceUrl, 'text', 'https://...'));
    basic.push(EditEntity.of('bookSourceName', '书源名称*', s.bookSourceName, 'text', '显示名称'));
    basic.push(EditEntity.of('bookSourceGroup', '分组', s.bookSourceGroup, 'text', '多个分组用逗号分隔'));
    basic.push(EditEntity.of('bookSourceComment', '备注', s.bookSourceComment, 'text', ''));
    basic.push(EditEntity.of('header', '请求头 (JSON)', s.header, 'textarea', '{"Referer":"https://..."}'
    ));
    basic.push(EditEntity.of('concurrentRate', '并发控制', s.concurrentRate, 'text', '1/s'));
    basic.push(EditEntity.of('loginUrl', '登录 URL', s.loginUrl, 'text', ''));
    basic.push(EditEntity.of('loginCheckJs', '登录检测 JS', s.loginCheckJs, 'textarea', '@js:...'));
    basic.push(EditEntity.of('jsLib', 'jsLib (全局函数)', s.jsLib, 'textarea', 'function helper(){...}'));
    this.basicEntities = basic;

    const search: EditEntity[] = [];
    search.push(EditEntity.of('searchUrl', '搜索 URL*', s.searchUrl, 'textarea', 'https://...{{key}}'));
    search.push(EditEntity.of('bookList', '书籍列表', sr?.bookList, 'textarea', '.class-name'));
    search.push(EditEntity.of('name', '书名', sr?.name, 'textarea', '.title@text'));
    search.push(EditEntity.of('author', '作者', sr?.author, 'textarea', '.author@text'));
    search.push(EditEntity.of('coverUrl', '封面', sr?.coverUrl, 'textarea', '.cover@src'));
    search.push(EditEntity.of('bookUrl', '详情链接', sr?.bookUrl, 'textarea', 'a@href'));
    search.push(EditEntity.of('intro', '简介', sr?.intro, 'textarea', '.intro@text'));
    search.push(EditEntity.of('kind', '标签/类型', sr?.kind, 'textarea', '.kind@text'));
    search.push(EditEntity.of('lastChapter', '最新章节', sr?.lastChapter, 'textarea', '.last@text'));
    search.push(EditEntity.of('checkKeyWord', '验证关键词', sr?.checkKeyWord, 'text', ''));
    this.searchEntities = search;

    const explore: EditEntity[] = [];
    explore.push(EditEntity.of('exploreUrl', '发现 URL', s.exploreUrl, 'textarea', '标签::/path/{{page}}\n多行'));
    explore.push(EditEntity.of('bookList', '书籍列表', er?.bookList, 'textarea', ''));
    explore.push(EditEntity.of('name', '书名', er?.name, 'textarea', ''));
    explore.push(EditEntity.of('author', '作者', er?.author, 'textarea', ''));
    explore.push(EditEntity.of('coverUrl', '封面', er?.coverUrl, 'textarea', ''));
    explore.push(EditEntity.of('bookUrl', '详情链接', er?.bookUrl, 'textarea', ''));
    explore.push(EditEntity.of('intro', '简介', er?.intro, 'textarea', ''));
    this.exploreEntities = explore;

    const info: EditEntity[] = [];
    info.push(EditEntity.of('init', '初始化规则', ir?.init, 'textarea', ''));
    info.push(EditEntity.of('name', '书名', ir?.name, 'textarea', ''));
    info.push(EditEntity.of('author', '作者', ir?.author, 'textarea', ''));
    info.push(EditEntity.of('coverUrl', '封面', ir?.coverUrl, 'textarea', ''));
    info.push(EditEntity.of('intro', '简介', ir?.intro, 'textarea', ''));
    info.push(EditEntity.of('kind', '类型', ir?.kind, 'textarea', ''));
    info.push(EditEntity.of('tocUrl', '目录链接', ir?.tocUrl, 'textarea', ''));
    info.push(EditEntity.of('lastChapter', '最新章节', ir?.lastChapter, 'textarea', ''));
    this.infoEntities = info;

    const toc: EditEntity[] = [];
    toc.push(EditEntity.of('preUpdateJs', '预处理 JS', tr?.preUpdateJs, 'textarea', ''));
    toc.push(EditEntity.of('chapterList', '章节列表', tr?.chapterList, 'textarea', '.chapter-item'));
    toc.push(EditEntity.of('chapterName', '章节名', tr?.chapterName, 'textarea', 'a@text'));
    toc.push(EditEntity.of('chapterUrl', '章节链接', tr?.chapterUrl, 'textarea', 'a@href'));
    toc.push(EditEntity.of('formatJs', '格式化 JS', tr?.formatJs, 'textarea', ''));
    toc.push(EditEntity.of('isVip', 'VIP 规则', tr?.isVip, 'textarea', ''));
    toc.push(EditEntity.of('isPay', '付费规则', tr?.isPay, 'textarea', ''));
    toc.push(EditEntity.of('isVolume', '卷规则', tr?.isVolume, 'textarea', ''));
    toc.push(EditEntity.of('nextTocUrl', '下一目录页', tr?.nextTocUrl, 'textarea', ''));
    toc.push(EditEntity.of('duration', '时长规则', tr?.duration, 'textarea', ''));
    this.tocEntities = toc;

    const content: EditEntity[] = [];
    content.push(EditEntity.of('audioUrl', '音频 URL 规则 (有声书)', cr?.audioUrl, 'textarea',
      'JSONPath/CSS/正则/JS，空则取 content'));
    content.push(EditEntity.of('content', '正文/内容规则', cr?.content, 'textarea', ''));
    content.push(EditEntity.of('sourceRegex', '嗅探 URL 正则 (sourceRegex)', cr?.sourceRegex, 'text',
      '.*\\.(mp3|mp4).*'));
    content.push(EditEntity.of('webJs', 'WebView JS 表达式', cr?.webJs, 'textarea',
      'document.querySelector("audio").src'));
    content.push(EditEntity.of('nextContentUrl', '下一页链接', cr?.nextContentUrl, 'textarea', ''));
    content.push(EditEntity.of('replaceRegex', '替换规则', cr?.replaceRegex, 'textarea', ''));
    this.contentEntities = content;
  }

  private entitiesForTab(tab: number): EditEntity[] {
    if (tab === TAB_BASIC) return this.basicEntities;
    if (tab === TAB_SEARCH) return this.searchEntities;
    if (tab === TAB_EXPLORE) return this.exploreEntities;
    if (tab === TAB_INFO) return this.infoEntities;
    if (tab === TAB_TOC) return this.tocEntities;
    if (tab === TAB_CONTENT) return this.contentEntities;
    return [];
  }

  /* SAVE_PLACEHOLDER */

  /** 在某个 entity 列表里取值 */
  private static val(list: EditEntity[], key: string): string {
    for (const e of list) if (e.key === key) return e.value.trim();
    return '';
  }

  private static boolVal(list: EditEntity[], key: string): boolean {
    for (const e of list) if (e.key === key) return e.boolValue;
    return false;
  }

  /** 把各 Tab 的 entities 收集回 BookSource */
  private collectSource(): BookSource {
    const base = this.source!;
    const b = this.basicEntities;
    const s = this.searchEntities;
    const ex = this.exploreEntities;
    const i = this.infoEntities;
    const t = this.tocEntities;
    const c = this.contentEntities;

    const result: BookSource = {
      bookSourceUrl: SourceEditPage.val(b, 'bookSourceUrl'),
      bookSourceName: SourceEditPage.val(b, 'bookSourceName'),
      bookSourceType: base.bookSourceType,
      bookSourceGroup: SourceEditPage.val(b, 'bookSourceGroup'),
      bookSourceComment: SourceEditPage.val(b, 'bookSourceComment'),
      enabled: SourceEditPage.boolVal(b, 'enabled'),
      enabledExplore: SourceEditPage.boolVal(b, 'enabledExplore'),
      enabledCookieJar: SourceEditPage.boolVal(b, 'enabledCookieJar'),
      searchUrl: SourceEditPage.val(s, 'searchUrl'),
      exploreUrl: SourceEditPage.val(ex, 'exploreUrl'),
      header: SourceEditPage.val(b, 'header'),
      loginUrl: SourceEditPage.val(b, 'loginUrl'),
      loginCheckJs: SourceEditPage.val(b, 'loginCheckJs'),
      jsLib: SourceEditPage.val(b, 'jsLib'),
      concurrentRate: SourceEditPage.val(b, 'concurrentRate'),
      respondTime: base.respondTime,
      customOrder: base.customOrder,
      weight: base.weight,
      subscriptionUrl: base.subscriptionUrl,
      ruleSearch: {
        bookList: SourceEditPage.val(s, 'bookList'),
        name: SourceEditPage.val(s, 'name'),
        author: SourceEditPage.val(s, 'author'),
        coverUrl: SourceEditPage.val(s, 'coverUrl'),
        bookUrl: SourceEditPage.val(s, 'bookUrl'),
        intro: SourceEditPage.val(s, 'intro'),
        kind: SourceEditPage.val(s, 'kind'),
        lastChapter: SourceEditPage.val(s, 'lastChapter'),
        checkKeyWord: SourceEditPage.val(s, 'checkKeyWord'),
      },
      ruleExplore: {
        bookList: SourceEditPage.val(ex, 'bookList'),
        name: SourceEditPage.val(ex, 'name'),
        author: SourceEditPage.val(ex, 'author'),
        coverUrl: SourceEditPage.val(ex, 'coverUrl'),
        bookUrl: SourceEditPage.val(ex, 'bookUrl'),
        intro: SourceEditPage.val(ex, 'intro'),
        kind: '',
        lastChapter: '',
      },
      ruleBookInfo: {
        init: SourceEditPage.val(i, 'init'),
        name: SourceEditPage.val(i, 'name'),
        author: SourceEditPage.val(i, 'author'),
        coverUrl: SourceEditPage.val(i, 'coverUrl'),
        intro: SourceEditPage.val(i, 'intro'),
        kind: SourceEditPage.val(i, 'kind'),
        tocUrl: SourceEditPage.val(i, 'tocUrl'),
        lastChapter: SourceEditPage.val(i, 'lastChapter'),
      },
      ruleToc: {
        preUpdateJs: SourceEditPage.val(t, 'preUpdateJs'),
        chapterList: SourceEditPage.val(t, 'chapterList'),
        chapterName: SourceEditPage.val(t, 'chapterName'),
        chapterUrl: SourceEditPage.val(t, 'chapterUrl'),
        formatJs: SourceEditPage.val(t, 'formatJs'),
        isVip: SourceEditPage.val(t, 'isVip'),
        isPay: SourceEditPage.val(t, 'isPay'),
        isVolume: SourceEditPage.val(t, 'isVolume'),
        nextTocUrl: SourceEditPage.val(t, 'nextTocUrl'),
        duration: SourceEditPage.val(t, 'duration'),
      },
      ruleContent: {
        content: SourceEditPage.val(c, 'content'),
        audioUrl: SourceEditPage.val(c, 'audioUrl'),
        sourceRegex: SourceEditPage.val(c, 'sourceRegex'),
        webJs: SourceEditPage.val(c, 'webJs'),
        nextContentUrl: SourceEditPage.val(c, 'nextContentUrl'),
        replaceRegex: SourceEditPage.val(c, 'replaceRegex'),
      },
      lastUpdateTime: Date.now(),
    };
    return result;
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) { /* ignore */ }
  }

  private async save(): Promise<void> {
    if (this.readonly || !this.source) return;
    const collected = this.collectSource();
    if (!collected.bookSourceUrl || !collected.bookSourceName) {
      this.toast('书源地址和名称不能为空');
      this.activeTab = TAB_BASIC;
      return;
    }
    // header 若填了，校验 JSON 合法性（容错：空串放过）
    if (collected.header && collected.header.length > 0) {
      try {
        JSON.parse(collected.header);
      } catch (_e) {
        this.toast('请求头不是合法 JSON');
        this.activeTab = TAB_BASIC;
        return;
      }
    }
    this.saving = true;
    try {
      const origin = this.sourceUrl || collected.bookSourceUrl;
      await SourceDataService.updateSource(origin, collected);
      emitter.emit(EVT_SOURCES_CHANGED);
      this.toast('已保存');
      this.navStack.pop();
    } catch (e) {
      this.toast('保存失败: ' + (e instanceof Error ? e.message : String(e)));
    } finally {
      this.saving = false;
    }
  }

  private static emptySource(): BookSource {
    const empty: SearchRule = { bookList: '', name: '', author: '', coverUrl: '', bookUrl: '', intro: '', kind: '', lastChapter: '' };
    const exp: ExploreRule = { bookList: '', name: '', author: '', coverUrl: '', bookUrl: '', intro: '', kind: '', lastChapter: '' };
    const info: BookInfoRule = { name: '', author: '', coverUrl: '', intro: '', tocUrl: '' };
    const toc: TocRule = { chapterList: '', chapterName: '', chapterUrl: '' };
    const content: ContentRule = { content: '' };
    return {
      bookSourceUrl: '',
      bookSourceName: '',
      bookSourceType: 1,
      bookSourceGroup: '',
      enabled: true,
      enabledExplore: true,
      searchUrl: '',
      exploreUrl: '',
      header: '',
      respondTime: 0,
      customOrder: 0,
      weight: 0,
      ruleSearch: empty,
      ruleExplore: exp,
      ruleBookInfo: info,
      ruleToc: toc,
      ruleContent: content,
    };
  }

  build() {
    Column() {
      // 标题栏
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text(this.readonly ? '书源详情（只读）' : (this.sourceUrl ? '编辑书源' : '新建书源'))
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        if (!this.readonly) {
          if (this.saving) {
            LoadingProgress().width(24).height(24).color(AppColor.Brand)
          } else {
            Text('保存')
              .fontSize(AppFont.Body)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
              .padding({ left: AppSpace.Sm, right: AppSpace.Xs })
              .onClick(() => this.save())
          }
        }
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md,
        right: AppSpace.Md,
        bottom: AppSpace.Xs
      })

      // Tab 选项卡
      Row() {
        ForEach(TAB_NAMES, (name: string, idx: number) => {
          Text(name)
            .fontSize(AppFont.Caption)
            .fontColor(this.activeTab === idx ? AppColor.Brand : $r('sys.color.font_tertiary'))
            .fontWeight(this.activeTab === idx ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: 6, right: 6, top: 6, bottom: 6 })
            .borderWidth({ bottom: this.activeTab === idx ? 2 : 0 })
            .borderColor({ bottom: AppColor.Brand })
            .onClick(() => {
              this.activeTab = idx;
            })
        }, (name: string) => name)
      }
      .width('100%')
      .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      .justifyContent(FlexAlign.Start)

      Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5)

      // 字段列表
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.entitiesForTab(this.activeTab), (entity: EditEntity) => {
            this.buildField(entity)
          }, (entity: EditEntity) => entity.key + '_' + this.activeTab)
          Column().height(32)
        }
        .width('100%')
        .padding({ top: AppSpace.Xs })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildField(entity: EditEntity) {
    Column({ space: 4 }) {
      Row() {
        Text(entity.label)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        if (entity.type === 'bool') {
          Toggle({ type: ToggleType.Switch, isOn: entity.boolValue })
            .selectedColor(AppColor.Brand)
            .onChange((on: boolean) => {
              if (!this.readonly) entity.boolValue = on;
            })
        }
      }
      .width('100%')

      if (entity.type !== 'bool') {
        if (entity.type === 'text') {
          TextInput({ text: entity.value!!, placeholder: entity.hint })
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
            .enabled(!this.readonly)
            .onChange((v: string) => { entity.value = v; })
        } else {
          TextArea({ text: entity.value!!, placeholder: entity.hint })
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
            .constraintSize({ minHeight: 56, maxHeight: 200 })
            .enabled(!this.readonly)
            .onChange((v: string) => { entity.value = v; })
        }
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
    .alignItems(HorizontalAlign.Start)
  }
}
