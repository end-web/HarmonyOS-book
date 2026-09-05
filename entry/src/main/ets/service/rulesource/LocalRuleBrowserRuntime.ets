import { webview } from '@kit.ArkWeb';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleFetchResult, LocalRuleRequestPlan, LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';
import { LocalRuleWebSession } from './LocalRuleWebSession';
import { LocalRuleHttpClient } from './LocalRuleHttpClient';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';
import { WebEngineGate } from '../WebEngineGate';

class LocalRuleBrowserTask {
  initial: LocalRuleFetchResult = new LocalRuleFetchResult();
  deadline: number = 0;
  timer: number = 0;
  probe: number = 0;
  requests: number = 0;
  pages: number = 0;
  lastHtml: string = '';
  stable: number = 0;
  documentServed: boolean = false;
  variables: Record<string, string> = {};
  origins: Set<string> = new Set<string>();
  urls: Set<string> = new Set<string>();
  resolve: (result: LocalRuleFetchResult) => void = (_result: LocalRuleFetchResult): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
}

/** Explicit page rendering has no JS-to-platform bridge. Rule webJs runs separately in QuickJS. */
export class LocalRuleBrowserRuntime {
  static readonly instance: LocalRuleBrowserRuntime = new LocalRuleBrowserRuntime();
  private controller: webview.WebviewController | undefined = undefined;
  private active: LocalRuleBrowserTask | undefined = undefined;

  attach(controller: webview.WebviewController): void { this.controller = controller; }

  detach(controller: webview.WebviewController): void {
    if (this.controller !== controller) return;
    this.fail(new Error('网页渲染宿主已关闭'));
    this.controller = undefined;
  }

  async render(source: LocalRuleSource, plan: LocalRuleRequestPlan, initial: LocalRuleFetchResult,
    variables: Record<string, string>): Promise<LocalRuleFetchResult> {
    const deadline = Date.now() + plan.timeoutMs;
    const lease = await LocalRuleWebSession.acquire(plan.timeoutMs);
    const snapshots: Record<string, string> = {};
    let task: LocalRuleBrowserTask | undefined = undefined;
    try {
      LocalRuleDiagnostics.check(variables);
      WebEngineGate.instance.needRuleBrowser = true;
      const mountDeadline = Math.min(deadline, Date.now() + 5000);
      while (this.controller === undefined && Date.now() < mountDeadline) {
        if (Date.now() >= deadline) break;
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 50); });
      }
      const controller = this.controller;
      if (controller === undefined) throw new Error('网页渲染宿主挂载超时');
      if (Date.now() >= deadline) throw new Error('网页渲染超时');
      webview.WebCookieManager.clearAllCookiesSync(true);
      const cookieHeaders: Record<string, string> = source.enabledCookieJar
        ? await LocalRuleHttpClient.getCookieSnapshot(source.bookSourceUrl) : {};
      let ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
      for (const name of Object.keys(plan.headers)) {
        if (name.toLowerCase() === 'cookie') this.injectCookies(initial.requestUrl, plan.headers[name]);
        if (name.toLowerCase() === 'user-agent') ua = plan.headers[name];
      }
      // The response may have replaced a cookie sent by the initial request.
      for (const origin of Object.keys(cookieHeaders)) this.injectCookies(origin, cookieHeaders[origin]);
      controller.setCustomUserAgent(ua);
      task = new LocalRuleBrowserTask();
      task.initial = initial;
      task.deadline = deadline;
      task.variables = variables;
      const current = task;
      const result = await new Promise<LocalRuleFetchResult>((resolve, reject) => {
        current.resolve = resolve;
        current.reject = reject;
        this.active = current;
        current.origins.add(LocalRuleHttpClient.requestOrigin(initial.requestUrl));
        current.timer = setTimeout(() => this.fail(new Error('网页渲染超时')), Math.max(1, deadline - Date.now()));
        // The native request has already applied method, headers, cookies and redirects.
        controller.loadUrl(initial.requestUrl);
        this.schedule(current);
      });
      return result;
    } finally {
      if (task !== undefined && this.active === task) this.fail(new Error('网页渲染已结束'));
      if (task !== undefined) {
        for (const origin of task.origins) {
          try { snapshots[origin] = webview.WebCookieManager.fetchCookieSync(origin, true); }
          catch (_error) { /* A page may never have established a cookie store. */ }
        }
      }
      const controller = this.controller;
      if (controller !== undefined) {
        try { controller.stop(); controller.loadUrl('about:blank'); } catch (_error) { /* Already detached. */ }
      }
      try { webview.WebCookieManager.clearAllCookiesSync(true); } catch (_error) { /* Not initialized. */ }
      try {
        if (source.enabledCookieJar) {
          for (const origin of Object.keys(snapshots)) {
            if (LocalRuleSourceRepository.isInitialized() && await LocalRuleSourceRepository.get(source.bookSourceUrl) === undefined) break;
            await LocalRuleHttpClient.saveWebCookies(source.bookSourceUrl, origin, snapshots[origin]);
          }
        }
      } catch (_error) {
        LocalRuleDiagnostics.record(variables, 'warn', '网页已完成，Cookie 未能持久化');
      } finally {
        LocalRuleWebSession.release(lease);
      }
    }
  }

  private injectCookies(origin: string, cookies: string): void {
    for (const raw of cookies.split(';')) {
      const pair = raw.trim();
      if (pair.indexOf('=') < 1) continue;
      webview.WebCookieManager.configCookieSync(origin, `${pair}; Path=/${origin.startsWith('https:') ? '; Secure' : ''}`, true, true);
    }
  }

  allowRequest(url: string): boolean {
    const task = this.active;
    if (url === 'about:blank') return true;
    if (task === undefined || !new RegExp('^https?://', 'i').test(url)) return false;
    if (url.length > LocalRuleExecutionLimits.MAX_FIELD_CHARS || task.requests >= 128 || Date.now() >= task.deadline) return false;
    task.requests++;
    const origin = LocalRuleHttpClient.requestOrigin(url);
    if (!task.origins.has(origin) && task.origins.size >= 16) return false;
    task.origins.add(origin);
    task.urls.add(url);
    return true;
  }

  intercept(request: WebResourceRequest): WebResourceResponse | null {
    const task = this.active;
    const url = request.getRequestUrl();
    if (task !== undefined && !task.documentServed && request.isMainFrame() && url === task.initial.requestUrl) {
      task.documentServed = true;
      const response = new WebResourceResponse();
      response.setResponseCode(task.initial.statusCode);
      response.setReasonMessage('OK');
      response.setResponseMimeType('text/html');
      response.setResponseEncoding('UTF-8');
      const headers: Header[] = [];
      for (const key of Object.keys(task.initial.headers)) {
        if (['content-length', 'content-encoding', 'transfer-encoding'].includes(key.toLowerCase())) continue;
        headers.push({ headerKey: key, headerValue: task.initial.headers[key] });
      }
      response.setResponseHeader(headers);
      response.setResponseData(task.initial.body);
      return response;
    }
    if (this.allowRequest(url)) return null;
    const response = new WebResourceResponse();
    response.setResponseCode(403);
    response.setReasonMessage('Forbidden');
    response.setResponseData('');
    return response;
  }

  navigate(url: string): boolean {
    const task = this.active;
    if (url === 'about:blank') return false;
    if (task === undefined || !new RegExp('^https?://', 'i').test(url)) return true;
    task.pages++;
    return task.pages > 5 || Date.now() >= task.deadline;
  }

  private schedule(task: LocalRuleBrowserTask): void {
    if (this.active !== task) return;
    task.probe = setTimeout(() => { this.inspect(task); }, 300);
  }

  private async inspect(task: LocalRuleBrowserTask): Promise<void> {
    const controller = this.controller;
    if (this.active !== task || controller === undefined) return;
    try {
      LocalRuleDiagnostics.check(task.variables);
      if (!task.documentServed) { this.schedule(task); return; }
      const raw = await controller.runJavaScript(`(function(){
        var html=document.documentElement?document.documentElement.outerHTML:'';
        if(html.length>${LocalRuleExecutionLimits.MAX_RESPONSE_CHARS})return JSON.stringify({error:'网页内容超过预算'});
        var nodes=0,chars=0;
        var copy=function(value,depth){
          if(depth>12||++nodes>10000||chars>262144)return null;
          if(value===null||typeof value==='boolean'||typeof value==='number')return value;
          if(typeof value==='string'){chars+=value.length;return value.length<65536?value:null;}
          if(typeof value!=='object'||(!Array.isArray(value)&&Object.getPrototypeOf(value)!==Object.prototype))return undefined;
          var out=Array.isArray(value)?[]:{};
          Object.keys(value).slice(0,1000).forEach(function(k){var d=Object.getOwnPropertyDescriptor(value,k);if(d&&'value' in d){var v=copy(d.value,depth+1);if(v!==undefined)out[k]=v;}});return out;
        };
        var state={};Object.keys(window).slice(0,1000).forEach(function(k){
          if(k==='window'||k==='document'||k==='localStorage'||k==='sessionStorage')return;
          var d=Object.getOwnPropertyDescriptor(window,k);if(d&&'value' in d){var v=copy(d.value,0);if(v!==undefined)state[k]=v;}
        });
        var media=[];document.querySelectorAll('audio,video,source').forEach(function(n){var u=n.currentSrc||n.src;if(u)media.push(String(u));});
        return JSON.stringify({html:html,url:String(location.href),ready:document.readyState,state:JSON.stringify(state),media:media});
      })()`);
      if (this.active !== task) return;
      let parsed: Object = JSON.parse(raw);
      if (typeof parsed === 'string') parsed = JSON.parse(parsed);
      const snapshot: Record<string, Object> = JSON.parse(JSON.stringify(parsed));
      if (snapshot['error']) throw new Error(String(snapshot['error']));
      const html = String(snapshot['html'] ?? '');
      const currentUrl = String(snapshot['url'] ?? '');
      if (!new RegExp('^https?://', 'i').test(currentUrl)) { this.schedule(task); return; }
      task.stable = html === task.lastHtml ? task.stable + 1 : 0;
      task.lastHtml = html;
      if (String(snapshot['ready']) !== 'complete' || task.stable < 2) { this.schedule(task); return; }
      const response = new LocalRuleFetchResult();
      response.ok = true;
      response.statusCode = task.initial.statusCode;
      response.headers = task.initial.headers;
      response.body = html;
      response.requestUrl = new RegExp('^https?://', 'i').test(currentUrl) ? currentUrl : task.initial.requestUrl;
      console.info(`[LocalRuleBrowser] rendered ${html.length} characters`);
      response.browserState = String(snapshot['state'] ?? '{}');
      response.resourceUrls = Array.from(task.urls);
      const media: string[] = JSON.parse(JSON.stringify(snapshot['media'] ?? []));
      response.resourceUrls.push(...media);
      this.active = undefined;
      clearTimeout(task.timer);
      clearTimeout(task.probe);
      task.resolve(response);
    } catch (error) {
      if (this.active === task) this.fail(new Error(error instanceof Error ? error.message : String(error)));
    }
  }

  private fail(error: Error): void {
    const task = this.active;
    if (task === undefined) return;
    this.active = undefined;
    clearTimeout(task.timer);
    clearTimeout(task.probe);
    task.reject(error);
  }
}

@ComponentV2
export struct LocalRuleBrowserRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToDisappear(): void { LocalRuleBrowserRuntime.instance.detach(this.controller); }

  build() {
    Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
      .width(1).height(1).opacity(0.01)
      .javaScriptAccess(true).domStorageAccess(false).fileAccess(false)
      .imageAccess(false).onlineImageAccess(false)
      .onPageEnd(() => LocalRuleBrowserRuntime.instance.attach(this.controller))
      .onLoadFinished(() => LocalRuleBrowserRuntime.instance.attach(this.controller))
      .onOverrideUrlLoading((request: WebResourceRequest): boolean => LocalRuleBrowserRuntime.instance.navigate(request.getRequestUrl()))
      .onInterceptRequest((event) => {
        return event === undefined ? null : LocalRuleBrowserRuntime.instance.intercept(event.request);
      })
  }
}
