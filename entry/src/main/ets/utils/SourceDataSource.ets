import { BookSource } from '../model/BookSource';

export class SourceDataSource implements IDataSource {
  private sources: BookSource[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.sources.length;
  }

  getData(index: number): BookSource {
    return this.sources[index];
  }

  setSources(sources: BookSource[]): void {
    this.sources = sources;
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  getAll(): BookSource[] {
    return this.sources;
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
