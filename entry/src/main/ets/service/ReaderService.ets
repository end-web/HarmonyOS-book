import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { SourceDataService } from './SourceDataService';
import { SearchCache } from '../utils/SearchCache';

export class ReaderService {
  static async getBook(context: common.UIAbilityContext, bookId: string): Promise<Book | null> {
    const cached = SearchCache.get(bookId);
    if (cached) return cached;
    const book = await DataService.getBookById(context, bookId);
    return book || null;
  }

  static async ensureChapters(book: Book): Promise<Book> {
    if (book.chapters && book.chapters.length > 0) return book;
    if (!book.bookUrl || !book.sourceUrl) return book;

    const sources = await SourceDataService.getSources();
    const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
    if (!source) return book;

    let tocUrl = book.bookUrl;
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
    if (info?.tocUrl) tocUrl = info.tocUrl;
    if (info?.intro && !book.intro) book.intro = info.intro;
    if (info?.coverUrl && !book.cover) book.cover = info.coverUrl;
    if (info?.author && !book.author) book.author = info.author;

    const vars: Record<string, string> = {};
    if (book.variables) {
      for (const k of Object.keys(book.variables)) vars[k] = book.variables[k];
    }
    if (info?.variables) {
      if (!book.variables) book.variables = {};
      for (const k of Object.keys(info.variables)) {
        vars[k] = info.variables[k];
        book.variables[k] = info.variables[k];
      }
    }

    const items = await BookSourceService.getBookToc(source, tocUrl, vars, book.title);
    const seen = new Set<string>();
    const unique = items.filter((item: TocItem): boolean => {
      if (seen.has(item.url)) return false;
      seen.add(item.url);
      return true;
    });
    book.chapters = unique.map((item: TocItem, idx: number): Chapter => ({
      id: `${book.id}-c${idx}`,
      index: idx + 1,
      title: item.name,
      duration: item.duration || 0,
      source: { type: 'url', value: item.url },
      originSourceValue: item.url
    }));
    book.chapterCount = book.chapters.length;
    await DataService.upsertCachedBook(book);
    SearchCache.put(book);
    return book;
  }

  static async loadContent(book: Book, chapter: Chapter, nextChapter?: Chapter): Promise<string[]> {
    if (!book.sourceUrl) return [];
    const sources = await SourceDataService.getSources();
    const source = sources.find((s) => s.bookSourceUrl === book.sourceUrl);
    if (!source) return [];
    const url = chapter.originSourceValue || chapter.source.value;
    const nextUrl = nextChapter ? (nextChapter.originSourceValue || nextChapter.source.value) : undefined;
    const content = await BookSourceService.getTextContent(source, url, nextUrl);
    return ReaderService.splitParagraphs(content);
  }

  /**
   * 取章节原始正文文本(Reader Kit txt 桥接用)。
   * 复用 loadContent 的抓取/清洗,再把段落用空行拼回 —— Reader Kit txt 解析器按空行分段排版。
   */
  static async loadChapterText(book: Book, chapter: Chapter, nextChapter?: Chapter): Promise<string> {
    const paragraphs = await ReaderService.loadContent(book, chapter, nextChapter);
    let text = paragraphs.join('\n\n');
    hilog.info(0x9527, 'RdrDbg', 'content src=%{public}s paraN=%{public}d len=%{public}d head=%{public}s',
      book.sourceUrl, paragraphs.length, text.length, text.substring(0, 180));
    // 防御:正常章节远小于此;超出多为书源 JS 内容规则返回异常(整本/错误页),截断避免排版引擎产生上千页
    const MAX_CHARS = 200000;
    if (text.length > MAX_CHARS) {
      text = text.substring(0, MAX_CHARS);
    }
    return text;
  }

  /**
   * 把章节文本写成沙箱 txt 文件,返回绝对路径,供 bookParser.getDefaultHandler(path) 解析。
   * Reader Kit 仅支持当前 hap 沙箱路径;首行写章节标题,UTF-8。
   * 一书一章一文件(同章重读 TRUNC 覆盖),文件很小(KB 级)。
   */
  static async writeChapterTxt(context: common.UIAbilityContext, book: Book, chapter: Chapter, text: string): Promise<string> {
    const fileName = `reader_${ReaderService.sanitizeName(book.id)}_${ReaderService.sanitizeName(chapter.id)}.txt`;
    const filePath = `${context.filesDir}/${fileName}`;
    const body = `${chapter.title}\n\n${text}`;
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, body);
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
    return filePath;
  }

  /** 文件名安全化:非 [a-zA-Z0-9._-] 一律替换为下划线 */
  private static sanitizeName(s: string): string {
    return s.replace(/[^a-zA-Z0-9._-]/g, '_');
  }

  static splitParagraphs(content: string): string[] {
    if (!content) return [];
    const normalized = content
      .replace(/\r/g, '\n')
      .replace(/\u00a0/g, ' ')
      .replace(/[ \t]+\n/g, '\n');
    const parts = normalized.split(/\n+/);
    const out: string[] = [];
    for (const p of parts) {
      const text = p.trim();
      if (text.length === 0) continue;
      out.push(text);
    }
    return out;
  }
}
