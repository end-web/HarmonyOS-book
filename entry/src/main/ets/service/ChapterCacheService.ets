import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { BookSourceService } from './BookSourceService';
import { SourceDataService } from './SourceDataService';
import { PreferenceService } from './PreferenceService';

interface ClearListenedResult {
  deletedFiles: number;
  freedBytes: number;
  keptFiles: number;
}

const DOMAIN = 0x0001;
const TAG = 'ChapterCache';

export const EVT_CHAPTER_DURATION_UPDATED = 'app.chapter.duration.updated';

let PRE_DOWNLOAD_FORWARD = 3;
let PRE_DOWNLOAD_BACKWARD = 0;
const MAX_CONCURRENT = 2;             // URL 解析（WebView/HTTP）最多 2 并发
const MAX_FILE_CONCURRENT = 2;        // 音频文件下载最多 2 并发
const MAX_URL_CACHE_SIZE = 50;
const MAX_FILE_CACHE_COUNT = 12;      // 最多缓存 12 个音频文件（约 200MB 量级）

interface CacheEntry {
  resolvedUrl: string;
  timestamp: number;
}

interface TextCacheEntry {
  content: string;
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

export class ChapterCacheService {
  private static instance: ChapterCacheService | null = null;
  private audioCache: Map<string, CacheEntry> = new Map();
  private textCache: Map<string, TextCacheEntry> = new Map();
  /** 章节 → 已下载到本地的音频文件 */
  private fileCache: Map<string, FileCacheEntry> = new Map();
  /** 章节 → 解析出的真实时长（秒）。来自缓存音频文件的元数据 */
  private durationCache: Map<string, number> = new Map();
  private pendingTasks: Set<string> = new Set();
  private runningCount: number = 0;
  private queue: Array<() => Promise<void>> = [];
  private fileRunningCount: number = 0;
  private fileQueue: Array<() => Promise<void>> = [];
  private appContext: common.Context | null = null;

  static getInstance(): ChapterCacheService {
    if (!ChapterCacheService.instance) {
      ChapterCacheService.instance = new ChapterCacheService();
    }
    return ChapterCacheService.instance;
  }

  setPreloadCount(forward: number, backward: number = 0): void {
    PRE_DOWNLOAD_FORWARD = forward;
    PRE_DOWNLOAD_BACKWARD = backward;
  }

  getPreloadForward(): number {
    return PRE_DOWNLOAD_FORWARD;
  }

  isChapterCached(chapterId: string): boolean {
    return this.audioCache.has(chapterId) || this.fileCache.has(chapterId) || this.textCache.has(chapterId);
  }

  /** 已解析的章节真实时长（秒）。仅在音频文件下载完成后才有值。 */
  getChapterDuration(chapterId: string): number {
    return this.durationCache.get(chapterId) ?? 0;
  }

  clearAllCache(): void {
    this.audioCache.clear();
    this.textCache.clear();
    this.durationCache.clear();
    for (const entry of this.fileCache.values()) {
      this.deleteFileSafely(entry.filePath);
    }
    this.fileCache.clear();
  }

  setContext(ctx: common.Context): void {
    this.appContext = ctx;
  }

  getAudioUrl(chapterId: string): string | null {
    const entry = this.audioCache.get(chapterId);
    return entry ? entry.resolvedUrl : null;
  }

  /** 章节是否已经有完整音频文件落盘，命中后 AudioService 直接 file:// 播放 */
  getAudioFilePath(chapterId: string, pageUrl: string): string | null {
    const entry = this.fileCache.get(chapterId);
    if (!entry) return null;
    // pageUrl 不一致说明缓存对应的章节不同（书源 toc 重排过），失效
    if (entry.pageUrl !== pageUrl) return null;
    return entry.filePath;
  }

  getTextContent(chapterId: string): string | null {
    const entry = this.textCache.get(chapterId);
    return entry ? entry.content : null;
  }

  preloadAudioChapters(book: Book, currentIndex: number): void {
    if (!book.sourceUrl) return;
    const start = Math.max(0, currentIndex - PRE_DOWNLOAD_BACKWARD);
    const end = Math.min(book.chapters.length - 1, currentIndex + PRE_DOWNLOAD_FORWARD);
    for (let i = start; i <= end; i++) {
      if (i === currentIndex) continue;
      const ch = book.chapters[i];
      if (ch.source.type !== 'url') continue;
      if (this.fileCache.has(ch.id)) continue;
      // 1) URL 解析
      if (!this.audioCache.has(ch.id) && !this.pendingTasks.has(`audio_${ch.id}`)) {
        this.enqueue(() => this.resolveAudioAndDownload(book, ch));
      } else if (this.audioCache.has(ch.id) && !this.pendingTasks.has(`file_${ch.id}`)) {
        // 2) URL 已有，仅下载文件
        const cached = this.audioCache.get(ch.id);
        if (cached) {
          this.enqueueFile(() => this.downloadFile(book, ch, cached.resolvedUrl));
        }
      }
    }
  }

  preloadTextChapters(book: Book, currentIndex: number): void {
    if (!book.sourceUrl) return;
    const start = Math.max(0, currentIndex - PRE_DOWNLOAD_BACKWARD);
    const end = Math.min(book.chapters.length - 1, currentIndex + PRE_DOWNLOAD_FORWARD);
    for (let i = start; i <= end; i++) {
      if (i === currentIndex) continue;
      const ch = book.chapters[i];
      if (ch.source.type === 'file') continue;
      if (this.textCache.has(ch.id) || this.pendingTasks.has(`text_${ch.id}`)) continue;
      this.enqueue(() => this.resolveText(book, ch));
    }
  }

  clearBook(bookId: string): void {
    const prefix = bookId + '-c';
    for (const key of this.audioCache.keys()) {
      if (key.startsWith(prefix)) this.audioCache.delete(key);
    }
    for (const key of this.textCache.keys()) {
      if (key.startsWith(prefix)) this.textCache.delete(key);
    }
    for (const key of this.durationCache.keys()) {
      if (key.startsWith(prefix)) this.durationCache.delete(key);
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
    this.textCache.delete(chapterId);
    this.durationCache.delete(chapterId);
    const entry = this.fileCache.get(chapterId);
    if (entry) this.deleteFileSafely(entry.filePath);
    this.fileCache.delete(chapterId);
  }

  /** 主动给某个章节下载文件（AudioService 在 playChapter 时调用，让当前章节也能落盘） */
  ensureFileCached(book: Book, chapter: Chapter, resolvedUrl: string): void {
    if (!resolvedUrl || !resolvedUrl.startsWith('http')) return;
    if (this.fileCache.has(chapter.id)) return;
    if (this.pendingTasks.has(`file_${chapter.id}`)) return;
    this.enqueueFile(() => this.downloadFile(book, chapter, resolvedUrl));
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
    const taskKey = `audio_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!source) return;
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const audioUrl = await BookSourceService.getAudioUrl(source, pageUrl);
      if (audioUrl && audioUrl !== pageUrl) {
        this.evictUrlCache();
        this.audioCache.set(chapter.id, { resolvedUrl: audioUrl, timestamp: Date.now() });
        // URL 拿到后顺手把文件也下了
        this.enqueueFile(() => this.downloadFile(book, chapter, audioUrl));
      }
    } catch (_e) {
    } finally {
      this.pendingTasks.delete(taskKey);
    }
  }

  private async downloadFile(book: Book, chapter: Chapter, audioUrl: string): Promise<void> {
    if (!this.appContext) return;
    if (!audioUrl || !audioUrl.startsWith('http')) return;
    if (this.fileCache.has(chapter.id)) return;
    const taskKey = `file_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    let httpClient: http.HttpRequest | null = null;
    let f: fileIo.File | null = null;
    try {
      const cacheDir = this.appContext.cacheDir;
      const fileName = `chap_${this.hash(book.id + '|' + chapter.id)}.mp3`;
      const filePath = `${cacheDir}/${fileName}`;
      // 已存在直接复用（避免重复下）
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.size > 1024) {
          this.fileCache.set(chapter.id, {
            filePath,
            pageUrl: chapter.originSourceValue || chapter.source.value,
            bytes: stat.size,
            timestamp: Date.now(),
          });
          this.evictFileCache();
          this.extractDuration(chapter, filePath);
          return;
        }
      } catch (_e) { /* 不存在，下载 */ }

      httpClient = http.createHttp();
      const resp = await httpClient.request(audioUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (resp.responseCode !== 200 || !resp.result) {
        hilog.warn(DOMAIN, TAG, 'download failed [%{public}d] %{public}s', resp.responseCode, chapter.title);
        return;
      }
      const buf = resp.result as ArrayBuffer;
      f = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, buf);
      await fileIo.close(f);
      f = null;
      this.fileCache.set(chapter.id, {
        filePath,
        pageUrl: chapter.originSourceValue || chapter.source.value,
        bytes: buf.byteLength,
        timestamp: Date.now(),
      });
      this.evictFileCache();
      this.extractDuration(chapter, filePath);
    } catch (err) {
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

  private async resolveText(book: Book, chapter: Chapter): Promise<void> {
    const taskKey = `text_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!source) return;
      const text = await BookSourceService.getTextContent(source, chapter.originSourceValue || chapter.source.value);
      if (text) {
        this.evictIfNeeded(this.textCache);
        this.textCache.set(chapter.id, { content: text, timestamp: Date.now() });
      }
    } catch (_e) {
    } finally {
      this.pendingTasks.delete(taskKey);
    }
  }

  private async findSource(sourceUrl: string): Promise<BookSource | null> {
    const sources = await SourceDataService.getSources();
    return sources.find((s) => s.bookSourceUrl === sourceUrl) || null;
  }

  private evictUrlCache(): void {
    if (this.audioCache.size < MAX_URL_CACHE_SIZE) return;
    const first = this.audioCache.keys().next();
    if (!first.done) this.audioCache.delete(first.value);
  }

  private evictIfNeeded<T>(cache: Map<string, T>): void {
    if (cache.size < MAX_URL_CACHE_SIZE) return;
    const first = cache.keys().next();
    if (!first.done) cache.delete(first.value);
  }

  /** 文件缓存满了，从最旧的开始删 */
  private evictFileCache(): void {
    while (this.fileCache.size > MAX_FILE_CACHE_COUNT) {
      const first = this.fileCache.keys().next();
      if (first.done) return;
      const id = first.value as string;
      const entry = this.fileCache.get(id);
      if (entry) this.deleteFileSafely(entry.filePath);
      this.fileCache.delete(id);
    }
  }

  private deleteFileSafely(path: string): void {
    try {
      fileIo.unlink(path).catch(() => { /* ignore */ });
    } catch (_e) { /* ignore */ }
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
