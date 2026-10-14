import { webview } from '@kit.ArkWeb';
import { LocalRuleSourceDownloadService } from '../LocalRuleSourceDownloadService';

@ComponentV2
export struct RuleSourceImportWebHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private retry: number = -1;
  private alive: boolean = false;
  aboutToAppear(): void { this.alive = true; this.attach(0); }
  private attach(attempt: number): void {
    if (!this.alive) return;
    try {
      this.controller.getWebId();
      const context = this.getUIContext().getHostContext();
      if (context) LocalRuleSourceDownloadService.attach(this.controller, context);
    } catch (_error) {
      if (attempt < 100) this.retry = setTimeout((): void => this.attach(attempt + 1), 100);
    }
  }
  aboutToDisappear(): void {
    this.alive = false;
    if (this.retry >= 0) clearTimeout(this.retry);
    LocalRuleSourceDownloadService.detach(this.controller);
  }
  build() {
    if (canIUse('SystemCapability.Web.Webview.Core')) {
      Web({src:'about:blank',controller:this.controller,incognitoMode:true})
        .width(1).height(1).opacity(0.01).javaScriptAccess(true).domStorageAccess(true)
        .onControllerAttached((): void => this.attach(0))
        .onPageEnd((): void => LocalRuleSourceDownloadService.inspect())
    }
  }
}
