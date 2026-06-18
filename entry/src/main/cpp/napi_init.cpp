// jsvmengine - 用 @ohos.JSVM (C-API) 跑任意复杂 legado @js: 书源的通用引擎。
//  - evalJs(code, contextJson): Promise<string>  异步(napi_async_work)，在工作线程跑 JSVM，不阻塞 UI
//  - native __httpRequest(url, method, headersFlat) -> "status\nbody"  用 net_http + 条件变量做同步阻塞
//  - native __log(msg)
//  - JS preamble: 纯 JS md5/base64/hex/timeFormatUTC + java.ajax/ajaxAll(StrResponse) + source.getVariable/setVariable + 注入 context
//  (AES: 阶段3)
#include "napi/native_api.h"
#include "ark_runtime/jsvm.h"
#include "network/netstack/net_http.h"
#include <hilog/log.h>
#include <string>
#include <vector>
#include <mutex>
#include <condition_variable>
#include <cstring>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x9530
#define LOG_TAG "JsvmEngine"

static bool g_jsvmInited = false;

// ───────────── net_http 同步桥（全局串行，一次一个在途请求）─────────────
namespace {
std::mutex g_serial;       // 串行化所有请求（回调无 userdata，用全局槽位）
std::mutex g_mu;
std::condition_variable g_cv;
bool g_done = false;
int g_status = 0;
std::string g_body;

void OnHttpResponse(struct Http_Response *response, uint32_t errCode) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (errCode == 0 && response != nullptr) {
        g_status = static_cast<int>(response->responseCode);
        if (response->body.buffer != nullptr && response->body.length > 0) {
            g_body.assign(response->body.buffer, response->body.length);
        } else {
            g_body.clear();
        }
    } else {
        g_status = -static_cast<int>(errCode);
        g_body.clear();
    }
    g_done = true;
    g_cv.notify_one();
}

// 同步发请求；headers 为 [name,value,...] 扁平表
Http_RequestOptions g_opts; // 串行下复用

void DoHttpSync(const std::string &url, const std::string &method,
                const std::vector<std::string> &headers, int &outStatus, std::string &outBody) {
    std::lock_guard<std::mutex> serial(g_serial);
    Http_Request *req = OH_Http_CreateRequest(url.c_str());
    if (req == nullptr) { outStatus = -1; outBody = "createReq-null"; return; }

    Http_Headers *hd = OH_Http_CreateHeaders();
    for (size_t i = 0; i + 1 < headers.size(); i += 2) {
        OH_Http_SetHeaderValue(hd, headers[i].c_str(), headers[i + 1].c_str());
    }
    // req->options 可能由 CreateRequest 分配；若为空则用本地静态结构兜底
    if (req->options == nullptr) {
        memset(&g_opts, 0, sizeof(g_opts));
        req->options = &g_opts;
    }
    req->options->method = method.c_str();
    req->options->readTimeout = 30000;
    req->options->connectTimeout = 30000;
    req->options->headers = hd;

    { std::lock_guard<std::mutex> lk(g_mu); g_done = false; g_status = 0; g_body.clear(); }
    Http_EventsHandler handler;
    memset(&handler, 0, sizeof(handler));
    int ret = OH_Http_Request(req, OnHttpResponse, handler);
    if (ret != 0) {
        outStatus = -1000 - ret; outBody = "reqFail";
        if (req->options == &g_opts) req->options = nullptr;
        OH_Http_DestroyHeaders(&hd); OH_Http_Destroy(&req);
        return;
    }
    { std::unique_lock<std::mutex> lk(g_mu); g_cv.wait(lk, [] { return g_done; }); outStatus = g_status; outBody = g_body; }
    if (req->options == &g_opts) req->options = nullptr; // 避免 Destroy 释放本地结构
    OH_Http_DestroyHeaders(&hd);
    OH_Http_Destroy(&req);
}
} // namespace

// ───────────── JSVM helpers ─────────────
static std::string JsvmStr(JSVM_Env env, JSVM_Value v) {
    JSVM_ValueType t;
    if (OH_JSVM_Typeof(env, v, &t) != JSVM_OK) return "";
    if (t == JSVM_STRING) {
        size_t size = 0;
        OH_JSVM_GetValueStringUtf8(env, v, nullptr, 0, &size);
        std::string out(size + 1, '\0');
        OH_JSVM_GetValueStringUtf8(env, v, &out[0], size + 1, &size);
        out.resize(size);
        return out;
    }
    if (t == JSVM_NUMBER) { double d = 0; OH_JSVM_GetValueDouble(env, v, &d);
        if (d == static_cast<long long>(d)) return std::to_string(static_cast<long long>(d)); return std::to_string(d); }
    if (t == JSVM_BOOLEAN) { bool b = false; OH_JSVM_GetValueBool(env, v, &b); return b ? "true" : "false"; }
    if (t == JSVM_OBJECT) { JSVM_Value j = nullptr; if (OH_JSVM_JsonStringify(env, v, &j) == JSVM_OK && j) return JsvmStr(env, j); return "[object]"; }
    return "";
}

// native: __httpRequest(url, method, headersFlat) -> "status\nbody"
static JSVM_Value NativeHttpRequest(JSVM_Env env, JSVM_CallbackInfo info) {
    size_t argc = 3;
    JSVM_Value argv[3] = {nullptr, nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, argv, nullptr, nullptr);
    std::string url = argc > 0 ? JsvmStr(env, argv[0]) : "";
    std::string method = argc > 1 ? JsvmStr(env, argv[1]) : "GET";
    std::string flat = argc > 2 ? JsvmStr(env, argv[2]) : "";
    if (method.empty()) method = "GET";

    std::vector<std::string> headers;
    size_t pos = 0;
    while (pos < flat.size()) {
        size_t nl = flat.find('\n', pos);
        if (nl == std::string::npos) { headers.push_back(flat.substr(pos)); break; }
        headers.push_back(flat.substr(pos, nl - pos));
        pos = nl + 1;
    }
    int status = 0; std::string body;
    DoHttpSync(url, method, headers, status, body);

    std::string out = std::to_string(status) + "\n" + body;
    JSVM_Value res = nullptr;
    OH_JSVM_CreateStringUtf8(env, out.c_str(), out.size(), &res);
    return res;
}

static JSVM_Value NativeLog(JSVM_Env env, JSVM_CallbackInfo info) {
    size_t argc = 1; JSVM_Value argv[1] = {nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, argv, nullptr, nullptr);
    std::string msg = argc > 0 ? JsvmStr(env, argv[0]) : "";
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "[js] %{public}.300s", msg.c_str());
    return nullptr;
}

static JSVM_CallbackStruct g_cbHttp = {NativeHttpRequest, nullptr};
static JSVM_CallbackStruct g_cbLog = {NativeLog, nullptr};

// ───────────── JS preamble（每次 eval 前注入；__CTX__/__VAR__ 由外层脚本预置）─────────────
static const char *PREAMBLE = R"JS(
(function(g){
  'use strict';
  // ---- hex ----
  function bytesToHex(b){var s='';for(var i=0;i<b.length;i++){var h=(b[i]&0xff).toString(16);s+=h.length<2?'0'+h:h;}return s;}
  function utf8Bytes(str){var b=[];for(var i=0;i<str.length;i++){var c=str.charCodeAt(i);
    if(c<0x80)b.push(c);else if(c<0x800){b.push(0xc0|(c>>6),0x80|(c&0x3f));}
    else if(c<0xd800||c>=0xe000){b.push(0xe0|(c>>12),0x80|((c>>6)&0x3f),0x80|(c&0x3f));}
    else{i++;var cp=0x10000+(((c&0x3ff)<<10)|(str.charCodeAt(i)&0x3ff));b.push(0xf0|(cp>>18),0x80|((cp>>12)&0x3f),0x80|((cp>>6)&0x3f),0x80|(cp&0x3f));}}
    return b;}
  function bytesToUtf8(b){var s='',i=0;while(i<b.length){var c=b[i++];
    if(c<0x80)s+=String.fromCharCode(c);
    else if(c<0xe0)s+=String.fromCharCode(((c&0x1f)<<6)|(b[i++]&0x3f));
    else if(c<0xf0)s+=String.fromCharCode(((c&0xf)<<12)|((b[i++]&0x3f)<<6)|(b[i++]&0x3f));
    else{var cp=((c&0x7)<<18)|((b[i++]&0x3f)<<12)|((b[i++]&0x3f)<<6)|(b[i++]&0x3f);s+=String.fromCodePoint(cp);}}
    return s;}
  // ---- base64 ----
  var B64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function b64encBytes(b){var o='';for(var i=0;i<b.length;i+=3){var b1=b[i],b2=i+1<b.length?b[i+1]:-1,b3=i+2<b.length?b[i+2]:-1;
    o+=B64[(b1>>2)&0x3f];o+=B64[((b1&3)<<4)|(((b2<0?0:b2)>>4)&0xf)];o+=b2<0?'=':B64[((b2&0xf)<<2)|(((b3<0?0:b3)>>6)&3)];o+=b3<0?'=':B64[b3&0x3f];}return o;}
  function b64decBytes(s){s=String(s).replace(/[^A-Za-z0-9+/=]/g,'');var b=[];for(var i=0;i<s.length;i+=4){
    var c1=B64.indexOf(s[i]),c2=B64.indexOf(s[i+1]),c3=B64.indexOf(s[i+2]),c4=B64.indexOf(s[i+3]);
    b.push((c1<<2)|(c2>>4));if(s[i+2]!=='=')b.push(((c2&0xf)<<4)|(c3>>2));if(s[i+3]!=='=')b.push(((c3&3)<<6)|c4);}return b;}
  // ---- AES (decrypt, CBC/ECB, PKCS7; key/iv 为 UTF-8 字节) ----
  var SBOX_HEX="637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16";
  var SBOX=[],INVSBOX=[];for(var _i=0;_i<256;_i++){SBOX[_i]=parseInt(SBOX_HEX.substr(_i*2,2),16);}for(var _i=0;_i<256;_i++){INVSBOX[SBOX[_i]]=_i;}
  function gmul(a,b){var p=0;for(var i=0;i<8;i++){if(b&1)p^=a;var hi=a&0x80;a=(a<<1)&0xff;if(hi)a^=0x1b;b>>=1;}return p&0xff;}
  function keyExpansion(key){var Nk=key.length/4|0;var Nr=Nk+6;var w=[];for(var i=0;i<Nk;i++)w[i]=[key[4*i],key[4*i+1],key[4*i+2],key[4*i+3]];
    var Rcon=[0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d];
    for(var i=Nk;i<4*(Nr+1);i++){var t=w[i-1].slice();
      if(i%Nk===0){t=[SBOX[t[1]],SBOX[t[2]],SBOX[t[3]],SBOX[t[0]]];t[0]^=Rcon[(i/Nk|0)-1];}
      else if(Nk>6&&i%Nk===4){t=[SBOX[t[0]],SBOX[t[1]],SBOX[t[2]],SBOX[t[3]]];}
      w[i]=[w[i-Nk][0]^t[0],w[i-Nk][1]^t[1],w[i-Nk][2]^t[2],w[i-Nk][3]^t[3]];}
    return {w:w,Nr:Nr};}
  function ark(s,w,r){for(var c=0;c<4;c++)for(var ro=0;ro<4;ro++)s[ro][c]^=w[r*4+c][ro];}
  function invShift(s){for(var r=1;r<4;r++){var row=[s[r][0],s[r][1],s[r][2],s[r][3]];for(var c=0;c<4;c++)s[r][c]=row[(c-r+4)%4];}}
  function invSub(s){for(var r=0;r<4;r++)for(var c=0;c<4;c++)s[r][c]=INVSBOX[s[r][c]];}
  function invMix(s){for(var c=0;c<4;c++){var a0=s[0][c],a1=s[1][c],a2=s[2][c],a3=s[3][c];
    s[0][c]=gmul(a0,14)^gmul(a1,11)^gmul(a2,13)^gmul(a3,9);
    s[1][c]=gmul(a0,9)^gmul(a1,14)^gmul(a2,11)^gmul(a3,13);
    s[2][c]=gmul(a0,13)^gmul(a1,9)^gmul(a2,14)^gmul(a3,11);
    s[3][c]=gmul(a0,11)^gmul(a1,13)^gmul(a2,9)^gmul(a3,14);}}
  function decBlock(block,ks){var s=[[],[],[],[]];for(var i=0;i<16;i++)s[i%4][i/4|0]=block[i];
    ark(s,ks.w,ks.Nr);for(var r=ks.Nr-1;r>0;r--){invShift(s);invSub(s);ark(s,ks.w,r);invMix(s);}
    invShift(s);invSub(s);ark(s,ks.w,0);var out=[];for(var i=0;i<16;i++)out[i]=s[i%4][i/4|0];return out;}
  function aesDec(key,iv,ct,cbc){var ks=keyExpansion(key);var out=[];var prev=cbc?iv.slice():null;
    for(var i=0;i+16<=ct.length;i+=16){var block=ct.slice(i,i+16);var d=decBlock(block,ks);
      if(cbc){for(var j=0;j<16;j++)out.push(d[j]^prev[j]);prev=block;}else{for(var j=0;j<16;j++)out.push(d[j]);}}
    var pad=out[out.length-1];if(pad>0&&pad<=16){var okp=true;for(var k=0;k<pad;k++)if(out[out.length-1-k]!==pad)okp=false;if(okp)out=out.slice(0,out.length-pad);}
    return out;}
  function createSymmetricCrypto(transformation,key,iv){var cbc=/CBC/i.test(String(transformation));
    var kb=utf8Bytes(String(key));var ivb=iv!=null?utf8Bytes(String(iv)):[];
    return {decryptStr:function(s){return bytesToUtf8(aesDec(kb,ivb,b64decBytes(s),cbc));},
      decrypt:function(s){return aesDec(kb,ivb,b64decBytes(s),cbc);}};}

  // ---- md5 (compact) ----
  function md5hex(str){
    function rl(n,c){return (n<<c)|(n>>>(32-c));}
    function ad(a,b){var l=(a&0xffff)+(b&0xffff);return (((a>>16)+(b>>16)+(l>>16))<<16)|(l&0xffff);}
    function cm(q,a,b,x,s,t){return ad(rl(ad(ad(a,q),ad(x,t)),s),b);}
    function ff(a,b,c,d,x,s,t){return cm((b&c)|((~b)&d),a,b,x,s,t);}
    function gg(a,b,c,d,x,s,t){return cm((b&d)|(c&(~d)),a,b,x,s,t);}
    function hh(a,b,c,d,x,s,t){return cm(b^c^d,a,b,x,s,t);}
    function ii(a,b,c,d,x,s,t){return cm(c^(b|(~d)),a,b,x,s,t);}
    var bytes=utf8Bytes(str);var n=bytes.length;var words=[];for(var i=0;i<n;i++)words[i>>2]=(words[i>>2]||0)|(bytes[i]<<((i%4)*8));
    words[n>>2]=(words[n>>2]||0)|(0x80<<((n%4)*8));var bl=n*8;var li=(((n+8)>>6)+1)*16-2;words[li]=bl;
    var a=1732584193,b=-271733879,c=-1732584194,d=271733878;
    for(var i=0;i<li+2;i+=16){var oa=a,ob=b,oc=c,od=d;var w=function(j){return words[i+j]||0;};
      a=ff(a,b,c,d,w(0),7,-680876936);d=ff(d,a,b,c,w(1),12,-389564586);c=ff(c,d,a,b,w(2),17,606105819);b=ff(b,c,d,a,w(3),22,-1044525330);
      a=ff(a,b,c,d,w(4),7,-176418897);d=ff(d,a,b,c,w(5),12,1200080426);c=ff(c,d,a,b,w(6),17,-1473231341);b=ff(b,c,d,a,w(7),22,-45705983);
      a=ff(a,b,c,d,w(8),7,1770035416);d=ff(d,a,b,c,w(9),12,-1958414417);c=ff(c,d,a,b,w(10),17,-42063);b=ff(b,c,d,a,w(11),22,-1990404162);
      a=ff(a,b,c,d,w(12),7,1804603682);d=ff(d,a,b,c,w(13),12,-40341101);c=ff(c,d,a,b,w(14),17,-1502002290);b=ff(b,c,d,a,w(15),22,1236535329);
      a=gg(a,b,c,d,w(1),5,-165796510);d=gg(d,a,b,c,w(6),9,-1069501632);c=gg(c,d,a,b,w(11),14,643717713);b=gg(b,c,d,a,w(0),20,-373897302);
      a=gg(a,b,c,d,w(5),5,-701558691);d=gg(d,a,b,c,w(10),9,38016083);c=gg(c,d,a,b,w(15),14,-660478335);b=gg(b,c,d,a,w(4),20,-405537848);
      a=gg(a,b,c,d,w(9),5,568446438);d=gg(d,a,b,c,w(14),9,-1019803690);c=gg(c,d,a,b,w(3),14,-187363961);b=gg(b,c,d,a,w(8),20,1163531501);
      a=gg(a,b,c,d,w(13),5,-1444681467);d=gg(d,a,b,c,w(2),9,-51403784);c=gg(c,d,a,b,w(7),14,1735328473);b=gg(b,c,d,a,w(12),20,-1926607734);
      a=hh(a,b,c,d,w(5),4,-378558);d=hh(d,a,b,c,w(8),11,-2022574463);c=hh(c,d,a,b,w(11),16,1839030562);b=hh(b,c,d,a,w(14),23,-35309556);
      a=hh(a,b,c,d,w(1),4,-1530992060);d=hh(d,a,b,c,w(4),11,1272893353);c=hh(c,d,a,b,w(7),16,-155497632);b=hh(b,c,d,a,w(10),23,-1094730640);
      a=hh(a,b,c,d,w(13),4,681279174);d=hh(d,a,b,c,w(0),11,-358537222);c=hh(c,d,a,b,w(3),16,-722521979);b=hh(b,c,d,a,w(6),23,76029189);
      a=hh(a,b,c,d,w(9),4,-640364487);d=hh(d,a,b,c,w(12),11,-421815835);c=hh(c,d,a,b,w(15),16,530742520);b=hh(b,c,d,a,w(2),23,-995338651);
      a=ii(a,b,c,d,w(0),6,-198630844);d=ii(d,a,b,c,w(7),10,1126891415);c=ii(c,d,a,b,w(14),15,-1416354905);b=ii(b,c,d,a,w(5),21,-57434055);
      a=ii(a,b,c,d,w(12),6,1700485571);d=ii(d,a,b,c,w(3),10,-1894986606);c=ii(c,d,a,b,w(10),15,-1051523);b=ii(b,c,d,a,w(1),21,-2054922799);
      a=ii(a,b,c,d,w(8),6,1873313359);d=ii(d,a,b,c,w(15),10,-30611744);c=ii(c,d,a,b,w(6),15,-1560198380);b=ii(b,c,d,a,w(13),21,1309151649);
      a=ii(a,b,c,d,w(4),6,-145523070);d=ii(d,a,b,c,w(11),10,-1120210379);c=ii(c,d,a,b,w(2),15,718787259);b=ii(b,c,d,a,w(9),21,-343485551);
      a=ad(a,oa);b=ad(b,ob);c=ad(c,oc);d=ad(d,od);}
    function le(n){var s='';for(var j=0;j<4;j++){var h=((n>>(j*8))&0xff).toString(16);s+=h.length<2?'0'+h:h;}return s;}
    return le(a)+le(b)+le(c)+le(d);
  }
  // ---- timeFormat ----
  function pad(n){return n<10?'0'+n:''+n;}
  function fmtUTC(date,pattern,off){var d=(date instanceof Date)?date:new Date(Number(date));var t=new Date(d.getTime()+(off==null?0:Number(off))*3600000);
    return String(pattern||'yyyy-MM-dd HH:mm:ss').replace(/yyyy/g,t.getUTCFullYear()).replace(/MM/g,pad(t.getUTCMonth()+1)).replace(/dd/g,pad(t.getUTCDate())).replace(/HH/g,pad(t.getUTCHours())).replace(/mm/g,pad(t.getUTCMinutes())).replace(/ss/g,pad(t.getUTCSeconds()));}
  function encUrl(u){return String(u).replace(/[^\x00-\x7F]+/g,function(m){return encodeURIComponent(m);});}

  // ---- HTTP: 解析 "url,{opt}"，调 native __httpRequest ----
  function splitOpt(raw){var s=String(raw);var i=s.search(/,\s*\{/);if(i<0)return{url:s,method:'GET',headers:null,body:null};
    var opt={};try{opt=JSON.parse(s.slice(i+1));}catch(e){}return{url:s.slice(0,i),method:opt.method||'GET',headers:opt.headers||null,body:opt.body||null};}
  function doReq(raw){var p=splitOpt(raw);var flat='';if(p.headers){for(var k in p.headers){flat+=k+'\n'+String(p.headers[k])+'\n';}}
    var rawres=__httpRequest(encUrl(p.url),p.method,flat);var nl=rawres.indexOf('\n');var st=parseInt(rawres.slice(0,nl),10);var bd=rawres.slice(nl+1);return{status:st,body:bd};}
  function StrResponse(r){return{code:function(){return r.status;},body:function(){return r.body;},header:function(){return '';},headers:function(){return '';},url:function(){return '';},toString:function(){return r.body;}};}

  var java={
    md5Encode:function(s){return md5hex(String(s));},
    md5Encode16:function(s){return md5hex(String(s)).slice(8,24);},
    base64Encode:function(s){return b64encBytes(utf8Bytes(String(s)));},
    base64Decode:function(s){return bytesToUtf8(b64decBytes(s));},
    hexDecodeToString:function(h){h=String(h);if(h.length%2===0&&/^[0-9a-fA-F]+$/.test(h)){var b=[];for(var i=0;i<h.length;i+=2)b.push(parseInt(h.substr(i,2),16));return bytesToUtf8(b);}return bytesToUtf8(b64decBytes(h));},
    timeFormat:function(ts){return fmtUTC(new Date(Number(ts)),'yyyy-MM-dd HH:mm:ss',8);},
    timeFormatUTC:function(date,pattern,off){return fmtUTC(date,pattern,off);},
    createSymmetricCrypto:function(t,k,iv){return createSymmetricCrypto(t,k,iv);},
    encodeURI:function(s){return encodeURIComponent(String(s));},
    toast:function(){},longToast:function(){},
    log:function(m){__log(String(m));return m;},
    ajax:function(u){return doReq(Array.isArray(u)?u[0]:u).body;},
    get:function(u){return doReq(u).body;},
    connect:function(u){return StrResponse(doReq(u));},
    ajaxAll:function(list){var a=Array.isArray(list)?list:[list];var out=[];for(var i=0;i<a.length;i++)out.push(StrResponse(doReq(a[i])));return out;}
  };
  g.java=java;
  g.cookie={getCookie:function(){return '';},setCookie:function(){}};
  g.cache={get:function(){return '';},put:function(){},set:function(){}};
  var ctx=g.__CTX__||{};
  g.result=ctx.result!==undefined?ctx.result:'';
  g.src=g.result;
  g.baseUrl=ctx.baseUrl||'';
  g.key=ctx.key||'';
  g.page=ctx.page||1;
  g.book=ctx.book||null;
  g.chapter=ctx.chapter||null;
  g.source={
    bookSourceComment:ctx.bookSourceComment||'',
    bookSourceUrl:ctx.bookSourceUrl||'',
    bookSourceName:ctx.bookSourceName||'',
    getVariable:function(){return ctx.sourceVar||'';},
    setVariable:function(v){g.__VAR__=(v==null?'':String(v));return v;},
    getKey:function(){return ctx.bookSourceName||'';},
    put:function(k,v){g.__KV__=g.__KV__||{};g.__KV__[k]=v;},
    get:function(k){return (g.__KV__||{})[k];}
  };
})(globalThis);
)JS";

// 运行 preamble + 源码，返回 JSON {"result":..,"sourceVar":..}
static std::string JsonEsc(const std::string &s) {
    std::string o; o.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"': o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) { char buf[8]; snprintf(buf, sizeof(buf), "\\u%04x", c); o += buf; }
                else o += c;
        }
    }
    return o;
}

static bool RunScriptInEnv(JSVM_Env env, const std::string &src, JSVM_Value *out, std::string *err) {
    JSVM_Value jsSrc = nullptr;
    OH_JSVM_CreateStringUtf8(env, src.c_str(), src.size(), &jsSrc);
    JSVM_Script script = nullptr;
    if (OH_JSVM_CompileScript(env, jsSrc, nullptr, 0, true, nullptr, &script) != JSVM_OK) { if (err) *err = "compile"; return false; }
    JSVM_Status st = OH_JSVM_RunScript(env, script, out);
    if (st != JSVM_OK) {
        JSVM_Value exc = nullptr;
        if (OH_JSVM_GetAndClearLastException(env, &exc) == JSVM_OK && exc) { if (err) *err = JsvmStr(env, exc); }
        else if (err) *err = "run:" + std::to_string(st);
        return false;
    }
    return true;
}

static std::string RunSource(const std::string &code, const std::string &ctxJson) {
    if (!g_jsvmInited) { JSVM_InitOptions io; memset(&io, 0, sizeof(io)); OH_JSVM_Init(&io); g_jsvmInited = true; }

    JSVM_VM vm = nullptr; JSVM_CreateVMOptions vo; memset(&vo, 0, sizeof(vo));
    if (OH_JSVM_CreateVM(&vo, &vm) != JSVM_OK) return "{\"result\":\"\",\"sourceVar\":\"\",\"error\":\"CreateVM\"}";
    JSVM_VMScope vmScope = nullptr; OH_JSVM_OpenVMScope(vm, &vmScope);
    JSVM_PropertyDescriptor desc[] = {
        {"__httpRequest", nullptr, &g_cbHttp, nullptr, nullptr, nullptr, JSVM_DEFAULT},
        {"__log", nullptr, &g_cbLog, nullptr, nullptr, nullptr, JSVM_DEFAULT},
    };
    JSVM_Env env = nullptr; OH_JSVM_CreateEnv(vm, sizeof(desc) / sizeof(desc[0]), desc, &env);
    JSVM_EnvScope envScope = nullptr; OH_JSVM_OpenEnvScope(env, &envScope);
    JSVM_HandleScope handleScope = nullptr; OH_JSVM_OpenHandleScope(env, &handleScope);

    std::string error;
    std::string setup = "var __CTX__=" + (ctxJson.empty() ? std::string("{}") : ctxJson) + "; var __VAR__='';\n";
    JSVM_Value tmp = nullptr;
    bool ok = RunScriptInEnv(env, setup, &tmp, &error);
    if (ok) ok = RunScriptInEnv(env, std::string(PREAMBLE), &tmp, &error);
    std::string resultStr, sourceVar;
    if (ok) {
        JSVM_Value rv = nullptr;
        if (RunScriptInEnv(env, code, &rv, &error)) resultStr = JsvmStr(env, rv);
        // 读 globalThis.__VAR__
        JSVM_Value global = nullptr, varv = nullptr;
        if (OH_JSVM_GetGlobal(env, &global) == JSVM_OK) {
            JSVM_Value key = nullptr; OH_JSVM_CreateStringUtf8(env, "__VAR__", JSVM_AUTO_LENGTH, &key);
            if (OH_JSVM_GetProperty(env, global, key, &varv) == JSVM_OK && varv) sourceVar = JsvmStr(env, varv);
        }
    }

    OH_JSVM_CloseHandleScope(env, handleScope);
    OH_JSVM_CloseEnvScope(env, envScope);
    OH_JSVM_DestroyEnv(env);
    OH_JSVM_CloseVMScope(vm, vmScope);
    OH_JSVM_DestroyVM(vm);

    std::string out = "{\"result\":\"" + JsonEsc(resultStr) + "\",\"sourceVar\":\"" + JsonEsc(sourceVar) + "\"";
    if (!error.empty()) out += ",\"error\":\"" + JsonEsc(error) + "\"";
    out += "}";
    if (!error.empty()) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "evalJs error=%{public}s", error.c_str());
    }
    return out;
}

// ───────────── NAPI 异步 evalJs(code, contextJson): Promise<string> ─────────────
struct EvalTask {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string code;
    std::string ctx;
    std::string result;
};

static napi_value EvalJs(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    auto readStr = [&](napi_value v) -> std::string {
        if (v == nullptr) return "";
        size_t len = 0; napi_get_value_string_utf8(env, v, nullptr, 0, &len);
        std::string s(len + 1, '\0'); napi_get_value_string_utf8(env, v, &s[0], len + 1, &len); s.resize(len); return s;
    };
    EvalTask *t = new EvalTask();
    t->code = argc > 0 ? readStr(argv[0]) : "";
    t->ctx = argc > 1 ? readStr(argv[1]) : "";

    napi_value promise = nullptr;
    napi_create_promise(env, &t->deferred, &promise);
    napi_value resName = nullptr;
    napi_create_string_utf8(env, "evalJs", NAPI_AUTO_LENGTH, &resName);
    napi_create_async_work(
        env, nullptr, resName,
        [](napi_env, void *data) { EvalTask *t = static_cast<EvalTask *>(data); t->result = RunSource(t->code, t->ctx); },
        [](napi_env env, napi_status, void *data) {
            EvalTask *t = static_cast<EvalTask *>(data);
            napi_value r = nullptr; napi_create_string_utf8(env, t->result.c_str(), t->result.size(), &r);
            napi_resolve_deferred(env, t->deferred, r);
            napi_delete_async_work(env, t->work);
            delete t;
        },
        t, &t->work);
    napi_queue_async_work(env, t->work);
    return promise;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"evalJs", nullptr, EvalJs, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "jsvmengine",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterJsvmEngineModule(void) {
    napi_module_register(&g_module);
}
