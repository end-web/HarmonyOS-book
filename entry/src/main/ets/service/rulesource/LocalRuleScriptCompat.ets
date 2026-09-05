/** This code runs only inside the bounded QuickJS context, never in ArkWeb or the ArkTS VM. */
export class LocalRuleScriptCompat {
  static code(): string {
    return `
const action=function(operation,args){
  const spec='local-rule-action:'+JSON.stringify(Object.assign({operation:operation},args));
  const response=request(spec);if(!response)return null;
  const parsed=JSON.parse(response);if(parsed.error)throw new Error(parsed.error);return parsed.value;
};
java.t2s=function(value){return String(action('chinese',{direction:'Traditional-Simplified',text:String(value??'')})||'');};
java.s2t=function(value){return String(action('chinese',{direction:'Simplified-Traditional',text:String(value??'')})||'');};
const chineseNumber=function(text){
  const digits={'零':0,'〇':0,'一':1,'壹':1,'二':2,'两':2,'兩':2,'贰':2,'貳':2,'三':3,'叁':3,'參':3,'四':4,'肆':4,'五':5,'伍':5,'六':6,'陆':6,'陸':6,'七':7,'柒':7,'八':8,'捌':8,'九':9,'玖':9};
  const units={'十':10,'拾':10,'百':100,'佰':100,'千':1000,'仟':1000,'万':10000,'萬':10000,'亿':100000000,'億':100000000};
  if(!Array.from(text).some(function(c){return units[c];}))return String(Number(Array.from(text).map(function(c){return digits[c]??c;}).join('')));
  let total=0,section=0,current=0;
  for(const c of text){if(digits[c]!==undefined){current=digits[c];continue;}if(/[0-9]/.test(c)){current=current*10+Number(c);continue;}
    const unit=units[c];if(unit<10000){section+=(current||1)*unit;current=0;}
    else if(unit===10000){total+=(section+current)*unit;section=0;current=0;}
    else {total=(total+section+current)*unit;section=0;current=0;}}
  return String(total+section+current);
};
java.toNumChapter=function(value){return String(value??'').replace(/(第\\s*)([零〇一二两兩三四五六七八九十百千万萬亿億壹贰貳叁參肆伍陆陸柒捌玖拾佰仟0-9]+)(\\s*[章回节節卷集部篇])/g,
  function(_all,prefix,number,suffix){return prefix+chineseNumber(number)+suffix;});};
const bytesHex=function(value){return Array.from(value||[]).map(function(x){return (Number(x)&255).toString(16).padStart(2,'0');}).join('');};
const fromHex=function(value){const text=String(value||'');if(text.length%2||!/^[0-9a-f]*$/i.test(text))throw new Error('Invalid hex');
  const bytes=[];for(let i=0;i<text.length;i+=2)bytes.push(parseInt(text.slice(i,i+2),16));return bytes;};
const toBytes=function(value,charset){
  if(Array.isArray(value)||ArrayBuffer.isView(value))return Array.from(value).map(function(x){return Number(x)&255;});
  if(value instanceof ArrayBuffer)return Array.from(new Uint8Array(value));
  if(!charset||/^utf-?8$/i.test(charset))return utf8Bytes(value);
  return fromHex(action('encode',{text:String(value??''),charset:String(charset)})||'');
};
const fromBytes=function(value,charset){const bytes=toBytes(value);
  return !charset||/^utf-?8$/i.test(charset)?utf8String(bytes):String(action('decode',{data:bytesHex(bytes),charset:String(charset)})||'');};
const encodeBase64=function(value,urlSafe){const bytes=toBytes(value);let text='';
  for(let i=0;i<bytes.length;i+=3){const n=(bytes[i]<<16)|((bytes[i+1]||0)<<8)|(bytes[i+2]||0);
    text+=b64chars[(n>>>18)&63]+b64chars[(n>>>12)&63]+(i+1<bytes.length?b64chars[(n>>>6)&63]:'=')+(i+2<bytes.length?b64chars[n&63]:'=');}
  return urlSafe?text.replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,''):text;
};
const decodeBase64=function(value){const text=String(value??'').replace(/-/g,'+').replace(/_/g,'/').replace(/\\s/g,'');
  if(!/^[A-Za-z0-9+/]*={0,2}$/.test(text)||text.length%4===1)throw new Error('Invalid Base64');
  const bytes=[];let bits=0,count=0;for(let i=0;i<text.length&&text[i]!=='=';i++){bits=(bits<<6)|b64chars.indexOf(text[i]);count+=6;
    if(count>=8){count-=8;bytes.push((bits>>>count)&255);}}return bytes;
};
const digestHex=function(algorithm,value){return String(action('digest',{algorithm:String(algorithm),data:bytesHex(toBytes(value))})||'');};
java.base64Encode=function(v,flags){return encodeBase64(v,(Number(flags)&8)!==0);};
java.base64EncodeToString=java.base64Encode;
java.base64Decode=function(v){return decodeBase64(v);};
java.base64DecodeToString=function(v,charset){return fromBytes(decodeBase64(v),charset);};
java.base64UrlEncode=function(v){return encodeBase64(v,true);};
java.base64UrlDecode=java.base64DecodeToString;
java.hexEncodeToString=function(v){return bytesHex(toBytes(v));};
java.hexDecode=function(v){return fromHex(v);};
java.hexDecodeToString=function(v,charset){return fromBytes(fromHex(v),charset);};
java.strToBytes=toBytes;java.bytesToStr=fromBytes;
['sha1','sha256','sha512'].forEach(function(name){java[name]=function(v){return digestHex(name,v);};java[name+'Encode']=java[name];});
java.digestHex=digestHex;
java.hmac=function(algorithm,value,key){return String(action('hmac',{algorithm:String(algorithm).replace(/^Hmac/i,''),data:bytesHex(toBytes(value)),key:bytesHex(toBytes(key))})||'');};
java.hmacSha256=function(value,key){return java.hmac('SHA256',value,key);};
const createSymmetricCrypto=function(algorithm,key,iv){
  const run=function(data,encrypt){return fromHex(action('cipher',{algorithm:String(algorithm||'AES/CBC/PKCS5Padding'),
    key:bytesHex(toBytes(key)),iv:bytesHex(toBytes(iv||[])),data:bytesHex(toBytes(data)),encrypt:encrypt})||'');};
  return {encrypt:function(v){return run(v,true);},decrypt:function(v){return run(v,false);},
    encryptBase64:function(v){return encodeBase64(run(v,true));},decryptBase64:function(v){return run(decodeBase64(v),false);},
    encryptHex:function(v){return bytesHex(run(v,true));},decryptHex:function(v){return run(fromHex(v),false);},
    decryptStr:function(v,charset){return fromBytes(run(typeof v==='string'?decodeBase64(v):v,false),charset);},
    decryptBase64ToString:function(v,charset){return fromBytes(run(decodeBase64(v),false),charset);}};
};
java.createSymmetricCrypto=createSymmetricCrypto;
java.aesDecodeToString=function(data,key,iv,algorithm){return createSymmetricCrypto(algorithm||'AES/CBC/PKCS5Padding',key,iv).decryptBase64ToString(data);};
java.aesEncodeToString=function(data,key,iv,algorithm){return createSymmetricCrypto(algorithm||'AES/CBC/PKCS5Padding',key,iv).encryptBase64(data);};
const formatTime=function(value,pattern,zone){const timestamp=Number(value),d=new Date(Number.isFinite(timestamp)?timestamp:fixedNow);
  const utc=zone!==undefined;if(utc)d.setTime(d.getTime()+Number(zone||0)*3600000);
  const get=function(name){return d[(utc?'getUTC':'get')+name]();};
  const fields={yyyy:String(get('FullYear')).padStart(4,'0'),MM:String(get('Month')+1).padStart(2,'0'),
    dd:String(get('Date')).padStart(2,'0'),HH:String(get('Hours')).padStart(2,'0'),
    mm:String(get('Minutes')).padStart(2,'0'),ss:String(get('Seconds')).padStart(2,'0'),SSS:String(get('Milliseconds')).padStart(3,'0')};
  return String(pattern||'yyyy-MM-dd HH:mm:ss').replace(/'([^']*)'|yyyy|SSS|MM|dd|HH|mm|ss/g,function(token,literal){return literal===undefined?fields[token]:literal;});
};
java.timeFormat=function(value,pattern){return formatTime(value,pattern);};
java.timeFormatUTC=function(value,pattern,zone){return formatTime(value,pattern,zone||0);};
java.urlEncode=function(value,charset){return toBytes(value,charset).map(function(x){const c=String.fromCharCode(x);return /[A-Za-z0-9_.~-]/.test(c)?c:x===32?'+':'%'+x.toString(16).toUpperCase().padStart(2,'0');}).join('');};
java.urlDecode=function(value,charset){const text=String(value??'').replace(/\\+/g,' '),bytes=[];
  for(let i=0;i<text.length;i++){if(text[i]==='%'&&/^[0-9a-f]{2}$/i.test(text.slice(i+1,i+3))){bytes.push(parseInt(text.slice(i+1,i+3),16));i+=2;}else bytes.push(...utf8Bytes(text[i]));}
  return fromBytes(bytes,charset);};
let ruleContent=src;
const extractValues=function(rule,elements,content){
  const payload=content===undefined?ruleContent:String(content),path=String(rule||'');
  if(!elements&&/^\\s*[\\[{]/.test(payload)&&/^\\$?(?:\\.[A-Za-z_$][\\w$-]*|\\[-?\\d+\\]|\\[['"][^'"]+['"]\\])+$/.test(path)){
    const found=readPath(parseValue(payload),path);return Array.isArray(found)?found.map(stringify):found==null?[]:[stringify(found)];}
  return action('extract',{content:payload,rule:path,elements:!!elements})||[];
};
const listMethods=function(list){Object.defineProperties(list,{size:{value:function(){return this.length;}},get:{value:function(i){return this[Number(i)];}},
  isEmpty:{value:function(){return this.length===0;}},toArray:{value:function(){return Array.from(this);}}});return list;};
const elementObject=function(html){return {toString:function(){return html;},outerHtml:function(){return html;},
  text:function(){return extractValues('@text',false,html).join(' ');},html:function(){return extractValues('@html',false,html).join('');},
  attr:function(name){return extractValues('@'+name,false,html)[0]||'';},
  select:function(rule){return listMethods(extractValues(rule,true,html).map(elementObject));}};};
java.setContent=function(value){ruleContent=stringify(value);};
java.getString=function(rule,isUrl){const value=extractValues(rule,false).join('\\n');return isUrl?java.getAbsoluteURL(baseUrl,value):value;};
java.getStringList=function(rule){return listMethods(extractValues(rule,false));};
java.getElements=function(rule){return listMethods(extractValues(rule,true).map(elementObject));};
java.getElement=function(rule){return java.getElements(rule)[0]||null;};
java.getAbsoluteURL=function(base,path){const value=String(path===undefined?base:path),origin=String(path===undefined?baseUrl:base);
  if(/^(https?:|data:)/i.test(value))return value;if(value.startsWith('//'))return (/^https:/i.test(origin)?'https:':'http:')+value;
  const host=/^(https?:\\/\\/[^/?#]+)/i.exec(origin);if(!host)return value;
  if(value.startsWith('?'))return origin.split(/[?#]/)[0]+value;
  const absolute=value.startsWith('/')?host[1]+value:origin.split(/[?#]/)[0].replace(/[^/]*$/,'')+value;
  return absolute.replace(/^(https?:\\/\\/[^/]+)(.*)$/,function(_all,h,p){const parts=[];p.split('/').forEach(function(segment){if(segment==='..')parts.pop();else if(segment!=='.')parts.push(segment);});return h+parts.join('/');});};
const define=function(prototype,name,fn){if(!prototype[name])Object.defineProperty(prototype,name,{value:fn,configurable:true});};
define(String.prototype,'getBytes',function(charset){return toBytes(String(this),charset);});
define(String.prototype,'equals',function(v){return String(this)===String(v);});
define(String.prototype,'equalsIgnoreCase',function(v){return String(this).toLowerCase()===String(v).toLowerCase();});
define(String.prototype,'contains',function(v){return String(this).includes(String(v));});
define(String.prototype,'replaceAll',function(pattern,replacement){return String(this).replace(new RegExp(pattern,'g'),String(replacement));});
define(String.prototype,'matches',function(pattern){return new RegExp('^(?:'+pattern+')$').test(String(this));});
define(Array.prototype,'size',function(){return this.length;});define(Array.prototype,'get',function(i){return this[Number(i)];});
define(Array.prototype,'add',function(v){this.push(v);return true;});define(Array.prototype,'isEmpty',function(){return this.length===0;});
define(Array.prototype,'toArray',function(){return Array.from(this);});
function JavaString(value,charset){return new String(Array.isArray(value)||ArrayBuffer.isView(value)?fromBytes(value,charset):String(value??''));}
JavaString.valueOf=function(v){return String(v);};
function StringBuilder(value){this.value=String(value??'');}
StringBuilder.prototype.append=function(v){this.value+=String(v);return this;};StringBuilder.prototype.toString=function(){return this.value;};
StringBuilder.prototype.length=function(){return this.value.length;};
function HashMap(value){this.values=Object.assign(Object.create(null),value&&value.values||value||{});}
HashMap.prototype.get=function(k){return Object.prototype.hasOwnProperty.call(this.values,String(k))?this.values[String(k)]:null;};
HashMap.prototype.put=function(k,v){const previous=this.get(k);this.values[String(k)]=v;return previous;};
HashMap.prototype.remove=function(k){const v=this.get(k);delete this.values[String(k)];return v;};
HashMap.prototype.containsKey=function(k){return Object.prototype.hasOwnProperty.call(this.values,String(k));};
HashMap.prototype.size=function(){return Object.keys(this.values).length;};HashMap.prototype.isEmpty=function(){return this.size()===0;};
HashMap.prototype.keySet=function(){return Object.keys(this.values);};HashMap.prototype.toJSON=function(){return this.values;};
function ArrayList(values){const result=Array.from(values||[]);result.addAll=function(v){this.push(...v);return true;};return result;}
const androidBase64={DEFAULT:0,NO_PADDING:1,NO_WRAP:2,CRLF:4,URL_SAFE:8,
  encodeToString:function(v,flags){let out=encodeBase64(v,(Number(flags)&8)!==0);return Number(flags)&1?out.replace(/=+$/,''):out;},
  encode:function(v,flags){return toBytes(this.encodeToString(v,flags));},decode:function(v){return decodeBase64(Array.isArray(v)?fromBytes(v):v);}};
const javaBase64={getEncoder:function(){return {encodeToString:encodeBase64,encode:function(v){return toBytes(encodeBase64(v));}};},
  getUrlEncoder:function(){return {encodeToString:function(v){return encodeBase64(v,true);}};},
  getDecoder:function(){return {decode:decodeBase64};},getUrlDecoder:function(){return {decode:decodeBase64};}};
const MessageDigest={getInstance:function(algorithm){let input=[];return {update:function(v){input.push(...toBytes(v));},
  digest:function(v){if(v!==undefined)input.push(...toBytes(v));const result=fromHex(digestHex(algorithm,input));input=[];return result;},reset:function(){input=[];}};}};
function SecretKeySpec(key,algorithm){this.bytes=toBytes(key);this.algorithm=String(algorithm||'AES');this.getEncoded=function(){return this.bytes;};}
function IvParameterSpec(iv){this.bytes=toBytes(iv);this.getIV=function(){return this.bytes;};}
const Cipher={ENCRYPT_MODE:1,DECRYPT_MODE:2,getInstance:function(algorithm){let encrypt=false,key=[],iv=[];
  return {init:function(mode,k,v){encrypt=Number(mode)===1;key=k.bytes||k;iv=v?v.bytes||v:[];},
    doFinal:function(v){const crypto=createSymmetricCrypto(algorithm,key,iv);return encrypt?crypto.encrypt(v):crypto.decrypt(v);}};}};
java.lang={String:JavaString,StringBuilder:StringBuilder,System:{currentTimeMillis:function(){return fixedNow;}},
  Integer:{parseInt:function(v,radix){return parseInt(v,radix||10);},toHexString:function(v){return (Number(v)>>>0).toString(16);}},
  Long:{parseLong:function(v,radix){return parseInt(v,radix||10);}},Boolean:{parseBoolean:function(v){return String(v).toLowerCase()==='true';}}};
java.util={HashMap:HashMap,LinkedHashMap:HashMap,ArrayList:ArrayList,Base64:javaBase64,UUID:{randomUUID:java.randomUUID}};
java.net={URLEncoder:{encode:java.urlEncode},URLDecoder:{decode:java.urlDecode}};java.security={MessageDigest:MessageDigest};
const android={util:{Base64:androidBase64}},javax={crypto:{Cipher:Cipher,spec:{SecretKeySpec:SecretKeySpec,IvParameterSpec:IvParameterSpec}}};
const Packages={java:java,javax:javax,android:android};
const Java={type:function(name){const parts=String(name).split('.');let item=Packages;for(const part of parts)item=item&&item[part];
  if(item===undefined)throw new Error('Unsupported Java class: '+name);return item;},to:function(value){return Array.from(value);},from:function(value){return Array.from(value);}};
Object.assign(globalThis,{android:android,javax:javax,Packages:Packages,Java:Java,createSymmetricCrypto:createSymmetricCrypto,
  Base64:androidBase64,URLEncoder:java.net.URLEncoder,URLDecoder:java.net.URLDecoder,System:java.lang.System,
  StringBuilder:StringBuilder,HashMap:HashMap,ArrayList:ArrayList,MessageDigest:MessageDigest,Cipher:Cipher,SecretKeySpec:SecretKeySpec,IvParameterSpec:IvParameterSpec});
globalThis.importClass=function(type){if(typeof type==='function'&&type.name)globalThis[type.name]=type;};
globalThis.importPackage=function(pkg){if(!Object.values(Packages).includes(pkg)&&pkg!==java.util&&pkg!==java.lang)throw new Error('Unsupported Java package');Object.assign(globalThis,pkg);};
java.androidId=function(){let id=source.get('__androidId');if(!id){id=java.randomUUID().replace(/-/g,'').slice(0,16);source.put('__androidId',id);}return id;};
java.startBrowser=function(url){const target=String(url||'');if(!/^https:\\/\\//i.test(target))throw new Error('Login requires HTTPS');
  V.__openBrowser=target;return '';};
java.startBrowserAwait=java.startBrowser;
source.removeLoginInfo=function(){S.loginInfo='';};source.removeLoginHeader=function(){S.loginHeader='';};
source.getLoginHeaderMap=function(){return parseValue(S.loginHeader||'{}');};
java.webView=function(html,url,script){const target=String(url||baseUrl),options={webView:true,webJs:String(script||'')};
  if(html!==null&&html!==undefined&&String(html))options.webHtml=String(html);return request(target+','+JSON.stringify(options));};
if(V.__browserSnapshot==='true'){
  const domNode=function(html){const element=elementObject(html),node={};
    const read=function(rule){return extractValues(rule,false,html).join('');};
    Object.defineProperties(node,{
      outerHTML:{get:function(){return html;}},innerHTML:{get:function(){return read('@html');}},
      innerText:{get:function(){return read('@text');}},textContent:{get:function(){return read('@text');}},
      src:{get:function(){return java.getAbsoluteURL(baseUrl,read('@src'));}},href:{get:function(){return java.getAbsoluteURL(baseUrl,read('@href'));}},
      value:{get:function(){return read('@value');}},id:{get:function(){return read('@id');}},className:{get:function(){return read('@class');}}
    });
    node.getAttribute=function(name){return read('@'+name);};
    node.querySelectorAll=function(selector){return extractValues(selector,true,html).map(domNode);};
    node.querySelector=function(selector){return node.querySelectorAll(selector)[0]||null;};
    return node;
  };
  const document={querySelectorAll:function(selector){return extractValues(selector,true,src).map(domNode);},
    querySelector:function(selector){return this.querySelectorAll(selector)[0]||null;},
    getElementById:function(id){return this.querySelector('[id='+JSON.stringify(String(id))+']');},
    getElementsByTagName:function(name){return this.querySelectorAll(name);},readyState:'complete',URL:baseUrl};
  Object.defineProperties(document,{documentElement:{get:function(){return domNode(src);}},
    body:{get:function(){return document.querySelector('body');}},title:{get:function(){return extractValues('title@text',false,src).join('');}}});
  const window=Object.assign({},parseValue(V.__browserState||'{}'));
  window.document=document;window.window=window;window.location={href:baseUrl,toString:function(){return baseUrl;}};
  Object.keys(window).forEach(function(k){if(!(k in globalThis))globalThis[k]=window[k];});
  globalThis.window=window;globalThis.document=document;globalThis.location=window.location;
}
`;
  }
}
