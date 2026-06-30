/**
 * LoginPage - 书源 Web 登录页
 *
 * 通过 WebView 加载登录页面，登录后捕获 WebView Cookie 并同步到书源请求 CookieJar。
 */

import { webview } from '@kit.ArkWeb';
import { emitter } from '@kit.BasicServicesKit';
import { getCookieManager } from '../service/rule/CookieManager';
import { SourceVariableStore } from '../service/SourceVariableStore';
import { WindowUtils } from '../utils/WindowUtils';
import { EVT_SOURCES_CHANGED } from './SourcePage';

const TAG = 'LoginPage';

interface WebPageUrlEvent {
  url: string;
}

interface LoginHeaderPayload {
  Cookie: string;
}

@ComponentV2
export struct LoginPage {
  @Param loginUrl: string = 'https://v1.gyks.cf/login';
  @Param serverHost: string = 'https://v1.gyks.cf';
  @Param sourceUrl: string = '';
  @Param title: string = '登录聚合源';
  @Param navStack: NavPathStack = new NavPathStack();
  @Local isLoading: boolean = true;
  @Local cookieStatus: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private cookieCheckTimer: number = -1;
  private loginSuccess: boolean = false;
  private currentUrl: string = '';

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
            this.navStack.pop();
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
        } else {
          Text('保存登录')
            .fontSize(14)
            .fontColor('#0A59F7')
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.captureAndSaveCookie(true);
            })
        }
      }
      .width('100%')
      .height(WindowUtils.getStatusBarHeightVp() + 56)
      .padding({ top: WindowUtils.getStatusBarHeightVp(), left: 16, right: 16 })
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
          .onPageBegin((event: WebPageUrlEvent) => {
            this.updateCurrentUrl(event.url);
          })
          .onPageEnd((event: WebPageUrlEvent) => {
            this.updateCurrentUrl(event.url);
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

      if (this.cookieStatus.length > 0) {
        Text(this.cookieStatus)
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  /**
   * 定时检查 WebView Cookie。
   * 聚合源检测到 qttoken 后自动返回；普通书源由用户点击“保存登录”确认。
   */
  private startCookieCheck(): void {
    if (this.cookieCheckTimer >= 0) return;
    let checkCount = 0;
    const maxChecks = 30; // 最多检查 60 秒（每 2000ms 一次）

    this.cookieCheckTimer = setInterval(() => {
      checkCount++;
      if (checkCount > maxChecks || this.loginSuccess) {
        clearInterval(this.cookieCheckTimer);
        this.cookieCheckTimer = -1;
        return;
      }

      this.captureAndSaveCookie(false);
    }, 2000);
  }

  private async captureAndSaveCookie(manual: boolean): Promise<void> {
    const cookie = await this.readWebCookie();
    if (!cookie) {
      if (manual) this.cookieStatus = '当前页面没有检测到 Cookie，请先完成网页登录';
      return;
    }

    this.cookieStatus = manual ? '已保存登录 Cookie' : '已检测到网页登录 Cookie';

    if (manual || cookie.includes('qttoken=')) {
      this.loginSuccess = true;
      this.saveCookie(cookie);
      if (this.cookieCheckTimer >= 0) {
        clearInterval(this.cookieCheckTimer);
        this.cookieCheckTimer = -1;
      }
      setTimeout(() => {
        this.navStack.pop();
      }, manual ? 500 : 1500);
    }
  }

  private async readWebCookie(): Promise<string> {
    const urls = this.cookieCandidateUrls();
    const cookies: string[] = [];
    for (const url of urls) {
      try {
        const cookie = webview.WebCookieManager.fetchCookieSync(url);
        if (cookie && cookie.length > 0) cookies.push(cookie);
      } catch (_e) { /* try next */ }
    }
    const merged = this.mergeCookieStrings(cookies);
    if (merged) return merged;

    try {
      const cookie = await this.controller.runJavaScript('document.cookie');
      return cookie || '';
    } catch {
      return '';
    }
  }

  private cookieCandidateUrls(): string[] {
    const out: string[] = [];
    const addUrl = (url: string): void => {
      const normalized = this.normalizeHttpUrl(url);
      if (normalized && !out.includes(normalized)) out.push(normalized);
    };
    const addOrigin = (url: string): void => {
      const origin = this.extractOrigin(url);
      if (origin && !out.includes(origin)) out.push(origin);
    };
    addUrl(this.currentUrl);
    addOrigin(this.currentUrl);
    addUrl(this.getControllerUrl());
    addOrigin(this.getControllerUrl());
    addUrl(this.loginUrl);
    addOrigin(this.loginUrl);
    addUrl(this.sourceUrl);
    addOrigin(this.sourceUrl);
    addUrl(this.serverHost);
    addOrigin(this.serverHost);
    return out;
  }

  private cookieSaveUrls(): string[] {
    const out: string[] = [];
    const addUrl = (url: string): void => {
      const normalized = this.normalizeHttpUrl(url);
      if (normalized && !out.includes(normalized)) out.push(normalized);
    };
    const addOrigin = (url: string): void => {
      const origin = this.extractOrigin(url);
      if (origin && !out.includes(origin)) out.push(origin);
    };
    addUrl(this.sourceUrl);
    addOrigin(this.sourceUrl);
    addUrl(this.serverHost);
    addOrigin(this.serverHost);
    addUrl(this.loginUrl);
    addOrigin(this.loginUrl);
    addUrl(this.currentUrl);
    addOrigin(this.currentUrl);
    addUrl(this.getControllerUrl());
    addOrigin(this.getControllerUrl());
    return out;
  }

  private updateCurrentUrl(url: string): void {
    const normalized = this.normalizeHttpUrl(url);
    if (normalized) this.currentUrl = normalized;
  }

  private getControllerUrl(): string {
    try {
      return this.controller.getUrl();
    } catch {
      return '';
    }
  }

  private mergeCookieStrings(cookies: string[]): string {
    const merged = new Map<string, string>();
    for (const cookie of cookies) {
      const parts = cookie.split(';');
      for (const rawPart of parts) {
        const part = rawPart.trim();
        if (!part) continue;
        const eq = part.indexOf('=');
        if (eq <= 0) continue;
        const name = part.substring(0, eq).trim();
        const value = part.substring(eq + 1).trim();
        if (name) merged.set(name, value);
      }
    }
    const out: string[] = [];
    for (const item of merged.entries()) {
      out.push(item[0] + '=' + item[1]);
    }
    return out.join('; ');
  }

  private normalizeHttpUrl(url: string): string {
    const text = (url || '').trim();
    if (!text.startsWith('http://') && !text.startsWith('https://')) return '';
    return text;
  }

  private extractOrigin(url: string): string {
    const text = (url || '').trim();
    const match = text.match(/^(https?:\/\/[^/]+)/);
    return match ? match[1] : '';
  }

  private saveCookie(cookie: string): void {
    try {
      const cookieManager = getCookieManager();
      const primaryUrl = this.sourceUrl || this.serverHost || this.loginUrl;
      const saveUrls = this.cookieSaveUrls();
      for (const url of saveUrls) {
        cookieManager.setCookie(url, cookie);
      }
      if (primaryUrl) {
        const payload: LoginHeaderPayload = { Cookie: cookie };
        SourceVariableStore.setSourceVariable(primaryUrl, '_loginHeader', JSON.stringify(payload));
      }
      try {
        webview.WebCookieManager.saveCookieAsync().catch(() => {});
      } catch (_e) { /* ignore */ }
      emitter.emit(EVT_SOURCES_CHANGED);
    } catch (e) {
      console.error(`[${TAG}] Failed to save cookie: ${e}`);
    }
  }
}
