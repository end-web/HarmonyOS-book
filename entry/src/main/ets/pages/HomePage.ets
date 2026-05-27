import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { SearchResult } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';

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

  @Event onBookTap: (id: string) => void = () => {};

  private readonly COLLAPSE_HEIGHT: number = 88; // 标题 32 + 搜索 40 + 间隔 16
  private readonly TAB_HEIGHT: number = 40;

  private textScroller: Scroller = new Scroller();
  private audioScroller: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.loadSourceCount();
  }

  private async loadSourceCount(): Promise<void> {
    try {
      const sources = await SourceDataService.getSources();
      this.sourceCount =
        sources.filter(s => s.bookSourceType === 0 && s.enabled !== false).length;
    } catch (_e) {
      this.sourceCount = 0;
    }
  }

  private async doSearch(): Promise<void> {
    if (!this.keyword.trim()) return;
    this.searching = true;
    this.searchingSource = '';
    this.hasSearched = true;
    this.textBooks = [];
    this.audioBooks = [];
    this.headerOffset = 0;
    try {
      const sources = await SourceDataService.getSources();
      const textSources =
        sources.filter(s => s.bookSourceType === 0 && s.enabled !== false);
      const audioSources =
        sources.filter(s => s.bookSourceType === 1 && s.enabled !== false);

      const textTasks = textSources.map((source) => {
        return BookSourceService.searchBooks(source, this.keyword.trim())
          .then((r: SearchResult[]) => {
            this.searchingSource = source.bookSourceName;
            return r;
          })
          .catch((_e: Object) => {
            this.searchingSource = source.bookSourceName;
            const empty: SearchResult[] = [];
            return empty;
          });
      });

      const audioTasks = audioSources.map((source) => {
        return BookSourceService.searchBooks(source, this.keyword.trim())
          .then((r: SearchResult[]) => {
            this.searchingSource = source.bookSourceName;
            return r;
          })
          .catch((_e: Object) => {
            this.searchingSource = source.bookSourceName;
            const empty: SearchResult[] = [];
            return empty;
          });
      });

      const allText = await Promise.all(textTasks);
      const textResults: SearchResult[] = [];
      for (const r of allText) {
        if (r && r.length > 0) textResults.push(...r);
      }
      const allAudio = await Promise.all(audioTasks);
      const audioResults: SearchResult[] = [];
      for (const r of allAudio) {
        if (r && r.length > 0) audioResults.push(...r);
      }

      this.textBooks =
        textResults.map((r) => this.searchResultToBook(r, 'novel'));
      this.audioBooks =
        audioResults.map((r) => this.searchResultToBook(r, 'audio'));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
      this.textBooks = [];
      this.audioBooks = [];
    }
    this.searching = false;
    this.searchingSource = '';
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
      sourceUrl: r.sourceUrl
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
    const y = scroller.currentOffset().yOffset;
    let h = y;
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
    const showTab = this.hasSearched && !this.searching;
    return WindowUtils.getStatusBarHeightVp()
      + this.COLLAPSE_HEIGHT
      + (showTab ? this.TAB_HEIGHT : 0);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容层
      if (this.searching) {
        this.buildSearchingState()
      } else if (this.hasSearched
        && this.textBooks.length === 0
        && this.audioBooks.length === 0) {
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
      if (this.hasSearched && !this.searching) {
        Row() {
          this.tabBarItem('电子书', this.textBooks.length, 0)
          this.tabBarItem('有声书', this.audioBooks.length, 1)
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
            .onClick(() => { this.viewMode = this.viewMode === 0 ? 1 : 0; })
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
  tabBarItem(title: string, count: number, idx: number) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.resultTab === idx ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.resultTab === idx ? Color.White : $r('sys.color.font_primary'))
      if (count > 0) {
        Text(` ${count}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resultTab === idx ? Color.White : $r('sys.color.font_tertiary'))
      }
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor(this.resultTab === idx ? '#E6000000' : '#B3FFFFFF')
    .backdropBlur(this.collapseRatio() > 0.5 ? (this.resultTab === idx ? 20 : 15) : 0)
    .border({ width: 0.5, color: this.resultTab === idx ? '#33FFFFFF' : '#33000000' })
    .shadow(this.resultTab === idx
      ? { radius: 6, color: '#33000000', offsetY: 2 }
      : { radius: 4, color: '#11000000', offsetY: 1 })
    .margin({ right: AppSpace.Sm })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.resultTab !== idx) {
        this.swiperController.changeIndex(idx, true);
      }
    })
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
      this.buildResultListScroll(this.textBooks, this.textScroller)
      this.buildResultListScroll(this.audioBooks, this.audioScroller)
    }
    .index(this.resultTab)
    .indicator(false)
    .loop(false)
    .duration(220)
    .onChange((index: number) => {
      this.resultTab = index;
      const s = index === 0 ? this.textScroller : this.audioScroller;
      this.updateHeaderOffset(s);
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  buildResultListScroll(books: Book[], scroller: Scroller) {
    if (books.length === 0) {
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
      Scroll(scroller) {
        Grid() {
          ForEach(books, (book: Book, idx?: number) => {
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
          bottom: AppSpace.Xl
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.updateHeaderOffset(scroller);
      })
    } else {
      Scroll(scroller) {
        Column({ space: 0 }) {
          ForEach(books, (book: Book) => {
            this.buildListItem(book)
          }, (book: Book) => book.id)
        }
        .width('100%')
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: this.contentTopPadding() + AppSpace.Sm,
          bottom: AppSpace.Xl
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDidScroll(() => {
        this.updateHeaderOffset(scroller);
      })
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
