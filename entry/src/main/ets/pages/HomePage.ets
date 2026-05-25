import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { WindowUtils } from '../utils/WindowUtils';

const DOMAIN = 0x0000;
const TAG = 'HomePage';

@ComponentV2
export struct HomePage {
  @Local books: Book[] = [];
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local sourceCount: number = 0;
  @Local debugInfo: string = '';
  @Event onBookTap: (id: string) => void = () => {};

  aboutToAppear(): void {
    this.loadSourceCount();
  }

  private async loadSourceCount(): Promise<void> {
    try {
      const sources = await SourceDataService.getSources();
      this.sourceCount = sources.filter(s => s.bookSourceType === 0 && s.enabled !== false).length;
    } catch (_e) {
      this.sourceCount = 0;
    }
  }

  private async doSearch(): Promise<void> {
    if (!this.keyword.trim()) return;
    this.searching = true;
    this.hasSearched = true;
    this.books = [];
    const lines: string[] = [];
    try {
      const sources = await SourceDataService.getSources();
      const textSources = sources.filter(s => s.bookSourceType === 0 && s.enabled !== false);
      lines.push(`文本/已启用 ${textSources.length} 个`);
      hilog.info(DOMAIN, TAG, 'search "%{public}s" across %{public}d text sources',
        this.keyword.trim(), textSources.length);
      this.debugInfo = lines.join('\n');
      const results: SearchResult[] = [];

      for (const source of textSources) {
        try {
          const r = await BookSourceService.searchBooks(source, this.keyword.trim());
          hilog.info(DOMAIN, TAG, 'src %{public}s -> %{public}d hits',
            source.bookSourceName, r.length);
          lines.push(`${source.bookSourceName}: ${r.length} 条`);
          results.push(...r);
        } catch (e) {
          const err = e as Error;
          const msg = err && err.message ? err.message : String(e);
          hilog.error(DOMAIN, TAG, 'src %{public}s failed: %{public}s', source.bookSourceName, msg);
          lines.push(`${source.bookSourceName}: 错误 ${msg}`);
        }
        this.debugInfo = lines.join('\n');
        if (results.length >= 30) break;
      }
      this.books = results.map((r, idx) => this.searchResultToBook(r, idx));
      lines.push(`合计命中 ${this.books.length} 条`);
      this.debugInfo = lines.join('\n');
    } catch (e) {
      const err = e as Error;
      const msg = err && err.message ? err.message : String(e);
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', msg);
      this.debugInfo = '搜索异常: ' + msg;
      this.books = [];
    }
    this.searching = false;
  }

  private searchResultToBook(r: SearchResult, idx: number): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: `search_${idx}_${Date.now()}`,
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: 'all',
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 内容区域（可滚动，顶部留出搜索栏空间）
      Column() {
        if (this.searching) {
          Column() {
            LoadingProgress().width(40).height(40).color(AppColor.Brand)
            Text('正在搜索...').fontSize(AppFont.Body).fontColor($r('sys.color.font_tertiary')).margin({ top: AppSpace.Sm })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (!this.hasSearched) {
          this.buildEmptyState()
        } else if (this.books.length === 0) {
          Column() {
            Text('未找到相关有声书').fontSize(AppFont.BodyL).fontColor($r('sys.color.font_tertiary'))
            Text('试试换个关键词').fontSize(AppFont.Body).fontColor('#CCCCCC').margin({ top: AppSpace.Xs })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.buildSearchResults()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: WindowUtils.getStatusBarHeightVp() + 90 })
      .backgroundColor($r('sys.color.background_primary'))

      // 顶部搜索栏（沉浸光感，颜色跟随系统深浅色）
      Column({ space: AppSpace.Xs }) {
        Text('首页')
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

        Search({ value: this.keyword!!, placeholder: '歌曲、歌手、听书...' })
          .searchButton('搜索')
          .onSubmit(() => this.doSearch())
          .height(40)
          .margin({ left: AppSpace.Md, right: AppSpace.Md })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        bottom: AppSpace.Md
      })
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, {
        colorMode: ThemeColorMode.SYSTEM
      })

      if (this.debugInfo.length > 0) {
        Text(this.debugInfo)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: AppSpace.Md, right: AppSpace.Md,
            top: WindowUtils.getStatusBarHeightVp() + 95 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(48)
        .fontColor(['#CCCCCC'])
      Text('搜索有声书')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_secondary'))

      if (this.sourceCount > 0) {
        Text(`已加载 ${this.sourceCount} 个有声源`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
      } else {
        Text('暂无可用书源')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
        Text('请到「书源」Tab 添加订阅')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Xxs })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSearchResults() {
    Scroll() {
      Column({ space: AppSpace.Sm }) {
        Text(`找到 ${this.books.length} 本有声书`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: AppSpace.Md, top: AppSpace.Sm })

        Grid() {
          ForEach(this.books, (book: Book) => {
            GridItem() {
              BookCard({
                book: book,
                cardWidth: 105,
                onTap: (id: string) => this.onBookTap(id)
              })
            }
          }, (book: Book) => book.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(AppSpace.Sm)
        .rowsGap(AppSpace.Md)
        .padding({ left: AppSpace.Md, right: AppSpace.Md })
        .width('100%')
      }
      .padding({ bottom: 200 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .layoutWeight(1)
  }
}
