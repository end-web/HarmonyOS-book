/**
 * 阅读页段落 LazyForEach 数据源。
 */
export class TextParagraphDataSource implements IDataSource {
  private paragraphs: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.paragraphs.length;
  }

  getData(index: number): string {
    return this.paragraphs[index];
  }

  setParagraphs(paragraphs: string[]): void {
    this.paragraphs = paragraphs;
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
