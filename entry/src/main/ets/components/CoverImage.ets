import { AppRadius } from '../theme/Theme';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { CoverAspectRatio } from '../utils/CoverAspectRatio';

/**
 * 网络封面图：失败自动延迟重试，直到出图或达到上限。
 * 解决首进首页封面半截停住、之后再不加载的问题。
 */
@ComponentV2
export struct CoverImage {
  @Param url: string = '';
  @Param imgWidth: Length = '100%';
  @Param imgHeight: Length = 0;
  @Param useFixedHeight: boolean = false;
  @Param aspectRatioValue: number = 0.75;
  @Param radius: number = AppRadius.Md;
  @Param imageFit: ImageFit = ImageFit.Cover;
  @Param decodeW: number = 300;
  @Param decodeH: number = 400;
  @Param highPriority: boolean = true;
  @Event onImageSize: (url: string, width: number, height: number) => void = () => {};
  @Event onImageReady: (url: string) => void = () => {};

  @Local showImage: boolean = true;
  @Local giveUp: boolean = false;
  @Local retryCount: number = 0;

  private static readonly MAX_UI_RETRY: number = 6;
  private retryTimer: number = -1;
  private appeared: boolean = false;

  aboutToAppear(): void {
    this.appeared = true;
    this.resetCover();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.cancelRetry();
  }

  @Monitor('url')
  onUrlChanged(): void {
    if (this.appeared) this.resetCover();
  }

  private resetCover(): void {
    this.cancelRetry();
    this.showImage = true;
    this.giveUp = false;
    this.retryCount = 0;
    if (this.url.startsWith('http')) {
      CoverPrefetcher.prefetch(this.url, this.highPriority);
    }
  }

  private cancelRetry(): void {
    if (this.retryTimer >= 0) clearTimeout(this.retryTimer);
    this.retryTimer = -1;
  }

  private scheduleRetry(): void {
    if (!this.appeared || this.retryTimer >= 0) return;
    if (this.retryCount >= CoverImage.MAX_UI_RETRY) {
      this.giveUp = true;
      return;
    }
    this.retryCount = this.retryCount + 1;
    this.showImage = false;
    CoverPrefetcher.retry(this.url);
    const delayMs: number = Math.min(800 * this.retryCount, 5000);
    const url = this.url;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (!this.appeared || this.url !== url) return;
      this.showImage = true;
    }, delayMs);
  }

  @Builder
  private networkImage() {
    if (this.useFixedHeight) {
      Image(this.url)
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.radius)
        .clip(true)
        .objectFit(this.imageFit)
        .sourceSize(this.imageFit === ImageFit.Contain ? undefined : { width: this.decodeW, height: this.decodeH })
        .alt($r('app.media.book_cover_placeholder'))
        .onComplete((event) => {
          // 数据加载阶段为原图尺寸；不能用 sourceSize 缩略解码后的尺寸覆盖它。
          if (!this.appeared || event?.loadingStatus !== 0) return;
          CoverAspectRatio.remember(this.url, event.width, event.height);
          this.onImageSize(this.url, event.width, event.height);
          this.onImageReady(this.url);
        })
        .onError(() => {
          this.scheduleRetry();
        })
    } else {
      Image(this.url)
        .width(this.imgWidth)
        .aspectRatio(this.aspectRatioValue)
        .borderRadius(this.radius)
        .clip(true)
        .objectFit(this.imageFit)
        .sourceSize(this.imageFit === ImageFit.Contain ? undefined : { width: this.decodeW, height: this.decodeH })
        .alt($r('app.media.book_cover_placeholder'))
        .onComplete((event) => {
          if (!this.appeared || event?.loadingStatus !== 0) return;
          CoverAspectRatio.remember(this.url, event.width, event.height);
          this.onImageSize(this.url, event.width, event.height);
          this.onImageReady(this.url);
        })
        .onError(() => {
          this.scheduleRetry();
        })
    }
  }

  @Builder
  private placeholderImage() {
    if (this.useFixedHeight) {
      Image($r('app.media.book_cover_placeholder'))
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.radius)
        .clip(true)
        .objectFit(this.imageFit)
    } else {
      Image($r('app.media.book_cover_placeholder'))
        .width(this.imgWidth)
        .aspectRatio(this.aspectRatioValue)
        .borderRadius(this.radius)
        .clip(true)
        .objectFit(this.imageFit)
    }
  }

  build() {
    if (this.url.startsWith('http') && this.showImage && !this.giveUp) {
      this.networkImage()
    } else {
      this.placeholderImage()
    }
  }
}
