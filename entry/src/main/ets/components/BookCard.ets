import { Book } from '../model/Book';
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';

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

  private static shownIds: Set<string> = new Set();

  aboutToAppear(): void {
    if (BookCard.shownIds.has(this.book.id)) {
      this.appeared = true;
      return;
    }
    BookCard.shownIds.add(this.book.id);
    // 仅前12个卡片有交错入场动画，后续直接显示，避免滑动时大量动画叠加掉帧
    if (this.indexHint < 12) {
      const delay = this.indexHint * 50;
      setTimeout(() => { this.appeared = true; }, delay);
    } else {
      this.appeared = true;
    }
  }

  static resetAnimations(): void {
    BookCard.shownIds.clear();
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
            .aspectRatio(0.75)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.app_icon_legacy'))
            .onError(() => {
              this.imageLoadFailed = true;
            })
        } else if (this.book.cover && this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(0.75)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .onError(() => { this.imageLoadFailed = true; })
        } else if (this.book.cover && !this.book.cover.startsWith('http') && !this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image($rawfile(this.book.cover))
            .width('100%')
            .aspectRatio(0.75)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
            .onError(() => { this.imageLoadFailed = true; })
        } else {
          // 无封面:用 app 图标占位(替代旧的绿色书形/品牌色占位)
          Image($r('app.media.app_icon_legacy'))
            .width('100%')
            .aspectRatio(0.75)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        }

        if (this.sourceName()) {
          Text(this.sourceName())
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#99000000')
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Md })
            .constraintSize({ maxWidth: '80%' })
        }
      }
      .width('100%')
      .borderRadius(AppRadius.Md)
      .clip(true)
      .shadow({ radius: 12, color: '#33000000', offsetY: 4 })

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
    .scale({
      x: this.pressed ? 0.96 : (this.appeared ? 1 : 0.92),
      y: this.pressed ? 0.96 : (this.appeared ? 1 : 0.92)
    })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 20 })
    .animation({ duration: AppMotion.Base, curve: AppCurve.Emphasized })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) this.pressed = true;
      else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressed = false;
    })
    .onClick(() => this.onTap(this.book.id))
  }
}
