/**
 * WebViewAudioExtractor - 通过隐藏 WebView 加载章节页提取音频 URL
 *
 * 用于天下书音 / 悦听吧 等站点：播放页内 audio src 由前端 JS 动态注入，
 * 或音频请求是站点 JS 异步发起的——只有在浏览器渲染 + 脚本执行后才能拿到。
 *
 * 两种命中路径（任一命中即返回，先到先得）：
 *   A. 网络嗅探：用 onInterceptRequest 监听 WebView 发出的所有请求(含 iframe / 子资源)，
 *      URL 匹配 sourceRegex 时立刻 resolve（典型规则：`.*\.(mp3|mp4).*`）
 *   B. DOM 取值：onPageEnd + settleMs 后跑 jsExpr，从 audio.src/source.src/HTML 中取
 *
 * 用法：
 *   1. 在 MainPage 中放置 WebViewAudioExtractorHost()（不可见，尺寸 0）
 *   2. 调用 getWebViewAudioExtractor().extract(chapterUrl, jsExpr, settleMs, sourceRegex?)
 *
 * 任务串行：同一时间只跑一个 extract（避免 controller 状态污染）
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';

interface ExtractTask {
  url: string;
  jsExpr: string;
  settleMs: number;
  type: string;
  /** 可选：匹配到的请求 URL 直接作为结果返回（网络嗅探路径） */
  sourceRegex: RegExp | null;
  resolve: (audioUrl: string) => void;
  reject: (e: Error) => void;
  loaded: boolean;
  evaluated: boolean;
  resolved: boolean;
  timerId: number;
  settleTimer: number;
}

let globalExtractor: WebViewAudioExtractor | null = null;

export function getWebViewAudioExtractor(): WebViewAudioExtractor {
  if (!globalExtractor) {
    globalExtractor = new WebViewAudioExtractor();
  }
  return globalExtractor;
}

export class WebViewAudioExtractor {
  private controller: webview.WebviewController | null = null;
  private currentUrl: string = '';
  private taskQueue: ExtractTask[] = [];
  private busy: boolean = false;
  private timeoutMs: number = 25000;

  setController(c: webview.WebviewController): void {
    this.controller = c;
  }

  /**
   * 将原生 CookieJar 中保存的登录态同步回 ArkWeb。
   * ArkWeb 的 configCookieSync 一次只设置一个 name=value，所以这里拆开逐个写。
   */
  syncCookies(urls: string[], cookieHeader: string): void {
    const pairs = this.cookiePairs(cookieHeader);
    if (pairs.length === 0) return;
    const targets = this.cookieTargets(urls);
    for (const url of targets) {
      for (const pair of pairs) {
        try {
          webview.WebCookieManager.configCookieSync(url, pair);
        } catch (_e) { /* ignore invalid cookie for this target */ }
      }
    }
    try {
      webview.WebCookieManager.saveCookieAsync().catch(() => {});
    } catch (_e) { /* ignore */ }
  }

  /**
   * 取消所有未完成任务（保留正在跑的那个，避免 controller 状态被污染）。
   * 用于 AudioService 切换章节时，把后台还在排队的旧 extract 全部丢弃，让新章节的 extract 尽快上场。
   */
  cancelPending(): void {
    if (this.taskQueue.length <= 1) return;
    const dropped = this.taskQueue.splice(1);
    for (const t of dropped) {
      clearTimeout(t.timerId);
      if (t.settleTimer) clearTimeout(t.settleTimer);
      t.reject(new Error('cancelled by newer extract'));
    }
  }

  /** 通知当前页加载完成 - 由 Host onPageEnd 调用 */
  onPageEnd(url: string): void {
    const task = this.taskQueue[0];
    if (!task || (task.loaded && task.type !== 'html')) return;
    if (task.type === 'html') {
      task.loaded = true;
      task.settleTimer = setTimeout(() => {
        this.evaluate();
      }, task.settleMs);
      return;
    }
    task.loaded = true;
    // 页面加载完后立即注入防护 JS：
    // 1. 禁用 disable-devtool（避免反调试脚本检测到隐藏 WebView 并阻断 JS）
    // 2. 若当前域是悦听吧且全局有 tingId，主动触发 iframe 初始化
    if (this.controller) {
      try {
        const guardJs = `(function(){
          try {
            // 覆盖 disable-devtool 的检测函数，阻止它干扰 JS 执行
            if(window._disableDevtool) window._disableDevtool = function(){};
            if(window.DisableDevtool) window.DisableDevtool = function(){};
            // 恢复可能被 disable-devtool 挂起的定时器
            var origSetInterval = window._origSetInterval || window.setInterval;
            var origSetTimeout = window._origSetTimeout || window.setTimeout;
          } catch(e){}
          // 悦听吧：确保 iframe SPA 能读到 tingId
          try {
            var iframeEl = document.getElementById('iframe_tingPlay');
            if(iframeEl && typeof window.tingId !== 'undefined' && window.tingId) {
              // 等待 iframe 加载完再操作
              function tryNotifyIframe() {
                try {
                  var cw = iframeEl.contentWindow;
                  if(cw && cw.document && cw.document.readyState === 'complete') {
                    // 方式1: 通过 parent scope（SPA 直接读 window.parent.tingId，此处已存在）
                    // 方式2: postMessage 兜底
                    cw.postMessage({type:'play',tingId:window.tingId,bookId:window.bookId||'',tingTitle:document.getElementById('hTitle')?document.getElementById('hTitle').innerText:''},'*');
                  } else {
                    setTimeout(tryNotifyIframe, 300);
                  }
                } catch(e){}
              }
              setTimeout(tryNotifyIframe, 500);
            }
          } catch(e){}
        })()`;
        this.controller.runJavaScript(guardJs).catch(() => {});
      } catch (_e) { /* ignore */ }
    }
    // 延迟等站点 JS 执行完 + iframe SPA 完成初始化 + 发出音频请求
    task.settleTimer = setTimeout(() => {
      this.evaluate();
    }, task.settleMs);
  }

  /**
   * 检查 WebView 中发出的请求 URL 是否命中 sourceRegex（网络嗅探路径）。
   * 由 Host 的 onInterceptRequest 回调对每个 request URL 调一次。
   */
  onResourceUrl(reqUrl: string): void {
    const task = this.taskQueue[0];
    if (!task || task.resolved || !reqUrl) return;
    // 诊断：打印 WebView 发出的所有"看起来像媒体/接口"的请求
    if (/\.(mp3|mp4|m4a|aac|wav|ogg|m3u8)|audio|play|stream|file|oss|media|booksdir/i.test(reqUrl)) {
      console.info(`[WebViewAudioExtractor] sniff candidate: ${reqUrl}`);
    }
    // 1. 书源配置的 sourceRegex 命中
    if (task.sourceRegex && task.sourceRegex.test(reqUrl)) {
      console.info(`[WebViewAudioExtractor] sniff HIT: ${reqUrl}`);
      this.fulfillCurrent(reqUrl);
      return;
    }
    // 2. 通用音频 URL 特征兜底（处理无后缀 CDN 链接，如悦听吧 oss.fileserver.yuetingba.cn）
    //    条件：URL 含音频文件路径特征 + 带 token/sign/expire 参数（说明是鉴权媒体链接）
    if (/\.(mp3|m4a|ogg|aac|wav|flac|opus)/i.test(reqUrl)) {
      console.info(`[WebViewAudioExtractor] sniff HIT (ext): ${reqUrl}`);
      this.fulfillCurrent(reqUrl);
      return;
    }
    if (/booksdir\//i.test(reqUrl) && /[?&](token|sign|key|t)=/i.test(reqUrl)) {
      console.info(`[WebViewAudioExtractor] sniff HIT (booksdir): ${reqUrl}`);
      this.fulfillCurrent(reqUrl);
      return;
    }
    if (/\/audio\/[a-f0-9/]+[?&]/i.test(reqUrl) && /[?&](sign|token|key|t)=/i.test(reqUrl)) {
      console.info(`[WebViewAudioExtractor] sniff HIT (audio-signed): ${reqUrl}`);
      this.fulfillCurrent(reqUrl);
    }
  }

  /**
   * 在隐藏 WebView 中加载 URL，等渲染完后运行 jsExpr，返回结果字符串。
   * 若提供 sourceRegex，则同时监听 WebView 网络请求，URL 命中正则即立即返回。
   * @param url         要加载的章节 URL
   * @param jsExpr      一段 JS 表达式，返回音频 URL 字符串（例如 'document.querySelector("audio").src'）
   * @param settleMs    页面 onPageEnd 后再等多久再执行 JS（默认 1500ms）
   * @param sourceRegex 网络嗅探正则（如 `.*\.(mp3|mp4).*`），命中的请求 URL 直接作为结果
   */
  extract(url: string, jsExpr: string, settleMs: number = 1500, sourceRegex: string = ''): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (!this.controller) {
        reject(new Error('WebViewAudioExtractor 尚未就绪：请确保 MainPage 中已放置 WebViewAudioExtractorHost'));
        return;
      }
      const timerId = setTimeout(() => {
        // 找到并失败掉这个任务
        const idx = this.taskQueue.findIndex(t => t.timerId === timerId);
        if (idx >= 0) {
          const t = this.taskQueue[idx];
          this.taskQueue.splice(idx, 1);
          t.reject(new Error('WebView 提取音频 URL 超时'));
          if (idx === 0) {
            this.busy = false;
            this.runNext();
          }
        }
      }, this.timeoutMs);

      let regex: RegExp | null = null;
      if (sourceRegex) {
        try {
          regex = new RegExp(sourceRegex, 'i');
        } catch (e) {
          console.warn(`[WebViewAudioExtractor] invalid sourceRegex: ${sourceRegex}`);
        }
      }

      const task: ExtractTask = {
        url, jsExpr, settleMs,
        type: 'audio',
        sourceRegex: regex,
        resolve, reject,
        loaded: false, evaluated: false, resolved: false,
        timerId,
        settleTimer: 0,
      };
      this.taskQueue.push(task);
      if (!this.busy) {
        this.runNext();
      }
    });
  }

  extractHtml(url: string, jsExpr: string, settleMs: number = 2000): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (!this.controller) {
        reject(new Error('WebViewAudioExtractor 尚未就绪：请确保 MainPage 中已放置 WebViewAudioExtractorHost'));
        return;
      }
      const timerId = setTimeout(() => {
        const idx = this.taskQueue.findIndex(t => t.timerId === timerId);
        if (idx >= 0) {
          const t = this.taskQueue[idx];
          this.taskQueue.splice(idx, 1);
          t.reject(new Error('WebView 提取 HTML 超时'));
          if (idx === 0) {
            this.busy = false;
            this.runNext();
          }
        }
      }, this.timeoutMs);

      const task: ExtractTask = {
        url,
        jsExpr,
        settleMs,
        type: 'html',
        sourceRegex: null,
        resolve,
        reject,
        loaded: false,
        evaluated: false,
        resolved: false,
        timerId,
        settleTimer: 0,
      };
      this.taskQueue.push(task);
      if (!this.busy) {
        this.runNext();
      }
    });
  }

  /** 让当前任务以 audioUrl 成功结束，并清理资源 */
  private fulfillCurrent(audioUrl: string): void {
    const task = this.taskQueue[0];
    if (!task || task.resolved) return;
    task.resolved = true;
    task.resolve(audioUrl);
    // 让 WebView 停止当前页面继续加载，避免广告/统计请求继续刷
    try {
      this.controller?.stop();
    } catch (_e) { /* ignore */ }
    this.finishTask();
  }

  private runNext(): void {
    if (this.busy) return;
    const task = this.taskQueue[0];
    if (!task) return;
    this.busy = true;
    try {
      this.controller!.loadUrl(task.url);
      this.currentUrl = task.url;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      task.reject(new Error('loadUrl 失败: ' + msg));
      this.finishTask();
    }
  }

  private evaluate(): void {
    const task = this.taskQueue[0];
    if (!task || task.evaluated || task.resolved) return;
    task.evaluated = true;
    if (!this.controller) {
      task.reject(new Error('WebView controller 丢失'));
      this.finishTask();
      return;
    }
    // 用 (function(){return ...})() 包裹，无论 jsExpr 是表达式还是语句都能取到字符串
    const code = '(function(){try{var __r = (' + task.jsExpr + '); return __r === undefined || __r === null ? "" : String(__r);}catch(e){return "";}})()';
    this.controller.runJavaScript(code).then((result: string) => {
      // 网络嗅探可能在 settleMs 内已经命中并 fulfill 了，这里直接退出
      if (task.resolved) return;
      // runJavaScript 返回的字符串是 JSON 编码（带引号）。如果是字面量字符串需要去掉外层引号。
      let v = result;
      if (typeof v === 'string' && v.length >= 2 && v.charAt(0) === '"' && v.charAt(v.length - 1) === '"') {
        try {
          v = JSON.parse(v) as string;
        } catch { /* ignore */ }
      }
      if (task.type === 'html' && v === '__WAIT__') {
        task.evaluated = false;
        return;
      }
      task.resolved = true;
      task.resolve(v || '');
      this.finishTask();
    }).catch((err: BusinessError) => {
      if (task.resolved) return;
      task.resolved = true;
      task.reject(new Error('runJavaScript 失败: ' + err.message));
      this.finishTask();
    });
  }

  private finishTask(): void {
    const task = this.taskQueue.shift();
    if (task) {
      clearTimeout(task.timerId);
      if (task.settleTimer) clearTimeout(task.settleTimer);
    }
    this.busy = false;
    // 让出一帧再起下个，避免 WebView 状态没完全切干净
    setTimeout(() => this.runNext(), 80);
  }

  private cookiePairs(cookieHeader: string): string[] {
    const out: string[] = [];
    const seen = new Set<string>();
    const parts = (cookieHeader || '').split(';');
    for (const raw of parts) {
      const pair = raw.trim();
      if (!pair) continue;
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      const name = pair.substring(0, eq).trim();
      if (!name || this.isCookieAttribute(name)) continue;
      if (seen.has(name)) continue;
      seen.add(name);
      out.push(name + '=' + pair.substring(eq + 1).trim());
    }
    return out;
  }

  private isCookieAttribute(name: string): boolean {
    const lower = name.toLowerCase();
    return lower === 'path' || lower === 'domain' || lower === 'expires' ||
      lower === 'max-age' || lower === 'samesite' || lower === 'secure' || lower === 'httponly';
  }

  private cookieTargets(urls: string[]): string[] {
    const out: string[] = [];
    for (const raw of urls) {
      const url = (raw || '').trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      if (!out.includes(url)) out.push(url);
      const match = url.match(/^(https?:\/\/[^/]+)/);
      if (match && !out.includes(match[1])) out.push(match[1]);
    }
    return out;
  }
}

/** 不可见 WebView 宿主组件（在 MainPage 中放置一次即可） */
@ComponentV2
export struct WebViewAudioExtractorHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private extractor: WebViewAudioExtractor = getWebViewAudioExtractor();

  aboutToAppear(): void {
    this.extractor.setController(this.controller);
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(0)
      .height(0)
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .imageAccess(false)
      .onlineImageAccess(true)
      .userAgent('Mozilla/5.0 (Linux; U; Android 11; zh-cn; MI 8 Build/RKQ1.200826.002) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/77.0.3865.120 MQQBrowser/13.7 Mobile Safari/537.36')
      // 允许 HTTP 页面加载 HTTPS iframe（悦听吧等站外层 HTTP + iframe HTTPS）
      .mixedMode(MixedMode.All)
      // 网络嗅探：onInterceptRequest 会触发主 frame + iframe + 所有子资源的请求 URL，
      // 比 DOM 取值更可靠（站点经常把 audio.src 临时写完又移除）。
      // 文档：https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-web-interceptor
      .onInterceptRequest((event) => {
        try {
          const reqUrl = event?.request?.getRequestUrl();
          // 打印所有进入 onInterceptRequest 的 URL 前缀，确认回调是否被触发
          if (reqUrl) {
            const preview = reqUrl.length > 80 ? reqUrl.substring(0, 80) : reqUrl;
            console.info(`[WebViewExtractor] intercept: ${preview}`);
            this.extractor.onResourceUrl(reqUrl);
          }
        } catch (_e) { /* ignore */ }
        return null; // 始终放行原始请求
      })
      .onPageEnd((event) => {
        if (event && event.url) {
          this.extractor.onPageEnd(event.url);
        } else {
          this.extractor.onPageEnd('');
        }
      })
  }
}
