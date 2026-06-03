import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { AppStorageV2, LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { SearchResult, HomeBlockSection } from '../model/BookSource';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { PreferenceService } from '../service/PreferenceService';
import { DataService } from '../service/DataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { ResumeCard, ResumeCardMode } from '../components/ResumeCard';
import { BookDataSource } from '../utils/BookDataSource';
import { HomeBlockDataSource } from '../utils/HomeBlockDataSource';
import { EVT_SOURCES_CHANGED } from './SourcePage';

const DOMAIN = 0x0000;
const TAG = 'HomePage';

const HEADER_TOOLBAR_HEIGHT: number = 40;

@ComponentV2
export struct HomePage {
  @Local audioBooks: Book[] = [];
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local searchingSource: string = '';
  @Local hasSearched: boolean = false;
  @Local sourceCount: number = 0;
  @Local viewMode: number = 0; // 0=grid, 1=list
  @Local pendingCount: number = 0;
  @Local audioCount: number = 0;
  @Local homeBlocks: HomeBlockSection[] = [];
  @Local loadingHome: boolean = false;
  /** 续听卡状态（由 loadResumeState 维护） */
  @Local resumeMode: ResumeCardMode = ResumeCardMode.Empty;
  @Local resumeBook: Book | null = null;
  @Local resumeChapterTitle: string = '';
  @Local resumeProgress: number = 0;
  /** 全局播放状态（监听 currentBook 变化触发续听卡刷新） */
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;

  @Event onBookTap: (id: string) => void = () => {};
  @Event onBlockMore: (block: HomeBlockSection) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onScrollDirection: (down: boolean) => void = () => {};

  private contentScroller: Scroller = new Scroller();
  private audioDataSource: BookDataSource = new BookDataSource();
  private homeBlockDataSource: HomeBlockDataSource = new HomeBlockDataSource();
  private searchGen: number = 0;
  private homeGen: number = 0;
  private sourcesChangedHandler: () => void = () => {
    this.loadSourceCount();
    this.loadHomeBlocks();
  };
  /** 上一次滚动位置,用于判断滚动方向(向下/向上) */
  private lastScrollOffset: number = 0;
  /** 当前是否处于折叠态,避免向同方向重复触发 applyMiniBarStyle */
  private currentCollapsed: boolean = false;

  aboutToAppear(): void {
    this.loadSourceCount();
    this.loadHomeBlocks();
    emitter.on(EVT_SOURCES_CHANGED, this.sourcesChangedHandler);
    // 把滚动控制器交给上层(MainPage)绑定到 HdsTabsController
    this.onScrollerReady(this.contentScroller);
    this.loadResumeState();
  }

  aboutToDisappear(): void {
    emitter.off(EVT_SOURCES_CHANGED, this.sourcesChangedHandler);
  }

  private async loadSourceCount(): Promise<void> {
    try {
      const sources = await SourceDataService.getSources();
      // 仅统计有声书源（type=1），其它（电子书）已不再使用
      this.sourceCount = sources.filter(s => s.bookSourceType === 1 && s.enabled !== false).length;
    } catch (_e) {
      this.sourceCount = 0;
    }
  }

  private async loadHomeBlocks(): Promise<void> {
    this.homeGen++;
    const gen = this.homeGen;
    if (this.homeBlocks.length === 0) this.loadingHome = true;
    hilog.info(DOMAIN, TAG, 'loadHomeBlocks: gen=%{public}d start', gen);
    this.homeBlocks = [];
    this.homeBlockDataSource.clear();
    try {
      await BookSourceService.streamAllHomeBlocks((blocks, source) => {
        if (gen !== this.homeGen) return;
        this.homeBlocks = this.homeBlocks.concat(blocks);
        this.homeBlockDataSource.appendBlocks(blocks);
        this.loadingHome = false;
        hilog.info(DOMAIN, TAG, 'loadHomeBlocks: +%{public}d from %{public}s, total=%{public}d',
          blocks.length, source.bookSourceName, this.homeBlocks.length);
        // 首板块到货 → 若续听卡仍是 Empty,触发 Suggest 兜底
        if (this.resumeMode === ResumeCardMode.Empty) {
          this.loadResumeState();
        }
      });
      if (gen !== this.homeGen) return;
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: done total=%{public}d', this.homeBlocks.length);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadHomeBlocks failed: %{public}s', String(e));
    } finally {
      if (gen === this.homeGen) {
        this.loadingHome = false;
      }
    }
  }

  private clearSearch(): void {
    this.searchGen++;
    this.searching = false;
    this.searchingSource = '';
    this.hasSearched = false;
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
    this.pendingCount = 0;
  }

  private homeBookFromResult(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const idHash = this.hashSearchKey(r.sourceUrl || '', r.bookUrl || r.name);
    const book: Book = {
      id: `home_audio_${idHash}`,
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: 'audio',
      intro: r.intro || '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [r.sourceName],
      chapters: emptyChapters,
      bookUrl: r.bookUrl,
      sourceUrl: r.sourceUrl,
      variables: r.variables,
    };
    SearchCache.put(book);
    return book;
  }

  private async doSearch(): Promise<void> {
    if (!this.keyword.trim()) {
      this.clearSearch();
      return;
    }
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.searchingSource = '';
    this.hasSearched = true;
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getSources();
      const audioSources =
        sources.filter(s => s.bookSourceType === 1 && s.enabled !== false);
      this.pendingCount = audioSources.length;

      if (this.pendingCount === 0) {
        this.searching = false;
        return;
      }

      for (const source of audioSources) {
        BookSourceService.searchBooks(source, this.keyword.trim())
          .then((r: SearchResult[]) => {
            if (gen !== this.searchGen) return;
            this.searchingSource = source.bookSourceName;
            if (r && r.length > 0) {
              const books = r.map((item) => this.searchResultToBook(item));
              this.audioBooks = this.audioBooks.concat(books);
              this.audioCount = this.audioBooks.length;
              this.audioDataSource.appendBooks(books);
              hilog.info(DOMAIN, TAG, '[audio] +%{public}d from %{public}s, total=%{public}d',
                books.length, source.bookSourceName, this.audioCount);
            }
          })
          .catch((_e: Object) => {
            if (gen !== this.searchGen) return;
            this.searchingSource = source.bookSourceName;
          })
          .finally(() => {
            if (gen !== this.searchGen) return;
            this.pendingCount--;
            if (this.pendingCount <= 0) {
              this.searching = false;
              this.searchingSource = '';
              hilog.info(DOMAIN, TAG, 'search done: audio=%{public}d', this.audioCount);
            }
          });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
      this.audioBooks = [];
      this.searching = false;
      this.searchingSource = '';
    }
  }

  private searchResultToBook(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const idHash = this.hashSearchKey(r.sourceUrl || '', r.bookUrl || r.name);
    const book: Book = {
      id: `search_audio_${idHash}`,
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: 'audio',
      intro: r.intro || '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [r.sourceName],
      chapters: emptyChapters,
      bookUrl: r.bookUrl,
      sourceUrl: r.sourceUrl,
      variables: r.variables,
    };
    SearchCache.put(book);
    return book;
  }

  private hashSearchKey(sourceUrl: string, bookUrl: string): string {
    const raw = `${sourceUrl}::${bookUrl}`;
    let h: number = 5381;
    for (let i = 0; i < raw.length; i++) {
      h = (((h << 5) + h) + raw.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(36);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // L0 暖色渐变背景层（满屏，覆盖到状态栏）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [HomeTheme.BgWarmTop, 0.0],
            [HomeTheme.BgWarmMid, 0.35],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      // L1 原 HdsNavigation
      HdsNavigation() {
        List({ scroller: this.contentScroller }) {
        // 第1项：搜索框 + (条件) 工具栏 —— 跟随滚动，滚到标题"首页"后方产生沉浸光感
        ListItem() {
          Column() {
            Search({ value: this.keyword!!, placeholder: '搜索书籍、作者...' })
              .searchButton('搜索')
              .onSubmit(() => this.doSearch())
              .onChange((value: string) => {
                this.keyword = value;
                if (value.length === 0 && this.hasSearched) {
                  this.clearSearch();
                }
              })
              .height(40)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(AppRadius.Lg)
              .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })

            if (this.hasSearched && this.audioCount > 0) {
              Row() {
                Text(`有声书 ${this.audioCount}`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_secondary'))
                if (this.searching) {
                  LoadingProgress()
                    .width(18).height(18)
                    .color($r('sys.color.brand'))
                    .margin({ left: AppSpace.Xs })
                }
                Blank()
                SymbolGlyph(this.viewMode === 0
                  ? $r('sys.symbol.list_bullet')
                  : $r('sys.symbol.square_grid_2x2'))
                  .fontSize(18)
                  .fontColor([$r('sys.color.font_primary')])
                  .padding(8)
                  .borderRadius(18)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .onClick(() => {
                    this.getUIContext()?.animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard },
                      () => { this.viewMode = this.viewMode === 0 ? 1 : 0; });
                  })
              }
              .width('100%')
              .height(HEADER_TOOLBAR_HEIGHT)
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
              .alignItems(VerticalAlign.Center)
            }
          }
          .width('100%')
        }

        // 第1.5项：续听卡 / 今日推荐（仅推荐态，且非 Empty）
        if (!this.hasSearched && this.resumeMode !== ResumeCardMode.Empty) {
          ListItem() {
            ResumeCard({
              mode: this.resumeMode,
              book: this.resumeBook,
              chapterTitle: this.resumeChapterTitle,
              progress: this.resumeProgress,
              onTapBody: () => this.onResumeBodyTap(),
              onTapPlay: () => this.onResumePlayTap()
            })
          }
        }

        // 第2~N项：内容主体（推荐板块 / 搜索结果 / 空态）
        if (this.searching && this.audioBooks.length === 0) {
          ListItem() {
            this.buildSearchingState()
          }
        } else if (this.hasSearched && this.audioBooks.length === 0 && !this.searching) {
          ListItem() {
            this.buildNoResultState()
          }
        } else if (this.hasSearched) {
          // 搜索结果：直接渲染为 ListItem
          if (this.viewMode === 0) {
            // Grid 模式：用单个 ListItem 包裹 Grid
            ListItem() {
              Grid() {
                LazyForEach(this.audioDataSource, (book: Book, idx: number) => {
                  GridItem() {
                    BookCard({
                      book: book,
                      indexHint: idx,
                      onTap: () => this.onBookTap(book.id)
                    })
                  }
                }, (book: Book) => book.id)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(AppSpace.Sm)
              .rowsGap(AppSpace.Md)
              .width('100%')
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }
          } else {
            // List 模式：每本书一个 ListItem
            LazyForEach(this.audioDataSource, (book: Book) => {
              ListItem() {
                this.buildListItem(book)
              }
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
            }, (book: Book) => book.id)
          }
        } else {
          // 推荐板块或空态
          if (this.loadingHome && this.homeBlocks.length === 0) {
            ListItem() {
              Column() {
                LoadingProgress().width(40).height(40).color($r('sys.color.brand'))
                Text('加载推荐中...')
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: AppSpace.Sm })
              }
              .width('100%')
              .height(300)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.homeBlocks.length > 0) {
            // 推荐板块：每个板块一个 ListItem
            LazyForEach(this.homeBlockDataSource, (block: HomeBlockSection, idx: number) => {
              ListItem() {
                this.buildHomeBlock(block, idx)
              }
              .margin({ bottom: AppSpace.Lg })
            }, (block: HomeBlockSection, idx: number) => `${block.sourceUrl}#${block.title}#${idx}`)
          } else {
            ListItem() {
              Column() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(48)
                  .fontColor([$r('sys.color.font_tertiary')])
                Text('搜索你想听的书')
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: AppSpace.Md })
                if (this.sourceCount > 0) {
                  Text(`已启用 ${this.sourceCount} 个书源`)
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Xs })
                } else {
                  Text('请先添加书源')
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Xs })
                }
              }
              .width('100%')
              .height(300)
              .justifyContent(FlexAlign.Center)
            }
          }
        }

        // 底部留白避开浮动 Tab + MiniPlayer
        ListItem() {
          Column().height(WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg)
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onScroll(() => {
        // 阈值过滤抖动,只关心明确的方向
        const offset = this.contentScroller.currentOffset().yOffset;
        const delta = offset - this.lastScrollOffset;
        const THRESHOLD = 6;

        if (offset <= 0 || delta < -THRESHOLD) {
          // 顶部 或 向上滑动 → 展开
          if (this.currentCollapsed) {
            this.currentCollapsed = false;
            this.onScrollDirection(false);
          }
        } else if (delta > THRESHOLD) {
          // 向下滑动 → 折叠
          if (!this.currentCollapsed) {
            this.currentCollapsed = true;
            this.onScrollDirection(true);
          }
        }
        this.lastScrollOffset = offset;
      })
      .cachedCount(5)
      .clip(false) // 允许内容穿透到标题栏下方产生光感效果
      .backgroundColor(Color.Transparent) // 让 L0 暖色渐变透出
    }
    .titleBar({
      content: {
        title: { mainTitle: '首页' }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      enableComponentSafeArea: true
    })
    .bindToScrollable([this.contentScroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  @Builder
  buildSearchingState() {
    Column() {
      LoadingProgress().width(40).height(40).color($r('sys.color.brand'))
      if (this.searchingSource) {
        Text(`正在搜索 ${this.searchingSource}`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Sm })
      } else {
        Text('正在搜索...')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Sm })
      }
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildNoResultState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text('未找到相关书籍')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Md })
      Text('试试其他关键词')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Xs })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildHomeBlock(block: HomeBlockSection, blockIdx: number) {
    Column({ space: AppSpace.Sm }) {
      // 板块标题行
      Row() {
        Text(block.title)
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(` · ${block.sourceName}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        Blank()
        if (block.moreUrl) {
          Text('更多 ›')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 4, bottom: 4 })
            .onClick(() => this.onBlockMore(block))
        }
      }
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
      .alignItems(VerticalAlign.Center)

      // 板块内容
      if (block.layout === 'grid') {
        // 大卡片 + 简介：竖向 List
        Column({ space: AppSpace.Sm }) {
          ForEach(block.books, (r: SearchResult) => {
            this.buildHomeListItem(r)
          }, (r: SearchResult) => `${block.sourceUrl}#${r.bookUrl}`)
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
      } else {
        // 横向滚动小封面
        Scroll() {
          Row({ space: AppSpace.Sm }) {
            ForEach(block.books, (r: SearchResult, i?: number) => {
              this.buildHomeCoverCard(r, blockIdx * 1000 + (i ?? 0))
            }, (r: SearchResult) => `${block.sourceUrl}#${r.bookUrl}`)
          }
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  buildHomeCoverCard(r: SearchResult, indexHint: number) {
    Column({ space: 4 }) {
      BookCard({
        book: this.homeBookFromResult(r),
        cardWidth: 100,
        indexHint: indexHint,
        onTap: () => {
          const book = this.homeBookFromResult(r);
          this.onBookTap(book.id);
        }
      })
    }
    .width(100)
  }

  @Builder
  buildHomeListItem(r: SearchResult) {
    Row({ space: AppSpace.Md }) {
      if (r.coverUrl && r.coverUrl.startsWith('http')) {
        Image(r.coverUrl)
          .width(72)
          .height(100)
          .borderRadius(AppRadius.Sm)
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          Column().width('100%').height('100%').backgroundColor($r('sys.color.brand'))
          Text(r.name ? r.name.substring(0, 1) : '?')
            .fontSize(24).fontColor($r('sys.color.font_on_primary')).fontWeight(FontWeight.Bold)
        }
        .width(72).height(100).borderRadius(AppRadius.Sm).clip(true)
      }
      Column({ space: 4 }) {
        Text(r.name)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (r.author) {
          Text(r.author)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (r.intro) {
          Text(r.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
    .onClick(() => {
      const book = this.homeBookFromResult(r);
      this.onBookTap(book.id);
    })
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width(72)
            .height(100)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('sys.color.brand'))
            Text(book.title ? book.title.substring(0, 1) : '?')
              .fontSize(24)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width(72)
          .height(100)
          .borderRadius(AppRadius.Sm)
          .clip(true)
        }
        if (book.narrator) {
          Text(book.narrator)
            .fontSize(9)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('sys.color.ohos_id_color_mask_thin'))
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Sm })
        }
      }

      Column({ space: 4 }) {
        Text(book.title)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(book.author)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (book.intro) {
          Text(book.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .onClick(() => this.onBookTap(book.id))
  }

  @Monitor('playerState.currentBook')
  onCurrentBookChange(): void {
    this.loadResumeState();
  }

  private async loadResumeState(): Promise<void> {
    // 1) 优先：lastPlayed 还原
    try {
      const last = await PreferenceService.getLastPlayed();
      if (last && last.bookId) {
        const book = await this.restoreBookById(last.bookId);
        if (book) {
          this.resumeBook = book;
          this.resumeChapterTitle = last.chapterTitle ?? '';
          const dur = last.durationMs ?? 0;
          this.resumeProgress = dur > 0 ? Math.max(0, Math.min(1, last.progressMs / dur)) : 0;
          this.resumeMode = ResumeCardMode.Resume;
          return;
        }
      }
    } catch (_e) {
      // 还原失败兜底走 Suggest
    }

    // 2) 兜底：homeBlocks[0].books[0] → Suggest
    if (this.homeBlocks.length > 0 && this.homeBlocks[0].books.length > 0) {
      const r = this.homeBlocks[0].books[0];
      this.resumeBook = this.homeBookFromResult(r);
      this.resumeChapterTitle = '';
      this.resumeProgress = 0;
      this.resumeMode = ResumeCardMode.Suggest;
      return;
    }

    // 3) 都没有：Empty
    this.resumeMode = ResumeCardMode.Empty;
    this.resumeBook = null;
  }

  private async restoreBookById(bookId: string): Promise<Book | null> {
    // 优先内存 SearchCache（同步，最快）
    const cached = SearchCache.get(bookId);
    if (cached) return cached;
    // 兜底走 DataService（覆盖收藏 / 历史 / cachedBooks）
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext | undefined;
      if (!ctx) return null;
      const found = await DataService.getBookById(ctx, bookId);
      return found ?? null;
    } catch (_e) {
      return null;
    }
  }

  private onResumeBodyTap(): void {
    if (!this.resumeBook) return;
    this.onBookTap(this.resumeBook.id);
  }

  private onResumePlayTap(): void {
    if (!this.resumeBook) return;
    // Resume 模式带 progress 续播；Suggest 模式仅路由（详情页负责后续）
    // 路由仍走 onBookTap 回调，progressMs 由 PlaybackStore + 详情页恢复，
    // 与现有"返回首页继续播"路径一致，避免引入新事件协议。
    this.onBookTap(this.resumeBook.id);
  }
}
