const HOME_AUDIO_PREFIX = 'home_audio_';
const SEARCH_AUDIO_PREFIX = 'search_audio_';

export class BookIdentity {
  static onlineAudioBookId(sourceUrl: string, bookUrl: string): string {
    const raw = `${sourceUrl}::${bookUrl}`;
    let hash: number = 5381;
    for (let index = 0; index < raw.length; index++) {
      hash = (((hash << 5) + hash) + raw.charCodeAt(index)) | 0;
    }
    return `${SEARCH_AUDIO_PREFIX}${(hash >>> 0).toString(36)}`;
  }

  static isSameBook(leftId: string, leftSourceUrl: string, leftBookUrl: string,
    rightId: string, rightSourceUrl: string, rightBookUrl: string): boolean {
    if (leftId === rightId) return true;
    const leftHasSourceIdentity = leftSourceUrl.length > 0 && leftBookUrl.length > 0;
    const rightHasSourceIdentity = rightSourceUrl.length > 0 && rightBookUrl.length > 0;
    if (leftHasSourceIdentity && rightHasSourceIdentity) {
      return leftSourceUrl === rightSourceUrl && leftBookUrl === rightBookUrl;
    }
    const leftAlias = BookIdentity.legacyAudioAlias(leftId);
    const rightAlias = BookIdentity.legacyAudioAlias(rightId);
    return leftAlias.length > 0 && leftAlias === rightAlias;
  }

  static legacyAudioAlias(bookId: string): string {
    if (bookId.startsWith(HOME_AUDIO_PREFIX)) {
      return bookId.substring(HOME_AUDIO_PREFIX.length);
    }
    if (bookId.startsWith(SEARCH_AUDIO_PREFIX)) {
      return bookId.substring(SEARCH_AUDIO_PREFIX.length);
    }
    return '';
  }

  static rebaseChapterId(chapterId: string, sourceBookId: string, targetBookId: string): string {
    if (!chapterId || !sourceBookId || !targetBookId || sourceBookId === targetBookId) return chapterId;
    const sourcePrefix = `${sourceBookId}-c`;
    if (!chapterId.startsWith(sourcePrefix)) return chapterId;
    return `${targetBookId}${chapterId.substring(sourceBookId.length)}`;
  }

  static chapterIndexFromId(chapterId: string): number {
    const separator = chapterId.lastIndexOf('-c');
    if (separator < 0 || separator + 2 >= chapterId.length) return -1;
    const value = chapterId.substring(separator + 2);
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code < 48 || code > 57) return -1;
    }
    const chapterIndex = Number(value);
    return Number.isFinite(chapterIndex) ? chapterIndex : -1;
  }
}
