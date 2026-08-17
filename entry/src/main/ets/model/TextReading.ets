export class TextChapterContent {
  title: string = '';
  content: string = '';
  sourceUrl: string = '';

  static of(title: string, content: string, sourceUrl: string): TextChapterContent {
    const value = new TextChapterContent();
    value.title = title;
    value.content = content;
    value.sourceUrl = sourceUrl;
    return value;
  }
}

export class TextReadingPosition {
  bookId: string = '';
  resourceIndex: number = 0;
  domPos: string = '';
  charOffset: number = 0;
  pageOffset: number = 0;
  chapterTitle: string = '';
  updatedAt: number = 0;

  static of(bookId: string, resourceIndex: number, domPos: string,
    pageOffset: number, chapterTitle: string): TextReadingPosition {
    return TextReadingPosition.atChar(bookId, resourceIndex, domPos, 0, pageOffset, chapterTitle);
  }

  static atChar(bookId: string, resourceIndex: number, domPos: string,
    charOffset: number, pageOffset: number, chapterTitle: string): TextReadingPosition {
    const value = new TextReadingPosition();
    value.bookId = bookId;
    value.resourceIndex = resourceIndex;
    value.domPos = domPos;
    value.charOffset = Math.max(0, charOffset);
    value.pageOffset = pageOffset;
    value.chapterTitle = chapterTitle;
    value.updatedAt = Date.now();
    return value;
  }
}

export class TextReadingSettings {
  static readonly FONT_SIZE_MIN: number = 14;
  static readonly FONT_SIZE_MAX: number = 30;
  static readonly FONT_SIZE_DEFAULT: number = 18;
  static readonly LINE_HEIGHT_MIN: number = 1.4;
  static readonly LINE_HEIGHT_MAX: number = 2.4;
  static readonly LINE_HEIGHT_DEFAULT: number = 1.9;

  fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;

  static of(fontSize: number, lineHeight: number): TextReadingSettings {
    const value = new TextReadingSettings();
    value.fontSize = TextReadingSettings.normalizeFontSize(fontSize);
    value.lineHeight = TextReadingSettings.normalizeLineHeight(lineHeight);
    return value;
  }

  static normalizeFontSize(value: number): number {
    return Math.round(Math.max(TextReadingSettings.FONT_SIZE_MIN,
      Math.min(TextReadingSettings.FONT_SIZE_MAX, value)));
  }

  static normalizeLineHeight(value: number): number {
    const clamped = Math.max(TextReadingSettings.LINE_HEIGHT_MIN,
      Math.min(TextReadingSettings.LINE_HEIGHT_MAX, value));
    return Math.round(clamped * 10) / 10;
  }
}

export class TextReaderRouteParams {
  bookId: string = '';
  resourceIndex: number = -1;
  domPos: string = '';

  static of(bookId: string, resourceIndex: number = -1, domPos: string = ''): TextReaderRouteParams {
    const value = new TextReaderRouteParams();
    value.bookId = bookId;
    value.resourceIndex = resourceIndex;
    value.domPos = domPos;
    return value;
  }
}

export class TextSourceError extends Error {
  code: string = '';
  retryAfterSeconds: number = 0;

  constructor(code: string, message: string, retryAfterSeconds: number = 0) {
    super(message);
    this.name = 'TextSourceError';
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}
