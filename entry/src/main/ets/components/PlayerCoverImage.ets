import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { EnhancedPlayerCover } from './EnhancedPlayerCover';

class PlayerCoverRequest {
  url: string;
  size: number;
  key: string;
  constructor(url: string, size: number) {
    this.url = url;
    this.size = size;
    this.key = JSON.stringify([url, size]);
  }
}

/** 小图负责首帧和回退，大图解码成功后才显示；尺寸按组件 vp 传给 sourceSize。 */
@ComponentV2
export struct PlayerCoverImage {
  @Param url: string = '';
  @Param fallback: string = '';
  @Param highQuality: boolean = false;
  @Local decodeSize: number = 300;
  @Local loadedKey: string = '';
  @Local failedKey: string = '';
  @Local previewFailed: boolean = false;
  private resizeTimer: number = -1;

  aboutToAppear(): void { this.reset(); }
  aboutToDisappear(): void { this.cancelResize(); }

  @Monitor('url', 'fallback')
  onCoverChanged(): void { this.reset(); }

  private reset(): void {
    this.loadedKey = '';
    this.failedKey = '';
    this.previewFailed = false;
    CoverPrefetcher.prefetch(this.url, true);
    if (this.fallback) CoverPrefetcher.prefetch(this.fallback, true);
  }

  private cancelResize(): void {
    if (this.resizeTimer !== -1) clearTimeout(this.resizeTimer);
    this.resizeTimer = -1;
  }

  private resize(width: number): void {
    if (!Number.isFinite(width) || width <= 0) return;
    // sourceSize 单位为 vp，不能再乘屏幕密度；分档减少小窗拖动时反复解码。
    const size = Math.min(1024, Math.max(64, Math.ceil(width / 32) * 32));
    if (size === this.decodeSize) return;
    this.cancelResize();
    this.resizeTimer = setTimeout((): void => {
      this.resizeTimer = -1;
      this.decodeSize = size;
    }, 80);
  }

  private source(url: string): ResourceStr {
    if (!url) return $r('app.media.app_icon_legacy');
    if (url.startsWith('/')) return `file://${url}`;
    if (url.startsWith('http') || url.startsWith('file://')) return url;
    return $rawfile(url);
  }

  private requestKey(): string { return JSON.stringify([this.url, this.decodeSize]); }

  build() {
    Stack() {
      Image(this.source(this.previewFailed ? this.url : (this.fallback || this.url)))
        .width('100%').height('100%').objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 300 })
        .alt($r('app.media.app_icon_legacy'))
        .onError((): void => { this.previewFailed = true; })
      if (this.highQuality && this.url) {
        ForEach([new PlayerCoverRequest(this.url, this.decodeSize)], (request: PlayerCoverRequest) => {
          Image(this.source(request.url))
            .width('100%').height('100%').objectFit(ImageFit.Cover)
            .sourceSize({ width: request.size, height: request.size })
            .interpolation(ImageInterpolation.Medium)
            .opacity(this.loadedKey === request.key && this.failedKey !== request.key ? 1 : 0)
            .onComplete((event) => {
              if (event?.loadingStatus === 1 && this.requestKey() === request.key) {
                this.loadedKey = request.key;
              }
            })
            .onError((): void => {
              if (this.requestKey() === request.key) this.failedKey = request.key;
            })
        }, (request: PlayerCoverRequest): string => request.key)
        EnhancedPlayerCover({ url: this.failedKey === this.requestKey() ? (this.fallback || this.url) : this.url })
      }
    }
    .width('100%').height('100%')
    .onSizeChange((_oldValue, newValue) => {
      if (typeof newValue.width === 'number') this.resize(newValue.width);
    })
  }
}
