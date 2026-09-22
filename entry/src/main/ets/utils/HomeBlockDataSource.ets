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
    const previous = this.blocks;
    // 分类分批完成时只插入新增项，不重建已挂载的横向列表和 Swiper。
    if (previous.length > 0 && previous.every((block: HomeBlockSection): boolean => blocks.includes(block))) {
      this.blocks = blocks;
      for (let index = 0; index < blocks.length; index++) {
        if (!previous.includes(blocks[index])) {
          for (const listener of this.listeners.slice()) listener.onDataAdd(index);
        }
      }
      return;
    }
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
