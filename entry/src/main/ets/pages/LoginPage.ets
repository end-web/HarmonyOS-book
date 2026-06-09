/**
 * LoginPage - 聚合源登录页
 *
 * 通过 WebView 加载服务端登录页面，登录成功后自动捕获 qttoken cookie 并存储。
 * 登录完成后自动返回上一页。
 */

import web_webview from '@ohos.web.webview';
import { router } from '@kit.ArkUI';
import { getCookieManager } from '../service/rule/CookieManager';

const TAG = 'LoginPage';

@ComponentV2
export struct LoginPage {
  @Param loginUrl: string = 'https://v1.gyks.cf/login';
  @Param serverHost: string = 'https://v1.gyks.cf';
  @Param title: string = '登录聚合源';
  @Local isLoading: boolean = true;
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private cookieCheckTimer: number = -1;
  private loginSuccess: boolean = false;

  aboutToDisappear(): void {
    if (this.cookieCheckTimer >= 0) {
      clearInterval(this.cookieCheckTimer);
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r('sys.media.ohos_ic_public_arrow_left'))
          .width(24)
          .height(24)
          .fillColor('#333333')
          .onClick(() => {
            router.back();
          })
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
        Blank()
        if (this.loginSuccess) {
          Text('登录成功')
            .fontSize(14)
            .fontColor('#4CAF50')
            .fontWeight(FontWeight.Medium)
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // WebView
      Stack() {
        Web({ src: this.loginUrl, controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .onPageEnd(() => {
            this.isLoading = false;
            // 页面加载完成后，开始检查 cookie
            this.startCookieCheck();
          })

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
            Text('正在加载登录页面...')
              .fontSize(14)
              .fontColor('#666666')
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  /**
   * 定时检查 WebView 中是否出现了 qttoken cookie
   * 登录成功后服务端会设置 qttoken cookie，检测到后自动存储并返回
   */
  private startCookieCheck(): void {
    let checkCount = 0;
    const maxChecks = 30; // 最多检查 60 秒（每 2000ms 一次）

    this.cookieCheckTimer = setInterval(() => {
      checkCount++;
      if (checkCount > maxChecks || this.loginSuccess) {
        clearInterval(this.cookieCheckTimer);
        this.cookieCheckTimer = -1;
        return;
      }

      // 通过 JS 注入读取 cookie
      this.controller.runJavaScript('document.cookie')
        .then((cookieStr: string) => {
          if (cookieStr && cookieStr.includes('qttoken')) {
            const token = this.extractQttoken(cookieStr);
            if (token && token.length > 5) {
              this.loginSuccess = true;
              this.saveCookie(token);
              clearInterval(this.cookieCheckTimer);
              this.cookieCheckTimer = -1;
              // 延迟返回，让用户看到"登录成功"提示
              setTimeout(() => {
                router.back();
              }, 1500);
            }
          }
        })
        .catch(() => {
          // ignore JS errors (page might be navigating)
        });
    }, 2000);
  }

  /**
   * 从 cookie 字符串中提取 qttoken 值
   */
  private extractQttoken(cookieStr: string): string {
    const parts = cookieStr.split(';');
    for (const part of parts) {
      const trimmed = part.trim();
      if (trimmed.startsWith('qttoken=')) {
        return trimmed.substring(8);
      }
    }
    return '';
  }

  /**
   * 保存 qttoken 到 CookieManager
   */
  private saveCookie(token: string): void {
    try {
      const cookieManager = getCookieManager();
      // 设置 cookie（格式：qttoken=xxx）
      cookieManager.setCookie(this.serverHost, `qttoken=${token}`);
    } catch (e) {
      console.error(`[${TAG}] Failed to save cookie: ${e}`);
    }
  }
}
