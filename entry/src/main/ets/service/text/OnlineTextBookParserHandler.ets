import { buffer } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { Book, Chapter } from '../../model/Book';
import { BookSourceService } from '../BookSourceService';
import { KkBiqugeHtmlParser } from './KkBiqugeHtmlParser';

export class OnlineTextBookParserHandler extends bookParser.BookParserHandler {
  private book: Book;
  private resourceDirectory: string;
  private contentCache: Map<number, string> = new Map();
  private contentRequests: Map<number, Promise<string>> = new Map();

  constructor(book: Book, resourceDirectory: string) {
    super();
    this.book = book;
    this.resourceDirectory = resourceDirectory;
    this.ensureResourceDirectory();
  }

  getBookInfo(): bookParser.BookInfo {
    const info: bookParser.BookInfo = {
      bookTitle: this.book.title,
      bookCreator: this.book.author,
      bookLanguage: 'zh_CN',
      bookCoverImage: '',
      bookCharset: 'utf-8',
      bookType: 'epub',
      isRtl: false,
      renditionLayout: 'reflowable',
      renditionOrientation: 'auto',
      renditionSpread: 'none'
    };
    return info;
  }

  getCatalogList(): bookParser.CatalogItem[] {
    const result: bookParser.CatalogItem[] = [];
    for (let i = 0; i < this.book.chapters.length; i++) {
      const chapter = this.book.chapters[i];
      const item: bookParser.CatalogItem = {
        catalogId: i,
        catalogName: chapter.title,
        catalogLevel: 0,
        playOrder: i,
        idRef: this.idRef(i),
        href: this.resourceName(i),
        resourceFile: this.resourceName(i)
      };
      result.push(item);
    }
    return result;
  }

  getSpineList(): bookParser.SpineItem[] {
    const result: bookParser.SpineItem[] = [];
    for (let i = 0; i < this.book.chapters.length; i++) {
      const item: bookParser.SpineItem = {
        idRef: this.idRef(i),
        index: i,
        href: this.resourceName(i),
        properties: ''
      };
      result.push(item);
    }
    return result;
  }

  async getSpineItemContent(spineIndex: number): Promise<string> {
    const cached = this.contentCache.get(spineIndex);
    if (cached !== undefined) {
      if (!fileIo.accessSync(this.resourcePath(spineIndex))) this.writeResourceFile(spineIndex, cached);
      return cached;
    }
    const pending = this.contentRequests.get(spineIndex);
    if (pending !== undefined) return pending;
    const request = this.loadSpineItemContent(spineIndex);
    this.contentRequests.set(spineIndex, request);
    try {
      return await request;
    } finally {
      this.contentRequests.delete(spineIndex);
    }
  }

  private async loadSpineItemContent(spineIndex: number): Promise<string> {
    const chapter = this.chapterAt(spineIndex);
    const url = chapter.originSourceValue ?? chapter.source.value;
    const content = await BookSourceService.getTextChapterContent(
      this.book, url, chapter.title, chapter.variables);
    const xhtml = KkBiqugeHtmlParser.toXhtml(chapter.title, content.content);
    this.writeResourceFile(spineIndex, xhtml);
    this.contentCache.set(spineIndex, xhtml);
    return xhtml;
  }

  async prepareSpineItem(spineIndex: number): Promise<void> {
    await this.getSpineItemContent(spineIndex);
  }

  getResourceContent(spineIndex: number, filePath: string): ArrayBuffer {
    const cached = this.contentCache.get(spineIndex);
    if (cached !== undefined) return buffer.from(cached, 'utf-8').buffer;
    let path = filePath;
    if (!path.startsWith('/')) path = `${this.resourceDirectory}/${path}`;
    if (fileIo.accessSync(path)) {
      const stat = fileIo.statSync(path);
      const value = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.readSync(file.fd, value);
      } finally {
        fileIo.closeSync(file);
      }
      return value;
    }
    return new ArrayBuffer(0);
  }

  getDomPosByCatalogHref(_href: string): string {
    return '';
  }

  getAbsoluteResourcePath(spineIndex: number): string {
    this.chapterAt(spineIndex);
    const path = this.resourcePath(spineIndex);
    if (!fileIo.accessSync(path)) throw new Error(`章节资源尚未准备：${spineIndex}`);
    return path;
  }

  private ensureResourceDirectory(): void {
    if (!fileIo.accessSync(this.resourceDirectory)) fileIo.mkdirSync(this.resourceDirectory, true);
  }

  private writeResourceFile(index: number, content: string): void {
    const file = fileIo.openSync(this.resourcePath(index),
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private resourcePath(index: number): string {
    return `${this.resourceDirectory}/${this.resourceName(index)}`;
  }

  private resourceName(index: number): string {
    return `chapter-${index}.xhtml`;
  }

  private chapterAt(index: number): Chapter {
    const chapter = this.book.chapters[index];
    if (chapter === undefined) throw new Error('章节索引无效');
    return chapter;
  }

  private idRef(index: number): string {
    return `online-chapter-${index}`;
  }
}
