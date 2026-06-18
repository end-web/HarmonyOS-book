// Legado 书源兼容验证 harness（聚焦"拿到正文"链路）
// 依赖: cheerio, iconv-lite, 系统 curl（同步 HTTP，忠实复刻 legado 的同步 java.ajax 语义）
import * as cheerio from 'cheerio';
import iconv from 'iconv-lite';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const VARSTORE = path.join(process.cwd(), '.sourcevars.json');

// ───────────────────────── 工具 ─────────────────────────
function loadVarStore() { try { return JSON.parse(fs.readFileSync(VARSTORE, 'utf8')); } catch { return {}; } }
function saveVarStore(o) { fs.writeFileSync(VARSTORE, JSON.stringify(o, null, 2)); }

function detectCharset(buf, headers, forced) {
  if (forced) return forced.toLowerCase();
  const ct = (headers?.['content-type'] || '').toLowerCase();
  if (ct.includes('gbk') || ct.includes('gb2312') || ct.includes('gb18030')) return 'gbk';
  const head = buf.slice(0, 2048).toString('latin1').toLowerCase();
  const m = head.match(/charset\s*=\s*["']?\s*([\w-]+)/);
  if (m) { const c = m[1]; if (c.includes('gb')) return 'gbk'; return c; }
  return 'utf-8';
}
function decodeBody(buf, headers, forced) {
  const cs = detectCharset(buf, headers, forced);
  if (cs === 'gbk' || cs === 'gb2312' || cs === 'gb18030') return iconv.decode(buf, 'gbk');
  if (cs === 'utf-8' || cs === 'utf8') return buf.toString('utf8');
  try { return iconv.decode(buf, cs); } catch { return buf.toString('utf8'); }
}

// 同步 HTTP（curl）。返回 {status, buf, text, headersText}
function syncHttp(url, { method = 'GET', headers = {}, body = null, charset = null, returnHex = false } = {}) {
  const SEP = '\n@@@CURLSTATUS@@@';
  const args = ['-sS', '-L', '--compressed', '-m', '40', '-o', '-', '-w', SEP + '%{http_code}', '-X', method];
  for (const [k, v] of Object.entries(headers)) args.push('-H', `${k}: ${v}`);
  if (body != null) {
    let b = body;
    if (charset && /gb/i.test(charset)) b = iconv.encode(body, 'gbk');
    else if (typeof body === 'string') b = Buffer.from(body, 'utf8');
    const hasCT = Object.keys(headers).some(k => k.toLowerCase() === 'content-type');
    if (!hasCT) args.push('-H', 'Content-Type: application/x-www-form-urlencoded');
    args.push('--data-binary', '@-'); // body via stdin
    args.push(url);
    const out = execFileSync('curl', args, { input: b, maxBuffer: 64 * 1024 * 1024 });
    return splitCurl(out, charset, returnHex);
  }
  args.push(url);
  const out = execFileSync('curl', args, { maxBuffer: 64 * 1024 * 1024 });
  return splitCurl(out, charset, returnHex);
}
function splitCurl(out, charset, returnHex) {
  const sepBuf = Buffer.from('\n@@@CURLSTATUS@@@');
  const idx = out.lastIndexOf(sepBuf);
  let bodyBuf, status = 0;
  if (idx >= 0) { bodyBuf = out.slice(0, idx); status = parseInt(out.slice(idx + sepBuf.length).toString('ascii'), 10) || 0; }
  else { bodyBuf = out; }
  const text = returnHex ? bodyBuf.toString('hex') : decodeBody(bodyBuf, {}, charset);
  return { status, buf: bodyBuf, text };
}

// ───────────────────────── URL 解析（legado AnalyzeUrl 子集）─────────────────────────
// 拆 url,{options}
function splitUrlOptions(raw) {
  const i = raw.search(/,\s*\{/);
  if (i < 0) return { url: raw, opt: {} };
  const urlPart = raw.slice(0, i);
  let optStr = raw.slice(i + 1).trim();
  try { return { url: urlPart, opt: JSON.parse(optStr) }; } catch { return { url: raw, opt: {} }; }
}
function absUrl(base, u) {
  if (!u) return u;
  if (/^https?:\/\//i.test(u) || u.startsWith('data:')) return u;
  try { return new URL(u, base).href; } catch { return u; }
}

// 取一个"页面"：返回 {status,text,buf}。处理 data: 协议（type→hex 契约）与普通 http(POST/charset)
function fetchPage(rawUrl, baseUrl, ctx) {
  let raw = rawUrl;
  const { url, opt } = splitUrlOptions(raw);
  if (url.startsWith('data:')) {
    // data:;base64,<payload>,{config}
    const b64idx = url.indexOf('base64,');
    const payload = url.slice(b64idx + 7);
    const decoded = Buffer.from(payload, 'base64');
    // legado: 当 options.type 存在 → 返回 hex 字符串；否则原文
    if (opt && opt.type) return { status: 200, buf: decoded, text: decoded.toString('hex') };
    return { status: 200, buf: decoded, text: decoded.toString('utf8') };
  }
  const full = absUrl(baseUrl, url);
  const headers = Object.assign({}, ctx.defaultHeaders || {});
  if (opt.headers) Object.assign(headers, opt.headers);
  const method = (opt.method || 'GET').toUpperCase();
  const charset = opt.charset || null;
  let body = opt.body != null ? opt.body : null;
  return syncHttp(full, { method, headers, body, charset });
}

// ───────────────────────── java 桥 ─────────────────────────
function makeJava(ctx) {
  const java = {
    log: (...a) => { if (ctx.debug) console.error('[js.log]', ...a); return a[0]; },
    toast: () => {},
    longToast: () => {},
    base64Encode: (s, _f) => Buffer.from(String(s), 'utf8').toString('base64'),
    base64Decode: (s, _f) => Buffer.from(String(s), 'base64').toString('utf8'),
    base64DecodeToByteArray: (s) => Buffer.from(String(s), 'base64'),
    hexDecodeToString: (h) => {
      const s = String(h);
      if (s.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(s)) return Buffer.from(s, 'hex').toString('utf8');
      return Buffer.from(s, 'base64').toString('utf8');
    },
    hexDecodeToByteArray: (h) => Buffer.from(String(h), 'hex'),
    encodeURI: (s, enc) => (enc && /gb/i.test(enc)) ? gbkEncodeURI(String(s)) : encodeURIComponent(String(s)),
    md5Encode: (s) => crypto.createHash('md5').update(String(s), 'utf8').digest('hex'),
    md5Encode16: (s) => crypto.createHash('md5').update(String(s), 'utf8').digest('hex').slice(8, 24),
    digestHex: (s, algo) => crypto.createHash(String(algo || 'md5').toLowerCase().replace('-', '')).update(String(s), 'utf8').digest('hex'),
    randomUUID: () => crypto.randomUUID(),
    androidId: () => 'listenbook-android-id',
    timeFormat: (ts) => fmt(new Date(Number(ts)), 'yyyy-MM-dd HH:mm:ss', 8),
    timeFormatUTC: (date, pattern, off) => fmt(date instanceof Date ? date : new Date(Number(date)), pattern || 'yyyy-MM-dd HH:mm:ss', off == null ? 0 : Number(off)),
    // 同步 HTTP（StrResponse）
    ajax: (urlObj) => strResponse(ajaxOne(urlObj, ctx)),
    ajaxAll: (list) => (Array.isArray(list) ? list : [list]).map(u => strResponse(ajaxOne(u, ctx))),
    get: (urlObj) => strResponse(ajaxOne(urlObj, ctx)).body(),
    post: (url, body, headers) => strResponse(ajaxOne([url + ',' + JSON.stringify({ method: 'POST', body, headers: headers || {} })], ctx)).body(),
    connect: (urlObj) => strResponse(ajaxOne(urlObj, ctx)),
    // AES/DES 对称加密
    createSymmetricCrypto: (transformation, key, iv) => makeSymmetric(transformation, key, iv),
    createSign: () => ({ }),
    getString: (rule, html) => { try { return analyzeOne(html || ctx.lastResult, rule, ctx); } catch { return ''; } },
    getElement: () => null,
    put: (k, v) => { ctx.kv[k] = v; return v; },
    get put_(){return 0},
    getVar: (k) => ctx.kv[k],
    strToBytes: (s) => Buffer.from(String(s), 'utf8'),
    bytesToStr: (b) => Buffer.from(b).toString('utf8'),
  };
  java.get = java.get; // keep
  return java;
}
function gbkEncodeURI(s) {
  const buf = iconv.encode(s, 'gbk'); let out = '';
  for (const b of buf) out += '%' + b.toString(16).toUpperCase().padStart(2, '0');
  return out;
}
function fmt(d, pattern, off) {
  const t = new Date(d.getTime() + off * 3600 * 1000);
  const p = (n, l = 2) => String(n).padStart(l, '0');
  return pattern
    .replace(/yyyy/g, t.getUTCFullYear())
    .replace(/MM/g, p(t.getUTCMonth() + 1))
    .replace(/dd/g, p(t.getUTCDate()))
    .replace(/HH/g, p(t.getUTCHours()))
    .replace(/mm/g, p(t.getUTCMinutes()))
    .replace(/ss/g, p(t.getUTCSeconds()));
}
function strResponse(r) {
  return {
    code: () => r.status,
    body: () => r.text,
    headers: () => r.headersText || '',
    header: () => '',
    url: () => r.url || '',
    raw: () => r,
    toString: () => r.text,
  };
}
function sleepSync(ms) { const sab = new Int32Array(new SharedArrayBuffer(4)); Atomics.wait(sab, 0, 0, ms); }
function encUrl(u) { return String(u).replace(/[^\x00-\x7F]+/g, m => encodeURIComponent(m)); }
// java.ajax 接收的 url 可能是 "url,{opt}" 字符串，或数组里的字符串
function ajaxOne(urlObj, ctx) {
  let raw = Array.isArray(urlObj) ? urlObj[0] : urlObj;
  raw = String(raw);
  const { url, opt } = splitUrlOptions(raw);
  if (url.startsWith('data:')) return fetchPage(raw, ctx.baseUrl, ctx);
  const headers = Object.assign({}, ctx.defaultHeaders || {}, opt.headers || {});
  const full = encUrl(absUrl(ctx.baseUrl, url));
  const r = syncHttp(full, {
    method: (opt.method || 'GET').toUpperCase(),
    headers, body: opt.body != null ? opt.body : null, charset: opt.charset || null,
  });
  r.url = full;
  // 限频(请勿频繁/4011)→ 立即抛错, 让源 run() 跳到下一个(新)域名(限频按域名计)
  if (/请勿频繁|"code"\s*:\s*4011/.test(r.text || '')) { if (ctx.debug) console.error('[rate-limit] skip domain', full.slice(0, 55)); throw new Error('rate-limited-4011'); }
  return r;
}
function makeSymmetric(transformation, key, iv) {
  // transformation 形如 "AES/CBC/PKCS5Padding"
  const t = String(transformation).toUpperCase();
  const algo = t.startsWith('AES') ? 'aes' : t.startsWith('DES') ? 'des' : 'aes';
  const keyBuf = Buffer.isBuffer(key) ? key : Buffer.from(String(key), 'utf8');
  const bits = keyBuf.length * 8;
  const mode = t.includes('CBC') ? 'cbc' : t.includes('ECB') ? 'ecb' : 'cbc';
  const cipherName = algo === 'aes' ? `aes-${bits}-${mode}` : `des-${mode}`;
  const ivBuf = iv == null ? null : (Buffer.isBuffer(iv) ? iv : Buffer.from(String(iv), 'utf8'));
  function decBuf(input) {
    const d = crypto.createDecipheriv(cipherName, keyBuf, mode === 'ecb' ? null : ivBuf);
    return Buffer.concat([d.update(input), d.final()]);
  }
  function encBuf(input) {
    const e = crypto.createCipheriv(cipherName, keyBuf, mode === 'ecb' ? null : ivBuf);
    return Buffer.concat([e.update(input), e.final()]);
  }
  return {
    decryptStr: (s) => { // legado: 入参按 base64 解；失败再按 hex
      let inp; const str = String(s);
      try { inp = Buffer.from(str, 'base64'); decBuf; } catch { inp = Buffer.from(str, 'hex'); }
      try { return decBuf(inp).toString('utf8'); }
      catch { try { return decBuf(Buffer.from(str, 'hex')).toString('utf8'); } catch { return ''; } }
    },
    decrypt: (s) => decBuf(Buffer.from(String(s), 'base64')),
    encryptBase64Str: (s) => encBuf(Buffer.from(String(s), 'utf8')).toString('base64'),
    encryptHex: (s) => encBuf(Buffer.from(String(s), 'utf8')).toString('hex'),
    encryptBase64: (s) => encBuf(Buffer.from(String(s), 'utf8')).toString('base64'),
  };
}

// ───────────────────────── @js 执行 ─────────────────────────
function runJs(code, ctx, extra = {}) {
  const sandbox = Object.assign({
    java: ctx.java,
    source: ctx.source,
    cookie: ctx.cookie,
    cache: ctx.cache,
    result: ctx.result,
    baseUrl: ctx.baseUrl,
    src: ctx.result,
    page: ctx.page,
    key: ctx.key,
    book: ctx.book,
    chapter: ctx.chapter,
    String, Number, Boolean, Array, Object, JSON, Math, Date, RegExp, parseInt, parseFloat, isNaN, encodeURIComponent, decodeURIComponent, console,
    org: { jsoup: { Jsoup: JsoupShim } },
    java_lang_String: String,
  }, extra);
  sandbox.globalThis = sandbox;
  const context = vm.createContext(sandbox);
  // 用包裹 IIFE 以拿到"最后表达式"的值：legado 取程序完成值，这里用 (function(){ ... })() 风格不行（含 return 才行）
  // node vm.runInContext 直接返回脚本完成值（最后一个表达式语句）
  const v = vm.runInContext(code, context, { timeout: 30000, filename: 'rule.js' });
  return v;
}
// Jsoup 兼容垫片（用 cheerio 实现 parse/.html()/.text()/.select()）
class JsoupShim {
  static parse(html) { return new JsoupDoc(String(html)); }
}
class JsoupDoc {
  constructor(html) { this.$ = cheerio.load(html, { decodeEntities: false }); this.root = this.$.root(); }
  html() { return this.$.root().html(); }
  text() { return this.$.root().text(); }
  select(sel) { return this.$(sel); }
  body() { return this; }
}

// ───────────────────────── 规则解析 ─────────────────────────
// 把 "##regex##repl" 应用到字符串
function applyRegexSpec(val, spec) {
  // spec 不含前导 ##
  // 形式: regex  或  regex##repl  （多段 ## 也尽量处理）
  const parts = spec.split('##');
  let s = val;
  // parts[0] = regex, parts[1] = repl(可空)
  for (let i = 0; i < parts.length; i += 2) {
    const reg = parts[i];
    const rep = parts[i + 1] != null ? parts[i + 1].replace(/\$(\d)/g, '$$$1') : '';
    if (!reg) continue;
    try { s = s.replace(new RegExp(reg, 'g'), rep); } catch {}
  }
  return s;
}
// 解析 CSS 规则（含 a.0 索引、@attr、@text、@html、##regex）
function cssExtractString(scope$, scopeEl, rule) {
  let r = rule.trim();
  let regexSpec = null;
  const hh = r.indexOf('##');
  if (hh >= 0) { regexSpec = r.slice(hh + 2); r = r.slice(0, hh); }
  // 按 @ 切（最后一段若是 text/href/src/html/attr.* 当作取值）
  const segs = r.split('@');
  let cur = scopeEl ? scope$(scopeEl) : scope$.root();
  let value = null;
  for (let i = 0; i < segs.length; i++) {
    let seg = segs[i].trim();
    if (seg === '') continue;
    const last = i === segs.length - 1;
    const kw = seg.toLowerCase();
    if (last && (kw === 'text' || kw === 'textnodes' || kw === 'owntext')) {
      const arr = []; cur.each((_, e) => { const t = scope$(e).text().trim(); if (t) arr.push(t); });
      value = arr.join('\n'); break;
    }
    if (last && kw === 'html') { value = cur.map((_, e) => scope$(e).html()).get().join('\n'); break; }
    if (last && (kw === 'href' || kw === 'src' || kw === 'value' || kw === 'title' || kw === 'content' || kw === 'data-src')) {
      value = cur.first().attr(kw) ?? ''; break;
    }
    if (last && kw.startsWith('attr.')) { value = cur.first().attr(seg.slice(5)) ?? ''; break; }
    // 否则 seg 是选择器（可能带 .N 索引 / legado class.x tag.x id.x）
    cur = selectLegado(scope$, cur, seg);
  }
  if (value == null) { // 没有显式取值 → 取 text
    const arr = []; cur.each((_, e) => { const t = scope$(e).text().trim(); if (t) arr.push(t); }); value = arr.join('\n');
  }
  if (regexSpec != null) value = applyRegexSpec(value, regexSpec);
  return value;
}
// legado 选择器（含 class./tag./id. 前缀与 .N 索引）
function selectLegado(scope$, cur, seg) {
  let sel = seg, index = null;
  // 取末尾 .数字(:数字)* 作为索引
  const im = sel.match(/\.(\d+(?::\d+)*)$/);
  if (im) { sel = sel.slice(0, im.index); index = im[1]; }
  sel = sel.replace(/^class\./, '.').replace(/^tag\./, '').replace(/^id\./, '#');
  let found = cur.find ? cur.find(sel) : scope$(sel);
  if (found.length === 0 && scope$(sel).length) found = scope$(sel);
  if (index != null) {
    const idxs = index.split(':').map(n => parseInt(n, 10));
    if (idxs.length === 1) found = found.eq(idxs[0]);
    else { const picked = idxs.map(i => found.get(i)).filter(Boolean); found = scope$(picked); }
  }
  return found;
}
function cssExtractList(scope$, rule) {
  let r = rule.trim().replace(/^class\./, '.').replace(/^tag\./, '').replace(/^id\./, '#');
  // 支持 "A@B@C" 链式（class.box.0@ul@li）
  if (r.includes('@')) {
    const segs = r.split('@'); let cur = scope$.root();
    for (const s of segs) cur = selectLegado(scope$, cur, s.trim());
    return cur.toArray();
  }
  return scope$(r).toArray();
}

// 极简 XPath（仅支持本项目所需: //tag[@attr="v"]/child 、 //@attr 、 text）
function xpathList($, expr) {
  // //select[@name="titleselect"]/option
  let e = expr.trim();
  let css = e.replace(/^\/\//, '').split('/').map(step => {
    const m = step.match(/^(\w+)(\[@([\w-]+)=["']([^"']*)["']\])?$/);
    if (!m) return step;
    let s = m[1]; if (m[3]) s += `[${m[3]}="${m[4]}"]`;
    return s;
  }).join(' > ');
  return $(css).toArray();
}

// 把单个"项"按子规则取值。item 可以是 cheerio 元素、JSON 对象、或字符串
function extractField(item, ctx, rule) {
  if (rule == null || rule === '') return '';
  rule = String(rule);
  if (rule.startsWith('@js:') || rule.startsWith('<js>')) {
    const code = rule.replace(/^@js:/, '').replace(/^<js>/, '').replace(/<\/js>$/, '');
    const sub = Object.assign({}, ctx, { result: item == null ? ctx.result : itemToResult(item) });
    sub.java = ctx.java;
    return runJs(code, sub);
  }
  // JSONPath
  if (rule.startsWith('$.') || rule.startsWith('$[') || rule.startsWith('$..')) {
    return jsonpath(item == null ? ctx.result : itemToObject(item, ctx), rule);
  }
  // 含 {{}} 模板
  if (rule.includes('{{') ) return evalTemplate(rule, item == null ? ctx.result : item, ctx);
  // 对象/字符串：键取值 + ##regex
  if (item && typeof item === 'object' && !item.cheerio && !item.tagName && !item.type) {
    let regexSpec = null, key = rule; const hh = rule.indexOf('##');
    if (hh >= 0) { regexSpec = rule.slice(hh + 2); key = rule.slice(0, hh); }
    let v = item[key] != null ? String(item[key]) : '';
    if (regexSpec != null) v = applyRegexSpec(v, regexSpec);
    return v;
  }
  // XPath
  if (rule.startsWith('//')) {
    if (rule.startsWith('//@')) { // 取属性
      const attr = rule.slice(3);
      const el = item && item.tagName ? item : null;
      return el ? (ctx.$(el).attr(attr) ?? '') : '';
    }
  }
  if (rule.startsWith('text')) { // text##... 用于 option 文本
    let regexSpec = null, r = rule; const hh = rule.indexOf('##');
    if (hh >= 0) { regexSpec = rule.slice(hh + 2); r = rule.slice(0, hh); }
    let v = item && item.tagName ? ctx.$(item).text().trim() : String(item);
    if (regexSpec != null) v = applyRegexSpec(v, regexSpec);
    return v;
  }
  // 默认 CSS（item 为元素或全文）
  if (item && item.tagName) return cssExtractString(ctx.$, item, rule);
  return cssExtractString(ctx.$, null, rule);
}
function itemToResult(item) {
  if (typeof item === 'string') return item;
  if (item && typeof item === 'object' && !item.tagName) return JSON.stringify(item);
  return item;
}
function itemToObject(item, ctx) {
  if (typeof item === 'string') { try { return JSON.parse(item); } catch { return item; } }
  if (item && typeof item === 'object' && !item.tagName) return item;
  return item;
}

// ───────────────────────── JSONPath（子集）─────────────────────────
function jsonpath(obj, expr) {
  // 支持 $.a.b, $..key, $.a.b||$.c, &&
  if (typeof obj === 'string') { try { obj = JSON.parse(obj); } catch {} }
  const orParts = expr.split('||');
  for (const op of orParts) {
    const v = jsonpathOne(obj, op.trim());
    if (v != null && v !== '') return v;
  }
  return '';
}
function jsonpathOne(obj, expr) {
  let e = expr.replace(/^\$/, '');
  if (e.startsWith('..')) { // 递归搜 key
    const key = e.slice(2).replace(/^\./, '');
    const res = []; (function walk(o) { if (o && typeof o === 'object') { for (const k in o) { if (k === key) res.push(o[k]); walk(o[k]); } } })(obj);
    return res.length ? (res.length === 1 ? res[0] : res) : '';
  }
  e = e.replace(/^\./, '');
  if (!e) return obj;
  let cur = obj;
  for (const part of e.split('.')) {
    if (cur == null) return '';
    const m = part.match(/^([^\[]*)(\[(\d+)\])?$/);
    const key = m[1], idx = m[3];
    if (key) cur = cur[key];
    if (idx != null) cur = cur && cur[parseInt(idx, 10)];
  }
  return cur == null ? '' : cur;
}

// ───────────────────────── {{}} 模板 ─────────────────────────
function evalTemplate(tpl, item, ctx) {
  return tpl.replace(/\{\{([\s\S]*?)\}\}/g, (_, expr) => {
    expr = expr.trim();
    if (expr.startsWith('$.') || expr.startsWith('$..')) {
      let regexSpec = null, e = expr; const hh = expr.indexOf('##');
      if (hh >= 0) { regexSpec = expr.slice(hh + 2); e = expr.slice(0, hh); }
      let v = jsonpath(itemToObject(item, ctx), e); v = Array.isArray(v) ? v.join(', ') : String(v);
      if (regexSpec != null) v = applyRegexSpec(v, regexSpec);
      return v;
    }
    try { return String(runJs('(' + expr + ')', Object.assign({}, ctx, { result: itemToResult(item) }))); } catch { return ''; }
  });
}
// URL 里的 {{}} 与 {{key}}/{{page}}
function expandUrlTemplate(u, ctx) {
  u = u.replace(/\{\{\s*key\s*\}\}/g, ctx.key ?? '').replace(/\{\{\s*page\s*\}\}/g, String(ctx.page ?? 1));
  u = u.replace(/\{\{([\s\S]*?)\}\}/g, (_, expr) => {
    try { return String(runJs('(' + expr.trim() + ')', ctx)); } catch (e) { return ''; }
  });
  return u;
}

// ───────────────────────── 顶层管线 ─────────────────────────
export class Source {
  constructor(json, opts = {}) {
    this.s = typeof json === 'string' ? JSON.parse(json) : json;
    this.baseUrl = this.s.bookSourceUrl.replace(/#.*$/, '');
    this.debug = opts.debug;
    this.varStore = loadVarStore();
    const self = this;
    this.ctx = {
      baseUrl: this.baseUrl, page: 1, key: '', kv: {}, cache: {}, debug: this.debug,
      defaultHeaders: this.parseHeaders(),
      cookie: { getCookie: () => '', setCookie: () => {} },
      source: {
        bookSourceComment: this.s.bookSourceComment || '',
        bookSourceUrl: this.s.bookSourceUrl,
        bookSourceName: this.s.bookSourceName,
        getVariable: () => self.varStore[self.s.bookSourceName] || '',
        setVariable: (v) => { self.varStore[self.s.bookSourceName] = v; saveVarStore(self.varStore); },
        getKey: () => self.s.bookSourceName,
        put: (k, v) => { self.ctx.kv[k] = v; },
        get: (k) => self.ctx.kv[k],
      },
    };
    this.ctx.java = makeJava(this.ctx);
  }
  parseHeaders() {
    const h = { 'User-Agent': 'Mozilla/5.0 (Linux; Android 9) Mobile Safari/537.36' };
    try { if (this.s.header) Object.assign(h, JSON.parse(this.s.header.startsWith('@js:') ? '{}' : this.s.header)); } catch {}
    return h;
  }
  setCtx(o) { Object.assign(this.ctx, o); }

  // 抓页面 → 设置 ctx.result
  _fetch(rawUrl) {
    const r = fetchPage(rawUrl, this.baseUrl, this.ctx);
    this.ctx.result = r.text; this.ctx.lastResult = r.text; this.ctx.$ = null;
    this.ctx._status = r.status;
    return r;
  }
  _ensure$() { if (!this.ctx.$) this.ctx.$ = cheerio.load(this.ctx.result || '', { decodeEntities: false }); return this.ctx.$; }

  async search(key, page = 1) {
    this.ctx.key = key; this.ctx.page = page;
    let url = expandUrlTemplate(this.s.searchUrl, this.ctx);
    if (this.debug) console.error('[search url]', url.slice(0, 200));
    this._fetch(url);
    const rs = this.s.ruleSearch;
    const items = this._list(rs.bookList);
    const out = [];
    for (const it of items) {
      const b = {
        name: this._field(it, rs.name), author: this._field(it, rs.author),
        bookUrl: absUrl(this.baseUrl, this._field(it, rs.bookUrl)),
        coverUrl: this._field(it, rs.coverUrl), intro: this._field(it, rs.intro),
        kind: this._field(it, rs.kind), lastChapter: this._field(it, rs.lastChapter),
        _raw: (typeof it === 'object' && !it.tagName) ? it : undefined,
      };
      if (b.name || b.bookUrl) out.push(b);
    }
    return out;
  }
  async bookInfo(book) {
    const ri = this.s.ruleBookInfo || {};
    this.ctx.book = book;
    this._fetch(book.bookUrl);
    if (ri.init) {
      const v = this._field(null, ri.init); // @js init → 返回新的 result(JSON)
      if (v != null && v !== '') { this.ctx.result = typeof v === 'string' ? v : JSON.stringify(v); this.ctx.$ = null; }
    }
    const info = Object.assign({}, book);
    if (ri.name) info.name = this._field(null, ri.name) || book.name;
    if (ri.author) info.author = this._field(null, ri.author) || book.author;
    if (ri.intro) info.intro = this._field(null, ri.intro);
    const tocUrl = ri.tocUrl ? this._field(null, ri.tocUrl) : '';
    info.tocUrl = absUrl(this.baseUrl, tocUrl) || book.bookUrl;
    return info;
  }
  async toc(tocUrl) {
    this._fetch(tocUrl);
    const rt = this.s.ruleToc;
    let items = this._list(rt.chapterList);
    const out = [];
    for (const it of items) {
      let name = this._field(it, rt.chapterName);
      let url = this._field(it, rt.chapterUrl);
      out.push({ name: String(name).trim(), url: absUrl(this.baseUrl, String(url)) });
    }
    return out;
  }
  async content(chapterUrl) {
    this._fetch(chapterUrl);
    const rc = this.s.ruleContent;
    let v = this._field(null, rc.content);
    let text = v == null ? '' : (typeof v === 'string' ? v : String(v));
    // 若是 html，转纯文本
    if (/<[a-z][\s\S]*>/i.test(text)) {
      const $ = cheerio.load('<div id="_c">' + text + '</div>', { decodeEntities: false });
      $('#_c br').replaceWith('\n'); $('#_c p').append('\n');
      text = $('#_c').text();
    }
    if (rc.replaceRegex) text = applyRegexSpec(text, rc.replaceRegex.replace(/^##/, ''));
    text = text.replace(/\n{3,}/g, '\n\n').replace(/[\t ]+\n/g, '\n').trim();
    return text;
  }

  // 取列表（CSS / XPath / @js）
  _list(rule) {
    if (!rule) return [];
    rule = String(rule);
    if (rule.startsWith('@js:') || rule.startsWith('<js>')) {
      const code = rule.replace(/^@js:/, '').replace(/^<js>/, '').replace(/<\/js>$/, '');
      const v = runJs(code, this.ctx);
      if (Array.isArray(v)) return v;
      if (typeof v === 'string') { try { const p = JSON.parse(v); return Array.isArray(p) ? p : [p]; } catch { return [v]; } }
      return v ? [v] : [];
    }
    if (rule.startsWith('//')) { const $ = this._ensure$(); return xpathList($, rule).map(el => ({ tagName: el.tagName || el.name, _el: el, ...{} }, el)).map(x => x); }
    const $ = this._ensure$();
    if (rule.startsWith('//')) return xpathList($, rule);
    return cssExtractList($, rule);
  }
  _field(item, rule) {
    if (rule == null) return '';
    this.ctx.$ = this.ctx.$ || (this.ctx.result != null ? cheerio.load(this.ctx.result || '', { decodeEntities: false }) : cheerio.load(''));
    const ctx = this.ctx;
    return extractField(item == null ? wholeDoc(ctx) : item, ctx, rule);
  }
}
function wholeDoc(ctx) { return null; }

// CLI
if (process.argv[1] && process.argv[1].endsWith('harness.mjs')) {
  const [, , file, action, ...rest] = process.argv;
  const json = fs.readFileSync(file, 'utf8');
  const src = new Source(json, { debug: process.env.DEBUG === '1' });
  const arg = rest.join(' ');
  const run = async () => {
    if (action === 'book') { // 直接按 bookUrl 跑 详情→目录→正文（绕过搜索）
      const info = await src.bookInfo({ name: '(direct)', bookUrl: arg });
      console.log('详情 tocUrl:', info.tocUrl, '| name:', info.name);
      const ch = await src.toc(info.tocUrl);
      console.log('目录:', ch.length, '章; 前5:', ch.slice(0, 5).map(c => c.name).join(' | '));
      if (ch.length) {
        const c0 = ch[0];
        const text = await src.content(c0.url);
        console.log('\n===== 正文 [' + c0.name + '] (' + c0.url + ') =====\n' + text.slice(0, 1500));
        console.log('\n[正文长度]', text.length);
      }
    }
    else if (action === 'search') console.log(JSON.stringify(await src.search(arg || '深空彼岸'), null, 2));
    else if (action === 'full') {
      const list = await src.search(arg || '深空彼岸');
      console.log('搜索结果:', list.length, '本'); console.log(list.slice(0, 3).map(b => `  - ${b.name} / ${b.author} / ${b.bookUrl}`).join('\n'));
      if (!list.length) return;
      const info = await src.bookInfo(list[0]);
      console.log('详情 tocUrl:', info.tocUrl);
      const ch = await src.toc(info.tocUrl);
      console.log('目录:', ch.length, '章; 前3:', ch.slice(0, 3).map(c => c.name).join(' | '));
      if (!ch.length) return;
      const c0 = ch[Math.min(1, ch.length - 1)];
      const text = await src.content(c0.url);
      console.log('\n===== 正文 [' + c0.name + '] =====\n' + text.slice(0, 1200));
      console.log('\n[正文长度]', text.length);
    }
  };
  run().catch(e => { console.error('ERROR', e && e.stack || e); process.exit(1); });
}
