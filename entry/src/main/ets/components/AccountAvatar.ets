import { AppColor } from '../theme/Theme';

@ComponentV2
export struct AccountAvatar {
  @Param uri: string = '';
  @Param avatarSize: number = 28;
  @Local failedUri: string = '';

  build() {
    Stack() {
      SymbolGlyph($r('sys.symbol.person_fill'))
        .fontSize(this.avatarSize * 0.64)
        .fontColor([Color.White])
      if (this.uri.length > 0 && this.failedUri !== this.uri) {
        Image(this.uri)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .objectFit(ImageFit.Cover)
          .onError(() => { this.failedUri = this.uri; })
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .backgroundColor(AppColor.Brand)
    .borderRadius(this.avatarSize / 2)
    .clip(true)
    .accessibilityText($r('app.string.account_avatar'))
  }
}
