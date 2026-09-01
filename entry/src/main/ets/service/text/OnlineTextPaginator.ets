import { text as graphicsText } from '@kit.ArkGraphics2D';

export class OnlineTextPage {
  text: string = '';
  startOffset: number = 0;
  endOffset: number = 0;

  static of(content: string, startOffset: number, endOffset: number): OnlineTextPage {
    const page = new OnlineTextPage();
    page.startOffset = Math.max(0, Math.min(startOffset, content.length));
    page.endOffset = Math.max(page.startOffset, Math.min(endOffset, content.length));
    page.text = content.substring(page.startOffset, page.endOffset);
    return page;
  }
}

export class OnlineTextMeasuredLine {
  startOffset: number = 0;
  heightPx: number = 0;

  static of(startOffset: number, heightPx: number): OnlineTextMeasuredLine {
    const line = new OnlineTextMeasuredLine();
    line.startOffset = Math.max(0, startOffset);
    line.heightPx = Math.max(1, heightPx);
    return line;
  }
}

export class OnlineTextNavigationTarget {
  chapterIndex: number = 0;
  pageIndex: number = 0;
  openLastPage: boolean = false;
  moved: boolean = false;

  static of(chapterIndex: number, pageIndex: number,
    openLastPage: boolean, moved: boolean): OnlineTextNavigationTarget {
    const target = new OnlineTextNavigationTarget();
    target.chapterIndex = Math.max(0, chapterIndex);
    target.pageIndex = Math.max(0, pageIndex);
    target.openLastPage = openLastPage;
    target.moved = moved;
    return target;
  }
}

export class OnlineTextPageNavigator {
  static previous(chapterIndex: number, pageIndex: number): OnlineTextNavigationTarget {
    if (pageIndex > 0) {
      return OnlineTextNavigationTarget.of(chapterIndex, pageIndex - 1, false, true);
    }
    if (chapterIndex > 0) {
      return OnlineTextNavigationTarget.of(chapterIndex - 1, 0, true, true);
    }
    return OnlineTextNavigationTarget.of(chapterIndex, pageIndex, false, false);
  }

  static next(chapterIndex: number, pageIndex: number,
    pageCount: number, chapterCount: number): OnlineTextNavigationTarget {
    const safePageCount = Math.max(1, pageCount);
    const safeChapterCount = Math.max(1, chapterCount);
    if (pageIndex + 1 < safePageCount) {
      return OnlineTextNavigationTarget.of(chapterIndex, pageIndex + 1, false, true);
    }
    if (chapterIndex + 1 < safeChapterCount) {
      return OnlineTextNavigationTarget.of(chapterIndex + 1, 0, false, true);
    }
    return OnlineTextNavigationTarget.of(chapterIndex, pageIndex, false, false);
  }
}

export class OnlineTextPaginator {
  static normalizeContent(content: string): string {
    let value = content
      .replace(new RegExp('\\r\\n?', 'g'), '\n')
      .replace(new RegExp('[\\u200B\\uFEFF]', 'g'), '')
      .replace(new RegExp('&nbsp;|&#160;', 'gi'), ' ');
    const hasHtmlBlocks = new RegExp(
      '<(?:br|p|div|section|article|li|h[1-6])(?:\\s[^>]*)?/?>|</(?:p|div|section|article|li|h[1-6])\\s*>', 'i')
      .test(value);
    if (hasHtmlBlocks) {
      value = value
        .replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
        .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), '')
        .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), '')
        .replace(new RegExp('<br\\s*/?>', 'gi'), '\n')
        .replace(new RegExp('</(?:p|div|section|article|li|h[1-6])\\s*>', 'gi'), '\n')
        .replace(new RegExp('<(?:p|div|section|article|li|h[1-6])\\b[^>]*>', 'gi'), '\n')
        .replace(new RegExp('<[^>]+>', 'g'), '');
    }
    return OnlineTextPaginator.decodeEntities(value)
      .replace(new RegExp('[ \\t]+\\n', 'g'), '\n')
      .replace(new RegExp('\\n[ \\t]+', 'g'), '\n')
      .replace(new RegExp('\\n{3,}', 'g'), '\n\n')
      .trim();
  }

  static paginate(content: string, widthPx: number, heightPx: number,
    fontSizePx: number, lineHeight: number): OnlineTextPage[] {
    const normalized = OnlineTextPaginator.normalizeContent(content);
    if (normalized.length === 0) return [OnlineTextPage.of('', 0, 0)];

    const safeWidth = Math.max(1, widthPx);
    const safeFontSize = Math.max(1, fontSizePx);
    const safeLineHeight = Math.max(1, lineHeight);
    const textStyle: graphicsText.TextStyle = {
      fontSize: safeFontSize,
      fontWeight: graphicsText.FontWeight.W400,
      heightScale: safeLineHeight,
      heightOnly: true,
      locale: 'zh-Hans'
    };
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: textStyle,
      align: graphicsText.TextAlign.START,
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      breakStrategy: graphicsText.BreakStrategy.GREEDY
    };
    const builder = new graphicsText.ParagraphBuilder(
      paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(textStyle);
    builder.addText(normalized);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(safeWidth);
    const metrics = paragraph.getLineMetrics();
    const lines: OnlineTextMeasuredLine[] = [];
    for (let i = 0; i < metrics.length; i++) {
      lines.push(OnlineTextMeasuredLine.of(metrics[i].startIndex, metrics[i].height));
    }
    return OnlineTextPaginator.paginateMeasuredLines(normalized, lines, heightPx);
  }

  static paginateMeasuredLines(content: string, lines: OnlineTextMeasuredLine[],
    heightPx: number): OnlineTextPage[] {
    if (content.length === 0) return [OnlineTextPage.of('', 0, 0)];
    if (lines.length === 0) return [OnlineTextPage.of(content, 0, content.length)];

    const pages: OnlineTextPage[] = [];
    const safeHeight = Math.max(1, heightPx);
    let pageStart = 0;
    let usedHeight = 0;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineStart = Math.max(pageStart, Math.min(line.startOffset, content.length));
      if (usedHeight > 0 && usedHeight + line.heightPx > safeHeight && lineStart > pageStart) {
        pages.push(OnlineTextPage.of(content, pageStart, lineStart));
        pageStart = lineStart;
        usedHeight = 0;
      }
      usedHeight += line.heightPx;
    }
    if (pageStart < content.length || pages.length === 0) {
      pages.push(OnlineTextPage.of(content, pageStart, content.length));
    }
    return pages;
  }

  static pageIndexForOffset(pages: OnlineTextPage[], charOffset: number): number {
    if (pages.length === 0) return 0;
    const offset = Math.max(0, charOffset);
    for (let i = 0; i < pages.length; i++) {
      if (offset < pages[i].endOffset) return i;
    }
    return pages.length - 1;
  }

  private static decodeEntities(content: string): string {
    return content
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'")
      .replace(new RegExp('&lt;', 'gi'), '<')
      .replace(new RegExp('&gt;', 'gi'), '>')
      .replace(new RegExp('&amp;', 'gi'), '&');
  }
}
