import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { Book, Chapter } from '../model/Book';
import { SearchResult, HomeBlockSection } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { BookCard } from '../components/BookCard';
import { BookDataSource } from '../utils/BookDataSource';
import { HomeBlockDataSource } from '../utils/HomeBlockDataSource';
import { BuiltInSourceRegistry } from '../service/builtin/BuiltInSourceRegistry';

/** 双击首页 Tab 触发刷新首页数据 */
export const EVT_REFRESH_HOME = 'app.home.refresh';

/** 首页分类入口项 */
interface HomeCategory {
  name: string;
  /** 分类列表 URL（听友FM 的 types/<typeId>/comprehensive/p1 路径） */
  url: string;
}

const LATEST_CATEGORY_URL = 'rank/recommend_novel/latest/p1';

/** 最新榜单 + 完整的16个分类。 */
const HOME_CATEGORIES: HomeCategory[] = [
  { name: '最新', url: LATEST_CATEGORY_URL },
  { name: '玄幻奇幻', url: 'types/46/comprehensive/p1' },
  { name: '武侠小说', url: 'types/11/comprehensive/p1' },
  { name: '恐怖惊悚', url: 'types/14/comprehensive/p1' },
  { name: '言情通俗', url: 'types/19/comprehensive/p1' },
  { name: '历史军事', url: 'types/15/comprehensive/p1' },
  { name: '官场商战', url: 'types/17/comprehensive/p1' },
  { name: '百家讲坛', url: 'types/9/comprehensive/p1' },
  { name: '有声文学', url: 'types/10/comprehensive/p1' },
  { name: '刑侦反腐', url: 'types/16/comprehensive/p1' },
  { name: '广播剧', url: 'types/36/comprehensive/p1' },
  { name: '人物纪实', url: 'types/18/comprehensive/p1' },
  { name: '相声小品', url: 'types/21/comprehensive/p1' },
  { name: '健康养生', url: 'types/33/comprehensive/p1' },
  { name: '商业财经', url: 'types/42/comprehensive/p1' },
  { name: '童话寓言', url: 'types/20/comprehensive/p1' },
  { name: '单田芳', url: 'types/1/comprehensive/p1' },
];

/** 第一行固定入口：最新、玄幻奇幻、武侠小说（配合“推荐”凑4个）。 */
const FIXED_CATEGORIES: HomeCategory[] = [
  { name: '最新', url: LATEST_CATEGORY_URL },
  { name: '玄幻奇幻', url: 'types/46/comprehensive/p1' },
  { name: '武侠小说', url: 'types/11/comprehensive/p1' },
];

/** 第二行固定保留恐怖惊悚，再从剩余13类随机抽取3个。 */
const SECOND_ROW_FIXED_CATEGORY: HomeCategory =
  { name: '恐怖惊悚', url: 'types/14/comprehensive/p1' };

const RANDOM_POOL_CATEGORIES: HomeCategory[] = [
  { name: '言情通俗', url: 'types/19/comprehensive/p1' },
  { name: '历史军事', url: 'types/15/comprehensive/p1' },
  { name: '官场商战', url: 'types/17/comprehensive/p1' },
  { name: '百家讲坛', url: 'types/9/comprehensive/p1' },
  { name: '有声文学', url: 'types/10/comprehensive/p1' },
  { name: '刑侦反腐', url: 'types/16/comprehensive/p1' },
  { name: '广播剧', url: 'types/36/comprehensive/p1' },
  { name: '人物纪实', url: 'types/18/comprehensive/p1' },
  { name: '相声小品', url: 'types/21/comprehensive/p1' },
  { name: '健康养生', url: 'types/33/comprehensive/p1' },
  { name: '商业财经', url: 'types/42/comprehensive/p1' },
  { name: '童话寓言', url: 'types/20/comprehensive/p1' },
  { name: '单田芳', url: 'types/1/comprehensive/p1' },
];

/** 听友FM内置源标识(分类入口固定走该源) */
const TINGYOU_SOURCE_URL = 'builtin://eprendre/tingyou_fm';
const TINGYOU_SOURCE_NAME = '听友FM';

const DOMAIN = 0x0000;
const TAG = 'HomePage';

const HEADER_TOOLBAR_HEIGHT: number = 40;

@ComponentV2
export struct HomePage {
  @Local audioBooks: Book[] = [];
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local hasSearched: boolean = false;
  @Local viewMode: number = 0; // 0=grid, 1=list (默认表格模式)
  @Local audioCount: number = 0;
  @Local homeBlocks: HomeBlockSection[] = [];
  @Local loadingHome: boolean = false;
  /** 当前选中的入口索引（-1=推荐，其他值对应 HOME_CATEGORIES）。 */
  @Local selectedCategoryIndex: number = -1;
  /** 分类书单数据 */
  @Local categoryBooks: Book[] = [];
  @Local categoryLoading: boolean = false;
  @Local categoryError: string = '';
  @Local categoryHasMore: boolean = true;
  @Local categoryNextUrl: string = '';
  /** 固定搜索栏实测高度(含状态栏让位),用于给列表首项让出等高占位 */
  @Local searchBarHeight: number = 0;
  /** 第二行随机分类(每次刷新时更新) */
  @Local randomCategories: HomeCategory[] = [];

  @Event onBookTap: (id: string) => void = () => {};
  @Event onBlockMore: (block: HomeBlockSection) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  /** 分类入口点击:跳到分类书单页(复用 blockMore 路由) */
  @Event onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) => void = () => {};

  private contentScroller: Scroller = new Scroller();
  private audioDataSource: BookDataSource = new BookDataSource();
  private categoryDS: BookDataSource = new BookDataSource();
  private homeBlockDataSource: HomeBlockDataSource = new HomeBlockDataSource();
  private searchGen: number = 0;
  private homeGen: number = 0;
  private refreshHandler: () => void = () => this.refreshHomeData();

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'HomePage aboutToAppear');
    // 固定搜索栏高度初始估值(状态栏 + 搜索框约 56vp),实际以 onAreaChange 实测为准
    this.searchBarHeight = WindowUtils.getStatusBarHeightVp() + 56;
    this.shuffleRandomCategories();
    this.loadHomeBlocks();
    emitter.on(EVT_REFRESH_HOME, this.refreshHandler);
    // 把滚动控制器交给上层(MainPage)绑定到 HdsTabsController
    this.onScrollerReady(this.contentScroller);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_REFRESH_HOME, this.refreshHandler);
  }

  /** 第二行保留恐怖惊悚，并从剩余池中随机选3个。 */
  private shuffleRandomCategories(): void {
    const pool = [...RANDOM_POOL_CATEGORIES];
    const selected: HomeCategory[] = [SECOND_ROW_FIXED_CATEGORY];
    for (let i = 0; i < 3 && pool.length > 0; i++) {
      const randomIndex = Math.floor(Math.random() * pool.length);
      selected.push(pool[randomIndex]);
      pool.splice(randomIndex, 1);
    }
    this.randomCategories = selected;
  }

  /** 刷新首页数据(双击首页 Tab 触发):重抽随机分类 + 重载推荐板块 / 当前分类 */
  private refreshHomeData(): void {
    if (this.hasSearched) return; // 搜索结果态不刷新
    this.shuffleRandomCategories();
    if (this.selectedCategoryIndex === -1) {
      this.loadingHome = true; // 显示加载态,避免清空后闪现空态
      this.loadHomeBlocks();
    } else {
      // 强制重载当前分类(绕过 switchCategory 的同索引短路)
      const idx = this.selectedCategoryIndex;
      this.selectedCategoryIndex = -1;
      this.switchCategory(idx);
    }
  }

  private async loadHomeBlocks(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'loadHomeBlocks START, gen=%{public}d', this.homeGen);
    this.homeGen++;
    const gen = this.homeGen;
    if (this.homeBlocks.length === 0) this.loadingHome = true;
    this.homeBlocks = [];
    this.homeBlockDataSource.clear();
    hilog.info(DOMAIN, TAG, 'loadHomeBlocks: cleared data, loadingHome=%{public}s', String(this.loadingHome));
    try {
      // 只加载内置书源的首页推荐,不加载导入的书源
      const plugin = BuiltInSourceRegistry.getByUrl(TINGYOU_SOURCE_URL);
      if (!plugin) {
        hilog.warn(DOMAIN, TAG, 'loadHomeBlocks: Built-in source not available');
        this.loadingHome = false;
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: calling plugin.getHomeBlocks()');

      const blocks = await plugin.getHomeBlocks();
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: got %{public}d blocks', blocks.length);
      if (gen !== this.homeGen) return;

      // 转换为 HomeBlockSection 格式
      const sections: HomeBlockSection[] = [];
      for (const b of blocks) {
        const books: SearchResult[] = [];
        for (const book of b.books) {
          BuiltInSourceRegistry.cacheBookMeta(book);
          books.push({
            name: book.title,
            author: book.author,
            coverUrl: book.coverUrl,
            bookUrl: book.bookUrl,
            intro: book.intro,
            kind: book.status || '',
            lastChapter: '',
            sourceName: plugin.name,
            sourceUrl: TINGYOU_SOURCE_URL
          });
        }
        sections.push({
          title: b.title,
          books: books,
          moreUrl: b.moreUrl,
          layout: b.layout,
          sourceName: plugin.name,
          sourceUrl: TINGYOU_SOURCE_URL
        });
      }

      this.homeBlocks = sections;
      this.homeBlockDataSource.appendBlocks(sections);
      this.loadingHome = false;
      hilog.info(DOMAIN, TAG, 'loadHomeBlocks: SUCCESS, sections=%{public}d, loadingHome=false', sections.length);

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
    this.hasSearched = false;
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
  }

  /** 切换首页入口（-1=推荐，其他值为榜单或具体分类）。 */
  private async switchCategory(index: number): Promise<void> {
    if (this.selectedCategoryIndex === index) return; // 重复点击不处理

    this.selectedCategoryIndex = index;

    if (index === -1) {
      // 切回推荐
      this.categoryBooks = [];
      this.categoryDS.setBooks([]);
      return;
    }

    // 加载分类书单
    const cat = HOME_CATEGORIES[index];
    if (!cat) return;

    this.categoryBooks = [];
    this.categoryDS.setBooks([]);
    this.categoryLoading = true;
    this.categoryError = '';
    this.categoryHasMore = true;
    this.categoryNextUrl = '';

    try {
      const plugin = BuiltInSourceRegistry.getByUrl(TINGYOU_SOURCE_URL);
      if (!plugin) {
        this.categoryLoading = false;
        this.categoryError = '听友FM源不可用';
        return;
      }

      const books: Book[] = [];
      let nextUrl = cat.url;
      const MIN_BOOKS = 50; // 至少加载50本

      // 循环加载直到达到50本以上
      while (books.length < MIN_BOOKS && nextUrl) {
        const result = await plugin.getCategoryList(nextUrl);

        for (const b of result.books) {
          BuiltInSourceRegistry.cacheBookMeta(b);
          const sr: SearchResult = {
            name: b.title, author: b.author, coverUrl: b.coverUrl,
            bookUrl: b.bookUrl, intro: b.intro, kind: b.status, lastChapter: '',
            sourceName: plugin.name, sourceUrl: TINGYOU_SOURCE_URL,
          };
          books.push(this.homeBookFromResult(sr));
        }

        nextUrl = result.nextUrl || '';

        // 如果没有更多数据了就退出
        if (!nextUrl || result.books.length === 0) {
          break;
        }
      }

      this.categoryBooks = books;
      this.categoryDS.setBooks(books);
      this.categoryNextUrl = nextUrl;
      this.categoryHasMore = nextUrl.length > 0;
      this.categoryLoading = false;
      hilog.info(DOMAIN, TAG, 'switchCategory: loaded %{public}d books for category %{public}d', books.length, index);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'switchCategory failed: %{public}s', String(e));
      this.categoryLoading = false;
      this.categoryError = '加载失败：' + String(e);
    }
  }

  /** 通过 URL 切换分类 */
  private async switchCategoryByUrl(url: string): Promise<void> {
    // 查找对应的索引
    const index = HOME_CATEGORIES.findIndex(cat => cat.url === url);
    if (index !== -1) {
      await this.switchCategory(index);
    }
  }

  /** 判断固定分类是否选中 */
  private getFixedCategorySelected(cat: HomeCategory): boolean {
    if (this.selectedCategoryIndex === -1) return false;
    const selected = HOME_CATEGORIES[this.selectedCategoryIndex];
    return selected && selected.url === cat.url;
  }

  /** 判断随机分类是否选中 */
  private getRandomCategorySelected(cat: HomeCategory): boolean {
    if (this.selectedCategoryIndex === -1) return false;
    const selected = HOME_CATEGORIES[this.selectedCategoryIndex];
    return selected && selected.url === cat.url;
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

  private async doSearch(): Promise<void> {
    const keyword = this.keyword.trim();
    if (!keyword) {
      this.clearSearch();
      return;
    }
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.hasSearched = true;
    this.audioBooks = [];
    this.audioCount = 0;
    this.audioDataSource.clear();
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getEnabledSources();
      const source = sources.length > 0 ? sources[0] : undefined;
      if (!source || gen !== this.searchGen) return;
      const results = await BookSourceService.searchBooks(source, keyword);
      if (gen !== this.searchGen) return;
      const books = results.map((item: SearchResult): Book => this.searchResultToBook(item));
      this.audioBooks = books;
      this.audioCount = books.length;
      this.audioDataSource.appendBooks(books);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
      this.audioBooks = [];
      this.audioCount = 0;
      this.audioDataSource.clear();
    } finally {
      if (gen === this.searchGen) this.searching = false;
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

  private hashSearchKey(sourceUrl: string, bookUrl: string): string {
    const raw = `${sourceUrl}::${bookUrl}`;
    let h: number = 5381;
    for (let i = 0; i < raw.length; i++) {
      h = (((h << 5) + h) + raw.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(36);
  }

  /**
   * 固定搜索栏：常驻顶部、不随内容上滑，整条栏透明(悬浮无背景)。
   * 搜索框胶囊浮在内容上方，列表从其下方滚过、四周直接透出。
   * expandSafeArea + padding.top 让搜索框落在状态栏下方。
   * onAreaChange 实测栏高 → 列表首项用等高占位让出空间。
   */
  @Builder
  fixedSearchBar() {
    Column() {
      Search({ value: this.keyword!!, placeholder: '搜索书籍、作者...' })
        .searchButton('搜索', { fontColor: HomeTheme.Accent })
        .onSubmit(() => this.doSearch())
        .onChange((value: string) => {
          this.keyword = value;
          if (value.length === 0 && this.hasSearched) {
            this.clearSearch();
          }
        })
        .height(40)
        // 搜索框胶囊做成磨砂玻璃：内容从其下方滚过被模糊，既有沉浸光感观感、又看得清
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .borderRadius(AppRadius.Lg)
        .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })

      if (this.hasSearched) {
        Row() {
          Text(`有声书 ${this.audioCount}`)
            .fontSize(13)
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
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
            .backgroundColor('rgba(255,255,255,0.3)')
            .onClick(() => {
              this.getUIContext()?.animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard },
                () => { this.viewMode = this.viewMode === 0 ? 1 : 0; });
            })
        }
        .width('100%')
        .height(HEADER_TOOLBAR_HEIGHT)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Xs })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ top: WindowUtils.getStatusBarHeightVp() })
    // 悬浮无背景：整条栏透明，搜索框胶囊浮在内容上方，四周直接透出滚动内容
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onAreaChange((_o: Area, n: Area) => {
      this.searchBarHeight = n.height as number;
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // L0 背景层（满屏，覆盖到状态栏）
      // 浅色模式为暖色渐变,深色模式三色统一为中性色(等效纯色)
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
        // 仅让背景渐变铺到状态栏后面，不影响 HdsNavigation 自身的状态栏避让
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      // L1 原 HdsNavigation
      HdsNavigation() {
        List({ scroller: this.contentScroller }) {
        // 第1项:固定搜索栏的等高占位 —— 搜索栏本身常驻不滚动(见 fixedSearchBar),
        // 这里只用等高空白把列表内容顶到固定栏下方开始。
        ListItem() {
          Column().height(this.searchBarHeight)
        }

        // 第1.5项：分类标签横向滚动（仅推荐态，未搜索时显示）
        if (!this.hasSearched) {
          ListItem() {
            this.buildCategoryTags()
          }
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
        }

        // 第2~N项：内容主体（推荐板块 / 搜索结果 / 空态）
        if (this.hasSearched && this.audioCount === 0 && this.searching) {
          ListItem() {
            this.buildSearchingState()
          }
        } else if (this.hasSearched && this.audioCount === 0 && !this.searching) {
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
                    BookCard({ book: book, indexHint: idx, onTap: () => this.onBookTap(book.id) })
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
          // 未搜索状态:根据 selectedCategoryIndex 显示推荐或分类书单
          if (this.selectedCategoryIndex === -1) {
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
                  Text(TINGYOU_SOURCE_NAME)
                    .fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Xs })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            }
          } else {
            // 分类书单
            if (this.categoryLoading && this.categoryBooks.length === 0) {
              ListItem() {
                Column() {
                  LoadingProgress().width(40).height(40).color($r('sys.color.brand'))
                  Text('加载中...')
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Sm })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.categoryError && this.categoryBooks.length === 0) {
              ListItem() {
                Column() {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(48)
                    .fontColor([$r('sys.color.font_tertiary')])
                  Text(this.categoryError)
                    .fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_tertiary'))
                    .margin({ top: AppSpace.Md })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.categoryBooks.length > 0) {
              ListItem() {
                Grid() {
                  LazyForEach(this.categoryDS, (book: Book, idx: number) => {
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
      .cachedCount(5)
      .clip(false) // 允许内容穿透到固定搜索栏下方产生毛玻璃透出
      .backgroundColor(Color.Transparent) // 让 L0 暖色渐变透出
      }
    .titleBar({
      content: { title: { mainTitle: '' } }
    })
    .hideTitleBar(true) // 顶部改用固定毛玻璃搜索栏(fixedSearchBar)，HdsNavigation 标题栏不再使用
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)

      // 固定搜索栏：常驻顶部、不随内容上滑，内容从其下方滚过被毛玻璃材质模糊透出。
      // 背景渐变由 L0 Column 的 expandSafeArea 铺到状态栏后面。
      this.fixedSearchBar()
    }
  }

  @Builder
  buildSearchingState() {
    Column() {
      LoadingProgress().width(40).height(40).color($r('sys.color.brand'))
      Text(`正在搜索 ${TINGYOU_SOURCE_NAME}...`)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Sm })
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
      Text('未找到相关有声书')
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
          .sourceSize({ width: 300, height: 400 })
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
  buildCategoryTags() {
    Column({ space: AppSpace.Sm }) {
      // 第一行：推荐 + 最新 + 两个固定分类
      Row({ space: AppSpace.Sm }) {
        // 推荐标签
        Text('推荐')
          .fontSize(AppFont.Body)
          .fontColor(this.selectedCategoryIndex === -1 ? Color.White : $r('sys.color.font_primary'))
          .fontWeight(FontWeight.Regular)
          .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
          .borderRadius(AppRadius.Xl)
          .backgroundColor(this.selectedCategoryIndex === -1 ? '#E87A3E' : $r('sys.color.comp_background_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .onClick(() => {
            this.switchCategory(-1);
          })

        // 固定3个分类
        ForEach(FIXED_CATEGORIES, (cat: HomeCategory) => {
          Text(cat.name)
            .fontSize(AppFont.Body)
            .fontColor(this.getFixedCategorySelected(cat) ? Color.White : $r('sys.color.font_primary'))
            .fontWeight(FontWeight.Regular)
            .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
            .borderRadius(AppRadius.Xl)
            .backgroundColor(this.getFixedCategorySelected(cat) ? '#E87A3E' : $r('sys.color.comp_background_secondary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.switchCategoryByUrl(cat.url);
            })
        }, (cat: HomeCategory) => cat.url)
      }
      .width('100%')

      // 第二行：恐怖惊悚 + 随机3个分类
      Row({ space: AppSpace.Sm }) {
        ForEach(this.randomCategories, (cat: HomeCategory) => {
          Text(cat.name)
            .fontSize(AppFont.Body)
            .fontColor(this.getRandomCategorySelected(cat) ? Color.White : $r('sys.color.font_primary'))
            .fontWeight(FontWeight.Regular)
            .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
            .borderRadius(AppRadius.Xl)
            .backgroundColor(this.getRandomCategorySelected(cat) ? '#E87A3E' : $r('sys.color.comp_background_secondary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.switchCategoryByUrl(cat.url);
            })
        }, (cat: HomeCategory) => cat.url)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width(100)
            .aspectRatio(0.7)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('sys.color.brand'))
            Text(book.title ? book.title.substring(0, 1) : '?')
              .fontSize(32)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width(100)
          .aspectRatio(0.7)
          .borderRadius(AppRadius.Md)
          .clip(true)
        }
        if (book.narrator) {
          Text(book.narrator)
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('sys.color.ohos_id_color_mask_thin'))
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Md })
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
    .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
    .onClick(() => this.onBookTap(book.id))
  }

}
