import { Book } from '../model/Book';

export class HomeCategoryBookRow {
  books: Book[];
  startIndex: number;
  key: string;

  constructor(books: Book[], startIndex: number) {
    this.books = books;
    this.startIndex = startIndex;
    this.key = books.map((book: Book): string => book.id).join('|');
  }
}

/** 按三本书分行，让 API 20 的 List 也能按可见行懒加载分类网格。 */
export class HomeCategoryRowDataSource implements IDataSource {
  private rows: HomeCategoryBookRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HomeCategoryBookRow {
    return this.rows[index];
  }

  setBooks(books: Book[]): void {
    const rows: HomeCategoryBookRow[] = [];
    for (let index: number = 0; index < books.length; index += 3) {
      rows.push(new HomeCategoryBookRow(books.slice(index, index + 3), index));
    }
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
