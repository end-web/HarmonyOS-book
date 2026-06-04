/**
 * BrowserPage - 内嵌浏览器页面
 *
 * 用于 java.startBrowser() / java.showBrowser() 打开的 WebView 页面。
 * 接收 URL 参数，展示一个全屏 WebView。
 */

import { webview } from '@kit.ArkWeb';

@ComponentV2
export struct BrowserPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param url: string = '';
  @Param title: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        Row() {
          Text(this.title || '浏览器')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 16 })

          Button('关闭')
            .fontSize(14)
            .height(32)
            .margin({ right: 12 })
            .onClick(() => {
              this.navStack.pop();
            })
        }
        .width('100%')
        .height(48)
        .backgroundColor('#F5F5F5')
        .alignItems(VerticalAlign.Center)

        // WebView
        Web({ src: this.url, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#FFFFFF')
  }
}
