/**
 * WebViewJSEngine - 基于 ArkWeb 的 JS 执行引擎
 *
 * 利用鸿蒙 WebView (Chromium 内核) 的 runJavaScript 能力执行任意 JS 代码。
 * 作为 JSExecutor 本地求值的降级方案：简单表达式走本地，复杂 JS 走 WebView。
 *
 * 使用方式：
 * 1. 在页面中放置 <WebViewJSEngineHost /> 组件（不可见，尺寸 0）
 * 2. 调用 getWebViewJSEngine().eval(code, context) 执行 JS
 */

import web_webview from '@ohos.web.webview';
import { BusinessError } from '@kit.BasicServicesKit';

// ──────────── 类型定义 ────────────

interface EvalTask {
  code: string;
  context: Record<string, Object>;
  resolve: (value: Object | null) => void;
  reject: (reason: Error) => void;
  timerId: number;
}

interface EvalRequest {
  id: number;
  code: string;
  contextJson: string;
}

interface EvalResponse {
  id: number;
  success: boolean;
  resultJson?: string;
  error?: string;
}

// ──────────── 全局状态 ────────────

let globalEngine: WebViewJSEngine | null = null;

export function getWebViewJSEngine(): WebViewJSEngine {
  if (!globalEngine) {
    globalEngine = new WebViewJSEngine();
  }
  return globalEngine;
}

// ──────────── 桥接 HTML（内嵌 JS 运行时） ────────────

const BRIDGE_SCRIPT = `
"use strict";
window.__evalReady = true;
window.__nativeBridge = {
  dispatch: function(reqStr) {
    var req = JSON.parse(reqStr);
    var id = req.id;
    var result = { id: id, success: false };
    try {
      var ctx = JSON.parse(req.contextJson);
      var javaBridge = {
        ajax: function(url) {
          if (typeof XMLHttpRequest === "undefined") return "";
          var xhr = new XMLHttpRequest();
          try { xhr.open("GET", url, false); xhr.send(); } catch(e) {}
          return xhr.responseText || "";
        },
        connect: function(url) { return this.ajax(url); },
        getString: function(url) { return this.ajax(url); },
        log: function() {
          var a = []; for (var i=0;i<arguments.length;i++) a.push(String(arguments[i]));
          console.log("[JS]", a.join(" "));
        },
        get: function(k) { return ctx[k] !== undefined ? String(ctx[k]) : ""; },
        put: function(k, v) { ctx[k] = String(v); return String(v); },
        webView: function() { return ""; }
      };
      var cookie = { setCookie:function(){}, getCookie:function(){return "";}, removeCookie:function(){} };
      var cache = { get:function(){return "";}, put:function(){}, delete:function(){} };
      var source = ctx.source || {};
      var fn = new Function(
        "result","baseUrl","src","key","page","book","chapter",
        "cookie","cache","source","java",
        '"use strict";\\n' + req.code
      );
      var ret = fn(
        ctx.result || "", ctx.baseUrl || "", ctx.src || "",
        ctx.key || "", ctx.page || 1,
        ctx.book || null, ctx.chapter || null,
        cookie, cache, source, javaBridge
      );
      result.resultJson = (ret === undefined || ret === null) ? "null" : JSON.stringify(ret);
      result.success = true;
    } catch(e) {
      result.error = e.message || String(e);
    }
    return JSON.stringify(result);
  }
};`;

// ──────────── 引擎核心 ────────────

export class WebViewJSEngine {
  private controller: web_webview.WebviewController | null = null;
  private isReady: boolean = false;
  private readyCallbacks: Array<() => void> = [];
  private pendingTasks: Map<number, EvalTask> = new Map();
  private nextId: number = 1;
  private defaultTimeout: number = 15000;

  /**
   * 由 WebViewJSEngineHost 组件调用
   */
  setController(ctrl: web_webview.WebviewController): void {
    this.controller = ctrl;
  }

  /**
   * 桥接 HTML 加载并注入完成后调用
   */
  markReady(): void {
    this.isReady = true;
    for (const cb of this.readyCallbacks) {
      cb();
    }
    this.readyCallbacks = [];
  }

  /**
   * 执行 JS 代码
   * @param code JS 代码字符串
   * @param context 上下文变量（result, baseUrl, src, book, chapter 等）
   * @param timeout 超时毫秒数
   * @returns 执行结果
   */
  async eval(code: string, context: Record<string, Object> = {}, timeout?: number): Promise<Object | null> {
    if (!code || !code.trim()) return null;

    await this.ensureReady();
    if (!this.controller) {
      throw new Error('WebView controller 未初始化');
    }

    const id = this.nextId++;
    const actualTimeout = timeout ?? this.defaultTimeout;

    return new Promise<Object | null>((resolve, reject) => {
      const timerId: number = setTimeout(() => {
        this.pendingTasks.delete(id);
        reject(new Error(`WebView JS 执行超时 (${actualTimeout}ms)`));
      }, actualTimeout);

      const task: EvalTask = { code, context, resolve, reject, timerId };
      this.pendingTasks.set(id, task);

      const request: EvalRequest = {
        id,
        code,
        contextJson: JSON.stringify(context),
      };

      // runJavaScript 接收的是在 WebView 页面上下文中执行的代码
      // 参数需要双重序列化：外层是 JS 字符串字面量，内层是 JSON
      const callCode = `window.__nativeBridge.dispatch(${JSON.stringify(JSON.stringify(request))})`;

      this.controller!.runJavaScript(callCode).then((resultStr: string) => {
        this.handleResponse(id, resultStr);
      }).catch((err: BusinessError) => {
        const t = this.pendingTasks.get(id);
        if (t) {
          clearTimeout(t.timerId);
          this.pendingTasks.delete(id);
          t.reject(new Error(`runJavaScript 失败: ${err.message}`));
        }
      });
    });
  }

  private handleResponse(id: number, resultStr: string): void {
    const task = this.pendingTasks.get(id);
    if (!task) return;

    clearTimeout(task.timerId);
    this.pendingTasks.delete(id);

    try {
      const resp: EvalResponse = JSON.parse(resultStr) as EvalResponse;
      if (resp.success) {
        if (resp.resultJson === undefined || resp.resultJson === null || resp.resultJson === 'null') {
          task.resolve(null);
        } else {
          try {
            task.resolve(JSON.parse(resp.resultJson));
          } catch {
            // 不是合法 JSON，作为原始字符串返回
            task.resolve(resp.resultJson);
          }
        }
      } else {
        task.reject(new Error(resp.error ?? 'JS 执行失败'));
      }
    } catch (err) {
      task.reject(new Error(`解析响应失败: ${String(err)}`));
    }
  }

  private ensureReady(): Promise<void> {
    if (this.isReady) return Promise.resolve();
    return new Promise<void>((resolve) => {
      this.readyCallbacks.push(resolve);
    });
  }
}

// ──────────── WebView 宿主组件 ────────────

/**
 * 不可见的 WebView 宿主组件，在页面中放置即可。
 * 组件尺寸为 0，不影响布局。
 *
 * 用法：在 MainPage 的 build() 中放置：
 *   WebViewJSEngineHost()
 */
@ComponentV2
export struct WebViewJSEngineHost {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private engine: WebViewJSEngine = getWebViewJSEngine();
  private bridgeInjected: boolean = false;

  aboutToAppear(): void {
    this.engine.setController(this.controller);
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(0)
      .height(0)
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .imageAccess(false)
      .onlineImageAccess(false)
      .onPageEnd(() => {
        if (!this.bridgeInjected) {
          this.bridgeInjected = true;
          // 页面加载完成后注入桥接代码
          this.controller.runJavaScript(BRIDGE_SCRIPT).then(() => {
            return this.controller.runJavaScript('!!window.__evalReady');
          }).then((ready: string) => {
            if (ready === 'true') {
              this.engine.markReady();
            } else {
              this.engine.markReady();
            }
          }).catch(() => {
            // 注入失败也标记就绪，eval 调用时会走降级
            this.engine.markReady();
          });
        }
      })
  }
}
