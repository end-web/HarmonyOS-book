import { AppRadius } from '../theme/Theme';
import { CoverPrefetcher } from '../service/CoverPrefetcher';

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
  @Param decodeW: number = 300;
  @Param decodeH: number = 400;
  @Param highPriority: boolean = true;

  @Local showImage: boolean = true;
  @Local giveUp: boolean = false;
  @Local retryCount: number = 0;

  private static readonly MAX_UI_RETRY: number = 6;

  aboutToAppear(): void {
    if (this.url.startsWith('http')) {
      CoverPrefetcher.prefetch(this.url, this.highPriority);
    }
  }

  private scheduleRetry(): void {
    if (this.retryCount >= CoverImage.MAX_UI_RETRY) {
      this.giveUp = true;
      return;
    }
    this.retryCount = this.retryCount + 1;
    this.showImage = false;
    CoverPrefetcher.retry(this.url);
    const delayMs: number = Math.min(800 * this.retryCount, 5000);
    setTimeout((): void => {
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
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: this.decodeW, height: this.decodeH })
        .alt($r('app.media.app_icon_legacy'))
        .onError(() => {
          this.scheduleRetry();
        })
    } else {
      Image(this.url)
        .width(this.imgWidth)
        .aspectRatio(this.aspectRatioValue)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: this.decodeW, height: this.decodeH })
        .alt($r('app.media.app_icon_legacy'))
        .onError(() => {
          this.scheduleRetry();
        })
    }
  }

  @Builder
  private placeholderImage() {
    if (this.useFixedHeight) {
      Image($r('app.media.app_icon_legacy'))
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
    } else {
      Image($r('app.media.app_icon_legacy'))
        .width(this.imgWidth)
        .aspectRatio(this.aspectRatioValue)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
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
