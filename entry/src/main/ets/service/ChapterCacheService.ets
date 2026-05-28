import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { BookSourceService } from './BookSourceService';
import { PreferenceService } from './PreferenceService';

const DOMAIN = 0x0001;
const TAG = 'ChapterCache';

const PRE_DOWNLOAD_FORWARD = 10;
const PRE_DOWNLOAD_BACKWARD = 3;
const MAX_CONCURRENT = 2;
const MAX_CACHE_SIZE = 50;

interface CacheEntry {
  resolvedUrl: string;
  timestamp: number;
}

interface TextCacheEntry {
  content: string;
  timestamp: number;
}

export class ChapterCacheService {
  private static instance: ChapterCacheService | null = null;
  private audioCache: Map<string, CacheEntry> = new Map();
  private textCache: Map<string, TextCacheEntry> = new Map();
  private pendingTasks: Set<string> = new Set();
  private runningCount: number = 0;
  private queue: Array<() => Promise<void>> = [];

  static getInstance(): ChapterCacheService {
    if (!ChapterCacheService.instance) {
      ChapterCacheService.instance = new ChapterCacheService();
    }
    return ChapterCacheService.instance;
  }

  getAudioUrl(chapterId: string): string | null {
    const entry = this.audioCache.get(chapterId);
    return entry ? entry.resolvedUrl : null;
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
      if (this.audioCache.has(ch.id) || this.pendingTasks.has(`audio_${ch.id}`)) continue;
      this.enqueue(() => this.resolveAudio(book, ch));
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
  }

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

  private async resolveAudio(book: Book, chapter: Chapter): Promise<void> {
    const taskKey = `audio_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!source) return;
      const audioUrl = await BookSourceService.getAudioUrl(source, chapter.source.value);
      if (audioUrl && audioUrl !== chapter.source.value) {
        this.evictIfNeeded(this.audioCache);
        this.audioCache.set(chapter.id, { resolvedUrl: audioUrl, timestamp: Date.now() });
        hilog.info(DOMAIN, TAG, 'preloaded audio: %{public}s', chapter.title);
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'preload audio failed: %{public}s', chapter.title);
    } finally {
      this.pendingTasks.delete(taskKey);
    }
  }

  private async resolveText(book: Book, chapter: Chapter): Promise<void> {
    const taskKey = `text_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!source) return;
      const text = await BookSourceService.getTextContent(source, chapter.source.value);
      if (text) {
        this.evictIfNeeded(this.textCache);
        this.textCache.set(chapter.id, { content: text, timestamp: Date.now() });
        hilog.info(DOMAIN, TAG, 'preloaded text: %{public}s', chapter.title);
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'preload text failed: %{public}s', chapter.title);
    } finally {
      this.pendingTasks.delete(taskKey);
    }
  }

  private async findSource(sourceUrl: string): Promise<BookSource | null> {
    const json = await PreferenceService.getBookSources();
    const sources = JSON.parse(json) as Object as BookSource[];
    return sources.find((s) => s.bookSourceUrl === sourceUrl) || null;
  }

  private evictIfNeeded<T>(cache: Map<string, T>): void {
    if (cache.size < MAX_CACHE_SIZE) return;
    const first = cache.keys().next();
    if (!first.done) cache.delete(first.value);
  }
}
