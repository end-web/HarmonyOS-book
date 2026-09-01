import { webview } from '@kit.ArkWeb';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleHttpClient } from '../service/rulesource/LocalRuleHttpClient';
import { RuleSourceAccountService } from '../service/rulesource/RuleSourceAccountService';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const RULE_LOGIN_DANGER: string = '#D03050';
const RULE_LOGIN_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 ' +
  'Chrome/126.0.0.0 Mobile Safari/537.36';

class RuleSourceWebCookieSnapshot {
  url: string = '';
  cookieHeader: string = '';
}

@ComponentV2
export struct RuleSourceLoginPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param route: RuleSourceLoginRouteParams = new RuleSourceLoginRouteParams();
  @Local ready: boolean = false;
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local currentUrl: string = '';
  @Local currentOrigin: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private visitedUrls: string[] = [];
  private leaving: boolean = false;

  aboutToAppear(): void {
    WindowUtils.setStatusBarLight(false);
    this.prepareLogin();
  }

  aboutToDisappear(): void {
    WindowUtils.setStatusBarLight(false);
    if (!this.leaving) {
      const snapshots = this.snapshotCookies();
      this.releaseWebCookies();
      this.persistOnDisappear(snapshots);
    }
  }

  private async prepareLogin(): Promise<void> {
    if (!this.route.isValid()) {
      this.showToast($r('app.string.rule_source_login_invalid'));
      this.navStack.pop();
      return;
    }
    try {
      const source = await LocalRuleSourceRepository.get(this.route.sourceUrl);
      if (source === undefined) throw new Error('Rule source not found');
      this.releaseWebCookies();
      const loginUrls = this.loginUrls();
      for (const loginUrl of loginUrls) {
        const cookieHeader = await LocalRuleHttpClient.getStoredCookieHeader(
          this.route.sourceUrl, loginUrl);
        this.injectCookies(loginUrl, cookieHeader);
        this.rememberUrl(loginUrl);
      }
      this.currentUrl = this.route.loginUrl;
      this.currentOrigin = LocalRuleHttpClient.requestOrigin(this.route.loginUrl);
      this.ready = true;
      this.loading = true;
    } catch (_error) {
      this.showToast($r('app.string.rule_source_login_prepare_failed'));
      this.navStack.pop();
    }
  }

  private loginUrls(): string[] {
    const urls: string[] = [this.route.loginUrl];
    if (!this.route.isMainAccount) return urls;
    const accountUrls = RuleSourceAccountService.webLoginUrls(this.route.sourceUrl);
    for (const accountUrl of accountUrls) {
      const origin = LocalRuleHttpClient.requestOrigin(accountUrl);
      let exists = false;
      for (const url of urls) {
        if (LocalRuleHttpClient.requestOrigin(url) === origin) {
          exists = true;
          break;
        }
      }
      if (!exists && origin.length > 0) urls.push(accountUrl);
    }
    return urls;
  }

  private injectCookies(url: string, cookieHeader: string): void {
    const pairs = cookieHeader.split(';');
    for (const rawPair of pairs) {
      const pair = rawPair.trim();
      if (pair.length === 0 || pair.indexOf('=') <= 0) continue;
      try {
        webview.WebCookieManager.configCookieSync(url, `${pair}; Path=/; Secure`, true, true);
      } catch (_error) {
        // 单个失效 Cookie 不阻断其余登录态恢复。
      }
    }
  }

  private rememberUrl(url: string): void {
    const origin = LocalRuleHttpClient.requestOrigin(url);
    if (origin.length === 0) return;
    for (let index = 0; index < this.visitedUrls.length; index++) {
      if (LocalRuleHttpClient.requestOrigin(this.visitedUrls[index]) === origin) {
        this.visitedUrls[index] = url;
        return;
      }
    }
    if (this.visitedUrls.length < 16) this.visitedUrls.push(url);
  }

  private snapshotCookies(): RuleSourceWebCookieSnapshot[] {
    const snapshots: RuleSourceWebCookieSnapshot[] = [];
    for (const url of this.visitedUrls) {
      const snapshot = new RuleSourceWebCookieSnapshot();
      snapshot.url = url;
      try {
        snapshot.cookieHeader = webview.WebCookieManager.fetchCookieSync(url, true) || '';
      } catch (_error) {
        snapshot.cookieHeader = '';
      }
      snapshots.push(snapshot);
    }
    return snapshots;
  }

  private async persistSnapshots(snapshots: RuleSourceWebCookieSnapshot[]): Promise<void> {
    for (const snapshot of snapshots) {
      try {
        await LocalRuleHttpClient.saveWebCookies(
          this.route.sourceUrl, snapshot.url, snapshot.cookieHeader);
      } catch (_error) {
        // 页面退出时无法再可靠提示，下一次登录仍可重新获取。
      }
    }
  }

  private async persistOnDisappear(snapshots: RuleSourceWebCookieSnapshot[]): Promise<void> {
    await this.persistSnapshots(snapshots);
    if (this.route.isMainAccount) {
      try {
        await RuleSourceAccountService.saveWebLogin(
          this.route.sourceUrl, this.cookieHeaders(snapshots));
      } catch (_error) {
        // 页面已经退出，仅保留 Cookie，用户下次进入时仍可完成主账号会话保存。
      }
    }
  }

  private cookieHeaders(snapshots: RuleSourceWebCookieSnapshot[]): string[] {
    const headers: string[] = [];
    for (const snapshot of snapshots) {
      if (snapshot.cookieHeader.length > 0) headers.push(snapshot.cookieHeader);
    }
    return headers;
  }

  private releaseWebCookies(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (_error) {
      // ArkWeb 尚未完成初始化时无需清理。
    }
  }

  private async finishLogin(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    const snapshots = this.snapshotCookies();
    try {
      await this.persistSnapshots(snapshots);
      if (this.route.isMainAccount) {
        const saved = await RuleSourceAccountService.saveWebLogin(
          this.route.sourceUrl, this.cookieHeaders(snapshots));
        if (!saved) {
          this.showToast($r('app.string.rule_source_account_web_required'));
          return;
        }
      }
      this.leaving = true;
      this.stopAndRelease();
      this.showToast(this.route.isMainAccount
        ? $r('app.string.rule_source_account_login_success')
        : $r('app.string.rule_source_login_saved'));
      this.navStack.pop();
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.saving = false;
    }
  }

  private async leaveLogin(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    const snapshots = this.snapshotCookies();
    try {
      await this.persistSnapshots(snapshots);
      if (this.route.isMainAccount) {
        await RuleSourceAccountService.saveWebLogin(
          this.route.sourceUrl, this.cookieHeaders(snapshots));
      }
    } catch (_error) {
      // 返回操作不能被会话保存失败阻塞。
    }
    this.leaving = true;
    this.stopAndRelease();
    this.navStack.pop();
    this.saving = false;
  }

  private stopAndRelease(): void {
    try {
      this.controller.stop();
    } catch (_error) {
      // 页面已经停止时直接清理隔离 Cookie。
    }
    this.releaseWebCookies();
  }

  private confirmClearLogin(): void {
    if (this.saving) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_login_clear_title'),
      message: this.route.isMainAccount
        ? $r('app.string.rule_source_account_clear_message')
        : $r('app.string.rule_source_login_clear_message'),
      primaryButton: {
        value: $r('app.string.rule_source_login_clear_action'),
        fontColor: RULE_LOGIN_DANGER,
        action: () => {
          this.clearLogin();
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async clearLogin(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      if (this.route.isMainAccount) {
        await RuleSourceAccountService.logout(this.route.sourceUrl);
      }
      const loginUrls = this.loginUrls();
      for (const loginUrl of loginUrls) {
        await LocalRuleHttpClient.clearCookies(this.route.sourceUrl, loginUrl);
      }
      this.releaseWebCookies();
      this.visitedUrls = [];
      for (const loginUrl of loginUrls) this.rememberUrl(loginUrl);
      this.currentUrl = this.route.loginUrl;
      this.currentOrigin = LocalRuleHttpClient.requestOrigin(this.route.loginUrl);
      this.controller.loadUrl(this.route.loginUrl);
      this.showToast($r('app.string.rule_source_login_cleared'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.saving = false;
    }
  }

  private refreshPage(): void {
    if (!this.ready || this.saving) return;
    try {
      this.controller.refresh(true);
    } catch (_error) {
      this.showToast($r('app.string.rule_source_login_refresh_failed'));
    }
  }

  private allowNavigation(url: string): boolean {
    if (url === 'about:blank') return true;
    if (!url.toLowerCase().startsWith('https://')) {
      this.showToast($r('app.string.rule_source_login_https_only'));
      return false;
    }
    if (!this.route.isMainAccount) return true;
    const origin = LocalRuleHttpClient.requestOrigin(url);
    const loginUrls = this.loginUrls();
    for (const loginUrl of loginUrls) {
      if (LocalRuleHttpClient.requestOrigin(loginUrl) === origin) return true;
    }
    this.showToast($r('app.string.rule_source_login_domain_blocked'));
    return false;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  build() {
    Column() {
      this.buildHeader()

      if (!this.ready) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(AppColor.Brand)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Web({ src: this.route.loginUrl, controller: this.controller, incognitoMode: true })
            .width('100%')
            .height('100%')
            .onControllerAttached((): void => {
              try {
                this.controller.setCustomUserAgent(RULE_LOGIN_USER_AGENT);
              } catch (_error) {
                // 使用 ArkWeb 默认 UA 继续加载。
              }
            })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(false)
            .fileAccess(false)
            .geolocationAccess(false)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.None)
            .multiWindowAccess(false)
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              return !this.allowNavigation(request.getRequestUrl());
            })
            .onPageBegin((event): void => {
              this.loading = true;
              if (event?.url) {
                this.currentUrl = event.url;
                this.currentOrigin = LocalRuleHttpClient.requestOrigin(event.url);
                this.rememberUrl(event.url);
              }
            })
            .onPageEnd((event): void => {
              this.loading = false;
              if (event?.url) {
                this.currentUrl = event.url;
                this.currentOrigin = LocalRuleHttpClient.requestOrigin(event.url);
                this.rememberUrl(event.url);
              }
            })
            .onErrorReceive((): void => {
              this.loading = false;
            })

          if (this.loading) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color(AppColor.Brand)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(AppRadius.Pill)
      .onClick(() => this.leaveLogin())

      Column({ space: 1 }) {
        Text(this.route.displayName)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.currentOrigin)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(19)
          .fontColor([AppColor.Brand])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Pill)
      .enabled(this.ready && !this.saving)
      .accessibilityText($r('app.string.rule_source_login_refresh'))
      .onClick(() => this.refreshPage())

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([RULE_LOGIN_DANGER])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Pill)
      .enabled(this.ready && !this.saving)
      .accessibilityText($r('app.string.rule_source_login_clear_action'))
      .onClick(() => this.confirmClearLogin())

      Text($r('app.string.common_done'))
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .fontWeight(FontWeight.Medium)
        .height(44)
        .padding({ left: AppSpace.Xs, right: AppSpace.Xs })
        .onClick(() => this.finishLogin())
    }
    .width('100%')
    .height(WindowUtils.getStatusBarHeightVp() + 56)
    .padding({
      left: AppSpace.Xs,
      right: AppSpace.Xs,
      top: WindowUtils.getStatusBarHeightVp()
    })
    .backgroundColor($r('sys.color.background_primary'))
  }
}
