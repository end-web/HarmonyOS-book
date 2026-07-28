import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRadius, AppSpace, AppFont, AppColor } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { SearchResult } from '../model/BookSource';
import { SourceDataService } from '../service/SourceDataService';
import { BookSourceService } from '../service/BookSourceService';
import { SearchCache } from '../utils/SearchCache';
import { BookDataSource } from '../utils/BookDataSource';
import { BookCard } from '../components/BookCard';
import { WindowUtils } from '../utils/WindowUtils';
import { PlaybackStore } from '../service/PlaybackStore';

const DOMAIN = 0x0000;
const TAG = 'BlockMorePage';

@ComponentV2
export struct BlockMorePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Param sourceName: string = '';
  @Param title: string = '';
  @Param moreUrl: string = '';

  @Local books: Book[] = [];
  @Local loading: boolean = true;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMsg: string = '';

  private dataSource: BookDataSource = new BookDataSource();
  private nextUrl: string = '';
  private nextPage: number = 2;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.nextUrl = this.moreUrl;
    this.nextPage = 2;
    this.loading = true;
    this.loadFirstPage();
  }

  private async loadFirstPage(): Promise<void> {
    if (!this.moreUrl || !this.sourceUrl) {
      this.errorMsg = '参数错误';
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    this.books = [];
    this.dataSource.clear();
    BookCard.resetAnimations();
    this.nextPage = 2;
    await this.fetchPage(this.moreUrl, false);
    this.loading = false;
  }

  private async loadNextPage(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore || !this.nextUrl) return;
    this.loadingMore = true;
    await this.fetchPage(this.nextUrl, true);
    this.loadingMore = false;
  }

  private async fetchPage(url: string, append: boolean): Promise<void> {
    try {
      const sources = await SourceDataService.getSources();
      const source = sources.find((s) => s.bookSourceUrl === this.sourceUrl);
      if (!source) {
        this.errorMsg = '听友 FM 暂不可用';
        this.hasMore = false;
        return;
      }

      const newBooks: Book[] = [];
      const page = append ? this.nextPage : 1;
      const result = await BookSourceService.getExploreBooksByUrl(source, url, page);
      for (const item of result.books) {
        newBooks.push(this.searchResultToBook(item));
      }
      const nextUrl = result.nextUrl || '';
      this.nextPage = result.nextPage ?? (page + 1);

      if (append) {
        this.books = this.books.concat(newBooks);
        this.dataSource.appendBooks(newBooks);
      } else {
        this.books = newBooks;
        this.dataSource.setBooks(newBooks);
      }
      this.nextUrl = nextUrl;
      this.hasMore = this.nextUrl.length > 0 && newBooks.length > 0;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'fetchPage failed: %{public}s', msg);
      if (!append) this.errorMsg = '加载失败：' + msg;
      this.hasMore = false;
    }
  }

  private hashSearchKey(sourceUrl: string, bookUrl: string): string {
    const raw = `${sourceUrl}::${bookUrl}`;
    let h: number = 5381;
    for (let i = 0; i < raw.length; i++) {
      h = (((h << 5) + h) + raw.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(36);
  }

  private searchResultToBook(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const idHash = this.hashSearchKey(r.sourceUrl || '', r.bookUrl || r.name);
    const book: Book = {
      id: `home_audio_${idHash}`,
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: 'audio',
      contentType: 'audio',
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

  private handleBookTap(bookId: string): void {
    if (PlaybackStore.getInstance().isCurrentBook(bookId)) {
      this.navStack.pushPathByName('player', bookId);
      return;
    }
    this.navStack.pushPathByName('detail', bookId);
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .padding(4)
          .onClick(() => this.navStack.pop())
        Column({ space: 2 }) {
          Text(this.title || '更多')
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.sourceName) {
            Text(this.sourceName)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm
      })

      if (this.loading && this.books.length === 0) {
        this.buildLoading()
      } else if (this.errorMsg && this.books.length === 0) {
        this.buildError()
      } else if (this.books.length === 0) {
        this.buildEmpty()
      } else {
        this.buildGrid()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildEmpty() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text('暂无内容')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
      Text(this.moreUrl)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        .textAlign(TextAlign.Center)
      Text('点击重试')
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .borderRadius(AppRadius.Md)
        .onClick(() => this.loadFirstPage())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColor.Brand)
      Text('加载中...')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Sm })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildError() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(this.errorMsg)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
      Text('点击重试')
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .borderRadius(AppRadius.Md)
        .onClick(() => this.loadFirstPage())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGrid() {
    Grid(this.scroller) {
      LazyForEach(this.dataSource, (book: Book, idx: number) => {
        GridItem() {
          BookCard({
            book: book,
            indexHint: idx,
            onTap: () => this.handleBookTap(book.id)
          })
        }
      }, (book: Book) => book.id)

      if (this.loadingMore) {
        GridItem() {
          Row({ space: AppSpace.Xs }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text('加载更多...')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .height(48)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .columnStart(0).columnEnd(2)
      } else if (!this.hasMore && this.books.length > 0) {
        GridItem() {
          Text('— 没有更多了 —')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .height(48)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .columnStart(0).columnEnd(2)
      }
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(AppSpace.Sm)
    .rowsGap(AppSpace.Md)
    .cachedCount(6)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({
      left: AppSpace.Md, right: AppSpace.Md,
      top: AppSpace.Sm,
      bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg
    })
    .onReachEnd(() => this.loadNextPage())
  }
}
