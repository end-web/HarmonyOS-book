import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { SearchResult } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { BookDataSource } from '../utils/BookDataSource';
import { EVT_SOURCES_CHANGED } from './SourcePage';

const DOMAIN = 0x0000;
const TAG = 'HomePage';

@ComponentV2
export struct HomePage {
  @Local textBooks: Book[] = [];
  @Local audioBooks: Book[] = [];
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local searchingSource: string = '';
  @Local hasSearched: boolean = false;
  @Local sourceCount: number = 0;
  @Local resultTab: number = 0;
  @Local headerOffset: number = 0;
  @Local viewMode: number = 0; // 0=grid, 1=list
  @Local pendingCount: number = 0;
  @Local textCount: number = 0;
  @Local audioCount: number = 0;
  @Local isRefreshingText: boolean = false;
  @Local isRefreshingAudio: boolean = false;

  @Event onBookTap: (id: string) => void = () => {};

  private readonly COLLAPSE_HEIGHT: number = 88; // 标题 32 + 搜索 40 + 间隔 16
  private readonly TAB_HEIGHT: number = 40;

  private textScroller: Scroller = new Scroller();
  private audioScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();
  private textDataSource: BookDataSource = new BookDataSource();
  private audioDataSource: BookDataSource = new BookDataSource();
  private searchGen: number = 0;
  private sourcesChangedHandler: () => void = () => this.loadSourceCount();

  aboutToAppear(): void {
    this.loadSourceCount();
    emitter.on(EVT_SOURCES_CHANGED, this.sourcesChangedHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_SOURCES_CHANGED, this.sourcesChangedHandler);
  }

  private async loadSourceCount(): Promise<void> {
    try {
      const sources = await SourceDataService.getSources();
      // 与 doSearch 里的过滤口径保持一致：电子书 + 有声书
      this.sourceCount = sources.filter(s =>
        (s.bookSourceType === 0 || s.bookSourceType === 1) && s.enabled !== false
      ).length;
    } catch (_e) {
      this.sourceCount = 0;
    }
  }

  private async doSearch(): Promise<void> {
    if (!this.keyword.trim()) return;
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.searchingSource = '';
    this.hasSearched = true;
    this.textBooks = [];
    this.audioBooks = [];
    this.textCount = 0;
    this.audioCount = 0;
    this.textDataSource.clear();
    this.audioDataSource.clear();
    this.headerOffset = 0;
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getSources();
      const textSources =
        sources.filter(s => s.bookSourceType === 0 && s.enabled !== false);
      const audioSources =
        sources.filter(s => s.bookSourceType === 1 && s.enabled !== false);
      this.pendingCount = textSources.length + audioSources.length;

      if (this.pendingCount === 0) {
        this.searching = false;
        return;
      }

      for (const source of textSources) {
        BookSourceService.searchBooks(source, this.keyword.trim())
          .then((r: SearchResult[]) => {
            if (gen !== this.searchGen) return;
            this.searchingSource = source.bookSourceName;
            if (r && r.length > 0) {
              const books = r.map((item) => this.searchResultToBook(item, 'novel'));
              this.textBooks = this.textBooks.concat(books);
              this.textCount = this.textBooks.length;
              this.textDataSource.appendBooks(books);
              hilog.info(DOMAIN, TAG, '[text] +%{public}d from %{public}s, total=%{public}d',
                books.length, source.bookSourceName, this.textCount);
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
              this.isRefreshingText = false;
              this.isRefreshingAudio = false;
              hilog.info(DOMAIN, TAG, 'search done: text=%{public}d audio=%{public}d',
                this.textCount, this.audioCount);
            }
          });
      }

      for (const source of audioSources) {
        BookSourceService.searchBooks(source, this.keyword.trim())
          .then((r: SearchResult[]) => {
            if (gen !== this.searchGen) return;
            this.searchingSource = source.bookSourceName;
            if (r && r.length > 0) {
              const books = r.map((item) => this.searchResultToBook(item, 'audio'));
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
              this.isRefreshingText = false;
              this.isRefreshingAudio = false;
              hilog.info(DOMAIN, TAG, 'search done: text=%{public}d audio=%{public}d',
                this.textCount, this.audioCount);
            }
          });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
      this.textBooks = [];
      this.audioBooks = [];
      this.searching = false;
      this.searchingSource = '';
    }
  }

  private searchResultToBook(r: SearchResult, category: string): Book {
    const emptyChapters: Chapter[] = [];
    const idHash = this.hashSearchKey(r.sourceUrl || '', r.bookUrl || r.name);
    const book: Book = {
      id: `search_${category}_${idHash}`,
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: category,
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

  private updateHeaderOffset(scroller: Scroller): void {
    const offset = scroller.currentOffset();
    if (!offset) return;
    let h = offset.yOffset;
    if (h < 0) h = 0;
    if (h > this.COLLAPSE_HEIGHT) h = this.COLLAPSE_HEIGHT;
    if (Math.abs(h - this.headerOffset) >= 0.5) {
      this.headerOffset = h;
    }
  }

  private collapseRatio(): number {
    return this.headerOffset / this.COLLAPSE_HEIGHT;
  }

  private contentTopPadding(): number {
    const showTab = this.hasSearched && (this.textCount > 0 || this.audioCount > 0);
    return WindowUtils.getStatusBarHeightVp()
      + this.COLLAPSE_HEIGHT
      + (showTab ? this.TAB_HEIGHT : 0);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容层
      if (this.searching && this.textBooks.length === 0 && this.audioBooks.length === 0) {
        this.buildSearchingState()
      } else if (this.hasSearched
        && this.textBooks.length === 0
        && this.audioBooks.length === 0
        && !this.searching) {
        this.buildNoResultState()
      } else if (this.hasSearched) {
        this.buildResultsSwiper()
      } else {
        this.buildEmptyPlaceholder()
      }

      // 顶部浮层(标题 + 搜索框 + Tab)
      this.buildTopHeader()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildTopHeader() {
    Column() {
      // 状态栏占位
      Blank().height(WindowUtils.getStatusBarHeightVp())

      // 折叠区:首页标题 + 搜索框
      Column() {
        Row() {
          Text('首页')
            .fontSize(AppFont.TitleL)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        .height(32)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .alignItems(VerticalAlign.Center)

        Search({ value: this.keyword!!, placeholder: '搜索书籍、作者...' })
          .searchButton('搜索')
          .onSubmit(() => this.doSearch())
          .height(40)
          .margin({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: AppSpace.Xs,
            bottom: AppSpace.Xs
          })
      }
      .width('100%')
      .height(this.COLLAPSE_HEIGHT * (1 - this.collapseRatio()))
      .opacity(1 - this.collapseRatio())
      .clip(true)
      .animation({ duration: 0, curve: Curve.Linear })

      // Tab 行(仅在有搜索结果时显示,折叠后贴到状态栏下)
      if (this.hasSearched && (this.textCount > 0 || this.audioCount > 0)) {
        Row() {
          // 电子书 tab
          Row() {
            Text('电子书')
              .fontSize(14)
              .fontWeight(this.resultTab === 0 ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.resultTab === 0 ? Color.White : $r('sys.color.font_primary'))
            if (!this.searching && this.textCount > 0) {
              Text(` ${this.textCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.resultTab === 0 ? Color.White : $r('sys.color.font_tertiary'))
            }
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(this.resultTab === 0 ? '#E6000000' : '#B3FFFFFF')
          .border({ width: 0.5, color: this.resultTab === 0 ? '#33FFFFFF' : '#33000000' })
          .margin({ right: AppSpace.Sm })
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            if (this.resultTab !== 0) {
              this.swiperController.changeIndex(0, true);
            }
          })
          // 有声书 tab
          Row() {
            Text('有声书')
              .fontSize(14)
              .fontWeight(this.resultTab === 1 ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.resultTab === 1 ? Color.White : $r('sys.color.font_primary'))
            if (!this.searching && this.audioCount > 0) {
              Text(` ${this.audioCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.resultTab === 1 ? Color.White : $r('sys.color.font_tertiary'))
            }
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(this.resultTab === 1 ? '#E6000000' : '#B3FFFFFF')
          .border({ width: 0.5, color: this.resultTab === 1 ? '#33FFFFFF' : '#33000000' })
          .margin({ right: AppSpace.Sm })
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            if (this.resultTab !== 1) {
              this.swiperController.changeIndex(1, true);
            }
          })
          if (this.searching) {
            LoadingProgress().width(18).height(18).color(AppColor.Brand)
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
            .backgroundColor('#B3FFFFFF')
            .backdropBlur(this.collapseRatio() > 0.5 ? 15 : 0)
            .border({ width: 0.5, color: '#33000000' })
            .onClick(() => {
              animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard },
                () => { this.viewMode = this.viewMode === 0 ? 1 : 0; });
            })
        }
        .width('100%')
        .height(this.TAB_HEIGHT)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
  }

  @Builder
  buildEmptyPlaceholder() {
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
    .height('100%')
    .padding({ top: this.contentTopPadding() })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSearchingState() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColor.Brand)
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
    .height('100%')
    .padding({ top: this.contentTopPadding() })
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
    .height('100%')
    .padding({ top: this.contentTopPadding() })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildResultsSwiper() {
    Swiper(this.swiperController) {
      this.buildTextResults()
      this.buildAudioResults()
    }
    .index(this.resultTab)
    .indicator(false)
    .loop(false)
    .duration(220)
    .onChange((index: number) => {
      this.resultTab = index;
      const hasContent = index === 0 ? this.textCount > 0 : this.audioCount > 0;
      if (!hasContent) {
        this.headerOffset = 0;
        return;
      }
      const s = index === 0 ? this.textScroller : this.audioScroller;
      this.updateHeaderOffset(s);
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTextResults() {
    if (this.textBooks.length === 0 && !this.searching) {
      Column() {
        Text('该分类暂无结果')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.contentTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else if (this.viewMode === 0) {
      Refresh({ refreshing: $$this.isRefreshingText }) {
        Scroll(this.textScroller) {
          Grid() {
            ForEach(this.textBooks, (book: Book, idx?: number) => {
              GridItem() {
                BookCard({
                  book: book,
                  indexHint: idx ?? 0,
                  onTap: () => this.onBookTap(book.id)
                })
              }
            }, (book: Book) => book.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(AppSpace.Sm)
          .rowsGap(AppSpace.Md)
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: this.contentTopPadding() + AppSpace.Sm,
            bottom: WindowUtils.getFloatingTabBottomVp()
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onDidScroll(() => {
          this.updateHeaderOffset(this.textScroller);
        })
      }
      .onRefreshing(() => {
        if (this.searching) { this.isRefreshingText = false; return; }
        this.doSearch();
      })
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY)
    } else {
      Refresh({ refreshing: $$this.isRefreshingText }) {
        List({ scroller: this.textScroller }) {
          ListItem() {
            Column().height(this.contentTopPadding() + AppSpace.Sm)
          }
          LazyForEach(this.textDataSource, (book: Book) => {
            ListItem() {
              this.buildListItem(book)
            }
          }, (book: Book) => book.id)
          ListItem() {
            Column().height(WindowUtils.getFloatingTabBottomVp())
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(8)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .onDidScroll(() => {
          this.updateHeaderOffset(this.textScroller);
        })
      }
      .onRefreshing(() => {
        if (this.searching) { this.isRefreshingText = false; return; }
        this.doSearch();
      })
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY)
    }
  }

  @Builder
  buildAudioResults() {
    if (this.audioBooks.length === 0 && !this.searching) {
      Column() {
        Text('该分类暂无结果')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.contentTopPadding() })
      .justifyContent(FlexAlign.Center)
    } else if (this.viewMode === 0) {
      Refresh({ refreshing: $$this.isRefreshingAudio }) {
        Scroll(this.audioScroller) {
          Grid() {
            ForEach(this.audioBooks, (book: Book, idx?: number) => {
              GridItem() {
                BookCard({
                  book: book,
                  indexHint: idx ?? 0,
                  onTap: () => this.onBookTap(book.id)
                })
              }
            }, (book: Book) => book.id)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(AppSpace.Sm)
          .rowsGap(AppSpace.Md)
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: this.contentTopPadding() + AppSpace.Sm,
            bottom: WindowUtils.getFloatingTabBottomVp()
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onDidScroll(() => {
          this.updateHeaderOffset(this.audioScroller);
        })
      }
      .onRefreshing(() => {
        if (this.searching) { this.isRefreshingAudio = false; return; }
        this.doSearch();
      })
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY)
    } else {
      Refresh({ refreshing: $$this.isRefreshingAudio }) {
        List({ scroller: this.audioScroller }) {
          ListItem() {
            Column().height(this.contentTopPadding() + AppSpace.Sm)
          }
          LazyForEach(this.audioDataSource, (book: Book) => {
            ListItem() {
              this.buildListItem(book)
            }
          }, (book: Book) => book.id)
          ListItem() {
            Column().height(WindowUtils.getFloatingTabBottomVp())
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(8)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .onDidScroll(() => {
          this.updateHeaderOffset(this.audioScroller);
        })
      }
      .onRefreshing(() => {
        if (this.searching) { this.isRefreshingAudio = false; return; }
        this.doSearch();
      })
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY)
    }
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
              .backgroundColor(AppColor.Brand)
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
            .backgroundColor('#99000000')
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
}
