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
import { JSExecutor } from './JSExecutor';

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
          try {
            // 支持 Legado "URL,{config}" 语法
            if (url.indexOf(",{") > 0) {
              var idx = url.indexOf(",{");
              var realUrl = url.substring(0, idx);
              var cfg = JSON.parse(url.substring(idx + 1));
              var method = (cfg.method || "GET").toUpperCase();
              xhr.open(method, realUrl, false);
              if (cfg.headers) { for (var h in cfg.headers) xhr.setRequestHeader(h, cfg.headers[h]); }
              if (method === "POST" && cfg.body) {
                xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
                xhr.send(cfg.body);
              } else { xhr.send(); }
            } else {
              xhr.open("GET", url, false);
              xhr.send();
            }
          } catch(e) {}
          return xhr.responseText || "";
        },
        connect: function(url) { return this.ajax(url); },
        getString: function(url) { return this.ajax(url); },
        log: function() {
          var a = []; for (var i=0;i<arguments.length;i++) a.push(String(arguments[i]));
          console.log("[JS]", a.join(" "));
        },
        toast: function(msg) { console.log("[Toast]", String(msg)); },
        longToast: function(msg) { console.log("[LongToast]", String(msg)); },
        get: function(k) {
          // 优先从 _javaVars 中取（源变量），再从 ctx 中取
          if (ctx._javaVars && ctx._javaVars[k] !== undefined) return String(ctx._javaVars[k]);
          return ctx[k] !== undefined ? String(ctx[k]) : "";
        },
        put: function(k, v) { ctx[k] = String(v); return String(v); },
        webView: function() { return ""; },
        hexDecodeToString: function(hex) {
          if (!hex) return "";
          // 检测是否为合法 hex 字符串
          var isHex = hex.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(hex);
          if (isHex) {
            var bytes = [];
            for (var i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substring(i, i + 2), 16));
            try { return new TextDecoder().decode(new Uint8Array(bytes)); } catch(e) { return ""; }
          }
          // 非 hex，尝试 base64 解码（兼容光遇聚合等书源误用）
          try { return decodeURIComponent(escape(atob(hex))); } catch(e) { return ""; }
        },
        base64Encode: function(s) { try { return btoa(unescape(encodeURIComponent(s))); } catch(e) { return ""; } },
        base64Decode: function(s) { try { return decodeURIComponent(escape(atob(s))); } catch(e) { return ""; } },
        androidId: function() { return ctx._deviceId || ""; },
        deviceID: function() { return this.androidId(); },
        getWebViewUA: function() { return "Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36"; },
        getAppVariant: function() { return ""; },
        getCookie: function(url) { return cookie.getCookie(url); },
        startBrowser: function(url, title) { console.log("[Browser]", url); },
        startBrowserDp: function(url, title) { this.startBrowser(url, title); },
        showBrowser: function(url, html, js, opts) { console.log("[ShowBrowser]", url); },
        refreshExplore: function() { console.log("[RefreshExplore]"); },
        randomUUID: function() { return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) { var r = Math.random()*16|0; return (c==="x"?r:r&0x3|0x8).toString(16); }); },
        timeFormat: function(ts) { try { return new Date(ts).toISOString(); } catch(e) { return String(ts); } },
        md5: function() { return ""; }
      };
      var cookie = {
        setCookie: function(url, value) { ctx["_cookie_" + url] = value; },
        getCookie: function(url) { return ctx["_cookie_" + url] || ""; },
        removeCookie: function(url) { delete ctx["_cookie_" + url]; }
      };
      var cacheStore = ctx._cacheStore || {};
      var cache = {
        get: function(key) { return cacheStore[key] || ""; },
        put: function(key, value) { cacheStore[key] = value; },
        delete: function(key) { delete cacheStore[key]; },
        putMemory: function(key, value) { cacheStore["_mem_" + key] = value; },
        getFromMemory: function(key) { return cacheStore["_mem_" + key] || 0; }
      };
      var source = ctx.source || {};
      if (!source.getVariable) source.getVariable = function() { return ctx._sourceVar || ""; };
      if (!source.setVariable) source.setVariable = function(v) { ctx._sourceVar = v; };
      var book = ctx.book || {};
      if (book && !book.getVariable) book.getVariable = function(key) { return ctx["_bookVar_" + key] || ""; };
      if (book && !book.setVariable) book.setVariable = function(key, v) { ctx["_bookVar_" + key] = v; };
      // 构建 this 上下文，供 jsLib 中的 this.source / this.java 等使用
      var thisCtx = {
        source: source,
        java: javaBridge,
        cookie: cookie,
        cache: cache
      };
      // 用 .call() 绑定 this 到 thisCtx，让 jsLib 函数能通过 this.source 等访问上下文
      // 内层函数通过 .call(thisCtx) 绑定 this
      var wrappedCode = '(function(){\\n' +
        req.code + '\\n' +
        '}).call(this);';
      var fn = new Function(
        "result","baseUrl","src","key","page","book","chapter",
        "cookie","cache","source","java",
        '"use strict";\\n' + wrappedCode
      );
      var ret = fn.call(thisCtx,
        ctx.result || "", ctx.baseUrl || "", ctx.src || "",
        ctx.key || "", ctx.page || 1,
        book, ctx.chapter || null,
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

    // 注入 jsLib 全局函数（如果有）
    // 修正 jsLib 中的 this 引用，消除 this 绑定依赖
    const jsLib = context['_jsLib'] as string;
    if (jsLib && jsLib.trim()) {
      const patchedJsLib = JSExecutor.patchJsLibThis(jsLib);
      code = patchedJsLib + '\n' + code;
    }

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
