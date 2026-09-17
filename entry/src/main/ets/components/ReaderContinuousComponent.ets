import { AppColor } from '../theme/Theme';
import { ReaderPalette } from '../model/ReaderTheme';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { OnlineTextPaginator } from '../service/text/OnlineTextPaginator';
import { OnlineTextScrollChapter, OnlineTextScrollDataSource, OnlineTextScrollRow } from '../service/text/OnlineTextScrollDataSource';
import { ReaderSpeechText } from './ReaderSpeechText';

/** 按真实排版行懒加载的连续正文。只保留当前章附近内容，补章不替换可见正文。 */
@ComponentV2
export struct ReaderContinuousComponent {
  @Param revision: number = 0;
  @Param chapterIndex: number = 0;
  @Param content: string = '';
  @Param charOffset: number = 0;
  @Param chapterCount: number = 0;
  @Param chapterStep: number = 1;
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();
  @Param speechState: TextToSpeechState = new TextToSpeechState();
  @Param bookId: string = '';
  @Param followOffset: number = -1;
  @Param topGestureInset: number = 0;
  @Event getContent: (index: number) => Promise<string> = async (): Promise<string> => '';
  @Event getTitle: (index: number) => string = (): string => '';
  @Event getKey: (index: number) => string = (index: number): string => `${index}`;
  @Event onPosition: (chapter: number, offset: number, content: string, persist: boolean) => void = () => {};
  @Event onCenterTap: () => void = () => {};
  @Event onScrollStart: () => void = () => {};
  @Local previousLoading: boolean = false;
  @Local nextLoading: boolean = false;
  @Local previousFailed: boolean = false;
  @Local nextFailed: boolean = false;
  @Local rowHeight: number = 34.2;
  private source: OnlineTextScrollDataSource = new OnlineTextScrollDataSource();
  private scroller: Scroller = new Scroller();
  private chapters: OnlineTextScrollChapter[] = [];
  private contentWidth: number = 0;
  private firstVisible: number = 0;
  private lastVisible: number = 0;
  private serial: number = 0;
  private restoreTimer: number = -1;
  private restoring: boolean = false;
  private disposed: boolean = false;

  @Monitor('revision')
  onRevisionChanged(): void { this.reset(); }

  @Monitor('followOffset')
  onFollowChanged(): void {
    if (this.followOffset < 0 || this.restoring) return;
    const target = this.source.findPosition(this.chapterIndex, this.followOffset);
    if (target >= 0 && (target < this.firstVisible || target >= this.lastVisible)) {
      this.scroller.scrollToIndex(target, false, ScrollAlign.START);
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.serial++;
    if (this.restoreTimer !== -1) clearTimeout(this.restoreTimer);
  }

  private makeChapter(index: number, content: string): OnlineTextScrollChapter {
    const ui = this.getUIContext();
    const fontPx = ui.fp2px(this.fontSize);
    this.rowHeight = ui.px2vp(fontPx) * this.lineHeight;
    // 高度 1px 将测量结果按行输出；列表按像素连续滚动，不做分页吸附。
    const lines = OnlineTextPaginator.paginate(content, ui.vp2px(this.contentWidth), 1, fontPx, this.lineHeight);
    return OnlineTextScrollChapter.create(index, this.getKey(index), this.getTitle(index), content, lines);
  }

  private reset(): void {
    if (this.contentWidth <= 0 || this.disposed) return;
    const ticket = ++this.serial;
    if (this.restoreTimer !== -1) clearTimeout(this.restoreTimer);
    this.restoring = true;
    this.previousLoading = false;
    this.nextLoading = false;
    this.previousFailed = false;
    this.nextFailed = false;
    const chapter = this.makeChapter(this.chapterIndex, this.content);
    this.chapters = [chapter];
    this.source.reset(chapter.rows);
    const target = Math.max(0, this.source.findPosition(this.chapterIndex, this.charOffset));
    this.firstVisible = target;
    this.lastVisible = target;
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (this.disposed || ticket !== this.serial) return;
      this.scroller.scrollToIndex(target, false, ScrollAlign.START);
      this.restoring = false;
      this.loadNeighbor(false);
      this.loadNeighbor(true);
    }, 0);
  }

  private async loadNeighbor(forward: boolean): Promise<void> {
    if (this.disposed || this.restoring || this.chapters.length === 0 || this.chapters.length >= 5) return;
    if (forward ? this.nextLoading || this.nextFailed : this.previousLoading || this.previousFailed) return;
    const edge = this.chapters[forward ? this.chapters.length - 1 : 0];
    const index = edge.index + (forward ? this.chapterStep : -this.chapterStep);
    if (index < 0 || index >= this.chapterCount) return;
    const ticket = this.serial;
    if (forward) this.nextLoading = true;
    else this.previousLoading = true;
    try {
      const content = await this.getContent(index);
      if (ticket !== this.serial || this.disposed || this.chapters.length >= 5) return;
      const chapter = this.makeChapter(index, content);
      if (forward) {
        this.chapters.push(chapter);
        this.source.insert(this.source.totalCount(), chapter.rows);
      } else {
        this.chapters.unshift(chapter);
        this.firstVisible += chapter.rows.length;
        this.lastVisible += chapter.rows.length;
        this.source.insert(0, chapter.rows);
      }
    } catch (_error) {
      if (ticket !== this.serial || this.disposed) return;
      if (forward) this.nextFailed = true;
      else this.previousFailed = true;
    } finally {
      if (ticket === this.serial && !this.disposed) {
        if (forward) this.nextLoading = false;
        else this.previousLoading = false;
      }
    }
  }

  private reportPosition(persist: boolean): void {
    if (this.restoring || this.disposed) return;
    const row = this.source.getData(this.firstVisible);
    if (row === undefined) return;
    const chapter = this.chapters.find((item: OnlineTextScrollChapter): boolean => item.index === row.chapterIndex);
    if (chapter !== undefined) this.onPosition(row.chapterIndex, row.startOffset, chapter.content, persist);
  }

  private visibleChanged(first: number, last: number): void {
    if (this.restoring || first < 0) return;
    this.firstVisible = first;
    this.lastVisible = last;
    this.reportPosition(false);
    this.trimChapters();
    if (this.firstVisible < 24) this.loadNeighbor(false);
    if (this.lastVisible >= this.source.totalCount() - 24) this.loadNeighbor(true);
  }

  private trimChapters(): void {
    // 仅移除可见区之外的章节。增删通知配合 maintainVisibleContentPosition 保持视觉锚点。
    const first = this.source.getData(this.firstVisible);
    const last = this.source.getData(this.lastVisible);
    if (first === undefined || last === undefined) return;
    while (this.chapters.length > 3 &&
      Math.abs(this.chapters[0].index - first.chapterIndex) > 1 &&
      this.chapters[0].index !== last.chapterIndex) {
      const removed = this.chapters.shift();
      if (removed === undefined) break;
      this.firstVisible -= removed.rows.length;
      this.lastVisible -= removed.rows.length;
      this.source.remove(0, removed.rows.length);
    }
    while (this.chapters.length > 3 &&
      Math.abs(this.chapters[this.chapters.length - 1].index - last.chapterIndex) > 1 &&
      this.chapters[this.chapters.length - 1].index !== first.chapterIndex) {
      const removed = this.chapters.pop();
      if (removed === undefined) break;
      this.source.remove(this.source.totalCount() - removed.rows.length, removed.rows.length);
    }
  }

  private retry(forward: boolean): void {
    if (forward) this.nextFailed = false;
    else this.previousFailed = false;
    this.loadNeighbor(forward);
  }

  @Builder
  loadIndicator(forward: boolean): void {
    Row({ space: 6 }) {
      if (forward ? this.nextFailed : this.previousFailed) {
        Button($r('app.string.reader_scroll_retry'))
          .fontSize(12).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .onClick((): void => this.retry(forward))
      } else if (forward ? this.nextLoading : this.previousLoading) {
        LoadingProgress().width(20).height(20).color(AppColor.Brand)
      }
    }
    .padding(4)
    .align(forward ? Alignment.BottomEnd : Alignment.TopEnd)
  }

  build() {
    Stack() {
      List({ scroller: this.scroller, space: 0 }) {
        LazyForEach(this.source, (row: OnlineTextScrollRow) => {
          ListItem() {
            if (row.heading) {
              Text(row.text)
                .fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor(this.palette.primary)
                .width('100%').height(this.rowHeight * 2).maxLines(2)
            } else {
              ReaderSpeechText({
                text: row.text, source: row.source, sourceStart: row.startOffset,
                state: this.speechState, fontSize: this.fontSize, lineHeight: this.lineHeight, palette: this.palette,
                highlightEnabled: this.speechState.bookId === this.bookId && this.speechState.chapterIndex === row.chapterIndex
              })
                .width('100%').height(this.rowHeight)
            }
          }
        }, (row: OnlineTextScrollRow): string => row.key)
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .cachedCount(12)
      .maintainVisibleContentPosition(true)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width !== 'number' || size.width <= 0 || Math.abs(this.contentWidth - size.width) < 0.5) return;
        this.contentWidth = size.width;
        this.reset();
      })
      .onTouchIntercept((event: TouchEvent): HitTestMode => {
        const touch = event.touches[0];
        return touch !== undefined && touch.y < this.topGestureInset ? HitTestMode.None : HitTestMode.Default;
      })
      .onScrollIndex((first: number, last: number): void => this.visibleChanged(first, last))
      .onScrollStart((): void => { if (!this.restoring) this.onScrollStart(); })
      .onScrollStop((): void => this.reportPosition(true))
      .parallelGesture(TapGesture().onAction((event: GestureEvent): void => {
        const finger = event.fingerList[0];
        if (finger !== undefined && finger.localY >= this.topGestureInset &&
          finger.localX >= this.contentWidth * 0.3 && finger.localX <= this.contentWidth * 0.7) this.onCenterTap();
      }))
      this.loadIndicator(false)
      this.loadIndicator(true)
    }
    .width('100%').height('100%')
  }
}
