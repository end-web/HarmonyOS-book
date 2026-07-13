import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../model/Book';
import { BookInfo, TocItem } from '../model/BookSource';
import { AudioDownloadTransport } from './AudioDownloadTransport';
import { AudioRequestInfo, BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { DownloadFailureCode, DownloadPolicy } from './DownloadPolicy';
import { DownloadBookRecord, DownloadChapterRecord, DownloadStore } from './DownloadStore';
import { SourceDataService } from './SourceDataService';
import { DownloadNotificationService, DownloadNotificationSummary } from './DownloadNotificationService';
import { BackgroundTaskService } from './BackgroundTaskService';

const DOMAIN = 0x0001;
const TAG = 'DownloadService';
const MAX_RESOLVE_CONCURRENT = 2;
const MAX_FILE_CONCURRENT = 2;

export const EVT_DOWNLOAD_UPDATED = 'app.download.updated';

interface DownloadQueueItem {
  book: Book;
  chapter: Chapter;
  globalGeneration: number;
  bookGeneration: number;
  chapterGeneration: number;
  requestInfo?: AudioRequestInfo;
}

interface ActiveDownloadProgress {
  bookId: string;
  chapterId: string;
  chapterTitle: string;
  receivedBytes: number;
  totalBytes: number;
}

export interface DownloadProgressSnapshot {
  progressPercent: number;
  receivedBytes: number;
  expectedBytes: number;
  indeterminate: boolean;
  currentChapterTitle: string;
  totalCount: number;
}

export interface DownloadUpdatePayload {
  bookId: string;
  chapterId?: string;
  status: string;
  downloadedCount: number;
  failedCount: number;
  totalCount: number;
  progressPercent: number;
  receivedBytes: number;
  expectedBytes: number;
  indeterminate: boolean;
  currentChapterTitle: string;
  progressOnly: boolean;
}

export class DownloadService {
  private static instance: DownloadService | null = null;

  private ctx: common.Context | null = null;
  private resolveQueue: DownloadQueueItem[] = [];
  private fileQueue: DownloadQueueItem[] = [];
  private resolveRunningCount: number = 0;
  private fileRunningCount: number = 0;
  private pendingKeys: Map<string, string> = new Map();
  private pausedBooks: Set<string> = new Set();
  private deletedBooks: Set<string> = new Set();
  private deletedChapters: Set<string> = new Set();
  private activeTransports: Map<string, AudioDownloadTransport> = new Map();
  private globalGeneration: number = 0;
  private bookGenerations: Map<string, number> = new Map();
  private chapterGenerations: Map<string, number> = new Map();
  private activeProgress: Map<string, ActiveDownloadProgress> = new Map();
  private lastProgressEmitAt: Map<string, number> = new Map();
  private durationHydrationBooks: Set<string> = new Set();
  private notificationBookIds: Set<string> = new Set();
  private lastNotificationAt: number = 0;

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService();
    }
    return DownloadService.instance;
  }

  async init(ctx: common.Context): Promise<void> {
    this.ctx = ctx;
    DownloadNotificationService.setContext(ctx);
    await DownloadStore.init(ctx);
  }

  async restoreDownloads(): Promise<void> {
    await this.restoreInterruptedDownloads();
  }

  setContext(ctx: common.Context): void {
    this.ctx = ctx;
    DownloadStore.setContext(ctx);
    DownloadNotificationService.setContext(ctx);
  }

  async downloadBook(book: Book): Promise<number> {
    await DownloadNotificationService.requestPermission();
    return this.enqueueChapters(book, book.chapters);
  }

  async downloadNextChapters(book: Book, startIndex: number, count: number): Promise<number> {
    await DownloadNotificationService.requestPermission();
    const safeStart = Math.max(0, Math.min(startIndex, Math.max(0, book.chapters.length - 1)));
    const safeEnd = Math.min(book.chapters.length, safeStart + Math.max(1, count));
    return this.enqueueChapters(book, book.chapters.slice(safeStart, safeEnd));
  }

  async downloadIncremental(book: Book): Promise<number> {
    await DownloadNotificationService.requestPermission();
    const refreshed = await this.refreshBookToc(book);
    return this.enqueueChapters(refreshed, refreshed.chapters);
  }

  async downloadChapter(book: Book, chapter: Chapter): Promise<number> {
    await DownloadNotificationService.requestPermission();
    return this.enqueueChapters(book, [chapter]);
  }

  async pauseBook(bookId: string): Promise<void> {
    this.advanceBookGeneration(bookId);
    this.pausedBooks.add(bookId);
    this.cancelBookTransports(bookId);
    this.resolveQueue = this.resolveQueue.filter((item: DownloadQueueItem) => item.book.id !== bookId);
    this.fileQueue = this.fileQueue.filter((item: DownloadQueueItem) => item.book.id !== bookId);
    this.removePendingBookKeys(bookId);
    this.clearBookProgress(bookId);
    const record = await DownloadStore.getBook(bookId);
    if (record) {
      for (const chapter of record.chapters) {
        if (chapter.status === 'resolving' || chapter.status === 'downloading') chapter.status = 'pending';
      }
      record.status = 'paused';
      await DownloadStore.saveBook(record);
      this.emitUpdate(bookId);
    }
    this.stopBackgroundTransferIfIdle();
  }

  async resumeBook(bookId: string): Promise<void> {
    await DownloadNotificationService.requestPermission();
    this.pausedBooks.delete(bookId);
    this.deletedBooks.delete(bookId);
    const record = await DownloadStore.getBook(bookId);
    if (!record) return;
    const book = this.bookFromRecord(record);
    const chapters: Chapter[] = [];
    for (const ch of record.chapters) {
      if (ch.status !== 'completed' && ch.status !== 'deleted') {
        chapters.push(this.chapterFromRecord(ch));
      }
    }
    if (chapters.length === 0) return;
    record.status = 'queued';
    await this.enqueueChapters(book, chapters);
  }

  async deleteBookDownload(bookId: string): Promise<void> {
    this.advanceBookGeneration(bookId);
    this.deletedBooks.add(bookId);
    this.pausedBooks.delete(bookId);
    this.cancelBookTransports(bookId);
    this.resolveQueue = this.resolveQueue.filter((item: DownloadQueueItem) => item.book.id !== bookId);
    this.fileQueue = this.fileQueue.filter((item: DownloadQueueItem) => item.book.id !== bookId);
    this.clearBookProgress(bookId);
    this.notificationBookIds.delete(bookId);
    const record = await DownloadStore.getBook(bookId);
    if (record) {
      for (const chapter of record.chapters) {
        await DownloadStore.deleteFileSafely(chapter.filePath);
      }
    }
    const dir = DownloadStore.getBookDir(bookId);
    if (dir) await this.deleteDirChildren(dir, true);
    await DownloadStore.removeBook(bookId);
    this.removePendingBookKeys(bookId);
    this.emitRawUpdate(bookId, undefined, 'deleted', 0, 0, 0);
    this.refreshNotification(true).catch((_e: Error): void => {});
    this.stopBackgroundTransferIfIdle();
  }

  async deleteChapterDownload(bookId: string, chapterId: string, pageUrl: string = ''): Promise<void> {
    const record = DownloadStore.getBookSync(bookId);
    if (!record) return;
    let chapter: DownloadChapterRecord | undefined = undefined;
    if (pageUrl) chapter = record.chapters.find((item: DownloadChapterRecord) => item.pageUrl === pageUrl);
    if (!chapter) chapter = record.chapters.find((item: DownloadChapterRecord) => item.chapterId === chapterId);
    if (!chapter) return;
    const stablePageUrl = chapter.pageUrl;
    const deletedKey = this.taskKey(bookId, stablePageUrl);
    this.advanceChapterGeneration(deletedKey);
    this.deletedChapters.add(deletedKey);
    const transport = this.activeTransports.get(deletedKey);
    if (transport) transport.cancel();
    this.resolveQueue = this.resolveQueue.filter((item: DownloadQueueItem) =>
      !(item.book.id === bookId && this.matchesChapter(item.chapter, chapterId, stablePageUrl)));
    this.fileQueue = this.fileQueue.filter((item: DownloadQueueItem) =>
      !(item.book.id === bookId && this.matchesChapter(item.chapter, chapterId, stablePageUrl)));
    await DownloadStore.deleteFileSafely(chapter.filePath);
    chapter.status = 'deleted';
    chapter.filePath = '';
    chapter.bytes = 0;
    chapter.updatedAt = Date.now();
    await DownloadStore.saveBook(record);
    this.pendingKeys.delete(deletedKey);
    this.activeProgress.delete(deletedKey);
    this.lastProgressEmitAt.delete(deletedKey);
    this.emitUpdate(bookId, chapterId);
    this.stopBackgroundTransferIfIdle();
  }

  async clearAllDownloads(): Promise<void> {
    this.globalGeneration++;
    for (const transport of this.activeTransports.values()) transport.cancel();
    this.activeTransports.clear();
    this.deletedBooks = new Set((await DownloadStore.getBooks()).map((item: DownloadBookRecord) => item.bookId));
    this.resolveQueue = [];
    this.fileQueue = [];
    this.pendingKeys.clear();
    this.activeProgress.clear();
    this.lastProgressEmitAt.clear();
    this.notificationBookIds.clear();
    const root = DownloadStore.getAudioRootPath();
    if (root) await this.deleteDirChildren(root, false);
    await DownloadStore.clearAll();
    this.emitRawUpdate('', undefined, 'cleared', 0, 0, 0);
    await DownloadNotificationService.cancel();
    this.stopBackgroundTransferIfIdle();
  }

  getBookStatus(bookId: string): DownloadBookRecord | null {
    return DownloadStore.getBookSync(bookId);
  }

  getAllBookStatuses(): DownloadBookRecord[] {
    return DownloadStore.getBooksSync();
  }

  getBookProgress(bookId: string): DownloadProgressSnapshot {
    const record = DownloadStore.getBookSync(bookId);
    if (!record) return this.emptyProgress();
    const chapters = record.chapters.filter((item: DownloadChapterRecord) => item.status !== 'deleted');
    const totalCount = chapters.length;
    if (totalCount === 0) return this.emptyProgress();
    let completedUnits = 0;
    let receivedBytes = 0;
    let expectedBytes = 0;
    let indeterminate = false;
    let currentChapterTitle = '';
    for (const chapter of chapters) {
      if (chapter.status === 'completed') {
        completedUnits++;
        continue;
      }
      const progress = this.activeProgress.get(this.taskKey(bookId, chapter.pageUrl));
      if (!progress) continue;
      receivedBytes += progress.receivedBytes;
      if (progress.totalBytes > 0) {
        expectedBytes += progress.totalBytes;
        completedUnits += Math.min(1, progress.receivedBytes / progress.totalBytes);
      } else {
        indeterminate = true;
      }
      if (!currentChapterTitle) currentChapterTitle = progress.chapterTitle;
    }
    return {
      progressPercent: Math.max(0, Math.min(100, completedUnits / totalCount * 100)),
      receivedBytes,
      expectedBytes,
      indeterminate,
      currentChapterTitle,
      totalCount
    };
  }

  getChapterStatus(bookId: string, chapter: Chapter): DownloadChapterRecord | null {
    const record = DownloadStore.getChapterSync(bookId, chapter);
    if (!record || record.status === 'deleted') return null;
    return record;
  }

  getDownloadedFilePath(bookId: string, chapter: Chapter): string | null {
    const record = DownloadStore.getChapterSync(bookId, chapter);
    if (!record || record.status !== 'completed') return null;
    if (DownloadStore.isExpectedFile(record.filePath, record.bytes)) return record.filePath;
    return null;
  }

  async hydrateBookDurations(bookId: string): Promise<void> {
    if (!bookId || this.durationHydrationBooks.has(bookId)) return;
    this.durationHydrationBooks.add(bookId);
    try {
      const record = await DownloadStore.getBook(bookId);
      if (!record) return;
      let changed = false;
      for (const chapter of record.chapters) {
        if (chapter.status !== 'completed' || (chapter.durationSec ?? 0) > 0
          || !DownloadStore.isExpectedFile(chapter.filePath, chapter.bytes)) continue;
        const durationSec = await this.extractAudioDuration(chapter.filePath);
        if (durationSec <= 0) continue;
        chapter.durationSec = durationSec;
        changed = true;
      }
      if (changed) {
        await DownloadStore.saveBook(record);
        const progress = this.getBookProgress(bookId);
        this.emitRawUpdate(bookId, undefined, record.status, record.downloadedCount, record.failedCount,
          progress.totalCount, progress);
      }
    } finally {
      this.durationHydrationBooks.delete(bookId);
    }
  }

  hasAnyDownload(bookId: string): boolean {
    const record = DownloadStore.getBookSync(bookId);
    if (!record) return false;
    return record.chapters.some((item: DownloadChapterRecord) => item.status === 'completed'
      || item.status === 'pending' || item.status === 'resolving' || item.status === 'downloading'
      || item.status === 'failed');
  }

  private async enqueueChapters(book: Book, chapters: Chapter[]): Promise<number> {
    if (!book || !book.id || chapters.length === 0) return 0;
    if (book.contentType === 'text' || book.category === 'text') return 0;
    this.deletedBooks.delete(book.id);
    this.pausedBooks.delete(book.id);
    const candidates: DownloadQueueItem[] = [];
    const localKeys: Set<string> = new Set();
    for (const chapter of chapters) {
      if (!chapter) continue;
      const pageUrl = this.chapterPageUrl(chapter);
      if (!pageUrl) continue;
      const existing = DownloadStore.getChapterSync(book.id, chapter);
      if (existing && existing.status === 'completed' && DownloadStore.isUsableFile(existing.filePath)) continue;
      const key = this.taskKey(book.id, pageUrl);
      if (this.pendingKeys.has(key) || localKeys.has(key)) continue;
      this.deletedChapters.delete(key);
      localKeys.add(key);
      candidates.push(this.createQueueItem(book, chapter));
    }
    if (candidates.length === 0) return 0;
    const globalGeneration = candidates[0].globalGeneration;
    const bookGeneration = candidates[0].bookGeneration;
    await DownloadStore.prepareChapters(book,
      candidates.map((item: DownloadQueueItem) => item.chapter),
      (): boolean => this.globalGeneration === globalGeneration
        && this.getBookGeneration(book.id) === bookGeneration
        && !this.pausedBooks.has(book.id) && !this.deletedBooks.has(book.id));
    for (const item of candidates) {
      if (!this.isItemCurrent(item)) continue;
      const key = this.itemKey(item);
      this.pendingKeys.set(key, this.itemToken(item));
      this.resolveQueue.push(item);
    }
    this.notificationBookIds.add(book.id);
    await this.startBackgroundTransfer();
    this.emitUpdate(book.id);
    this.drainResolve();
    return candidates.length;
  }

  private drainResolve(): void {
    while (this.resolveRunningCount < MAX_RESOLVE_CONCURRENT && this.resolveQueue.length > 0) {
      const item = this.resolveQueue.shift()!;
      this.resolveRunningCount++;
      this.resolveAndQueueFile(item).then(() => {
        this.resolveRunningCount--;
        this.drainResolve();
        this.stopBackgroundTransferIfIdle();
      }).catch(() => {
        this.resolveRunningCount--;
        this.drainResolve();
        this.stopBackgroundTransferIfIdle();
      });
    }
  }

  private drainFile(): void {
    while (this.fileRunningCount < MAX_FILE_CONCURRENT && this.fileQueue.length > 0) {
      const item = this.fileQueue.shift()!;
      this.fileRunningCount++;
      this.downloadFile(item).then(() => {
        this.fileRunningCount--;
        this.drainFile();
        this.stopBackgroundTransferIfIdle();
      }).catch(() => {
        this.fileRunningCount--;
        this.drainFile();
        this.stopBackgroundTransferIfIdle();
      });
    }
  }

  private async resolveAndQueueFile(item: DownloadQueueItem): Promise<void> {
    const pageUrl = this.chapterPageUrl(item.chapter);
    if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
    try {
      await DownloadStore.upsertChapter(item.book, item.chapter, 'resolving', '', '', 0, '',
        (): boolean => this.isItemCurrent(item));
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      this.emitUpdate(item.book.id, item.chapter.id);
      const sources = await SourceDataService.getSources();
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      const source = sources.find((s) => s.bookSourceUrl === item.book.sourceUrl);
      if (!source) {
        await this.markFailed(item, '书源不存在');
        return;
      }
      const requestInfo = await BookSourceService.resolveAudioRequest(source, pageUrl);
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      if (!this.isValidAudioUrl(pageUrl, requestInfo.url)) {
        await this.markFailed(item, '音频地址解析失败');
        return;
      }
      await DownloadStore.upsertChapter(item.book, item.chapter, 'pending', requestInfo.url, '', 0, '',
        (): boolean => this.isItemCurrent(item));
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      item.requestInfo = requestInfo;
      this.fileQueue.push(item);
      this.drainFile();
    } catch (err) {
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      const e = err as Error;
      await this.markFailed(item, e?.message ?? JSON.stringify(err));
    }
  }

  private async downloadFile(item: DownloadQueueItem): Promise<void> {
    const pageUrl = this.chapterPageUrl(item.chapter);
    const key = this.itemKey(item);
    let transport: AudioDownloadTransport | null = null;
    let filePath = '';
    try {
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      const record = DownloadStore.getChapterSync(item.book.id, item.chapter);
      const audioUrl = item.requestInfo?.url || record?.audioUrl || item.chapter.source.value;
      filePath = DownloadStore.getAudioFilePath(item.book.id, pageUrl) || '';
      if (!filePath) {
        await this.markFailed(item, '下载目录不可用');
        return;
      }
      await DownloadStore.ensureBookDir(item.book.id);
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      if (DownloadStore.isExpectedFile(filePath, record?.bytes ?? 0)) {
        const size = fileIo.statSync(filePath).size;
        await this.ensureChapterDuration(item, filePath, record?.durationSec ?? 0);
        await DownloadStore.upsertChapter(item.book, item.chapter, 'completed', audioUrl, filePath, size, '',
          (): boolean => this.isItemCurrent(item));
        if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
        this.clearPendingItem(item);
        this.emitUpdate(item.book.id, item.chapter.id);
        return;
      }
      await DownloadStore.upsertChapter(item.book, item.chapter, 'downloading', audioUrl, filePath, 0, '',
        (): boolean => this.isItemCurrent(item));
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      this.emitUpdate(item.book.id, item.chapter.id);
      transport = new AudioDownloadTransport();
      this.activeTransports.set(key, transport);
      const bytes = await transport.download({
        url: audioUrl,
        headers: item.requestInfo?.headers || {},
        finalPath: filePath,
        onProgress: (receivedBytes: number, totalBytes: number): void => {
          this.handleProgress(item, receivedBytes, totalBytes);
        }
      });
      if (!this.isItemCurrent(item)) {
        if (this.isItemDeleted(item)) await DownloadStore.deleteFileSafely(filePath);
        return this.discardStaleItem(item);
      }
      await this.ensureChapterDuration(item, filePath);
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      await DownloadStore.upsertChapter(item.book, item.chapter, 'completed', audioUrl, filePath, bytes, '',
        (): boolean => this.isItemCurrent(item));
      if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
      this.clearPendingItem(item);
      this.emitUpdate(item.book.id, item.chapter.id);
    } catch (err) {
      if (!this.isItemCurrent(item)) {
        if (filePath && this.isItemDeleted(item)) await DownloadStore.deleteFileSafely(filePath);
        return this.discardStaleItem(item);
      }
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'downloadFile failed: %{public}s', e?.message ?? JSON.stringify(err));
      await this.markFailed(item, e?.message ?? JSON.stringify(err));
    } finally {
      if (transport && this.activeTransports.get(key) === transport) this.activeTransports.delete(key);
    }
  }

  private async markFailed(item: DownloadQueueItem, reason: string): Promise<void> {
    if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
    const failureCode: DownloadFailureCode = DownloadPolicy.classifyFailure(reason);
    if (failureCode === 'cancelled') return this.discardStaleItem(item);
    await DownloadStore.upsertChapter(item.book, item.chapter, 'failed', '', '', 0, reason,
      (): boolean => this.isItemCurrent(item), failureCode);
    if (!this.isItemCurrent(item)) return this.discardStaleItem(item);
    this.clearPendingItem(item);
    this.emitUpdate(item.book.id, item.chapter.id);
  }

  private async ensureChapterDuration(item: DownloadQueueItem, filePath: string,
    knownDurationSec: number = 0): Promise<void> {
    let durationSec = item.chapter.duration > 0 ? item.chapter.duration : knownDurationSec;
    if (durationSec <= 0) durationSec = await this.extractAudioDuration(filePath);
    if (durationSec <= 0) return;
    item.chapter.duration = durationSec;
    const pageUrl = this.chapterPageUrl(item.chapter);
    const original = item.book.chapters.find((chapter: Chapter) => chapter.id === item.chapter.id
      || this.chapterPageUrl(chapter) === pageUrl);
    if (original) original.duration = durationSec;
  }

  private async extractAudioDuration(filePath: string): Promise<number> {
    let extractor: media.AVMetadataExtractor | null = null;
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
      const metadata = await extractor.fetchMetadata();
      const durationMs = parseInt(metadata.duration ?? '0', 10);
      return Number.isFinite(durationMs) && durationMs > 0 ? Math.round(durationMs / 1000) : 0;
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'extract duration failed: %{public}s', e?.message ?? JSON.stringify(err));
      return 0;
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (_e) { /* ignore */ }
      }
      if (file) {
        try { await fileIo.close(file); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async refreshBookToc(book: Book): Promise<Book> {
    const sources = await SourceDataService.getSources();
    const source = sources.find(s => s.bookSourceUrl === book.sourceUrl);
    if (!source || !book.bookUrl) return book;
    let tocUrl = book.bookUrl;
    const bookInfo: BookInfo | null = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
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
    if (bookInfo?.tocUrl) tocUrl = bookInfo.tocUrl;
    const tocItems = await BookSourceService.getBookToc(source, tocUrl, mergedVars, book.title);
    if (tocItems.length === 0) return book;
    const seenUrls = new Set<string>();
    const unique = tocItems.filter((item: TocItem) => {
      if (!item.url || seenUrls.has(item.url)) return false;
      seenUrls.add(item.url);
      return true;
    });
    const chapters = unique.map((item: TocItem, idx: number): Chapter => ({
      id: `${book.id}-c${idx}`,
      index: idx + 1,
      title: item.name,
      duration: item.duration || 0,
      source: { type: 'url', value: item.url },
      originSourceValue: item.url
    }));
    const refreshed: Book = {
      id: book.id,
      contentType: book.contentType,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      cover: book.cover,
      category: book.category,
      intro: bookInfo?.intro || book.intro,
      totalDuration: book.totalDuration,
      chapterCount: chapters.length,
      rating: book.rating,
      tags: book.tags,
      chapters,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: Object.keys(mergedVars).length > 0 ? mergedVars : book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro
    };
    await DataService.upsertCachedBook(refreshed);
    return refreshed;
  }

  private isValidAudioUrl(pageUrl: string, audioUrl: string): boolean {
    if (!audioUrl || !audioUrl.startsWith('http')) return false;
    if (audioUrl !== pageUrl) return true;
    return this.looksLikeDirectAudioUrl(audioUrl);
  }

  private looksLikeDirectAudioUrl(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.indexOf('.mp3') >= 0 || lower.indexOf('.m4a') >= 0
      || lower.indexOf('.aac') >= 0 || lower.indexOf('.flac') >= 0
      || lower.indexOf('.wav') >= 0 || lower.indexOf('.ogg') >= 0;
  }

  private async restoreInterruptedDownloads(): Promise<void> {
    const records = await DownloadStore.getBooks();
    for (const record of records) {
      if (record.status !== 'queued') continue;
      const chapters: Chapter[] = [];
      for (const chapter of record.chapters) {
        if (chapter.status === 'pending' || chapter.status === 'resolving' || chapter.status === 'downloading') {
          chapters.push(this.chapterFromRecord(chapter));
        }
      }
      if (chapters.length > 0) await this.enqueueChapters(this.bookFromRecord(record), chapters);
    }
  }

  private createQueueItem(book: Book, chapter: Chapter): DownloadQueueItem {
    const clonedChapter = this.cloneChapter(chapter);
    const key = this.taskKey(book.id, this.chapterPageUrl(clonedChapter));
    return {
      book: this.cloneBook(book),
      chapter: clonedChapter,
      globalGeneration: this.globalGeneration,
      bookGeneration: this.getBookGeneration(book.id),
      chapterGeneration: this.getChapterGeneration(key)
    };
  }

  private isItemCurrent(item: DownloadQueueItem): boolean {
    return DownloadPolicy.isGenerationCurrent({
      global: item.globalGeneration,
      book: item.bookGeneration,
      chapter: item.chapterGeneration
    }, {
      global: this.globalGeneration,
      book: this.getBookGeneration(item.book.id),
      chapter: this.getChapterGeneration(this.itemKey(item))
    }, this.pausedBooks.has(item.book.id), this.isItemDeleted(item));
  }

  private isItemDeleted(item: DownloadQueueItem): boolean {
    return this.deletedBooks.has(item.book.id) || this.deletedChapters.has(this.itemKey(item));
  }

  private discardStaleItem(item: DownloadQueueItem): void {
    this.clearPendingItem(item);
  }

  private getBookGeneration(bookId: string): number {
    return this.bookGenerations.get(bookId) ?? 0;
  }

  private advanceBookGeneration(bookId: string): void {
    this.bookGenerations.set(bookId, this.getBookGeneration(bookId) + 1);
  }

  private getChapterGeneration(key: string): number {
    return this.chapterGenerations.get(key) ?? 0;
  }

  private advanceChapterGeneration(key: string): void {
    this.chapterGenerations.set(key, this.getChapterGeneration(key) + 1);
  }

  private cancelBookTransports(bookId: string): void {
    const prefix = `${bookId}|`;
    for (const item of this.activeTransports.entries()) {
      if (item[0].startsWith(prefix)) item[1].cancel();
    }
  }

  private removePendingBookKeys(bookId: string): void {
    const prefix = `${bookId}|`;
    for (const key of this.pendingKeys.keys()) {
      if (key.startsWith(prefix)) this.pendingKeys.delete(key);
    }
  }

  private matchesChapter(chapter: Chapter, chapterId: string, pageUrl: string): boolean {
    return DownloadPolicy.matchesChapter(chapter.id, this.chapterPageUrl(chapter), chapterId, pageUrl);
  }

  private chapterPageUrl(chapter: Chapter): string {
    return DownloadPolicy.stablePageUrl(chapter);
  }

  private itemKey(item: DownloadQueueItem): string {
    return this.taskKey(item.book.id, this.chapterPageUrl(item.chapter));
  }

  private itemToken(item: DownloadQueueItem): string {
    return DownloadPolicy.generationToken({
      global: item.globalGeneration,
      book: item.bookGeneration,
      chapter: item.chapterGeneration
    });
  }

  private clearPendingItem(item: DownloadQueueItem): void {
    const key = this.itemKey(item);
    if (this.pendingKeys.get(key) === this.itemToken(item)) this.pendingKeys.delete(key);
    this.activeProgress.delete(key);
    this.lastProgressEmitAt.delete(key);
  }

  private async startBackgroundTransfer(): Promise<void> {
    if (!this.ctx) return;
    await BackgroundTaskService.startDataTransfer(this.ctx as common.UIAbilityContext);
  }

  private stopBackgroundTransferIfIdle(): void {
    if (this.resolveQueue.length > 0 || this.fileQueue.length > 0
      || this.resolveRunningCount > 0 || this.fileRunningCount > 0 || this.pendingKeys.size > 0) return;
    if (!this.ctx) return;
    BackgroundTaskService.stopDataTransfer(this.ctx as common.UIAbilityContext).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'stop background transfer failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  private taskKey(bookId: string, pageUrl: string): string {
    return DownloadPolicy.taskKey(bookId, pageUrl);
  }

  private handleProgress(item: DownloadQueueItem, receivedBytes: number, totalBytes: number): void {
    if (!this.isItemCurrent(item)) return;
    const key = this.itemKey(item);
    this.activeProgress.set(key, {
      bookId: item.book.id,
      chapterId: item.chapter.id,
      chapterTitle: item.chapter.title,
      receivedBytes,
      totalBytes
    });
    const now = Date.now();
    const last = this.lastProgressEmitAt.get(key) ?? 0;
    if (now - last < 500) return;
    this.lastProgressEmitAt.set(key, now);
    this.emitUpdate(item.book.id, item.chapter.id, false);
  }

  private emptyProgress(): DownloadProgressSnapshot {
    return {
      progressPercent: 0,
      receivedBytes: 0,
      expectedBytes: 0,
      indeterminate: false,
      currentChapterTitle: '',
      totalCount: 0
    };
  }

  private clearBookProgress(bookId: string): void {
    const prefix = `${bookId}|`;
    for (const key of this.activeProgress.keys()) {
      if (key.startsWith(prefix)) this.activeProgress.delete(key);
    }
    for (const key of this.lastProgressEmitAt.keys()) {
      if (key.startsWith(prefix)) this.lastProgressEmitAt.delete(key);
    }
  }

  private emitUpdate(bookId: string, chapterId?: string, forceNotification: boolean = true): void {
    const record = DownloadStore.getBookSync(bookId);
    if (!record) {
      this.emitRawUpdate(bookId, chapterId, 'idle', 0, 0, 0);
      return;
    }
    const progress = this.getBookProgress(bookId);
    this.emitRawUpdate(bookId, chapterId, record.status, record.downloadedCount, record.failedCount,
      progress.totalCount, progress, !forceNotification);
    this.refreshNotification(forceNotification).catch((_e: Error): void => {});
  }

  private emitRawUpdate(bookId: string, chapterId: string | undefined, status: string,
    downloadedCount: number, failedCount: number, totalCount: number,
    progress: DownloadProgressSnapshot = this.emptyProgress(), progressOnly: boolean = false): void {
    emitter.emit(EVT_DOWNLOAD_UPDATED, {
      data: {
        bookId,
        chapterId,
        status,
        downloadedCount,
        failedCount,
        totalCount,
        progressPercent: progress.progressPercent,
        receivedBytes: progress.receivedBytes,
        expectedBytes: progress.expectedBytes,
        indeterminate: progress.indeterminate,
        currentChapterTitle: progress.currentChapterTitle,
        progressOnly
      } as DownloadUpdatePayload
    });
  }

  private async refreshNotification(force: boolean): Promise<void> {
    const now = Date.now();
    const records: DownloadBookRecord[] = [];
    for (const bookId of this.notificationBookIds) {
      const record = DownloadStore.getBookSync(bookId);
      if (record) records.push(record);
    }
    if (records.length === 0) {
      await DownloadNotificationService.cancel();
      return;
    }
    const active = records.filter((item: DownloadBookRecord) => item.status === 'downloading'
      || item.status === 'queued');
    const paused = records.filter((item: DownloadBookRecord) => item.status === 'paused');
    const status = active.length > 0 ? 'downloading'
      : paused.length > 0 ? 'paused'
        : records.some((item: DownloadBookRecord) => item.failedCount > 0) ? 'failed' : 'completed';
    if ((!force || status === 'downloading') && now - this.lastNotificationAt < 1000) return;
    this.lastNotificationAt = now;
    const summary = this.notificationSummary(records, status);
    await DownloadNotificationService.publish(summary);
    if (summary.status === 'completed' || summary.status === 'failed') this.notificationBookIds.clear();
  }

  private notificationSummary(records: DownloadBookRecord[], status: 'downloading' | 'paused'
    | 'completed' | 'failed'): DownloadNotificationSummary {
    let totalCount = 0;
    let downloadedCount = 0;
    let weightedProgress = 0;
    for (const record of records) {
      const progress = this.getBookProgress(record.bookId);
      totalCount += progress.totalCount;
      downloadedCount += record.downloadedCount;
      weightedProgress += progress.progressPercent * progress.totalCount;
    }
    const progressPercent = totalCount > 0 ? weightedProgress / totalCount : 0;
    let title = records.length === 1 ? records[0].title : `正在下载 ${records.length} 本书`;
    if (status === 'paused') title = records.length === 1 ? `${records[0].title} · 已暂停` : '下载已暂停';
    if (status === 'completed') title = '离线下载完成';
    if (status === 'failed') title = '离线下载结束';
    const failedCount = records.reduce((sum: number, item: DownloadBookRecord) => sum + item.failedCount, 0);
    const detail = status === 'failed' ? `已完成 ${downloadedCount}/${totalCount} 章，失败 ${failedCount} 章`
      : `已完成 ${downloadedCount}/${totalCount} 章`;
    return { title, detail, progressPercent, status };
  }

  private cloneBook(book: Book): Book {
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
      tags: book.tags,
      chapters: book.chapters,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro
    };
  }

  private cloneChapter(chapter: Chapter): Chapter {
    return {
      id: chapter.id,
      index: chapter.index,
      title: chapter.title,
      duration: chapter.duration,
      source: { type: chapter.source.type, value: chapter.source.value },
      originSourceValue: chapter.originSourceValue
    };
  }

  private bookFromRecord(record: DownloadBookRecord): Book {
    return {
      id: record.bookId,
      contentType: record.contentType === 'text' ? 'text' : 'audio',
      title: record.title,
      author: record.author,
      narrator: '',
      cover: record.cover,
      category: '',
      intro: '',
      totalDuration: 0,
      chapterCount: record.chapterCount,
      rating: 0,
      tags: [],
      chapters: record.chapters.map((item: DownloadChapterRecord) => this.chapterFromRecord(item)),
      bookUrl: record.bookUrl,
      sourceUrl: record.sourceUrl
    };
  }

  private chapterFromRecord(record: DownloadChapterRecord): Chapter {
    return {
      id: record.chapterId,
      index: record.chapterIndex,
      title: record.title,
      duration: record.durationSec ?? 0,
      source: { type: 'url', value: record.pageUrl },
      originSourceValue: record.pageUrl
    };
  }

  private async deleteDirChildren(dir: string, removeSelf: boolean): Promise<void> {
    let names: string[] = [];
    try {
      names = await fileIo.listFile(dir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      const path = `${dir}/${name}`;
      try {
        const st = await fileIo.stat(path);
        if (st.isDirectory()) {
          await this.deleteDirChildren(path, true);
        } else {
          await fileIo.unlink(path);
        }
      } catch (_e) {
        // ignore
      }
    }
    if (removeSelf) {
      try { await fileIo.rmdir(dir); } catch (_e) { /* ignore */ }
    }
  }
}
