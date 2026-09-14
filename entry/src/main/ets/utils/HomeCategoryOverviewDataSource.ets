import { HomeSourceCategory } from '../service/rulesource/HomeSourceService';

export class HomeCategoryOverviewRow {
  categories: HomeSourceCategory[];
  startIndex: number;
  key: string;

  constructor(categories: HomeSourceCategory[], startIndex: number) {
    this.categories = categories;
    this.startIndex = startIndex;
    this.key = categories.map((category: HomeSourceCategory): string => category.url).join('|');
  }
}

/** 分类总览按双列分行，复用首页 List 的滚动、刷新和安全区。 */
export class HomeCategoryOverviewDataSource implements IDataSource {
  private rows: HomeCategoryOverviewRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HomeCategoryOverviewRow {
    return this.rows[index];
  }

  setCategories(categories: HomeSourceCategory[]): void {
    const rows: HomeCategoryOverviewRow[] = [];
    for (let index: number = 0; index < categories.length; index += 2) {
      rows.push(new HomeCategoryOverviewRow(categories.slice(index, index + 2), index));
    }
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
