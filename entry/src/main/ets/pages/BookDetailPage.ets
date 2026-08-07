import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion, AppMaterial } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { AudioService } from '../service/AudioService';
import { DownloadService, DownloadUpdatePayload, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadStore, DownloadBookRecord, DownloadChapterRecord } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ColorPickerUtils, RgbColor } from '../utils/ColorPickerUtils';
import { BuiltInSourceRegistry } from '../service/builtin/BuiltInSourceRegistry';
import { ChapterListItem, ChapterBadge, mapChapterBadge } from '../components/ChapterListItem';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';

@ComponentV2
export struct BookDetailPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Local book: Book | null = null;
  @Local isFavorite: boolean = false;
  @Local loadingToc: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local isStartingPlay: boolean = false;
  @Local lastHistory: PlayHistoryItem | null = null;
  @Local activeTab: number = 1;
  @Local bgColor: string = '#3A3A3A';
  @Local bgColorDark: string = '#1A1A1A';
  @Local hasThemeColor: boolean = false;
  @Local debugInfo: string = '';
  /** 节目搜索关键词。 */
  @Local chapterQuery: string = '';
  @Local downloadTick: number = 0;
  @Local chapterDownloadTick: number = 0;
  /** 章节列表滚动位置 vs 当前章节的偏离(vp);用来决定是否显示"回到当前章节"浮动按钮 */
  @Local listOffsetFromCurrent: number = 0;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  private viewportUpdateTimerId: number = -1;
  private chapterListScroller: Scroller = new Scroller();
  /** @ReusableV2 章节列表：Repeat 入参。过滤后的展示数组；下载/播放状态变化时浅拷贝重建引用以触发重渲染。 */
  @Local displayedChapters: Chapter[] = [];
  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId !== this.bookId) return;
    this.downloadTick = this.downloadTick + 1;
    if (!data.progressOnly) {
      this.chapterDownloadTick = this.chapterDownloadTick + 1;
      this.refreshDisplayedChapters(this.displayedChapters);
    }
  };

  aboutToAppear(): void {
    // 命中 SearchCache 时同步可拿到 book,首屏立刻有内容;
    // 收藏状态 / TOC 拉取 / 取色等重活推迟到转场动画结束后,避免抢主线程
    this.primeBookFromCache();
    this.downloadTick = this.downloadTick + 1;
    this.chapterDownloadTick = this.chapterDownloadTick + 1;
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    WindowUtils.setStatusBarLight(true);
    setTimeout(() => { this.loadBook(); }, AppMotion.Page);
  }

  /** 同步从 SearchCache 取 book,让首帧有内容,后续重活推迟 */
  private primeBookFromCache(): void {
    const cached = SearchCache.get(this.bookId);
    if (cached) {
      this.book = cached;
AudioService.getInstance().prewarmBookSource(cached);
      this.refreshDisplayedChapters(cached.chapters);
      const cachedRgb = ColorPickerUtils.getCached(cached.cover);
      if (cachedRgb) {
        this.applyCoverColor(cachedRgb);
      }
    }
  }

  aboutToDisappear(): void {
    this.cancelViewportUpdateTimer();
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    WindowUtils.setStatusBarLight(false);
  }

  private cancelViewportUpdateTimer(): void {
    if (this.viewportUpdateTimerId !== -1) {
      clearTimeout(this.viewportUpdateTimerId);
      this.viewportUpdateTimerId = -1;
    }
  }

  private handleViewportSizeChange(newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    const width: number = newValue.width;
    const height: number = newValue.height;
    if (Math.abs(width - this.viewportWidth) < 1 && Math.abs(height - this.viewportHeight) < 1) return;
    this.cancelViewportUpdateTimer();
    this.viewportUpdateTimerId = setTimeout(() => {
      this.viewportUpdateTimerId = -1;
      this.viewportWidth = width;
      this.viewportHeight = height;
    }, 0);
  }

  private isCompactLayout(): boolean {
    return AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight);
  }

  private horizontalPadding(): number {
    return AdaptiveLayout.horizontalPadding(this.viewportWidth, this.viewportHeight);
  }

  private detailHeroHeight(): number {
    return AdaptiveLayout.detailHeroHeight(this.viewportWidth, this.viewportHeight);
  }

  private detailCoverWidth(): number {
    return AdaptiveLayout.detailCoverWidth(this.viewportWidth, this.viewportHeight);
  }

  private detailCoverHeight(): number {
    return AdaptiveLayout.detailCoverHeight(this.viewportWidth, this.viewportHeight);
  }

  private async loadBook(): Promise<void> {
    const b = await this.findBookById(this.bookId);
    if (b) {
      // 独立 KV 为权威:贴回跳过头尾,详情页起播也带上正确 skip(否则会用无 skip 对象喂 AudioService)
      await PreferenceService.applySkipConfig(b);
      // 先快速渲染基础信息
      this.book = b;
      AudioService.getInstance().prewarmBookSource(b);
      this.refreshDisplayedChapters(b.chapters);
      DownloadService.getInstance().hydrateBookDurations(b.id).catch((_e: Error): void => {});
      this.isFavorite = await PreferenceService.isFavorite(b.id);
      // 加载播放历史，用于"继续播放"入口
      this.loadHistory(b.id);
      // 先同步检查封面色缓存，命中则直接用，避免异步提取期间的默认灰闪烁
      const cached = ColorPickerUtils.getCached(b.cover);
      if (cached) {
        this.applyCoverColor(cached);
      }
      // 取色异步执行,不阻塞首屏
      this.extractCoverColor(b.cover);
      // 章节懒加载
      if ((b.chapters.length === 0 || (b.chapters.length === 1 && b.chapterCount > 1))
        && b.bookUrl && b.sourceUrl) {
        this.loadTocFromSource(b);
      } else {
        this.scrollToCurrentChapter();
      }
    }
  }

  /** 从 Preferences 加载本书的播放历史。 */
  private async loadHistory(bookId: string): Promise<void> {
    const history = await PreferenceService.getHistory();
    const item = history.find((h) => h.bookId === bookId);
    if (item) {
      this.lastHistory = item;
      // 历史就绪后再定位一次(loadBook 首次滚动时 lastHistory 可能尚未加载)
      this.scrollToCurrentChapter();
    }
  }

  /** 一次性应用封面色，避免多次状态更新触发多次重绘 */
  private applyCoverColor(rgb: RgbColor): void {
    // 压亮度:白色系封面的主色直接铺背景会让白字不可读
    const safe = ColorPickerUtils.normalizeAmbient(rgb);
    const dark = ColorPickerUtils.darken(safe, 0.3);
    // 颜色变化包进 animateTo:背景主色随封面就绪/切换平滑过渡,而不是硬跳
    this.getUIContext().animateTo({ duration: 500, curve: Curve.Linear }, () => {
      this.bgColor = ColorPickerUtils.toHex(safe);
      this.bgColorDark = ColorPickerUtils.toHex(dark);
      this.hasThemeColor = true;
    });
  }

  private async findBookById(id: string): Promise<Book | null> {
    const cached = SearchCache.get(id);
    if (cached) return cached;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const imported = await DataService.getBookById(ctx, id);
    if (imported) return imported;
    const record = await DownloadStore.getBook(id);
    if (record) return DownloadService.getInstance().recordToBook(record);
    return null;
  }

  private async loadTocFromSource(book: Book): Promise<void> {
    this.loadingToc = true;
    this.debugInfo = `bookUrl=${book.bookUrl}\nsourceUrl=${book.sourceUrl}`;
    try {
      const sources = await SourceDataService.getSources();
      const source = sources.find(s => s.bookSourceUrl === book.sourceUrl);
      this.debugInfo += `\nsource=${source ? source.bookSourceName : 'NOT FOUND'}`;
      if (source && book.bookUrl) {
        const isServerAudio = BuiltInSourceRegistry.getByUrl(source.bookSourceUrl)?.id === 'jianhu_server';
        // 先获取书籍详情，提取正确的 tocUrl
        let tocUrl = book.bookUrl;
        const bookInfo = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
        if (!bookInfo && isServerAudio) {
          SearchCache.remove(book.id);
        }
        // 合并 search 时的 @put 变量 + getBookInfo 时的 @put 变量
        const mergedVars: Record<string, string> = {};
        if (book.variables) {
          for (const k of Object.keys(book.variables)) {
            mergedVars[k] = book.variables[k];
          }
        }
        if (bookInfo?.variables) {
          for (const k of Object.keys(bookInfo.variables)) {
            mergedVars[k] = bookInfo.variables[k];
          }
        }
        if (bookInfo) {
          if (bookInfo.tocUrl) tocUrl = bookInfo.tocUrl;
          if (bookInfo.intro && !book.intro) book.intro = bookInfo.intro;
          // 详情返回的分类/完结作为更权威来源补全（搜索快照可能因硬编码丢失）
          if (bookInfo.kind && bookInfo.kind.trim().length > 0 && !book.category.trim()) book.category = bookInfo.kind;
          if (bookInfo.completed !== undefined) book.completed = bookInfo.completed;
        }
        this.debugInfo += `\ntocUrl=${tocUrl}`;

        const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars, book.title);
        if (tocItems.length === 0 && isServerAudio) {
          SearchCache.remove(book.id);
        }
        this.debugInfo += `\ntocItems=${tocItems.length}`;
        if (tocItems.length > 0) {
          this.debugInfo += `\nfirst=${tocItems[0].name}`;
        }
        // 去重:按 URL 去重(保留首次出现的章节,丢弃重复 URL)
        const seenUrls = new Set<string>();
        const uniqueTocItems = tocItems.filter(item => {
          if (seenUrls.has(item.url)) {
            return false;
          }
          seenUrls.add(item.url);
          return true;
        });
        this.debugInfo += `\nunique=${uniqueTocItems.length}`;
        book.chapters = uniqueTocItems.map((item: TocItem, idx: number): Chapter => ({
          id: `${book.id}-c${idx}`,
          index: idx + 1,
          title: item.name,
          duration: item.duration || 0,
          source: { type: 'url', value: item.url },
          originSourceValue: item.url
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
          sourceUrl: book.sourceUrl,
          contentType: book.contentType,
          variables: Object.keys(mergedVars).length > 0 ? mergedVars : book.variables,
          // 保留 skip:否则 upsertCachedBook(cloned) 会把缓存索引里的旧 skip 清掉
          skipIntro: book.skipIntro,
          skipOutro: book.skipOutro,
          completed: book.completed
        };
        this.book = cloned;
        this.refreshDisplayedChapters(cloned.chapters);
        SearchCache.put(cloned);
        // 已收藏的在线书：同步把最新 toc 写回 cachedBooks,保证书架直接进播放器有完整章节
        if (this.isFavorite) {
          await DataService.upsertCachedBook(cloned);
        }
      }
    } catch (e) {
      this.debugInfo += `\nERROR: ${e}`;
    }
    this.loadingToc = false;
    this.scrollToCurrentChapter();
  }

  private async extractCoverColor(cover: string): Promise<void> {
    if (!cover) return;
    let rgb: RgbColor | null = null;
    try {
      if (cover.startsWith('http')) {
        rgb = await ColorPickerUtils.pickFromUrl(cover);
      } else if (cover.startsWith('/')) {
        rgb = await ColorPickerUtils.pickFromFile(cover);
      } else {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        rgb = await ColorPickerUtils.pickFromRawfile(ctx, cover);
      }
    } catch (_e) { /* ignore */ }
    if (!rgb) return;
    // 一次性更新，避免 3 次独立赋值触发 3 次重绘
    this.applyCoverColor(rgb);
  }

  /**
   * 当前章节在完整章节列表中的索引。
   * 1) 正在播放本书:取播放章;
   * 2) 否则用最近播放历史定位节目。
   */
  private currentChapterIndex(): number {
    if (!this.book) return -1;
    if (this.playerState.currentBook && this.playerState.currentChapter
        && this.playerState.currentBook.id === this.bookId) {
      return DataService.resolveChapterIndex(
        this.book,
        this.playerState.currentChapter.id,
        this.playerState.currentChapter.title
      );
    }
    if (this.lastHistory) {
      return DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    }
    return -1;
  }

  private scrollToCurrentChapter(): void {
    this.scrollChapterListToIndex(this.currentChapterIndex());
  }

  /** "回到当前章节"按钮:居中滚到当前章节 */
  private jumpToCurrentChapter(): void {
    this.scrollToCurrentChapter();
    this.listOffsetFromCurrent = 0;
  }

  /** 是否需要显示"回到当前章节"浮动按钮:列表滚动距离当前章节超过 200vp(搜索过滤时不显示,同播放页) */
  private shouldShowJumpButton(): boolean {
    return this.chapterQuery.trim().length === 0
      && Math.abs(this.listOffsetFromCurrent) > 200;
  }

  /**
   * 可靠定位章节列表到指定 index。
   * 两段式延迟:首次等「节目」tab/列表挂载并完成首屏布局(规避 setTimeout(0) 的挂载竞态),
   * 把目标项拉进 LazyForEach 渲染窗口;二次等目标项真实行高确定后再精确居中,
   * 修正长列表按平均行高估算导致的 ScrollAlign.CENTER 偏差(原先单次定位时灵时不灵)。
   */
  private scrollChapterListToIndex(idx: number): void {
    if (idx <= 0) return;
    setTimeout(() => {
      try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      setTimeout(() => {
        try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      }, 150);
    }, 50);
  }

  /** 过滤后的章节展示数组（Repeat 入参）。返回新引用以触发 @ReusableV2 行重渲染。 */
  private refreshDisplayedChapters(list: Chapter[]): void {
    // 浅拷贝一份，保证 Repeat 通过数组引用变化重算每行（badge/进度/播放态）
    this.displayedChapters = list.slice();
  }

  /** 按关键词过滤章节。空关键词回到完整列表，再推送展示数组给 Repeat。 */
  private applyChapterFilter(): void {
    if (!this.book) return;
    const q = this.chapterQuery.trim();
    if (!q) {
      this.refreshDisplayedChapters(this.book.chapters);
      return;
    }
    const filtered = this.book.chapters.filter((c) => c.title.indexOf(q) >= 0);
    this.refreshDisplayedChapters(filtered);
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    if (this.bookId.startsWith('import_') && this.isFavorite) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '导入的书需在书架长按删除' });
      } catch (_e) { /* ignore */ }
      return;
    }
    // 收藏 id 还在、但本地快照已彻底丢失(书架占位卡场景):这一下应"补回快照、保留收藏",
    // 而不是把仅存的收藏 id 也 toggle 掉 —— 否则用户重搜后点心形,体感是"重新加入书架没用"。
    if (this.isFavorite && !this.bookId.startsWith('import_')) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const snap = await DataService.getBookById(ctx, this.book.id);
      if (!snap) {
        const needToc = (!this.book.chapters || this.book.chapters.length === 0)
          && !!this.book.bookUrl && !!this.book.sourceUrl;
        if (needToc) {
          await this.loadTocFromSource(this.book);
        }
        await DataService.upsertCachedBook(this.book);
        this.isFavorite = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '已重新加入书架' });
        } catch (_e) { /* ignore */ }
        return;
      }
    }
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      // 在线书:章节还没拉到就先把 toc 拉齐再写缓存,避免书架点击时拿到空 chapters
      const needToc = (!this.book.chapters || this.book.chapters.length === 0)
        && !!this.book.bookUrl && !!this.book.sourceUrl;
      if (needToc) {
        await this.loadTocFromSource(this.book);
      }
      await DataService.upsertCachedBook(this.book);
    } else if (!this.bookId.startsWith('import_')) {
      // 取消收藏后,如果没有播放历史,也清掉缓存避免堆积
      const history = await PreferenceService.getHistory();
      const stillNeeded = history.some((h) => h.bookId === this.book!.id);
      if (!stillNeeded) {
        await DataService.removeCachedBook(this.book.id);
      }
    }
  }

  private downloadRecord(): DownloadBookRecord | null {
    if (this.downloadTick < 0) return null;
    return DownloadService.getInstance().getBookStatus(this.bookId);
  }

  private chapterDownloadRecord(chapter: Chapter): DownloadChapterRecord | null {
    if (this.chapterDownloadTick < 0) return null;
    return DownloadService.getInstance().getChapterStatus(this.bookId, chapter);
  }

  private chapterListKey(chapter: Chapter): string {
    return DownloadPolicy.stablePageUrl(chapter) || chapter.id;
  }

  private chapterDuration(chapter: Chapter): number {
    if (chapter.duration > 0) return chapter.duration;
    return this.chapterDownloadRecord(chapter)?.durationSec ?? 0;
  }

  private isChapterDownloaded(chapter: Chapter): boolean {
    return this.chapterDownloadRecord(chapter)?.status === 'completed';
  }

  private isChapterDownloading(chapter: Chapter): boolean {
    const status = this.chapterDownloadRecord(chapter)?.status;
    return status === 'pending' || status === 'resolving' || status === 'downloading';
  }

  private isChapterDownloadFailed(chapter: Chapter): boolean {
    return this.chapterDownloadRecord(chapter)?.status === 'failed';
  }

  private downloadProgress(): number {
    if (this.downloadTick < 0) return 0;
    return DownloadService.getInstance().getBookProgress(this.bookId).progressPercent;
  }

  private downloadStatusText(): string {
    const record = this.downloadRecord();
    if (!record || record.chapters.length === 0) return '未下载';
    const total = record.chapters.filter((item) => item.status !== 'deleted').length;
    if (record.status === 'completed') return `已下载 ${record.downloadedCount}/${total}`;
    if (record.status === 'downloading' || record.status === 'queued') {
      return `下载中 ${record.downloadedCount}/${total} · ${Math.round(this.downloadProgress())}%`
        + `${record.failedCount > 0 ? ` · 失败 ${record.failedCount}` : ''}`;
    }
    if (record.status === 'paused') return `已暂停 ${record.downloadedCount}/${total}`;
    if (record.failedCount > 0) {
      const failed = record.chapters.find((item) => item.status === 'failed');
      const reason = failed ? DownloadPolicy.failureText(failed.failureCode
        ?? DownloadPolicy.classifyFailure(failed.failureReason)) : '';
      return `已下载 ${record.downloadedCount}/${total} · 失败 ${record.failedCount}${reason ? ` · ${reason}` : ''}`;
    }
    return `已下载 ${record.downloadedCount}/${total}`;
  }

  private currentDownloadStartIndex(): number {
    const idx = this.currentChapterIndex();
    return idx >= 0 ? idx : 0;
  }

  private showToast(message: string | Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_e) {
      // ignore
    }
  }

  private async downloadWholeBook(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance().downloadBook(this.book);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_all') : '没有可下载的新章节');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async downloadNextTwenty(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance()
        .downloadNextChapters(this.book, this.currentDownloadStartIndex(), 20);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_next_twenty') : '后续章节已下载或不可下载');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async downloadIncremental(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance().downloadIncremental(this.book);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_incremental') : '没有发现可下载的新章节');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async pauseDownload(): Promise<void> {
    try {
      await DownloadService.getInstance().pauseBook(this.bookId);
      this.downloadTick = this.downloadTick + 1;
      this.showToast($r('app.string.download_paused'));
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async resumeDownload(): Promise<void> {
    try {
      await DownloadService.getInstance().resumeBook(this.bookId);
      this.downloadTick = this.downloadTick + 1;
      this.showToast($r('app.string.download_resumed'));
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private confirmDeleteBookDownload(): void {
    if (!this.book) return;
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: $r('app.string.download_delete_title'),
      message: $r('app.string.download_delete_message'),
      buttons: [
        { text: $r('app.string.common_cancel'), color: '#8F8F8F' },
        { text: $r('app.string.download_delete_confirm'), color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        DownloadService.getInstance().deleteBookDownload(this.bookId).then(() => {
          this.downloadTick = this.downloadTick + 1;
          this.showToast($r('app.string.download_deleted'));
        }).catch(() => this.showToast($r('app.string.download_operation_failed')));
      }
    }).catch(() => this.showToast($r('app.string.download_operation_failed')));
  }

  private openPrimaryAction(chapter?: Chapter): void {
    this.startPlay(chapter);
  }

  private async startPlay(chapter?: Chapter): Promise<void> {
    if (!this.book || this.isStartingPlay) return;
    this.isStartingPlay = true;

    // 没有指定章节时，优先从历史恢复，否则用第一章
    let target: Chapter | undefined = chapter;
    let resumeProgressMs = 0;
    if (!target && this.lastHistory) {
      // 标题优先定位:连载更新/TOC 重排后旧 chapterId 会指向错误章节
      const hi = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
      target = hi >= 0 ? this.book.chapters[hi] : undefined;
      resumeProgressMs = this.lastHistory.progressMs;
    }
    if (!target) {
      target = this.book.chapters[0];
    }
    if (!target) {
      this.isStartingPlay = false;
      return;
    }
    // ★ 用户当前正在播这本书且同章节:用 live state.progressMs(更新)替代 lastHistory.progressMs(可能旧 5s),
    //   避免从详情页继续播放反而回退进度
    if (PlaybackStore.getInstance().isCurrentChapter(this.book.id, target.id)) {
      resumeProgressMs = this.playerState.progressMs;
    }

    SearchCache.put(this.book);
    // ★ 当前在播的就是同书「且就是当前这一章」:直接 push player 不带 chapter 参数,
    //   PlayerPage 复用 live state,避免 tryResumePlay 触发 playChapterAndSeek 重置。
    //   若用户点的是别的章(target 非当前章),则走下面带 chapterId 的分支,播放选中的章。
    if (PlaybackStore.getInstance().isCurrentBook(this.book.id)
      && PlaybackStore.getInstance().isCurrentChapter(this.book.id, target.id)) {
      // 详情页入口,清理栈避免重复 player
      this.cleanStackBeforePushPlayer();
      animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', this.bookId, false);
      });
      this.isStartingPlay = false;
      return;
    }
    const playerParams: Record<string, Object> = {
      'bookId': this.bookId as Object,
      'chapterId': target.id as Object,
      'progressMs': resumeProgressMs as Object
    };
    // 详情页入口,清理栈避免重复 player
    this.cleanStackBeforePushPlayer();
    animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', playerParams, false);
    });
    this.isStartingPlay = false;
  }

  /** 从详情页进播放页前,清理栈避免重复 player。如果栈里已有 player,先 pop 到 home,再 push player */
  private cleanStackBeforePushPlayer(): void {
    const names = this.navStack.getAllPathName();
    if (!names || names.length === 0) return;
    // 栈结构:home, player?, detail, ...
    // 如果 names[1] === 'player',说明从 player 进的 detail,需要 pop 到 home
    if (names.length >= 2 && names[1] === 'player') {
      this.navStack.popToName('home');
    }
  }

  private formatDuration(seconds: number): string {
    if (seconds <= 0) return '';
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private formatPlayCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(0) + '万';
    }
    return count.toString();
  }

  private getPlayProgress(ch: Chapter): number {
    if (!this.playerState.currentBook || !this.playerState.currentChapter) return 0;
    if (this.isCurrentPlaybackChapter(ch)) {
      if (this.playerState.durationMs > 0) {
        return Math.round(this.playerState.progressMs / this.playerState.durationMs * 100);
      }
    }
    return 0;
  }

  private isPlayingChapter(ch: Chapter): boolean {
    return this.isCurrentPlaybackChapter(ch);
  }

  private isCurrentPlaybackChapter(ch: Chapter): boolean {
    if (!this.book || !this.playerState.currentBook || !this.playerState.currentChapter) return false;
    if (this.playerState.currentBook.id !== this.bookId) return false;
    if (this.playerState.currentChapter.id === ch.id) return true;
    const idx = DataService.resolveChapterIndex(
      this.book,
      this.playerState.currentChapter.id,
      this.playerState.currentChapter.title
    );
    return idx >= 0 && this.book.chapters[idx].id === ch.id;
  }

  build() {
    Column() {
      if (this.book) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 沉浸式背景:封面主色→深色纵向渐变,与下方正文底色保持明确分界(用户定调:不做消散融合)
          Column()
            .width('100%')
            .height(this.detailHeroHeight())
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
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
    })
  }

  @Builder
  buildTopBar() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor(['#FFFFFF'])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .systemMaterial(AppMaterial.FloatingControl)
      .onClick(() => this.navStack.pop())
      Blank()
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(22)
          .fontColor([this.isFavorite ? '#FF6B8A' : '#FFFFFF'])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .systemMaterial(AppMaterial.FloatingControl)
      .onClick(() => this.toggleFavorite())
    }
    .width('100%')
    .height(48)
    .padding({ left: this.horizontalPadding(), right: this.horizontalPadding() })
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Lg }) {
      // 封面（共享元素，飞向 PlayerPage / 飞回 BookCard）
      Stack() {
        if (this.book!.cover && this.book!.cover.startsWith('http')) {
          Image(this.book!.cover)
            .width(this.detailCoverWidth())
            .height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            // 与列表统一解码尺寸,复用同一份解码缓存(100x130vp 显示足够清晰)
            .sourceSize({ width: 300, height: 400 })
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else if (this.book!.cover && (this.book!.cover.startsWith('/') || this.book!.cover.startsWith('file://'))) {
          // 判断与 BookCard.isLocalFile 对齐:file:// 前缀不能掉进 $rawfile 分支
          Image('file://' + this.book!.cover.replace(/^file:\/\//, ''))
            .width(this.detailCoverWidth())
            .height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 300, height: 400 })
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else if (this.book!.cover) {
          Image($rawfile(this.book!.cover))
            .width(this.detailCoverWidth())
            .height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else {
          // 无封面:用 app 图标占位(替代旧的书形占位)
          Image($r('app.media.app_icon_legacy'))
            .width(this.detailCoverWidth()).height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        }
      }

      // 书名信息
      Column({ space: AppSpace.Xs }) {
        Text(this.book!.title)
          .fontSize(AppFont.TitleL)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.book!.author) {
          Text(this.book!.author)
            .fontSize(AppFont.Body)
            .fontColor('#FFFFFFCC')
            .maxLines(1)
        }
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
    .padding({
      left: this.horizontalPadding(),
      right: this.horizontalPadding(),
      top: this.isCompactLayout() ? AppSpace.Xs : AppSpace.Md
    })
  }

  @Builder
  buildStats() {
    Row() {
      // 分类
      Column({ space: 2 }) {
        Text(this.book!.category.trim().length > 0 ? this.book!.category : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('分类')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)

      // 状态
      Column({ space: 2 }) {
        Text(this.book!.completed === undefined ? '--' : (this.book!.completed ? '已完结' : '连载中'))
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text('状态')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)

      // 章节数
      Column({ space: 2 }) {
        Text(this.book!.chapterCount > 0 ? this.book!.chapterCount.toString() + ' 集' : '--')
          .fontSize(AppFont.Title)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
        Text('总集数')
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF99')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: this.isCompactLayout() ? AppSpace.Lg : AppSpace.Xl,
      right: this.isCompactLayout() ? AppSpace.Lg : AppSpace.Xl,
      top: this.isCompactLayout() ? AppSpace.Sm : AppSpace.Lg,
      bottom: this.isCompactLayout() ? AppSpace.Sm : AppSpace.Lg
    })
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

      Text('节目')
        .fontSize(AppFont.BodyL)
        .fontColor(this.activeTab === 1 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
        .border(this.activeTab === 1
          ? { width: { bottom: 2 }, color: { bottom: AppColor.Brand } }
          : { width: { bottom: 2 }, color: { bottom: Color.Transparent } })
        .onClick(() => {
          this.activeTab = 1;
          // 进「节目」tab 复位搜索,避免带着旧过滤态定位章节
          if (this.chapterQuery.length > 0) {
            this.chapterQuery = '';
            this.applyChapterFilter();
          }
          this.scrollToCurrentChapter();
        })
    }
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: { bottom: AppColor.Divider } })
    .backgroundColor($r('sys.color.background_primary'))
  }

  /** 获取历史章节标题，供 Builder 使用 */
  private historyChapterTitle(): string {
    if (!this.lastHistory || !this.book) return '';
    const idx = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    return idx >= 0 ? this.book.chapters[idx].title : (this.lastHistory.chapterTitle ?? '');
  }

  /** 根据是否有历史记录返回按钮文案 */
  private resumeButtonText(): string {
    if (!this.lastHistory || !this.book) {
      return '开始播放';
    }
    const idx = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    if (idx >= 0) {
      const title = this.book.chapters[idx].title;
      return `继续播放 ${title}`;
    }
    return '继续播放';
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

        // 播放按钮
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18).fontColor(['#FFFFFF'])
          Text(this.resumeButtonText())
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
        .onClick(() => this.openPrimaryAction())

        this.buildDownloadPanel()
      }
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Lg, bottom: AppSpace.Xl })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildDownloadPanel() {
    Column({ space: AppSpace.Xs }) {
      Row() {
        Text($r('app.string.download_panel_title'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
        Blank()
        Text(this.downloadStatusText())
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.downloadRecord() && this.downloadRecord()!.chapters.length > 0) {
        Progress({ value: this.downloadProgress(), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(AppColor.Brand)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
      }

      Row({ space: AppSpace.Xs }) {
        this.buildDownloadChip($r('app.string.download_all'), $r('sys.symbol.arrow_down_circle'),
          () => this.downloadWholeBook(), false)
        this.buildDownloadChip($r('app.string.download_next_twenty'), $r('sys.symbol.cloud'),
          () => this.downloadNextTwenty(), false)
        this.buildDownloadChip($r('app.string.download_incremental'), $r('sys.symbol.arrow_clockwise'),
          () => this.downloadIncremental(), false)
      }
      .width('100%')

      if (DownloadService.getInstance().hasAnyDownload(this.bookId)) {
        Row({ space: AppSpace.Xs }) {
          if (this.downloadRecord()?.status === 'downloading' || this.downloadRecord()?.status === 'queued') {
            this.buildDownloadChip($r('app.string.download_pause'), $r('sys.symbol.pause_fill'),
              () => this.pauseDownload(), false)
          } else if (this.downloadRecord()?.status === 'paused') {
            this.buildDownloadChip($r('app.string.download_resume'), $r('sys.symbol.play_fill'),
              () => this.resumeDownload(), false)
          }
          this.buildDownloadChip($r('app.string.download_delete'), $r('sys.symbol.trash'),
            () => this.confirmDeleteBookDownload(), true)
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: AppSpace.Md })
  }

  @Builder
  buildDownloadChip(text: string | Resource, icon: Resource, onAction: () => void, danger: boolean) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([danger ? '#D03050' : AppColor.Brand])
      Text(text)
        .fontSize(AppFont.Caption)
        .fontColor(danger ? '#D03050' : $r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(AppRadius.Lg)
    .backgroundColor(danger ? '#14D03050' : $r('sys.color.comp_background_tertiary'))
    .onClick(() => onAction())
  }

  @Builder
  buildChapterContent() {
    Column() {
      // 章节头部
      Row() {
        Text(this.chapterQuery.trim().length > 0
          ? `匹配 ${this.displayedChapters.length} 集`
          : `共 ${this.book!.chapters.length} 集`)
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

      // 有节目时显示目录搜索。
      if (this.book!.chapters.length > 0) {
        Search({ value: this.chapterQuery, placeholder: '搜索节目' })
          .height(38)
          .margin({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Sm })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(AppRadius.Lg)
          .onChange((v: string) => {
            this.chapterQuery = v;
            this.applyChapterFilter();
          })
      }

      // 章节列表
      if (this.book!.chapters.length === 0 && !this.loadingToc) {
        Column() {
          Text('暂无章节信息')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
          if (this.debugInfo) {
            Text(this.debugInfo)
              .fontSize(10)
              .fontColor('#FF6B6B')
              .margin({ top: 8 })
              .padding(8)
              .backgroundColor('#1AFFFFFF')
              .borderRadius(4)
              .maxLines(10)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.chapterQuery.trim().length > 0 && this.displayedChapters.length === 0) {
        Column() {
          Text('无匹配章节')
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          List({ space: 0, scroller: this.chapterListScroller }) {
            Repeat<Chapter>(this.displayedChapters)
              .each((ri: RepeatItem<Chapter>) => {
                ListItem() {
                  // Repeat 与 @Builder 混用必须整体传 RepeatItem，只传 .item 会导致节点复用时渲染乱序
                  this.buildChapterItem(ri)
                }
              })
              .key((ch: Chapter) => this.chapterListKey(ch))
              .virtualScroll({ reusable: true })
          }
          .width('100%')
          .height('100%')
          .cachedCount(5)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .divider({ strokeWidth: 0.5, color: AppColor.Divider, startMargin: AppSpace.Lg, endMargin: AppSpace.Lg })
          .onScrollIndex((firstIndex: number, lastIndex: number) => {
            // 用首尾可见 index 与当前章节 index 计算偏离
            // 行高约 64vp(BodyL+Caption+上下 14 padding),用 (center - idx) * 64 估算
            const idx = this.currentChapterIndex();
            if (idx < 0) return;
            const center = (firstIndex + lastIndex) / 2;
            this.listOffsetFromCurrent = (center - idx) * 64;
          })

          // "回到当前章节"浮动按钮:列表滚远时显示(同播放页章节抽屉)
          if (this.shouldShowJumpButton()) {
            Row({ space: AppSpace.Xs }) {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text('回到当前章节')
                .fontSize(AppFont.Caption)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
            }
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(22)
            .backgroundColor(AppColor.Brand)
            .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
            .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
            .onClick(() => this.jumpToCurrentChapter())
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
              .animation({ curve: curves.springMotion(0.4, 0.9) }))
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .layoutWeight(1)
  }

  @Builder
  buildChapterItem(ri: RepeatItem<Chapter>) {
    ChapterListItem({
      title: ri.item.title,
      isPlaying: this.isPlayingChapter(ri.item),
      durationText: this.chapterDuration(ri.item) > 0 ? this.formatDuration(this.chapterDuration(ri.item)) : '',
      bytesText: this.isChapterDownloaded(ri.item) && (this.chapterDownloadRecord(ri.item)?.bytes ?? 0) > 0
        ? this.formatBytes(this.chapterDownloadRecord(ri.item)?.bytes ?? 0)
        : '',
      progressText: this.getPlayProgress(ri.item) > 0 ? `${this.getPlayProgress(ri.item)}%` : '',
      badge: mapChapterBadge(this.isChapterDownloaded(ri.item), this.isChapterDownloading(ri.item), this.isChapterDownloadFailed(ri.item)),
      onTap: () => this.openPrimaryAction(ri.item)
    })
  }

  @Builder
  buildBottomPlayer() {
    Row({ space: AppSpace.Md }) {
      // 播放按钮
      Row() {
        SymbolGlyph(this.playerState.isPlaying && this.playerState.currentBook?.id === this.bookId
          ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(20).fontColor(['#FFFFFF'])
      }
      .width(40).height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.Brand)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.playerState.currentBook?.id === this.bookId && this.playerState.currentChapter) {
          AudioService.getInstance().toggle();
        } else {
          this.openPrimaryAction();
        }
      })

      // 当前播放信息 / 默认提示
      Column({ space: 2 }) {
        if (this.playerState.currentBook?.id === this.bookId
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
          Text(this.resumeButtonText())
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          if (this.historyChapterTitle()) {
            Text(this.historyChapterTitle())
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else if (this.book!.chapters.length > 0) {
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
        .onClick(() => {
          this.activeTab = 1;
          this.scrollToCurrentChapter();
        })
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
