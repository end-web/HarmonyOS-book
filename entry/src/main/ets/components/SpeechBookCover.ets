@ComponentV2
export struct SpeechBookCover {
  @Param cover: string = '';
  @Local failed: boolean = false;

  @Monitor('cover')
  onCoverChange(): void { this.failed = false; }

  private source(): ResourceStr {
    if (!this.cover || this.failed) return $r('app.media.app_icon_legacy');
    if (this.cover.startsWith('/')) return 'file://' + this.cover;
    return this.cover;
  }

  build() {
    Image(this.source())
      .width('100%').height('100%').objectFit(ImageFit.Cover)
      .sourceSize({ width: 240, height: 320 })
      .onError((): void => { if (!this.failed) this.failed = true; })
  }
}
