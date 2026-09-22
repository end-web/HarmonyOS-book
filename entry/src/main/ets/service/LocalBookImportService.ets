import { common } from '@kit.AbilityKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { Book, Chapter } from '../model/Book';
import { KkBiqugeHtmlParser } from './text/KkBiqugeHtmlParser';
import { EpubCoverService } from './text/EpubCoverService';

export class LocalImportFile {
  uri: string = '';
  name: string = '';
  ext: string = '';
}

export class LocalBookPreview {
  title: string = '';
  author: string = '';
  cover: string = '';
  directory: string = '';
}

export class LocalBookImportService {
  static readonly MAX_CHAPTERS: number = 50000;
  static readonly MAX_ARCHIVE_BYTES: number = 32 * 1024 * 1024 * 1024;
  static readonly MAX_EXPANDED_BYTES: number = 64 * 1024 * 1024 * 1024;
  static readonly TEXT_EXTS: string[] = ['.txt', '.epub', '.html', '.htm'];
  static readonly AUDIO_EXTS: string[] = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac'];

  /** 选文件后预解析，不写入书架；临时封面在正式导入时复制到书籍目录。 */
  static async preview(context: common.Context, file: LocalImportFile): Promise<LocalBookPreview> {
    const result = new LocalBookPreview();
    result.title = file.name;
    if (file.ext === '.txt' || file.ext === '.html' || file.ext === '.htm') {
      const source = await fileIo.open(file.uri, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(16384);
        const length = await fileIo.read(source.fd, buffer);
        const sample = new Uint8Array(buffer, 0, length);
        const content = util.TextDecoder.create(LocalBookImportService.detectEncoding(sample))
          .decodeToString(sample, { stream: true });
        const title = file.ext === '.txt' ? /(?:^|\n)\s*(?:书名[：:]\s*|《)([^\n》]{1,120})/.exec(content) :
          /<title[^>]*>([^<]{1,120})<\/title\s*>/i.exec(content);
        const author = /(?:^|\n)\s*作者[：:]\s*([^\r\n]{1,80})/.exec(content);
        if (title !== null) result.title = title[1].trim();
        if (author !== null) result.author = author[1].trim();
      } finally { await fileIo.close(source); }
      return result;
    }
    if (file.ext !== '.epub') return result;
    result.directory = `${context.cacheDir}/book_preview_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    await fileIo.mkdir(result.directory, true);
    try {
      const size = await LocalBookImportService.fileSize(file.uri);
      if (size <= 0 || size > 512 * 1024 * 1024) throw new Error('Invalid EPUB size');
      await LocalBookImportService.requireSpace(context, size * 3);
      const archive = `${result.directory}/source.zip`;
      const epub = `${result.directory}/source.epub`;
      await LocalBookImportService.copyFile(file.uri, archive);
      const expanded = await zlib.getOriginalSize(archive);
      if (expanded > 2 * 1024 * 1024 * 1024) throw new Error('Invalid EPUB expanded size');
      await LocalBookImportService.requireSpace(context, expanded * 2);
      await fileIo.moveFile(archive, epub);
      const handler = await bookParser.getDefaultHandler(epub);
      const info = handler.getBookInfo();
      result.title = info.bookTitle || file.name;
      result.author = info.bookCreator || await LocalBookImportService.epubCreator(handler);
      result.cover = await EpubCoverService.extract(handler, result.directory);
      return result;
    } catch (error) {
      await fileIo.rmdir(result.directory).catch((): void => {});
      throw new Error(error instanceof Error ? error.message : 'EPUB preview failed');
    }
  }

  private static async epubMetadataText(handler: bookParser.BookParserHandler, path: string): Promise<string> {
    if (handler.getSpineList().length === 0) return '';
    await handler.getSpineItemContent(0);
    const parts = path.split('/');
    const candidates: string[] = [path];
    for (let index = 1; index < parts.length; index++) candidates.push(parts.slice(index).join('/'));
    for (let depth = 1; depth <= 8; depth++) candidates.push('../'.repeat(depth) + path);
    for (const candidate of candidates) {
      try {
        const bytes = handler.getResourceContent(0, candidate);
        if (bytes !== undefined && bytes.byteLength > 0 && bytes.byteLength <= 2 * 1024 * 1024) {
          return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
        }
      } catch (_e) { /* 尝试相对包根目录读取。 */ }
    }
    return '';
  }

  private static async epubCreator(handler: bookParser.BookParserHandler): Promise<string> {
    try {
      const container = await LocalBookImportService.epubMetadataText(handler, 'META-INF/container.xml');
      const root = /full-path\s*=\s*["']([^"']+)["']/i.exec(container);
      if (root === null) return '';
      const metadata = await LocalBookImportService.epubMetadataText(handler, root[1]);
      const creator = /<(?:[\w-]+:)?creator\b[^>]*>([\s\S]*?)<\/(?:[\w-]+:)?creator\s*>/i.exec(metadata);
      return creator === null ? '' : KkBiqugeHtmlParser.cleanContent(creator[1]).trim();
    } catch (_e) { return ''; }
  }

  static async requireSpace(context: common.Context, bytes: number): Promise<void> {
    const free = await statfs.getFreeSize(context.filesDir);
    if (!Number.isSafeInteger(bytes) || bytes < 0 || free < bytes + 256 * 1024 * 1024) {
      throw new Error('空间不足，请清理存储后重试（另需保留 256 MiB）');
    }
  }

  static async copyFile(uri: string, destination: string): Promise<void> {
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let target: fileIo.File | null = null;
    try {
      target = await fileIo.open(destination, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(source.fd, target.fd);
    } finally {
      if (target !== null) await fileIo.close(target);
      await fileIo.close(source);
    }
  }

  static async fileSize(uri: string): Promise<number> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try { return (await fileIo.stat(file.fd)).size; }
    finally { await fileIo.close(file); }
  }

  static async writeText(path: string, text: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(file.fd, text); }
    finally { await fileIo.close(file); }
  }

  /** 有上限的单章节文件，正文读取不需要在线书源。 */
  static async appendText(book: Book, directory: string, title: string, text: string): Promise<void> {
    let offset = 0;
    while (offset < text.length) {
      let end = Math.min(text.length, offset + 32000);
      if (end < text.length) {
        const newline = text.lastIndexOf('\n', end);
        if (newline > offset + 16000) end = newline;
        const code = text.charCodeAt(end - 1);
        if (code >= 0xD800 && code <= 0xDBFF) end--;
      }
      const content = text.substring(offset, end).trim();
      if (content.length > 0) {
        if (book.chapters.length >= LocalBookImportService.MAX_CHAPTERS) throw new Error('单书超过 50000 章');
        const index = book.chapters.length;
        const path = `${directory}/${index}.txt`;
        await LocalBookImportService.writeText(path, content);
        const chapter: Chapter = {
          id: `${book.id}-c${index}`, index: index + 1,
          title: offset === 0 ? title : `${title}（续）`, duration: 0,
          source: { type: 'file', value: path }
        };
        book.chapters.push(chapter);
      }
      offset = end;
    }
  }

  static htmlText(html: string): string {
    const body = /<body\b[^>]*>([\s\S]*?)<\/body\s*>/i.exec(html);
    return KkBiqugeHtmlParser.cleanContent(body ? body[1] : html);
  }

  static detectEncoding(sample: Uint8Array): string {
    if (sample[0] === 0xFF && sample[1] === 0xFE) return 'utf-16le';
    if (sample[0] === 0xFE && sample[1] === 0xFF) return 'utf-16be';
    if (sample[0] === 0xEF && sample[1] === 0xBB && sample[2] === 0xBF) return 'utf-8';
    try {
      util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(sample, { stream: true });
      return 'utf-8';
    } catch (_error) { return 'gb18030'; }
  }

  /** 64 KiB 流式读取 TXT；章节标题分段，无标题的长文按 32000 字符分段。 */
  private static async importText(book: Book, directory: string, uri: string,
    html: boolean, progress: (text: string) => void): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      const max = (html ? 32 : 256) * 1024 * 1024;
      if (size <= 0 || size > max) throw new Error(html ? 'HTML 需为 1 字节至 32 MiB' : 'TXT 需为 1 字节至 256 MiB');
      const buffer = new ArrayBuffer(65536);
      const firstLength = await fileIo.read(file.fd, buffer, { offset: 0, length: Math.min(buffer.byteLength, size) });
      const decoder = util.TextDecoder.create(LocalBookImportService.detectEncoding(new Uint8Array(buffer, 0, firstLength)));
      let offset = 0;
      let pending = '';
      let section = '';
      let title = book.title;
      let htmlContent = '';
      while (offset < size) {
        const count = await fileIo.read(file.fd, buffer, { offset: offset, length: Math.min(buffer.byteLength, size - offset) });
        if (count <= 0) throw new Error('文件读取中断');
        offset += count;
        const decoded = decoder.decodeToString(new Uint8Array(buffer, 0, count), { stream: offset < size });
        if (html) { htmlContent += decoded; continue; }
        pending += decoded.replace(/\r/g, '');
        const lines = pending.split('\n');
        pending = lines.pop() ?? '';
        for (const line of lines) {
          const trimmed = line.trim();
          if (/^(?:第[零〇一二三四五六七八九十百千万两\d]+[章节卷回部篇].{0,70}|chapter\s+\d+.{0,70}|序章|序言|楔子|尾声|后记)$/i.test(trimmed)) {
            await LocalBookImportService.appendText(book, directory, title, section);
            title = trimmed;
            section = '';
          }
          section += line + '\n';
          if (section.length >= 32000) {
            await LocalBookImportService.appendText(book, directory, title, section);
            section = '';
          }
        }
        if (pending.length >= 32000) {
          section += pending;
          pending = '';
          await LocalBookImportService.appendText(book, directory, title, section);
          section = '';
        }
        progress(`${book.title} ${Math.floor(offset * 100 / size)}%`);
      }
      await LocalBookImportService.appendText(book, directory, title,
        html ? LocalBookImportService.htmlText(htmlContent) : section + pending);
    } finally { await fileIo.close(file); }
  }

  static async importBook(context: common.Context, file: LocalImportFile, id: string,
    title: string, author: string, cover: string, progress: (text: string) => void): Promise<Book> {
    const directory = `${context.filesDir}/ebooks/${id}`;
    const book: Book = {
      id: id, contentType: 'text', title: title || file.name, author: author || '未知',
      narrator: '', cover: cover, category: 'import', intro: '本地电子书', totalDuration: 0,
      chapterCount: 0, rating: 0, tags: ['本地导入'], chapters: [],
      bookUrl: `local-text://${id}`, sourceUrl: ''
    };
    await fileIo.mkdir(directory, true);
    try {
      if (cover.length > 0) {
        const localCover = `${directory}/cover${cover.toLowerCase().endsWith('.png') ? '.png' : '.jpg'}`;
        await LocalBookImportService.copyFile(cover, localCover);
        book.cover = localCover;
      }
      const size = await LocalBookImportService.fileSize(file.uri);
      await LocalBookImportService.requireSpace(context, size * 3);
      if (file.ext === '.epub') {
        if (size > 512 * 1024 * 1024) throw new Error('EPUB 超过 512 MiB');
        const archive = `${directory}/source.zip`;
        const epub = `${directory}/source.epub`;
        await LocalBookImportService.copyFile(file.uri, archive);
        const expanded = await zlib.getOriginalSize(archive);
        if (expanded > 2 * 1024 * 1024 * 1024) throw new Error('EPUB 解压内容超过 2 GiB');
        await LocalBookImportService.requireSpace(context, expanded * 2);
        await fileIo.moveFile(archive, epub);
        const handler = await bookParser.getDefaultHandler(epub);
        const info = handler.getBookInfo();
        if (book.cover.length === 0) book.cover = await EpubCoverService.extract(handler, directory);
        if (!title && info.bookTitle) book.title = info.bookTitle;
        if (!author) book.author = info.bookCreator || await LocalBookImportService.epubCreator(handler) || book.author;
        const spine = handler.getSpineList();
        const catalog = handler.getCatalogList();
        if (spine.length > LocalBookImportService.MAX_CHAPTERS) throw new Error('EPUB 超过 50000 节');
        for (let index = 0; index < spine.length; index++) {
          progress(`${book.title} ${index + 1}/${spine.length}`);
          const label = catalog.find((item: bookParser.CatalogItem): boolean => item.idRef === spine[index].idRef);
          const html = await handler.getSpineItemContent(index);
          await LocalBookImportService.appendText(book, directory, label?.catalogName || `${book.title} ${index + 1}`,
            LocalBookImportService.htmlText(html));
        }
      } else {
        await LocalBookImportService.importText(book, directory, file.uri, file.ext !== '.txt', progress);
      }
      if (book.chapters.length === 0) throw new Error('没有可读取的文字章节');
      book.chapterCount = book.chapters.length;
      return book;
    } catch (error) {
      try { await fileIo.rmdir(directory); } catch (_cleanup) { /* 保留原始错误 */ }
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }
}
