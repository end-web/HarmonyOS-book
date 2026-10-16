import { BookSource } from '../../model/data/Book';
import { SourceEngineHost } from '../host/SourceEngineHost';

/**
 * Persistence the host app provides for book-source runtime state (variable/login header/login info).
 * The engine never opens the app database itself; until a host installs an implementation, reads
 * return null and writes are skipped, which matches the behaviour of an uninitialized database.
 */
export interface BookSourceRuntimePersistence {
  getBookSource(bookSourceUrl: string): Promise<BookSource | null>;
  updateBookSourceLoginRuntime(bookSourceUrl: string, variable: string, loginHeader: string,
    loginInfo: string): Promise<void>;
}

export class BookSourceRuntimeStore {
  private static persistence: BookSourceRuntimePersistence | null = null;

  /** 宿主按书源提供的持久化优先，其次是启动时 install 的全局实现；都没有时返回 null。 */
  static forSource(source: BookSource): BookSourceRuntimePersistence | null {
    return SourceEngineHost.persistence(source) || BookSourceRuntimeStore.persistence;
  }

  static install(persistence: BookSourceRuntimePersistence): void {
    BookSourceRuntimeStore.persistence = persistence;
  }

  static async getBookSource(bookSourceUrl: string): Promise<BookSource | null> {
    const persistence = BookSourceRuntimeStore.persistence;
    return persistence ? persistence.getBookSource(bookSourceUrl) : null;
  }

  static async updateLoginRuntime(bookSourceUrl: string, variable: string, loginHeader: string,
    loginInfo: string): Promise<void> {
    const persistence = BookSourceRuntimeStore.persistence;
    if (persistence) await persistence.updateBookSourceLoginRuntime(bookSourceUrl, variable, loginHeader, loginInfo);
  }
}
