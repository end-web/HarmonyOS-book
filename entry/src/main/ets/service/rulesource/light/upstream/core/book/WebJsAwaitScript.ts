/**
 * Page-side wrappers that let a `webJs` whose result is a Promise (an `async` function call, a
 * `fetch(...).then(...)` chain) hand back its settled value. `runJavaScript` only reports the
 * synchronous completion value, so a thenable is parked in a window slot and polled.
 *
 * A synchronous `webJs` keeps its exact previous result. Pages whose CSP forbids `eval` report
 * BLOCKED before any source code runs, so the caller can execute the script unwrapped instead.
 */
export class WebJsAwaitScript {
  static readonly PENDING: string = '__legado_webjs_pending__';
  static readonly LOST: string = '__legado_webjs_lost__';
  static readonly BLOCKED: string = '__legado_webjs_eval_blocked__';
  static readonly FAILED_PREFIX: string = '__legado_webjs_failed__:';

  static start(webJs: string, slot: string): string {
    return `(function(){try{(0,eval)('1');}catch(e){return ${JSON.stringify(WebJsAwaitScript.BLOCKED)};}` +
      `var r=(0,eval)(${JSON.stringify(webJs)});` +
      `if(!r||typeof r.then!=='function')return r;` +
      `var s={state:'pending',value:undefined,error:''};window[${JSON.stringify(slot)}]=s;` +
      `r.then(function(v){s.value=v;s.state='done';},` +
      `function(e){s.error=String(e&&e.message?e.message:e);s.state='failed';});` +
      `return ${JSON.stringify(WebJsAwaitScript.PENDING)};})()`;
  }

  static poll(slot: string): string {
    const key = JSON.stringify(slot);
    return `(function(){var s=window[${key}];if(!s)return ${JSON.stringify(WebJsAwaitScript.LOST)};` +
      `if(s.state==='pending')return ${JSON.stringify(WebJsAwaitScript.PENDING)};` +
      `delete window[${key}];` +
      `if(s.state==='failed')return ${JSON.stringify(WebJsAwaitScript.FAILED_PREFIX)}+s.error;` +
      `return s.value;})()`;
  }
}
