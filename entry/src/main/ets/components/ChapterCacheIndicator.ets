import { common } from '@kit.AbilityKit';
import { Book, Chapter } from '../model/Book';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct ChapterCacheIndicator {
  @Param book: Book | null = null;
  @Param chapter: Chapter | null = null;
  @Local cached: boolean = false;
  private serial: number = 0;

  aboutToAppear(): void { this.refresh(); }
  aboutToDisappear(): void { this.serial++; }
  @Monitor('book', 'chapter')
  onChapterChanged(): void { this.refresh(); }

  private async refresh(): Promise<void> {
    const ticket = ++this.serial;
    this.cached = false;
    const book = this.book;
    const chapter = this.chapter;
    if (book === null || chapter === null) return;
    if (chapter.source.type === 'file' || chapter.source.type === 'rawfile') {
      this.cached = true;
    } else if (book.contentType === 'text') {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) return;
      const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
        chapter.originSourceValue ?? chapter.source.value);
      const cached = await OnlineTextContentCache.contains(context, key);
      if (ticket === this.serial) this.cached = cached;
    } else {
      this.cached = ChapterCacheService.getInstance().isAudioChapterCached(book, chapter);
    }
  }

  build() {
    SymbolGlyph(this.cached ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.cloud'))
      .fontSize(16).fontColor([this.cached ? AppColor.Brand : $r('sys.color.font_tertiary')])
      .accessibilityText(this.cached ? $r('app.string.chapter_downloaded') : $r('app.string.chapter_not_cached'))
  }
}
