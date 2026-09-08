/** Browser objects below exist only inside bounded QuickJS. */
export class LocalRuleBrowserCompat {
  static code(): string {
    return `
if(V.__browserInteractive==='true'){
  let sequence=0;
  const dom=function(operation,args){const spec='local-rule-browser:'+JSON.stringify(Object.assign({sequence:sequence++,operation:operation},args||{}));
    const raw=request(spec);if(!raw)throw new Error('Browser action pending');const response=JSON.parse(raw);
    if(response.error)throw new Error(response.error);return response.value;};
  const wrap=function(ref){if(!ref)return null;const node={};
    ['outerHTML','innerHTML','innerText','textContent','value','checked','selected','selectedIndex','disabled','src','currentSrc','href','action',
      'id','className','tagName','nodeName','nodeType','title','readyState','URL','cookie','scrollTop','scrollLeft','scrollHeight','scrollWidth',
      'clientHeight','clientWidth','paused','duration','currentTime'].forEach(function(name){Object.defineProperty(node,name,{
        get:function(){return dom('read',{node:ref,name:name});},set:function(value){dom('set',{node:ref,name:name,value:value});}});});
    ['parentElement','parentNode','firstElementChild','lastElementChild','nextElementSibling','previousElementSibling',
      'documentElement','body','head','activeElement','form'].forEach(function(name){Object.defineProperty(node,name,{get:function(){return wrap(dom('relation',{node:ref,name:name}));}});});
    Object.defineProperty(node,'children',{get:function(){return list(dom('children',{node:ref}));}});
    node.querySelectorAll=function(selector){return list(dom('query',{node:ref,selector:String(selector)}));};
    node.querySelector=function(selector){return node.querySelectorAll(selector)[0]||null;};
    node.getAttribute=function(name){return dom('attribute',{node:ref,name:String(name)});};
    node.hasAttribute=function(name){return node.getAttribute(name)!==null;};
    node.setAttribute=function(name,value){dom('setAttribute',{node:ref,name:String(name),value:String(value)});};
    node.removeAttribute=function(name){dom('removeAttribute',{node:ref,name:String(name)});};
    ['click','focus','blur','submit','requestSubmit','pause','play','load','scrollIntoView','remove'].forEach(function(name){node[name]=function(){return dom('call',{node:ref,name:name});};});
    node.dispatchEvent=function(event){return dom('event',{node:ref,name:event.type,bubbles:event.bubbles,cancelable:event.cancelable,key:event.key,code:event.code});};
    node.getElementsByTagName=function(name){return node.querySelectorAll(String(name));};
    node.getElementsByClassName=function(name){return node.querySelectorAll(String(name).trim().split(/\\s+/).map(function(n){return '[class~='+JSON.stringify(n)+']';}).join(''));};
    return node;
  };
  const list=function(values){const out=values.map(wrap);Object.defineProperty(out,'item',{value:function(i){return out[i]||null;}});return out;};
  const document=wrap({id:0,epoch:''});
  // The document handle follows navigations; element handles keep their page identity.
  document.querySelectorAll=function(selector){return list(dom('query',{selector:String(selector)}));};
  document.querySelector=function(selector){return document.querySelectorAll(selector)[0]||null;};
  document.getElementById=function(id){return document.querySelector('[id='+JSON.stringify(String(id))+']');};
  const location={toString:function(){return dom('location');},assign:function(url){dom('navigate',{value:String(url)});},
    replace:function(url){dom('navigate',{value:String(url)});},reload:function(){dom('reload');}};
  Object.defineProperty(location,'href',{get:function(){return dom('location');},set:function(url){location.assign(url);}});
  ['origin','host','hostname','pathname','search','hash','protocol','port'].forEach(function(name){
    Object.defineProperty(location,name,{get:function(){return dom('locationInfo',{name:name});}});});
  const window=Object.assign({},parseValue(V.__browserState||'{}'));
  Object.keys(window).forEach(function(k){Object.defineProperty(window,k,{get:function(){return dom('state',{path:[k]});},configurable:true});});
  window.window=window;window.document=document;window.scrollTo=function(x,y){dom('scroll',{x:x,y:y});};
  Object.defineProperty(window,'location',{get:function(){return location;},set:function(v){location.assign(v);}});
  java.sleep=function(ms){dom('wait',{value:Number(ms)});scriptElapsed+=Number(ms);};
  function BrowserEvent(type,options){this.type=String(type);Object.assign(this,options||{});}
  let timerSequence=0,clock=0;const timers=[];
  const setTimer=function(callback,delay,repeat,args){if(typeof callback!=='function')throw new Error('Timer requires a function');
    if(timers.length>=64)throw new Error('Timer budget exceeded');const timer={id:++timerSequence,callback:callback,due:clock+Math.max(0,Number(delay)||0),
      delay:Math.max(1,Number(delay)||0),repeat:repeat,args:args,active:true};timers.push(timer);return timer.id;};
  const clearTimer=function(id){timers.forEach(function(t){if(t.id===id)t.active=false;});};
  globalThis.__drainBrowserTimers=function(){let count=0;
    while(timers.some(function(t){return t.active;})){if(++count>64)throw new Error('Timer callback budget exceeded');
      const next=timers.filter(function(t){return t.active;}).sort(function(a,b){return a.due-b.due||a.id-b.id;})[0];
      java.sleep(Math.max(0,next.due-clock));clock=next.due;next.active=next.repeat;next.due=clock+next.delay;next.callback(...next.args);}};
  window.setTimeout=function(fn,ms,...args){return setTimer(fn,ms,false,args);};window.setInterval=function(fn,ms,...args){return setTimer(fn,ms,true,args);};
  window.clearTimeout=clearTimer;window.clearInterval=clearTimer;
  Object.assign(globalThis,{window:window,document:document,location:location,Event:BrowserEvent,MouseEvent:BrowserEvent,
    KeyboardEvent:BrowserEvent,InputEvent:BrowserEvent,setTimeout:window.setTimeout,setInterval:window.setInterval,clearTimeout:clearTimer,clearInterval:clearTimer});
}
`;
  }
}
