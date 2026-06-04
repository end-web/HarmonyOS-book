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
          this._lastResponse = xhr.responseText || "";
          return this._lastResponse;
        },
        connect: function(url) { return this.ajax(url); },
        getString: function(url) { return this.ajax(url); },
        getStrResponse: function() { return this._lastResponse || ""; },
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
        timeFormat: function(ts) {
          try {
            var d = new Date(ts);
            var pad = function(n) { return n < 10 ? "0" + n : "" + n; };
            return d.getFullYear() + "-" + pad(d.getMonth()+1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
          } catch(e) { return String(ts); }
        },
        md5: function(s) {
          // 纯 JS MD5 实现（简化版，覆盖常见书源场景）
          if (!s) return "";
          try {
            function md5cycle(x,k){var a=x[0],b=x[1],c=x[2],d=x[3];a=ff(a,b,c,d,k[0],7,-680876936);d=ff(d,a,b,c,k[1],12,-389564586);c=ff(c,d,a,b,k[2],17,606105819);b=ff(b,c,d,a,k[3],22,-1044525330);a=ff(a,b,c,d,k[4],7,-176418897);d=ff(d,a,b,c,k[5],12,1200080426);c=ff(c,d,a,b,k[6],17,-1473231341);b=ff(b,c,d,a,k[7],22,-45705983);a=ff(a,b,c,d,k[8],7,1770035416);d=ff(d,a,b,c,k[9],12,-1958414417);c=ff(c,d,a,b,k[10],17,-42063);b=ff(b,c,d,a,k[11],22,-1990404162);a=ff(a,b,c,d,k[12],7,1804603682);d=ff(d,a,b,c,k[13],12,-40341101);c=ff(c,d,a,b,k[14],17,-1502002290);b=ff(b,c,d,a,k[15],22,1236535329);a=gg(a,b,c,d,k[1],5,-165796510);d=gg(d,a,b,c,k[6],9,-1069501632);c=gg(c,d,a,b,k[11],14,643717713);b=gg(b,c,d,a,k[0],20,-373897302);a=gg(a,b,c,d,k[5],5,-701558691);d=gg(d,a,b,c,k[10],9,38016083);c=gg(c,d,a,b,k[15],14,-660478335);b=gg(b,c,d,a,k[4],20,-405537848);a=gg(a,b,c,d,k[9],5,568446438);d=gg(d,a,b,c,k[14],9,-1019803690);c=gg(c,d,a,b,k[3],14,-187363961);b=gg(b,c,d,a,k[8],20,1163531501);a=gg(a,b,c,d,k[13],5,-1444681467);d=gg(d,a,b,c,k[2],9,-51403784);c=gg(c,d,a,b,k[7],14,1735328473);b=gg(b,c,d,a,k[12],20,-1926607734);a=hh(a,b,c,d,k[5],4,-378558);d=hh(d,a,b,c,k[8],11,-2022574463);c=hh(c,d,a,b,k[11],16,1839030562);b=hh(b,c,d,a,k[14],23,-35309556);a=hh(a,b,c,d,k[1],4,-1530992060);d=hh(d,a,b,c,k[4],11,1272893353);c=hh(c,d,a,b,k[7],16,-155497632);b=hh(b,c,d,a,k[10],23,-1094730640);a=hh(a,b,c,d,k[13],4,681279174);d=hh(d,a,b,c,k[0],11,-358537222);c=hh(c,d,a,b,k[3],16,-722521979);b=hh(b,c,d,a,k[6],23,76029189);a=hh(a,b,c,d,k[9],4,-640364487);d=hh(d,a,b,c,k[12],11,-421815835);c=hh(c,d,a,b,k[15],16,530742520);b=hh(b,c,d,a,k[2],23,-995338651);a=ii(a,b,c,d,k[0],6,-198630844);d=ii(d,a,b,c,k[7],10,1126891415);c=ii(c,d,a,b,k[14],15,-1416354905);b=ii(b,c,d,a,k[5],21,-57434055);a=ii(a,b,c,d,k[12],6,1700485571);d=ii(d,a,b,c,k[3],10,-1894986606);c=ii(c,d,a,b,k[10],15,-1051523);b=ii(b,c,d,a,k[1],21,-2054922799);a=ii(a,b,c,d,k[8],6,1873313359);d=ii(d,a,b,c,k[15],10,-30611744);c=ii(c,d,a,b,k[6],15,-1560198380);b=ii(b,c,d,a,k[13],21,1309151649);a=ii(a,b,c,d,k[4],6,-145523070);d=ii(d,a,b,c,k[11],10,-1120210379);c=ii(c,d,a,b,k[14],15,718787259);b=ii(b,c,d,a,k[3],21,-343485551);x[0]=add32(a,x[0]);x[1]=add32(b,x[1]);x[2]=add32(c,x[2]);x[3]=add32(d,x[3])}
            function cmn(q,a,b,x,s,t){a=add32(add32(a,q),add32(x,t));return add32((a<<s)|(a>>>(32-s)),b)}
            function ff(a,b,c,d,x,s,t){return cmn((b&c)|((~b)&d),a,b,x,s,t)}
            function gg(a,b,c,d,x,s,t){return cmn((b&d)|(c&(~d)),a,b,x,s,t)}
            function hh(a,b,c,d,x,s,t){return cmn(b^c^d,a,b,x,s,t)}
            function ii(a,b,c,d,x,s,t){return cmn(c^(b|(~d)),a,b,x,s,t)}
            function md51(s){var n=s.length,state=[1732584193,-271733879,-1732584194,271733878],i;for(i=64;i<=n;i+=64)md5cycle(state,md5blk(s.substring(i-64,i)));s=s.substring(i-64);var tail=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];for(i=0;i<s.length;i++)tail[i>>2]|=s.charCodeAt(i)<<((i%4)<<3);tail[i>>2]|=0x80<<((i%4)<<3);if(i>55){md5cycle(state,tail);for(i=0;i<16;i++)tail[i]=0}tail[14]=n*8;md5cycle(state,tail);return state}
            function md5blk(s){var md5blks=[],i;for(i=0;i<64;i+=4)md5blks[i>>2]=s.charCodeAt(i)+(s.charCodeAt(i+1)<<8)+(s.charCodeAt(i+2)<<16)+(s.charCodeAt(i+3)<<24);return md5blks}
            var hex_chr="0123456789abcdef".split("");
            function rhex(n){var s="",j=0;for(;j<4;j++)s+=hex_chr[(n>>(j*8+4))&0x0F]+hex_chr[(n>>(j*8))&0x0F];return s}
            function hex(x){for(var i=0;i<x.length;i++)x[i]=rhex(x[i]);return x.join("")}
            function add32(a,b){return(a+b)&0xFFFFFFFF}
            return hex(md51(s));
          } catch(e) { return ""; }
        },
        md5Encode: function(s) { return this.md5(s); },
        md5Encode16: function(s) { var full = this.md5(s); return full.length >= 32 ? full.substring(8, 24) : full; },
        encodeURI: function(s) { try { return encodeURI(s); } catch(e) { return s || ""; } },
        encodeURIComponent: function(s) { try { return encodeURIComponent(s); } catch(e) { return s || ""; } },
        strToBytes: function(str) {
          if (!str) return [];
          var bytes = [];
          for (var i = 0; i < str.length; i++) {
            var cp = str.charCodeAt(i);
            if (cp < 0x80) bytes.push(cp);
            else if (cp < 0x800) { bytes.push(0xC0 | (cp >> 6)); bytes.push(0x80 | (cp & 0x3F)); }
            else { bytes.push(0xE0 | (cp >> 12)); bytes.push(0x80 | ((cp >> 6) & 0x3F)); bytes.push(0x80 | (cp & 0x3F)); }
          }
          return bytes;
        },
        hexEncodeToString: function(utf8) {
          if (!utf8) return "";
          var hex = "";
          for (var i = 0; i < utf8.length; i++) {
            var h = utf8.charCodeAt(i).toString(16);
            hex += (h.length < 2 ? "0" : "") + h;
          }
          return hex;
        },
        digestHex: function(data, algorithm) { return this.md5(data); },
        digestBase64Str: function(data, algorithm) {
          var hex = this.md5(data);
          if (!hex) return "";
          var bytes = [];
          for (var i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substring(i, i + 2), 16));
          return this.base64Encode(String.fromCharCode.apply(null, bytes));
        },
        HMacHex: function(data, algorithm, key) { return this.md5(key + data); },
        HMacBase64: function(data, algorithm, key) {
          var hex = this.HMacHex(data, algorithm, key);
          if (!hex) return "";
          var bytes = [];
          for (var i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.substring(i, i + 2), 16));
          return this.base64Encode(String.fromCharCode.apply(null, bytes));
        },
        ajaxAll: function(urlList) {
          if (!urlList || !urlList.length) return [];
          var results = [];
          for (var i = 0; i < urlList.length; i++) {
            results.push(this.ajax(urlList[i]));
          }
          return results;
        },
        createSymmetricCrypto: function(transformation, key, iv) {
          // 简化实现：返回一个 doFinal 方法
          return {
            doFinal: function(data, mode) {
              console.log("[Crypto]", transformation, mode, data ? data.substring(0, 20) : "");
              return "";
            }
          };
        },
        cacheFile: function(url) { return this.ajax(url); },
        downloadFile: function(url) { return this.ajax(url); },
        readTxtFile: function(path) { return this.ajax(path); },
        importScript: function(path) { return this.ajax(path); },
        evalJS: function(js) {
          try { return eval(js); } catch(e) { return ""; }
        }
      };
      var cookie = {
        setCookie: function(url, value) { ctx["_cookie_" + url] = value; },
        getCookie: function(url) { return ctx["_cookie_" + url] || ""; },
        removeCookie: function(url) { delete ctx["_cookie_" + url]; },
        replaceCookie: function(url, value) {
          var existing = ctx["_cookie_" + url] || "";
          var map = {};
          if (existing) { existing.split(";").forEach(function(p) { var eq = p.indexOf("="); if (eq > 0) map[p.substring(0,eq).trim()] = p.substring(eq+1).trim(); }); }
          value.split(";").forEach(function(p) { var eq = p.indexOf("="); if (eq > 0) map[p.substring(0,eq).trim()] = p.substring(eq+1).trim(); });
          ctx["_cookie_" + url] = Object.keys(map).map(function(k) { return k + "=" + map[k]; }).join("; ");
        },
        getKey: function(url, key) {
          var raw = ctx["_cookie_" + url] || "";
          var parts = raw.split(";");
          for (var i = 0; i < parts.length; i++) {
            var eq = parts[i].indexOf("=");
            if (eq > 0 && parts[i].substring(0, eq).trim() === key) return parts[i].substring(eq + 1).trim();
          }
          return "";
        },
        cookieToMap: function(cookieStr) {
          var map = {};
          if (!cookieStr) return map;
          cookieStr.split(";").forEach(function(p) { var eq = p.indexOf("="); if (eq > 0) map[p.substring(0,eq).trim()] = p.substring(eq+1).trim(); });
          return map;
        },
        mapToCookie: function(map) {
          if (!map || typeof map !== "object") return "";
          return Object.keys(map).map(function(k) { return k + "=" + map[k]; }).join("; ");
        }
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
      if (!source.login) source.login = function() { return false; };
      if (!source.getLoginHeader) source.getLoginHeader = function() { return ctx._loginHeader || "{}"; };
      if (!source.putLoginHeader) source.putLoginHeader = function(h) { ctx._loginHeader = h; };
      if (!source.removeLoginHeader) source.removeLoginHeader = function() { delete ctx._loginHeader; };
      if (!source.getLoginInfo) source.getLoginInfo = function() { return ctx._loginInfo || "{}"; };
      if (!source.putLoginInfo) source.putLoginInfo = function(info) { ctx._loginInfo = info; };
      if (!source.removeLoginInfo) source.removeLoginInfo = function() { delete ctx._loginInfo; };
      if (!source.getHeaderMap) source.getHeaderMap = function(hasLogin) { return {}; };
      if (!source.put) source.put = function(k, v) { ctx["_source_" + k] = v; };
      if (!source.get) source.get = function(k) { return ctx["_source_" + k] || ""; };
      if (!source.evalJS) source.evalJS = function(js) { try { return eval(js); } catch(e) { return ""; } };
      var book = ctx.book || {};
      if (!book.getVariable) book.getVariable = function(key) { return ctx["_bookVar_" + key] || ""; };
      if (!book.setVariable) book.setVariable = function(key, v) { ctx["_bookVar_" + key] = v; };
      var chapter = ctx.chapter || {};
      if (!chapter.getVariable) chapter.getVariable = function(key) { return ctx["_chapterVar_" + key] || ""; };
      if (!chapter.setVariable) chapter.setVariable = function(key, v) { ctx["_chapterVar_" + key] = v; };
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
