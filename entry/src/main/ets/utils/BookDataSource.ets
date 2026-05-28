import { Book } from '../model/Book';

/**
 * LazyForEach 通用数据源
 * 长列表性能基础设施，禁用 index 作为 key
 */
export class BookDataSource implements IDataSource {
  private books: Book[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.books.length;
  }

  getData(index: number): Book {
    return this.books[index];
  }

  setBooks(books: Book[]): void {
    this.books = books;
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  appendBooks(newBooks: Book[]): void {
    const start = this.books.length;
    this.books.push(...newBooks);
    for (let i = start; i < this.books.length; i++) {
      this.listeners.forEach((l) => l.onDataAdd(i));
    }
  }

  clear(): void {
    this.books = [];
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}
