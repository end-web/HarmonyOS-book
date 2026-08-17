import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { KK_BIQU_GE_BASE_URL } from '../service/text/KkBiqugeHtmlParser';
import { KkBiqugeTextSource } from '../service/text/KkBiqugeTextSource';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const TEXT_SOURCE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 ' +
  'Chrome/126.0.0.0 Mobile Safari/537.36';

@ComponentV2
export struct TextSourceVerifyPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local loading: boolean = true;
  @Local verified: boolean = false;
  @Local currentUrl: string = KK_BIQU_GE_BASE_URL;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  aboutToDisappear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  private inspectCookie(): void {
    try {
      const cookie = webview.WebCookieManager.fetchCookieSync(KK_BIQU_GE_BASE_URL);
      this.verified = cookie.indexOf('server_name_session=') >= 0;
    } catch (_e) {
      this.verified = false;
    }
  }

  private finishVerification(): void {
    KkBiqugeTextSource.clearSearchCache();
    try {
      webview.WebCookieManager.saveCookieAsync().catch((_e: BusinessError): void => {});
    } catch (_e) {
      // Cookie 已经保存在当前 ArkWeb 进程中。
    }
    this.navStack.pop();
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(AppRadius.Pill)
        .onClick(() => this.navStack.pop())

        Column({ space: 2 }) {
          Text('电子书源验证')
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          Text(this.verified ? '验证信息已获取' : '完成网页验证后返回')
            .fontSize(AppFont.Caption)
            .fontColor(this.verified ? AppColor.Brand : $r('sys.color.font_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('完成')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .fontWeight(FontWeight.Medium)
          .height(44)
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
          .onClick(() => this.finishVerification())
      }
      .width('100%')
      .height(WindowUtils.getStatusBarHeightVp() + 56)
      .padding({
        left: AppSpace.Sm,
        right: AppSpace.Sm,
        top: WindowUtils.getStatusBarHeightVp()
      })
      .backgroundColor($r('sys.color.background_primary'))

      Stack({ alignContent: Alignment.Center }) {
        Web({ src: KK_BIQU_GE_BASE_URL, controller: this.controller })
          .width('100%')
          .height('100%')
          .onControllerAttached(() => {
            try {
              this.controller.setCustomUserAgent(TEXT_SOURCE_USER_AGENT);
            } catch (_e) {
              // 使用 ArkWeb 默认 UA 继续加载。
            }
          })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .mixedMode(MixedMode.All)
          .onPageBegin((event) => {
            this.loading = true;
            if (event?.url) this.currentUrl = event.url;
          })
          .onPageEnd((event) => {
            this.loading = false;
            if (event?.url) this.currentUrl = event.url;
            this.inspectCookie();
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
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
