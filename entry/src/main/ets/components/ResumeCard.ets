import { Book } from '../model/Book';
import { AppFont, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';

export enum ResumeCardMode {
  Empty = 0,
  Resume = 1,
  Suggest = 2,
}

@ComponentV2
export struct ResumeCard {
  @Param mode: ResumeCardMode = ResumeCardMode.Empty;
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';
  @Param progress: number = 0;
  @Event onTapBody: () => void = () => {};
  @Event onTapPlay: () => void = () => {};

  build() {
    if (this.mode === ResumeCardMode.Empty || this.book === null) {
      Column().height(0).width(0)
    } else {
      this.cardBuilder()
    }
  }

  @Builder
  cardBuilder() {
    Row({ space: AppSpace.Md }) {
      this.coverBuilder()

      Column({ space: 4 }) {
        Text(this.modeLabel())
          .fontSize(AppFont.Caption)
          .fontColor(HomeTheme.Accent)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(1)

        Text(this.book?.title ?? '')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.subtitle())
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.mode === ResumeCardMode.Resume) {
          Stack({ alignContent: Alignment.Start }) {
            Column()
              .width('100%')
              .height(3)
              .borderRadius(2)
              .backgroundColor(HomeTheme.ProgressTrack)
            Column()
              .width(`${Math.max(0, Math.min(1, this.progress)) * 100}%`)
              .height(3)
              .borderRadius(2)
              .backgroundColor(HomeTheme.Accent)
          }
          .width('100%')
          .margin({ top: 6 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Stack() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(14)
          .fontColor([Color.White])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(HomeTheme.Accent)
      .shadow({ radius: 8, color: HomeTheme.CardShadow, offsetY: 2 })
      .onClick(() => this.onTapPlay())
    }
    .width('100%')
    .padding(AppSpace.Sm)
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
    .shadow({ radius: 14, color: HomeTheme.CardShadow, offsetY: 4 })
    .onClick(() => this.onTapBody())
  }

  @Builder
  coverBuilder() {
    if (this.book?.cover && this.book.cover.startsWith('http')) {
      Image(this.book.cover)
        .width(44)
        .height(60)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
        // 与列表统一 300x400,共享同一份解码缓存(原 150x200 会独立解码一份)
        .sourceSize({ width: 300, height: 400 })
    } else if (this.book?.cover && (this.book.cover.startsWith('/') || this.book.cover.startsWith('file://'))) {
      // 本地导入书的封面此前落到首字占位,补齐本地文件分支(判断与 BookCard.isLocalFile 对齐)
      Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
        .width(44)
        .height(60)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 400 })
        .syncLoad(true)
    } else {
      Stack() {
        Column().width('100%').height('100%').backgroundColor(HomeTheme.Accent)
        Text(this.book?.title ? this.book.title.substring(0, 1) : '?')
          .fontSize(18)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width(44)
      .height(60)
      .borderRadius(6)
      .clip(true)
    }
  }

  private modeLabel(): string {
    if (this.mode === ResumeCardMode.Resume) return '继续收听';
    if (this.mode === ResumeCardMode.Suggest) return '今日推荐';
    return '';
  }

  private subtitle(): string {
    if (this.mode === ResumeCardMode.Resume) {
      return this.chapterTitle || '继续上次播放';
    }
    if (this.mode === ResumeCardMode.Suggest && this.book) {
      const author: string = this.book.author || '未知';
      const narrator: string | undefined = this.book.narrator;
      return narrator ? `${author} · ${narrator}` : author;
    }
    return '';
  }
}
