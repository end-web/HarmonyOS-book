import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct FavoritePage {
  @Local favoriteBooks: Book[] = [];
  @Local historyMap: Record<string, PlayHistoryItem> = {};
  @Local loading: boolean = true;
  @Param visible: boolean = false;
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onBookTap: (id: string) => void = () => {};
  @Event onGotoStore: () => void = () => {};

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadFavorites();
  }

  @Monitor('visible')
  onVisibleChange(): void {
    if (this.visible) {
      this.loadFavorites();
    }
  }

  async loadFavorites(): Promise<void> {
    const ids = await PreferenceService.getFavorites();
    const allBooks = await DataService.getBooks(this.context);
    this.favoriteBooks = allBooks.filter((b) => ids.includes(b.id));
    const history = await PreferenceService.getHistory();
    const map: Record<string, PlayHistoryItem> = {};
    for (const item of history) {
      if (!map[item.bookId]) {
        map[item.bookId] = item;
      }
    }
    this.historyMap = map;
    this.loading = false;
  }

  private getProgressText(book: Book): string {
    const unit = book.category === 'novel' ? '章' : '集';
    const h = this.historyMap[book.id];
    if (h && book.chapterCount > 0) {
      const chapters = book.chapters;
      const idx = chapters.findIndex(c => c.id === h.chapterId);
      if (idx >= 0) {
        return `${idx + 1}${unit}/${book.chapterCount}${unit}`;
      }
      return `共${book.chapterCount}${unit}`;
    }
    if (book.chapterCount > 0) {
      return `共${book.chapterCount}${unit}`;
    }
    return book.author || '';
  }

  private hasHistory(book: Book): boolean {
    return !!this.historyMap[book.id];
  }

  private handleBookTap(book: Book): void {
    const history = this.historyMap[book.id];
    if (!history) {
      this.navStack.pushPathByName('detail', book.id);
      return;
    }
    if (book.category === 'novel') {
      const idx = book.chapters.findIndex(c => c.id === history.chapterId);
      const chapterIndex = idx >= 0 ? idx : 0;
      const bookIdObj: Object = book.id as Object;
      const indexObj: Object = chapterIndex as Object;
      const params: Record<string, Object> = { 'bookId': bookIdObj, 'chapterIndex': indexObj };
      this.navStack.pushPathByName('TextReaderPage', params);
    } else {
      this.navStack.pushPathByName('player', book.id);
    }
  }

  private confirmDelete(book: Book): void {
    const isLocal = book.id.startsWith('import_');
    if (isLocal) {
      promptAction.showDialog({
        title: '移除书籍',
        message: `"${book.title}"是本地导入的书籍`,
        buttons: [
          { text: '取消', color: '#8F8F8F' },
          { text: '仅移除书架', color: '#333333' },
          { text: '删除本地文件', color: '#FF4444' }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.doRemove(book.id, false);
        } else if (result.index === 2) {
          this.doRemove(book.id, true);
        }
      });
    } else {
      promptAction.showDialog({
        title: '移除书籍',
        message: `确认从书架移除"${book.title}"？`,
        buttons: [
          { text: '取消', color: '#8F8F8F' },
          { text: '移除', color: '#FF4444' }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.doRemove(book.id, false);
        }
      });
    }
  }

  private async doRemove(bookId: string, deleteFiles: boolean): Promise<void> {
    if (deleteFiles) {
      const novelDir = this.context.filesDir + '/novel/' + bookId;
      const audioDir = this.context.filesDir + '/audio/' + bookId;
      try { await fileIo.rmdir(novelDir); } catch (_e) { /* not exists */ }
      try { await fileIo.rmdir(audioDir); } catch (_e) { /* not exists */ }
      await DataService.removeImportedBook(bookId);
    }
    await PreferenceService.toggleFavorite(bookId);
    await this.loadFavorites();
  }

  build() {
    Column() {
      Text('书架')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .padding({ left: AppSpace.Md, top: WindowUtils.getStatusBarHeightVp() + AppSpace.Lg, bottom: AppSpace.Md })

      Grid() {
        ForEach(this.favoriteBooks, (book: Book) => {
          GridItem() {
            this.buildBookTile(book)
          }
        }, (book: Book) => book.id)
        GridItem() {
          this.buildAddTile()
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(AppSpace.Sm)
      .rowsGap(AppSpace.Md)
      .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: 160 })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildBookTile(book: Book) {
    Column({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (book.cover && book.cover.startsWith('http')) {
          Image(book.cover)
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.startIcon'))
        } else if (book.cover && (book.cover.startsWith('/data/') || book.cover.startsWith('file://'))) {
          Image('file://' + book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        } else if (book.cover) {
          Image($rawfile(book.cover))
            .width('100%')
            .aspectRatio(0.72)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(AppColor.Brand)
              .borderRadius(AppRadius.Md)
            Text(book.title ? book.title.substring(0, 1) : '?')
              .fontSize(36)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .aspectRatio(0.72)
          .borderRadius(AppRadius.Md)
          .clip(true)
        }
      }
      .width('100%')
      .borderRadius(AppRadius.Md)
      .clip(true)
      .shadow({ radius: 8, color: '#22000000', offsetY: 3 })

      Text(book.title)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.getProgressText(book))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .width('100%')
    }
    .onClick(() => this.handleBookTap(book))
    .gesture(
      LongPressGesture({ repeat: false, duration: 600 })
        .onAction(() => {
          this.confirmDelete(book);
        })
    )
  }

  @Builder
  buildAddTile() {
    Column({ space: AppSpace.Xs }) {
      Column() {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(32)
          .fontColor(['#CCCCCC'])
        Text('去书城寻好书')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: AppSpace.Xs })
      }
      .width('100%')
      .aspectRatio(0.72)
      .borderRadius(AppRadius.Md)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#F5F5F5')
      .border({ width: 1, color: '#E0E0E0', style: BorderStyle.Dashed })

      Text(' ')
        .fontSize(AppFont.Body)
        .width('100%')
      Text(' ')
        .fontSize(AppFont.Caption)
        .width('100%')
    }
    .onClick(() => this.onGotoStore())
  }
}
