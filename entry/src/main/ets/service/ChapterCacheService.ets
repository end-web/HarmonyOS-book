import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { AudioRequestInfo, BookSourceService } from './BookSourceService';
import { SourceDataService } from './SourceDataService';

const DOMAIN = 0x0001;
const TAG = 'ChapterCache';

export const EVT_CHAPTER_DURATION_UPDATED = 'app.chapter.duration.updated';

let PRE_DOWNLOAD_FORWARD = 3;
let PRE_DOWNLOAD_BACKWARD = 0;
const MAX_CONCURRENT = 2;             // URL 解析（WebView/HTTP）最多 2 并发
const MAX_FILE_CONCURRENT = 2;        // 音频文件下载最多 2 并发
const MAX_URL_CACHE_SIZE = 50;
const MAX_FILE_CACHE_BYTES = 1024 * 1024 * 1024; // 章节临时音频缓存上限 1GB
const PRELOAD_FAILURE_COOLDOWN_MS = 30000;

class ClearCacheResult {
  deleted: number = 0;
  failed: number = 0;
}

interface CacheEntry {
  resolvedUrl: string;
  headers: Record<string, string>;
  timestamp: number;
}

interface FileCacheEntry {
  /** 沙箱内的绝对路径 */
  filePath: string;
  /** 对应章节页 URL（书源解析的入口）— 用于命中校验 */
  pageUrl: string;
  bytes: number;
  timestamp: number;
}

interface DiskCacheEntry {
  filePath: string;
  bytes: number;
  timestamp: number;
}

export class ChapterCacheService {
  private static instance: ChapterCacheService | null = null;
  private audioCache: Map<string, CacheEntry> = new Map();
  /** 章节 → 已下载到本地的音频文件 */
  private fileCache: Map<string, FileCacheEntry> = new Map();
  /** 章节 → 解析出的真实时长（秒）。来自缓存音频文件的元数据 */
  private durationCache: Map<string, number> = new Map();
  private pendingTasks: Set<string> = new Set();
  private preloadFailureAt: Map<string, number> = new Map();
  private runningCount: number = 0;
  private queue: Array<() => Promise<void>> = [];
  private fileRunningCount: number = 0;
  private fileQueue: Array<() => Promise<void>> = [];
  private appContext: common.Context | null = null;
  private clearGen: number = 0;

  static getInstance(): ChapterCacheService {
    if (!ChapterCacheService.instance) {
      ChapterCacheService.instance = new ChapterCacheService();
    }
    return ChapterCacheService.instance;
  }

  setPreloadCount(forward: number, backward: number = 0): void {
    PRE_DOWNLOAD_FORWARD = forward;
    PRE_DOWNLOAD_BACKWARD = backward;
    if (forward <= 0) {
      // 不预加载时丢弃尚未开始的 URL 解析任务；正在执行的请求自然结束。
      this.queue = [];
      this.fileQueue = [];
    }
  }

  getPreloadForward(): number {
    return PRE_DOWNLOAD_FORWARD;
  }

  isPreloadEnabled(): boolean {
    return PRE_DOWNLOAD_FORWARD > 0;
  }

  isChapterCached(chapterId: string): boolean {
    return this.audioCache.has(chapterId) || this.fileCache.has(chapterId);
  }

  isAudioChapterCached(_book: Book, chapter: Chapter): boolean {
    if (chapter.source.type === 'file' || chapter.source.type === 'rawfile') return true;
    return this.audioCache.has(chapter.id) || this.fileCache.has(chapter.id);
  }

  /** 已解析的章节真实时长（秒）。仅在音频文件下载完成后才有值。 */
  getChapterDuration(chapterId: string): number {
    return this.durationCache.get(chapterId) ?? 0;
  }

  async clearAllCache(): Promise<ClearCacheResult> {
    const myGen = ++this.clearGen;
    this.audioCache.clear();
    this.durationCache.clear();
    this.preloadFailureAt.clear();
    this.queue = [];
    this.fileQueue = [];
    this.pendingTasks.clear();
    const result = new ClearCacheResult();
    const unlinkPromises: Promise<void>[] = [];
    for (const entry of this.fileCache.values()) {
      unlinkPromises.push(fileIo.unlink(entry.filePath).then((): void => { result.deleted++; }).catch((): void => { result.failed++; }));
    }
    this.fileCache.clear();
    const ctx = this.appContext;
    if (ctx) {
      try {
        const names = await fileIo.listFile(ctx.cacheDir);
        for (const name of names) {
          if (!name.startsWith('chap_')) continue;
          const p = `${ctx.cacheDir}/${name}`;
          unlinkPromises.push(fileIo.unlink(p).then((): void => { result.deleted++; }).catch((): void => { result.failed++; }));
        }
      } catch (_e) { /* ignore */ }
    }
    await Promise.all(unlinkPromises);
    return result;
  }

  /**
   * 物理清除磁盘上的章节音频与图片缓存，并顺带清理旧版本遗留的 reader 文件。
   */
  async wipeDiskCaches(): Promise<void> {
    await this.clearAllCache();
    const ctx = this.appContext;
    if (!ctx) return;
    await ChapterCacheService.deleteEntries(ctx.filesDir, true);
    await ChapterCacheService.deleteEntries(ctx.cacheDir, false);
  }

  /** readerScope=true:删 filesDir 里的旧缓存;false:删 cacheDir 里的章节/图片/卡片封面缓存 */
  private static async deleteEntries(dir: string, readerScope: boolean): Promise<void> {
    let names: string[] = [];
    try {
      names = await fileIo.listFile(dir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      const hit = readerScope
        ? (name.startsWith('reader_') || name.startsWith('widget_cover_'))
        : (name.startsWith('chap_') || name.startsWith('widget_cover_') || name === 'image_file_cache');
      if (!hit) continue;
      const p = `${dir}/${name}`;
      try {
        const st = await fileIo.stat(p);
        if (st.isDirectory()) {
          await fileIo.rmdir(p);
        } else {
          await fileIo.unlink(p);
        }
      } catch (_e) { /* ignore */ }
    }
  }

  setContext(ctx: common.Context): void {
    this.appContext = ctx;
    this.enforceDiskCacheLimit().catch((): void => { /* 系统缓存目录不可用时交由系统回收 */ });
  }

  getAudioUrl(chapterId: string): string | null {
    const entry = this.audioCache.get(chapterId);
    return entry ? entry.resolvedUrl : null;
  }

  getAudioHeaders(chapterId: string): Record<string, string> {
    const entry = this.audioCache.get(chapterId);
    return entry ? entry.headers : {};
  }

  /** 章节是否已经有完整音频文件落盘，命中后 AudioService 直接 fdSrc 播放 */
  getAudioFilePath(bookId: string, chapterId: string, pageUrl: string): string | null {
    const safePageUrl = pageUrl || '';
    const entry = this.fileCache.get(chapterId);
    if (entry) {
      // pageUrl 不一致说明缓存对应的章节不同（书源 toc 重排过），失效
      if (entry.pageUrl === safePageUrl && this.isUsableFile(entry.filePath)) {
        entry.timestamp = Date.now();
        try {
          fileIo.utimes(entry.filePath, entry.timestamp);
        } catch (_e) { /* 文件可能刚被系统缓存清理 */ }
        return entry.filePath;
      }
      this.fileCache.delete(chapterId);
    }

    const stablePath = this.audioFilePath(bookId, safePageUrl);
    const restored = this.restoreFileCacheEntry(chapterId, safePageUrl, stablePath);
    if (restored) return restored;

    // 兼容旧版本已经下载到磁盘的 chap_<hash(bookId|chapterId)>.mp3。
    const legacyPath = this.legacyAudioFilePath(bookId, chapterId);
    return this.restoreFileCacheEntry(chapterId, safePageUrl, legacyPath);
  }

  preloadAudioChapters(book: Book, currentIndex: number): void {
    if (!book.sourceUrl || PRE_DOWNLOAD_FORWARD <= 0) return;
    const start = Math.max(0, currentIndex - PRE_DOWNLOAD_BACKWARD);
    const end = Math.min(book.chapters.length - 1, currentIndex + PRE_DOWNLOAD_FORWARD);
    for (let i = start; i <= end; i++) {
      if (i === currentIndex) continue;
      const ch = book.chapters[i];
      if (ch.source.type !== 'url') continue;
      if (this.isPreloadCoolingDown(ch.id)) continue;
      const pageUrl = ch.originSourceValue || ch.source.value;
      if (this.getAudioFilePath(book.id, ch.id, pageUrl)) continue;
      // 1) URL 解析
      if (!this.audioCache.has(ch.id) && !this.pendingTasks.has(`audio_${ch.id}`)) {
        this.enqueue(() => this.resolveAudioAndDownload(book, ch));
      } else if (this.audioCache.has(ch.id) && !this.pendingTasks.has(`file_${ch.id}`)) {
        // 2) URL 已有，仅下载文件
        const cached = this.audioCache.get(ch.id);
        if (cached) {
          this.enqueueFile(() => this.downloadFile(book, ch, cached.resolvedUrl, cached.headers));
        }
      }
    }
  }

  clearBook(bookId: string): void {
    const prefix = bookId + '-c';
    for (const key of this.audioCache.keys()) {
      if (key.startsWith(prefix)) this.audioCache.delete(key);
    }
    for (const key of this.durationCache.keys()) {
      if (key.startsWith(prefix)) this.durationCache.delete(key);
    }
    for (const key of this.preloadFailureAt.keys()) {
      if (key.startsWith(prefix)) this.preloadFailureAt.delete(key);
    }
    for (const key of this.fileCache.keys()) {
      if (key.startsWith(prefix)) {
        const entry = this.fileCache.get(key);
        if (entry) this.deleteFileSafely(entry.filePath);
        this.fileCache.delete(key);
      }
    }
  }

  /** 清除某个章节的所有缓存（临时签名 URL 失效时用） */
  clearChapter(chapterId: string): void {
    this.audioCache.delete(chapterId);
    this.durationCache.delete(chapterId);
    this.preloadFailureAt.delete(chapterId);
    const entry = this.fileCache.get(chapterId);
    if (entry) this.deleteFileSafely(entry.filePath);
    this.fileCache.delete(chapterId);
  }

  /** 主动给某个章节下载文件（AudioService 在 playChapter 时调用，让当前章节也能落盘） */
  ensureFileCached(book: Book, chapter: Chapter, resolvedUrl: string,
    headers: Record<string, string> = {}): void {
    if (!this.isPreloadEnabled()) return;
    if (!resolvedUrl || !resolvedUrl.startsWith('http')) return;
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (this.getAudioFilePath(book.id, chapter.id, pageUrl)) return;
    if (this.pendingTasks.has(`file_${chapter.id}`)) return;
    this.enqueueFile(() => this.downloadFile(book, chapter, resolvedUrl, headers));
  }

  /* ───────────── 内部：URL 解析队列 ───────────── */

  private enqueue(task: () => Promise<void>): void {
    this.queue.push(task);
    this.drain();
  }

  private drain(): void {
    while (this.runningCount < MAX_CONCURRENT && this.queue.length > 0) {
      const task = this.queue.shift()!;
      this.runningCount++;
      task().then(() => {
        this.runningCount--;
        this.drain();
      }).catch(() => {
        this.runningCount--;
        this.drain();
      });
    }
  }

  /* ───────────── 内部：音频文件下载队列 ───────────── */

  private enqueueFile(task: () => Promise<void>): void {
    this.fileQueue.push(task);
    this.drainFile();
  }

  private drainFile(): void {
    while (this.fileRunningCount < MAX_FILE_CONCURRENT && this.fileQueue.length > 0) {
      const task = this.fileQueue.shift()!;
      this.fileRunningCount++;
      task().then(() => {
        this.fileRunningCount--;
        this.drainFile();
      }).catch(() => {
        this.fileRunningCount--;
        this.drainFile();
      });
    }
  }

  /* ───────────── 内部：解析 + 下载 ───────────── */

  private async resolveAudioAndDownload(book: Book, chapter: Chapter): Promise<void> {
    const myClearGen = this.clearGen;
    const taskKey = `audio_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!source) throw new Error('预加载书源不可用');
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const requestInfo: AudioRequestInfo =
        await BookSourceService.resolveAudioRequest(source, pageUrl, book.variables, chapter.variables);
      const audioUrl = requestInfo.url;
      if (audioUrl && audioUrl !== pageUrl) {
        this.preloadFailureAt.delete(chapter.id);
        this.evictUrlCache();
        this.audioCache.set(chapter.id, {
          resolvedUrl: audioUrl,
          headers: requestInfo.headers,
          timestamp: Date.now()
        });
        // URL 拿到后顺手把文件也下了
        if (myClearGen === this.clearGen) {
          this.enqueueFile(() => this.downloadFileCheckGen(book, chapter, audioUrl, requestInfo.headers, myClearGen));
        }
      } else {
        throw new Error('预加载未获取到有效音频地址');
      }
    } catch (err) {
      this.markPreloadFailure(chapter.id);
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'resolve preload failed [%{public}s]: %{public}s', chapter.title,
        e?.message ?? JSON.stringify(err));
    } finally {
      this.pendingTasks.delete(taskKey);
    }
  }

  private downloadFileCheckGen(book: Book, chapter: Chapter, audioUrl: string,
    headers: Record<string, string>, gen: number): Promise<void> {
    if (gen !== this.clearGen) return Promise.resolve();
    return this.downloadFile(book, chapter, audioUrl, headers);
  }

  private async downloadFile(book: Book, chapter: Chapter, audioUrl: string,
    headers: Record<string, string> = {}): Promise<void> {
    if (!this.appContext) return;
    if (!audioUrl || !audioUrl.startsWith('http')) return;
    if (this.fileCache.has(chapter.id)) return;
    const capturedGen = this.clearGen;
    const taskKey = `file_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    let httpClient: http.HttpRequest | null = null;
    let f: fileIo.File | null = null;
    try {
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const filePath = this.audioFilePath(book.id, pageUrl);
      if (!filePath) return;
      // 已存在直接复用（避免重复下）
      const restored = this.restoreFileCacheEntry(chapter.id, pageUrl, filePath)
        ?? this.restoreFileCacheEntry(chapter.id, pageUrl, this.legacyAudioFilePath(book.id, chapter.id));
      if (restored) {
        this.extractDuration(chapter, restored);
        return;
      }

      httpClient = http.createHttp();
      const resp = await httpClient.request(audioUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (resp.responseCode !== 200 || !resp.result) {
        this.markPreloadFailure(chapter.id);
        hilog.warn(DOMAIN, TAG, 'download failed [%{public}d] %{public}s', resp.responseCode, chapter.title);
        return;
      }
      const buf = resp.result as ArrayBuffer;
      f = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, buf);
      await fileIo.close(f);
      f = null;
      if (capturedGen !== this.clearGen) return;
      this.fileCache.set(chapter.id, {
        filePath,
        pageUrl,
        bytes: buf.byteLength,
        timestamp: Date.now(),
      });
      this.preloadFailureAt.delete(chapter.id);
      this.evictFileCache();
      await this.enforceDiskCacheLimit();
      this.extractDuration(chapter, filePath);
    } catch (err) {
      this.markPreloadFailure(chapter.id);
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'downloadFile failed: %{public}s', e?.message ?? JSON.stringify(err));
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
      if (httpClient) httpClient.destroy();
      this.pendingTasks.delete(taskKey);
    }
  }

  private isPreloadCoolingDown(chapterId: string): boolean {
    const failedAt = this.preloadFailureAt.get(chapterId) ?? 0;
    if (failedAt <= 0) return false;
    if (Date.now() - failedAt < PRELOAD_FAILURE_COOLDOWN_MS) return true;
    this.preloadFailureAt.delete(chapterId);
    return false;
  }

  private markPreloadFailure(chapterId: string): void {
    this.preloadFailureAt.set(chapterId, Date.now());
  }

  private async findSource(sourceUrl: string): Promise<BookSource | null> {
    return await SourceDataService.getSourceByUrl(sourceUrl) ?? null;
  }

  private evictUrlCache(): void {
    if (this.audioCache.size < MAX_URL_CACHE_SIZE) return;
    const first = this.audioCache.keys().next();
    if (!first.done) this.audioCache.delete(first.value);
  }

  /** 文件缓存超过 1GB 后，按最近访问时间淘汰最久未使用的章节。 */
  private evictFileCache(): void {
    let totalBytes: number = 0;
    for (const entry of this.fileCache.values()) {
      totalBytes += Math.max(0, entry.bytes);
    }
    while (totalBytes > MAX_FILE_CACHE_BYTES) {
      let oldestId: string | null = null;
      let oldestTimestamp: number = Number.MAX_SAFE_INTEGER;
      for (const id of this.fileCache.keys()) {
        const candidate = this.fileCache.get(id);
        if (candidate && candidate.timestamp < oldestTimestamp) {
          oldestId = id;
          oldestTimestamp = candidate.timestamp;
        }
      }
      if (oldestId === null) return;
      const entry = this.fileCache.get(oldestId);
      if (entry) {
        totalBytes -= Math.max(0, entry.bytes);
        this.deleteFileSafely(entry.filePath);
      }
      this.fileCache.delete(oldestId);
    }
  }

  /** 冷启动时按磁盘实际大小执行 1GB 上限，避免上个进程遗留文件脱离内存索引。 */
  private async enforceDiskCacheLimit(): Promise<void> {
    const ctx = this.appContext;
    if (!ctx) return;
    let names: string[] = [];
    try {
      names = await fileIo.listFile(ctx.cacheDir);
    } catch (_e) {
      return;
    }
    const entries: DiskCacheEntry[] = [];
    let totalBytes: number = 0;
    for (const name of names) {
      if (!name.startsWith('chap_')) continue;
      const filePath = `${ctx.cacheDir}/${name}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.isDirectory()) continue;
        const entry: DiskCacheEntry = {
          filePath,
          bytes: Math.max(0, stat.size),
          timestamp: stat.mtime,
        };
        entries.push(entry);
        totalBytes += entry.bytes;
      } catch (_e) { /* 文件可能被系统并发清理 */ }
    }
    if (totalBytes <= MAX_FILE_CACHE_BYTES) return;
    entries.sort((left: DiskCacheEntry, right: DiskCacheEntry): number => left.timestamp - right.timestamp);
    for (const entry of entries) {
      if (totalBytes <= MAX_FILE_CACHE_BYTES) return;
      try {
        await fileIo.unlink(entry.filePath);
        totalBytes -= entry.bytes;
        this.removeFileCacheEntry(entry.filePath);
      } catch (_e) { /* 正在使用或已经被系统删除 */ }
    }
  }

  private removeFileCacheEntry(filePath: string): void {
    for (const chapterId of this.fileCache.keys()) {
      const entry = this.fileCache.get(chapterId);
      if (entry && entry.filePath === filePath) {
        this.fileCache.delete(chapterId);
        return;
      }
    }
  }

  private deleteFileSafely(path: string): void {
    try {
      fileIo.unlink(path).catch(() => { /* ignore */ });
    } catch (_e) { /* ignore */ }
  }

  private audioFilePath(bookId: string, pageUrl: string): string | null {
    if (!this.appContext || !bookId || !pageUrl) return null;
    return `${this.appContext.cacheDir}/chap_${this.hash(bookId + '|' + pageUrl)}.mp3`;
  }

  private legacyAudioFilePath(bookId: string, chapterId: string): string | null {
    if (!this.appContext || !bookId || !chapterId) return null;
    return `${this.appContext.cacheDir}/chap_${this.hash(bookId + '|' + chapterId)}.mp3`;
  }

  private restoreFileCacheEntry(chapterId: string, pageUrl: string, filePath: string | null): string | null {
    if (!filePath || !this.isUsableFile(filePath)) return null;
    let bytes = 0;
    try {
      bytes = fileIo.statSync(filePath).size;
    } catch (_e) {
      bytes = 0;
    }
    this.fileCache.set(chapterId, {
      filePath,
      pageUrl,
      bytes,
      timestamp: Date.now(),
    });
    this.evictFileCache();
    return filePath;
  }

  private isUsableFile(filePath: string): boolean {
    try {
      return fileIo.statSync(filePath).size > 1024;
    } catch (_e) {
      return false;
    }
  }

  /** 解析音频文件的元数据时长（秒），写入 durationCache 并广播事件让 UI 刷新 */
  private async extractDuration(chapter: Chapter, filePath: string): Promise<void> {
    if (this.durationCache.has(chapter.id)) return;
    let extractor: media.AVMetadataExtractor | null = null;
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      const meta = await extractor.fetchMetadata();
      const ms = parseInt(meta.duration ?? '0', 10);
      if (Number.isFinite(ms) && ms > 0) {
        const seconds = Math.round(ms / 1000);
        this.durationCache.set(chapter.id, seconds);
        emitter.emit(EVT_CHAPTER_DURATION_UPDATED, {
          data: { chapterId: chapter.id, durationSec: seconds }
        });
      }
    } catch (err) {
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (_e) { /* ignore */ }
      }
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
  }

  private hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }
}
