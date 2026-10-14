import { webview } from '@kit.ArkWeb';
import { BookSourceAudioWebRuntime } from './upstream/core/book/BookSourceAudioWebRuntime';

/** Hidden page loader for legacy `{webView:true}` audiobook rules. */
@ComponentV2
export struct BookSourceAudioWebRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToDisappear(): void {
    BookSourceAudioWebRuntime.get().detach(this.controller);
  }

  build() {
    if (canIUse('SystemCapability.Web.Webview.Core')) {
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
        .width(1)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .onControllerAttached((): void => {
          BookSourceAudioWebRuntime.get().attach(this.controller);
        })
        .onPageBegin((): void => {
          BookSourceAudioWebRuntime.get().setReady(false, this.controller);
        })
        .onPageEnd((): void => {
          BookSourceAudioWebRuntime.get().setReady(true, this.controller);
        })
        .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
          if (event?.data) {
            BookSourceAudioWebRuntime.get().observeRequestUrl(event.data.getRequestUrl());
          }
          return false;
        })
        .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => {
          if (event?.request) {
            BookSourceAudioWebRuntime.get().observeRequestUrl(event.request.getRequestUrl());
          }
          return null;
        })
    }
  }
}
