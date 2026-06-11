import { common } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { AudioService } from '../service/AudioService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { playerEntryState } from './PlayerPage';

@ComponentV2
export struct BookDetailPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Local book: Book | null = null;
  @Local isFavorite: boolean = false;
  @Local loadingToc: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local isStartingPlay: boolean = false;
  @Local lastHistory: PlayHistoryItem | null = null;
  @Local activeTab: number = 1;
  @Local bgColor: string = '#3A3A3A';
  @Local bgColorDark: string = '#1A1A1A';
  @Local hasThemeColor: boolean = false;
  @Local debugInfo: string = '';
  private chapterListScroller: Scroller = new Scroller();
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();

  aboutToAppear(): void {
    // 命中 SearchCache 时同步可拿到 book,首屏立刻有内容;
    // 收藏状态 / TOC 拉取 / 取色等重活推迟到转场动画结束后,避免抢主线程
    this.primeBookFromCache();
    WindowUtils.setStatusBarLight(true);
    setTimeout(() => { this.loadBook(); }, AppMotion.Page);
  }

  /** 同步从 SearchCache 取 book,让首帧有内容,后续重活推迟 */
  private primeBookFromCache(): void {
    const cached = SearchCache.get(this.bookId);
    if (cached) {
      this.book = cached;
      this.chapterDataSource.setChapters(cached.chapters);
      const cachedRgb = ColorPickerUtils.getCached(cached.cover);
      if (cachedRgb) {
        this.applyCoverColor(cachedRgb);
      }
    }
  }

  aboutToDisappear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  private async loadBook(): Promise<void> {
    const b = await this.findBookById(this.bookId);
    if (b) {
      // 先快速渲染基础信息
      this.book = b;
      this.chapterDataSource.setChapters(b.chapters);
      this.isFavorite = await PreferenceService.isFavorite(b.id);
      // 加载播放/阅读历史，用于"继续播放"入口
      this.loadHistory(b.id);
      // 先同步检查封面色缓存，命中则直接用，避免异步提取期间的默认灰闪烁
      const cached = ColorPickerUtils.getCached(b.cover);
      if (cached) {
        this.applyCoverColor(cached);
      }
      // 取色异步执行,不阻塞首屏
      this.extractCoverColor(b.cover);
      // 章节懒加载
      if (b.chapters.length === 0 && b.bookUrl && b.sourceUrl) {
        this.loadTocFromSource(b);
      } else {
        this.scrollToCurrentChapter();
      }
    }
  }

  /** 从 Preferences 加载本书的播放/阅读历史 */
  private async loadHistory(bookId: string): Promise<void> {
    const history = await PreferenceService.getHistory();
    const item = history.find((h) => h.bookId === bookId);
    if (item) {
      this.lastHistory = item;
    }
  }

  /** 一次性应用封面色，避免多次状态更新触发多次重绘 */
  private applyCoverColor(rgb: RgbColor): void {
    const dark = ColorPickerUtils.darken(rgb, 0.3);
    this.bgColor = ColorPickerUtils.toHex(rgb);
    this.bgColorDark = ColorPickerUtils.toHex(dark);
    this.hasThemeColor = true;
  }

  private async findBookById(id: string): Promise<Book | null> {
    const cached = SearchCache.get(id);
    if (cached) return cached;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const imported = await DataService.getBookById(ctx, id);
    return imported || null;
  }

  private async loadTocFromSource(book: Book): Promise<void> {
    this.loadingToc = true;
    this.debugInfo = `bookUrl=${book.bookUrl}\nsourceUrl=${book.sourceUrl}`;
    try {
      const sources = await SourceDataService.getSources();
      const source = sources.find(s => s.bookSourceUrl === book.sourceUrl);
      this.debugInfo += `\nsource=${source ? source.bookSourceName : 'NOT FOUND'}`;
      if (source && book.bookUrl) {
        // 先获取书籍详情，提取正确的 tocUrl
        let tocUrl = book.bookUrl;
        const bookInfo = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
        // 合并 search 时的 @put 变量 + getBookInfo 时的 @put 变量
        const mergedVars: Record<string, string> = {};
        if (book.variables) {
          for (const k of Object.keys(book.variables)) {
            mergedVars[k] = book.variables[k];
          }
        }
        if (bookInfo?.variables) {
          for (const k of Object.keys(bookInfo.variables)) {
            mergedVars[k] = bookInfo.variables[k];
          }
        }
        if (bookInfo) {
          if (bookInfo.tocUrl) tocUrl = bookInfo.tocUrl;
          if (bookInfo.intro && !book.intro) book.intro = bookInfo.intro;
        }
        this.debugInfo += `\ntocUrl=${tocUrl}`;

        const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars, book.title);
        this.debugInfo += `\ntocItems=${tocItems.length}`;
        if (tocItems.length > 0) {
          this.debugInfo += `\nfirst=${tocItems[0].name}`;
        }
        // 去重:按 URL 去重(保留首次出现的章节,丢弃重复 URL)
        const seenUrls = new Set<string>();
        const uniqueTocItems = tocItems.filter(item => {
          if (seenUrls.has(item.url)) {
            return false;
          }
          seenUrls.add(item.url);
          return true;
        });
        this.debugInfo += `\nunique=${uniqueTocItems.length}`;
        book.chapters = uniqueTocItems.map((item: TocItem, idx: number): Chapter => ({
          id: `${book.id}-c${idx}`,
          index: idx + 1,
          title: item.name,
          duration: item.duration || 0,
          source: { type: 'url', value: item.url },
          originSourceValue: item.url
        }));
        book.chapterCount = book.chapters.length;
        const cloned: Book = {
          id: book.id,
          title: book.title,
          author: book.author,
          narrator: book.narrator,
          cover: book.cover,
          category: book.category,
          intro: book.intro,
          totalDuration: book.totalDuration,
          chapterCount: book.chapterCount,
          rating: book.rating,
          tags: book.tags,
          chapters: book.chapters,
          bookUrl: book.bookUrl,
          sourceUrl: book.sourceUrl
        };
        this.book = cloned;
        this.chapterDataSource.setChapters(cloned.chapters);
        SearchCache.put(cloned);
        // 已收藏的在线书：同步把最新 toc 写回 cachedBooks,保证书架直接进播放器有完整章节
        if (this.isFavorite) {
          await DataService.upsertCachedBook(cloned);
        }
      }
    } catch (e) {
      this.debugInfo += `\nERROR: ${e}`;
    }
    this.loadingToc = false;
    this.scrollToCurrentChapter();
  }

  private async extractCoverColor(cover: string): Promise<void> {
    if (!cover) return;
    let rgb: RgbColor | null = null;
    try {
      if (cover.startsWith('http')) {
        rgb = await ColorPickerUtils.pickFromUrl(cover);
      } else if (cover.startsWith('/')) {
        rgb = await ColorPickerUtils.pickFromFile(cover);
      } else {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        rgb = await ColorPickerUtils.pickFromRawfile(ctx, cover);
      }
    } catch (_e) { /* ignore */ }
    if (!rgb) return;
    // 一次性更新，避免 3 次独立赋值触发 3 次重绘
    this.applyCoverColor(rgb);
  }

  private scrollToCurrentChapter(): void {
    if (!this.book || !this.playerState.currentBook || !this.playerState.currentChapter) return;
    if (this.playerState.currentBook.id !== this.bookId) return;
    const idx = this.book.chapters.findIndex(ch => ch.id === this.playerState.currentChapter!.id);
    this.scrollChapterListToIndex(idx);
  }

  /**
   * 可靠定位章节列表到指定 index。
   * 两段式延迟:首次等「节目」tab/列表挂载并完成首屏布局(规避 setTimeout(0) 的挂载竞态),
   * 把目标项拉进 LazyForEach 渲染窗口;二次等目标项真实行高确定后再精确居中,
   * 修正长列表按平均行高估算导致的 ScrollAlign.CENTER 偏差(原先单次定位时灵时不灵)。
   */
  private scrollChapterListToIndex(idx: number): void {
    if (idx <= 0) return;
    setTimeout(() => {
      try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      setTimeout(() => {
        try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      }, 150);
    }, 50);
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    if (this.bookId.startsWith('import_') && this.isFavorite) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '导入的书需在书架长按删除' });
      } catch (_e) { /* ignore */ }
      return;
    }
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      // 在线书:章节还没拉到就先把 toc 拉齐再写缓存,避免书架点击时拿到空 chapters
      const needToc = (!this.book.chapters || this.book.chapters.length === 0)
        && !!this.book.bookUrl && !!this.book.sourceUrl;
      if (needToc) {
        await this.loadTocFromSource(this.book);
      }
      await DataService.upsertCachedBook(this.book);
    } else if (!this.bookId.startsWith('import_')) {
      // 取消收藏后,如果没有播放历史,也清掉缓存避免堆积
      const history = await PreferenceService.getHistory();
      const stillNeeded = history.some((h) => h.bookId === this.book!.id);
      if (!stillNeeded) {
        await DataService.removeCachedBook(this.book.id);
      }
    }
  }

  private async startPlay(chapter?: Chapter): Promise<void> {
    if (!this.book || this.isStartingPlay) return;
    this.isStartingPlay = true;

    // 没有指定章节时，优先从历史恢复，否则用第一章
    let target: Chapter | undefined = chapter;
    let resumeProgressMs = 0;
    if (!target && this.lastHistory) {
      // 标题优先定位:连载更新/TOC 重排后旧 chapterId 会指向错误章节
      const hi = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
      target = hi >= 0 ? this.book.chapters[hi] : undefined;
      resumeProgressMs = this.lastHistory.progressMs;
    }
    if (!target) {
      target = this.book.chapters[0];
    }
    if (!target) {
      this.isStartingPlay = false;
      return;
    }
    // ★ 用户当前正在播这本书且同章节:用 live state.progressMs(更新)替代 lastHistory.progressMs(可能旧 5s),
    //   避免从详情页继续播放反而回退进度
    if (PlaybackStore.getInstance().isCurrentChapter(this.book.id, target.id)) {
      resumeProgressMs = this.playerState.progressMs;
    }

    SearchCache.put(this.book);
    // ★ 当前在播的就是同书:直接 push player 不带 chapter 参数,PlayerPage 复用 live state,
    //   避免 tryResumePlay 触发 playChapterAndSeek 重置
    if (PlaybackStore.getInstance().isCurrentBook(this.book.id)) {
      // 详情页入口,非共享元素,且清理栈避免重复 player
      playerEntryState.fromMini = false;
      playerEntryState.fromBookCard = false;
      playerEntryState.bookCardId = '';
      this.cleanStackBeforePushPlayer();
      this.navStack.pushPathByName('player', this.bookId);
      this.isStartingPlay = false;
      return;
    }
    const playerParams: Record<string, Object> = {
      'bookId': this.bookId as Object,
      'chapterId': target.id as Object,
      'progressMs': resumeProgressMs as Object
    };
    // 详情页入口,非共享元素,且清理栈避免重复 player
    playerEntryState.fromMini = false;
    playerEntryState.fromBookCard = false;
    playerEntryState.bookCardId = '';
    this.cleanStackBeforePushPlayer();
    this.navStack.pushPathByName('player', playerParams);
    this.isStartingPlay = false;
  }

  /** 从详情页进播放页前,清理栈避免重复 player。如果栈里已有 player,先 pop 到 home,再 push player */
  private cleanStackBeforePushPlayer(): void {
    const names = this.navStack.getAllPathName();
    if (!names || names.length === 0) return;
    // 栈结构:home, player?, detail, ...
    // 如果 names[1] === 'player',说明从 player 进的 detail,需要 pop 到 home
    if (names.length >= 2 && names[1] === 'player') {
      this.navStack.popToName('home');
    }
  }

  private formatDuration(seconds: number): string {
    if (seconds <= 0) return '';
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private formatPlayCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(0) + '万';
    }
    return count.toString();
  }

  private getPlayProgress(ch: Chapter): number {
    if (!this.playerState.currentBook || !this.playerState.currentChapter) return 0;
    if (this.playerState.currentBook.id === this.bookId && this.playerState.currentChapter.id === ch.id) {
      if (this.playerState.durationMs > 0) {
        return Math.round(this.playerState.progressMs / this.playerState.durationMs * 100);
      }
    }
    return 0;
  }

  private isPlayingChapter(ch: Chapter): boolean {
    if (!this.playerState.currentBook || !this.playerState.currentChapter) return false;
    return this.playerState.currentBook.id === this.bookId && this.playerState.currentChapter.id === ch.id;
  }

  build() {
    Column() {
      if (this.book) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 沉浸式背景
          Column()
            .width('100%')
            .height(320)
            .linearGradient({
              angle: 180,
              colors: [[this.bgColor, 0.0], [this.bgColorDark, 1.0]]
            })

          Column() {
            this.buildTopBar()
            this.buildHeader()
            this.buildStats()
          }
          .width('100%')
          .padding({ top: WindowUtils.getStatusBarHeightVp() })
        }
        .width('100%')

        // Tab 区域
        this.buildTabBar()

        // 内容区
        if (this.activeTab === 0) {
          this.buildIntroContent()
        } else {
          this.buildChapterContent()
        }
      } else {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColor.Brand)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildTopBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24).fontColor(['#FFFFFF'])
        .onClick(() => this.navStack.pop())
      Blank()
      SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(22)
        .fontColor([this.isFavorite ? '#FF6B8A' : '#FFFFFF'])
        .onClick(() => this.toggleFavorite())
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Lg }) {
      // 封面（共享元素，飞向 PlayerPage / 飞回 BookCard）
      Stack() {
        if (this.book!.cover && this.book!.cover.startsWith('http')) {
          Image(this.book!.cover)
            .width(100)
            .height(130)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else if (this.book!.cover && this.book!.cover.startsWith('/')) {
          Image('file://' + this.book!.cover)
            .width(100)
            .height(130)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else if (this.book!.cover) {
          Image($rawfile(this.book!.cover))
            .width(100)
            .height(130)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(48).fontColor(['#FFFFFF'])
          }
          .width(100).height(130)
          .borderRadius(AppRadius.Sm)
          .backgroundColor('#33FFFFFF')
          .justifyContent(FlexAlign.Center)
        }
      }

      // 书名信息
      Column({ space: AppSpace.Xs }) {
        Text(this.book!.title)
          .fontSize(AppFont.TitleL)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.book!.author) {
          Text(this.book!.author)
            .fontSize(AppFont.Body)
            .fontColor('#FFFFFFCC')
            .maxLines(1)
        }
        if (this.book!.tags && this.book!.tags.length > 0) {
          Row({ space: AppSpace.Xs }) {
            ForEach(this.book!.tags.slice(0, 2), (tag: string) => {
              Text(tag)
                .fontSize(AppFont.Caption)
                .fontColor('#FFFFFF')
                .backgroundColor('#33FFFFFF')
                .borderRadius(AppRadius.Xs)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }, (tag: string) => tag)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })
  }

  @Builder
  buildStats() {
    Row() {
      // 评分
      Column({ space: 2 }) {
        Text(this.book!.rating > 0 ? this.book!.rating.toFixed(1) + ' 分' : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text('评分')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)

      // 播放量
      Column({ space: 2 }) {
        Text(this.book!.totalDuration > 0 ? this.formatPlayCount(this.book!.totalDuration) : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text('播放量')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)

      // 章节数
      Column({ space: 2 }) {
        Text(this.book!.chapterCount > 0 ? this.book!.chapterCount.toString() + ' 集' : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text('总集数')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpace.Xl, right: AppSpace.Xl, top: AppSpace.Lg, bottom: AppSpace.Lg })
  }

  @Builder
  buildTabBar() {
    Row() {
      Text('详情')
        .fontSize(AppFont.BodyL)
        .fontColor(this.activeTab === 0 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
        .border(this.activeTab === 0
          ? { width: { bottom: 2 }, color: { bottom: AppColor.Brand } }
          : { width: { bottom: 2 }, color: { bottom: Color.Transparent } })
        .onClick(() => { this.activeTab = 0; })

      Text('节目')
        .fontSize(AppFont.BodyL)
        .fontColor(this.activeTab === 1 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
        .border(this.activeTab === 1
          ? { width: { bottom: 2 }, color: { bottom: AppColor.Brand } }
          : { width: { bottom: 2 }, color: { bottom: Color.Transparent } })
        .onClick(() => {
          this.activeTab = 1;
          this.scrollToCurrentChapter();
        })
    }
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: { bottom: AppColor.Divider } })
    .backgroundColor($r('sys.color.background_primary'))
  }

  /** 获取历史章节标题，供 Builder 使用 */
  private historyChapterTitle(): string {
    if (!this.lastHistory || !this.book) return '';
    const idx = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    return idx >= 0 ? this.book.chapters[idx].title : (this.lastHistory.chapterTitle ?? '');
  }

  /** 根据是否有历史记录返回按钮文案 */
  private resumeButtonText(): string {
    if (!this.lastHistory || !this.book) {
      return '开始播放';
    }
    const idx = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    if (idx >= 0) {
      const title = this.book.chapters[idx].title;
      return `继续播放 ${title}`;
    }
    return '继续播放';
  }

  @Builder
  buildIntroContent() {
    Scroll() {
      Column({ space: AppSpace.Md }) {
        if (this.book!.intro) {
          Text(this.book!.intro)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(24)
            .width('100%')
        } else {
          Text('暂无简介')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }

        // 播放/阅读按钮
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18).fontColor(['#FFFFFF'])
          Text(this.resumeButtonText())
            .fontSize(AppFont.BodyL)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
            .margin({ left: AppSpace.Xs })
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
        .borderRadius(24)
        .backgroundColor(AppColor.Brand)
        .margin({ top: AppSpace.Md })
        .onClick(() => this.startPlay())
      }
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildChapterContent() {
    Column() {
      // 章节头部
      Row() {
        Text(`共 ${this.book!.chapters.length} 集`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
        if (this.loadingToc) {
          LoadingProgress().width(16).height(16).color(AppColor.Brand).margin({ left: AppSpace.Xs })
        }
        Blank()
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(18).fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Sm })

      // 章节列表
      if (this.book!.chapters.length === 0 && !this.loadingToc) {
        Column() {
          Text('暂无章节信息')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
          if (this.debugInfo) {
            Text(this.debugInfo)
              .fontSize(10)
              .fontColor('#FF6B6B')
              .margin({ top: 8 })
              .padding(8)
              .backgroundColor('#1AFFFFFF')
              .borderRadius(4)
              .maxLines(10)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0, scroller: this.chapterListScroller }) {
          LazyForEach(this.chapterDataSource, (ch: Chapter) => {
            ListItem() {
              this.buildChapterItem(ch)
            }
          }, (ch: Chapter) => ch.id)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(5)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0.5, color: AppColor.Divider, startMargin: AppSpace.Lg, endMargin: AppSpace.Lg })
      }
    }
    .layoutWeight(1)
  }

  @Builder
  buildChapterItem(ch: Chapter) {
    Row() {
      Column({ space: 2 }) {
        Text(ch.title)
          .fontSize(AppFont.BodyL)
          .fontColor(this.isPlayingChapter(ch) ? '#D4380D' : $r('sys.color.font_primary'))
          .fontWeight(this.isPlayingChapter(ch) ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: AppSpace.Xs }) {
          if (ch.duration > 0) {
            Text(this.formatDuration(ch.duration))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          if (this.getPlayProgress(ch) > 0) {
            Text(`已播 ${this.getPlayProgress(ch)}%`)
              .fontSize(AppFont.Caption)
              .fontColor('#D4380D')
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isPlayingChapter(ch)) {
        SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
          .fontSize(18).fontColor(['#D4380D'])
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: 14, bottom: 14 })
    .onClick(() => this.startPlay(ch))
  }

  @Builder
  buildBottomPlayer() {
    Row({ space: AppSpace.Md }) {
      // 播放按钮
      Row() {
        SymbolGlyph(this.playerState.isPlaying && this.playerState.currentBook?.id === this.bookId
          ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(20).fontColor(['#FFFFFF'])
      }
      .width(40).height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.Brand)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.playerState.currentBook?.id === this.bookId && this.playerState.currentChapter) {
          AudioService.getInstance().toggle();
        } else {
          this.startPlay();
        }
      })

      // 当前播放信息 / 默认提示
      Column({ space: 2 }) {
        if (this.playerState.currentBook?.id === this.bookId
            && this.playerState.currentChapter) {
          Text(this.playerState.currentChapter.title)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatMs(this.playerState.progressMs) + ' / ' + this.formatMs(this.playerState.durationMs))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        } else {
          Text(this.resumeButtonText())
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          if (this.historyChapterTitle()) {
            Text(this.historyChapterTitle())
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else if (this.book!.chapters.length > 0) {
            Text(this.book!.chapters[0].title)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 章节列表入口
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(22).fontColor([$r('sys.color.font_secondary')])
        .onClick(() => {
          this.activeTab = 1;
          this.scrollToCurrentChapter();
        })
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm + WindowUtils.getBottomSafeVp() })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .border({ width: { top: 0.5 }, color: { top: AppColor.Divider } })
  }

  private formatMs(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }
}
