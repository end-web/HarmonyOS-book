import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleScriptState } from '../../model/LocalRuleScriptState';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { LocalRuleHttpClient } from './LocalRuleHttpClient';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';
import { LocalRuleScriptCompat } from './LocalRuleScriptCompat';
import { LocalRuleScriptActions } from './LocalRuleScriptActions';
import { LocalRuleTemplate } from './LocalRuleTemplate';
import { LocalRuleScriptLibrary } from './LocalRuleScriptLibrary';
import {
  LocalRuleQuickJsRequest,
  LocalRuleQuickJsResult,
  LocalRuleQuickJsRuntime
} from './LocalRuleQuickJsRuntime';
import { LocalRuleExecutionLimits, LocalRuleFetchResult } from './LocalRuleRuntimeTypes';

class LocalRuleScriptStep {
  value: string = '';
  pendingAddress: string = '';
  variables: Record<string, string> = {};
  errorMessage: string = '';
  sourceState: string = '';
}

/**
 * 本地规则脚本的受控 QuickJS 运行时。
 *
 * 网络请求采用“动作请求 -> 原生执行 -> 响应重放”，规则脚本无法直接使用 fetch/XHR。
 * 每个阶段使用独立输入和变量副本，完成后才提交变量，避免失败脚本污染后续规则。
 */
export class LocalRuleScriptRuntime {
  private static readonly MAX_SCRIPT_CHARS: number = 2 * 1024 * 1024;
  private static readonly MAX_REPLAY_STEPS: number = 64;
  private static readonly MAX_ACTION_RESPONSE_CHARS: number = 4 * 1024 * 1024;
  private static pendingBySource: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private static transientState: WeakMap<LocalRuleSource, string> = new WeakMap<LocalRuleSource, string>();

  static hasScript(rule: string): boolean {
    const value = rule.trim().toLowerCase();
    return value.startsWith('@js:') || value.startsWith('js:') ||
      value.includes('<js>') || value.includes('</js>');
  }

  static standaloneCode(rule: string): string {
    const value = rule.trim();
    const lower = value.toLowerCase();
    if (lower.startsWith('@js:')) return value.substring(4).trim();
    if (lower.startsWith('js:')) return value.substring(3).trim();
    if (lower.startsWith('<js>') && lower.endsWith('</js>')) {
      return value.substring(4, value.length - 5).trim();
    }
    return '';
  }

  static async resolveAddress(rawRule: string, source: LocalRuleSource,
    variables: Record<string, string>, keyword: string = '', page: number = 1): Promise<string> {
    const scoped = LocalRuleScriptRuntime.copyVariables(variables);
    scoped['key'] = keyword;
    scoped['searchKey'] = keyword;
    scoped['keyword'] = keyword;
    scoped['searchKeyRaw'] = keyword;
    scoped['page'] = String(Math.max(1, page));
    scoped['pageIndex'] = String(Math.max(1, page));
    const result = await LocalRuleScriptRuntime.resolveText(rawRule, source.bookSourceUrl, source, scoped, true);
    LocalRuleScriptRuntime.replaceVariables(variables, scoped);
    return result;
  }

  /** 计算 Legado 字段中的 @js/<js> 与 {{ JavaScript 表达式 }}，失败表达式原样保留。 */
  static async resolveText(rawRule: string, baseUrl: string, source: LocalRuleSource,
    variables: Record<string, string>, requestTemplates: boolean = false): Promise<string> {
    const code = LocalRuleScriptRuntime.standaloneCode(rawRule);
    if (code.length > 0) {
      return LocalRuleScriptRuntime.evaluate('', baseUrl, code, source, variables, '');
    }
    let output = '';
    let position = 0;
    while (position < rawRule.length) {
      const start = rawRule.indexOf('{{', position);
      if (start < 0) {
        output += rawRule.substring(position);
        break;
      }
      output += rawRule.substring(position, start);
      const end = LocalRuleTemplate.end(rawRule, start + 2);
      if (end < 0) {
        output += rawRule.substring(start);
        break;
      }
      const expression = rawRule.substring(start + 2, end).trim();
      let replacement = rawRule.substring(start, end + 2);
      const requestParameter = requestTemplates &&
        new RegExp('^(key|keyword|searchKey|searchKeyRaw|page|pageIndex)(\\s*[+-]\\s*\\d+)?$').test(expression);
      if (expression.length > 0 && !requestParameter) {
        try {
          replacement = await LocalRuleScriptRuntime.evaluate(
            '', baseUrl, expression, source, variables, '');
        } catch (_error) {
          // 未知变量可能由后续元素规则提供，保留给下一解析阶段。
        }
      }
      output += replacement;
      position = end + 2;
    }
    return output;
  }

  static async evaluate(content: string, baseUrl: string, code: string,
    source: LocalRuleSource, variables: Record<string, string>, initialResult: string = ''): Promise<string> {
    const sourceKey = source.bookSourceUrl;
    const previous = LocalRuleScriptRuntime.pendingBySource.get(sourceKey);
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve: () => void) => { release = resolve; });
    const pending = previous === undefined ? gate : previous.then(() => gate);
    LocalRuleScriptRuntime.pendingBySource.set(sourceKey, pending);
    if (previous !== undefined) await previous;
    try {
      LocalRuleDiagnostics.check(variables);
      return await LocalRuleScriptRuntime.evaluateLocked(content, baseUrl, code, source, variables, initialResult);
    } finally {
      release();
      if (LocalRuleScriptRuntime.pendingBySource.get(sourceKey) === pending) {
        LocalRuleScriptRuntime.pendingBySource.delete(sourceKey);
      }
    }
  }

  static async evaluateBrowserSnapshot(source: LocalRuleSource, response: LocalRuleFetchResult,
    code: string, variables: Record<string, string>): Promise<string> {
    const scoped = LocalRuleScriptRuntime.copyVariables(variables);
    scoped['__browserSnapshot'] = 'true';
    scoped['__browserState'] = response.browserState || '{}';
    return LocalRuleScriptRuntime.evaluateLocked(response.body, response.requestUrl, code, source, scoped, response.body, true);
  }

  static async transformResponse(source: LocalRuleSource, response: LocalRuleFetchResult,
    code: string, variables: Record<string, string>): Promise<string> {
    const library = await LocalRuleScriptLibrary.load(source, variables);
    return LocalRuleScriptRuntime.evaluateLocked(response.body, response.requestUrl,
      LocalRuleScriptRuntime.standaloneCode(code) || code, source,
      LocalRuleScriptRuntime.copyVariables(variables), response.body, true, library);
  }

  private static async evaluateLocked(content: string, baseUrl: string, code: string,
    source: LocalRuleSource, variables: Record<string, string>, initialResult: string,
    readOnly: boolean = false, readOnlyLibrary: string = ''): Promise<string> {
    const library = readOnly ? readOnlyLibrary : await LocalRuleScriptLibrary.load(source, variables);
    LocalRuleScriptRuntime.validate(code, library);
    const persisted = LocalRuleSourceRepository.isInitialized()
      ? await LocalRuleSourceRepository.readScriptState(source.bookSourceUrl)
      : LocalRuleScriptRuntime.transientState.get(source) ?? '';
    const sourceState = LocalRuleScriptState.parse(persisted, source.variable);
    const originalState = JSON.stringify(sourceState);
    const responses: Record<string, string> = {};
    const initialVariables = LocalRuleScriptRuntime.copyVariables(variables);
    initialVariables['__cookieSnapshot'] = JSON.stringify(await LocalRuleHttpClient.getCookieSnapshot(source.bookSourceUrl));
    if ((initialVariables['__scriptNow'] ?? '').length === 0) {
      initialVariables['__scriptNow'] = String(Date.now());
    }
    if ((initialVariables['__scriptSeed'] ?? '').length === 0) {
      initialVariables['__scriptSeed'] = String((Date.now() + baseUrl.length * 2654435761) >>> 0);
    }
    let responseCharacters = 0;
    let networkActions = 0;
    if (baseUrl.toLowerCase().startsWith('http://') || baseUrl.toLowerCase().startsWith('https://')) {
      await LocalRuleHttpClient.hydrateCookies(source.bookSourceUrl);
      initialVariables['__cookie'] = LocalRuleHttpClient.getCookieHeader(source, baseUrl);
    }
    for (let stepIndex = 0; stepIndex <= LocalRuleScriptRuntime.MAX_REPLAY_STEPS; stepIndex++) {
      LocalRuleDiagnostics.check(variables);
      const script = LocalRuleScriptRuntime.buildScript(content, baseUrl, code, source,
        initialVariables, initialResult, responses, sourceState, library);
      const request = new LocalRuleQuickJsRequest();
      request.script = script;
      request.sourceUrl = source.bookSourceUrl;
      const execution: LocalRuleQuickJsResult = await LocalRuleQuickJsRuntime.execute(request);
      if (!execution.success) {
        const detail = execution.timedOut ? '执行超时' : (execution.errorMessage || '未知错误');
        throw new Error(`书源脚本执行失败：${detail}`);
      }
      const raw = execution.value;
      const step = LocalRuleScriptRuntime.parseStep(raw);
      if (step.pendingAddress.length > 0) {
        if (stepIndex >= LocalRuleScriptRuntime.MAX_REPLAY_STEPS) {
          throw new Error(`书源脚本动作超过 ${LocalRuleScriptRuntime.MAX_REPLAY_STEPS} 步`);
        }
        if (step.pendingAddress.startsWith(LocalRuleScriptActions.PREFIX)) {
          const actionResult = await LocalRuleScriptActions.execute(step.pendingAddress, source, initialVariables, baseUrl);
          responseCharacters += actionResult.length;
          if (responseCharacters > LocalRuleScriptRuntime.MAX_ACTION_RESPONSE_CHARS) throw new Error('书源脚本动作响应超过 4 MiB 预算');
          responses[step.pendingAddress] = actionResult;
          continue;
        }
        networkActions++;
        if (readOnly) throw new Error('响应转换只读取当前数据；网络请求应在书源请求规则中声明');
        if (networkActions > 32) throw new Error('书源脚本网络动作超过 32 步');
        const actionVariables = LocalRuleScriptRuntime.copyVariables(initialVariables);
        LocalRuleScriptRuntime.replaceVariables(actionVariables, step.variables, true);
        if (step.sourceState.length > 0) {
          const actionState = LocalRuleScriptState.parse(step.sourceState);
          actionVariables['__sourceLoginHeader'] = actionState.loginHeader;
          actionVariables['__useActionLoginHeader'] = 'true';
        }
        const response: LocalRuleFetchResult = await LocalRuleHttpClient.fetch(
          source, step.pendingAddress, actionVariables);
        if (!response.ok && response.statusCode === 0) {
          throw new Error(`书源脚本请求失败：${response.errorMessage || '未知错误'}`);
        }
        responseCharacters += response.body.length;
        if (responseCharacters > LocalRuleScriptRuntime.MAX_ACTION_RESPONSE_CHARS) {
          throw new Error('书源脚本网络动作响应超过 4 MiB 预算');
        }
        responses[step.pendingAddress] = LocalRuleScriptRuntime.encodeResponse(response);
        continue;
      }
      if (step.errorMessage.length > 0) throw new Error(`书源脚本执行失败：${step.errorMessage}`);
      LocalRuleDiagnostics.check(variables);
      if (readOnly) return step.value;
      if (step.sourceState.length > 0 && step.sourceState !== originalState) {
        const finalState = LocalRuleScriptState.parse(step.sourceState);
        const finalStateJson = JSON.stringify(finalState);
        if (finalStateJson.length > 256 * 1024) throw new Error('书源脚本状态超过 256 KiB');
        if (LocalRuleSourceRepository.isInitialized()) {
          await LocalRuleSourceRepository.writeScriptState(source.bookSourceUrl, finalStateJson);
        } else {
          LocalRuleScriptRuntime.transientState.set(source, finalStateJson);
        }
      }
      if (step.variables['__cookieOverrides']) {
        const cookies: Record<string, string> = JSON.parse(step.variables['__cookieOverrides']);
        for (const origin of Object.keys(cookies)) {
          if (LocalRuleSourceRepository.isInitialized() &&
            await LocalRuleSourceRepository.get(source.bookSourceUrl) === undefined) break;
          await LocalRuleHttpClient.saveWebCookies(source.bookSourceUrl, origin, cookies[origin]);
        }
      }
      LocalRuleScriptRuntime.replaceVariables(variables, step.variables);
      return step.value;
    }
    throw new Error('书源脚本没有在执行预算内完成');
  }

  private static validate(code: string, jsLib: string): void {
    const combined = `${jsLib}\n${code}`;
    if (combined.length > LocalRuleScriptRuntime.MAX_SCRIPT_CHARS) {
      throw new Error('书源脚本超过 2 MiB 执行预算');
    }
  }

  private static buildScript(content: string, baseUrl: string, code: string,
    source: LocalRuleSource, variables: Record<string, string>, initialResult: string,
    responses: Record<string, string>, sourceState: LocalRuleScriptState, library: string): string {
    const sourceRecord: Record<string, string> = {};
    sourceRecord['bookSourceUrl'] = source.bookSourceUrl;
    sourceRecord['bookSourceName'] = source.bookSourceName;
    sourceRecord['bookSourceGroup'] = source.bookSourceGroup;
    sourceRecord['bookSourceComment'] = source.bookSourceComment;
    sourceRecord['variable'] = sourceState.variable;
    sourceRecord['definitionVariable'] = sourceState.definitionVariable;
    sourceRecord['values'] = JSON.stringify(sourceState.values);
    sourceRecord['loginInfo'] = sourceState.loginInfo;
    sourceRecord['loginHeader'] = sourceState.loginHeader;

    const input: Record<string, Object> = {};
    input['content'] = content;
    input['baseUrl'] = baseUrl;
    input['code'] = code;
    input['jsLib'] = library;
    input['initialResult'] = initialResult;
    input['variables'] = variables;
    input['responses'] = responses;
    input['source'] = sourceRecord;
    const encoded = JSON.stringify(input);
    const maxOutput = LocalRuleExecutionLimits.MAX_CONTENT_CHARS;

    return `(function(){try{` +
      `const I=${encoded};const V=Object.assign({},I.variables||{});const R=I.responses||{};` +
      `let pending='';const parseValue=function(v){if(typeof v!=='string')return v;` +
      `const t=v.trim();if((t[0]==='{'&&t[t.length-1]==='}')||(t[0]==='['&&t[t.length-1]===']')){` +
      `try{return JSON.parse(t);}catch(_e){}}return v;};` +
      `const src=String(I.content||''),root=parseValue(src);let result=I.initialResult!==''?I.initialResult:src;const $=root;` +
      `const fixedNow=Number(V.__scriptNow||Date.now()),initialSeed=Number(V.__scriptSeed||1)>>>0;let randomSeed=initialSeed||1;` +
      `Date.now=function(){return fixedNow;};Math.random=function(){randomSeed=(randomSeed*1664525+1013904223)>>>0;` +
      `return randomSeed/4294967296;};` +
      `const RealDate=Date;const StableDate=function(...a){if(!new.target)return new RealDate(fixedNow).toString();` +
      `return a.length?new RealDate(...a):new RealDate(fixedNow);};StableDate.now=function(){return fixedNow;};` +
      `StableDate.parse=RealDate.parse;StableDate.UTC=RealDate.UTC;StableDate.prototype=RealDate.prototype;` +
      `const readPath=function(value,path){let p=String(path||'').trim().replace(/^@json:/i,'');` +
      `if(p[0]==='@')p='$'+p.substring(1);if(p[0]!=='$')p='$.'+p;` +
      `const tokens=[];p.replace(/(?:^\\$|\\.([A-Za-z_$][\\w$-]*)|\\[['\"]([^'\"]+)['\"]\\]|\\[(-?\\d+)\\])/g,` +
      `function(_a,dot,key,index){if(dot!=null)tokens.push(dot);else if(key!=null)tokens.push(key);` +
      `else if(index!=null)tokens.push(Number(index));return _a;});let current=value;` +
      `for(let i=0;i<tokens.length;i++){if(current==null)return undefined;let k=tokens[i];` +
      `if(typeof k==='number'&&Array.isArray(current)&&k<0)k=current.length+k;current=current[k];}return current;};` +
      `const stringify=function(v){if(v==null)return '';if(typeof v==='string')return v;` +
      `if(typeof v==='object'){try{return JSON.stringify(v);}catch(_e){return '';}}return String(v);};` +
      `const responseData=function(spec){const key=String(spec==null?'':spec);` +
      `if(!Object.prototype.hasOwnProperty.call(R,key)){if(!pending)pending=key;` +
      `return {body:'',statusCode:599,headers:{},requestUrl:key};}` +
      `const raw=String(R[key]??'');if(raw.indexOf('__LOCAL_RULE_RESPONSE__')===0){` +
      `try{return JSON.parse(raw.substring(23));}catch(_e){}}` +
      `return {body:raw,statusCode:raw?200:599,headers:{},requestUrl:key};};` +
      `const request=function(spec){return String(responseData(spec).body??'');};` +
      `const responseObject=function(spec){const data=responseData(spec);return {body:function(){return String(data.body??'');},` +
      `header:function(name){const h=data.headers||{},key=Object.keys(h).find(function(k){return k.toLowerCase()===String(name).toLowerCase();});return key===undefined?null:String(h[key]);},` +
      `code:function(){return Number(data.statusCode||0);},isSuccessful:function(){const c=Number(data.statusCode||0);return c>=200&&c<400;},` +
      `headers:function(name){const h=Object.assign({},data.headers||{});Object.keys(h).forEach(function(k){h[k.toLowerCase()]=h[k];});if(name===undefined)return h;const expected=String(name).toLowerCase();` +
      `const keys=Object.keys(h);for(let i=0;i<keys.length;i++)if(keys[i].toLowerCase()===expected)return [String(h[keys[i]]??'')];` +
      `return [];},url:function(){return String(data.requestUrl||'');},toString:function(){return String(data.body??'');}};};` +
      `const requestSpec=function(method,u,b,h){const o={method:String(method||'GET').toUpperCase(),redirect:false};` +
      `if(b!==undefined&&b!==null)o.body=typeof b==='string'?b:JSON.stringify(b);` +
      `if(typeof h==='string'){try{h=JSON.parse(h);}catch(_e){h={};}}if(h&&typeof h.toJSON==='function')h=h.toJSON();` +
      `if(h&&typeof h==='object')o.headers=h;return String(u??'')+','+JSON.stringify(o);};` +
      `const utf8Bytes=function(v){const e=encodeURIComponent(String(v??'')),a=[];` +
      `for(let i=0;i<e.length;i++){if(e[i]==='%'&&i+2<e.length){a.push(parseInt(e.substring(i+1,i+3),16));i+=2;}` +
      `else a.push(e.charCodeAt(i)&255);}return a;};` +
      `const utf8String=function(a){let e='';for(let i=0;i<a.length;i++)e+='%'+Number(a[i]&255).toString(16).padStart(2,'0');` +
      `try{return decodeURIComponent(e);}catch(_e){let s='';for(let i=0;i<a.length;i++)s+=String.fromCharCode(a[i]&255);return s;}};` +
      `const b64chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';` +
      `const b64encode=function(v){const a=utf8Bytes(v);let o='';for(let i=0;i<a.length;i+=3){` +
      `const n=(a[i]<<16)|((a[i+1]||0)<<8)|(a[i+2]||0);o+=b64chars[(n>>>18)&63]+b64chars[(n>>>12)&63]+` +
      `(i+1<a.length?b64chars[(n>>>6)&63]:'=')+(i+2<a.length?b64chars[n&63]:'=');}return o;};` +
      `const b64decode=function(v){const s=String(v??'').replace(/[^A-Za-z0-9+\\/=]/g,'');const a=[];` +
      `for(let i=0;i<s.length;i+=4){const c1=b64chars.indexOf(s[i]),c2=b64chars.indexOf(s[i+1]);` +
      `const c3=s[i+2]==='='?-1:b64chars.indexOf(s[i+2]),c4=s[i+3]==='='?-1:b64chars.indexOf(s[i+3]);` +
      `if(c1<0||c2<0)continue;const n=(c1<<18)|(c2<<12)|((c3<0?0:c3)<<6)|(c4<0?0:c4);` +
      `a.push((n>>>16)&255);if(c3>=0)a.push((n>>>8)&255);if(c4>=0)a.push(n&255);}return utf8String(a);};` +
      `const hexEncode=function(v){return utf8Bytes(v).map(function(x){return Number(x).toString(16).padStart(2,'0');}).join('');};` +
      `const hexDecode=function(v){const s=String(v??'').replace(/\\s+/g,''),a=[];` +
      `for(let i=0;i+1<s.length;i+=2){const n=parseInt(s.substring(i,i+2),16);if(!Number.isNaN(n))a.push(n);}return utf8String(a);};` +
      `const htmlEncode=function(v){return String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;')` +
      `.replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');};` +
      `const htmlDecode=function(v){return String(v??'').replace(/&#(x?[0-9a-f]+);/gi,function(_m,n){` +
      `const x=String(n).toLowerCase().startsWith('x')?parseInt(String(n).substring(1),16):parseInt(String(n),10);` +
      `return Number.isFinite(x)?String.fromCodePoint(x):_m;}).replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'")` +
      `.replace(/&lt;/gi,'<').replace(/&gt;/gi,'>').replace(/&nbsp;/gi,' ').replace(/&amp;/gi,'&');};` +
      `const md5=function(v){const a=utf8Bytes(v),bits=a.length*8;a.push(128);while(a.length%64!==56)a.push(0);` +
      `for(let i=0;i<8;i++)a.push(Math.floor(bits/Math.pow(256,i))&255);` +
      `let aa=0x67452301|0,bb=0xefcdab89|0,cc=0x98badcfe|0,dd=0x10325476|0;` +
      `const sh=[7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,` +
      `4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];` +
      `const kk=[];for(let i=0;i<64;i++)kk[i]=Math.floor(Math.abs(Math.sin(i+1))*4294967296)|0;` +
      `for(let p=0;p<a.length;p+=64){const m=[];for(let i=0;i<16;i++){const q=p+i*4;` +
      `m[i]=(a[q]|(a[q+1]<<8)|(a[q+2]<<16)|(a[q+3]<<24))|0;}const oa=aa,ob=bb,oc=cc,od=dd;` +
      `for(let i=0;i<64;i++){let f=0,g=0;if(i<16){f=(bb&cc)|((~bb)&dd);g=i;}` +
      `else if(i<32){f=(dd&bb)|((~dd)&cc);g=(5*i+1)%16;}else if(i<48){f=bb^cc^dd;g=(3*i+5)%16;}` +
      `else{f=cc^(bb|(~dd));g=(7*i)%16;}const old=dd;dd=cc;cc=bb;` +
      `const x=(aa+f+kk[i]+m[g])|0;bb=(bb+((x<<sh[i])|(x>>>(32-sh[i]))))|0;aa=old;}` +
      `aa=(aa+oa)|0;bb=(bb+ob)|0;cc=(cc+oc)|0;dd=(dd+od)|0;}` +
      `const wh=function(x){let o='';for(let i=0;i<4;i++)o+=((x>>>(i*8))&255).toString(16).padStart(2,'0');return o;};` +
      `return wh(aa)+wh(bb)+wh(cc)+wh(dd);};` +
      `const C=JSON.parse(V.__cookieSnapshot||'{}'),CW={};` +
      `const cookieOrigin=function(u){const m=/^(https?:\\/\\/[^/?#]+)/i.exec(String(u||I.baseUrl));` +
      `if(!m)throw new Error('Cookie requires an HTTP(S) origin');return m[1].toLowerCase();};` +
      `const cookieRead=function(u){const o=cookieOrigin(u);return Object.prototype.hasOwnProperty.call(CW,o)?CW[o]:(C[o]||'');};` +
      `const cookieWrite=function(u,v,merge){const o=cookieOrigin(u),jar={};` +
      `const parse=function(s){String(s||'').split(';').forEach(function(x){const p=x.indexOf('=');if(p>0)jar[x.slice(0,p).trim()]=x.slice(p+1).trim();});};` +
      `if(merge)parse(cookieRead(u));parse(v);CW[o]=Object.keys(jar).map(function(k){return k+'='+jar[k];}).join('; ');` +
      `V.__cookieOverrides=JSON.stringify(CW);return v;};` +
      `const cookie={getCookie:cookieRead,getKey:function(a,b){const name=String(b===undefined?a:b);` +
      `const parts=cookieRead(b===undefined?I.baseUrl:a).split(';');for(let i=0;i<parts.length;i++){const x=parts[i].trim();` +
      `if(x.substring(0,name.length+1)===name+'=')return x.substring(name.length+1);}return '';},` +
      `setCookie:function(u,v){return cookieWrite(u,v,true);},replaceCookie:function(u,v){return cookieWrite(u,v,false);},` +
      `removeCookie:function(u,n){const name=String(n??'');const value=name?cookieRead(u).split(';').filter(function(x){` +
      `return x.trim().substring(0,name.length+1)!==name+'=';}).join(';'):'';cookieWrite(u,value,false);return true;}};` +
      `const isAddress=function(v){const s=String(v??'').trim().toLowerCase();return s.indexOf('http://')===0||` +
      `s.indexOf('https://')===0||s.indexOf('/')===0||s.indexOf('./')===0||s.indexOf('../')===0;};` +
      `const java={ajax:request,ajaxAll:function(v){const list=Array.isArray(v)?v:[v];return list.map(responseObject);},` +
      `get:function(k,h){if(arguments.length>1||isAddress(k))return responseObject(requestSpec('GET',k,null,h));` +
      `const variableKey=String(k??'');return Object.prototype.hasOwnProperty.call(V,variableKey)?V[variableKey]:null;},` +
      `post:function(u,b,h){return responseObject(requestSpec('POST',u,b,h));},` +
      `connect:function(u,h){return responseObject(requestSpec('GET',u,null,h));},` +
      `delete:function(u,h){return responseObject(requestSpec('DELETE',u,null,h));},` +
      `put:function(k,v){V[String(k||'')]=stringify(v);return v;},getVariable:function(k){return V[String(k||'')]??'';},` +
      `getString:function(p){return stringify(readPath(root,p));},getStringList:function(p){const v=readPath(root,p);` +
      `return Array.isArray(v)?v.map(stringify):(v==null?[]:[stringify(v)]);},` +
      `base64Encode:b64encode,base64EncodeToString:b64encode,base64Decode:b64decode,` +
      `base64DecodeToString:b64decode,hexEncodeToString:hexEncode,hexDecodeToString:hexDecode,` +
      `md5:md5,md5Encode:md5,md5Encode32:md5,md5Encode16:function(v){return md5(v).substring(8,24);},` +
      `urlEncode:function(v){return encodeURIComponent(String(v??''));},` +
      `urlDecode:function(v){return decodeURIComponent(String(v??''));},encodeURI:function(v){return encodeURI(String(v??''));},` +
      `htmlDecode:htmlDecode,htmlEncode:htmlEncode,getCookie:function(u,n){return arguments.length>1?cookie.getKey(u,n):cookie.getCookie(u);},` +
      `getWebViewUA:function(){return 'Mozilla/5.0 Mobile Safari/537.36';},` +
      `timeFormat:function(v){const d=new Date(Number(v)||fixedNow);return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+` +
      `'-'+String(d.getDate()).padStart(2,'0')+' '+String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');},` +
      `randomUUID:function(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,function(c){` +
      `const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16);});},` +
      `lang:function(){return 'zh';},log:function(){},toast:function(){},longToast:function(){}};` +
      `const S=Object.assign({},I.source||{}),SV=JSON.parse(S.values||'{}');const source={bookSourceUrl:S.bookSourceUrl||'',` +
      `bookSourceName:S.bookSourceName||'',bookSourceGroup:S.bookSourceGroup||'',variable:S.variable||'',` +
      `key:S.bookSourceUrl||'',tag:S.bookSourceName||'',` +
      `getKey:function(){return S.bookSourceUrl||'';},getTag:function(){return S.bookSourceName||'';},` +
      `getSource:function(){return source;},getVariable:function(){return S.variable||'';},` +
      `setVariable:function(v){S.variable=String(v??'');source.variable=S.variable;return S.variable;},` +
      `get:function(k){const key=String(k||'');return Object.prototype.hasOwnProperty.call(SV,key)?SV[key]:(S[key]??V[key]??'');},` +
      `put:function(k,v){const key=String(k||'');SV[key]=stringify(v);return v;},` +
      `getLoginInfo:function(){return S.loginInfo||'';},getLoginInfoMap:function(){try{return JSON.parse(S.loginInfo||'{}');}catch(_e){return {}; }},` +
      `putLoginInfo:function(v){S.loginInfo=stringify(v);return v;},getLoginHeader:function(){return S.loginHeader||'';},` +
      `putLoginHeader:function(v){S.loginHeader=stringify(v);return v;}};` +
      `const cache={get:function(k){const key='cache.'+String(k),expiry=Number(SV[key+'.expires']||0);` +
      `if(expiry>0&&fixedNow>=expiry)return null;return Object.prototype.hasOwnProperty.call(SV,key)?SV[key]:null;},` +
      `put:function(k,v,seconds){const key='cache.'+String(k);SV[key]=stringify(v);` +
      `SV[key+'.expires']=String(Number(seconds)>0?fixedNow+Number(seconds)*1000:0);return v;},` +
      `delete:function(k){delete SV['cache.'+String(k)];delete SV['cache.'+String(k)+'.expires'];}};` +
      `const infoMap=parseValue(V.infoMap||S.loginInfo||'{}');` +
      `if(infoMap&&typeof infoMap==='object'){Object.defineProperties(infoMap,{` +
      `get:{value:function(k){return this[String(k)]??null;}},` +
      `put:{value:function(k,v){this[String(k)]=v;return v;}},` +
      `save:{value:function(){source.putLoginInfo(this);}}});}` +
      `java.refreshExplore=function(){V.__refreshExplore='true';};` +
      `java.searchBook=function(k){V.__searchBook=String(k||'');};` +
      `java.toast=function(v){V.__toast=String(v||'').substring(0,512);};java.longToast=java.toast;` +
      `const book=Object.assign({},V);book.getVariable=function(k){return V[String(k??'')]??'';};` +
      `book.putVariable=function(k,v){V[String(k??'')]=stringify(v);return v;};book.setVariable=book.putVariable;` +
      `const chapter=Object.assign({},V);chapter.name=V.chapterName||V.title||'';chapter.title=chapter.name;` +
      `chapter.index=Number(V.chapterIndex||0);chapter.url=V.chapterUrl||I.baseUrl;` +
      `chapter.getVariable=book.getVariable;chapter.putVariable=book.putVariable;` +
      `const baseUrl=String(I.baseUrl||''),url=baseUrl,key=String(V.key??V.searchKey??''),` +
      `searchKey=String(V.searchKey??key),page=Number(V.page||1),pageIndex=Number(V.pageIndex||page),title=String(V.title??'');` +
      LocalRuleScriptCompat.code() +
      `const args=['result','$','java','source','cookie','baseUrl','book','chapter','src','url','key','searchKey',` +
      `'page','pageIndex','title','cache','infoMap','Date','__code'];let runner=new Function(...args,String(I.jsLib||'')+'\\nreturn eval(__code);');` +
      `let value='';try{value=runner(result,$,java,source,cookie,baseUrl,book,chapter,src,url,key,searchKey,page,pageIndex,title,cache,infoMap,StableDate,String(I.code||''));}` +
      `catch(e){if(!pending&&e instanceof SyntaxError){runner=new Function(...args,String(I.jsLib||'')+'\\n'+String(I.code||'')+` +
      `'\\n;return typeof result===\\'undefined\\'?\\'\\':result;');value=runner(result,$,java,source,cookie,baseUrl,book,chapter,` +
      `src,url,key,searchKey,page,pageIndex,title,cache,infoMap,StableDate,String(I.code||''));}else if(!pending)throw e;}` +
      `if(value===undefined)value=result;value=stringify(value);` +
      `if(value.length>${maxOutput})throw new Error('脚本输出超过预算');` +
      `return JSON.stringify({value:value,pendingAddress:pending,variables:V,errorMessage:'',` +
      `sourceState:JSON.stringify({variable:S.variable||'',definitionVariable:S.definitionVariable||'',` +
      `values:SV,loginInfo:S.loginInfo||'',loginHeader:S.loginHeader||''})});` +
      `}catch(e){return JSON.stringify({value:'',pendingAddress:'',variables:{},` +
      `errorMessage:String(e&&e.message?e.message:e)});}})()`;
  }

  private static parseStep(raw: string): LocalRuleScriptStep {
    const step = new LocalRuleScriptStep();
    try {
      const parsed = JSON.parse(raw) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        step.errorMessage = '脚本结果格式无效';
        return step;
      }
      const record = parsed as Record<string, Object>;
      step.value = LocalRuleScriptRuntime.scalar(record['value']);
      step.pendingAddress = LocalRuleScriptRuntime.scalar(record['pendingAddress']);
      step.errorMessage = LocalRuleScriptRuntime.scalar(record['errorMessage']);
      step.sourceState = LocalRuleScriptRuntime.scalar(record['sourceState']);
      const rawVariables = record['variables'];
      if (rawVariables !== undefined && rawVariables !== null && typeof rawVariables === 'object' &&
        !Array.isArray(rawVariables)) {
        const sourceVariables = rawVariables as Record<string, Object>;
        const keys = Object.keys(sourceVariables);
        for (const key of keys) step.variables[key] = LocalRuleScriptRuntime.scalar(sourceVariables[key]);
      }
    } catch (error) {
      step.errorMessage = LocalRuleScriptRuntime.errorMessage(error as Object);
    }
    return step;
  }

  private static scalar(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'object') {
      try {
        return JSON.stringify(value);
      } catch (_error) {
        return '';
      }
    }
    return String(value);
  }

  private static encodeResponse(response: LocalRuleFetchResult): string {
    const record: Record<string, Object> = {};
    record['body'] = response.body;
    record['statusCode'] = response.statusCode;
    record['headers'] = response.headers;
    record['requestUrl'] = response.requestUrl;
    return `__LOCAL_RULE_RESPONSE__${JSON.stringify(record)}`;
  }

  private static copyVariables(input: Record<string, string>): Record<string, string> {
    const output: Record<string, string> = {};
    const keys = Object.keys(input);
    for (const key of keys) output[key] = input[key] ?? '';
    return output;
  }

  private static replaceVariables(target: Record<string, string>, source: Record<string, string>,
    includeInternal: boolean = false): void {
    const keys = Object.keys(source);
    for (const key of keys) {
      if (!includeInternal && key.startsWith('__') &&
        key !== '__refreshExplore' && key !== '__searchBook' && key !== '__toast' && key !== '__openBrowser') continue;
      target[key] = source[key] ?? '';
    }
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '未知错误';
    return String(error || '未知错误');
  }
}
