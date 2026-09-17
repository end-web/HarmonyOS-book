import { OnlineTextPage } from './OnlineTextPaginator';

/** 连续阅读的可见行；字符偏移沿用原始正文，键不依赖列表位置。 */
export class OnlineTextScrollRow {
  key: string = '';
  chapterIndex: number = 0;
  startOffset: number = 0;
  endOffset: number = 0;
  text: string = '';
  source: string = '';
  heading: boolean = false;
}

export class OnlineTextScrollChapter {
  index: number = 0;
  content: string = '';
  rows: OnlineTextScrollRow[] = [];

  static create(index: number, key: string, title: string, content: string,
    lines: OnlineTextPage[]): OnlineTextScrollChapter {
    const chapter = new OnlineTextScrollChapter();
    chapter.index = index;
    chapter.content = content;
    const heading = new OnlineTextScrollRow();
    heading.key = `${key}:heading`;
    heading.chapterIndex = index;
    heading.text = title;
    heading.heading = true;
    chapter.rows.push(heading);
    for (const line of lines) {
      const row = new OnlineTextScrollRow();
      row.key = `${key}:${line.startOffset}:${line.endOffset}`;
      row.chapterIndex = index;
      row.startOffset = line.startOffset;
      row.endOffset = line.endOffset;
      // 换行由相邻 ListItem 表达，不在每行末尾额外增加一个空行。
      row.text = line.text.replace(new RegExp('\\n$'), '');
      row.source = content.substring(line.startOffset, line.endOffset);
      chapter.rows.push(row);
    }
    return chapter;
  }
}

export class OnlineTextScrollDataSource implements IDataSource {
  private rows: OnlineTextScrollRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): OnlineTextScrollRow { return this.rows[index]; }
  reset(rows: OnlineTextScrollRow[]): void {
    this.rows = rows.slice();
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  insert(index: number, rows: OnlineTextScrollRow[]): void {
    for (let offset = 0; offset < rows.length; offset++) {
      const position = index + offset;
      this.rows.splice(position, 0, rows[offset]);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(position));
    }
  }
  remove(index: number, count: number): void {
    for (let offset = 0; offset < count; offset++) {
      this.rows.splice(index, 1);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(index));
    }
  }
  findPosition(chapterIndex: number, offset: number): number {
    let last = -1;
    for (let index = 0; index < this.rows.length; index++) {
      const row = this.rows[index];
      if (row.chapterIndex !== chapterIndex || row.heading) continue;
      last = index;
      if (offset < row.endOffset || row.endOffset === 0) return index;
    }
    return last;
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
