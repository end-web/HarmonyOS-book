import { BookSource } from './upstream/model/data/Book';
import { BookSourceLoginWebRuntime, LoginRuntimeStep } from './upstream/core/book/BookSourceLoginWebRuntime';
import { BookSourceLoginCrypto } from './upstream/core/book/BookSourceLoginCrypto';
import { BookSourceExecutionJournal } from './upstream/core/book/BookSourceExecutionJournal';
import { AnalyzeUrl } from './upstream/core/rule/AnalyzeUrl';
import { HttpClient } from './upstream/core/http/HttpClient';
import { LightCookieStore, LightSourceRuntime, LightSourceDatabase, LightWebFetchRuntime } from './LightSourceRuntime';

/** Upstream login bridge with bounded evaluation and replayed host effects. */
export class LightSourceLogin {
  private static buildScript(source: BookSource, action: string, responses: Record<string, string>,
    cookies: Record<string, string>, fixedNow: number, randomSeed: number, applied: string[]): string {
    return BookSourceLoginWebRuntime.buildScript(source, action, responses, cookies, fixedNow, randomSeed, applied)
      .replace("const d=document.createElement('div');d.textContent=String(v??'');return d.innerHTML;",
        "if(typeof __lightHtmlBridge==='function')return __lightHtmlBridge('encode',String(v??''));return String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');")
      .replace("const d=document.createElement('textarea');d.innerHTML=String(v??'');return d.value;",
        "if(typeof __lightHtmlBridge==='function')return __lightHtmlBridge('decode',String(v??''));return String(v??'').replace(/&#x([0-9a-f]+);/gi,function(_,n){return String.fromCodePoint(parseInt(n,16));}).replace(/&#([0-9]+);/g,function(_,n){return String.fromCodePoint(Number(n));}).replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,String.fromCharCode(34)).replace(/&apos;|&#39;/g,String.fromCharCode(39)).replace(/&nbsp;/g,String.fromCharCode(160)).replace(/&amp;/g,'&');");
  }
  static async execute(source: BookSource, action: string, browserContent: string = ''): Promise<LoginRuntimeStep> {
    const journal = new BookSourceExecutionJournal();
    const state = JSON.parse(await LightSourceRuntime.host.readState(source.bookSourceUrl) || '{}');
    const pending = action === 'light-login-resume' ? state.lightLoginPending : null;
    let cookies: Record<string, string> = pending?.cookies || {};
    const applied: string[] = pending?.applied || [];
    const fixedNow = pending?.fixedNow || Date.now();
    const randomSeed = pending?.randomSeed || Math.max(1, Math.floor(Math.random() * 0x7fffffff));
    let deadline = Date.now() + 60000;
    if (pending) {
      action = pending.action;
      const resumedSource = Object.assign(new BookSource(),source,pending.source);
      LightSourceRuntime.bindSource(source,resumedSource);
      source = resumedSource;
      journal.responses = pending.responses;
      journal.recordResponse(`browser:${pending.url}`,browserContent);
      for (const url of Object.keys(cookies)) cookies[url] = LightCookieStore.forSource(source.bookSourceUrl).getCookie(url);
    }
    let requests = 0;
    for (let iteration = 0; iteration < 64 && Date.now() < deadline; iteration++) {
      const step = BookSourceLoginWebRuntime.parseResult(await LightSourceRuntime.evaluate(
        this.buildScript(source, action, journal.responses, cookies, fixedNow, randomSeed, applied),source.bookSourceUrl));
      for (const operation of BookSourceLoginWebRuntime.parseCookieOperations(step.cookieOperations)) {
        const key = `${operation.operation}\n${operation.url}\n${operation.name}\n${operation.value}`;
        if (applied.includes(key)) continue;
        if (operation.operation === 'remove') LightCookieStore.forSource(source.bookSourceUrl).removeCookie(operation.url, operation.name);
        else if (operation.operation === 'replace') LightCookieStore.forSource(source.bookSourceUrl).replaceCookies(operation.url, operation.value);
        else LightCookieStore.forSource(source.bookSourceUrl).setCookies(operation.url, operation.value);
        applied.push(key);
        cookies[operation.url] = LightCookieStore.forSource(source.bookSourceUrl).getCookie(operation.url);
      }
      if (step.pendingCrypto) {
        const key = `crypto:${step.pendingCrypto}`;
        if (!journal.hasResponse(key)) journal.recordResponse(key, await BookSourceLoginCrypto.execute(step.pendingCrypto));
        continue;
      }
      if (step.pendingCookie) {
        cookies[step.pendingCookie] = LightCookieStore.forSource(source.bookSourceUrl).getCookie(step.pendingCookie);
        continue;
      }
      if (step.pendingWebView) {
        const key = `webview:${step.pendingWebView}`;
        if (!journal.hasResponse(key)) {
          if (++requests > 12) throw new Error('登录脚本网络请求次数过多');
          const request = JSON.parse(step.pendingWebView) as {url:string;script:string};
          const response = await LightSourceRuntime.withWeb(source.bookSourceUrl, () => LightWebFetchRuntime.get().fetch({url:request.url,method:'GET',headers:{},webJs:request.script,cookieSource:source.bookSourceUrl}));
          if (!response.success) throw new Error(response.error || '网页登录请求失败');
          journal.recordResponse(key, response.body);
        }
        continue;
      }
      if (step.pendingAjax) {
        if (!journal.hasResponse(step.pendingAjax)) {
          if (++requests > 12 || !journal.markRequestStarted(step.pendingAjax)) throw new Error('登录脚本重复请求未完成');
          const requestSource = Object.assign(new BookSource(), source, {variable:step.variable,loginHeader:step.loginHeader,loginInfo:step.loginInfo});
          const response = await new AnalyzeUrl(requestSource, new HttpClient(20000)).fetch(step.pendingAjax);
          if (!response.success && !response.body) throw new Error(response.error || `HTTP ${response.statusCode}`);
          journal.recordResponse(step.pendingAjax, response.body);
          for (const url of Object.keys(cookies)) cookies[url] = LightCookieStore.forSource(source.bookSourceUrl).getCookie(url);
        }
        continue;
      }
      if (step.pendingBrowserAwait && LightSourceRuntime.host.browse) {
        await LightSourceDatabase.getInstance(source).updateBookSourceLoginRuntime(source.bookSourceUrl,
          step.variable, step.loginHeader, step.loginInfo);
        await LightCookieStore.forSource(source.bookSourceUrl).flush();
        let html: string;
        try {
          html = await LightSourceRuntime.host.browse(source.bookSourceUrl, source.bookSourceName,
            step.pendingBrowserAwait, step.requestedHtml, step.requestedInjectJs);
        } finally {
          // The routed page releases its Web lease before completing/cancelling the request.
          const cookieState = JSON.parse(await LightSourceRuntime.host.readState(source.bookSourceUrl) || '{}');
          LightCookieStore.forSource(source.bookSourceUrl).load(JSON.parse(await LightSourceRuntime.host.hydrate(source.bookSourceUrl)),false,
            cookieState.lightCookieRecords || []);
        }
        source.variable = step.variable;
        source.loginHeader = step.loginHeader;
        source.loginInfo = step.loginInfo;
        journal.recordResponse(`browser:${step.pendingBrowserAwait}`, html);
        for (const url of Object.keys(cookies)) cookies[url] = LightCookieStore.forSource(source.bookSourceUrl).getCookie(url);
        deadline = Date.now() + 60000; // Human interaction is outside the script execution budget.
        continue;
      }
      if (step.errorMessage) throw new Error(step.errorMessage);
      await LightSourceDatabase.getInstance(source).updateBookSourceLoginRuntime(source.bookSourceUrl,
        step.variable, step.loginHeader, step.loginInfo);
      if (step.pendingBrowserAwait) {
        await LightSourceRuntime.updateState(source.bookSourceUrl,saved => {
          saved.lightLoginPending = {source,action,responses:journal.responses,cookies,applied,fixedNow,randomSeed,url:step.pendingBrowserAwait};
        });
        step.requestedUrl = step.pendingBrowserAwait;
        return step;
      }
      await LightSourceRuntime.updateState(source.bookSourceUrl,saved => { delete saved.lightLoginPending; });
      return step;
    }
    throw new Error('登录脚本执行超时或超过回放预算');
  }
}
