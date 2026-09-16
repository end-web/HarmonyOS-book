// Runs the actual Talebook ArkTS adapters with an in-memory NAS and encrypted-store boundary.
// Usage: DEVECO_HOME=<installed IDE> node scripts/test-talebook.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawn } = require('node:child_process');
const live = process.argv.includes('--live');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const prefix = 'service/rulesource/talebook/';
const origin = 'http://[2001:db8::1]:58080';
const definitions = new Map();
const cookies = new Map();
const requests = [];
let expires = false;
let empty = false;
const opf = '<package><manifest><item id="first" href="text/a.xhtml" media-type="application/xhtml+xml"/>' +
  '<item id="second" href="text/b.xhtml" media-type="application/xhtml+xml"/>' +
  '<item id="nav" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>' +
  '<spine><itemref idref="second"/><itemref idref="first"/><itemref idref="second"/></spine></package>';
const book = { id: 14, title: '测试电子书', author: '作者', img: '/cover.jpg', comments: '<p>简介</p>',
  files: [{ format: 'EPUB', href: '/api/book/14.EPUB' }], edition: { id: 6 } };
const manifest = { id: 6, book_id: 14, chapters: [
  { number: 1, title: '第一章', duration_ms: 42500, audio_url: '/media/audio/6/chapter/1.mp3' }
] };
const result = (body, headers = {}, statusCode = 200) => ({
  ok: statusCode >= 200 && statusCode < 300, statusCode, headers,
  body: typeof body === 'string' ? body : JSON.stringify(body), errorMessage: ''
});
async function execute(plan) {
  if (live) return liveRequest(plan);
  requests.push(plan);
  const url = new URL(plan.url);
  if (url.pathname === '/api/welcome') {
    const valid = plan.body === 'invite_code=fixture-code';
    return valid ? result({ err: 'ok' }, { 'Set-Cookie': 'invited="fixture-session"; HttpOnly; Path=/; expires=Wed, 01 Jan 2031 00:00:00 GMT' })
      : result({ err: 'params.invalid', msg: '访问码无效' });
  }
  if (expires || plan.headers.Cookie !== 'invited="fixture-session"') return result({ err: 'not_invited' });
  switch (url.pathname) {
    case '/api/user/info': return result({ err: 'ok', sys: { title: '测试书库', version: 'v26.09.01' } });
    case '/api/audios': return result({ err: 'ok', total: empty ? 0 : 1, books: empty ? [] : [book] });
    case '/api/search':
    case '/api/recent': return result({ err: 'ok', total: empty ? 0 : 1, books: empty ? [] : [book] });
    case '/api/book/14': return result({ err: 'ok', book });
    case '/api/audio/6': return result({ err: 'ok', manifest });
    case '/get/extract/14/META-INF/container.xml': return result('<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>');
    case '/get/extract/14/OEBPS/content.opf': return result(opf);
    case '/get/extract/14/OEBPS/toc.ncx': return result('<ncx><navMap><navPoint><navLabel><text>第一节</text></navLabel><content src="text/b.xhtml#part"/></navPoint></navMap></ncx>');
    case '/get/extract/14/OEBPS/text/b.xhtml': return result('<html><head><title>不应进入正文</title></head><body><p>正文 &amp; 内容</p><script>bad()</script><p>下一段</p></body></html>');
    default: throw new Error(`Unexpected fixture request ${url.pathname}`);
  }
}
const repository = {
  get: async key => definitions.get(key),
  upsertImportedBatch: async sources => { for (const s of sources) definitions.set(s.bookSourceUrl, s); },
};
const http = {
  execute,
  getStoredCookieHeader: async key => cookies.get(key) || '',
  saveWebCookies: async (key, _url, value) => { assert(definitions.has(key)); cookies.set(key, value); },
  fetch: async (source, address) => {
    const options = JSON.parse(address.slice(address.indexOf(',{') + 1));
    assert.equal(options.redirect, false);
    return execute({ url: address.split(',{')[0], headers: { Cookie: cookies.get(source.bookSourceUrl) || '' } });
  }
};
const modules = new Map();
const stubs = {
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: repository },
  'service/rulesource/LocalRuleHttpClient': { LocalRuleHttpClient: http },
  'service/CoverPrefetcher': { CoverPrefetcher: { registerHeaders() {} } },
  'utils/CharsetCodec': { CharsetCodec: {} },
  '@kit.ArkTS': { buffer: { from: Buffer.from }, util: {} },
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const filename = path.join(root, name + '.ets');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
  }).outputText;
  const module = { exports: {} };
  modules.set(name, module);
  vm.runInNewContext(code, {
    module, exports: module.exports, console, Error, Map, Set, URL,
    ObservedV2: value => value, Trace: () => {},
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
async function main() {
  const { TalebookSourceIdentity: identity } = load(prefix + 'TalebookSourceIdentity');
  const { TalebookApiClient: api } = load(prefix + 'TalebookApiClient');
  const { TalebookSourceAdapter: adapter } = load(prefix + 'TalebookSourceAdapter');
  const { TalebookEpub: epub } = load(prefix + 'TalebookEpub');
  if (live) {
    const address = process.env.TALEBOOK_URL;
    if (!address) throw new Error('--live requires TALEBOOK_URL and optional TALEBOOK_CODE');
    const connection = await api.connect(address, process.env.TALEBOOK_CODE || '');
    await api.install(connection);
    const audio = definitions.get(connection.origin + '/#talebook-audio');
    const text = definitions.get(connection.origin + '/#talebook-text');
    const keyword = process.env.TALEBOOK_KEYWORD || '';
    const audioBooks = await adapter.search(audio, keyword);
    const textBooks = await adapter.search(text, keyword);
    console.log(`LIVE login success; matching audio=${audioBooks.length}, text=${textBooks.length}`);
    assert(audioBooks.length && textBooks.length, 'Select a keyword with both audio and EPUB books');
    const info = await adapter.info(audio.bookSourceUrl, audioBooks[0].bookUrl);
    const chapters = await adapter.toc(audio.bookSourceUrl, info.tocUrl);
    assert(chapters.length);
    const playback = await adapter.content(audio.bookSourceUrl, chapters[0].url);
    const audioBytes = await liveRequest({ url: playback.audioUrl, headers: { ...playback.requestHeaders, Range: 'bytes=0-1023' }, binary: true });
    assert.equal(audioBytes.statusCode, 206);
    assert.equal(audioBytes.bytes, 1024);
    console.log(`LIVE audio detail/toc=${chapters.length}; authenticated Range request=206/1024 bytes`);
    const textInfo = await adapter.info(text.bookSourceUrl, textBooks[0].bookUrl);
    const textChapters = await adapter.toc(text.bookSourceUrl, textInfo.tocUrl);
    assert(textChapters.length);
    const content = await adapter.content(text.bookSourceUrl, textChapters[0].url);
    assert(content.content.length > 0);
    console.log(`LIVE EPUB toc=${textChapters.length}; first chapter=${content.content.length} characters`);
    return;
  }
  assert.equal(identity.origin(origin + '/'), origin);
  for (const invalid of ['file:///tmp', 'http://u:p@nas', origin + '/admin', origin + '?password=x']) {
    assert.throws(() => identity.origin(invalid));
  }
  await assert.rejects(() => api.connect(origin, 'wrong'), /访问码无效/);
  assert.equal(definitions.size, 0);
  const connection = await api.connect(origin, 'fixture-code');
  await api.install(connection);
  assert.equal(definitions.size, 2);
  const audio = definitions.get(origin + '/#talebook-audio');
  const text = definitions.get(origin + '/#talebook-text');
  assert(audio.hasSearchCapability());
  assert(text.hasSearchCapability());
  assert(!JSON.stringify([...definitions.values()]).includes('fixture-code'));
  assert(!JSON.stringify([...definitions.values()]).includes('fixture-session'));
  const books = await adapter.search(audio, '测试');
  assert.equal(books.length, 1);
  assert.equal((await adapter.search(audio, '不存在')).length, 0);
  const info = await adapter.info(audio.bookSourceUrl, books[0].bookUrl);
  assert.equal(info.name, book.title);
  const toc = await adapter.toc(audio.bookSourceUrl, info.tocUrl);
  assert.equal(toc[0].duration, 42);
  const playback = await adapter.content(audio.bookSourceUrl, toc[0].url);
  assert.equal(playback.audioUrl, origin + '/media/audio/6/chapter/1.mp3');
  assert.equal(playback.requestHeaders.Cookie, 'invited="fixture-session"');
  const textBooks = await adapter.search(text, '测试');
  const chapters = await adapter.toc(text.bookSourceUrl, textBooks[0].bookUrl);
  assert.equal(chapters.length, 2);
  assert.equal(chapters[0].name, '第一节');
  assert(chapters[0].url.endsWith('/b.xhtml'));
  const content = await adapter.content(text.bookSourceUrl, chapters[0].url);
  assert.equal(content.content, '正文 & 内容\n\n下一段');
  for (const href of ['../../../../outside.xhtml', 'https://evil.test/x', '%2e%2e/%2e%2e/outside', 'text/%5c..%5cx']) {
    assert.throws(() => epub.resource(origin + '/get/extract/14/', origin + '/get/extract/14/OEBPS/content.opf', href));
  }
  await assert.rejects(() => adapter.content(audio.bookSourceUrl, 'https://evil.test/a.mp3'), /非本站/);
  await assert.rejects(() => adapter.content(audio.bookSourceUrl, origin + '/api/admin'), /音频地址/);
  audio.enabled = false;
  audio.isLocked = true;
  audio.bookSourceName = '自定义名称';
  await api.install(connection);
  assert.equal(definitions.get(audio.bookSourceUrl), audio);
  assert.equal(audio.enabled, false);
  assert.equal(audio.isLocked, true);
  assert.equal(audio.bookSourceName, '自定义名称');
  assert((await adapter.content(audio.bookSourceUrl, toc[0].url)).audioUrl);
  empty = true;
  const noBooks = await adapter.list(audio);
  assert.equal(noBooks.books.length, 0);
  assert.equal(noBooks.nextUrl, '');
  expires = true;
  await assert.rejects(() => adapter.content(audio.bookSourceUrl, toc[0].url), /会话已失效/);
  expires = false;
  definitions.delete(audio.bookSourceUrl);
  await assert.rejects(() => adapter.content(audio.bookSourceUrl, toc[0].url), /已删除/);
  console.log('PASS Talebook: login, source/session isolation, search, audio, EPUB spine/content, path bounds, empty library, expiry, disabled/locked/deleted sources');
}
// Credentials travel via stdin only; cookies and NAS contents stay in this process's memory.
async function liveRequest(plan) {
  const command = `
$ErrorActionPreference='Stop'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$p=([Console]::In.ReadToEnd() | ConvertFrom-Json)
$headers=@{}
foreach($prop in $p.headers.PSObject.Properties){$headers[$prop.Name]=[string]$prop.Value}
$args=@{Uri=$p.url;Method=$(if($p.method){$p.method}else{'GET'});Headers=$headers;TimeoutSec=20;MaximumRedirection=0;SkipHttpErrorCheck=$true}
if($null -ne $p.body){$args.Body=[string]$p.body}
$r=Invoke-WebRequest @args
$out=@{}
foreach($key in $r.Headers.Keys){$out[$key]=$r.Headers[$key] -join "\n"}
@{ok=($r.StatusCode -ge 200 -and $r.StatusCode -lt 300);statusCode=[int]$r.StatusCode;headers=$out;body=$(if($p.binary){''}else{[string]$r.Content});bytes=$r.RawContentLength;errorMessage=''} | ConvertTo-Json -Depth 6 -Compress
`;
  for (let attempt = 0; attempt < 3; attempt++) {
    const response = await new Promise((resolve, reject) => {
      const child = spawn('pwsh', ['-NoProfile', '-NonInteractive', '-Command', command], { windowsHide: true });
      let output = '';
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', value => { output += value; });
      child.stderr.resume();
      child.on('error', reject);
      child.on('close', code => {
        if (code !== 0) return reject(new Error('NAS transport failed (network/proxy/timeout)'));
        try { resolve(JSON.parse(output)); } catch { reject(new Error('Invalid transport response')); }
      });
      child.stdin.end(JSON.stringify(plan));
    });
    if (response.statusCode < 500 || attempt === 2) return response;
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
