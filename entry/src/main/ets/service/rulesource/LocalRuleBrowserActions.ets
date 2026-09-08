import { webview } from '@kit.ArkWeb';
import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';

/** Only this fixed program runs in the page. Script input is JSON data, never executable code. */
export class LocalRuleBrowserActions {
  static readonly PREFIX: string = 'local-rule-browser:';

  static async execute(controller: webview.WebviewController, address: string, session: string,
    deadline: number, variables: Record<string, string>, alive: () => boolean): Promise<string> {
    LocalRuleDiagnostics.check(variables);
    if (!alive() || Date.now() >= deadline) throw new Error('网页交互会话已结束');
    if (address.length > 65536) throw new Error('网页交互输入超过预算');
    const args: Record<string, Object> = JSON.parse(address.substring(LocalRuleBrowserActions.PREFIX.length));
    if (args['operation'] === 'wait') {
      const duration = Number(args['value']);
      if (!Number.isFinite(duration) || duration < 0 || duration > 10000) throw new Error('网页单次等待须在 0 到 10000 毫秒内');
      const until = Date.now() + duration;
      while (Date.now() < until) {
        LocalRuleDiagnostics.check(variables);
        if (!alive() || Date.now() >= deadline) throw new Error('网页交互超时');
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, Math.min(50, until - Date.now())); });
      }
      return '{"value":null}';
    }
    const script = `(function(){try{
      const a=JSON.parse(${JSON.stringify(JSON.stringify(args))}),key=${JSON.stringify(session)};
      let registry=window[key];
      if(!registry){registry={nodes:[document],epoch:Date.now().toString(36)+Math.random().toString(36)};
        Object.defineProperty(window,key,{value:registry,configurable:true});}
      const handle=function(n){if(!n)return null;let id=registry.nodes.indexOf(n);
        if(id<0){if(registry.nodes.length>=2048)throw new Error('DOM node budget exceeded');id=registry.nodes.push(n)-1;}
        return {id:id,epoch:registry.epoch};};
      const node=function(ref){if(!ref||ref.id===0)return document;if(ref.epoch!==registry.epoch)throw new Error('DOM node belongs to a previous page');
        const n=registry.nodes[ref.id];if(!n)throw new Error('Invalid DOM node');return n;};
      const webUrl=function(v){const u=new URL(String(v),location.href);if(!/^https?:$/.test(u.protocol))throw new Error('Navigation requires HTTP(S)');return u.href;};
      const read=['outerHTML','innerHTML','innerText','textContent','value','checked','selected','selectedIndex','disabled',
        'src','currentSrc','href','action','id','className','tagName','nodeName','nodeType','title','readyState','URL','cookie',
        'scrollTop','scrollLeft','scrollHeight','scrollWidth','clientHeight','clientWidth','paused','duration','currentTime'];
      const write=['value','checked','selected','selectedIndex','disabled','textContent','innerText','id','className','title','cookie',
        'scrollTop','scrollLeft','currentTime','src','href','action'];
      const relation=['parentElement','parentNode','firstElementChild','lastElementChild','nextElementSibling','previousElementSibling',
        'documentElement','body','head','activeElement','form'];
      const attributes=['value','checked','selected','disabled','id','class','title','name','type','href','src','action','method','target','rel'];
      const events=['click','input','change','submit','keydown','keyup','keypress','focus','blur','touchstart','touchend'];
      let value=null,n;
      switch(a.operation){
        case 'query': n=node(a.node);value=Array.from(n.querySelectorAll(String(a.selector))).slice(0,1024).map(handle);break;
        case 'read': n=node(a.node);if(!read.includes(a.name))throw new Error('Unsupported DOM property');value=n[a.name]??null;break;
        case 'relation': n=node(a.node);if(!relation.includes(a.name))throw new Error('Unsupported DOM relation');value=handle(n[a.name]);break;
        case 'children': value=Array.from(node(a.node).children||[]).slice(0,1024).map(handle);break;
        case 'set': n=node(a.node);if(!write.includes(a.name))throw new Error('Unsupported DOM write');
          n[a.name]=['src','href','action'].includes(a.name)?webUrl(a.value):a.value;break;
        case 'attribute': value=node(a.node).getAttribute(String(a.name));break;
        case 'setAttribute': case 'removeAttribute':
          if(!attributes.includes(a.name)&&!/^data-[a-z0-9-]+$|^aria-[a-z0-9-]+$/.test(a.name))throw new Error('Unsupported DOM attribute write');
          n=node(a.node);if(a.operation==='removeAttribute')n.removeAttribute(a.name);
          else n.setAttribute(a.name,['src','href','action'].includes(a.name)?webUrl(a.value):String(a.value));break;
        case 'call': n=node(a.node);if(!['click','focus','blur','submit','requestSubmit','pause','play','load','scrollIntoView','remove'].includes(a.name))throw new Error('Unsupported DOM method');
          if(typeof n[a.name]!=='function')throw new Error('DOM method unavailable');
          const outcome=n[a.name]();if(outcome&&typeof outcome.catch==='function')outcome.catch(function(){});break;
        case 'event': if(!events.includes(a.name))throw new Error('Unsupported DOM event');
          const options={bubbles:!!a.bubbles,cancelable:!!a.cancelable,key:String(a.key||''),code:String(a.code||'')};
          value=node(a.node).dispatchEvent(/^key/.test(a.name)?new KeyboardEvent(a.name,options):new Event(a.name,options));break;
        case 'location': value=String(location.href);break;
        case 'locationInfo': if(!['origin','host','hostname','pathname','search','hash','protocol','port'].includes(a.name))throw new Error('Unsupported location property');value=String(location[a.name]);break;
        case 'navigate': location.href=webUrl(a.value);break;
        case 'reload': location.reload();break;
        case 'scroll': window.scrollTo(Number(a.x)||0,Number(a.y)||0);break;
        case 'state':
          value=window;const path=Array.isArray(a.path)?a.path:[];if(path.length>12)throw new Error('Page state depth exceeded');
          for(const part of path){if(['__proto__','constructor','prototype'].includes(part))throw new Error('Invalid state key');
            const d=value&&Object.getOwnPropertyDescriptor(value,String(part));value=d&&'value' in d?d.value:null;}
          const seen=new Set();let nodes=0;
          value=JSON.parse(JSON.stringify(value,function(k,v){if(++nodes>10000)throw new Error('Page state budget exceeded');
            if(v&&typeof v==='object'){if(seen.has(v)||(!Array.isArray(v)&&Object.getPrototypeOf(v)!==Object.prototype))return null;seen.add(v);}
            return typeof v==='function'?null:v;})||'null');break;
        default: throw new Error('Unsupported browser action');
      }
      const output=JSON.stringify({value:value});if(output.length>${LocalRuleExecutionLimits.MAX_RESPONSE_CHARS})throw new Error('Browser result budget exceeded');return output;
    }catch(e){return JSON.stringify({error:String(e.message||e)});}})()`;
    const raw = await LocalRuleBrowserActions.run(controller, script, deadline);
    LocalRuleDiagnostics.check(variables);
    if (!alive() || Date.now() >= deadline) throw new Error('网页交互会话已结束');
    if (raw.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) throw new Error('网页交互输出超过预算');
    const parsed: Object = JSON.parse(raw);
    return typeof parsed === 'string' ? parsed : JSON.stringify(parsed);
  }

  static async run(controller: webview.WebviewController, script: string, deadline: number): Promise<string> {
    if (Date.now() >= deadline) throw new Error('网页交互超时');
    let timer: number = 0;
    try {
      return await Promise.race<string>([
        controller.runJavaScript(script),
        new Promise<string>((_resolve, reject) => { timer = setTimeout(() => reject(new Error('网页交互超时')), deadline - Date.now()); })
      ]);
    } finally { clearTimeout(timer); }
  }
}
