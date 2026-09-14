import { matrix4 } from '@kit.ArkUI';
import { SearchResult } from '../model/BookSource';
import { CoverImage } from './CoverImage';
import { AppRadius, AppSpace } from '../theme/Theme';

const HOME_COVER_SIDE_ANGLE: number = 55 * Math.PI / 180;

/** 将封面投影成向内收拢的梯形：外沿较高，靠近中间封面的内沿较短。 */
export function homeCoverPerspective(sizePx: number, relativePosition: number,
  offsetXPx: number = 0): matrix4.Matrix4Transit {
  const distance = Math.min(1, Math.abs(relativePosition));
  const inset = sizePx * (1 - Math.cos(distance * HOME_COVER_SIDE_ANGLE)) / 2;
  const outerTop = sizePx * distance * 0.15;
  const innerTop = sizePx * distance * 0.24;
  const outerBottom = sizePx * (1 - distance * 0.03);
  const innerBottom = sizePx * (1 - distance * 0.12);
  const leftSide = relativePosition < 0;
  return matrix4.identity().setPolyToPoly({
    src: [{ x: 0, y: 0 }, { x: sizePx, y: 0 }, { x: 0, y: sizePx }, { x: sizePx, y: sizePx }],
    dst: [
      { x: inset + offsetXPx, y: leftSide ? outerTop : innerTop },
      { x: sizePx - inset + offsetXPx, y: leftSide ? innerTop : outerTop },
      { x: inset + offsetXPx, y: leftSide ? outerBottom : innerBottom },
      { x: sizePx - inset + offsetXPx, y: leftSide ? innerBottom : outerBottom }
    ],
    srcIndex: 0,
    dstIndex: 0,
    pointCount: 4
  });
}

@ComponentV2
struct HomeCarouselCover {
  @Param book: SearchResult | undefined = undefined;
  @Param cardSize: number = 180;
  @Param viewportWidth: number = 336;
  @Param relativePosition: number = 0;
  @Event onOpen: () => void = () => {};

  private distance(): number {
    return Math.min(1, Math.abs(this.relativePosition));
  }

  private sideOffsetPx(): number {
    const sideWidth = this.cardSize * Math.cos(HOME_COVER_SIDE_ANGLE);
    // 两侧投影的外沿与轮播容器边缘对齐，沿用下方内容的页面边距。
    const sideDistance = Math.max(0, (this.viewportWidth - sideWidth) / 2);
    return this.getUIContext().vp2px(-Math.max(-1, Math.min(1, this.relativePosition)) *
      (this.cardSize - sideDistance));
  }

  build() {
    Stack() {
      Stack() {
        CoverImage({
          url: this.book?.coverUrl ?? '',
          imgWidth: '100%',
          imgHeight: this.cardSize,
          useFixedHeight: true,
          radius: AppRadius.Md,
          decodeW: 600,
          decodeH: 600
        })
      }
      .width('100%').height(this.cardSize)
      .borderRadius(AppRadius.Md)
      .shadow({ radius: 18, color: '#40000000', offsetY: 8 })
      .scale({ centerX: 0, centerY: 0, x: 1, y: 1 })
      .transform3D(homeCoverPerspective(this.getUIContext().vp2px(this.cardSize), this.relativePosition,
        this.sideOffsetPx()))
      .opacity(1 - this.distance() * 0.2)
    }
    // Swiper 只负责外层页面布局，封面的尺寸和透视由内层节点保持。
    .width('100%').height(this.cardSize + 28)
    .zIndex(Math.round(10 - this.distance() * 5))
    .accessibilityGroup(true)
    .accessibilityText(this.book?.name ?? '')
    .accessibilityDescription($r('app.string.home_carousel_open'))
    .onClick(() => this.onOpen())
  }
}

/** 推荐封面轮播：使用 Swiper 的滑动进度驱动层次变化，不创建额外定时器。 */
@ComponentV2
export struct HomeCoverCarousel {
  @Param books: SearchResult[] = [];
  @Event onBookTap: (book: SearchResult) => void = () => {};
  @Local activeIndex: number = 0;
  @Local scrollIndex: number = 0;
  @Local scrollOffset: number = 0;
  @Local contentWidth: number = 336;
  @Local inViewport: boolean = false;

  @Monitor('books')
  private resetSelection(): void {
    this.activeIndex = 0;
    this.scrollIndex = 0;
    this.scrollOffset = 0;
  }

  private coverSize(): number {
    return Math.min(216, Math.max(144, this.contentWidth * 0.52));
  }

  private itemPosition(index: number): number {
    let distance = index - this.scrollIndex;
    // 两本时不循环，避免同一本同时出现在 Swiper 的前后两侧。
    if (this.books.length > 2) {
      const count = this.books.length;
      if (distance > count / 2) distance -= count;
      if (distance < -count / 2) distance += count;
    }
    return distance + this.scrollOffset;
  }

  private currentBook(): SearchResult | undefined {
    return this.books[this.activeIndex] ?? this.books[0];
  }

  private openCurrentBook(): void {
    const book = this.currentBook();
    if (book !== undefined) this.onBookTap(book);
  }

  build() {
    Column() {
      Swiper() {
        ForEach(this.books, (book: SearchResult, index: number) => {
          HomeCarouselCover({
            book: book,
            cardSize: this.coverSize(),
            viewportWidth: this.contentWidth,
            relativePosition: this.itemPosition(index),
            onOpen: () => this.onBookTap(book)
          })
        }, (book: SearchResult) => `${book.sourceUrl}#${book.bookUrl}`)
      }
      .width('100%').height(this.coverSize() + 28)
      .index(this.activeIndex)
      .displayCount(1)
      .prevMargin((this.contentWidth - this.coverSize()) / 2)
      .nextMargin((this.contentWidth - this.coverSize()) / 2)
      .loop(this.books.length > 2)
      .autoPlay(this.books.length > 1 && this.inViewport, { stopWhenTouched: true })
      .interval(4500).duration(550).curve(Curve.EaseInOut)
      .indicator(false)
      .onContentDidScroll((selectedIndex: number, index: number, position: number) => {
        if (index !== selectedIndex) return;
        this.scrollIndex = selectedIndex;
        this.scrollOffset = position;
      })
      .onChange((index: number) => {
        this.activeIndex = index;
        this.scrollIndex = index;
        this.scrollOffset = 0;
      })

      Text(this.currentBook()?.name ?? '')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%').textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        .onClick(() => this.openCurrentBook())
    }
    .width('100%').padding({ bottom: AppSpace.Xs })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      const width = Number(newSize.width);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 1) {
        this.contentWidth = width;
      }
    })
    .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number) => {
      this.inViewport = visible && ratio >= 0.5;
    })
  }
}
