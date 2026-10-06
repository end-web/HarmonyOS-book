import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Book, Chapter } from '../model/Book';
import { TextReadingPosition } from '../model/TextReading';
import { DiagnosticLogService } from './DiagnosticLogService';

export class SessionLocation {
  bookId: string = '';
  chapterId: string = '';
  chapterTitle: string = '';
  chapterUrl: string = '';
  chapterIndex: number = 0;
  position: number = 0;
  total: number = 0;
  domPos: string = '';
  pageOffset: number = 0;

  static audio(book: Book, chapter: Chapter, position: number, total: number): SessionLocation {
    const value = new SessionLocation();
    value.bookId = book.id;
    value.chapterId = chapter.id;
    value.chapterTitle = chapter.title;
    value.chapterUrl = chapter.originSourceValue || chapter.source.value;
    value.chapterIndex = Math.max(0, book.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id));
    value.position = Math.max(0, position);
    value.total = Math.max(0, total);
    return value;
  }

  static text(book: Book, position: TextReadingPosition): SessionLocation {
    const chapter = book.chapters[position.resourceIndex];
    const value = chapter ? SessionLocation.audio(book, chapter, position.charOffset, 0) : new SessionLocation();
    value.bookId = book.id;
    value.chapterIndex = position.resourceIndex;
    value.chapterTitle = position.chapterTitle;
    value.position = position.charOffset;
    value.domPos = position.domPos;
    value.pageOffset = position.pageOffset;
    return value;
  }
}

export class ReadingSession {
  id: string = '';
  sessionId: string = '';
  kind: string = '';
  startedAt: number = 0;
  endedAt: number = 0;
  start: SessionLocation = new SessionLocation();
  end: SessionLocation = new SessionLocation();
}

/** 独立于最新进度的有界会话记录。跨章保留分段，跳回不覆盖过去会话。 */
export class ReadingSessionService {
  private static store: preferences.Preferences | null = null;
  private static ready: Promise<void> = Promise.resolve();
  private static chain: Promise<void> = Promise.resolve();
  private static active: Map<string, ReadingSession> = new Map();
  private static savedAt: Map<string, number> = new Map();
  private static sequence: number = 0;

  static init(context: common.BaseContext): void {
    ReadingSessionService.ready = preferences.getPreferences(context, { name: 'reading_sessions_v1' })
      .then((store: preferences.Preferences): void => { ReadingSessionService.store = store; })
      .catch((error: Error): void => { DiagnosticLogService.info('session.init.failed', error.message); });
  }

  static checkpoint(kind: string, location: SessionLocation, running: boolean): void {
    let entry = ReadingSessionService.active.get(kind);
    if (!entry && !running) return;
    const now = Date.now();
    if (!entry || entry.end.bookId !== location.bookId || entry.end.chapterId !== location.chapterId ||
      entry.end.chapterIndex !== location.chapterIndex) {
      const sessionId = entry?.end.bookId === location.bookId ? entry.sessionId : '';
      if (entry) ReadingSessionService.persist(entry);
      entry = new ReadingSession();
      entry.id = `${now}_${++ReadingSessionService.sequence}`;
      entry.sessionId = sessionId || entry.id;
      entry.kind = kind;
      entry.startedAt = now;
      entry.start = location;
      ReadingSessionService.active.set(kind, entry);
      ReadingSessionService.savedAt.delete(kind);
    }
    entry.endedAt = Math.max(entry.startedAt, now);
    entry.end = location;
    if (!running || now - (ReadingSessionService.savedAt.get(kind) ?? 0) >= 5000) {
      ReadingSessionService.persist(entry);
      ReadingSessionService.savedAt.set(kind, now);
    }
    if (!running) ReadingSessionService.active.delete(kind);
  }

  static end(kind: string): void {
    const entry = ReadingSessionService.active.get(kind);
    if (!entry) return;
    entry.endedAt = Math.max(entry.startedAt, Date.now());
    ReadingSessionService.persist(entry);
    ReadingSessionService.active.delete(kind);
  }

  private static persist(entry: ReadingSession): void {
    const raw = JSON.stringify(entry);
    const id = entry.id;
    ReadingSessionService.chain = ReadingSessionService.chain.then(async (): Promise<void> => {
      await ReadingSessionService.ready;
      const store = ReadingSessionService.store;
      if (!store) throw new Error('Session store unavailable');
      await store.put(id, raw);
      const keys = Object.keys(await store.getAll()).sort();
      for (let index = 0; index < keys.length - 2000; index++) await store.delete(keys[index]);
      await store.flush();
    }).catch((error: Error): void => { DiagnosticLogService.info('session.save.failed', error.message); });
  }

  static async list(bookIds: string[]): Promise<ReadingSession[]> {
    for (const entry of ReadingSessionService.active.values()) ReadingSessionService.persist(entry);
    await ReadingSessionService.chain;
    await ReadingSessionService.ready;
    const store = ReadingSessionService.store;
    if (!store) throw new Error('Session store unavailable');
    const result: ReadingSession[] = [];
    for (const key of Object.keys(await store.getAll())) {
      const raw = store.getSync(key, '');
      if (typeof raw !== 'string') continue;
      try {
        const item: ReadingSession = JSON.parse(raw);
        if (item && item.start && item.end && typeof item.id === 'string' &&
          ['audio', 'reading', 'tts'].includes(item.kind) && bookIds.includes(item.end.bookId) &&
          Number.isFinite(item.startedAt) && Number.isFinite(item.endedAt) &&
          Number.isFinite(item.start.position) && Number.isFinite(item.end.position)) result.push(item);
      } catch (_error) { /* 单条损坏不覆盖其他会话。 */ }
    }
    return result.sort((left: ReadingSession, right: ReadingSession): number => right.startedAt - left.startedAt);
  }
}
