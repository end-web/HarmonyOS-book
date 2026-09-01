import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import {
  RuleSourceAccountService,
  RuleSourceAccountState,
  RuleSourceAuthResult
} from '../service/rulesource/RuleSourceAccountService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const ACCOUNT_SUCCESS: string = '#168A5B';
const ACCOUNT_DANGER: string = '#D03050';

@ComponentV2
export struct RuleSourceAccountPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local email: string = '';
  @Local password: string = '';
  @Local loggedIn: boolean = false;
  @Local accountLabel: string = '';
  @Local isLoading: boolean = true;
  @Local isLoggingIn: boolean = false;
  @Local isLoggingOut: boolean = false;

  aboutToAppear(): void {
    if (!RuleSourceAccountService.supports(this.sourceUrl)) {
      this.navStack.pop();
      return;
    }
    this.loadAccountState();
  }

  aboutToDisappear(): void {
    this.password = '';
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  private async loadAccountState(): Promise<void> {
    this.isLoading = true;
    try {
      const state: RuleSourceAccountState = await RuleSourceAccountService.getState(this.sourceUrl);
      this.loggedIn = state.loggedIn;
      this.accountLabel = state.accountLabel;
    } catch (_error) {
      this.loggedIn = false;
      this.accountLabel = '';
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  private isValidEmail(value: string): boolean {
    const atIndex = value.indexOf('@');
    if (atIndex <= 0 || atIndex >= value.length - 1) return false;
    const dotIndex = value.lastIndexOf('.');
    return dotIndex > atIndex + 1 && dotIndex < value.length - 1;
  }

  private async login(): Promise<void> {
    if (this.isLoggingIn || this.isLoggingOut) return;
    const email = this.email.trim();
    if (email.length === 0 || this.password.length === 0) {
      this.showToast($r('app.string.rule_source_account_required'));
      return;
    }
    if (!this.isValidEmail(email)) {
      this.showToast($r('app.string.rule_source_account_email_invalid'));
      return;
    }

    this.isLoggingIn = true;
    try {
      const result: RuleSourceAuthResult = await RuleSourceAccountService.login(
        this.sourceUrl, email, this.password);
      if (!result.success) {
        this.showToast(result.message.length > 0
          ? result.message : $r('app.string.rule_source_operation_failed'));
        return;
      }
      this.loggedIn = true;
      this.accountLabel = result.accountLabel.length > 0 ? result.accountLabel : email;
      this.email = '';
      this.showToast(result.message.length > 0
        ? result.message : $r('app.string.rule_source_account_login_success'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.password = '';
      this.isLoggingIn = false;
    }
  }

  private async logout(): Promise<void> {
    if (this.isLoggingIn || this.isLoggingOut) return;
    this.isLoggingOut = true;
    try {
      await RuleSourceAccountService.logout(this.sourceUrl);
      this.loggedIn = false;
      this.accountLabel = '';
      this.email = '';
      this.showToast($r('app.string.rule_source_account_logout_success'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.password = '';
      this.isLoggingOut = false;
    }
  }

  private async openRegistration(): Promise<void> {
    try {
      const url = RuleSourceAccountService.registrationUrl(this.sourceUrl);
      if (!url.startsWith('https://')) throw new Error('Registration URL is invalid');
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) throw new Error('UIAbilityContext is unavailable');
      const context = hostContext as common.UIAbilityContext;
      const options: OpenLinkOptions = { appLinkingOnly: false };
      await context.openLink(url, options);
    } catch (_error) {
      this.showToast($r('app.string.rule_source_account_register_failed'));
    }
  }

  private openWebLogin(): void {
    const loginUrl = RuleSourceAccountService.webLoginUrl(this.sourceUrl);
    const route = RuleSourceLoginRouteParams.forMainAccount(
      this.sourceUrl, this.sourceUrl, loginUrl);
    if (!route.isValid()) {
      this.showToast($r('app.string.rule_source_login_invalid'));
      return;
    }
    this.navStack.pushPathByName('ruleSourceLogin', route);
  }

  build() {
    Column() {
      this.buildHeader()

      if (this.isLoading) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(AppColor.Brand)
          Text($r('app.string.rule_source_loading'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: AppSpace.Lg }) {
            this.buildAccountStatus()
            if (this.loggedIn) {
              this.buildLoggedInActions()
            } else if (RuleSourceAccountService.usesWebLogin(this.sourceUrl)) {
              this.buildWebLoginAction()
            } else {
              this.buildLoginForm()
            }
          }
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: AppSpace.Sm,
            bottom: AppSpace.Xl
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Sm }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(AppRadius.Pill)
      .accessibilityText($r('app.string.common_back'))
      .onClick(() => this.navStack.pop())

      Text($r('app.string.rule_source_account_title'))
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xs,
      left: AppSpace.Xs,
      right: AppSpace.Md,
      bottom: AppSpace.Xs
    })
  }

  @Builder
  buildAccountStatus() {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(26)
          .fontColor([this.loggedIn ? ACCOUNT_SUCCESS : AppColor.Brand])
      }
      .width(48)
      .height(48)
      .backgroundColor(AppColor.BrandSoft)
      .borderRadius(AppRadius.Pill)

      Column({ space: AppSpace.Xxs }) {
        Text(this.loggedIn
          ? $r('app.string.rule_source_account_logged_in')
          : $r('app.string.rule_source_account_logged_out'))
          .fontSize(AppFont.BodyL)
          .fontColor(this.loggedIn ? ACCOUNT_SUCCESS : $r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
        Text(this.accountLabel.length > 0 ? this.accountLabel : this.sourceUrl)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
  }

  @Builder
  buildWebLoginAction() {
    Button() {
      Row({ space: AppSpace.Xs }) {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(18)
          .fontColor([AppColor.OnBrand])
        Text($r('app.string.rule_source_account_login'))
          .fontSize(AppFont.BodyL)
          .fontColor(AppColor.OnBrand)
          .fontWeight(FontWeight.Medium)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(48)
    .backgroundColor(AppColor.Brand)
    .borderRadius(AppRadius.Sm)
    .onClick(() => this.openWebLogin())
  }

  @Builder
  buildLoginForm() {
    Column({ space: AppSpace.Md }) {
      Column({ space: AppSpace.Xs }) {
        Text($r('app.string.rule_source_account_email'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .fontWeight(FontWeight.Medium)
        TextInput({
          placeholder: $r('app.string.rule_source_account_email'),
          text: this.email
        })
          .width('100%')
          .height(48)
          .type(InputType.Email)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Sm)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
          .enabled(!this.isLoggingIn)
          .onChange((value: string) => {
            this.email = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: AppSpace.Xs }) {
        Text($r('app.string.rule_source_account_password'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .fontWeight(FontWeight.Medium)
        TextInput({
          placeholder: $r('app.string.rule_source_account_password'),
          text: this.password
        })
          .width('100%')
          .height(48)
          .type(InputType.Password)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Sm)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
          .enabled(!this.isLoggingIn)
          .onChange((value: string) => {
            this.password = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button() {
        Row({ space: AppSpace.Xs }) {
          if (this.isLoggingIn) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(18)
              .fontColor([AppColor.OnBrand])
          }
          Text(this.isLoggingIn
            ? $r('app.string.rule_source_account_logging_in')
            : $r('app.string.rule_source_account_login'))
            .fontSize(AppFont.BodyL)
            .fontColor(this.isLoggingIn ? AppColor.Brand : AppColor.OnBrand)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(48)
      .backgroundColor(this.isLoggingIn ? AppColor.BrandSoft : AppColor.Brand)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isLoggingIn)
      .onClick(() => this.login())

      Button() {
        Row({ space: AppSpace.Xs }) {
          Text($r('app.string.rule_source_account_register'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .fontWeight(FontWeight.Medium)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([AppColor.Brand])
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(44)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Sm)
      .enabled(!this.isLoggingIn)
      .onClick(() => this.openRegistration())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildLoggedInActions() {
    Button() {
      Row({ space: AppSpace.Xs }) {
        if (this.isLoggingOut) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(AppColor.Brand)
        } else {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(17)
            .fontColor([ACCOUNT_DANGER])
        }
        Text($r('app.string.rule_source_account_logout'))
          .fontSize(AppFont.BodyL)
          .fontColor(this.isLoggingOut ? AppColor.Brand : ACCOUNT_DANGER)
          .fontWeight(FontWeight.Medium)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(48)
    .backgroundColor(this.isLoggingOut
      ? AppColor.BrandSoft : $r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Sm)
    .enabled(!this.isLoggingOut)
    .onClick(() => this.logout())
  }
}
