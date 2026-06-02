/**
 * WebViewAudioExtractor - 通过隐藏 WebView 加载章节页并执行 JS 提取音频 URL
 *
 * 用于天下书音这种站点：
 *   播放页内 audio 标签的 src 由前端 JS 动态注入，
 *   只有在浏览器渲染 + 脚本执行后才能取到。
 *
 * 用法：
 *   1. 在 MainPage 中放置 WebViewAudioExtractorHost()（不可见，尺寸 0）
 *   2. 调用 getWebViewAudioExtractor().extract(chapterUrl, jsExpr) 取回音频 URL
 *
 * 设计：
 *   - 任务串行：同一时间只跑一个 extract（避免 onPageEnd 状态共享冲突）
 *   - 加载完成后等额外的 settleMs 让站点 JS 有时间执行
 *   - 跑 jsExpr，结果返回字符串
 */

import web_webview from '@ohos.web.webview';
import { BusinessError } from '@kit.BasicServicesKit';

interface ExtractTask {
  url: string;
  jsExpr: string;
  settleMs: number;
  resolve: (audioUrl: string) => void;
  reject: (e: Error) => void;
  loaded: boolean;
  evaluated: boolean;
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
  private controller: web_webview.WebviewController | null = null;
  private currentUrl: string = '';
  private taskQueue: ExtractTask[] = [];
  private busy: boolean = false;
  private timeoutMs: number = 25000;

  setController(c: web_webview.WebviewController): void {
    this.controller = c;
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
    if (!task || task.loaded) return;
    task.loaded = true;
    // 延迟一些时间等站点 JS 执行
    task.settleTimer = setTimeout(() => {
      this.evaluate();
    }, task.settleMs);
  }

  /**
   * 在隐藏 WebView 中加载 URL，等渲染完后运行 jsExpr，返回结果字符串。
   * @param url      要加载的章节 URL
   * @param jsExpr   一段 JS 表达式，返回音频 URL 字符串（例如 'document.querySelector("audio").src'）
   * @param settleMs 页面 onPageEnd 后再等多久再执行 JS（默认 1500ms）
   */
  extract(url: string, jsExpr: string, settleMs: number = 1500): Promise<string> {
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

      const task: ExtractTask = {
        url, jsExpr, settleMs,
        resolve, reject,
        loaded: false, evaluated: false,
        timerId,
        settleTimer: 0,
      };
      this.taskQueue.push(task);
      if (!this.busy) {
        this.runNext();
      }
    });
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
    if (!task || task.evaluated) return;
    task.evaluated = true;
    if (!this.controller) {
      task.reject(new Error('WebView controller 丢失'));
      this.finishTask();
      return;
    }
    // 用 (function(){return ...})() 包裹，无论 jsExpr 是表达式还是语句都能取到字符串
    const code = '(function(){try{var __r = (' + task.jsExpr + '); return __r === undefined || __r === null ? "" : String(__r);}catch(e){return "";}})()';
    this.controller.runJavaScript(code).then((result: string) => {
      // runJavaScript 返回的字符串是 JSON 编码（带引号）。如果是字面量字符串需要去掉外层引号。
      let v = result;
      if (typeof v === 'string' && v.length >= 2 && v.charAt(0) === '"' && v.charAt(v.length - 1) === '"') {
        try {
          v = JSON.parse(v) as string;
        } catch { /* ignore */ }
      }
      task.resolve(v || '');
      this.finishTask();
    }).catch((err: BusinessError) => {
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
}

/** 不可见 WebView 宿主组件（在 MainPage 中放置一次即可） */
@ComponentV2
export struct WebViewAudioExtractorHost {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
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
      .onPageEnd((event) => {
        if (event && event.url) {
          this.extractor.onPageEnd(event.url);
        } else {
          this.extractor.onPageEnd('');
        }
      })
  }
}
