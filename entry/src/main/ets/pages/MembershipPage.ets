import { common, sendableContextManager } from '@kit.AbilityKit';
import { MembershipState } from '../model/MembershipState';
import { MembershipService } from '../service/MembershipService';
import { AppColor, AppFont, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { MembershipBadge } from '../components/MembershipBadge';
import { AppIconPage } from './AppIconPage';

/** 一级只展示主题及订阅入口，权益、套餐和规则集中在订阅详情页。 */
@ComponentV2
export struct MembershipPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local membership: MembershipService = MembershipService.instance;
  @Local state: MembershipState = MembershipState.current;

  private abilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;
    try {
      return sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(host));
    } catch (_error) { return undefined; }
  }

  private openSubscription(): void {
    this.navStack.pushPathByName('membershipSubscription', '');
  }

  private async manage(): Promise<void> {
    const context = this.abilityContext();
    if (!context) return;
    const opened = await this.membership.manage(context);
    if (!opened) {
      this.getUIContext().getPromptAction().showToast({ message: this.membership.message });
    }
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([$r('sys.color.font_primary')])
        }.width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.app_icon_back')).onClick(() => this.navStack.pop())
        Text($r('app.string.membership_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        if (this.state.active) {
          MembershipBadge({ productId: this.state.productId })
        }
        Blank()
      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })
      Scroll() {
        Column({ space: AppSpace.Lg }) {
          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.membership_subscription_entry'))
              .layoutWeight(1).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
              .onClick(() => this.openSubscription())
            Button($r('app.string.membership_manage'))
              .layoutWeight(1).backgroundColor($r('sys.color.comp_background_primary')).fontColor(AppColor.Brand)
              .enabled(!this.membership.busy && this.membership.supported).onClick(() => this.manage())
          }.width('100%')
          AppIconPage({ onMembershipRequired: (): void => this.openSubscription() })
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
