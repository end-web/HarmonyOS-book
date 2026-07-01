import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { emitter } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { AppColor, AppRadius, AppSpace, AppFont, HomeTheme } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem, EVT_FAVORITES_CHANGED } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { EVT_HISTORY_UPDATED } from '../service/AudioService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { BookDataSource } from '../utils/BookDataSource';

const BOOKSHELF_COVER_RATIO: number = 0.75;

interface BookUpdateInfo {
  title: string;
  oldCount: number;
  newCount: number;
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
    originSourceValue: ch.originSourceValue
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
    totalDuration: book.totalDuration,
    chapterCount: book.chapterCount,
    rating: book.rating,
    tags: book.tags ? book.tags.slice() : [],
    chapters: book.chapters ? book.chapters.map((ch: Chapter): Chapter => cloneChapter(ch)) : [],
    bookUrl: book.bookUrl,
    sourceUrl: book.sourceUrl,
    variables,
    skipIntro: book.skipIntro,
    skipOutro: book.skipOutro
  };
}

function chaptersChanged(oldChapters: Chapter[], newChapters: Chapter[]): boolean {
  if (oldChapters.length !== newChapters.length) return true;
  for (let i = 0; i < newChapters.length; i++) {
    const oldChapter = oldChapters[i];
    const newChapter = newChapters[i];
    if (!oldChapter || oldChapter.title !== newChapter.title ||
      oldChapter.originSourceValue !== newChapter.originSourceValue ||
      oldChapter.source.value !== newChapter.source.value) {
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
  @Local dragging: boolean = false;
  @Local trashHover: boolean = false;
  @Local draggingBookId: string = '';
  @Local isRefreshing: boolean = false;
  @Local resolvingTocId: string = '';
  @Local refreshProgress: string = '';
  @Local missingFavoriteCount: number = 0;
  @Param visible: boolean = false;
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onBookTap: (id: string) => void = () => {};
  @Event onGotoStore: () => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};

  private context: common.UIAbilityContext | null = null;
  private listScroller: Scroller = new Scroller();
  private bookDataSource: BookDataSource = new BookDataSource();
  private historyUpdatedHandler: (e: emitter.EventData) => void = (e) => this.onHistoryUpdated(e);
  /** 加入/移出书架后重新拉书清单(覆盖从阅读页/详情页等任意入口的收藏变化) */
  private favoritesChangedHandler: () => void = () => { this.loadFavorites(); };

  private getChapterCount(book: Book): number {
    return book.chapters && book.chapters.length > 0 ? book.chapters.length : (book.chapterCount || 0);
  }

  private syncFavoriteBook(updatedBook: Book): void {
    const books = this.favoriteBooks.map((book: Book): Book => book.id === updatedBook.id ? updatedBook : book);
    this.favoriteBooks = books;
    this.bookDataSource.setBooks(books);
  }

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadFavorites();
    emitter.on(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
    emitter.on(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
    this.onScrollerReady(this.listScroller);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_HISTORY_UPDATED, this.historyUpdatedHandler);
    emitter.off(EVT_FAVORITES_CHANGED, this.favoritesChangedHandler);
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
      const idx = DataService.resolveChapterIndex(b, h.chapterId, h.chapterTitle);
      if (idx >= 0) idxMap[b.id] = idx;
    }
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
  }

  async loadFavorites(): Promise<void> {
    if (!this.context) return;
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
    let missingCount = 0;
    for (const id of ids) {
      const book = byId.get(id);
      if (book) {
        books.push(book);
        continue;
      }
      const progress = await PreferenceService.getProgress(id);
      const chapterTitle = map[id]?.chapterTitle ?? progress?.chapterTitle ??
        (lastPlayed?.bookId === id ? (lastPlayed.chapterTitle ?? '') : '');
      const chapterId = map[id]?.chapterId ?? progress?.chapterId ??
        (lastPlayed?.bookId === id ? lastPlayed.chapterId : '');
      const chapterIndex = progress?.chapterIndex ?? this.parseLegacyChapterIndex(chapterId);
      const alias = this.findFavoriteAlias(id, chapterTitle, chapterIndex, allBooks);
      if (alias) {
        books.push(alias);
        continue;
      }
      books.push(this.createMissingFavoriteBook(id, chapterTitle));
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

    // 预算每本书的 chapterId → chapterIndex,避免后续 build / click 反复 findIndex
    const idxMap: Record<string, number> = {};
    for (const b of books) {
      const h = map[b.id];
      if (!h || !b.chapters || b.chapters.length === 0) continue;
      const idx = DataService.resolveChapterIndex(b, h.chapterId, h.chapterTitle);
      if (idx >= 0) idxMap[b.id] = idx;
    }
    this.favoriteBooks = books;
    this.bookDataSource.setBooks(books);
    this.historyMap = map;
    this.chapterIdxMap = idxMap;
    this.loading = false;
  }

  private createMissingFavoriteBook(id: string, chapterTitle: string): Book {
    const isTextBook = id.startsWith('search_text_') || id.startsWith('home_text_');
    const inferredTitle = this.legacyBookNameFromChapterTitle(chapterTitle);
    return {
      id,
      contentType: isTextBook ? 'text' : 'audio',
      title: inferredTitle || (isTextBook ? '电子书缓存缺失' : '有声书缓存缺失'),
      author: '收藏记录仍在',
      narrator: '',
      cover: '',
      category: isTextBook ? 'text' : 'audio',
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
   * 规则故意保守:旧标题里能取到书名,且缓存池里只有一本完整标题精确匹配的同类型书,才用于展示和打开。
   */
  private findFavoriteAlias(oldId: string, chapterTitle: string, chapterIndex: number, books: Book[]): Book | null {
    const oldIsText = oldId.startsWith('search_text_') || oldId.startsWith('home_text_');
    const oldIsAudio = oldId.startsWith('search_audio_') || oldId.startsWith('home_audio_');
    if (!oldIsAudio && !oldIsText) return null;

    if (oldIsText) {
      return this.findTextFavoriteAlias(oldId, chapterTitle, chapterIndex, books);
    }

    const name = this.normalizeRecoverName(this.legacyBookNameFromChapterTitle(chapterTitle));
    if (!name) return null;
    const candidates: Book[] = [];
    for (const book of books) {
      if (this.isText(book)) continue;
      if (this.normalizeRecoverName(book.title) !== name) continue;
      if (chapterIndex >= 0 && book.chapters && chapterIndex >= book.chapters.length) continue;
      candidates.push(book);
    }
    if (candidates.length !== 1) return null;
    return this.createFavoriteAliasBook(oldId, candidates[0]);
  }

  private findTextFavoriteAlias(oldId: string, chapterTitle: string, chapterIndex: number, books: Book[]): Book | null {
    if (!chapterTitle) return null;
    const candidates: Book[] = [];
    for (const book of books) {
      if (!this.isText(book) || !book.chapters || book.chapters.length === 0) continue;
      const idx = DataService.resolveChapterIndex(book, '', chapterTitle);
      if (idx < 0) continue;
      if (chapterIndex >= 0 && idx !== chapterIndex) continue;
      candidates.push(book);
    }
    if (candidates.length !== 1) return null;
    return this.createFavoriteAliasBook(oldId, candidates[0]);
  }

  /** 下拉刷新:从书源重新加载在线书籍的最新数据 */
  private async refreshOnlineBooks(): Promise<void> {
    if (!this.context) return;
    // 筛选出在线书源的书(非本地导入)
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
            originSourceValue: item.url
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
            updatedBooks.push({ title: nextBook.title, oldCount, newCount });
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
        return `《${u.title}》  ${u.oldCount} → ${u.newCount} 集（+${delta}）`;
      });
      const tail = failed > 0 ? `\n\n${failed} 本刷新失败` : '';
      prompt.showDialog({
        title: `${updatedBooks.length} 本书有更新`,
        message: lines.join('\n') + tail,
        buttons: [{ text: '知道了', color: '#333333' }]
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

  /** 电子书判定:文本源标"章"+进阅读器,有声书标"集"+进播放器 */
  private isText(book: Book): boolean {
    return book.contentType === 'text' || book.category === 'text';
  }

  /** 当前在读章节的短标签:优先"第N章/集/回",取不到用完整标题(由 Text 省略号兜底) */
  private currentChapterLabel(book: Book, idx: number): string {
    const ch = book.chapters && book.chapters[idx] ? book.chapters[idx] : undefined;
    if (!ch || !ch.title) return '';
    const m = ch.title.match(/^第\s*\d+\s*[章集回话]/);
    return m ? m[0] : ch.title;
  }

  /** 从章节标题里提取"第N章/集/回/话"短标签;取不到返回空(交由调用方退化处理) */
  private chapterLabelFromTitle(title: string): string {
    if (!title) return '';
    const m = title.match(/^第\s*\d+\s*[章集回话]/);
    return m ? m[0] : '';
  }

  private getProgressText(book: Book): string {
    if (this.isMissingCachedBook(book)) {
      return '缓存缺失 · 重新搜索后加入';
    }
    const unit = this.isText(book) ? '章' : '集';
    const chapterCount = this.getChapterCount(book);
    const h = this.historyMap[book.id];
    if (h && chapterCount > 0) {
      const idx = this.chapterIdxMap[book.id];
      if (idx !== undefined && idx >= 0) {
        // 显示"当前章标题 · 总数",与阅读/播放页内章号一致;不用 idx+1(列表位置),
        // 因为含水章/公告章时列表位置≠作者章号(如列表第527位其实是"第512章"),会对不上
        const label = this.currentChapterLabel(book, idx);
        if (label) return `${label} · ${chapterCount}${unit}`;
        return `${idx + 1}${unit}/${chapterCount}${unit}`;
      }
      // 章节尚未加载(壳书,章节在 sidecar 懒加载)→ 用历史里的章节标题提取章号,避免退化成"共N集"
      const histLabel = h.chapterTitle ? this.chapterLabelFromTitle(h.chapterTitle) : '';
      if (histLabel) return `${histLabel} · ${chapterCount}${unit}`;
      return `共${chapterCount}${unit}`;
    }
    if (chapterCount > 0) {
      return `共${chapterCount}${unit}`;
    }
    return book.author || '';
  }

  private handleBookTap(book: Book): void {
    if (this.isMissingCachedBook(book)) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '这本书的缓存快照缺失，请重新搜索后加入书架' });
      } catch (_e) { /* ignore */ }
      return;
    }
    const onPop = (): void => { this.loadFavorites(); };
    SearchCache.put(book);
    const text = this.isText(book);
    // ★ 当前正在播这本书:不重新解析 URL,不带 chapter 参数,直接进 player 复用 live state(电子书不走此路)
    if (!text && PlaybackStore.getInstance().isCurrentBook(book.id)) {
      this.navStack.pushPathByName('player', book.id, onPop);
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
    this.navStack.pushPathByName(text ? 'reader' : 'player', params, onPop);
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
          this.navStack.pushPathByName(this.isText(book) ? 'reader' : 'player', localParams, onPop);
          return;
        }
        // 本地目录命中但定位不到章节(可能已下架/重排)→ 落到下面联网重拉刷新
      }
      // 2) 本地没有 → 联网拉取(此时才提示"加载章节")
      try {
        this.getUIContext().getPromptAction().showToast({ message: '加载章节中...' });
      } catch (_e) { /* ignore */ }
      const sources = await SourceDataService.getSources();
      const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
      if (!source) {
        this.getUIContext().getPromptAction().showToast({ message: '书源已删除,请到详情页重新选择' });
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
        originSourceValue: item.url
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
      this.navStack.pushPathByName(this.isText(book) ? 'reader' : 'player', params, onPop);
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '章节加载失败' });
      } catch (_e2) { /* ignore */ }
      this.navStack.pushPathByName('detail', book.id, onPop);
    } finally {
      this.resolvingTocId = '';
    }
  }

  private confirmDelete(book: Book): void {
    if (this.isMissingCachedBook(book)) {
      this.confirmRemoveMissingFavorite(book);
      return;
    }
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

  private confirmRemoveMissingFavorite(book: Book): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '移除失效收藏',
      message: `确认从书架移除"${book.title}"？收藏记录还在，但本地缓存快照缺失。`,
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

  private async doRemove(bookId: string, deleteFiles: boolean): Promise<void> {
    if (!this.context) return;
    if (deleteFiles) {
      const audioDir = this.context.filesDir + '/audio/' + bookId;
      try { await fileIo.rmdir(audioDir); } catch (_e) { /* not exists */ }
      await DataService.removeImportedBook(bookId);
    }
    await PreferenceService.removeFavorite(bookId);
    if (!bookId.startsWith('import_')) {
      await DataService.removeCachedBook(bookId);
    }
    await this.loadFavorites();
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

      // 内容层：标题固定在上方，Refresh 只负责标题下方的书籍区域
      Column() {
        Column() {
          Row() {
            Text('书架')
              .fontSize(AppFont.TitleL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Md,
          bottom: AppSpace.Sm
        })

        Refresh({ refreshing: $$this.isRefreshing }) {
          Grid(this.listScroller) {
            LazyForEach(this.bookDataSource, (book: Book) => {
              GridItem() {
                this.buildBookTile(book)
              }
              // key 带上"总章数 + 当前章索引":LazyForEach 对相同 key 的项会复用旧节点、
              // 不重跑 buildBookTile。刷新后章数 742→758 但 book.id 不变 → 贴片卡在旧值。
              // 把会变的展示量编进 key,值一变 key 变 → 强制重建贴片。
            }, (book: Book) => `${book.id}:${this.getChapterCount(book)}:${this.chapterIdxMap[book.id] ?? -1}`)
            GridItem() {
              this.buildAddTile()
            }
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(AppSpace.Sm)
          .rowsGap(AppSpace.Md)
          .cachedCount(6)
          .width('100%')
          .height('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: AppSpace.Sm,
            bottom: WindowUtils.getFloatingTabBottomVp()
          })
          .scrollBar(BarState.Off)
          .backgroundColor(Color.Transparent)
        }
        .onRefreshing(() => {
          this.refreshOnlineBooks().finally(() => { this.isRefreshing = false; });
        })
        .refreshOffset(64)
        .pullToRefresh(true)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

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
    .onDragEnter(() => {
      this.trashHover = true;
      // 进入删除区:轻震一下,让用户知道"放手就会删"
      try {
        vibrator.startVibration(
          { type: 'time', duration: 30 },
          { id: 0, usage: 'touch' }
        ).catch((_e: object) => { /* 无震动器或权限被关 */ });
      } catch (_e) { /* 同步异常忽略 */ }
    })
    .onDragLeave(() => { this.trashHover = false; })
    .onDrop(() => {
      const id = this.draggingBookId;
      this.trashHover = false;
      this.dragging = false;
      this.draggingBookId = '';
      if (id) {
        // 松手震一下,作为"删除即将触发"的确认
        try {
          vibrator.startVibration(
            { type: 'time', duration: 60 },
            { id: 0, usage: 'touch' }
          ).catch((_e: object) => { /* 无震动器或权限被关 */ });
        } catch (_e) { /* 同步异常忽略 */ }
        const book = this.favoriteBooks.find(b => b.id === id);
        if (book) this.confirmDelete(book);
      }
    })
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
            .width('100%')
            .aspectRatio(BOOKSHELF_COVER_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        }
        this.buildTypeBadge(false, this.isText(book))
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
  buildTypeBadge(small: boolean, isTextBook: boolean) {
    Row({ space: small ? 2 : 3 }) {
      SymbolGlyph(isTextBook ? $r('sys.symbol.book') : $r('sys.symbol.speaker_wave_2_fill'))
        .fontSize(small ? 10 : 12)
        .fontColor([Color.White])
      Text(isTextBook ? '电子书' : '有声书')
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
    .backgroundColor(isTextBook ? '#CC3478F6' : '#CCFF8800')
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
        this.buildTypeBadge(true, this.isText(book))
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
        Text(this.getProgressText(book))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
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
}
