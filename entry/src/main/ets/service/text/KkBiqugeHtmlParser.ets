import { Book, Chapter } from '../../model/Book';
import { TextChapterContent } from '../../model/TextReading';
import { BookIdentity } from '../../utils/BookIdentity';

export const KK_BIQU_GE_BASE_URL: string = 'http://www.kkbiquge.net';
export const KK_BIQU_GE_SOURCE_URL: string = 'builtin://text/kk_biquge';
export const KK_BIQU_GE_SOURCE_NAME: string = 'kk笔趣阁';

export class KkBiqugeHtmlParser {
  private static readonly CONTENT_IDS: string[] = ['booktxt', 'chaptercontent', 'content'];
  private static readonly CONTENT_CLASSES: string[] = ['booktxt', 'read-content', 'showtxt'];

  static parseSearch(html: string): Book[] {
    const books: Book[] = [];
    const itemStart = new RegExp('<div\\s+class=["\\\']item["\\\'][^>]*>', 'gi');
    const parts = html.split(itemStart);
    for (let i = 1; i < parts.length; i++) {
      const segment = parts[i];
      const link = KkBiqugeHtmlParser.firstMatch(segment,
        '<dt[^>]*>[\\s\\S]*?<a[^>]*href=["\\\']([^"\\\']+)["\\\'][^>]*>([\\s\\S]*?)</a>');
      if (link.length < 3) continue;
      const bookUrl = KkBiqugeHtmlParser.absoluteUrl(link[1]);
      const title = KkBiqugeHtmlParser.cleanText(link[2]);
      if (!bookUrl || !title) continue;
      const authorMatch = KkBiqugeHtmlParser.firstMatch(segment,
        '<div[^>]*class=["\\\'][^"\\\']*btm[^"\\\']*["\\\'][^>]*>[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>');
      const introMatch = KkBiqugeHtmlParser.firstMatch(segment, '<dd[^>]*>([\\s\\S]*?)</dd>');
      const coverMatch = KkBiqugeHtmlParser.firstMatch(segment,
        '<img[^>]*(?:data-original|src)=["\\\']([^"\\\']+)["\\\'][^>]*>');
      const author = authorMatch.length > 1 ? KkBiqugeHtmlParser.cleanText(authorMatch[1]) : '未知作者';
      const intro = introMatch.length > 1 ? KkBiqugeHtmlParser.cleanText(introMatch[1]) : '';
      const cover = coverMatch.length > 1 ? KkBiqugeHtmlParser.absoluteUrl(coverMatch[1]) : '';
      books.push(KkBiqugeHtmlParser.createBook(title, author, cover, intro, bookUrl));
    }
    return books;
  }

  static applyDetail(book: Book, html: string): Book {
    const nameMatch = KkBiqugeHtmlParser.firstMatch(html,
      '<[^>]*id=["\\\']info["\\\'][^>]*>[\\s\\S]*?<h1[^>]*>([\\s\\S]*?)</h1>');
    const authorMatch = KkBiqugeHtmlParser.firstMatch(html,
      '<[^>]*id=["\\\']info["\\\'][^>]*>[\\s\\S]*?<p[^>]*>[\\s\\S]*?<a[^>]*>([\\s\\S]*?)</a>');
    const introMatch = KkBiqugeHtmlParser.firstMatch(html,
      '<[^>]*id=["\\\']intro["\\\'][^>]*>([\\s\\S]*?)</[^>]+>');
    const categoryMatch = KkBiqugeHtmlParser.firstMatch(html,
      '<p[^>]*class=["\\\'][^"\\\']*sort[^"\\\']*["\\\'][^>]*>([\\s\\S]*?)</p>');
    const coverMatch = KkBiqugeHtmlParser.firstMatch(html,
      '<[^>]*id=["\\\']fmimg["\\\'][^>]*>[\\s\\S]*?<img[^>]*src=["\\\']([^"\\\']+)["\\\']');
    if (nameMatch.length > 1) book.title = KkBiqugeHtmlParser.cleanText(nameMatch[1]) || book.title;
    if (authorMatch.length > 1) book.author = KkBiqugeHtmlParser.cleanText(authorMatch[1]) || book.author;
    if (introMatch.length > 1) book.intro = KkBiqugeHtmlParser.cleanText(introMatch[1]) || book.intro;
    if (categoryMatch.length > 1) {
      book.category = KkBiqugeHtmlParser.cleanText(categoryMatch[1]).replace('类别：', '').trim();
    }
    if (coverMatch.length > 1) {
      book.cover = KkBiqugeHtmlParser.absoluteUrl(coverMatch[1]) || book.cover;
    }
    const chapters = KkBiqugeHtmlParser.parseChapters(book.id, html);
    if (chapters.length > 0) {
      book.chapters = chapters;
      book.chapterCount = chapters.length;
    }
    return book;
  }

  static parseChapters(bookId: string, html: string): Chapter[] {
    const listIndex = KkBiqugeHtmlParser.findIdIndex(html, 'list');
    if (listIndex < 0) return [];
    const footerIndex = KkBiqugeHtmlParser.findIdIndex(html, 'footer');
    const sectionEnd = footerIndex > listIndex ? footerIndex : html.length;
    const section = html.substring(listIndex, sectionEnd);
    const fullListMarkerIndex = section.indexOf('全部章节目录');
    const fullListHeadingEnd = fullListMarkerIndex >= 0 ? section.indexOf('</dt>', fullListMarkerIndex) : -1;
    // 页面前部是倒序的“最新章节”，后部才是正序完整目录；只解析完整目录，避免两段混排。
    const chapterSection = fullListHeadingEnd >= 0 ? section.substring(fullListHeadingEnd + 5) : section;
    const pattern = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)</a>', 'gi');
    const chapters: Chapter[] = [];
    const seen = new Set<string>();
    let match: RegExpExecArray | null = pattern.exec(chapterSection);
    while (match !== null) {
      const attributes = match[1];
      const relation = KkBiqugeHtmlParser.firstMatch(attributes,
        'rel=["\\\']([^"\\\']+)["\\\']');
      const href = KkBiqugeHtmlParser.firstMatch(attributes,
        'href=["\\\']([^"\\\']+\\.html)["\\\']');
      if (relation.length < 2 || relation[1].toLowerCase() !== 'chapter' || href.length < 2) {
        match = pattern.exec(chapterSection);
        continue;
      }
      const url = KkBiqugeHtmlParser.absoluteUrl(href[1]);
      const title = KkBiqugeHtmlParser.cleanText(match[2]);
      if (url && title && !seen.has(url)) {
        seen.add(url);
        const chapter: Chapter = {
          id: '',
          index: 0,
          title,
          duration: 0,
          source: { type: 'url', value: url },
          originSourceValue: url
        };
        chapters.push(chapter);
      }
      match = pattern.exec(chapterSection);
    }
    for (let i = 0; i < chapters.length; i++) {
      chapters[i].id = `${bookId}-c${i}`;
      chapters[i].index = i + 1;
    }
    return chapters;
  }

  static parseContent(title: string, url: string, html: string): TextChapterContent {
    const rawContent = KkBiqugeHtmlParser.extractContentHtml(html);
    const content = rawContent.length > 0 ? KkBiqugeHtmlParser.cleanContent(rawContent) : '';
    return TextChapterContent.of(title, content, url);
  }

  static nextContentUrl(currentUrl: string, html: string): string {
    const anchorPattern = new RegExp('<a\\b([^>]*)>([\\s\\S]*?)</a>', 'gi');
    let match: RegExpExecArray | null = anchorPattern.exec(html);
    while (match !== null) {
      const attributes = match[1] || '';
      const label = KkBiqugeHtmlParser.cleanText(match[2] || '');
      const id = KkBiqugeHtmlParser.attributeValue(attributes, 'id').toLowerCase();
      const className = KkBiqugeHtmlParser.attributeValue(attributes, 'class').toLowerCase();
      const href = KkBiqugeHtmlParser.attributeValue(attributes, 'href');
      const hasNextMarker = id === 'next_url' || className.indexOf('next') >= 0;
      const hasNextLabel = label.indexOf('下一页') >= 0 || label.indexOf('下一頁') >= 0 ||
        label.indexOf('下页') >= 0 || label.indexOf('后页') >= 0;
      if (href.length > 0 && (hasNextMarker || hasNextLabel)) {
        const nextUrl = KkBiqugeHtmlParser.resolveUrl(currentUrl, href);
        if (nextUrl.length > 0 && nextUrl !== currentUrl &&
          KkBiqugeHtmlParser.chapterBase(currentUrl) === KkBiqugeHtmlParser.chapterBase(nextUrl)) {
          return nextUrl;
        }
      }
      match = anchorPattern.exec(html);
    }
    return '';
  }

  static parseSearchAction(html: string): string {
    const match = KkBiqugeHtmlParser.firstMatch(html,
      '<form[^>]*id=["\\\']search["\\\'][^>]*action=["\\\']([^"\\\']+)["\\\']');
    return match.length > 1 ? KkBiqugeHtmlParser.absoluteUrl(match[1]) : `${KK_BIQU_GE_BASE_URL}/searchbe.html`;
  }

  static isVerificationPage(html: string): boolean {
    return new RegExp('<script>\\s*window', 'i').test(html) || html.indexOf('需要先访问首页获取验证') >= 0;
  }

  static toXhtml(title: string, text: string): string {
    const paragraphs = text.split(new RegExp('\\n+', 'g'));
    let body = `<h1>${KkBiqugeHtmlParser.escapeXml(title)}</h1>`;
    for (const paragraph of paragraphs) {
      const value = paragraph.trim();
      if (value) body += `<p>${KkBiqugeHtmlParser.escapeXml(value)}</p>`;
    }
    return `<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head>` +
      `<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/>` +
      `<title>${KkBiqugeHtmlParser.escapeXml(title)}</title>` +
      `<style>html,body{margin:0;padding:0;background:#F5F2EA;color:#2A2622;}` +
      `body{font-family:sans-serif;}h1{font-size:1.35em;}p{margin:0 0 0.9em;}</style>` +
      `</head><body>${body}</body></html>`;
  }

  static absoluteUrl(value: string): string {
    return KkBiqugeHtmlParser.resolveUrl(`${KK_BIQU_GE_BASE_URL}/`, value);
  }

  /** Resolve a link against the page that contains it.  The source often emits
   * relative links for chapter sub-pages, so joining against the host root is
   * incorrect (for example `67606563_2.html`). */
  static resolveUrl(baseUrl: string, value: string): string {
    const raw = KkBiqugeHtmlParser.decodeEntities(value.trim());
    if (!raw || raw.startsWith('#') || raw.toLowerCase().startsWith('javascript:') ||
      raw.toLowerCase().startsWith('data:')) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('//')) {
      const schemeEnd = baseUrl.indexOf('://');
      const scheme = schemeEnd > 0 ? baseUrl.substring(0, schemeEnd) : 'http';
      return `${scheme}:${raw}`;
    }

    const suffixIndex = KkBiqugeHtmlParser.firstUrlSuffixIndex(raw);
    const rawPath = suffixIndex >= 0 ? raw.substring(0, suffixIndex) : raw;
    const suffix = suffixIndex >= 0 ? raw.substring(suffixIndex) : '';
    if (rawPath.length === 0) return KkBiqugeHtmlParser.stripUrlSuffix(baseUrl) + suffix;
    let joinedPath: string;
    if (rawPath.startsWith('/')) {
      joinedPath = KkBiqugeHtmlParser.baseOrigin(baseUrl) + rawPath;
    } else {
      const basePath = KkBiqugeHtmlParser.stripUrlSuffix(baseUrl);
      const slash = basePath.lastIndexOf('/');
      const directory = slash >= 0 ? basePath.substring(0, slash + 1) : `${KK_BIQU_GE_BASE_URL}/`;
      joinedPath = directory + rawPath;
    }
    return KkBiqugeHtmlParser.normalizeUrlPath(joinedPath) + suffix;
  }

  static cleanText(value: string): string {
    const withoutScripts = value
      .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), '')
      .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), '')
      .replace(new RegExp('<[^>]+>', 'g'), ' ');
    return KkBiqugeHtmlParser.decodeEntities(withoutScripts)
      .replace(new RegExp('\\s+', 'g'), ' ')
      .trim();
  }

  static cleanContent(value: string): string {
    const withLines = value
      .replace(new RegExp('\\r\\n?', 'g'), '\n')
      .replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
      .replace(new RegExp('<br\\s*/?>', 'gi'), '\n')
      .replace(new RegExp('<(?:p|div|section|article|li|h[1-6])\\b[^>]*>', 'gi'), '\n')
      .replace(new RegExp('</(?:p|div|section|article|li|h[1-6])\\s*>', 'gi'), '\n')
      .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), '')
      .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), '')
      .replace(new RegExp('<[^>]+>', 'g'), '');
    return KkBiqugeHtmlParser.decodeEntities(withLines)
      .replace(new RegExp('[\\t ]+', 'g'), ' ')
      .replace(new RegExp(' *\\n *', 'g'), '\n')
      .replace(new RegExp('\\n{3,}', 'g'), '\n\n')
      .trim();
  }

  private static extractContentHtml(html: string): string {
    for (const id of KkBiqugeHtmlParser.CONTENT_IDS) {
      const content = KkBiqugeHtmlParser.extractElementByAttribute(html, 'id', id);
      if (content.length > 0) return content;
    }
    for (const className of KkBiqugeHtmlParser.CONTENT_CLASSES) {
      const content = KkBiqugeHtmlParser.extractElementByClass(html, className);
      if (content.length > 0) return content;
    }
    return '';
  }

  private static extractElementByAttribute(html: string, attribute: string, value: string): string {
    const pattern = new RegExp(`<([A-Za-z][A-Za-z0-9:-]*)\\b[^>]*\\b${attribute}\\s*=\\s*["']${value}["'][^>]*>`, 'i');
    return KkBiqugeHtmlParser.extractElementByOpeningPattern(html, pattern);
  }

  private static extractElementByClass(html: string, className: string): string {
    const pattern = new RegExp(`<([A-Za-z][A-Za-z0-9:-]*)\\b[^>]*\\bclass\\s*=\\s*["'][^"']*\\b${className}\\b[^"']*["'][^>]*>`, 'i');
    return KkBiqugeHtmlParser.extractElementByOpeningPattern(html, pattern);
  }

  private static extractElementByOpeningPattern(html: string, pattern: RegExp): string {
    const match = pattern.exec(html);
    if (match === null || match.index === undefined || match.length < 2) return '';
    const openingTag = match[0];
    const start = match.index + openingTag.length;
    const end = KkBiqugeHtmlParser.findMatchingClosingTag(html, match[1], start);
    return html.substring(start, end >= 0 ? end : html.length);
  }

  private static findMatchingClosingTag(html: string, tagName: string, start: number): number {
    const tokenPattern = new RegExp(`<\\/?${tagName}\\b[^>]*>`, 'gi');
    tokenPattern.lastIndex = start;
    let depth = 1;
    let token: RegExpExecArray | null = tokenPattern.exec(html);
    while (token !== null) {
      const tokenText = token[0];
      if (tokenText.startsWith('</')) {
        depth--;
      } else if (!tokenText.endsWith('/>')) {
        depth++;
      }
      if (depth === 0 && token.index !== undefined) return token.index;
      token = tokenPattern.exec(html);
    }
    return -1;
  }

  private static attributeValue(attributes: string, name: string): string {
    const pattern = new RegExp(`\\b${name}\\s*=\\s*(?:["']([^"']*)["']|([^\\s>]+))`, 'i');
    const match = pattern.exec(attributes);
    if (match === null) return '';
    return match[1] || match[2] || '';
  }

  private static firstUrlSuffixIndex(value: string): number {
    const query = value.indexOf('?');
    const hash = value.indexOf('#');
    if (query < 0) return hash;
    if (hash < 0) return query;
    return Math.min(query, hash);
  }

  private static stripUrlSuffix(value: string): string {
    const index = KkBiqugeHtmlParser.firstUrlSuffixIndex(value);
    return index >= 0 ? value.substring(0, index) : value;
  }

  private static baseOrigin(value: string): string {
    const schemeEnd = value.indexOf('://');
    const authorityStart = schemeEnd >= 0 ? schemeEnd + 3 : 0;
    const slash = value.indexOf('/', authorityStart);
    return slash >= 0 ? value.substring(0, slash) : value;
  }

  private static normalizeUrlPath(value: string): string {
    const origin = KkBiqugeHtmlParser.baseOrigin(value);
    const originEnd = origin.length;
    const path = value.substring(originEnd);
    const segments = path.split('/');
    const normalized: string[] = [];
    for (const segment of segments) {
      if (!segment || segment === '.') continue;
      if (segment === '..') {
        if (normalized.length > 0) normalized.pop();
        continue;
      }
      normalized.push(segment);
    }
    return `${origin}/${normalized.join('/')}`;
  }

  private static createBook(title: string, author: string, cover: string, intro: string, bookUrl: string): Book {
    const chapters: Chapter[] = [];
    const book: Book = {
      id: BookIdentity.onlineTextBookId(KK_BIQU_GE_SOURCE_URL, bookUrl),
      contentType: 'text',
      title,
      author: author || '未知作者',
      narrator: KK_BIQU_GE_SOURCE_NAME,
      cover,
      category: '电子书',
      intro,
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: ['电子书', KK_BIQU_GE_SOURCE_NAME],
      chapters,
      bookUrl,
      sourceUrl: KK_BIQU_GE_SOURCE_URL
    };
    return book;
  }

  private static firstMatch(value: string, pattern: string): string[] {
    const match = new RegExp(pattern, 'i').exec(value);
    if (match === null) return [];
    const result: string[] = [];
    for (let i = 0; i < match.length; i++) result.push(match[i] || '');
    return result;
  }

  private static findIdIndex(html: string, id: string): number {
    const quoted = `id="${id}"`;
    const singleQuoted = `id='${id}'`;
    const first = html.indexOf(quoted);
    return first >= 0 ? first : html.indexOf(singleQuoted);
  }

  private static chapterBase(url: string): string {
    const cleanUrl = KkBiqugeHtmlParser.stripUrlSuffix(url);
    const match = new RegExp('^(.*)_\\d+(\\.(?:html?|shtml))$', 'i').exec(cleanUrl);
    return match !== null ? `${match[1]}${match[2]}` : cleanUrl;
  }

  private static decodeEntities(value: string): string {
    return value
      .replace(new RegExp('&nbsp;', 'gi'), ' ')
      .replace(new RegExp('&amp;', 'gi'), '&')
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'")
      .replace(new RegExp('&lt;', 'gi'), '<')
      .replace(new RegExp('&gt;', 'gi'), '>');
  }

  private static escapeXml(value: string): string {
    return value
      .replace(new RegExp('&', 'g'), '&amp;')
      .replace(new RegExp('<', 'g'), '&lt;')
      .replace(new RegExp('>', 'g'), '&gt;')
      .replace(new RegExp('"', 'g'), '&quot;')
      .replace(new RegExp("'", 'g'), '&apos;');
  }
}
