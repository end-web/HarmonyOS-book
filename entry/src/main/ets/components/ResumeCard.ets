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
    Row({ space: AppSpace.Sm }) {
      Text('card placeholder')
        .fontColor($r('sys.color.font_primary'))
        .fontSize(AppFont.Body)
    }
    .width('100%')
    .padding(AppSpace.Sm)
    .margin({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs })
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
  }
}
