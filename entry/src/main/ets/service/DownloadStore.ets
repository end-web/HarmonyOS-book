import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book, Chapter } from '../model/Book';
import { DownloadFailureCode } from './DownloadPolicy';

export type DownloadBookStatus = 'idle' | 'queued' | 'downloading' | 'paused' | 'completed' | 'failed';
export type DownloadChapterStatus = 'pending' | 'resolving' | 'downloading' | 'completed' | 'failed' | 'deleted';

export interface DownloadChapterRecord {
  chapterId: string;
  chapterIndex: number;
  title: string;
  pageUrl: string;
  audioUrl: string;
  filePath: string;
  bytes: number;
  status: DownloadChapterStatus;
  failureReason: string;
  failureCode?: DownloadFailureCode;
  updatedAt: number;
}

export interface DownloadBookRecord {
  bookId: string;
  title: string;
  author: string;
  cover: string;
  sourceUrl: string;
  bookUrl: string;
  contentType: string;
  chapterCount: number;
  downloadedCount: number;
  failedCount: number;
  totalBytes: number;
  status: DownloadBookStatus;
  updatedAt: number;
  chapters: DownloadChapterRecord[];
}

interface DownloadStoreRead {
  ok: boolean;
  existed: boolean;
  json: string;
}

const DOWNLOAD_ROOT_DIR = 'downloads';
const DOWNLOAD_AUDIO_DIR = 'audio';
const DOWNLOAD_STORE_FILE = 'download_store.json';

export class DownloadStore {
  private static ctx: common.Context | null = null;
  private static records: DownloadBookRecord[] | null = null;
  private static writeChain: Promise<void> = Promise.resolve();
  private static persistUnsafe: boolean = false;

  static async init(ctx: common.Context): Promise<void> {
    DownloadStore.ctx = ctx;
    await DownloadStore.ensureBaseDirs();
    await DownloadStore.ensureLoaded();
    await DownloadStore.normalizeInterruptedTasks();
  }

  static setContext(ctx: common.Context): void {
    DownloadStore.ctx = ctx;
  }

  static getDownloadRootPath(): string | null {
    return DownloadStore.ctx ? `${DownloadStore.ctx.filesDir}/${DOWNLOAD_ROOT_DIR}` : null;
  }

  static getAudioRootPath(): string | null {
    const root = DownloadStore.getDownloadRootPath();
    return root ? `${root}/${DOWNLOAD_AUDIO_DIR}` : null;
  }

  static getBookDir(bookId: string): string | null {
    const root = DownloadStore.getAudioRootPath();
    if (!root || !bookId) return null;
    return `${root}/${DownloadStore.hash(bookId)}`;
  }

  static getAudioFilePath(bookId: string, pageUrl: string): string | null {
    const dir = DownloadStore.getBookDir(bookId);
    if (!dir || !pageUrl) return null;
    return `${dir}/${DownloadStore.hash(`${bookId}|${pageUrl}`)}.mp3`;
  }

  static async ensureBookDir(bookId: string): Promise<string | null> {
    await DownloadStore.ensureBaseDirs();
    const dir = DownloadStore.getBookDir(bookId);
    if (!dir) return null;
    await DownloadStore.ensureDir(dir);
    return dir;
  }

  static async getBooks(): Promise<DownloadBookRecord[]> {
    await DownloadStore.ensureLoaded();
    return DownloadStore.records ?? [];
  }

  static getBooksSync(): DownloadBookRecord[] {
    return DownloadStore.records ?? [];
  }

  static async getBook(bookId: string): Promise<DownloadBookRecord | null> {
    await DownloadStore.ensureLoaded();
    return DownloadStore.getBookSync(bookId);
  }

  static getBookSync(bookId: string): DownloadBookRecord | null {
    const list = DownloadStore.records ?? [];
    return list.find((item: DownloadBookRecord) => item.bookId === bookId) ?? null;
  }

  static getChapterSync(bookId: string, chapter: Chapter): DownloadChapterRecord | null {
    const book = DownloadStore.getBookSync(bookId);
    if (!book) return null;
    return DownloadStore.findChapterRecord(book, chapter);
  }

  static findChapterRecord(book: DownloadBookRecord, chapter: Chapter): DownloadChapterRecord | null {
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (pageUrl) {
      const byPageUrl = book.chapters.find((item: DownloadChapterRecord) => item.pageUrl === pageUrl);
      if (byPageUrl) return byPageUrl;
    }
    return book.chapters.find((item: DownloadChapterRecord) => item.chapterId === chapter.id) ?? null;
  }

  static async ensureBookRecord(book: Book): Promise<DownloadBookRecord> {
    await DownloadStore.ensureLoaded();
    const record = DownloadStore.ensureBookRecordInMemory(book);
    DownloadStore.recalculateBook(record);
    await DownloadStore.saveAll();
    return record;
  }

  static async prepareChapters(book: Book, chapters: Chapter[], canApply?: () => boolean):
    Promise<DownloadChapterRecord[]> {
    await DownloadStore.ensureLoaded();
    if (canApply && !canApply()) return [];
    const bookRecord = DownloadStore.ensureBookRecordInMemory(book);
    const prepared: DownloadChapterRecord[] = [];
    for (const chapter of chapters) {
      prepared.push(DownloadStore.upsertChapterInMemory(bookRecord, chapter, 'pending'));
    }
    DownloadStore.recalculateBook(bookRecord);
    if (prepared.length > 0) bookRecord.status = 'queued';
    bookRecord.updatedAt = Date.now();
    await DownloadStore.saveAll();
    return prepared;
  }

  private static ensureBookRecordInMemory(book: Book): DownloadBookRecord {
    const list = DownloadStore.records ?? [];
    let record = list.find((item: DownloadBookRecord) => item.bookId === book.id);
    if (!record) {
      record = {
        bookId: book.id,
        title: book.title,
        author: book.author,
        cover: book.cover,
        sourceUrl: book.sourceUrl,
        bookUrl: book.bookUrl,
        contentType: book.contentType ?? '',
        chapterCount: book.chapters.length || book.chapterCount || 0,
        downloadedCount: 0,
        failedCount: 0,
        totalBytes: 0,
        status: 'idle',
        updatedAt: Date.now(),
        chapters: []
      };
      list.push(record);
      DownloadStore.records = list;
    } else {
      record.title = book.title || record.title;
      record.author = book.author || record.author;
      record.cover = book.cover || record.cover;
      record.sourceUrl = book.sourceUrl || record.sourceUrl;
      record.bookUrl = book.bookUrl || record.bookUrl;
      record.contentType = book.contentType ?? record.contentType;
      record.chapterCount = book.chapters.length || book.chapterCount || record.chapterCount;
      record.updatedAt = Date.now();
    }
    return record;
  }

  static async upsertChapter(book: Book, chapter: Chapter, status: DownloadChapterStatus,
    audioUrl: string = '', filePath: string = '', bytes: number = 0, failureReason: string = '',
    canApply?: () => boolean, failureCode: DownloadFailureCode = 'unknown'): Promise<DownloadChapterRecord | null> {
    await DownloadStore.ensureLoaded();
    if (canApply && !canApply()) return null;
    const bookRecord = DownloadStore.ensureBookRecordInMemory(book);
    const record = DownloadStore.upsertChapterInMemory(bookRecord, chapter, status,
      audioUrl, filePath, bytes, failureReason, failureCode);
    bookRecord.updatedAt = Date.now();
    DownloadStore.recalculateBook(bookRecord);
    await DownloadStore.saveAll();
    return record;
  }

  private static upsertChapterInMemory(bookRecord: DownloadBookRecord, chapter: Chapter,
    status: DownloadChapterStatus, audioUrl: string = '', filePath: string = '', bytes: number = 0,
    failureReason: string = '', failureCode: DownloadFailureCode = 'unknown'): DownloadChapterRecord {
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    let record = DownloadStore.findChapterRecord(bookRecord, chapter);
    if (!record) {
      record = {
        chapterId: chapter.id,
        chapterIndex: chapter.index,
        title: chapter.title,
        pageUrl,
        audioUrl,
        filePath,
        bytes,
        status,
        failureReason,
        failureCode: status === 'failed' ? failureCode : undefined,
        updatedAt: Date.now()
      };
      bookRecord.chapters.push(record);
    } else {
      record.chapterId = chapter.id;
      record.chapterIndex = chapter.index;
      record.title = chapter.title;
      record.pageUrl = pageUrl || record.pageUrl;
      record.audioUrl = audioUrl || record.audioUrl;
      record.filePath = filePath || record.filePath;
      record.bytes = bytes > 0 ? bytes : record.bytes;
      record.status = status;
      record.failureReason = failureReason;
      record.failureCode = status === 'failed' ? failureCode : undefined;
      record.updatedAt = Date.now();
    }
    return record;
  }

  static async saveBook(record: DownloadBookRecord): Promise<void> {
    await DownloadStore.ensureLoaded();
    DownloadStore.recalculateBook(record);
    record.updatedAt = Date.now();
    await DownloadStore.saveAll();
  }

  static async removeBook(bookId: string): Promise<void> {
    await DownloadStore.ensureLoaded();
    const list = DownloadStore.records ?? [];
    DownloadStore.records = list.filter((item: DownloadBookRecord) => item.bookId !== bookId);
    await DownloadStore.saveAll();
  }

  static async clearAll(): Promise<void> {
    DownloadStore.records = [];
    DownloadStore.persistUnsafe = false;
    await DownloadStore.saveAll();
  }

  static async deleteFileSafely(path: string): Promise<void> {
    if (!path) return;
    const paths = [path, `${path}.part`];
    for (const current of paths) {
      try {
        await fileIo.unlink(current);
      } catch (_e) {
        // ignore
      }
    }
  }

  static isUsableFile(path: string): boolean {
    if (!path) return false;
    try {
      return fileIo.statSync(path).size > 1024;
    } catch (_e) {
      return false;
    }
  }

  static isExpectedFile(path: string, expectedBytes: number): boolean {
    if (!path) return false;
    try {
      const size = fileIo.statSync(path).size;
      return size > 1024 && (expectedBytes <= 0 || size === expectedBytes);
    } catch (_e) {
      return false;
    }
  }

  static hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }

  private static async normalizeInterruptedTasks(): Promise<void> {
    await DownloadStore.ensureLoaded();
    let changed = false;
    const list = DownloadStore.records ?? [];
    for (const book of list) {
      const shouldResume = book.status === 'downloading' || book.status === 'queued';
      for (const chapter of book.chapters) {
        if (chapter.status === 'completed' && !DownloadStore.isCompletedFileValid(chapter)) {
          await DownloadStore.deleteFileSafely(chapter.filePath);
          chapter.status = 'failed';
          chapter.failureCode = 'invalid_response';
          chapter.failureReason = '已下载文件缺失或不完整';
          chapter.bytes = 0;
          changed = true;
        }
        if (chapter.status === 'resolving' || chapter.status === 'downloading') {
          chapter.status = 'pending';
          changed = true;
        }
      }
      DownloadStore.recalculateBook(book);
      if (shouldResume && book.chapters.some((chapter: DownloadChapterRecord) => chapter.status === 'pending')) {
        if (book.status !== 'queued') changed = true;
        book.status = 'queued';
      }
    }
    if (changed) await DownloadStore.saveAll();
  }

  private static isCompletedFileValid(chapter: DownloadChapterRecord): boolean {
    return DownloadStore.isExpectedFile(chapter.filePath, chapter.bytes);
  }

  private static recalculateBook(book: DownloadBookRecord): void {
    let downloaded = 0;
    let failed = 0;
    let totalBytes = 0;
    let active = 0;
    for (const chapter of book.chapters) {
      if (chapter.status === 'completed') downloaded++;
      if (chapter.status === 'failed') failed++;
      if (chapter.status === 'pending' || chapter.status === 'resolving' || chapter.status === 'downloading') active++;
      if (chapter.status === 'completed') totalBytes += chapter.bytes;
    }
    book.downloadedCount = downloaded;
    book.failedCount = failed;
    book.totalBytes = totalBytes;
    if (book.status !== 'paused') {
      if (active > 0) {
        book.status = 'downloading';
      } else if (failed > 0) {
        book.status = downloaded > 0 ? 'failed' : 'failed';
      } else if (downloaded > 0 && downloaded >= book.chapters.length) {
        book.status = 'completed';
      } else if (downloaded > 0) {
        book.status = 'idle';
      } else {
        book.status = 'idle';
      }
    }
  }

  private static storePath(): string | null {
    const root = DownloadStore.getDownloadRootPath();
    return root ? `${root}/${DOWNLOAD_STORE_FILE}` : null;
  }

  private static async ensureLoaded(): Promise<void> {
    if (DownloadStore.records !== null) return;
    const read = await DownloadStore.readFileSafe(DownloadStore.storePath());
    if (!read.ok) {
      DownloadStore.persistUnsafe = true;
      DownloadStore.records = [];
      return;
    }
    if (!read.existed || !read.json) {
      DownloadStore.records = [];
      return;
    }
    try {
      const parsed: Object = JSON.parse(read.json) as Object;
      DownloadStore.records = Array.isArray(parsed) ? parsed as DownloadBookRecord[] : [];
    } catch (_e) {
      DownloadStore.persistUnsafe = true;
      DownloadStore.records = [];
    }
  }

  private static async readFileSafe(path: string | null): Promise<DownloadStoreRead> {
    if (!path) return { ok: true, existed: false, json: '' };
    let existed = false;
    try {
      existed = await fileIo.access(path);
    } catch (_e) {
      existed = false;
    }
    if (!existed) return { ok: true, existed: false, json: '' };
    try {
      return { ok: true, existed: true, json: await fileIo.readText(path) };
    } catch (_e) {
      return { ok: false, existed: true, json: '' };
    }
  }

  private static saveAll(): Promise<void> {
    if (DownloadStore.persistUnsafe) return Promise.reject(new Error('下载记录文件不可安全写入'));
    const path = DownloadStore.storePath();
    const json = JSON.stringify(DownloadStore.records ?? []);
    const task = DownloadStore.writeChain.then(() => DownloadStore.atomicWrite(path, json));
    DownloadStore.writeChain = task.catch((_e: Error): void => {});
    return task;
  }

  private static async atomicWrite(finalPath: string | null, json: string): Promise<void> {
    if (!finalPath) return;
    await DownloadStore.ensureBaseDirs();
    const tmp = finalPath + '.tmp';
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(tmp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, json);
      try { await fileIo.fsync(f.fd); } catch (_e) { /* ignore */ }
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
    await fileIo.moveFile(tmp, finalPath);
  }

  private static async ensureBaseDirs(): Promise<void> {
    const root = DownloadStore.getDownloadRootPath();
    const audio = DownloadStore.getAudioRootPath();
    if (root) await DownloadStore.ensureDir(root);
    if (audio) await DownloadStore.ensureDir(audio);
  }

  private static async ensureDir(dir: string): Promise<void> {
    try {
      const ok = await fileIo.access(dir);
      if (ok) return;
    } catch (_e) {
      // mkdir below
    }
    try {
      await fileIo.mkdir(dir);
    } catch (_e) {
      // already exists or unavailable; later file operations will surface real errors
    }
  }
}
