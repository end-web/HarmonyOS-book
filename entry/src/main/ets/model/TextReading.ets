import { ReaderPattern, ReaderThemeId, findThemePreset, normalizeHex } from './ReaderTheme';

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
  /** 背景图蒙层浓度：0 = 图片原样，0.85 = 几乎被底色盖住 */
  static readonly OVERLAY_MIN: number = 0;
  static readonly OVERLAY_MAX: number = 0.85;
  static readonly OVERLAY_DEFAULT: number = 0.35;
  static readonly THEME_DEFAULT: string = ReaderThemeId.Parchment;
  static readonly CUSTOM_BACKGROUND_DEFAULT: string = '#F5F2EA';

  fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  /** 预设主题 id，或 ReaderThemeId.Custom 表示走 customBackground */
  themeId: string = TextReadingSettings.THEME_DEFAULT;
  /** themeId=custom 时生效的底色 */
  customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  /** 背景图案 */
  pattern: string = ReaderPattern.None;
  /** pattern=image 时的沙箱内图片路径 */
  backgroundImage: string = '';
  /** 背景图上的底色蒙层浓度 */
  overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;

  static of(fontSize: number, lineHeight: number): TextReadingSettings {
    const value = new TextReadingSettings();
    value.fontSize = TextReadingSettings.normalizeFontSize(fontSize);
    value.lineHeight = TextReadingSettings.normalizeLineHeight(lineHeight);
    return value;
  }

  /** 完整构造；服务层读盘后用它一次装配。 */
  static ofAll(fontSize: number, lineHeight: number, themeId: string,
    customBackground: string, pattern: string, backgroundImage: string,
    overlayAlpha: number): TextReadingSettings {
    const value = TextReadingSettings.of(fontSize, lineHeight);
    value.themeId = TextReadingSettings.normalizeThemeId(themeId);
    value.customBackground = normalizeHex(customBackground);
    value.pattern = TextReadingSettings.normalizePattern(pattern);
    value.backgroundImage = typeof backgroundImage === 'string' ? backgroundImage : '';
    value.overlayAlpha = TextReadingSettings.normalizeOverlay(overlayAlpha);
    // 声明了图片图案但没有实际路径时退回无图案，避免画出空白层
    if (value.pattern === ReaderPattern.Image && value.backgroundImage.length === 0) {
      value.pattern = ReaderPattern.None;
    }
    return value;
  }

  static normalizeThemeId(value: string): string {
    if (typeof value !== 'string' || value.length === 0) return TextReadingSettings.THEME_DEFAULT;
    if (value === ReaderThemeId.Custom) return value;
    return findThemePreset(value) !== null ? value : TextReadingSettings.THEME_DEFAULT;
  }

  static normalizePattern(value: string): string {
    if (value === ReaderPattern.Paper || value === ReaderPattern.Cloth
      || value === ReaderPattern.Image || value === ReaderPattern.None) {
      return value;
    }
    return ReaderPattern.None;
  }

  static normalizeOverlay(value: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) return TextReadingSettings.OVERLAY_DEFAULT;
    const clamped = Math.max(TextReadingSettings.OVERLAY_MIN,
      Math.min(TextReadingSettings.OVERLAY_MAX, value));
    return Math.round(clamped * 100) / 100;
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
