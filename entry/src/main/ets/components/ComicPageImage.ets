import { ComicPage } from '../service/ComicReaderService';
import { AppColor } from '../theme/Theme';
import { ComicSuperResolutionService } from '../service/ComicSuperResolutionService';

@ComponentV2
export struct ComicPageImage {
  @Param page: ComicPage = new ComicPage();
  @Param pageWidth: number = 360;
  @Param pageHeight: number = 600;
  @Param paged: boolean = false;
  @Param superResolution: boolean = false;
  @Event onToggle: (event: ClickEvent) => void = () => {};
  @Local ratio: number = 0;
  @Local failed: boolean = false;
  @Local loaded: boolean = false;
  @Local retry: number = 0;
  @Local zoom: number = 1;
  @Local enhancedUrl: string = '';
  @Local enhancementFailed: boolean = false;
  private visible: boolean = false;
  private enhancementSerial: number = 0;

  aboutToDisappear(): void { this.visible = false; this.enhancementSerial++; }

  @Monitor('superResolution', 'page')
  onEnhancementChanged(): void {
    this.enhancedUrl = '';
    this.enhancementFailed = false;
    this.enhancementSerial++;
    this.enhance();
  }

  private enhance(): void {
    if (!this.visible || !this.superResolution || this.enhancedUrl) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const ticket = ++this.enhancementSerial;
    const active = (): boolean => this.visible && this.superResolution && ticket === this.enhancementSerial;
    ComicSuperResolutionService.enhance(context, this.page.url, active).then((uri: string): void => {
      if (!active()) return;
      this.enhancedUrl = uri;
      this.enhancementFailed = !uri;
    }).catch((): void => { if (active()) this.enhancementFailed = true; });
  }

  private imageHeight(): number {
    const ratio = this.ratio > 0 ? this.ratio : this.page.width > 0 && this.page.height > 0 ?
      this.page.height / this.page.width : 1.45;
    return Math.max(1, this.pageWidth * ratio);
  }

  build() {
    Stack() {
      if (!this.loaded && !this.failed) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
      if (this.failed) {
        Column({ space: 12 }) {
          Text($r('app.string.comic_image_failed', this.page.index + 1)).fontColor('#CCCCCC').fontSize(14)
          Button($r('app.string.comic_retry')).backgroundColor(AppColor.Brand).fontColor(Color.White)
            .onClick(() => { this.failed = false; this.loaded = false; this.retry++; })
        }
      } else {
        Scroll() {
        Image(this.enhancedUrl || this.page.url)
          .id(`${this.page.key}:${this.retry}`)
          .width(this.pageWidth).height(this.imageHeight())
          .objectFit(ImageFit.Contain)
          .syncLoad(false)
          .autoResize(true)
          .scale({ x: this.zoom, y: this.zoom })
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) {
              this.ratio = event.height / event.width;
              this.loaded = true;
            }
          })
          .onError(() => {
            if (this.enhancedUrl) { this.enhancedUrl = ''; this.enhancementFailed = true; }
            else this.failed = true;
          })
          .onClick((event: ClickEvent) => { this.onToggle(event); })
          .gesture(TapGesture({ count: 2 }).onAction(() => { this.zoom = this.zoom === 1 ? 2 : 1; }))
          .accessibilityText($r('app.string.comic_page_number', this.page.index + 1))
        }.width(this.pageWidth).height(this.paged ? this.pageHeight : this.imageHeight())
          .scrollable(this.paged ? ScrollDirection.Vertical : ScrollDirection.None)
          .scrollBar(BarState.Off)
      }
      if (this.superResolution && this.enhancementFailed) {
        Text($r('app.string.comic_ai_original')).fontSize(11).fontColor('#CCCCCC')
          .padding(6).backgroundColor('#AA121212').hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.pageWidth).height(this.paged ? this.pageHeight : this.imageHeight()).clip(true)
    .backgroundColor('#121212')
    .onVisibleAreaChange([0.01], (_visible: boolean, ratio: number) => {
      const visible = ratio > 0;
      if (this.visible === visible) return;
      this.visible = visible;
      if (visible) this.enhance();
      else this.enhancementSerial++;
    })
  }
}
