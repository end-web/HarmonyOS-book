import { AttributeUpdater, matrix4 } from '@kit.ArkUI';
import { SearchResult } from '../model/BookSource';
import { CoverImage } from './CoverImage';
import { AppRadius } from '../theme/Theme';

const HOME_COVER_SIDE_ANGLE: number = 55 * Math.PI / 180;
const HOME_COVER_SIDE_WIDTH_RATIO: number = Math.cos(HOME_COVER_SIDE_ANGLE);
const HOME_COVER_VERTICAL_SPACE: number = 20;

export function homeCoverSize(contentWidth: number): number {
  return Math.min(216, Math.max(144, contentWidth * 0.52));
}

/** 与轮播实际布局共用，供导航标题栏及列表占位计算完整高度。 */
export function homeCoverCarouselHeight(contentWidth: number): number {
  return homeCoverSize(contentWidth) + HOME_COVER_VERTICAL_SPACE;
}

/** 中间封面到侧封面的距离，真实轮播和骨架共用。 */
export function homeCoverSideDistance(contentWidth: number): number {
  return Math.max(0, (contentWidth - homeCoverSize(contentWidth) * HOME_COVER_SIDE_WIDTH_RATIO) / 2);
}

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

/** 仅在中间封面交接时调整层级，避免滑动途中反复重排。 */
class HomeCoverLayer extends AttributeUpdater<StackAttribute> {
  private front: boolean = true;

  initializeModifier(instance: StackAttribute): void {
    instance.zIndex(this.front ? 10 : 5);
  }

  setFront(front: boolean): void {
    if (this.front === front) return;
    this.front = front;
    this.attribute?.zIndex(front ? 10 : 5);
  }
}

/** 每张封面独立直通更新绘制属性，不经过父组件的状态更新与 ForEach。 */
class HomeCoverMotion extends AttributeUpdater<StackAttribute> {
  readonly layer: HomeCoverLayer = new HomeCoverLayer();
  private sizePx: number = 180;
  private sideOffsetPx: number = 0;
  private position: number = 0;

  initializeModifier(instance: StackAttribute): void {
    this.applyMotion(instance);
  }

  setGeometry(sizePx: number, sideOffsetPx: number): void {
    if (this.sizePx === sizePx && this.sideOffsetPx === sideOffsetPx) return;
    this.sizePx = sizePx;
    this.sideOffsetPx = sideOffsetPx;
    this.updateMotion();
  }

  setPosition(position: number): void {
    if (!Number.isFinite(position)) return;
    const nextPosition = Math.max(-1, Math.min(1, position));
    if (Math.abs(this.position - nextPosition) < 0.0001) return;
    this.position = nextPosition;
    this.layer.setFront(Math.abs(nextPosition) < 0.5);
    this.updateMotion();
  }

  private updateMotion(): void {
    // 真机在节点尚未绑定时可能返回 null，统一为未就绪状态。
    const attribute = this.attribute ?? undefined;
    if (attribute !== undefined) this.applyMotion(attribute);
  }

  private applyMotion(instance: StackAttribute): void {
    instance.transform3D(homeCoverPerspective(this.sizePx, this.position,
      -this.position * this.sideOffsetPx))
      .opacity(1 - Math.abs(this.position) * 0.2);
  }
}

@ComponentV2
struct HomeCarouselCover {
  @Param book: SearchResult | undefined = undefined;
  @Param cardSize: number = 180;
  @Param motion: HomeCoverMotion = new HomeCoverMotion();
  @Event onOpen: () => void = () => {};

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
      .attributeModifier(this.motion)
    }
    // Swiper 只负责外层页面布局，封面的尺寸和透视由内层节点保持。
    .width('100%').height(this.cardSize + HOME_COVER_VERTICAL_SPACE)
    .attributeModifier(this.motion.layer)
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
  @Param active: boolean = true;
  @Event onBookTap: (book: SearchResult) => void = () => {};
  @Local contentWidth: number = 336;
  @Local inViewport: boolean = false;
  private swiperController: SwiperController = new SwiperController();
  private coverMotions: Map<string, HomeCoverMotion> = new Map();
  private indexedMotions: HomeCoverMotion[] = [];

  aboutToAppear(): void {
    this.syncCoverMotions(true);
  }

  @Monitor('books')
  private resetSelection(): void {
    this.syncCoverMotions(true);
    this.swiperController.changeIndex(0, false);
  }

  private coverSize(): number {
    return homeCoverSize(this.contentWidth);
  }

  private initialPosition(index: number): number {
    let distance = index;
    // 两本时不循环，避免同一本同时出现在 Swiper 的前后两侧。
    if (this.books.length > 2) {
      const count = this.books.length;
      if (distance > count / 2) distance -= count;
      if (distance < -count / 2) distance += count;
    }
    return distance;
  }

  private motionForBook(book: SearchResult, index: number): HomeCoverMotion {
    const key = `${book.sourceUrl}#${book.bookUrl}`;
    let motion = this.coverMotions.get(key);
    if (motion === undefined) {
      motion = new HomeCoverMotion();
      motion.setPosition(this.initialPosition(index));
      this.coverMotions.set(key, motion);
    }
    return motion;
  }

  private syncCoverMotions(resetPosition: boolean): void {
    const cardSize = this.coverSize();
    // 尺寸换算只在数据或容器宽度变化时执行，帧回调仅接收原生页面位置。
    const sizePx = this.getUIContext().vp2px(cardSize);
    const sideDistance = homeCoverSideDistance(this.contentWidth);
    const sideOffsetPx = this.getUIContext().vp2px(cardSize - sideDistance);
    const nextMotions: Map<string, HomeCoverMotion> = new Map();
    const indexedMotions: HomeCoverMotion[] = [];
    this.books.forEach((book: SearchResult, index: number) => {
      const motion = this.motionForBook(book, index);
      motion.setGeometry(sizePx, sideOffsetPx);
      if (resetPosition) motion.setPosition(this.initialPosition(index));
      nextMotions.set(`${book.sourceUrl}#${book.bookUrl}`, motion);
      indexedMotions.push(motion);
    });
    this.coverMotions = nextMotions;
    this.indexedMotions = indexedMotions;
  }

  build() {
    Column() {
      Swiper(this.swiperController) {
        ForEach(this.books, (book: SearchResult, index: number) => {
          HomeCarouselCover({
            book: book,
            cardSize: this.coverSize(),
            motion: this.motionForBook(book, index),
            onOpen: () => this.onBookTap(book)
          })
        }, (book: SearchResult) => `${book.sourceUrl}#${book.bookUrl}`)
      }
      .width('100%').height(this.coverSize() + HOME_COVER_VERTICAL_SPACE)
      // 索引由 Swiper 自己保持；显式 .index(0) 会在可见性改变、暂停自动播放时
      // 重置页面，但 AttributeUpdater 仍保留原页的透视，导致中间封面消失。
      // 换源、刷新回到首张仅由 resetSelection 中的 controller 执行。
      .displayCount(1)
      .prevMargin((this.contentWidth - this.coverSize()) / 2)
      .nextMargin((this.contentWidth - this.coverSize()) / 2)
      .loop(this.books.length > 2)
      .autoPlay(this.active && this.books.length > 1 && this.inViewport, { stopWhenTouched: true })
      .interval(4500).duration(400).curve(Curve.EaseOut)
      .indicator(false)
      .onContentDidScroll((_selectedIndex: number, index: number, position: number) => {
        // 每个可见页都有自己的原生位置，循环和换向时也不推导或重置中间进度。
        const count = this.indexedMotions.length;
        if (count > 0) this.indexedMotions[((index % count) + count) % count].setPosition(position);
      })
    }
    .width('100%')
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      const width = Number(newSize.width);
      if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 1) {
        this.contentWidth = width;
        this.syncCoverMotions(false);
      }
    })
    .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number) => {
      this.inViewport = visible && ratio >= 0.5;
    })
  }
}
