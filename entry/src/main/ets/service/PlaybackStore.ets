/**
 * PlaybackStore: 跨页面"当前正在播什么"信号源。
 *
 * 不持久化,不持有 AVPlayer,只暴露查询。
 * AudioService 是唯一写入方,所有页面只读,避免引用比较的不一致
 * (例如 FavoritePage 列表里的 Book 与 state.currentBook 是不同对象但 id 相同)。
 *
 * 路由层依赖此 store 决定"点击书 A 是否打断当前播放":
 *   - isCurrentBook(bookId) → true: 直接进 PlayerPage 不重置
 *   - 否则: 走详情或带 chapterId 续播
 */
export class PlaybackStore {
  private static _instance: PlaybackStore | null = null;

  private _bookId: string = '';
  private _chapterId: string = '';
  private _chapterIndex: number = -1;
  private _sourceUrl: string = '';
  private _isPlaying: boolean = false;

  static getInstance(): PlaybackStore {
    if (!PlaybackStore._instance) {
      PlaybackStore._instance = new PlaybackStore();
    }
    return PlaybackStore._instance;
  }

  /** AudioService 内部用：切书/切章节/seek/暂停后同步 */
  update(bookId: string, chapterId: string, chapterIndex: number, sourceUrl: string, isPlaying: boolean): void {
    this._bookId = bookId;
    this._chapterId = chapterId;
    this._chapterIndex = chapterIndex;
    this._sourceUrl = sourceUrl;
    this._isPlaying = isPlaying;
  }

  setPlaying(isPlaying: boolean): void {
    this._isPlaying = isPlaying;
  }

  clear(): void {
    this._bookId = '';
    this._chapterId = '';
    this._chapterIndex = -1;
    this._sourceUrl = '';
    this._isPlaying = false;
  }

  isCurrentBook(bookId: string): boolean {
    return !!this._bookId && this._bookId === bookId;
  }

  isCurrentChapter(bookId: string, chapterId: string): boolean {
    return this.isCurrentBook(bookId) && !!this._chapterId && this._chapterId === chapterId;
  }

  isSameSourceUrl(url: string): boolean {
    return !!this._sourceUrl && this._sourceUrl === url;
  }

  isPlayingNow(): boolean {
    return this._isPlaying;
  }

  getCurrentBookId(): string {
    return this._bookId;
  }

  getCurrentChapterId(): string {
    return this._chapterId;
  }

  getCurrentChapterIndex(): number {
    return this._chapterIndex;
  }

  getCurrentSourceUrl(): string {
    return this._sourceUrl;
  }
}
