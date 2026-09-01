import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { WebEngineGate } from '../WebEngineGate';
import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';

export class LocalRuleWebExtractMode {
  static readonly TEXT: string = 'text';
  static readonly HTML: string = 'html';
  static readonly OUTER_HTML: string = 'outerHtml';
  static readonly OWN_TEXT: string = 'ownText';
  static readonly TEXT_NODES: string = 'textNodes';
  static readonly ATTRIBUTE: string = 'attribute';
}

class LocalRuleWebTask {
  html: string = '';
  selector: string = '';
  xpath: boolean = false;
  mode: string = LocalRuleWebExtractMode.TEXT;
  attribute: string = '';
  resolve: (values: string[]) => void = (_values: string[]): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
  timerId: number = 0;
  settled: boolean = false;
}

/**
 * 受控 DOM 解析宿主。HTML 只传给 DOMParser，不通过 loadUrl/loadData 执行站点脚本或发起子资源请求。
 * 所有任务串行，避免多个规则源共享 controller 时相互污染。
 */
export class LocalRuleWebRuntime {
  private static singleton: LocalRuleWebRuntime | undefined = undefined;
  private controller: webview.WebviewController | undefined = undefined;
  private controllerReady: Promise<void> | undefined = undefined;
  private resolveControllerReady: (() => void) | undefined = undefined;
  private queue: LocalRuleWebTask[] = [];
  private busy: boolean = false;

  static get instance(): LocalRuleWebRuntime {
    if (LocalRuleWebRuntime.singleton === undefined) {
      LocalRuleWebRuntime.singleton = new LocalRuleWebRuntime();
    }
    return LocalRuleWebRuntime.singleton;
  }

  setController(controller: webview.WebviewController): void {
    this.controller = controller;
    const resolveReady = this.resolveControllerReady;
    if (resolveReady !== undefined) {
      this.resolveControllerReady = undefined;
      resolveReady();
    }
  }

  async select(html: string, selector: string, xpath: boolean, mode: string,
    attribute: string = ''): Promise<string[]> {
    if (html.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) {
      throw new Error('HTML 超出 DOM 解析预算');
    }
    await this.ensureController();
    return new Promise<string[]>((resolve, reject) => {
      const task = new LocalRuleWebTask();
      task.html = html;
      task.selector = selector;
      task.xpath = xpath;
      task.mode = mode;
      task.attribute = attribute;
      task.resolve = resolve;
      task.reject = reject;
      task.timerId = setTimeout((): void => {
        this.failTimedOutTask(task);
      }, 10000);
      this.queue.push(task);
      this.runNext();
    });
  }

  private ensureController(): Promise<void> {
    if (this.controller !== undefined) return Promise.resolve();
    if (this.controllerReady === undefined) {
      this.controllerReady = new Promise<void>((resolve) => {
        this.resolveControllerReady = resolve;
      });
      WebEngineGate.instance.needRuleParser = true;
    }
    const ready = this.controllerReady;
    return new Promise<void>((resolve, reject) => {
      let settled = false;
      const timerId = setTimeout((): void => {
        if (settled) return;
        settled = true;
        reject(new Error('本地规则 DOM 解析宿主挂载超时'));
      }, 5000);
      ready.then((): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timerId);
        resolve();
      }).catch((): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timerId);
        reject(new Error('本地规则 DOM 解析宿主不可用'));
      });
    });
  }

  private runNext(): void {
    if (this.busy || this.queue.length === 0) return;
    const controller = this.controller;
    const task = this.queue[0];
    if (controller === undefined || task === undefined) return;
    this.busy = true;
    const script = this.buildScript(task);
    controller.runJavaScript(script).then((result: string): void => {
      if (task.settled) return;
      try {
        const values = this.parseResult(result);
        this.completeTask(task, values);
      } catch (error) {
        this.failTask(task, new Error(this.errorMessage(error as Object)));
      }
    }).catch((error: BusinessError): void => {
      this.failTask(task, new Error(`DOM 解析失败：${error.message ?? String(error.code)}`));
    });
  }

  private buildScript(task: LocalRuleWebTask): string {
    const html = JSON.stringify(task.html);
    const selector = JSON.stringify(task.selector);
    const mode = JSON.stringify(task.mode);
    const attribute = JSON.stringify(task.attribute);
    const xpath = task.xpath ? 'true' : 'false';
    const maxNodes = LocalRuleExecutionLimits.MAX_JSON_NODES;
    const maxChars = LocalRuleExecutionLimits.MAX_RESPONSE_CHARS;
    return `(function(){try{
      var html=${html}, selector=${selector}, mode=${mode}, attribute=${attribute}, useXpath=${xpath};
      var doc=(new DOMParser()).parseFromString(html,'text/html');
      var nodes=[];
      if(useXpath){
        var evaluated=doc.evaluate(selector,doc,null,XPathResult.ORDERED_NODE_SNAPSHOT_TYPE,null);
        for(var xi=0;xi<evaluated.snapshotLength&&nodes.length<${maxNodes};xi++)nodes.push(evaluated.snapshotItem(xi));
      }else if(selector.indexOf('text.')===0){
        var needle=selector.substring(5), all=doc.querySelectorAll('*');
        for(var ti=0;ti<all.length&&nodes.length<${maxNodes};ti++){
          var own='';
          for(var tc=0;tc<all[ti].childNodes.length;tc++)if(all[ti].childNodes[tc].nodeType===3)own+=all[ti].childNodes[tc].nodeValue||'';
          if(own.indexOf(needle)>=0)nodes.push(all[ti]);
        }
      }else if(!selector){
        var root=doc.body&&doc.body.children.length===1?doc.body.firstElementChild:doc.body;
        if(root)nodes.push(root);
      }else{
        var containsText='', indexMode='', indexValue=0;
        selector=selector.replace(/:contains\\(\\s*(["']?)(.*?)\\1\\s*\\)/gi,function(_all,_quote,text){
          containsText=String(text||'');return '';
        });
        selector=selector.replace(/:(eq|lt|gt)\\(\\s*(-?\\d+)\\s*\\)\\s*$/i,function(_all,kind,index){
          indexMode=String(kind||'').toLowerCase();indexValue=Number(index||0);return '';
        });
        selector=selector.replace(/:(first|last)\\s*$/i,function(_all,kind){
          indexMode=String(kind||'').toLowerCase();return '';
        });
        var selected=doc.querySelectorAll(selector||'*'), filtered=[];
        for(var si=0;si<selected.length&&filtered.length<${maxNodes};si++){
          var candidate=selected[si];
          if(containsText&&String(candidate.textContent||'').indexOf(containsText)<0)continue;
          filtered.push(candidate);
        }
        if(indexMode==='first'&&filtered.length>0)nodes.push(filtered[0]);
        else if(indexMode==='last'&&filtered.length>0)nodes.push(filtered[filtered.length-1]);
        else if(indexMode==='eq'){
          var eqIndex=indexValue<0?filtered.length+indexValue:indexValue;
          if(eqIndex>=0&&eqIndex<filtered.length)nodes.push(filtered[eqIndex]);
        }else if(indexMode==='lt'){
          var ltEnd=indexValue<0?filtered.length+indexValue:indexValue;
          for(var li=0;li<filtered.length&&li<ltEnd&&nodes.length<${maxNodes};li++)nodes.push(filtered[li]);
        }else if(indexMode==='gt'){
          var gtStart=indexValue<0?filtered.length+indexValue:indexValue;
          for(var gi=gtStart+1;gi<filtered.length&&nodes.length<${maxNodes};gi++)if(gi>=0)nodes.push(filtered[gi]);
        }else{
          for(var fi=0;fi<filtered.length&&nodes.length<${maxNodes};fi++)nodes.push(filtered[fi]);
        }
      }
      var out=[], total=0;
      for(var i=0;i<nodes.length;i++){
        var node=nodes[i], value='';
        if(!node)continue;
        if(node.nodeType===2||node.nodeType===3){value=node.nodeValue||'';}
        else if(mode==='outerHtml'){value=node.outerHTML||'';}
        else if(mode==='html'){value=node.innerHTML||'';}
        else if(mode==='ownText'||mode==='textNodes'){
          var pieces=[];
          for(var c=0;c<node.childNodes.length;c++)if(node.childNodes[c].nodeType===3)pieces.push(node.childNodes[c].nodeValue||'');
          value=mode==='textNodes'?pieces.join('\\n'):pieces.join(' ');
        }else if(mode==='attribute'){value=node.getAttribute?node.getAttribute(attribute)||'':'';}
        else{value=node.textContent||'';}
        if(mode!=='outerHtml'&&mode!=='html')value=String(value).replace(/\\u00a0/g,' ').replace(/[ \\t\\f\\v]+/g,' ').trim();
        total+=value.length;
        if(total>${maxChars})break;
        out.push(value);
      }
      return JSON.stringify(out);
    }catch(e){return JSON.stringify(['__LOCAL_RULE_ERROR__'+String(e&&e.message?e.message:e)]);}})()`;
  }

  private parseResult(result: string): string[] {
    let payload = result || '[]';
    if (payload.length >= 2 && payload.charAt(0) === '"' && payload.charAt(payload.length - 1) === '"') {
      const decoded = JSON.parse(payload) as Object;
      payload = typeof decoded === 'string' ? decoded : '[]';
    }
    const parsed = JSON.parse(payload) as Object;
    if (!Array.isArray(parsed)) return [];
    const values = parsed as Object[];
    const output: string[] = [];
    for (const value of values) {
      if (value === undefined || value === null) continue;
      const text = String(value);
      if (text.startsWith('__LOCAL_RULE_ERROR__')) {
        throw new Error(text.substring('__LOCAL_RULE_ERROR__'.length));
      }
      output.push(text);
    }
    return output;
  }

  private completeTask(task: LocalRuleWebTask, values: string[]): void {
    if (task.settled) return;
    task.settled = true;
    clearTimeout(task.timerId);
    task.resolve(values);
    this.removeTask(task);
  }

  private failTask(task: LocalRuleWebTask, error: Error): void {
    if (task.settled) return;
    task.settled = true;
    clearTimeout(task.timerId);
    task.reject(error);
    this.removeTask(task);
  }

  private failTimedOutTask(task: LocalRuleWebTask): void {
    if (task.settled) return;
    task.settled = true;
    task.reject(new Error('本地规则 DOM 解析超时'));
    this.removeTask(task);
  }

  private removeTask(task: LocalRuleWebTask): void {
    const index = this.queue.indexOf(task);
    if (index >= 0) this.queue.splice(index, 1);
    if (index === 0) this.busy = false;
    this.runNext();
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error || '未知错误');
  }
}

/** MainPage 按 WebEngineGate.needRuleParser 为 true 时挂载。 */
@ComponentV2
export struct LocalRuleWebRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private runtime: LocalRuleWebRuntime = LocalRuleWebRuntime.instance;

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(0)
      .height(0)
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .imageAccess(false)
      .onlineImageAccess(false)
      .onControllerAttached((): void => {
        this.runtime.setController(this.controller);
      })
  }
}
