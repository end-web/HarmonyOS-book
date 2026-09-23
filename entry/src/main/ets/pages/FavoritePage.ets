import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  AppColor,
  AppRadius,
  AppSpace,
  AppFont,
  AppMaterial,
  HomeTheme
} from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem, EVT_FAVORITES_CHANGED } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { AudioService, EVT_HISTORY_UPDATED } from '../service/AudioService';
import { StatsService } from '../service/StatsService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { BookDataSource } from '../utils/BookDataSource';
import { ShelfBatchActions } from '../components/ShelfBatchActions';
import { DownloadService } from '../service/DownloadService';
import { TextReaderRouteParams, TextReadingPosition } from '../model/TextReading';
import { TextReadingProgressService, EVT_TEXT_READING_PROGRESS_CHANGED } from '../service/text/TextReadingProgressService';

const BOOKSHELF_COVER_RATIO: number = 0.75;
const MINI_TITLE_BAR_HEIGHT: number = 56;
const SHELF_FILTER_TOP_OFFSET: number = MINI_TITLE_BAR_HEIGHT;
const SHELF_FILTER_ROW_HEIGHT: number = 40;
const SHELF_CONTENT_GAP: number = 18;

interface BookUpdateInfo {
  title: string;
  oldCount: number;
  newCount: number;
  unit: string;
}

function cloneChapter(ch: Chapter): Chapter {
  return {
    id: ch.id,
    index: ch.index,
    title: ch.title,
    duration: ch.duration,
    source: {
      type: ch.source.type,
      value: ch.source.value
    },
    originSourceValue: ch.originSourceValue,
    variables: ch.variables
  };
}

function cloneBook(book: Book): Book {
  const variables: Record<string, string> | undefined = book.variables ? {} : undefined;
  if (book.variables && variables) {
    for (const k of Object.keys(book.variables)) {
      variables[k] = book.variables[k];
    }
  }
  return {
    id: book.id,
    contentType: book.contentType,
    title: book.title,
    author: book.author,
    narrator: book.narrator,
    cover: book.cover,
    category: book.category,
    intro: book.intro,
    wordCount: book.wordCount,
    latestChapterTitle: book.latestChapterTitle,
    updateTime: book.updateTime,
    totalDuration: book.totalDuration,
    chapterCount: book.chapterCount,
    rating: book.rating,
    tags: book.tags ? book.tags.slice() : [],
    chapters: book.chapters ? book.chapters.map((ch: Chapter): Chapter => cloneChapter(ch)) : [],
    bookUrl: book.bookUrl,
    sourceUrl: book.sourceUrl,
    variables,
    skipIntro: book.skipIntro,
    skipOutro: book.skipOutro,
    completed: book.completed
  };
}

function chaptersChanged(oldChapters: Chapter[], newChapters: Chapter[]): boolean {
  if (oldChapters.length !== newChapters.length) return true;
  for (let i = 0; i < newChapters.length; i++) {
    const oldChapter = oldChapters[i];
    const newChapter = newChapters[i];
    if (!oldChapter || oldChapter.title !== newChapter.title ||
      oldChapter.originSourceValue !== newChapter.originSourceValue ||
      oldChapter.source.value !== newChapter.source.value ||
      JSON.stringify(oldChapter.variables) !== JSON.stringify(newChapter.variables)) {
      return true;
    }
  }
  return false;
}

@ComponentV2
export struct FavoritePage {
  @Local favoriteBooks: Book[] = [];
  @Local historyMap: Record<string, PlayHistoryItem> = {};
  @Local chapterIdxMap: Record<string, number> = {};
  @Local loading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local resolvingTocId: string = '';
  @Local refreshProgress: string = '';
  @Local missingFavoriteCount: number = 0;
  @Local viewMode: number = 0; // 0=网格，1=列表
  @Local shelfFilter: number = 0; // 0=全部, 1=有声书, 2=电子书
  @Local textProgressMap: Map<string, TextReadingPosition> = new Map();
  @Param visible: boolean = false;
  @Local showBookActions: boolean = false;
  @Local removingBook: boolean = false;
  @Local isManaging: boolean = false;
  @Local selectedBookIds: Set<string> = new Set();
  @Local showBatchDelete: boolean = false;
  @Local deleteLocalFiles: boolean = false;
  private pendingSelection: string = '';
  private pendingManagementExit: boolean = false;
  private favoriteIdsByBookId: Map<string, string[]> = new Map();
  private favoritesLoadSerial: number = 0;
  private pendingRemoval: Book | null = null;
  private pendingDeleteFiles: boolean = false;

  @Param navStack: NavPathStack = new NavPathStack();
  @Event onBookTap: (id: string) => void = () => {};
  @Event onGotoStore: () => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};

  private context: common.UIAbilityContext | null = null;
  private listScroller: Scroller = new Scroller();
  private bookDataSource: BookDataSource = new BookDataSource();
  private historyUpdatedHandler: (e: emitter.EventData) => void = (e) => this.onHistoryUpdated(e);
  /** 加入/移出书架后重新拉书清单。 */
  private favoritesChangedHandler: () => void = () => {
    if (!this.removingBook) this.loadFavorites();
  };
  private textProgressLoadSerial: number = 0;
  private textProgressChangedHandler: () => void = () => { this.refreshTextProgress(); };

  @Computed
  get shelfAudioCount(): number {
    return this.favoriteBooks.filter((book: Book): boolean => book.contentType !== 'text').length;
  }

  @Computed
  get shelfTextCount(): number {
    return this.favoriteBooks.filter((book: Book): boolean => book.contentType === 'text').length;
  }

  @Computed
  get shelfFilterItems(): SegmentButtonV2Items {
    return new SegmentButtonV2Items([
      { text: this.shelfFilterText($r('app.string.shelf_filter_all_count'), this.favoriteBooks.length) },
      { text: this.shelfFilterText($r('app.string.shelf_filter_audio_count'), this.shelfAudioCount) },
      { text: this.shelfFilterText($r('app.string.shelf_filter_text_count'), this.shelfTextCount) }
    ]);
  }

  private shelfFilterText(label: Resource, count: number): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(label.id, count) ?? count.toString();
  }

  private getChapterCount(book: Book): number {
    return book.chapters && book.chapters.length > 0 ? book.chapters.length : (book.chapterCount || 0);
  }

  /** 汇总每本书的最新集数：优先章节匹配，失败时使用独立进度中已落盘的章节序号。 */
  private async buildChapterIndexMap(books: Book[], historyMap: Record<string, PlayHistoryItem>):
    Promise<Record<string, number>> {
    const idxMap: Record<string, number> = {};
    for (const book of books) {
      const chapterCount = this.getChapterCount(book);
      if (chapterCount <= 0) continue;

      const progress = await PreferenceService.getProgress(book.id);
      const history = historyMap[book.id];
      let idx = -1;
      if (progress && book.chapters && book.chapters.length > 0) {
        idx = DataService.resolveChapterIndex(book, progress.chapterId, progress.chapterTitle);
      }
      if (idx < 0 && progress && progress.chapterIndex >= 0 && progress.chapterIndex < chapterCount) {
        idx = progress.chapterIndex;
      }
      if (idx < 0 && history && book.chapters && book.chapters.length > 0) {
        idx = DataService.resolveChapterIndex(book, history.chapterId, history.chapterTitle);
      }
      if (idx >= 0 && idx < chapterCount) idxMap[book.id] = idx;
    }
    return idxMap;
  }

  private syncFavoriteBook(updatedBook: Book): void {
    const books = this.favoriteBooks.map((book: Book): Book => book.id === updatedBook.id ? updatedBook : book);
    this.favoriteBooks = books;
    this.bookDataSource.setBooks(this.filteredBooks(books));
  }

  aboutToAppear(): void {
    this.onBackHandlerChange((): boolean => this.handleManageBack());
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadFavorites();
    emitter.on(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
    emitter.on(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
    emitter.on(EVT_TEXT_READING_PROGRESS_CHANGED, this.textProgressChangedHandler);
    this.onScrollerReady(this.listScroller);
  }

  aboutToDisappear(): void {
    this.onBackHandlerChange(undefined);
    this.favoritesLoadSerial++;
    emitter.off(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
    emitter.off(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
    emitter.off(EVT_TEXT_READING_PROGRESS_CHANGED, this.textProgressChangedHandler);
    this.textProgressLoadSerial++;
  }

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.loadFavorites();
    } else if (!this.removingBook) {
      this.exitManagement();
    }
  }

  /** 收到播放进度更新事件:只重算历史相关 map,不重拉书清单,避免列表抖动 */
  private async onHistoryUpdated(_e: emitter.EventData): Promise<void> {
    if (!this.context || this.favoriteBooks.length === 0) return;
    const history = await PreferenceService.getHistory();
    const map: Record<string, PlayHistoryItem> = {};
    for (const item of history) {
      if (!map[item.bookId]) {
        map[item.bookId] = item;
      }
    }
    const idxMap = await this.buildChapterIndexMap(this.favoriteBooks, map);
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
  }

  async loadFavorites(): Promise<void> {
    if (!this.context) return;
    const serial = ++this.favoritesLoadSerial;
    // 刷新已导入规则源索引，来源库不可用时在线收藏不会被误判为可用。
    await SourceDataService.getSources();
    const ids = await PreferenceService.getFavorites();
    const allBooks = await DataService.getBooks(this.context);
    const byId = new Map<string, Book>();
    for (const book of allBooks) {
      if (book && book.id) {
        byId.set(book.id, book);
      }
    }

    const history = await PreferenceService.getHistory();
    const map: Record<string, PlayHistoryItem> = {};
    for (const item of history) {
      if (!map[item.bookId]) {
        map[item.bookId] = item;
      }
    }

    const lastPlayed = await PreferenceService.getLastPlayed();
    const books: Book[] = [];
    const aliases: Map<string, string[]> = new Map();
    let missingCount = 0;
    for (const id of ids) {
      const book = byId.get(id);
      if (book) {
        if (this.isSupportedBook(book)) {
          if (!aliases.has(book.id)) books.push(book);
          aliases.set(book.id, (aliases.get(book.id) ?? []).concat(id));
        }
        continue;
      }
      const progress = await PreferenceService.getProgress(id);
      const chapterTitle = map[id]?.chapterTitle ?? progress?.chapterTitle ??
        (lastPlayed?.bookId === id ? (lastPlayed.chapterTitle ?? '') : '');
      const chapterId = map[id]?.chapterId ?? progress?.chapterId ??
        (lastPlayed?.bookId === id ? lastPlayed.chapterId : '');
      const chapterIndex = progress?.chapterIndex ?? this.parseLegacyChapterIndex(chapterId);
      const alias = this.findFavoriteAlias(id, chapterTitle, chapterIndex, allBooks);
      if (alias && this.isSupportedBook(alias)) {
        if (!aliases.has(alias.id)) books.push(alias);
        aliases.set(alias.id, (aliases.get(alias.id) ?? []).concat(id));
        continue;
      }
      books.push(this.createMissingFavoriteBook(id, chapterTitle));
      aliases.set(id, [id]);
      missingCount++;
    }
    this.missingFavoriteCount = missingCount;

    // 修复历史缓存中的双倍章节:按 title + index 去重(title 稳定,不会被播放覆盖)
    for (const b of books) {
      if (this.isMissingCachedBook(b)) continue;
      if (b.chapters && b.chapters.length > 0) {
        const seen = new Set<string>();
        const unique: Chapter[] = [];
        for (const ch of b.chapters) {
          // 去重键用章节页 URL(唯一且稳定):originSourceValue 不会被播放期解析覆盖。
          // 旧实现用 title 去重会误删"同名不同章"(网文源极常见,如多章都叫"正文"),
          // 导致刷新拿到的新章节数(如 758)被吞回旧值(472)。
          const key = ch.originSourceValue || ch.source.value || ch.title;
          if (seen.has(key)) continue;
          seen.add(key);
          unique.push(ch);
        }
        if (unique.length !== b.chapters.length) {
          b.chapters = unique;
          b.chapterCount = unique.length;
          // 持久化修正后的数据
          await DataService.upsertCachedBook(b);
        } else if (b.chapterCount !== b.chapters.length) {
          b.chapterCount = b.chapters.length;
          await DataService.upsertCachedBook(b);
        }
      }
    }

    // 预算每本书的最新章节序号，避免 build / click 反复解析，也兼容章节 ID 已变化的旧进度。
    const idxMap = await this.buildChapterIndexMap(books, map);
    if (serial !== this.favoritesLoadSerial) return;
    this.favoriteIdsByBookId = aliases;
    this.favoriteBooks = books;
    await this.refreshTextProgress();
    if (serial !== this.favoritesLoadSerial) return;
    this.bookDataSource.setBooks(this.filteredBooks(books));
    const visibleIds = new Set(this.filteredBooks(books).map((book: Book): string => book.id));
    this.selectedBookIds = new Set(Array.from(this.selectedBookIds).filter((id: string): boolean => visibleIds.has(id)));
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
    this.loading = false;
  }

  /** 阅读器覆盖书架时 Tab 不变；由保存事件更新进度，避免重新加载书单。 */
  private async refreshTextProgress(): Promise<void> {
    const context = this.context;
    if (context === null) return;
    const serial = ++this.textProgressLoadSerial;
    const textProgress = new Map<string, TextReadingPosition>();
    try {
      for (const book of this.favoriteBooks) {
        if (book.contentType !== 'text') continue;
        const position = await TextReadingProgressService.get(context, book.id);
        if (position) textProgress.set(book.id, position);
      }
      if (serial === this.textProgressLoadSerial) this.textProgressMap = textProgress;
    } catch (_e) {
      // 读取失败保留已有展示，后续保存或刷新时重试。
    }
  }

  private createMissingFavoriteBook(id: string, chapterTitle: string): Book {
    const inferredTitle = this.legacyBookNameFromChapterTitle(chapterTitle);
    const isText = id.startsWith('search_text_') || id.startsWith('home_text_');
    return {
      id,
      contentType: isText ? 'text' : 'audio',
      title: inferredTitle || (isText ? '电子书缓存缺失' : '有声书缓存缺失'),
      author: '收藏记录仍在',
      narrator: '',
      cover: '',
      category: isText ? '电子书' : '有声书',
      intro: '',
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: ['cache_missing'],
      chapters: [],
      bookUrl: '',
      sourceUrl: ''
    };
  }

  private createFavoriteAliasBook(id: string, source: Book): Book {
    const book = cloneBook(source);
    book.id = id;
    const tags = book.tags ? book.tags.filter((tag: string): boolean =>
      tag !== 'cache_missing' && tag !== 'cache_alias') : [];
    tags.push('cache_alias');
    book.tags = tags;
    book.chapters = book.chapters ? book.chapters.map((ch: Chapter, idx: number): Chapter => {
      const next = cloneChapter(ch);
      next.id = `${id}-c${idx}`;
      next.index = idx + 1;
      return next;
    }) : [];
    book.chapterCount = book.chapters.length > 0 ? book.chapters.length : book.chapterCount;
    return book;
  }

  private isMissingCachedBook(book: Book): boolean {
    return book.tags ? book.tags.includes('cache_missing') : false;
  }

  private isFavoriteAliasBook(book: Book): boolean {
    return book.tags ? book.tags.includes('cache_alias') : false;
  }

  /** 仅展示本地文件和仍然安装的用户规则源。 */
  private isSupportedBook(book: Book): boolean {
    if (!book.sourceUrl) return true;
    return SourceDataService.isLocalRuleSource(book.sourceUrl);
  }

  private legacyBookNameFromChapterTitle(title: string): string {
    const t = title.trim();
    if (!t || t.startsWith('第') || /^[0-9０-９]/.test(t)) return '';
    const space = t.search(/[\s　]/);
    if (space <= 0) return '';
    const name = t.substring(0, space).trim();
    if (!name || name.startsWith('第') || /^[0-9０-９]/.test(name)) return '';
    return name;
  }

  private normalizeRecoverName(name: string): string {
    return name
      .replace(/[《》【】\[\]（）()：:，,。.\s　]/g, '')
      .trim();
  }

  private parseLegacyChapterIndex(chapterId: string): number {
    const m = chapterId.match(/-c(\d+)$/);
    if (!m) return -1;
    const idx = parseInt(m[1], 10);
    return isNaN(idx) ? -1 : idx;
  }

  /**
   * 只做运行期别名,不写 favorite_book_ids。
   * 规则故意保守:旧标题里能取到书名,且缓存池里只有一本完整标题精确匹配的有声书,才用于展示和打开。
   */
  private findFavoriteAlias(oldId: string, chapterTitle: string, chapterIndex: number, books: Book[]): Book | null {
    const oldIsAudio = oldId.startsWith('search_audio_') || oldId.startsWith('home_audio_');
    if (!oldIsAudio) return null;

    const name = this.normalizeRecoverName(this.legacyBookNameFromChapterTitle(chapterTitle));
    if (!name) return null;
    const candidates: Book[] = [];
    for (const book of books) {
      if (!this.isSupportedBook(book)) continue;
      if (this.normalizeRecoverName(book.title) !== name) continue;
      if (chapterIndex >= 0 && book.chapters && chapterIndex >= book.chapters.length) continue;
      candidates.push(book);
    }
    if (candidates.length !== 1) return null;
    return this.createFavoriteAliasBook(oldId, candidates[0]);
  }

  /** 下拉刷新:从书源重新加载在线书籍的最新数据 */
  private async refreshOnlineBooks(): Promise<void> {
    if (!this.context) return;
    // 所有在线收藏统一通过已导入规则源刷新详情与目录。
    const onlineBooks = this.favoriteBooks.filter(b =>
      !this.isMissingCachedBook(b) && !this.isFavoriteAliasBook(b) &&
        !b.id.startsWith('import_') && b.bookUrl && b.sourceUrl);
    if (onlineBooks.length === 0) {
      try {
        const message = this.missingFavoriteCount > 0 ?
          `有 ${this.missingFavoriteCount} 本收藏缓存缺失，请重新搜索加入` : '书架中没有在线书籍';
        this.getUIContext().getPromptAction().showToast({ message });
      } catch (_e) { /* ignore */ }
      return;
    }
    this.refreshProgress = `正在刷新 0/${onlineBooks.length}`;
    const sources = await SourceDataService.getSources();
    let updated = 0;
    let failed = 0;
    const updatedBooks: BookUpdateInfo[] = [];
    // 并行刷新所有在线书
    const tasks = onlineBooks.map(async (book, idx) => {
      try {
        const source = sources.find(s => s.bookSourceUrl === book.sourceUrl);
        if (!source) {
          failed++;
          return;
        }
        const nextBook = cloneBook(book);
        // 1. 获取最新书籍信息
        const bookInfo = await BookSourceService.getBookInfo(source, nextBook.bookUrl, nextBook.variables);
        let hasChange = false;
        let chapterChanged = false;
        const oldCount = this.getChapterCount(book);
        let newCount = oldCount;
        if (bookInfo) {
          // 更新封面/简介/作者等元数据
          if (bookInfo.coverUrl && bookInfo.coverUrl !== nextBook.cover) {
            nextBook.cover = bookInfo.coverUrl;
            hasChange = true;
          }
          if (bookInfo.intro && bookInfo.intro !== nextBook.intro) {
            nextBook.intro = bookInfo.intro;
            hasChange = true;
          }
          if (bookInfo.author && bookInfo.author !== nextBook.author) {
            nextBook.author = bookInfo.author;
            hasChange = true;
          }
          // 合并变量
          if (bookInfo.wordCount && bookInfo.wordCount !== nextBook.wordCount) {
            nextBook.wordCount = bookInfo.wordCount;
            hasChange = true;
          }
          if (bookInfo.lastChapter && bookInfo.lastChapter !== nextBook.latestChapterTitle) {
            nextBook.latestChapterTitle = bookInfo.lastChapter;
            hasChange = true;
          }
          if (bookInfo.updateTime && bookInfo.updateTime !== nextBook.updateTime) {
            nextBook.updateTime = bookInfo.updateTime;
            hasChange = true;
          }
          if (bookInfo.variables) {
            if (!nextBook.variables) nextBook.variables = {};
            for (const k of Object.keys(bookInfo.variables)) {
              nextBook.variables[k] = bookInfo.variables[k];
            }
          }
        }
        // 2. 获取最新章节列表
        const mergedVars: Record<string, string> = {};
        if (nextBook.variables) {
          for (const k of Object.keys(nextBook.variables)) mergedVars[k] = nextBook.variables[k];
        }
        if (bookInfo?.variables) {
          for (const k of Object.keys(bookInfo.variables)) mergedVars[k] = bookInfo.variables[k];
        }
        const tocUrl = bookInfo?.tocUrl || nextBook.bookUrl;
        const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars, nextBook.title);
        if (tocItems.length > 0) {
          const chapters = tocItems.map((item: TocItem, i: number): Chapter => ({
            id: `${nextBook.id}-c${i}`,
            index: i + 1,
            title: item.name,
            duration: item.duration || 0,
            source: { type: 'url', value: item.url },
            originSourceValue: item.url,
            variables: item.variables
          }));
          if (chaptersChanged(nextBook.chapters || [], chapters)) {
            hasChange = true;
          }
          nextBook.chapters = chapters;
          nextBook.chapterCount = chapters.length;
          newCount = nextBook.chapterCount;
          chapterChanged = newCount > oldCount;
        } else if (nextBook.chapters && nextBook.chapters.length > 0 && nextBook.chapterCount !== nextBook.chapters.length) {
          nextBook.chapterCount = nextBook.chapters.length;
          newCount = nextBook.chapterCount;
          hasChange = true;
        }
        if (hasChange) {
          await DataService.upsertCachedBook(nextBook);
          SearchCache.put(nextBook);
          this.syncFavoriteBook(nextBook);
          updated++;
          if (chapterChanged) {
            const updateInfo: BookUpdateInfo = {
              title: nextBook.title,
              oldCount,
              newCount,
              unit: nextBook.contentType === 'text' ? '章' : '集'
            };
            updatedBooks.push(updateInfo);
          }
        }
      } catch (_e) {
        failed++;
      } finally {
        this.refreshProgress = `正在刷新 ${idx + 1}/${onlineBooks.length}`;
      }
    });
    await Promise.all(tasks);
    // 刷新完成后重新加载
    await this.loadFavorites();
    this.refreshProgress = '';
    this.showRefreshResult(updatedBooks, updated, failed);
  }

  /** 把刷新结果以对话框形式呈现:有新集的书逐本列出,无新集只 toast */
  private showRefreshResult(updatedBooks: BookUpdateInfo[], updated: number, failed: number): void {
    const prompt = this.getUIContext().getPromptAction();
    if (updatedBooks.length > 0) {
      // 按新增集数从多到少排,用户最关心更新最多的那本
      updatedBooks.sort((a, b) => (b.newCount - b.oldCount) - (a.newCount - a.oldCount));
      const lines = updatedBooks.map(u => {
        const delta = u.newCount - u.oldCount;
        return `《${u.title}》  ${u.oldCount} → ${u.newCount} ${u.unit}（+${delta}）`;
      });
      const tail = failed > 0 ? `\n\n${failed} 本刷新失败` : '';
      prompt.showDialog({
        title: `${updatedBooks.length} 本书有更新`,
        message: lines.join('\n') + tail,
        buttons: [{ text: '知道了', color: $r('app.color.text_primary') }]
      }).catch(() => { /* ignore */ });
      return;
    }
    let msg = '所有书籍已是最新';
    if (updated > 0) {
      // 元数据(封面/简介/作者)有改但集数没变
      msg = `已更新 ${updated} 本书的资料${failed > 0 ? `，${failed} 本失败` : ''}`;
    } else if (failed > 0) {
      msg = `刷新完成，${failed} 本失败`;
    }
    try {
      prompt.showToast({ message: msg });
    } catch (_e) { /* ignore */ }
  }

  private getProgressText(book: Book): string {
    if (this.isMissingCachedBook(book)) {
      return '缓存缺失 · 重新搜索后加入';
    }
    if (book.contentType === 'text') {
      const position = this.textProgressMap.get(book.id);
      const chapterCount = this.getChapterCount(book);
      if (position && chapterCount > 0) {
        return `${Math.min(position.resourceIndex + 1, chapterCount)}/${chapterCount} 章`;
      }
      return chapterCount > 0 ? `共${chapterCount}章` : '未开始阅读';
    }
    const unit = '集';
    const chapterCount = this.getChapterCount(book);
    if (chapterCount > 0) {
      const idx = this.chapterIdxMap[book.id];
      if (idx !== undefined && idx >= 0) {
        return `${idx + 1}/${chapterCount} ${unit}`;
      }
      return `共${chapterCount}${unit}`;
    }
    return book.author || '';
  }

  private toggleViewMode(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
      this.viewMode = this.viewMode === 0 ? 1 : 0;
    });
  }

  private filteredBooks(books: Book[]): Book[] {
    if (this.shelfFilter === 1) return books.filter((book: Book): boolean => book.contentType !== 'text');
    if (this.shelfFilter === 2) return books.filter((book: Book): boolean => book.contentType === 'text');
    return books;
  }

  private selectShelfFilter(index: number): void {
    if (this.removingBook || this.showBatchDelete) return;
    if (index < 0 || index > 2 || this.shelfFilter === index) return;
    this.shelfFilter = index;
    this.selectedBookIds = new Set();
    this.bookDataSource.setBooks(this.filteredBooks(this.favoriteBooks));
  }

  private handleBookTap(book: Book): void {
    if (this.removingBook) return;
    if (this.isManaging) {
      this.toggleBookSelection(book.id);
      return;
    }
    if (this.isMissingCachedBook(book)) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '这本书的缓存快照缺失，请重新搜索后加入书架' });
      } catch (_e) { /* ignore */ }
      return;
    }
    const onPop = (): void => { this.loadFavorites(); };
    SearchCache.put(book);
    if (book.contentType === 'text') {
      const params = TextReaderRouteParams.of(book.id);
      this.navStack.pushPathByName('reader', params, onPop);
      return;
    }
    // 当前正在播这本书:不重新解析 URL,不带 chapter 参数,直接进 player 复用 live state。
    if (PlaybackStore.getInstance().isCurrentBook(book.id)) {
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', book.id, onPop, false);
      });
      return;
    }
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
    // 用校正后的章节 id(idx 可能因 TOC 重排已被标题校正过),
    // 直接传 history.chapterId 会让播放器再按旧 id 找回错位置
    const resolved = book.chapters[idx];
    const params: Record<string, Object> = {
      'bookId': book.id as Object,
      'chapterId': resolved.id as Object,
      'progressMs': history.progressMs as Object
    };
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', params, onPop, false);
    });
  }

  /** 老收藏的在线书没缓存章节时,先拉 toc 再恢复进度;期间禁用重复点击 */
  private async resumeOnlineWithToc(book: Book, history: PlayHistoryItem, onPop: () => void): Promise<void> {
    if (this.resolvingTocId) return;
    this.resolvingTocId = book.id;
    try {
      // 1) 先用本地缓存的章节目录(sidecar):瞬时、无网络、不弹"加载章节"
      const localToc = await DataService.getChaptersForBook(book.id);
      if (localToc.length > 0) {
        book.chapters = localToc;
        book.chapterCount = localToc.length;
        const localIdx = DataService.resolveChapterIndex(book, history.chapterId, history.chapterTitle);
        if (localIdx >= 0) {
          this.chapterIdxMap[book.id] = localIdx;
          SearchCache.put(book);
          const resolvedLocal = book.chapters[localIdx];
          const localParams: Record<string, Object> = {
            'bookId': book.id as Object,
            'chapterId': resolvedLocal.id as Object,
            'progressMs': history.progressMs as Object
          };
          this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
            this.navStack.pushPathByName('player', localParams, onPop, false);
          });
          return;
        }
        // 本地目录命中但定位不到章节(可能已下架/重排)→ 落到下面联网重拉刷新
      }
      // 2) 本地没有 → 联网拉取(此时才提示"加载章节")
      try {
        this.getUIContext().getPromptAction().showToast({ message: '加载章节中...' });
      } catch (_e) { /* ignore */ }
      const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
      if (!source) {
        this.getUIContext().getPromptAction().showToast({ message: '该内容来源已不可用，请重新搜索后加入书架' });
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
      const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars, book.title);
      if (tocItems.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '章节加载失败' });
        this.navStack.pushPathByName('detail', book.id, onPop);
        return;
      }
      book.chapters = tocItems.map((item: TocItem, idx: number): Chapter => ({
        id: `${book.id}-c${idx}`,
        index: idx + 1,
        title: item.name,
        duration: item.duration || 0,
        source: { type: 'url', value: item.url },
        originSourceValue: item.url,
        variables: item.variables
      }));
      book.chapterCount = book.chapters.length;
      // 持久化新 toc,下次点击不用再拉
      await DataService.upsertCachedBook(book);
      SearchCache.put(book);
      const idx = DataService.resolveChapterIndex(book, history.chapterId, history.chapterTitle);
      if (idx < 0) {
        // 标题和 id 都定位不回去(章节可能已下架) → 交给详情页让用户选
        this.navStack.pushPathByName('detail', book.id, onPop);
        return;
      }
      this.chapterIdxMap[book.id] = idx;
      // 传校正后章节的 id:连载在头部插新章后,旧 -c{idx} 已指向别的章节,
      // 标题校正拿到正确 idx,再取它的当前 id 给播放器
      const resolved = book.chapters[idx];
      const params: Record<string, Object> = {
        'bookId': book.id as Object,
        'chapterId': resolved.id as Object,
        'progressMs': history.progressMs as Object
      };
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', params, onPop, false);
    });
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '章节加载失败' });
      } catch (_e2) { /* ignore */ }
      this.navStack.pushPathByName('detail', book.id, onPop);
    } finally {
      this.resolvingTocId = '';
    }
  }

  private async removeActionBook(book: Book, deleteFiles: boolean): Promise<void> {
    if (this.removingBook) return;
    if (this.showBookActions) {
      // 先让原生菜单完成退场，避免删除宿主节点后菜单遮罩和点击锁残留。
      this.pendingRemoval = book;
      this.pendingDeleteFiles = deleteFiles;
      return;
    }
    this.removingBook = true;
    try { await this.doRemove(book.id, deleteFiles); }
    finally { this.removingBook = false; this.showBookActions = false; }
  }

  private async deleteBookFilesAndRecords(bookId: string): Promise<void> {
    if (!this.context) return;
    const ids = new Set<string>(this.favoriteIdsByBookId.get(bookId) ?? []);
    ids.add(bookId);
    // 兼容同一有声书由首页/搜索产生的旧 id，避免未收藏页残留重复记录。
    for (const id of Array.from(ids)) {
      if (id.startsWith('search_audio_')) ids.add(id.replace('search_audio_', 'home_audio_'));
      if (id.startsWith('home_audio_')) ids.add(id.replace('home_audio_', 'search_audio_'));
    }
    const audio = AudioService.getInstance();
    const stopAudio = ids.has(PlaybackStore.getInstance().getCurrentBookId());
    const speech = TextToSpeechService.getInstance();
    if (ids.has(speech.state.bookId)) speech.stop();
    try {
      if (stopAudio) await audio.stopForClear();
      await DownloadService.getInstance().deleteBookDownload(bookId);
      if (bookId.startsWith('import_')) await DataService.removeImportedBook(bookId);
      for (const id of ids) {
        await PreferenceService.removeHistory(id);
        await PreferenceService.removeProgress(id);
        await TextReadingProgressService.remove(this.context, id);
      }
      await speech.removeSavedPositions(this.context, Array.from(ids));
      await StatsService.removeBookStats(Array.from(ids));
    } finally {
      if (stopAudio) audio.unfreezePersist();
    }
  }

  private enterManagement(bookId: string = ''): void {
    if (this.removingBook || this.isRefreshing || this.resolvingTocId.length > 0 ||
      this.filteredBooks(this.favoriteBooks).length === 0) return;
    if (this.showBookActions) {
      this.pendingSelection = bookId;
      return;
    }
    this.isManaging = true;
    if (bookId.length > 0) {
      const selected = new Set(this.selectedBookIds);
      selected.add(bookId);
      this.selectedBookIds = selected;
    }
  }

  private exitManagement(): void {
    if (this.removingBook) return;
    this.showBatchDelete = false;
    this.isManaging = false;
    this.selectedBookIds = new Set();
  }

  private handleManageBack(): boolean {
    if (this.removingBook) return true;
    if (this.showBatchDelete) {
      this.showBatchDelete = false;
      return true;
    }
    if (!this.isManaging) return false;
    this.exitManagement();
    return true;
  }

  private toggleBookSelection(bookId: string): void {
    if (this.removingBook || this.showBatchDelete) return;
    const selected = new Set(this.selectedBookIds);
    if (selected.has(bookId)) selected.delete(bookId);
    else selected.add(bookId);
    this.selectedBookIds = selected;
  }

  private allVisibleBooksSelected(): boolean {
    const books = this.filteredBooks(this.favoriteBooks);
    return books.length > 0 && books.every((book: Book): boolean => this.selectedBookIds.has(book.id));
  }

  private toggleSelectAllBooks(): void {
    if (this.removingBook || this.showBatchDelete) return;
    this.selectedBookIds = this.allVisibleBooksSelected() ? new Set() :
      new Set(this.filteredBooks(this.favoriteBooks).map((book: Book): string => book.id));
  }

  private confirmBatchDelete(): void {
    if (this.selectedBookIds.size === 0 || this.removingBook) return;
    this.deleteLocalFiles = false;
    this.showBatchDelete = true;
  }

  private async deleteSelectedBooks(): Promise<void> {
    if (this.removingBook || !this.showBatchDelete || !this.context) return;
    const books = this.filteredBooks(this.favoriteBooks).filter((book: Book): boolean =>
      this.selectedBookIds.has(book.id));
    if (books.length === 0) { this.showBatchDelete = false; return; }
    const deleteFiles = this.deleteLocalFiles;
    this.removingBook = true;
    this.favoritesLoadSerial++;
    const removedBooks: string[] = [];
    const removedFavoriteIds: string[] = [];
    const failedIds: Set<string> = new Set();
    try {
      // 文件操作串行，避免多个删除同时覆盖本地书籍索引；一项失败不阻断其他项。
      for (const book of books) {
        try {
          if (deleteFiles) {
            await this.deleteBookFilesAndRecords(book.id);
          }
          removedBooks.push(book.id);
          removedFavoriteIds.push(...(this.favoriteIdsByBookId.get(book.id) ?? [book.id]));
        } catch (_error) {
          failedIds.add(book.id);
        }
      }
      await PreferenceService.removeFavorites(removedFavoriteIds);
      this.selectedBookIds = failedIds;
      this.isManaging = failedIds.size > 0;
      this.showBatchDelete = false;
      this.getUIContext().getPromptAction().showToast({
        message: failedIds.size > 0 ? $r('app.string.shelf_batch_partial', removedBooks.length, failedIds.size) :
          $r('app.string.shelf_batch_removed', removedBooks.length)
      });
    } catch (_error) {
      this.showBatchDelete = false;
      this.getUIContext().getPromptAction().showToast({ message: deleteFiles ?
        $r('app.string.shelf_batch_files_failed') : $r('app.string.shelf_batch_failed') });
    } finally {
      try { await this.loadFavorites(); }
      catch (_error) { /* 保留当前选择，允许重试刷新。 */ }
      this.removingBook = false;
      if (!this.visible) this.exitManagement();
    }
  }

  private bookMenuOptions(): ContextMenuOptions {
    const options: ContextMenuOptions = {
      preview: MenuPreviewMode.NONE,
      backgroundColor: AppMaterial.SheetBackground,
      backgroundBlurStyle: AppMaterial.SheetBlur,
      onAppear: (): void => { this.showBookActions = true; },
      onDisappear: (): void => {
        this.showBookActions = false;
        const selectedId = this.pendingSelection;
        this.pendingSelection = '';
        if (selectedId.length > 0) this.enterManagement(selectedId);
        if (this.pendingManagementExit) {
          this.pendingManagementExit = false;
          this.exitManagement();
        }
        const book = this.pendingRemoval;
        this.pendingRemoval = null;
        if (book !== null) this.removeActionBook(book, this.pendingDeleteFiles);
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    return options;
  }

  @Builder
  bookActions(book: Book) {
    Menu() {
      MenuItem({ content: this.isManaging ? $r('app.string.common_done') : $r('app.string.shelf_manage') })
        .enabled(!this.removingBook && !this.isRefreshing)
        .onClick((): void => {
          if (this.isManaging) this.pendingManagementExit = true;
          else this.enterManagement(book.id);
        })
      if (!this.isManaging) {
      MenuItem({ content: $r('app.string.shelf_delete_only') })
        .contentFontColor(AppColor.Brand)
        .onClick((): void => { this.removeActionBook(book, false); })
      MenuItem({ content: $r('app.string.shelf_delete_local') })
        .contentFontColor($r('sys.color.ohos_id_color_warning'))
        .onClick((): void => { this.removeActionBook(book, true); })
      }
    }
  }

  private async doRemove(bookId: string, deleteFiles: boolean): Promise<void> {
    if (!this.context) return;
    try {
      if (deleteFiles) {
        await this.deleteBookFilesAndRecords(bookId);
      }
      await PreferenceService.removeFavorites(this.favoriteIdsByBookId.get(bookId) ?? [bookId]);
      // 移出书架保留书籍身份，未收藏记录仍需续读。
      await this.loadFavorites();
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '移除失败，请重试' });
      } catch (_e2) { /* ignore */ }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // L0 暖色渐变背景（满屏，与首页一致）
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

      HdsNavigation() {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.refreshIndicator() }) {
          if (this.viewMode === 0) {
            // 三列书卡复用 List 的首尾边界，内容不足一屏时回弹后仍停留在安全起点。
            List({ scroller: this.listScroller, space: AppSpace.Md }) {
              LazyForEach(this.bookDataSource, (book: Book) => {
                ListItem() {
                  this.buildBookTile(book)
                }
                // key 带上"总章数 + 当前章索引":LazyForEach 对相同 key 的项会复用旧节点、
                // 不重跑 buildBookTile。刷新后章数 742→758 但 book.id 不变 → 贴片卡在旧值。
                // 把会变的展示量编进 key,值一变 key 变 → 强制重建贴片。
              }, (book: Book) => `${book.id}:${this.getChapterCount(book)}:${this.chapterIdxMap[book.id] ?? -1}`)
              if (!this.isManaging) {
                ListItem() { this.buildAddTile() }
              }
            }
            .lanes(3, AppSpace.Sm)
            .cachedCount(6)
            .width('100%')
            .height('100%')
            .padding({
              left: AppSpace.Md,
              right: AppSpace.Md
            })
            .contentStartOffset(WindowUtils.getStatusBarHeightVp() + SHELF_FILTER_TOP_OFFSET +
              SHELF_FILTER_ROW_HEIGHT + SHELF_CONTENT_GAP)
            .contentEndOffset(WindowUtils.getFloatingTabBottomVp() + (this.isManaging ? 72 : 0))
            .scrollBar(BarState.Off)
            // 空书架只有添加入口，也需要在上下边界提供原生回弹。
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .backgroundColor(Color.Transparent)
          } else {
            List({ scroller: this.listScroller }) {
              LazyForEach(this.bookDataSource, (book: Book) => {
                ListItem() {
                  this.buildListItem(book)
                }
              }, (book: Book) => `${book.id}:${this.getChapterCount(book)}:${this.chapterIdxMap[book.id] ?? -1}`)
              if (!this.isManaging) {
                ListItem() { this.buildAddListItem() }
              }
            }
            .cachedCount(6)
            .width('100%')
            .height('100%')
            .padding({
              left: AppSpace.Md,
              right: AppSpace.Md
            })
            .contentStartOffset(WindowUtils.getStatusBarHeightVp() + SHELF_FILTER_TOP_OFFSET +
              SHELF_FILTER_ROW_HEIGHT + SHELF_CONTENT_GAP)
            .contentEndOffset(WindowUtils.getFloatingTabBottomVp() + (this.isManaging ? 72 : 0))
            .divider({
              strokeWidth: 1,
              color: $r('sys.color.comp_divider'),
              startMargin: 88
            })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .backgroundColor(Color.Transparent)
          }
        }
        .onRefreshing(() => {
          this.refreshOnlineBooks().finally(() => { this.isRefreshing = false; });
        })
        .refreshOffset(64)
        .pullToRefresh(!this.isManaging && !this.removingBook)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: this.isManaging ? $r('app.string.shelf_selected_count', this.selectedBookIds.size) :
              $r('app.string.shelf_title')
          },
          bottomBuilder: {
            builder: (): void => this.buildShelfFilter(),
            height: SHELF_FILTER_ROW_HEIGHT
          },
          menu: {
            value: [{
              content: {
                icon: this.viewMode === 0
                  ? $r('sys.symbol.list_bullet')
                  : $r('sys.symbol.square_grid_2x2'),
                label: this.viewMode === 0 ? '切换为列表' : '切换为网格',
                action: () => { if (!this.removingBook && !this.showBatchDelete) this.toggleViewMode(); }
              }
            }]
          }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: HdsCompat.scrollEffect
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          systemMaterialEffect: HdsCompat.material
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .bindToScrollable([this.listScroller])
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      if (this.isManaging) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.buildBatchActions()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showBatchDelete, this.buildBatchDeleteSheet(), {
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: true,
      backgroundColor: AppMaterial.SheetBackground,
      blurStyle: AppMaterial.SheetBlur,
      systemMaterial: PlatformCompat.immersiveMaterial ? AppMaterial.Sheet : undefined,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.removingBook) action.dismiss();
      }
    })
  }

  @Builder
  buildSelectionMark(book: Book) {
    Stack() {
      if (this.selectedBookIds.has(book.id)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColor.OnBrand])
      }
    }
    .width(26).height(26)
    .borderRadius(AppRadius.Pill)
    .backgroundColor(this.selectedBookIds.has(book.id) ? AppColor.Brand : $r('sys.color.comp_background_primary'))
    .border({ width: 1.5, color: this.selectedBookIds.has(book.id) ? AppColor.Brand : $r('sys.color.font_tertiary') })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  buildBatchActions() {
    ShelfBatchActions({
      selectedCount: this.selectedBookIds.size,
      totalCount: this.filteredBooks(this.favoriteBooks).length,
      allSelected: this.allVisibleBooksSelected(),
      busy: this.removingBook,
      onSelectAll: (): void => this.toggleSelectAllBooks(),
      onDelete: (): void => this.confirmBatchDelete()
    })
      .width(`calc(100% - ${AppSpace.Md * 2}vp)`)
      .margin({ bottom: WindowUtils.getFloatingTabBottomVp() })
  }

  @Builder
  buildBatchDeleteSheet() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.shelf_batch_title', this.selectedBookIds.size))
        .fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text($r('app.string.shelf_batch_description'))
        .fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).width('100%')
      Row({ space: AppSpace.Sm }) {
        Checkbox({ name: 'shelfDeleteLocalFiles' })
          .select(this.deleteLocalFiles).selectedColor(AppColor.Brand)
          .enabled(!this.removingBook)
          .onChange((checked: boolean): void => { this.deleteLocalFiles = checked; })
          .accessibilityText($r('app.string.shelf_batch_delete_files'))
        Column({ space: 4 }) {
          Text($r('app.string.shelf_batch_delete_files'))
            .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).width('100%')
          Text($r('app.string.shelf_batch_files_hint'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
        }.layoutWeight(1)
        .onClick((): void => { if (!this.removingBook) this.deleteLocalFiles = !this.deleteLocalFiles; })
      }.width('100%').padding(AppSpace.Sm)
      .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(AppRadius.Md)
      Row({ space: AppSpace.Md }) {
        Button($r('app.string.common_cancel'), { type: ButtonType.Capsule })
          .layoutWeight(1).height(48).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
          .enabled(!this.removingBook).onClick((): void => { this.showBatchDelete = false; })
        Button({ type: ButtonType.Capsule }) {
          Row({ space: AppSpace.Xs }) {
            if (this.removingBook) {
              LoadingProgress().width(20).height(20).color(AppColor.Brand)
            }
            Text(this.removingBook ? $r('app.string.shelf_batch_deleting') :
              $r('app.string.shelf_delete_count', this.selectedBookIds.size))
              .fontSize(AppFont.Body).fontColor(Color.White)
          }
        }.layoutWeight(1).height(48).backgroundColor($r('sys.color.ohos_id_color_warning'))
        .enabled(!this.removingBook && this.selectedBookIds.size > 0)
        .onClick((): void => { this.deleteSelectedBooks(); })
      }.width('100%')
    }.width('100%').padding({ left: 24, right: 24, top: 12, bottom: 24 + WindowUtils.getBottomSafeVp() })
  }

  @Builder
  refreshIndicator() {
    Row() {
      if (this.isRefreshing) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AppColor.Brand)
      }
    }
    .height(56)
    .justifyContent(FlexAlign.Center)
      .translate({
        y: WindowUtils.getStatusBarHeightVp() + SHELF_FILTER_TOP_OFFSET + SHELF_FILTER_ROW_HEIGHT
      })
  }

  @Builder
  buildShelfFilter() {
    Row() {
      Stack({ alignContent: Alignment.Bottom }) {
        CapsuleSegmentButtonV2({
          items: this.shelfFilterItems,
          selectedIndex: this.shelfFilter,
          $selectedIndex: (index: number): void => this.selectShelfFilter(index),
          itemFontSize: LengthMetrics.fp(13),
          itemSelectedFontSize: LengthMetrics.fp(13),
          itemFontColor: ColorMetrics.resourceColor($r('sys.color.font_secondary')),
          itemSelectedFontColor: ColorMetrics.resourceColor(HomeTheme.Accent),
          itemSelectedBackgroundColor: ColorMetrics.resourceColor(Color.Transparent),
          itemMinHeight: LengthMetrics.vp(34),
          buttonMinHeight: LengthMetrics.vp(38),
          buttonPadding: LengthMetrics.vp(2),
          backgroundSystemMaterial: AppMaterial.FloatingControl
        })
        .width('100%')

        Row() {
          ForEach([0, 1, 2], (index: number) => {
            Column() {
              Row()
                .width(18)
                .height(2)
                .borderRadius(1)
                .backgroundColor(HomeTheme.Accent)
                .opacity(this.shelfFilter === index ? 1 : 0)
            }
            .layoutWeight(1)
          }, (index: number) => index.toString())
        }
        .width('100%')
        .padding({ left: 2, right: 2, bottom: 4 })
        .hitTestBehavior(HitTestMode.None)
      }
      .layoutWeight(1)

    }
    .width('100%')
    .height(SHELF_FILTER_ROW_HEIGHT)
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildBookTile(book: Book) {
    Column({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isMissingCachedBook(book)) {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#FFE8D6D6')
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(34)
              .fontColor(['#B3261E'])
            Text('缓存缺失')
              .fontSize(AppFont.Caption)
              .fontColor('#B3261E')
              .fontWeight(FontWeight.Medium)
              .margin({ top: 48 })
          }
          .width('100%')
          .aspectRatio(BOOKSHELF_COVER_RATIO)
          .borderRadius(AppRadius.Md)
          .clip(true)
        } else if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width('100%')
            .aspectRatio(BOOKSHELF_COVER_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
            .alt($r('app.media.app_icon_legacy'))
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (book.cover && (book.cover.startsWith('/data/') || book.cover.startsWith('file://'))) {
          Image('file://' + book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(BOOKSHELF_COVER_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (book.cover) {
          Image($rawfile(book.cover))
            .width('100%')
            .aspectRatio(BOOKSHELF_COVER_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          // 无封面:用 app 图标占位(替代旧的绿色书形/品牌色占位)
          Image($r('app.media.app_icon_legacy'))
            .draggable(false)
            .width('100%')
            .aspectRatio(BOOKSHELF_COVER_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        }
        this.buildTypeBadge(false, book.contentType === 'text')
        if (this.isManaging) {
          Row() {
            Blank()
            this.buildSelectionMark(book)
          }.width('100%').padding(6)
        }
      }
      .width('100%')
      .borderRadius(AppRadius.Md)
      .clip(true)
      .border({ width: this.isManaging && this.selectedBookIds.has(book.id) ? 2 : 0,
        color: AppColor.Brand, radius: AppRadius.Md })
      .shadow({ radius: 4, color: '#1A000000', offsetY: 1 })
      // 展示子树不参与触摸命中，封面/占位图的原生长按不能抢走书卡菜单。
      .hitTestBehavior(HitTestMode.None)

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
    .draggable(false)
    .bindContextMenu(this.bookActions(book), ResponseType.LongPress, this.bookMenuOptions())
    .onClick((): void => {
      if (!this.showBookActions && !this.resolvingTocId) this.handleBookTap(book);
    })
  }

  @Builder
  buildTypeBadge(small: boolean, isText: boolean) {
    Row() {
      Text(isText ? '电子书' : '有声书')
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
    .backgroundColor(isText ? '#CC4E7FA8' : '#CCFF8800')
    .borderRadius(AppRadius.Sm)
    .margin({ top: small ? 5 : 6, left: small ? 5 : 6 })
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width(72)
            .height(100)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (book.cover && (book.cover.startsWith('/data/') || book.cover.startsWith('file://'))) {
          Image('file://' + book.cover.replace(/^file:\/\//, ''))
            .width(72)
            .height(100)
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
            .draggable(false)
            .hitTestBehavior(HitTestMode.Transparent)
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
        this.buildTypeBadge(true, book.contentType === 'text')
      }
      .hitTestBehavior(HitTestMode.None)

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
        Text(this.getProgressText(book))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      if (this.isManaging) {
        this.buildSelectionMark(book)
      }
    }
    .width('100%')
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .backgroundColor(this.isManaging && this.selectedBookIds.has(book.id) ? AppColor.BrandSoft : Color.Transparent)
    .borderRadius(AppRadius.Sm)
    .draggable(false)
    .bindContextMenu(this.bookActions(book), ResponseType.LongPress, this.bookMenuOptions())
    .onClick((): void => {
      if (!this.showBookActions && !this.resolvingTocId) this.handleBookTap(book);
    })
  }

  @Builder
  buildAddTile() {
    Column({ space: AppSpace.Xs }) {
      Column() {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(32)
          .fontColor([$r('sys.color.font_tertiary')])
        Text('去书城寻好书')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Xs })
      }
      .width('100%')
      .aspectRatio(BOOKSHELF_COVER_RATIO)
      .borderRadius(AppRadius.Md)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .border({ width: 1, color: $r('sys.color.comp_divider'), style: BorderStyle.Dashed })

      Text(' ')
        .fontSize(AppFont.Body)
        .width('100%')
      Text(' ')
        .fontSize(AppFont.Caption)
        .width('100%')
    }
    .onClick(() => this.onGotoStore())
  }

  @Builder
  buildAddListItem() {
    Row({ space: AppSpace.Md }) {
      Column() {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(26)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width(72)
      .height(72)
      .borderRadius(AppRadius.Sm)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_secondary'))

      Text('去书城寻好书')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onGotoStore())
  }
}
