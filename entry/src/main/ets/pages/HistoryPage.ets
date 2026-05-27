import { common } from '@kit.AbilityKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { WindowUtils } from '../utils/WindowUtils';

interface HistoryEntry {
  book: Book;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  progressMs: number;
  updatedAt: number;
  isNovel: boolean;
}

@ComponentV2
export struct HistoryPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local entries: HistoryEntry[] = [];
  @Local loading: boolean = true;

  private context!: common.UIAbilityContext;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    const items = await PreferenceService.getHistory();
    const allBooks = await DataService.getBooks(this.context);
    const results: HistoryEntry[] = [];
    for (const item of items) {
      const book = allBooks.find((b) => b.id === item.bookId);
      if (!book) continue;
      const chIdx = book.chapters.findIndex((c) => c.id === item.chapterId);
      const ch = chIdx >= 0 ? book.chapters[chIdx] : null;
      const isNovel = book.category === 'novel';
      results.push({
        book: book,
        chapterId: item.chapterId,
        chapterTitle: ch ? ch.title : '未知章节',
        chapterIndex: chIdx >= 0 ? chIdx : 0,
        progressMs: item.progressMs,
        updatedAt: item.updatedAt,
        isNovel: isNovel
      });
    }
    this.entries = results;
    this.loading = false;
  }

  private formatTime(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return m + '分' + (s > 0 ? s + '秒' : '');
  }

  private formatDate(ts: number): string {
    const d = new Date(ts);
    const month = d.getMonth() + 1;
    const day = d.getDate();
    const h = d.getHours();
    const min = d.getMinutes();
    return month + '/' + day + ' ' + (h < 10 ? '0' : '') + h + ':' + (min < 10 ? '0' : '') + min;
  }

  private handleEntryClick(entry: HistoryEntry): void {
    if (entry.isNovel) {
      const params: Record<string, Object> = {
        'bookId': entry.book.id,
        'chapterIndex': entry.chapterIndex
      };
      this.navStack.pushPathByName('TextReaderPage', params);
    } else {
      const params: Record<string, Object> = {
        'bookId': entry.book.id,
        'chapterId': entry.chapterId,
        'progressMs': entry.progressMs
      };
      this.navStack.pushPathByName('player', params);
    }
  }

  private async deleteEntry(entry: HistoryEntry): Promise<void> {
    await PreferenceService.removeHistory(entry.book.id);
    this.loadHistory();
  }

  @Builder
  buildDeleteBtn(entry: HistoryEntry) {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(60)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FF4D4F')
    .borderRadius(AppRadius.Md)
    .onClick(() => this.deleteEntry(entry))
  }

  @Builder
  buildEntryRow(entry: HistoryEntry) {
    Row({ space: AppSpace.Md }) {
      if (entry.book.cover && entry.book.cover.startsWith('http')) {
        Image(entry.book.cover)
          .width(50).height(50)
          .borderRadius(AppRadius.Sm)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph(entry.isNovel ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_tertiary')])
        }
        .width(50).height(50)
        .borderRadius(AppRadius.Sm)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text(entry.book.title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.chapterTitle)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.buildProgressText(entry) + ' · ' + this.formatDate(entry.updatedAt))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Md)
    .onClick(() => this.handleEntryClick(entry))
  }

  private buildProgressText(entry: HistoryEntry): string {
    if (entry.isNovel) {
      return '读到 ' + entry.chapterTitle;
    }
    return '听到 ' + this.formatTime(entry.progressMs);
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('历史记录')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: AppSpace.Sm })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm
      })

      if (this.entries.length === 0 && !this.loading) {
        Column({ space: AppSpace.Md }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(56)
            .fontColor(['#CCCCCC'])
          Text('暂无记录')
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_secondary'))
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
      } else {
        List({ space: AppSpace.Xs }) {
          ForEach(this.entries, (entry: HistoryEntry) => {
            ListItem() {
              this.buildEntryRow(entry)
            }
            .swipeAction({ end: () => { this.buildDeleteBtn(entry) } })
          }, (entry: HistoryEntry) => entry.book.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
