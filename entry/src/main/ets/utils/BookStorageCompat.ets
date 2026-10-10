import { Book } from '../model/Book';

/** 已发布版本的混淆映射；仅用于读取旧缓存，不作为新数据字段写入。 */
class LegacyBookMetadata {
  i36?: string;
  b40?: boolean;
  i40?: boolean;
  j40?: string;
}

export class BookStorageCompat {
  static restoreMetadata(book: Book): Book {
    // 只读取四个旧字段，避免复制可能含数千章的 chapters 数组。
    const legacy: LegacyBookMetadata = JSON.parse(JSON.stringify(book, ['i36', 'b40', 'i40', 'j40']));
    if (book.latestChapterTitle === undefined && typeof legacy.i36 === 'string') {
      book.latestChapterTitle = legacy.i36;
    }
    if (book.tocComplete === undefined && typeof legacy.b40 === 'boolean') {
      book.tocComplete = legacy.b40;
    }
    if (book.coverFromDetail === undefined && typeof legacy.i40 === 'boolean') {
      book.coverFromDetail = legacy.i40;
    }
    if (book.coverFallback === undefined && typeof legacy.j40 === 'string') {
      book.coverFallback = legacy.j40;
    }
    return book;
  }
}
