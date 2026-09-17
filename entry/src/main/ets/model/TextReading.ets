import { ReaderPattern, ReaderThemeId, findThemePreset, normalizeHex, resolvePalette } from './ReaderTheme';

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

/** 翻页模式 */
export enum PageTurnMode {
  /** 覆盖翻页（默认） */
  Cover = 'cover',
  /** 仿真翻页 */
  Simulation = 'simulation',
  /** 滑动翻页 */
  Slide = 'slide',
  /** 连续滚动正文；保留旧存储值以兼容已保存的设置。 */
  Vertical = 'vertical'
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
  static readonly PAGE_TURN_MODE_DEFAULT: string = PageTurnMode.Cover;
  static readonly SHOW_READING_STATUS_DEFAULT: boolean = true;
  /** 边距持久化宽松上限：上边距允许随屏幕高度放大到视口一半，其余边保持 UI 上限。 */
  static readonly MARGIN_MAX_LIMIT: number = 512;
  /** 常规边距 UI 上限（左右/下） */
  static readonly MARGIN_UI_MAX: number = 64;

  followSystemTheme: boolean = false;
  marginLeft: number = 16;
  marginRight: number = 16;
  marginTop: number = 12;
  marginBottom: number = 12;

  static normalizeMargin(value: number, fallback: number, max: number = TextReadingSettings.MARGIN_UI_MAX): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(max, value))) : fallback;
  }

  fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  /** 预设主题 id，或 ReaderThemeId.Image 表示自定义图片 */
  themeId: string = TextReadingSettings.THEME_DEFAULT;
  /** 自定义图片的蒙层底色，兼容旧自定义色 */
  customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  /** 兼容旧偏好字段，只保留 none / image */
  pattern: string = ReaderPattern.None;
  /** pattern=image 时的沙箱内图片路径 */
  backgroundImage: string = '';
  /** 背景图上的底色蒙层浓度 */
  overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  /** 翻页模式 */
  pageTurnMode: string = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
  /** 底部居中显示电量和时间，不影响正文视口。 */
  showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;

  static of(fontSize: number, lineHeight: number): TextReadingSettings {
    const value = new TextReadingSettings();
    value.fontSize = TextReadingSettings.normalizeFontSize(fontSize);
    value.lineHeight = TextReadingSettings.normalizeLineHeight(lineHeight);
    return value;
  }

  /** 完整构造；服务层读盘后用它一次装配。 */
  static ofAll(fontSize: number, lineHeight: number, themeId: string,
    customBackground: string, pattern: string, backgroundImage: string,
    overlayAlpha: number, pageTurnMode?: string, showReadingStatus?: boolean): TextReadingSettings {
    const value = TextReadingSettings.of(fontSize, lineHeight);
    value.themeId = TextReadingSettings.normalizeThemeId(themeId);
    value.customBackground = normalizeHex(customBackground);
    value.pattern = TextReadingSettings.normalizePattern(pattern);
    value.backgroundImage = typeof backgroundImage === 'string' ? backgroundImage : '';
    value.overlayAlpha = TextReadingSettings.normalizeOverlay(overlayAlpha);
    value.pageTurnMode = TextReadingSettings.normalizePageTurnMode(pageTurnMode);
    value.showReadingStatus = typeof showReadingStatus === 'boolean' ? showReadingStatus :
      TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    // 旧版「主题 + 相册图案」合并为图片主题，保留原蒙层配色与浓度。
    if (value.pattern === ReaderPattern.Image && value.backgroundImage.length > 0
      && value.themeId !== ReaderThemeId.Image) {
      value.customBackground = resolvePalette(value.themeId, value.customBackground).background;
      value.themeId = ReaderThemeId.Image;
    }
    if (value.themeId === ReaderThemeId.Custom
      || (value.themeId === ReaderThemeId.Image && value.backgroundImage.length === 0)) {
      value.themeId = TextReadingSettings.THEME_DEFAULT;
    }
    value.pattern = value.themeId === ReaderThemeId.Image ? ReaderPattern.Image : ReaderPattern.None;
    return value;
  }

  static normalizeThemeId(value: string): string {
    if (typeof value !== 'string' || value.length === 0) return TextReadingSettings.THEME_DEFAULT;
    if (value === ReaderThemeId.Paper) return ReaderThemeId.Parchment;
    if (value === ReaderThemeId.Black) return ReaderThemeId.Night;
    if (value === ReaderThemeId.Custom || value === ReaderThemeId.Image) return value;
    return findThemePreset(value) !== null ? value : TextReadingSettings.THEME_DEFAULT;
  }

  static normalizePattern(value: string): string {
    if (value === ReaderPattern.Image || value === ReaderPattern.None) {
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

  static normalizePageTurnMode(value?: string): string {
    if (value === PageTurnMode.Cover || value === PageTurnMode.Simulation || value === PageTurnMode.Slide || value === PageTurnMode.Vertical) {
      return value;
    }
    return TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
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

/** 详情页复用栈内阅读页时请求跳章的事件 */
export const EVT_READER_JUMP_CHAPTER: string = 'app.reader.jumpChapter';

/** EVT_READER_JUMP_CHAPTER 的事件负载 */
export class ReaderJumpChapterEvent {
  bookId: string = '';
  resourceIndex: number = -1;
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
