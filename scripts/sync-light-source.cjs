// Import the source engine only. UI, account, database and app configuration stay local.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const project = path.resolve(__dirname, '..');
const source = path.resolve(process.argv[2] || 'D:/legado-harmony');
const sourceRoot = path.join(source, 'entry/src/main/ets');
const target = path.join(project, 'entry/src/main/ets/service/rulesource/light/upstream');
const manifestPath = path.join(project, 'third_party/light-source/upstream.json');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const excluded = new Set(['model/data/AppDatabase.ts']);
const seeds = ['core/book/WebBookService.ts', 'core/book/SearchCoordinator.ts',
  'core/book/ExploreCoordinator.ts', 'core/nativesource/NativeSourceService.ts',
  'core/book/ReaderInteractionProvider.ts', 'core/book/BookSourceScriptRunner.ts',
  'core/book/BookSourceLoginWebRuntime.ts', 'core/http/RawHttpTextClient.ts'];
const files = new Map();
const visit = name => {
  if (files.has(name) || excluded.has(name)) return;
  const text = fs.readFileSync(path.join(sourceRoot, name), 'utf8');
  files.set(name, text);
  for (const match of text.matchAll(/(?:from\s*|import\s*)['"]([^'"]+)['"]/g)) {
    if (!match[1].startsWith('.')) continue;
    const base = path.resolve(sourceRoot, path.dirname(name), match[1]);
    const found = ['.ts', '.ets', '/index.ts', '/index.ets'].map(ext => base + ext).find(fs.existsSync);
    if (!found) throw new Error(`Unresolved dependency ${name}: ${match[1]}`);
    const relative = path.relative(sourceRoot, found).replaceAll('\\', '/');
    if (relative.endsWith('.ets')) throw new Error(`UI dependency must be adapted explicitly: ${relative}`);
    visit(relative);
  }
};
seeds.forEach(visit);
const previous = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : null;
for (const entry of previous?.files || []) {
  const filename = path.join(target, entry.path);
  if (!fs.existsSync(filename) || hash(fs.readFileSync(filename)) !== entry.sha256) {
    throw new Error(`Local engine change: ${entry.path}. Update the adapter/patch before syncing.`);
  }
}
const replaceMethod = (text, signature, body) => {
  const expression = new RegExp('(^  ' + signature + '[\\s\\S]*?\\n  \\})', 'm');
  if (!expression.test(text)) throw new Error(`Upstream method changed: ${signature}`);
  return text.replace(expression, body);
};
function adapt(name, text) {
  text = text.replaceAll('\r\n', '\n');
  if (name === 'core/http/CookieStore.ts') return `export { LightCookieStore as CookieStore } from '../../../LightSourceRuntime';\n`;


  if (name === 'core/book/BookSourceStageWebRuntime.ts') {
    text = `import { LightSourceRuntime } from '../../../LightSourceRuntime';\n` + text;
    text = replaceMethod(text, 'isAvailable\\(\\)', '  isAvailable(): boolean {\n    return true;\n  }');
    text = replaceMethod(text, 'async waitUntilAvailable\\(', '  async waitUntilAvailable(timeoutMs: number = 5000): Promise<boolean> {\n    return true;\n  }');
    text = replaceMethod(text, 'private async runJavaScript\\(', '  private async runJavaScript(script: string): Promise<string> {\n    return LightSourceRuntime.evaluate(script);\n  }');
    text = text.replace('if (!this.findReadyController()) {', 'if (!this.isAvailable()) {');
  }
  if (name === 'core/book/WebBookService.ts') {
    text = text.replace('if (!resp.success || !resp.body) return book;',
      "if (!resp.success || !resp.body) { AppStorage.setOrCreate('bookSourceStageLastError', resp.error || '详情请求失败或空响应'); return book; }");
  }
  if (name === 'core/book/SearchCoordinator.ts') {
    text = text.replace('export interface SearchOptions {', 'export interface SearchOptions {\n  page?: number;');
    text = text.replace('private searchSerial: number = 0;', 'private searchSerial: number = 0;\n  private currentPage: number = 1;');
    text = text.replace('    this.searchSerial++;', '    this.searchSerial++;\n    this.currentPage = Math.max(1, Math.floor(options.page || 1));');
    text = text.replaceAll("setVar('page', '1')", "setVar('page', String(this.currentPage))")
      .replaceAll("setJsVar('page', '1')", "setJsVar('page', String(this.currentPage))")
      .replace('PageCandidateUrl.apply(urlTemplate, 1)', 'PageCandidateUrl.apply(urlTemplate, this.currentPage)')
      .replace("source, searchUrl, '1', keyword", 'source, searchUrl, String(this.currentPage), keyword')
      .replace("page: '1',", 'page: String(this.currentPage),').replace("pageIndex: '1'", 'pageIndex: String(this.currentPage)')
      .replace('keyword, stopped, responseLimit)', 'keyword, stopped, responseLimit, this.currentPage)');
    // Keep the task cookie context alive until abandoned work has stopped at its checkpoints.
    text = text.replace('return await Promise.race([this.searchOne(source, keyword, options, abort), timeout]);',
      'const work = this.searchOne(source, keyword, options, abort);\n      const result = await Promise.race([work, timeout]);\n      await work;\n      return result;');
  }
  if (name === 'core/nativesource/NativeSourceService.ts') {
    text = text.replace('maxResponseBytes: number = 0): Promise<SearchBook[]>', 'maxResponseBytes: number = 0, page: number = 1): Promise<SearchBook[]>')
      .replace('.search(keyword, 1)', '.search(keyword, page)');
  }
  if (name === 'core/script/QuickJsScriptRuntime.ts') {
    text = replaceMethod(text, 'private static evaluateInContext\\(',
      '  private static evaluateInContext(code: string, variables: Record<string, Object>,\n    declarations: string[], timeoutMs: number, output: QuickJsExpressionResult, scriptName: string): QuickJsExpressionResult {\n    output.error = \'synchronous QuickJS disabled; use bounded taskpool stage runtime\';\n    return output;\n  }');
  }
  if (name === 'core/book/BookSourceRuntimeRouter.ts') {
    text = text.replace('if (decision.capabilities.requiresFullJs) {', 'if (script.trim().length > 0) {');
  }
  return adaptRequestPolicy(name, adaptTiming(name, adaptIsolation(name, text)));
}

// Keep source frequency semantics upstream; application playback controls queue priority/cancellation.
function adaptRequestPolicy(name, text) {
  const selected = ['core/http/BookSourceRateLimiter.ts', 'core/rule/AnalyzeUrl.ts',
    'core/http/HttpClient.ts', 'core/book/BookSourceStageWebRuntime.ts'];
  if (!selected.includes(name)) return text;
  text = "import { LightSourceRequestPolicy } from '../../../LightSourceRequestPolicy';\n" + text;
  if (name === 'core/http/BookSourceRateLimiter.ts') {
    const match = text.match(/^  static async acquire\([\s\S]*?\n  \}/m);
    if (!match) throw Error('Missing source limiter adapter target');
    let method = match[0].replace('    if (!source ||',
      '    if (LightSourceRequestPolicy.isCancelled(source) || isCancelled?.()) return RateLimitAcquireResult.Cancelled;\n    if (!source ||');
    method = method.replace('    while (true) {', `    const waiter = LightSourceRequestPolicy.enqueue(key, source, isCancelled);
    try {
    while (true) {`)
      .replace('isCancelled && isCancelled()', 'waiter.isCancelled()')
      .replace('      if (state.timestamps.length < config.limit) {', `      if (state.timestamps.length < config.limit) {
        if (!LightSourceRequestPolicy.first(key, waiter)) {
          if (deadline > 0 && now >= deadline) return RateLimitAcquireResult.RateLimited;
          await waiter.wait(deadline > 0 ? Math.min(500, Math.max(1, deadline - now)) : 500);
          continue;
        }`)
      .replace('await sleepMs(', 'await waiter.wait(')
      .replace(/\n  \}$/, '\n    } finally { LightSourceRequestPolicy.remove(key, waiter); }\n  }');
    text = text.replace(match[0], method);
  }
  if (name === 'core/rule/AnalyzeUrl.ts') {
    text = text.replace('const request: HttpRequest = {', `const request: HttpRequest = {
      cancelCheck: () => LightSourceRequestPolicy.isCancelled(this.source) || !!this.cancelCheck?.(),`);
    text = text.replace("'source-rate-wait', startedAt);", "'source-rate-wait', startedAt, 'priority=' + LightSourceRequestPolicy.priority(this.source) + ' cancelled=' + LightSourceRequestPolicy.isCancelled(this.source));");
    text = text.replace('      const webResponse = await this.client.execute({ ...req, useWebView: true });',
      "      if (req.cancelCheck?.()) return this.notSentResponse(req, RateLimitAcquireResult.Cancelled);\n      const webResponse = await this.client.execute({ ...req, useWebView: true });");
  }
  if (name === 'core/http/HttpClient.ts') {
    text = text.replace('export interface HttpRequest {', 'export interface HttpRequest {\n  cancelCheck?: () => boolean;');
    // Check every attempt (including transport retries) immediately before creating/sending HTTP.
    const cancelled = `    if (req.cancelCheck?.()) return {url:req.url,statusCode:0,headers:{},body:'',success:false,error:'书源请求已取消'};\n`;
    text = text.replace('  private async executeInternal(req: HttpRequest): Promise<HttpResponse> {',
      '  private async executeInternal(req: HttpRequest): Promise<HttpResponse> {\n' + cancelled);
    text = text.replace('  private async executeWithProtocol(req: HttpRequest, forceHttp1: boolean): Promise<HttpResponse> {',
      '  private async executeWithProtocol(req: HttpRequest, forceHttp1: boolean): Promise<HttpResponse> {\n' + cancelled);
  }
  if (name === 'core/book/BookSourceStageWebRuntime.ts') {
    text = text.replace('    if (request.ownerId && this.cancelledOwners.has(request.ownerId)) {',
      '    if (LightSourceRequestPolicy.isCancelled(request.source) || (request.ownerId && this.cancelledOwners.has(request.ownerId))) {');
  }
  return text;
}

// Diagnostics stay in the platform adapter so a sync preserves the fixed upstream behavior.
function adaptTiming(name, text) {
  const selected = ['core/http/HttpClient.ts', 'core/rule/AnalyzeUrl.ts', 'core/book/BookSourceStageWebRuntime.ts'];
  if (!selected.includes(name)) return text;
  text = "import { LightSourceTiming } from '../../../LightSourceTiming';\n" + text;
  if (name === 'core/rule/AnalyzeUrl.ts') {
    text = text.replace('const request: HttpRequest = {', 'const request: HttpRequest = {\n      timingId: LightSourceTiming.id(this.source),');
    text = text.replaceAll('BookSourceRateLimiter.acquire(this.source, this.cancelCheck, this.rateLimitMaxWaitMs)', 'this.acquireTimedSlot()');
    text = text.replace('  private async fetchFollowingRedirects(', `  private async acquireTimedSlot(): Promise<RateLimitAcquireResult> {
    const startedAt = Date.now();
    try { return await BookSourceRateLimiter.acquire(this.source, this.cancelCheck, this.rateLimitMaxWaitMs); }
    finally { LightSourceTiming.end(LightSourceTiming.id(this.source), 'source-rate-wait', startedAt); }
  }

  private async fetchFollowingRedirects(`);
  }
  if (name === 'core/book/BookSourceStageWebRuntime.ts') {
    text = text.replace('private async runJavaScript(script: string, sourceUrl: string)', 'private async runJavaScript(script: string, sourceUrl: string, timingId: number)')
      .replace('LightSourceRuntime.evaluate(script, sourceUrl)', 'LightSourceRuntime.evaluate(script, sourceUrl, timingId)')
      .replace('this.runJavaScript(script, request.source.bookSourceUrl)', 'this.runJavaScript(script, request.source.bookSourceUrl, LightSourceTiming.id(request.source))');
    text = text.replace('      const script = this.buildScript(', '      const buildStartedAt = Date.now();\n      const script = this.buildScript(')
      .replace('      const raw = await this.runJavaScript(', "      LightSourceTiming.end(LightSourceTiming.id(request.source), 'stage-script-build', buildStartedAt, `replay=${stepIndex}`);\n      const raw = await this.runJavaScript(");
  }
  if (name === 'core/http/HttpClient.ts') {
    text = text.replace('export interface HttpRequest {', 'export interface HttpRequest {\n  timingId?: number;');
    text = text.replace('    if (req.debugContext) {', "    LightSourceTiming.end(req.timingId || 0, 'http-total', startedAt, `status=${response.statusCode} success=${response.success} web=${!!req.useWebView}`);\n    if (req.debugContext) {");
    // request() exposes cumulative SDK milestones in milliseconds (API 11+, valid on API 20).
    text = text.replaceAll('      const resp = await client.request(req.url, options);', `      const transportStartedAt = Date.now();
      const resp = await client.request(req.url, options);
      const timing = resp.performanceTiming;
      LightSourceTiming.end(req.timingId || 0, 'http-transport', transportStartedAt,
        'http1=' + forceHttp1 + ' status=' + resp.responseCode + (timing ?
        ' dnsEndMs=' + timing.dnsTiming + ' tcpEndMs=' + timing.tcpTiming +
        ' tlsEndMs=' + timing.tlsTiming + ' sendStartMs=' + timing.firstSendTiming +
        ' firstByteMs=' + timing.firstReceiveTiming + ' finishMs=' + timing.totalFinishTiming +
        ' redirectEndMs=' + timing.redirectTiming + ' sdkTotalMs=' + timing.totalTiming : ' sdkTiming=unavailable'));`);
    text = text.replace('    result: string | Object): HttpResponse {', '    result: string | Object): HttpResponse {\n    const decodeStartedAt = Date.now();');
    text = text.replace("    const finalBody = req.charset ? body : this.decodeBodyWithMetaCharset(result, body, charset);", "    const finalBody = req.charset ? body : this.decodeBodyWithMetaCharset(result, body, charset);\n    LightSourceTiming.end(req.timingId || 0, 'http-cookie-decode', decodeStartedAt);");
    text = text.replace('          responseCode = await client.requestInStream(req.url, options);', `          const streamStartedAt = Date.now();
          try { responseCode = await client.requestInStream(req.url, options); }
          finally { LightSourceTiming.end(req.timingId || 0, 'http-stream-transport', streamStartedAt, 'http1=' + forceHttp1); }`);
    text = text.replace('        let receivedBytes = 0;', '        let receivedBytes = 0;\n        let streamSentAt = 0;\n        let headersTimed = false;\n        let dataTimed = false;');
    text = text.replace('          streamedHeaders = (value || {})', "          if (!headersTimed && streamSentAt > 0) {\n            headersTimed = true;\n            LightSourceTiming.end(req.timingId || 0, 'http-stream-first-headers', streamSentAt);\n          }\n          streamedHeaders = (value || {})");
    text = text.replace('          receivedBytes += chunk.byteLength;', "          if (!dataTimed && streamSentAt > 0) {\n            dataTimed = true;\n            LightSourceTiming.end(req.timingId || 0, 'http-stream-first-data', streamSentAt);\n          }\n          receivedBytes += chunk.byteLength;");
    text = text.replace('          const streamStartedAt = Date.now();', '          const streamStartedAt = Date.now();\n          streamSentAt = streamStartedAt;');
  }
  return text;
}
// Local execution/session policy: keep rule syntax upstream, bind host effects explicitly.
function adaptIsolation(name, text) {
  const addRuntime = () => {
    if (!text.includes("import { LightSourceRuntime }")) text = "import { LightSourceRuntime } from '../../../LightSourceRuntime';\n" + text;
  };
  if (name === 'core/http/HttpClient.ts') {
    addRuntime();
    text = text.replace('export interface HttpRequest {', 'export interface HttpRequest {\n  cookieSource?: string;');
    text = text.replaceAll('CookieStore.', 'CookieStore.forSource(req.cookieSource).');
    text = text.replace('if (req.useWebView) {', "if (req.useWebView) {\n      return await LightSourceRuntime.withWeb(req.cookieSource || '', async () => {");
    text = text.replace('        url: req.url,\n        method: req.method,', '        url: req.url,\n        cookieSource: req.cookieSource,\n        method: req.method,');
    text = text.replace('      });\n    }\n    const response = await this.executeWithProtocol', '      });\n      });\n    }\n    const response = await this.executeWithProtocol');
    text = text.replaceAll('if (setCookie) {', 'if (setCookie && req.useCookieJar !== false) {');
  }
  if (name === 'core/rule/AnalyzeUrl.ts') {
    text = text.replace('RequestSessionSupport.apply(this.config.url, merged, this.config.session)',
      "RequestSessionSupport.apply(this.config.url, merged, this.config.session, this.source?.bookSourceUrl || '')");
    text = text.replace('const request: HttpRequest = {', "const request: HttpRequest = {\n      cookieSource: this.source?.bookSourceUrl || '',");
  }
  if (name === 'core/http/RequestSessionSupport.ts') {
    text = text.replace('config: RequestSessionConfig): void {', "config: RequestSessionConfig, sourceUrl: string = ''): void {");
    text = text.replaceAll('CookieStore.', 'CookieStore.forSource(sourceUrl).');
  }
  if (name === 'core/http/VerificationSupport.ts') {
    const split = text.indexOf('  static syncLoginCookiesToSourceHosts(');
    text = text.slice(0, split).replaceAll('CookieStore.', 'CookieStore.forSource(source.bookSourceUrl).') +
      text.slice(split).replaceAll('CookieStore.', 'CookieStore.forSource(sourceUrl).');
  }
  if (name === 'core/nativesource/NativeSourceService.ts') {
    const split = text.indexOf('export class NativeSourceService');
    text = text.slice(0, split).replaceAll('CookieStore.', 'CookieStore.forSource(this.source.bookSourceUrl).') +
      text.slice(split).replaceAll('CookieStore.', 'CookieStore.forSource(source.bookSourceUrl).');
  }
  if (name === 'core/rule/JsRuntime.ts') {
    text = text.replaceAll('CookieStore.', "CookieStore.forSource(this.getVar('source.bookSourceUrl') || this.getVar('bookSourceUrl')).");
  }
  if (name === 'core/rule/AnalyzeRule.ts') {
    text = text.replace('this.js = new JsRuntime();', "this.js = new JsRuntime();\n    this.js.setVar('source.bookSourceUrl', this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl'));");
    text = text.replace('setContext(ctx: RuleContext): AnalyzeRule { this.ctx = ctx; return this; }',
      "setContext(ctx: RuleContext): AnalyzeRule { this.ctx = ctx; this.js.setVar('source.bookSourceUrl',ctx.get('source.bookSourceUrl') || ctx.get('bookSourceUrl')); return this; }");
  }
  if (name === 'core/book/WebBookFetchRuntime.ts') {
    text = text.replace('export interface WebBookFetchRequest {', 'export interface WebBookFetchRequest {\n  cookieSource?: string;');
    text = text.replaceAll('CookieStore.', 'CookieStore.forSource(task.request.cookieSource).');
  }
  if (name === 'core/book/BookSourceStageWebRuntime.ts') {
    text = text.replace('private activeTask: StageWebRuntimeTask | null = null;',
      'private activeTask: StageWebRuntimeTask | null = null;\n  private workers = new Map<StageWebRuntimeTask, BookSourceStageWebRuntime>();');
    text = text.replace('this.tasks.length >= BookSourceStageWebRuntime.MAX_QUEUED_TASKS', 'this.workers.size >= BookSourceStageWebRuntime.MAX_QUEUED_TASKS');
    text = text.replace('      this.tasks.push(task);\n      this.queuedBytes += estimatedBytes;\n      this.startNext();',
      `      const worker = new BookSourceStageWebRuntime();
      worker.cancelledOwners = this.cancelledOwners;
      worker.caches = this.caches;
      worker.cacheTouchedAt = this.cacheTouchedAt;
      worker.activeTask = task;
      this.workers.set(task, worker);
      this.queuedBytes += estimatedBytes;
      worker.executeTask(request).then(resolve, reject).finally(() => {
        this.workers.delete(task);
        this.queuedBytes = Math.max(0, this.queuedBytes - estimatedBytes);
        worker.activeTask = null;
        worker.activeHttpClient = null;
      });`);
    text = text.replace('    this.cancelledOwners.add(ownerId);', '    this.cancelledOwners.add(ownerId);\n    for (const worker of this.workers.values()) worker.cancelOwner(ownerId);');
    text = text.replace("    runtime['java'] = this.parseObjectState(javaStateRaw);", "    if (!existingRuntime && Object.keys(this.parseObjectState(javaStateRaw)).length === 0 && Object.keys(this.parseObjectState(sourceStateRaw)).length === 0) return raw;\n    runtime['java'] = this.parseObjectState(javaStateRaw);");
    text = text.replace('this.storeCache(sourceKey, nextCacheState)', 'this.storeCache(sourceKey, nextCacheState, cacheState)');
    text = text.replace('private storeCache(sourceKey: string, rawState: Record<string, string>): Record<string, string> {', `private storeCache(sourceKey: string, rawState: Record<string, string>, before: Record<string, string>): Record<string, string> {
    const merged = {...(this.caches[sourceKey] || {})};
    for (const key of new Set([...Object.keys(before), ...Object.keys(rawState)])) {
      if (before[key] === rawState[key]) continue;
      if (Object.prototype.hasOwnProperty.call(rawState,key)) merged[key] = rawState[key];
      else delete merged[key];
    }
    rawState = merged;`);
    text = text.replaceAll('AppDatabase.getInstance()', 'AppDatabase.getInstance(request.source)');
    text = text.replace('private async runJavaScript(script: string)', 'private async runJavaScript(script: string, sourceUrl: string)')
      .replace('LightSourceRuntime.evaluate(script)', 'LightSourceRuntime.evaluate(script, sourceUrl)')
      .replace('this.runJavaScript(script)', 'this.runJavaScript(script, request.source.bookSourceUrl)');
    text = text.replace('this.applyCookieOperations(step.cookieOperations, journal)', 'this.applyCookieOperations(step.cookieOperations, journal, request.source.bookSourceUrl)')
      .replace('raw: string, journal: BookSourceExecutionJournal): void', 'raw: string, journal: BookSourceExecutionJournal, sourceUrl: string): void');
    text = text.replace('response.url || \'\', response.headers)', 'response.url || \'\', response.headers, request.source.bookSourceUrl)')
      .replace('responseUrl: string, responseHeaders: Record<string, string>): void', 'responseUrl: string, responseHeaders: Record<string, string>, sourceUrl: string): void');
    text = text.replace('CookieStore.getCookie(step.pendingCookie)', 'CookieStore.forSource(request.source.bookSourceUrl).getCookie(step.pendingCookie)');
    text = text.replaceAll('CookieStore.getCookie(url)', 'CookieStore.forSource(sourceUrl).getCookie(url)');
    for (const method of ['setCookies','replaceCookies','removeCookie','saveAsync']) {
      text = text.replaceAll('CookieStore.' + method + '(', 'CookieStore.forSource(sourceUrl).' + method + '(');
    }
  }
  if (name === 'core/book/WebBookService.ts') {
    addRuntime();
    text = text.replace('const copy = Object.assign(new BookSource(), source);', 'const copy = Object.assign(new BookSource(), source);\n    LightSourceRuntime.bindSource(source,copy);');
    text = text.replaceAll("AppStorage.setOrCreate('bookSourceStageLastError',", 'LightSourceRuntime.setError(source,')
      .replaceAll("AppStorage.get<string>('bookSourceStageLastError')", 'LightSourceRuntime.getError(source)');
    const signature = /^  private async tryResolveAudioWebViewUrl\([\s\S]*?\n  \}/m;
    if (!signature.test(text)) throw Error('Missing audio WebView adapter target');
    text = text.replace(signature, method => method.replace('    const runtime = BookSourceAudioWebRuntime.get();',
      '    return LightSourceRuntime.withWeb(source.bookSourceUrl, async () => {\n    const runtime = BookSourceAudioWebRuntime.get();')
      .replace(/\n  \}$/, '\n    });\n  }'));
  }
  if (name === 'core/book/ComicImagePipeline.ts') {
    text = text.replace('http.executeBinary({', 'http.executeBinary({\n      cookieSource: source.bookSourceUrl,');
  }
  return text;
}
// Prepare and validate every transformation before mutating the working tree.
const generated = [...files].map(([name, original]) => ({ name, original, text: adapt(name, original) }));
// Keep upstream CookieStore semantics reusable, while its persistence/session entry remains local.
const cookieOriginal = files.get('core/http/CookieStore.ts');
let cookieSemantics = cookieOriginal.replace('export class CookieStore', 'export class LightCookieSemantics')
    .replace('fetchCookieSync(target)', 'fetchCookieSync(target, true)')
    .replaceAll('configCookieSync(target, value, false, true)', 'configCookieSync(target, value, true, true)')
    .replaceAll('configCookieSync(target, value)', 'configCookieSync(target, value, true)')
    .replace('clearAllCookiesSync()', 'clearAllCookiesSync(true)')
    .replace('private static withoutExpiredJwtCookies', 'static withoutExpiredJwtCookies');
cookieSemantics = replaceMethod(cookieSemantics, 'static saveAsync\\(',
  '  static saveAsync(): void { /* Encrypted persistence is flushed by the source lease. */ }');
generated.push({name:'core/http/LightCookieSemantics.ts',original:cookieOriginal,text:cookieSemantics});
const page = fs.readFileSync(path.join(sourceRoot, 'pages/BookSource.ets'), 'utf8').replaceAll('\r\n', '\n');
const methods = ['parseBookSource', 'parseCompactRule', 'applyRuleToSearchRule', 'applyRuleToTocRule',
  'applyRuleToContentRule', 'applyRuleToBookInfoRule'].map(name => {
  const match = page.match(new RegExp('^  ' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Source import method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightSourceImport.ts', original: methods.join('\n'), text:
  `import { BookSource, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from './model/data/Book';\n` +
  `export class LightSourceImport {\n${methods.join('\n\n')}\n}\n` });
const nativeService = files.get('core/nativesource/NativeSourceService.ts').replaceAll('\r\n', '\n');
const nativeMethods = ['toBookSource', 'importObject'].map(name => {
  const match = nativeService.match(new RegExp('^  static ' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Native import method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightNativeImport.ts', original: nativeMethods.join('\n'), text:
  `import { BookSource } from './model/data/Book';\n` +
  `import { NativeSourceSpec, NativeSourceDefinition } from './core/nativesource/NativeSourceSpec';\n` +
  `export class NativeSourceService {\n${nativeMethods.join('\n\n')}\n}\n` });
// The upstream audio page performs a second parsing step after the rule engine:
// unwrap JSON/HTML media results and carry the source's scoped stream headers.
// Extract those methods verbatim so adapter behavior follows the pinned player.
const audioPage = fs.readFileSync(path.join(sourceRoot, 'pages/AudioBook.ets'), 'utf8').replaceAll('\r\n', '\n');
const audioMethods = ['resolveAudioUrl', 'audioUrlFromObject', 'invalidAudioAddressMessage',
  'decodeAudioRuleValue', 'normalizeAudioCandidate', 'audioHeaders', 'sourceAudioHeaders'].map(name => {
  const match = audioPage.match(new RegExp('^  (?:private )?' + name + '\\([\\s\\S]*?\\n  \\}', 'm'));
  if (!match) throw new Error(`Source audio method changed: ${name}`);
  return match[0];
});
generated.push({ name: 'LightAudioSupport.ts', original: audioMethods.join('\n'), text:
  `import { BookSource } from './model/data/Book';\n` +
  `import { AudioRuleSupport } from './core/book/AudioRuleSupport';\n` +
  `import { BookUrlResolver } from './core/book/BookUrlResolver';\n` +
  `import { VerificationSupport } from './core/http/VerificationSupport';\n` +
  `export class LightAudioSupport {\n${audioMethods.join('\n\n')}\n}\n` });
const commit = cp.execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const status = cp.execFileSync('git', ['-C', source, 'status', '--porcelain', '--', 'entry/src/main/ets', 'LICENSE'], { encoding: 'utf8' }).trim();
if (status) throw new Error('The upstream source working tree must be clean.');
for (const entry of previous?.files || []) {
  if (!generated.some(value => value.name === entry.path)) fs.unlinkSync(path.join(target, entry.path));
}
for (const entry of generated) {
  const filename = path.join(target, entry.name);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, entry.text);
}
const licenseDir = path.dirname(manifestPath);
fs.mkdirSync(licenseDir, { recursive: true });
fs.copyFileSync(path.join(source, 'LICENSE'), path.join(licenseDir, 'LICENSE'));
const packagedLicense = path.join(project, 'entry/src/main/resources/rawfile/third_party/light-source/LICENSE');
fs.mkdirSync(path.dirname(packagedLicense), {recursive:true});
fs.copyFileSync(path.join(source, 'LICENSE'), packagedLicense);
fs.writeFileSync(manifestPath, JSON.stringify({ repository: 'https://github.com/wip3l/legado-harmony',
  fork: 'https://github.com/hos-book/legado-harmony', commit, license: 'GPL-3.0',
  files: generated.map(entry => ({ path: entry.name, upstreamSha256: hash(entry.original), sha256: hash(entry.text) }))
}, null, 2) + '\n');
console.log(`Imported ${generated.length} source-engine files at ${commit}. No pages copied.`);
