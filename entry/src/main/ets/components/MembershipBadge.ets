/** 用户提供的月/年 VIP 素材，仅裁去透明留白，保持原图比例。 */
@ComponentV2
export struct MembershipBadge {
  @Param productId: string = '';
  @Param badgeWidth: number = 40;

  build() {
    if (this.productId === 'iconMonth' || this.productId === 'iconYear') {
      Image(this.productId === 'iconMonth' ? $r('app.media.vip_month_badge') : $r('app.media.vip_year_badge'))
        .width(this.badgeWidth)
        .height(this.badgeWidth)
        .objectFit(ImageFit.Contain)
        .flexShrink(0)
        .accessibilityText(this.productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
    }
  }
}
