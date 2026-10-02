import { common, sendableContextManager } from '@kit.AbilityKit';
import { MembershipState } from '../model/MembershipState';
import { MembershipPlan, MembershipService } from '../service/MembershipService';
import { AppIconService } from '../service/AppIconService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { MembershipBadge } from '../components/MembershipBadge';

@ComponentV2
export struct MembershipSubscriptionPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local membership: MembershipService = MembershipService.instance;
  @Local state: MembershipState = MembershipState.current;
  @Local agreed: boolean = false;

  aboutToAppear(): void {
    const context = this.abilityContext();
    if (context) this.membership.load(context);
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;
    try {
      return sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(host));
    } catch (_error) { return undefined; }
  }

  private purchase(plan: MembershipPlan): void {
    if (!this.agreed || !AppIconService.instance.supported) return;
    const context = this.abilityContext();
    if (context) this.membership.purchase(context, plan.id);
  }

  private restore(): void {
    const context = this.abilityContext();
    if (context) this.membership.load(context);
  }

  private manage(): void {
    const context = this.abilityContext();
    if (context) this.membership.manage(context);
  }

  private findPlan(productId: string): MembershipPlan | undefined {
    return this.membership.plans.find((plan: MembershipPlan): boolean => plan.id === productId);
  }

  private planPrice(productId: string): ResourceStr {
    return this.findPlan(productId)?.price || $r('app.string.membership_plan_unavailable');
  }

  @Builder
  planCard(productId: string) {
    Row({ space: AppSpace.Md }) {
      MembershipBadge({ productId: productId, badgeWidth: 52 })
      Column({ space: AppSpace.Xs }) {
        Text(productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
          .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(productId === 'iconMonth' ? $r('app.string.membership_month_period') : $r('app.string.membership_year_period'))
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        Text(this.planPrice(productId)).fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppColor.Brand)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button(this.state.active ? $r('app.string.membership_manage') : $r('app.string.membership_subscribe'))
        .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
        .enabled(!this.membership.busy && (this.state.active ||
          (this.agreed && AppIconService.instance.supported && this.findPlan(productId) !== undefined)))
        .onClick((): void => {
          if (this.state.active) this.manage();
          else {
            const plan = this.findPlan(productId);
            if (plan) this.purchase(plan);
          }
        })
    }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([$r('sys.color.font_primary')])
        }.width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.app_icon_back')).onClick(() => this.navStack.pop())
        Text($r('app.string.membership_subscription_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (this.membership.busy) {
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }
      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })
      Scroll() {
        Column({ space: AppSpace.Md }) {
          Column({ space: AppSpace.Sm }) {
            Text(this.membership.message).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary')).width('100%')
            if (this.state.active) {
              Text($r('app.string.membership_expires', new Date(this.state.expiresAt).toLocaleString()))
                .fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).width('100%')
              Text(this.state.autoRenew ? $r('app.string.membership_renew_on') : $r('app.string.membership_renew_off'))
                .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
            }
            Text($r('app.string.membership_benefit')).fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary')).width('100%')
            if (!AppIconService.instance.supported) {
              Text($r('app.string.app_icon_unsupported')).fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_secondary')).width('100%')
            }
            if (this.membership.confirmationPending) {
              Text($r('app.string.membership_confirmation_pending')).fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_secondary')).width('100%')
            }
          }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg)
          .backgroundColor($r('sys.color.comp_background_primary'))
          this.planCard('iconMonth')
          this.planCard('iconYear')
          Text(this.membership.productsMessage).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
          Text($r('app.string.membership_terms')).fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary')).width('100%')
          if (!this.state.active) {
            Row({ space: AppSpace.Sm }) {
              Checkbox({ name: 'subscriptionConsent' }).select(this.agreed).selectedColor(AppColor.Brand)
                .onChange((value: boolean): void => { this.agreed = value; })
                .accessibilityText($r('app.string.membership_consent'))
              Text($r('app.string.membership_consent')).fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_primary')).layoutWeight(1)
            }.width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceAround }) {
            Button($r('app.string.membership_restore')).backgroundColor(Color.Transparent).fontColor(AppColor.Brand)
              .enabled(!this.membership.busy).onClick(() => this.restore())
            Button($r('app.string.membership_manage')).backgroundColor(Color.Transparent).fontColor(AppColor.Brand)
              .enabled(!this.membership.busy && this.membership.supported).onClick(() => this.manage())
          }.width('100%')
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
