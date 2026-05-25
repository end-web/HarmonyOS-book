import { common } from '@kit.AbilityKit';
import { Book } from '../model/Book';
import { PreferenceService } from './PreferenceService';

/**
 * 数据服务：只承载本地导入的书。
 * 在线源走 BookSourceService（待新引擎接入）。
 */
export class DataService {
  private static cache: Book[] | null = null;

  private static async load(): Promise<Book[]> {
    if (DataService.cache) return DataService.cache;
    DataService.cache = await DataService.getImportedBooks();
    return DataService.cache;
  }

  static async getBooks(_context: common.UIAbilityContext): Promise<Book[]> {
    return await DataService.load();
  }

  static async getBookById(_context: common.UIAbilityContext, id: string): Promise<Book | undefined> {
    const list = await DataService.load();
    return list.find((b) => b.id === id);
  }

  static async getImportedBooks(): Promise<Book[]> {
    try {
      const json = await PreferenceService.getImportedBooks();
      return JSON.parse(json) as Book[];
    } catch (_e) {
      return [];
    }
  }

  static async addImportedBook(book: Book): Promise<void> {
    const list = await DataService.getImportedBooks();
    list.unshift(book);
    await PreferenceService.saveImportedBooks(JSON.stringify(list));
    DataService.cache = list;
  }

  static async removeImportedBook(bookId: string): Promise<void> {
    const list = await DataService.getImportedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    await PreferenceService.saveImportedBooks(JSON.stringify(filtered));
    DataService.cache = filtered;
  }
}
