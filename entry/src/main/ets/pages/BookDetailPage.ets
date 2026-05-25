import { common } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, TocItem } from '../model/BookSource';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Detail';

@ComponentV2
export struct BookDetailPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Local book: Book | null = null;
  @Local isFavorite: boolean = false;
  @Local loadingToc: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local isStartingPlay: boolean = false;
  @Local activeTab: number = 1;
  @Local bgColor: string = '#3A3A3A';
  @Local bgColorDark: string = '#1A1A1A';
  @Local hasThemeColor: boolean = false;

  aboutToAppear(): void {
    this.loadBook();
    WindowUtils.setStatusBarLight(true);
  }

  aboutToDisappear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  private async loadBook(): Promise<void> {
    const b = await this.findBookById(this.bookId);
    if (b) {
      this.book = b;
      this.isFavorite = await PreferenceService.isFavorite(b.id);
      this.extractCoverColor(b.cover);
      if (b.chapters.length === 0 && b.bookUrl && b.sourceUrl) {
        await this.loadTocFromSource(b);
      }
    }
  }

  private async findBookById(id: string): Promise<Book | null> {
    const cached = SearchCache.get(id);
    if (cached) return cached;
    const ctx = getContext(this) as common.UIAbilityContext;
    const imported = await DataService.getBookById(ctx, id);
    return imported || null;
  }

  private async loadTocFromSource(book: Book): Promise<void> {
    this.loadingToc = true;
    try {
      const sourcesJson = await PreferenceService.getBookSources();
      const sources = JSON.parse(sourcesJson) as BookSource[];
      const source = sources.find(s => s.bookSourceUrl === book.sourceUrl);
      if (source && book.bookUrl) {
        const tocItems = await BookSourceService.getBookToc(source, book.bookUrl);
        book.chapters = tocItems.map((item: TocItem, idx: number): Chapter => ({
          id: `${book.id}-c${idx}`,
          index: idx + 1,
          title: item.name,
          duration: 0,
          source: { type: 'url', value: item.url }
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
        SearchCache.put(cloned);
      }
    } catch (_e) { /* ignore */ }
    this.loadingToc = false;
  }

  private async extractCoverColor(cover: string): Promise<void> {
    if (!cover) return;
    let rgb: RgbColor | null = null;
    try {
      if (cover.startsWith('http')) {
        rgb = await ColorPickerUtils.pickFromUrl(cover);
      } else {
        const ctx = getContext(this) as common.UIAbilityContext;
        rgb = await ColorPickerUtils.pickFromRawfile(ctx, cover);
      }
    } catch (_e) { /* ignore */ }
    if (!rgb) return;
    const dark = ColorPickerUtils.darken(rgb, 0.3);
    this.bgColor = ColorPickerUtils.toHex(rgb);
    this.bgColorDark = ColorPickerUtils.toHex(dark);
    this.hasThemeColor = true;
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
  }

  private isLocalNovel(chapter: Chapter): boolean {
    if (chapter.source.type !== 'file') return false;
    const v = chapter.source.value.toLowerCase();
    return v.endsWith('.txt') || v.endsWith('.epub');
  }

  private async startPlay(chapter?: Chapter): Promise<void> {
    if (!this.book || this.isStartingPlay) return;
    this.isStartingPlay = true;
    const target = chapter ?? this.book.chapters[0];
    if (!target) {
      this.isStartingPlay = false;
      return;
    }
    hilog.info(DOMAIN, TAG, 'startPlay chapter=%{public}s', target.title);

    // 本地小说：直接跳阅读器
    if (this.isLocalNovel(target)) {
      const chapterIndex = this.book.chapters.findIndex(c => c.id === target.id);
      const bookIdObj: Object = this.bookId as Object;
      const indexObj: Object = (chapterIndex >= 0 ? chapterIndex : 0) as Object;
      const params: Record<string, Object> = { 'bookId': bookIdObj, 'chapterIndex': indexObj };
      this.navStack.pushPathByName('TextReaderPage', params);
      this.isStartingPlay = false;
      return;
    }

    // 检测文本书源，跳转到阅读页
    if (this.book.sourceUrl) {
      try {
        const sourcesJson = await PreferenceService.getBookSources();
        const sources = JSON.parse(sourcesJson) as BookSource[];
        const source = sources.find(s => s.bookSourceUrl === this.book!.sourceUrl);

        if (source && source.bookSourceType === 0) {
          const chapterIndex = this.book.chapters.findIndex(c => c.id === target.id);
          const bookIdObj: Object = this.bookId as Object;
          const indexObj: Object = (chapterIndex >= 0 ? chapterIndex : 0) as Object;
          const params: Record<string, Object> = {
            'bookId': bookIdObj,
            'chapterIndex': indexObj
          };
          this.navStack.pushPathByName('TextReaderPage', params);
          this.isStartingPlay = false;
          return;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'check source type failed');
      }
    }

    // 有声书源，跳转到播放页
    this.navStack.pushPathByName('player', this.book.id);
    try {
      if (target.source.type === 'url' && this.book.sourceUrl) {
        try {
          const sourcesJson = await PreferenceService.getBookSources();
          const sources = JSON.parse(sourcesJson) as BookSource[];
          const source = sources.find(s => s.bookSourceUrl === this.book!.sourceUrl);
          if (source) {
            const audioUrl = await BookSourceService.getAudioUrl(source, target.source.value);
            target.source = { type: 'url', value: audioUrl };
          }
        } catch (_e) { /* ignore */ }
      }
      AudioService.getInstance().bind(this.playerState, getContext(this) as common.UIAbilityContext);
      await AudioService.getInstance().playChapter(this.book, target);
    } finally {
      this.isStartingPlay = false;
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
      SymbolGlyph($r('sys.symbol.share'))
        .fontSize(22).fontColor(['#FFFFFF']).margin({ left: AppSpace.Md })
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Lg }) {
      // 封面
      if (this.book!.cover && this.book!.cover.startsWith('http')) {
        Image(this.book!.cover)
          .width(100)
          .height(130)
          .borderRadius(AppRadius.Sm)
          .objectFit(ImageFit.Cover)
          .shadow({ radius: 16, color: '#44000000', offsetY: 4 })
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

      // 书名信息
      Column({ space: AppSpace.Xs }) {
        Text(this.book!.title)
          .fontSize(AppFont.TitleL)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.book!.narrator || this.book!.author)
          .fontSize(AppFont.Body)
          .fontColor('#FFFFFFCC')
          .maxLines(1)
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
        Text(this.book!.chapterCount > 0 ? this.book!.chapterCount.toString() + (this.book!.category === 'novel' ? ' 章' : ' 集') : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text(this.book!.category === 'novel' ? '总章数' : '总集数')
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

      Text(this.book!.category === 'novel' ? '章节' : '节目')
        .fontSize(AppFont.BodyL)
        .fontColor(this.activeTab === 1 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
        .border(this.activeTab === 1
          ? { width: { bottom: 2 }, color: { bottom: AppColor.Brand } }
          : { width: { bottom: 2 }, color: { bottom: Color.Transparent } })
        .onClick(() => { this.activeTab = 1; })
    }
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: { bottom: AppColor.Divider } })
    .backgroundColor($r('sys.color.background_primary'))
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
          SymbolGlyph(this.book!.category === 'novel' ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
            .fontSize(18).fontColor(['#FFFFFF'])
          Text(this.book!.category === 'novel' ? '开始阅读' : '开始播放')
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
        Text(`共 ${this.book!.chapters.length} ${this.book!.category === 'novel' ? '章' : '集'}`)
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
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.book!.chapters, (ch: Chapter) => {
            ListItem() {
              this.buildChapterItem(ch)
            }
          }, (ch: Chapter) => ch.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
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
      // 播放/阅读 按钮
      Row() {
        SymbolGlyph(this.book!.category === 'novel'
          ? $r('sys.symbol.book')
          : (this.playerState.isPlaying && this.playerState.currentBook?.id === this.bookId
              ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill')))
          .fontSize(20).fontColor(['#FFFFFF'])
      }
      .width(40).height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.Brand)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.book!.category === 'novel') {
          this.startPlay();
          return;
        }
        if (this.playerState.currentBook?.id === this.bookId && this.playerState.currentChapter) {
          AudioService.getInstance().toggle();
        } else {
          this.startPlay();
        }
      })

      // 当前播放信息 / 默认提示
      Column({ space: 2 }) {
        if (this.book!.category !== 'novel'
            && this.playerState.currentBook?.id === this.bookId
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
          Text(this.book!.category === 'novel' ? '开始阅读' : '开始播放')
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          if (this.book!.chapters.length > 0) {
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
        .onClick(() => { this.activeTab = 1; })
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
