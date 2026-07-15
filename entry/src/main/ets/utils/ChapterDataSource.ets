import { Chapter } from '../model/Book';

/**
 * 章节列表 LazyForEach 数据源
 * 用于 BookDetailPage / PlayerPage 的长章节列表，避免 ForEach 一次性创建所有 ListItem
 */
export class ChapterDataSource implements IDataSource {
  private chapters: Chapter[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.chapters.length;
  }

  getData(index: number): Chapter {
    return this.chapters[index];
  }

  setChapters(chapters: Chapter[]): void {
    this.chapters = chapters;
    this.notifyDataReloaded();
  }

  notifyDataReloaded(): void {
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

/**
 * 带原始索引的章节行（用于目录搜索过滤后保留原索引）
 */
export interface ChapterRow {
  ch: Chapter;
  idx: number;
}

/**
 * 章节行 LazyForEach 数据源（支持过滤）
 * 用于 ReaderPage 等需要搜索过滤的长章节目录
 */
export class ChapterRowDataSource implements IDataSource {
  private rows: ChapterRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): ChapterRow {
    return this.rows[index];
  }

  setRows(rows: ChapterRow[]): void {
    this.rows = rows;
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
