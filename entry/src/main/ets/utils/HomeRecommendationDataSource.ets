/** 首页横向书单的数据源；实例跨分类切换保留，仅在推荐数据返回时更新。 */
export class HomeRecommendationDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  setItems(items: T[]): void {
    this.items = items;
    for (const listener of this.listeners) listener.onDataReloaded();
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
