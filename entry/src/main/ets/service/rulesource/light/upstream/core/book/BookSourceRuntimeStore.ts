import { SourceEngineHost } from '../host/SourceEngineHost';
import { BookSource } from '../../model/data/Book';

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
  static forSource(source: BookSource): BookSourceRuntimePersistence | null {
    return SourceEngineHost.persistence(source) || this.persistence;
  }

  private static persistence: BookSourceRuntimePersistence | null = null;

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
