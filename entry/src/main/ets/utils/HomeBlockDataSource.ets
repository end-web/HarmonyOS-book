import { HomeBlockSection } from '../model/BookSource';

export class HomeBlockDataSource implements IDataSource {
  private blocks: HomeBlockSection[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.blocks.length;
  }

  getData(index: number): HomeBlockSection {
    return this.blocks[index];
  }

  setBlocks(blocks: HomeBlockSection[]): void {
    this.blocks = blocks;
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  appendBlocks(newBlocks: HomeBlockSection[]): void {
    const start = this.blocks.length;
    this.blocks.push(...newBlocks);
    for (let i = start; i < this.blocks.length; i++) {
      this.listeners.forEach((l) => l.onDataAdd(i));
    }
  }

  clear(): void {
    this.blocks = [];
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
