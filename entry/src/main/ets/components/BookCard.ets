import { Book } from '../model/Book';
import { AppColor, AppRadius, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';

/**
 * 书架卡片：封面 + 标题 + 作者
 * 点击进入详情；按压有微缩反馈；封面通过 geometryTransition 飞向详情页
 */
@ComponentV2
export struct BookCard {
  @Param book: Book = {} as Book;
  @Param cardWidth: number = 110;
  @Param indexHint: number = 0;
  @Event onTap: (id: string) => void = () => {};

  @Local pressed: boolean = false;
  @Local imageLoadFailed: boolean = false;
  @Local appeared: boolean = false;

  aboutToAppear(): void {
    const delay = Math.min(this.indexHint, 8) * 35;
    setTimeout(() => { this.appeared = true; }, delay);
  }

  private firstChar(): string {
    return this.book.title ? this.book.title.substring(0, 1) : '?';
  }

  private sourceName(): string {
    if (this.book.narrator) return this.book.narrator;
    if (this.book.tags && this.book.tags.length > 0) return this.book.tags[0];
    return '';
  }

  private isLocalFile(path: string): boolean {
    return path.startsWith('/data/') || path.startsWith('file://');
  }

  build() {
    Column({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.book.cover && this.book.cover.startsWith('http') && !this.imageLoadFailed) {
          Image(this.book.cover)
            .width('100%')
            .aspectRatio(0.7)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.startIcon'))
            .onError(() => {
              this.imageLoadFailed = true;
            })
        } else if (this.book.cover && this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(0.7)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .onError(() => { this.imageLoadFailed = true; })
        } else if (this.book.cover && !this.book.cover.startsWith('http') && !this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image($rawfile(this.book.cover))
            .width('100%')
            .aspectRatio(0.7)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .onError(() => { this.imageLoadFailed = true; })
        } else {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(AppColor.Brand)
              .borderRadius(AppRadius.Md)
            Text(this.firstChar())
              .fontSize(36)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .aspectRatio(0.7)
          .borderRadius(AppRadius.Md)
          .clip(true)
        }

        if (this.sourceName()) {
          Text(this.sourceName())
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#99000000')
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Md })
        }
      }
      .width('100%')
      .borderRadius(AppRadius.Md)
      .clip(true)
      .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
      .geometryTransition('book-cover-' + this.book.id, { follow: true })

      Column({ space: 2 }) {
        Text(this.book.title)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.book.author)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 12 })
    .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) this.pressed = true;
      else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressed = false;
    })
    .onClick(() => this.onTap(this.book.id))
  }
}
