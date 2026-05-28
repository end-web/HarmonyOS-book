import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, TocItem } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { EVT_HISTORY_UPDATED } from '../service/AudioService';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct FavoritePage {
  @Local favoriteBooks: Book[] = [];
  @Local historyMap: Record<string, PlayHistoryItem> = {};
  @Local chapterIdxMap: Record<string, number> = {};
  @Local loading: boolean = true;
  @Local dragging: boolean = false;
  @Local trashHover: boolean = false;
  @Local draggingBookId: string = '';
  @Local isRefreshing: boolean = false;
  @Local resolvingTocId: string = '';
  @Param visible: boolean = false;
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onBookTap: (id: string) => void = () => {};
  @Event onGotoStore: () => void = () => {};

  private context: common.UIAbilityContext | null = null;
  private historyUpdatedHandler: (e: emitter.EventData) => void = (e) => this.onHistoryUpdated(e);

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadFavorites();
    emitter.on(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
  }

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.loadFavorites();
    }
  }

  /** 收到播放/阅读进度更新事件:只重算历史相关 map,不重拉书清单,避免列表抖动 */
  private async onHistoryUpdated(_e: emitter.EventData): Promise<void> {
    if (!this.context || this.favoriteBooks.length === 0) return;
    const history = await PreferenceService.getHistory();
    const map: Record<string, PlayHistoryItem> = {};
    for (const item of history) {
      if (!map[item.bookId]) {
        map[item.bookId] = item;
      }
    }
    const idxMap: Record<string, number> = {};
    for (const b of this.favoriteBooks) {
      const h = map[b.id];
      if (!h || !b.chapters || b.chapters.length === 0) continue;
      const idx = b.chapters.findIndex((c) => c.id === h.chapterId);
      if (idx >= 0) idxMap[b.id] = idx;
    }
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
  }

  async loadFavorites(): Promise<void> {
    if (!this.context) return;
    const ids = await PreferenceService.getFavorites();
    const allBooks = await DataService.getBooks(this.context);
    const books = allBooks.filter((b) => ids.includes(b.id));
    const history = await PreferenceService.getHistory();
    const map: Record<string, PlayHistoryItem> = {};
    for (const item of history) {
      if (!map[item.bookId]) {
        map[item.bookId] = item;
      }
    }
    // 预算每本书的 chapterId → chapterIndex,避免后续 build / click 反复 findIndex
    const idxMap: Record<string, number> = {};
    for (const b of books) {
      const h = map[b.id];
      if (!h || !b.chapters || b.chapters.length === 0) continue;
      const idx = b.chapters.findIndex(c => c.id === h.chapterId);
      if (idx >= 0) idxMap[b.id] = idx;
    }
    this.favoriteBooks = books;
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
    this.loading = false;
  }

  private getProgressText(book: Book): string {
    const unit = book.category === 'novel' ? '章' : '集';
    const h = this.historyMap[book.id];
    if (h && book.chapterCount > 0) {
      const idx = this.chapterIdxMap[book.id];
      if (idx !== undefined && idx >= 0) {
        return `${idx + 1}${unit}/${book.chapterCount}${unit}`;
      }
      return `共${book.chapterCount}${unit}`;
    }
    if (book.chapterCount > 0) {
      return `共${book.chapterCount}${unit}`;
    }
    return book.author || '';
  }

  private handleBookTap(book: Book): void {
    const onPop = (): void => { this.loadFavorites(); };
    SearchCache.put(book);
    // 直接用已缓存的 historyMap,避免每次点击都 IO
    const history = this.historyMap[book.id];
    // 没有进度 → 详情页让用户选章节
    if (!history) {
      this.navStack.pushPathByName('detail', book.id, onPop);
      return;
    }
    // 章节列表尚未加载 → 在线书源主动拉 toc 后恢复进度;否则交给详情页
    if (!book.chapters || book.chapters.length === 0) {
      if (book.bookUrl && book.sourceUrl && !book.id.startsWith('import_')) {
        this.resumeOnlineWithToc(book, history, onPop);
      } else {
        this.navStack.pushPathByName('detail', book.id, onPop);
      }
      return;
    }
    // 有进度但定位不到对应章节(可能 TOC 重排) → 详情页
    const idx = this.chapterIdxMap[book.id];
    if (idx === undefined || idx < 0) {
      this.navStack.pushPathByName('detail', book.id, onPop);
      return;
    }
    SearchCache.put(book);
    if (book.category === 'novel') {
      const params: Record<string, Object> = {
        'bookId': book.id as Object,
        'chapterIndex': idx as Object
      };
      this.navStack.pushPathByName('TextReaderPage', params, onPop);
    } else {
      const params: Record<string, Object> = {
        'bookId': book.id as Object,
        'chapterId': history.chapterId as Object,
        'progressMs': history.progressMs as Object
      };
      this.navStack.pushPathByName('player', params, onPop);
    }
  }

  /** 老收藏的在线书没缓存章节时,先拉 toc 再恢复进度;期间禁用重复点击 */
  private async resumeOnlineWithToc(book: Book, history: PlayHistoryItem, onPop: () => void): Promise<void> {
    if (this.resolvingTocId) return;
    this.resolvingTocId = book.id;
    promptAction.showToast({ message: '加载章节中...' });
    try {
      const sourcesJson = await PreferenceService.getBookSources();
      const sources = JSON.parse(sourcesJson) as BookSource[];
      const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
      if (!source) {
        promptAction.showToast({ message: '书源已删除,请到详情页重新选择' });
        this.navStack.pushPathByName('detail', book.id, onPop);
        return;
      }
      let tocUrl = book.bookUrl;
      const bookInfo = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
      const mergedVars: Record<string, string> = {};
      if (book.variables) {
        for (const k of Object.keys(book.variables)) mergedVars[k] = book.variables[k];
      }
      if (bookInfo?.variables) {
        for (const k of Object.keys(bookInfo.variables)) mergedVars[k] = bookInfo.variables[k];
      }
      if (bookInfo?.tocUrl) tocUrl = bookInfo.tocUrl;
      const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars);
      if (tocItems.length === 0) {
        promptAction.showToast({ message: '章节加载失败' });
        this.navStack.pushPathByName('detail', book.id, onPop);
        return;
      }
      book.chapters = tocItems.map((item: TocItem, idx: number): Chapter => ({
        id: `${book.id}-c${idx}`,
        index: idx + 1,
        title: item.name,
        duration: 0,
        source: { type: 'url', value: item.url }
      }));
      book.chapterCount = book.chapters.length;
      // 持久化新 toc,下次点击不用再拉
      await DataService.upsertCachedBook(book);
      SearchCache.put(book);
      const idx = book.chapters.findIndex((c) => c.id === history.chapterId);
      if (idx < 0) {
        // 章节顺序变了,定位不回去 → 交给详情页让用户选
        this.navStack.pushPathByName('detail', book.id, onPop);
        return;
      }
      this.chapterIdxMap[book.id] = idx;
      const params: Record<string, Object> = {
        'bookId': book.id as Object,
        'chapterId': history.chapterId as Object,
        'progressMs': history.progressMs as Object
      };
      this.navStack.pushPathByName('player', params, onPop);
    } catch (_e) {
      promptAction.showToast({ message: '章节加载失败' });
      this.navStack.pushPathByName('detail', book.id, onPop);
    } finally {
      this.resolvingTocId = '';
    }
  }

  private confirmDelete(book: Book): void {
    const isLocal = book.id.startsWith('import_');
    const prompt = this.getUIContext().getPromptAction();
    if (isLocal) {
      prompt.showDialog({
        title: '移除书籍',
        message: `"${book.title}"是本地导入的书籍`,
        buttons: [
          { text: '取消', color: '#8F8F8F' },
          { text: '仅移除书架', color: '#333333' },
          { text: '删除本地文件', color: '#FF4444' }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.doRemove(book.id, false);
        } else if (result.index === 2) {
          this.doRemove(book.id, true);
        }
      }).catch(() => { /* ignore */ });
    } else {
      prompt.showDialog({
        title: '移除书籍',
        message: `确认从书架移除"${book.title}"？`,
        buttons: [
          { text: '取消', color: '#8F8F8F' },
          { text: '移除', color: '#FF4444' }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.doRemove(book.id, false);
        }
      }).catch(() => { /* ignore */ });
    }
  }

  private async doRemove(bookId: string, deleteFiles: boolean): Promise<void> {
    if (!this.context) return;
    if (deleteFiles) {
      const novelDir = this.context.filesDir + '/novel/' + bookId;
      const audioDir = this.context.filesDir + '/audio/' + bookId;
      try { await fileIo.rmdir(novelDir); } catch (_e) { /* not exists */ }
      try { await fileIo.rmdir(audioDir); } catch (_e) { /* not exists */ }
      await DataService.removeImportedBook(bookId);
    }
    await PreferenceService.toggleFavorite(bookId);
    await this.loadFavorites();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容层
      Refresh({ refreshing: $$this.isRefreshing }) {
        Grid() {
          ForEach(this.favoriteBooks, (book: Book) => {
            GridItem() {
              this.buildBookTile(book)
            }
          }, (book: Book) => book.id)
          GridItem() {
            this.buildAddTile()
          }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(AppSpace.Sm)
        .rowsGap(AppSpace.Md)
        .width('100%')
        .height('100%')
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xl + AppFont.TitleL,
          bottom: WindowUtils.getFloatingTabBottomVp()
        })
        .scrollBar(BarState.Off)
      }
      .onRefreshing(() => {
        this.loadFavorites().finally(() => { this.isRefreshing = false; });
      })

      // 浮顶标题（去掉 backgroundBlurStyle,改用纯色背景,转场时省 GPU）
      Column() {
        Text('书架')
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: AppSpace.Md,
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Md,
        bottom: AppSpace.Sm
      })
      .backgroundColor($r('sys.color.background_primary'))

      // 拖动删除浮层（自己居中）
      Column() {
        this.buildTrashZone()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildTrashZone() {
    Column() {
      SymbolGlyph($r('sys.symbol.trash_fill'))
        .fontSize(this.trashHover ? 28 : 22)
        .fontColor([Color.White])
    }
    .width(this.trashHover ? 64 : 52)
    .height(this.trashHover ? 64 : 52)
    .borderRadius(this.trashHover ? 32 : 26)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.trashHover ? '#FF3B30' : '#E64545')
    .shadow({ radius: 16, color: '#55000000', offsetY: 4 })
    .scale({ x: this.dragging ? 1 : 0.5, y: this.dragging ? 1 : 0.5 })
    .opacity(this.dragging ? 1 : 0)
    .animation({ duration: 250, curve: Curve.FastOutSlowIn })
    .allowDrop([])
    .onDragEnter(() => { this.trashHover = true; })
    .onDragLeave(() => { this.trashHover = false; })
    .onDrop(() => {
      const id = this.draggingBookId;
      this.trashHover = false;
      this.dragging = false;
      this.draggingBookId = '';
      if (id) {
        const book = this.favoriteBooks.find(b => b.id === id);
        if (book) this.confirmDelete(book);
      }
    })
  }

  @Builder
  buildBookTile(book: Book) {
    Column({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.startIcon'))
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (book.cover && (book.cover.startsWith('/data/') || book.cover.startsWith('file://'))) {
          Image('file://' + book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (book.cover) {
          Image($rawfile(book.cover))
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(AppColor.Brand)
              .borderRadius(AppRadius.Md)
            Text(book.title ? book.title.substring(0, 1) : '?')
              .fontSize(36)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .aspectRatio(0.72)
          .borderRadius(AppRadius.Md)
          .clip(true)
        }
        this.buildTypeBadge(book, false)
      }
      .width('100%')
      .borderRadius(AppRadius.Md)
      .clip(true)
      .shadow({ radius: 4, color: '#1A000000', offsetY: 1 })

      Text(book.title)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .copyOption(CopyOptions.None)
      Text(this.getProgressText(book))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .width('100%')
        .copyOption(CopyOptions.None)
    }
    .scale(this.draggingBookId === book.id ? { x: 0.92, y: 0.92 } : { x: 1, y: 1 })
    .opacity(this.draggingBookId === book.id ? 0.4 : 1)
    .animation(this.dragging ? { duration: 200, curve: Curve.FastOutSlowIn } : null)
    .onDragStart(() => {
      this.draggingBookId = book.id;
      this.dragging = true;
      return { builder: (): void => this.buildDragPreview(book) };
    })
    .onDragEnd(() => {
      setTimeout(() => {
        this.dragging = false;
        this.trashHover = false;
        this.draggingBookId = '';
      }, 100);
    })
    .onClick(() => {
      if (!this.dragging && !this.resolvingTocId) {
        this.handleBookTap(book);
      }
    })
  }

  @Builder
  buildDragPreview(book: Book) {
    Column() {
      Text(book.title ? book.title.substring(0, 2) : '?')
        .fontSize(24)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
    }
    .width(70)
    .height(70)
    .borderRadius(35)
    .backgroundColor(AppColor.Brand)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 8, color: '#44000000', offsetY: 3 })
  }

  @Builder
  buildTypeBadge(book: Book, small: boolean) {
    Row({ space: small ? 2 : 3 }) {
      SymbolGlyph(book.category === 'novel' ? $r('sys.symbol.book') : $r('sys.symbol.speaker_wave_2_fill'))
        .fontSize(small ? 10 : 12)
        .fontColor([Color.White])
      Text(book.category === 'novel' ? '电子书' : '有声书')
        .fontSize(small ? 9 : 10)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
    }
    .padding({
      left: small ? 5 : 6,
      right: small ? 5 : 6,
      top: small ? 2 : 3,
      bottom: small ? 2 : 3
    })
    .backgroundColor(book.category === 'novel' ? '#CC0A59F7' : '#CCFF8800')
    .borderRadius(AppRadius.Sm)
    .margin({ top: small ? 5 : 6, left: small ? 5 : 6 })
  }

  @Builder
  buildAddTile() {
    Column({ space: AppSpace.Xs }) {
      Column() {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(32)
          .fontColor(['#CCCCCC'])
        Text('去书城寻好书')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Xs })
      }
      .width('100%')
      .aspectRatio(0.72)
      .borderRadius(AppRadius.Md)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#F5F5F5')
      .border({ width: 1, color: '#E0E0E0', style: BorderStyle.Dashed })

      Text(' ')
        .fontSize(AppFont.Body)
        .width('100%')
      Text(' ')
        .fontSize(AppFont.Caption)
        .width('100%')
    }
    .onClick(() => this.onGotoStore())
  }
}
