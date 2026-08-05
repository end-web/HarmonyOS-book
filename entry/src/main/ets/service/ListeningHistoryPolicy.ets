import { BookIdentity } from '../utils/BookIdentity';

export class ListeningRecordCandidate {
  bookId: string = '';
  sourceUrl: string = '';
  bookUrl: string = '';
  hasBook: boolean = false;
  title: string = '';
  author: string = '';
  cover: string = '';
  listenSeconds: number = 0;
  statsUpdatedAt: number = 0;
  historyChapterId: string = '';
  historyChapterTitle: string = '';
  historyProgressMs: number = 0;
  historyDurationMs: number = 0;
  historyUpdatedAt: number = 0;
  progressChapterId: string = '';
  progressChapterTitle: string = '';
  progressPositionMs: number = 0;
  progressDurationMs: number = 0;
  progressChapterIndex: number = -1;
  progressUpdatedAt: number = 0;

  constructor(bookId: string) {
    this.bookId = bookId;
  }

  setBook(sourceUrl: string, bookUrl: string, title: string, author: string, cover: string): void {
    this.sourceUrl = sourceUrl;
    this.bookUrl = bookUrl;
    this.hasBook = true;
    if (title) this.title = title;
    if (author) this.author = author;
    if (cover) this.cover = cover;
  }

  addStats(listenSeconds: number, updatedAt: number, title: string, author: string, cover: string,
    sourceUrl?: string, bookUrl?: string): void {
    this.listenSeconds += Math.max(0, listenSeconds);
    if (updatedAt >= this.statsUpdatedAt) {
      this.statsUpdatedAt = updatedAt;
      if (title) this.title = title;
      if (author) this.author = author;
      if (cover) this.cover = cover;
      if (sourceUrl) this.sourceUrl = sourceUrl;
      if (bookUrl) this.bookUrl = bookUrl;
    }
  }

  setHistory(chapterId: string, chapterTitle: string, progressMs: number, durationMs: number,
    updatedAt: number, sourceUrl?: string, bookUrl?: string): void {
    this.historyChapterId = chapterId;
    this.historyChapterTitle = chapterTitle;
    this.historyProgressMs = progressMs;
    this.historyDurationMs = durationMs;
    this.historyUpdatedAt = updatedAt;
    if (sourceUrl) this.sourceUrl = sourceUrl;
    if (bookUrl) this.bookUrl = bookUrl;
  }

  setProgress(chapterId: string, chapterTitle: string, positionMs: number, durationMs: number,
    chapterIndex: number, updatedAt: number, sourceUrl?: string, bookUrl?: string): void {
    this.progressChapterId = chapterId;
    this.progressChapterTitle = chapterTitle;
    this.progressPositionMs = positionMs;
    this.progressDurationMs = durationMs;
    this.progressChapterIndex = chapterIndex;
    this.progressUpdatedAt = updatedAt;
    if (sourceUrl) this.sourceUrl = sourceUrl;
    if (bookUrl) this.bookUrl = bookUrl;
  }
}

export class MergedListeningRecord {
  bookId: string = '';
  aliasBookIds: string[] = [];
  sourceBookId: string = '';
  title: string = '';
  author: string = '';
  cover: string = '';
  chapterId: string = '';
  chapterTitle: string = '';
  progressMs: number = 0;
  durationMs: number = 0;
  chapterIndex: number = -1;
  listenSeconds: number = 0;
  updatedAt: number = 0;
}

export class ListeningHistoryPolicy {
  static merge(candidates: ListeningRecordCandidate[]): MergedListeningRecord[] {
    const ordered = candidates.slice().sort((left: ListeningRecordCandidate,
      right: ListeningRecordCandidate): number => {
      if (left.hasBook !== right.hasBook) return left.hasBook ? -1 : 1;
      return ListeningHistoryPolicy.candidateUpdatedAt(right) - ListeningHistoryPolicy.candidateUpdatedAt(left);
    });
    const groups: ListeningRecordCandidate[][] = [];
    for (const candidate of ordered) {
      let matchedGroup = -1;
      let matchCount = 0;
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        if (ListeningHistoryPolicy.matchesGroup(candidate, groups[groupIndex])) {
          matchedGroup = groupIndex;
          matchCount++;
        }
      }
      if (matchCount === 1) {
        groups[matchedGroup].push(candidate);
      } else {
        const group: ListeningRecordCandidate[] = [candidate];
        groups.push(group);
      }
    }

    const merged: MergedListeningRecord[] = [];
    for (const group of groups) {
      merged.push(ListeningHistoryPolicy.mergeGroup(group));
    }
    return merged.sort((left: MergedListeningRecord, right: MergedListeningRecord): number =>
      right.updatedAt - left.updatedAt);
  }

  private static matchesGroup(candidate: ListeningRecordCandidate, group: ListeningRecordCandidate[]): boolean {
    for (const member of group) {
      if (BookIdentity.isSameBook(
        candidate.bookId, candidate.sourceUrl, candidate.bookUrl,
        member.bookId, member.sourceUrl, member.bookUrl)) return true;
    }
    return false;
  }

  private static mergeGroup(group: ListeningRecordCandidate[]): MergedListeningRecord {
    const merged = new MergedListeningRecord();
    let representative = group[0];
    for (const candidate of group) {
      if (candidate.hasBook && (!representative.hasBook ||
        ListeningHistoryPolicy.candidateUpdatedAt(candidate) >
          ListeningHistoryPolicy.candidateUpdatedAt(representative))) {
        representative = candidate;
      } else if (candidate.hasBook === representative.hasBook &&
        ListeningHistoryPolicy.candidateUpdatedAt(candidate) >
          ListeningHistoryPolicy.candidateUpdatedAt(representative)) {
        representative = candidate;
      }
    }
    merged.bookId = representative.bookId;
    merged.sourceBookId = representative.bookId;

    const metadataCandidates = group.slice().sort((left: ListeningRecordCandidate,
      right: ListeningRecordCandidate): number => {
      if (left.hasBook !== right.hasBook) return left.hasBook ? -1 : 1;
      return ListeningHistoryPolicy.candidateUpdatedAt(right) - ListeningHistoryPolicy.candidateUpdatedAt(left);
    });
    for (const candidate of metadataCandidates) {
      if (!merged.title && candidate.title) merged.title = candidate.title;
      if (!merged.author && candidate.author) merged.author = candidate.author;
      if (!merged.cover && candidate.cover) merged.cover = candidate.cover;
    }

    let latestPlaybackAt = -1;
    for (const candidate of group) {
      if (!merged.aliasBookIds.includes(candidate.bookId)) merged.aliasBookIds.push(candidate.bookId);
      merged.listenSeconds += candidate.listenSeconds;
      merged.updatedAt = Math.max(merged.updatedAt, candidate.statsUpdatedAt);
      if (candidate.historyChapterId && candidate.historyUpdatedAt > latestPlaybackAt) {
        latestPlaybackAt = candidate.historyUpdatedAt;
        merged.sourceBookId = candidate.bookId;
        merged.chapterId = candidate.historyChapterId;
        merged.chapterTitle = candidate.historyChapterTitle;
        merged.progressMs = candidate.historyProgressMs;
        merged.durationMs = candidate.historyDurationMs;
        merged.chapterIndex = BookIdentity.chapterIndexFromId(candidate.historyChapterId);
      }
      if (candidate.progressChapterId && candidate.progressUpdatedAt >= latestPlaybackAt) {
        latestPlaybackAt = candidate.progressUpdatedAt;
        merged.sourceBookId = candidate.bookId;
        merged.chapterId = candidate.progressChapterId;
        merged.chapterTitle = candidate.progressChapterTitle;
        merged.progressMs = candidate.progressPositionMs;
        merged.durationMs = candidate.progressDurationMs;
        merged.chapterIndex = candidate.progressChapterIndex;
      }
    }
    if (latestPlaybackAt >= 0) merged.updatedAt = Math.max(merged.updatedAt, latestPlaybackAt);
    merged.chapterId = BookIdentity.rebaseChapterId(merged.chapterId, merged.sourceBookId, merged.bookId);
    return merged;
  }

  private static candidateUpdatedAt(candidate: ListeningRecordCandidate): number {
    return Math.max(candidate.statsUpdatedAt, candidate.historyUpdatedAt, candidate.progressUpdatedAt);
  }
}
