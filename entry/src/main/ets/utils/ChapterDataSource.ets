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
