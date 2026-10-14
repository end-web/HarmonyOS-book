import { EncodedSourceUrl } from '../book/EncodedSourceUrl';
import { RuleContext } from './RuleContext';
import { JsRuntime } from './JsRuntime';
import { ScriptCompatibility } from './ScriptCompatibility';

export class ScriptEvalResult {
  handled: boolean = false;
  value: string = '';
}

export class ScriptEngineContext {
  content: string = '';
  baseUrl: string = '';
  ctx: RuleContext = new RuleContext();
  requestedUrl: string = '';
  toastMessage: string = '';

  getVar(key: string): string {
    return this.ctx.get(key);
  }

  putVar(key: string, value: string): void {
    this.ctx.put(key, value);
  }

  getSourceKey(): string {
    return this.ctx.get('source.bookSourceUrl') || this.ctx.get('bookSourceUrl');
  }

  getSourceValue(key: string): string {
    return this.ctx.get(`source.${key}`) || this.ctx.get(key);
  }

  getSourceVariable(key?: string): string {
    if (key) return this.ctx.get(`source.variable.${key}`) || this.ctx.get(key);
    return this.ctx.get('source.variable');
  }

  setSourceVariable(value: string, key?: string): void {
    if (key) this.ctx.put(`source.variable.${key}`, value);
    else this.ctx.put('source.variable', value);
  }

  getCache(key: string): string {
    return this.ctx.get(`cache.${key}`) || this.ctx.get(key);
  }

  putCache(key: string, value: string): void {
    this.ctx.put(`cache.${key}`, value);
    this.ctx.put(key, value);
  }

  getJsLib(): string {
    const parts: string[] = [];
    const jsLib = this.ctx.get('source.jsLib') || this.ctx.get('jsLib');
    const comment = this.ctx.get('source.bookSourceComment') || this.ctx.get('bookSourceComment');
    if (jsLib) parts.push(jsLib);
    if (comment) parts.push(comment);
    return parts.join('\n');
  }
}

export interface ScriptEngineBackend {
  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult;
  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult;
}

class ScriptFunction {
  params: string[] = [];
  body: string = '';
}

class ScriptReturnSignal {
  value: Object = '';
}

class ArkTsJsEngineBackend implements ScriptEngineBackend {
  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult {
    return new ArkTsJsRunner(env).run(code, env.content);
  }

  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult {
    return new ArkTsJsRunner(env).run(code, value);
  }
}

class ArkTsJsRunner {
  private env: ScriptEngineContext;
  private js: JsRuntime = new JsRuntime();
  private vars: Record<string, Object> = {};
  private functions: Record<string, ScriptFunction> = {};
  private operationCount: number = 0;

  constructor(env: ScriptEngineContext) {
    this.env = env;
  }

  run(code: string, resultValue: string): ScriptEvalResult {
    const out = new ScriptEvalResult();
    const script = ScriptCompatibility.normalize((code || '').trim());
    if (!script || script.length > 512 * 1024 || this.requiresHostFallback(script)) return out;
    this.vars['result'] = resultValue;
    this.vars['baseUrl'] = this.env.baseUrl;
    this.vars['location'] = { href: this.env.baseUrl };
    this.seedContextObjects();
    try {
      const body = this.collectFunctions(this.stripLineComments(script));
      let last: Object = '';
      const statements = this.splitStatements(body);
      for (const statement of statements) {
        const value = this.evalStatement(statement);
        if (value instanceof ScriptReturnSignal) {
          last = value.value;
          break;
        }
        if (value !== undefined && value !== null) last = value;
      }
      out.handled = true;
      const value = this.toString(last);
      out.value = value.length <= 2 * 1024 * 1024 ? value : '';
      return out;
    } catch (_) {
      return out;
    }
  }

  private requiresHostFallback(code: string): boolean {
    // Apply the same allow-listed normalization to the library and the active rule. Otherwise a
    // harmless compatibility probe removed from `code` can still force fallback through raw jsLib.
    const jsLib = ScriptCompatibility.normalize(this.env.getJsLib());
    return /\bjava\.(?:ajax|ajaxAll|post|connect)|\b(?:JavaImporter|Packages|Cipher|SecretKeySpec|IvParameterSpec|MessageDigest)\b/.test(code) ||
      /\b(?:JavaImporter|Packages|Cipher|SecretKeySpec|IvParameterSpec|MessageDigest|android\.util\.Base64)\b/.test(jsLib);
  }

  private seedContextObjects(): void {
    const values = this.env.ctx.toRecord();
    const source: Record<string, Object> = {};
    const book: Record<string, Object> = {};
    const chapter: Record<string, Object> = {};
    for (const key in values) {
      const value = values[key];
      if (key.startsWith('source.')) source[key.substring(7)] = value;
      if (key.startsWith('book.')) book[key.substring(5)] = value;
      if (key.startsWith('chapter.')) chapter[key.substring(8)] = value;
      if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key) && this.vars[key] === undefined) this.vars[key] = value;
    }
    source['key'] = this.env.getSourceKey();
    this.vars['source'] = source;
    this.vars['book'] = book;
    this.vars['chapter'] = chapter;
  }

  private stripLineComments(code: string): string {
    const text = code || '';
    let result = '';
    let quote = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        result += ch;
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') {
        quote = ch;
        result += ch;
        continue;
      }
      if (ch === '/' && text.charAt(i + 1) === '/') {
        while (i < text.length && text.charAt(i) !== '\n') i++;
        if (i < text.length) result += '\n';
        continue;
      }
      result += ch;
    }
    return result;
  }

  private collectFunctions(code: string): string {
    let text = code || '';
    let index = 0;
    while (index < text.length) {
      const match = /function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(([^)]*)\)\s*\{/.exec(text.substring(index));
      if (!match) break;
      const start = index + match.index;
      const braceStart = text.indexOf('{', start + match[0].length - 1);
      const braceEnd = this.findMatching(text, braceStart, '{', '}');
      if (braceEnd < 0) break;
      const fn = new ScriptFunction();
      fn.params = match[2].split(',').map(item => item.trim()).filter(item => item.length > 0);
      fn.body = text.substring(braceStart + 1, braceEnd);
      this.functions[match[1]] = fn;
      text = text.substring(0, start) + text.substring(braceEnd + 1);
      index = start;
    }
    index = 0;
    while (index < text.length) {
      const match = /(?:var|let|const)?\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*\(([^)]*)\)\s*=>\s*\{/.exec(
        text.substring(index));
      if (!match) break;
      const start = index + match.index;
      const braceStart = text.indexOf('{', start + match[0].length - 1);
      const braceEnd = this.findMatching(text, braceStart, '{', '}');
      if (braceEnd < 0) break;
      const fn = new ScriptFunction();
      fn.params = match[2].split(',').map(item => item.trim()).filter(item => item.length > 0);
      fn.body = text.substring(braceStart + 1, braceEnd);
      this.functions[match[1]] = fn;
      text = text.substring(0, start) + text.substring(braceEnd + 1);
      index = start;
    }
    return text;
  }

  private evalStatement(statement: string): Object | undefined {
    let text = (statement || '').trim();
    if (!text) return undefined;
    this.operationCount++;
    if (this.operationCount > 50000) return undefined;
    if (text.startsWith('return ')) {
      const signal = new ScriptReturnSignal();
      signal.value = this.evalExpression(text.substring(7));
      return signal as Object;
    }

    const forValue = this.evalForStatement(text);
    if (forValue !== undefined) return forValue;

    const ifValue = this.evalIfStatement(text);
    if (ifValue !== undefined) return ifValue;

    const declare = text.match(/^(?:var|let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*([\s\S]+)$/);
    if (declare) {
      const value = this.evalExpression(declare[2]);
      this.vars[declare[1]] = value;
      return value;
    }
    const emptyDeclare = text.match(/^(?:var|let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)$/);
    if (emptyDeclare) {
      this.vars[emptyDeclare[1]] = '';
      return '';
    }

    const compound = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\s*([+\-])=\s*([\s\S]+)$/);
    if (compound) {
      const current = this.vars[compound[1]] || '';
      const next = this.evalExpression(compound[3]);
      const numeric = /^-?\d+(?:\.\d+)?$/.test(this.toString(current)) &&
        /^-?\d+(?:\.\d+)?$/.test(this.toString(next));
      const value = compound[2] === '+' ?
        (numeric ? Number(this.toString(current)) + Number(this.toString(next)) : this.toString(current) + this.toString(next)) :
        Number(this.toString(current)) - Number(this.toString(next));
      this.vars[compound[1]] = value;
      return value;
    }

    const increment = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)(\+\+|--)$/);
    if (increment) {
      const value = Number(this.toString(this.vars[increment[1]])) + (increment[2] === '++' ? 1 : -1);
      this.vars[increment[1]] = value;
      return value;
    }

    const memberAssign = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:\[\s*([\s\S]+?)\s*\]|\.\s*([A-Za-z_$][A-Za-z0-9_$]*))\s*=\s*([\s\S]+)$/);
    if (memberAssign) {
      const target = this.vars[memberAssign[1]];
      const key = memberAssign[3] || this.toString(this.evalExpression(memberAssign[2]));
      const value = this.evalExpression(memberAssign[4]);
      if (Array.isArray(target) && /^\d+$/.test(key)) {
        const index = Number(key);
        if (index < 10000) (target as Object[])[index] = value;
      } else if (target && typeof target === 'object') {
        (target as Record<string, Object>)[key] = value;
      }
      return value;
    }

    const assign = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*([\s\S]+)$/);
    if (assign) {
      const value = this.evalExpression(assign[2]);
      this.vars[assign[1]] = value;
      return value;
    }

    return this.evalExpression(text);
  }

  private evalForStatement(text: string): Object | undefined {
    if (!text.startsWith('for')) return undefined;
    const open = text.indexOf('(');
    const close = open >= 0 ? this.findMatching(text, open, '(', ')') : -1;
    if (open < 0 || close < 0) return undefined;
    const header = this.splitByTopLevel(text.substring(open + 1, close), [';']);
    if (header.length !== 3) return undefined;
    let body = text.substring(close + 1).trim();
    if (!body.startsWith('{')) return undefined;
    const bodyEnd = this.findMatching(body, 0, '{', '}');
    if (bodyEnd < 0) return undefined;
    body = body.substring(1, bodyEnd);
    this.evalStatement(header[0]);
    let last: Object = '';
    let iterations = 0;
    while (this.truthy(this.evalExpression(header[1])) && iterations < 10000 && this.operationCount < 50000) {
      last = this.evalStatements(body);
      if (last instanceof ScriptReturnSignal) return last;
      this.evalForUpdate(header[2]);
      iterations++;
    }
    return last;
  }

  private evalForUpdate(raw: string): void {
    const text = (raw || '').trim();
    const increment = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)(\+\+|--)$/);
    if (increment) {
      const current = Number(this.toString(this.vars[increment[1]]));
      this.vars[increment[1]] = current + (increment[2] === '++' ? 1 : -1);
      return;
    }
    const compound = text.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\s*([+\-])=\s*([\s\S]+)$/);
    if (compound) {
      const current = Number(this.toString(this.vars[compound[1]]));
      const delta = Number(this.toString(this.evalExpression(compound[3])));
      this.vars[compound[1]] = compound[2] === '+' ? current + delta : current - delta;
      return;
    }
    this.evalStatement(text);
  }

  private evalIfStatement(text: string): Object | undefined {
    if (!text.startsWith('if')) return undefined;
    const open = text.indexOf('(');
    const close = open >= 0 ? this.findMatching(text, open, '(', ')') : -1;
    if (open < 0 || close < 0) return undefined;
    const condition = this.truthy(this.evalExpression(text.substring(open + 1, close)));
    let rest = text.substring(close + 1).trim();
    let thenPart = '';
    let elsePart = '';
    if (rest.startsWith('{')) {
      const end = this.findMatching(rest, 0, '{', '}');
      if (end < 0) return undefined;
      thenPart = rest.substring(1, end);
      rest = rest.substring(end + 1).trim();
    } else {
      const elseIndex = this.indexOfTopLevelWord(rest, 'else');
      thenPart = elseIndex >= 0 ? rest.substring(0, elseIndex).trim() : rest;
      rest = elseIndex >= 0 ? rest.substring(elseIndex).trim() : '';
    }
    if (rest.startsWith('else')) {
      elsePart = rest.substring(4).trim();
      if (elsePart.startsWith('{')) {
        const end = this.findMatching(elsePart, 0, '{', '}');
        elsePart = end >= 0 ? elsePart.substring(1, end) : '';
      }
    }
    return this.evalStatements(condition ? thenPart : elsePart);
  }

  private evalStatements(code: string): Object {
    let last: Object = '';
    const statements = this.splitStatements(code || '');
    for (const statement of statements) {
      const value = this.evalStatement(statement);
      if (value instanceof ScriptReturnSignal) return value;
      if (value !== undefined && value !== null) last = value;
    }
    return last;
  }

  private evalExpression(expr: string): Object {
    let text = (expr || '').trim().replace(/;\s*$/, '');
    if (!text) return '';
    if (text.startsWith('return ')) text = text.substring(7).trim();
    text = this.unwrapParens(text);

    const orIndex = this.indexOfTopLevelOperator(text, '||');
    if (orIndex >= 0) {
      const left = this.evalExpression(text.substring(0, orIndex));
      return this.truthy(left) ? left : this.evalExpression(text.substring(orIndex + 2));
    }
    const andIndex = this.indexOfTopLevelOperator(text, '&&');
    if (andIndex >= 0) {
      const left = this.evalExpression(text.substring(0, andIndex));
      return this.truthy(left) ? this.evalExpression(text.substring(andIndex + 2)) : left;
    }
    if (text.startsWith('!') && !text.startsWith('!=')) {
      return !this.truthy(this.evalExpression(text.substring(1)));
    }

    const question = this.indexOfTopLevel(text, '?');
    if (question >= 0) {
      const colon = this.indexOfTopLevelFrom(text, ':', question + 1);
      if (colon > question) {
        return this.truthy(this.evalExpression(text.substring(0, question))) ?
          this.evalExpression(text.substring(question + 1, colon)) :
          this.evalExpression(text.substring(colon + 1));
      }
    }

    const direct = this.evalLiteralOrVariable(text);
    if (direct !== undefined) return direct;

    const compare = this.findComparison(text);
    if (compare.index >= 0) {
      const left = this.evalExpression(text.substring(0, compare.index));
      const right = this.evalExpression(text.substring(compare.index + compare.op.length));
      return this.compareValues(left, right, compare.op);
    }

    const plus = this.splitTopLevel(text, '+');
    if (plus.length > 1) {
      const values = plus.map(part => this.evalExpression(part));
      const numeric = values.every(item => typeof item === 'number' || /^-?\d+(?:\.\d+)?$/.test(this.toString(item)));
      if (numeric) return values.reduce((sum: number, item: Object) => sum + Number(this.toString(item)), 0);
      return values.map(item => this.toString(item)).join('');
    }

    const minus = this.splitTopLevel(text, '-');
    if (minus.length > 1) {
      let value = Number(this.toString(this.evalExpression(minus[0])));
      for (let i = 1; i < minus.length; i++) value -= Number(this.toString(this.evalExpression(minus[i])));
      return Number.isNaN(value) ? '' : value;
    }

    const multiply = this.splitTopLevel(text, '*');
    if (multiply.length > 1) {
      let value = Number(this.toString(this.evalExpression(multiply[0])));
      for (let i = 1; i < multiply.length; i++) value *= Number(this.toString(this.evalExpression(multiply[i])));
      return Number.isNaN(value) ? '' : value;
    }

    const divide = this.splitTopLevel(text, '/');
    if (divide.length > 1) {
      let value = Number(this.toString(this.evalExpression(divide[0])));
      for (let i = 1; i < divide.length; i++) {
        const divisor = Number(this.toString(this.evalExpression(divide[i])));
        if (divisor === 0 || Number.isNaN(divisor)) return 0;
        value /= divisor;
      }
      return Number.isNaN(value) ? '' : value;
    }

    const moduloIndex = this.indexOfTopLevelOperator(text, '%');
    if (moduloIndex >= 0) {
      const left = Number(this.toString(this.evalExpression(text.substring(0, moduloIndex))));
      const right = Number(this.toString(this.evalExpression(text.substring(moduloIndex + 1))));
      return right === 0 || Number.isNaN(left) || Number.isNaN(right) ? 0 : left % right;
    }

    const callValue = this.evalFunctionOrHostCall(text);
    if (callValue !== undefined) return callValue;

    return this.evalChain(text);
  }

  private evalLiteralOrVariable(text: string): Object | undefined {
    if (((text.startsWith('"') && text.endsWith('"')) || (text.startsWith("'") && text.endsWith("'"))) &&
      this.splitTopLevel(text, '+').length === 1) {
      return this.unescapeString(text.substring(1, text.length - 1));
    }
    if (text.startsWith('`') && text.endsWith('`')) return this.evalTemplateLiteral(text.substring(1, text.length - 1));
    if (text === 'true') return true;
    if (text === 'false') return false;
    if (text === 'undefined') return '';
    if (text === 'null') return null as Object;
    if (text === 'Date.now()') return Date.now();
    if (text.startsWith('[') && text.endsWith(']')) {
      const inner = text.substring(1, text.length - 1).trim();
      if (!inner) return [] as Object;
      return this.splitArgs(inner).map(item => this.evalExpression(item)) as Object;
    }
    if (text.startsWith('{') && text.endsWith('}')) {
      const record: Record<string, Object> = {};
      const inner = text.substring(1, text.length - 1).trim();
      if (!inner) return record as Object;
      for (const item of this.splitArgs(inner)) {
        const colon = this.indexOfTopLevel(item, ':');
        if (colon <= 0) continue;
        let key = item.substring(0, colon).trim();
        if ((key.startsWith('"') && key.endsWith('"')) || (key.startsWith("'") && key.endsWith("'"))) {
          key = this.unescapeString(key.substring(1, key.length - 1));
        }
        if (!key) continue;
        record[key] = this.evalExpression(item.substring(colon + 1));
      }
      return record as Object;
    }
    if (/^\/[\s\S]+\/[gimsuy]*$/.test(text)) return text;
    if (/^-?\d+(?:\.\d+)?$/.test(text)) return Number(text);
    if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(text) && this.vars[text] !== undefined) return this.vars[text];
    return undefined;
  }

  private evalFunctionOrHostCall(text: string): Object | undefined {
    const call = text.match(/^([A-Za-z_$][A-Za-z0-9_$.]*)\s*\(([\s\S]*)\)$/);
    if (!call) return undefined;
    const name = call[1];
    const args = this.splitArgs(call[2]).map(arg => this.evalExpression(arg));
    if (name === 'JSON.parse') {
      try { return JSON.parse(this.toString(args[0])); } catch (_) { return {}; }
    }
    if (name === 'JSON.stringify') return JSON.stringify(args[0]);
    if (name === 'String') return this.toString(args[0]);
    if (name === 'Number') return Number(this.toString(args[0]));
    if (name === 'parseInt') return parseInt(this.toString(args[0]));
    if (name === 'parseFloat') return parseFloat(this.toString(args[0]));
    if (name === 'isNaN') return Number.isNaN(Number(this.toString(args[0])));
    if (name === 'Date.now') return Date.now();
    if (name === 'Math.abs') return Math.abs(Number(this.toString(args[0])));
    if (name === 'Math.floor') return Math.floor(Number(this.toString(args[0])));
    if (name === 'Math.ceil') return Math.ceil(Number(this.toString(args[0])));
    if (name === 'Math.round') return Math.round(Number(this.toString(args[0])));
    if (name === 'Math.max') return Math.max(...args.map(item => Number(this.toString(item))));
    if (name === 'Math.min') return Math.min(...args.map(item => Number(this.toString(item))));
    if (name === 'Math.pow') return Math.pow(Number(this.toString(args[0])), Number(this.toString(args[1])));
    if (name === 'encodeURIComponent') return encodeURIComponent(this.toString(args[0]));
    if (name === 'encodeURI') return encodeURI(this.toString(args[0]));
    if (name === 'decodeURIComponent') {
      try { return decodeURIComponent(this.toString(args[0])); } catch (_) { return this.toString(args[0]); }
    }
    if (name === 'decodeURI') {
      try { return decodeURI(this.toString(args[0])); } catch (_) { return this.toString(args[0]); }
    }
    if (name === 'StringBuilder') {
      return { __compatType: 'StringBuilder', value: this.toString(args[0]) } as Object;
    }
    if (name === 'HashMap') return {} as Object;
    if (name === 'ArrayList' || name === 'Array') return [] as Object;
    if (name === 'isEmpty') {
      const value = args[0];
      return value === undefined || value === null || this.toString(value).length === 0;
    }
    if (name === 'source.getKey') return this.env.getSourceKey();
    if (name === 'source.getVariable') return this.env.getSourceVariable(args.length > 0 ? this.toString(args[0]) : undefined);
    if (name === 'source.setVariable') {
      if (args.length >= 2) this.env.setSourceVariable(this.toString(args[1]), this.toString(args[0]));
      else this.env.setSourceVariable(this.toString(args[0]));
      return args.length >= 2 ? this.toString(args[1]) : this.toString(args[0]);
    }
    if (name === 'cache.get' || name === 'cache.getFromMemory') return this.env.getCache(this.toString(args[0]));
    if (name === 'cache.put' || name === 'cache.putMemory') {
      this.env.putCache(this.toString(args[0]), this.toString(args[1]));
      return this.toString(args[1]);
    }
    if (name === 'java.put') {
      this.env.putVar(this.toString(args[0]), this.toString(args[1]));
      return this.toString(args[1]);
    }
    if (name === 'java.get') return this.env.getVar(this.toString(args[0]));
    if (name === 'java.startBrowser' || name === 'java.startBrowserAwait') {
      this.env.requestedUrl = this.toString(args[0]);
      return this.env.requestedUrl;
    }
    if (name === 'java.toast' || name === 'java.longToast') {
      this.env.toastMessage = this.toString(args[0]);
      return this.env.toastMessage;
    }
    if (name === 'java.getStringList') {
      return this.js.getStringList(this.toString(args[0]), this.env.content) as Object;
    }
    if (this.isJavaRuntimeCall(name)) return this.evalJavaRuntimeCall(name, args);
    if (name === 'cookie.getCookie' || name === 'cookie.getKey' || name === 'cookie.setCookie' ||
      name === 'cookie.removeCookie') {
      return this.evalJavaRuntimeCall(name, args);
    }
    if (this.functions[name]) return this.callUserFunction(name, args);
    return undefined;
  }

  private isJavaRuntimeCall(name: string): boolean {
    return [
      'java.base64Encode', 'java.base64EncodeToString', 'java.base64Decode', 'java.base64DecodeToString',
      'java.base64UrlEncode', 'java.base64UrlDecode',
      'java.hexDecodeToString', 'java.hexEncodeToString', 'java.md5Encode16',
      'java.md5Encode32', 'java.md5Encode', 'java.sha1Encode', 'java.sha256Encode', 'java.sha512Encode',
      'java.urlEncode', 'java.urlDecode', 'java.encodeURI', 'java.htmlEncode', 'java.htmlDecode',
      'java.getCookie', 'java.timeFormat', 'java.timeFormatUTC',
      'java.getString', 'java.getElement', 'java.t2s', 'java.androidId',
      'java.randomUUID', 'java.aesBase64DecodeToString', 'java.aesEncodeToBase64String',
      'java.desBase64DecodeToString', 'java.desEncodeToBase64String'
    ].includes(name);
  }

  private evalJavaRuntimeCall(name: string, args: Object[]): string {
    const normalizedName = name === 'cookie.getKey' ? 'java.getCookie' :
      name === 'cookie.getCookie' ? 'java.getCookie' : name;
    const expression = `${normalizedName}(${args.map(item => this.quoteString(this.toString(item))).join(',')})`;
    this.js.setJsonContext(this.env.content);
    return this.js.evaluate(expression, this.env.content);
  }

  private callUserFunction(name: string, args: Object[]): Object {
    const fn = this.functions[name];
    const snapshot: Record<string, Object> = {};
    for (const key in this.vars) snapshot[key] = this.vars[key];
    for (let i = 0; i < fn.params.length; i++) this.vars[fn.params[i]] = args[i] || '';
    const value = this.evalStatements(fn.body);
    this.vars = snapshot;
    if (value instanceof ScriptReturnSignal) return value.value;
    return value;
  }

  private evalChain(expr: string): Object {
    const callBase = expr.match(/^([A-Za-z_$][A-Za-z0-9_$.]*)\s*\(/);
    let current: Object = '';
    let index = -1;
    if (callBase && this.isCallableChainBase(callBase[1])) {
      const open = expr.indexOf('(', callBase[1].length);
      const end = this.findMatching(expr, open, '(', ')');
      if (end < 0) return '';
      const baseValue = this.evalFunctionOrHostCall(expr.substring(0, end + 1));
      if (baseValue === undefined) return '';
      current = baseValue;
      index = end + 1;
    } else {
      const firstEnd = this.firstChainBreak(expr);
      if (firstEnd <= 0) return '';
      current = this.evalExpression(expr.substring(0, firstEnd));
      index = firstEnd;
    }
    while (index < expr.length) {
      const ch = expr.charAt(index);
      if (/\s/.test(ch)) {
        index++;
        continue;
      }
      if (ch === '.') {
        const next = this.readIdentifier(expr, index + 1);
        if (!next.name) return '';
        index = next.end;
        if (expr.charAt(index) === '(') {
          const end = this.findMatching(expr, index, '(', ')');
          if (end < 0) return '';
          const rawArgs = this.splitArgs(expr.substring(index + 1, end));
          const args = (next.name === 'map' || next.name === 'filter') ?
            rawArgs as Object[] : rawArgs.map(arg => this.evalExpression(arg));
          current = this.applyMethod(current, next.name, args);
          index = end + 1;
        } else {
          current = this.readProperty(current, next.name);
        }
      } else if (ch === '[') {
        const end = this.findMatching(expr, index, '[', ']');
        if (end < 0) return '';
        current = this.readProperty(current, this.toString(this.evalExpression(expr.substring(index + 1, end))));
        index = end + 1;
      } else {
        return '';
      }
    }
    return current;
  }

  private isCallableChainBase(name: string): boolean {
    return !name.includes('.') || name === 'JSON.parse' || name === 'JSON.stringify' ||
      name.startsWith('source.') || name.startsWith('cache.') ||
      name.startsWith('java.') || name.startsWith('cookie.');
  }

  private applyMethod(target: Object, name: string, args: Object[]): Object {
    if (this.isStringBuilder(target)) {
      const builder = target as Record<string, Object>;
      if (name === 'append') {
        builder['value'] = this.toString(builder['value']) + this.toString(args[0]);
        return builder as Object;
      }
      if (name === 'insert') {
        const value = this.toString(builder['value']);
        const index = Math.max(0, Math.min(value.length, Number(this.toString(args[0]))));
        builder['value'] = value.substring(0, index) + this.toString(args[1]) + value.substring(index);
        return builder as Object;
      }
      if (name === 'reverse') {
        builder['value'] = this.toString(builder['value']).split('').reverse().join('');
        return builder as Object;
      }
      if (name === 'toString') return this.toString(builder['value']);
      if (name === 'length') return this.toString(builder['value']).length;
    }
    const text = this.toString(target);
    if (name === 'replace') {
      const pattern = this.asRegExp(args[0]);
      return pattern ? text.replace(pattern, this.toString(args[1])) : text.split(this.toString(args[0])).join(this.toString(args[1]));
    }
    if (name === 'match') {
      const pattern = this.asRegExp(args[0]);
      const match = pattern ? text.match(pattern) : null;
      return match ? Array.from(match) as Object : [];
    }
    if (name === 'replaceAll') {
      try { return text.replace(new RegExp(this.toString(args[0]), 'g'), this.toString(args[1])); } catch (_) { return text; }
    }
    if (name === 'replaceFirst') {
      try { return text.replace(new RegExp(this.toString(args[0])), this.toString(args[1])); } catch (_) { return text; }
    }
    if (name === 'substring') return text.substring(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    if (name === 'substr') return text.substr(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    if (name === 'slice') {
      if (Array.isArray(target)) return (target as Object[]).slice(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined) as Object;
      return text.slice(Number(this.toString(args[0])), args.length > 1 ? Number(this.toString(args[1])) : undefined);
    }
    if (name === 'split') return text.split(this.toString(args[0])) as Object;
    if (name === 'join' && Array.isArray(target)) return (target as Object[]).map(item => this.toString(item)).join(this.toString(args[0]));
    if (name === 'trim') return text.trim();
    if (name === 'concat') return text + args.map(item => this.toString(item)).join('');
    if (name === 'toString') return text;
    if (name === 'getBytes' || name === 'toByteArray') return text;
    if (name === 'toCharArray') return text.split('') as Object;
    if (name === 'toLowerCase') return text.toLowerCase();
    if (name === 'toUpperCase') return text.toUpperCase();
    if (name === 'startsWith') return text.startsWith(this.toString(args[0]));
    if (name === 'endsWith') return text.endsWith(this.toString(args[0]));
    if (name === 'contains' || name === 'includes') {
      if (Array.isArray(target)) return (target as Object[]).some(item => this.toString(item) === this.toString(args[0]));
      return text.includes(this.toString(args[0]));
    }
    if (name === 'indexOf') return text.indexOf(this.toString(args[0]), args.length > 1 ? Number(this.toString(args[1])) : 0);
    if (name === 'lastIndexOf') return text.lastIndexOf(this.toString(args[0]));
    if (name === 'charAt') return text.charAt(Number(this.toString(args[0])));
    if (name === 'equals') return text === this.toString(args[0]);
    if (name === 'equalsIgnoreCase') return text.toLowerCase() === this.toString(args[0]).toLowerCase();
    if (name === 'isEmpty') return Array.isArray(target) ? (target as Object[]).length === 0 : text.length === 0;
    if (name === 'size' && Array.isArray(target)) return (target as Object[]).length;
    if (name === 'get' && Array.isArray(target)) return (target as Object[])[Number(this.toString(args[0]))] || '';
    if (name === 'set' && Array.isArray(target)) {
      const values = target as Object[];
      const index = Number(this.toString(args[0]));
      if (index >= 0 && index < 10000) values[index] = args[1];
      return args[1];
    }
    if (name === 'add' && Array.isArray(target)) {
      const values = target as Object[];
      if (values.length >= 10000) return false;
      if (args.length > 1) values.splice(Number(this.toString(args[0])), 0, args[1]);
      else values.push(args[0]);
      return true;
    }
    if (name === 'remove' && Array.isArray(target)) {
      const values = target as Object[];
      const index = Number(this.toString(args[0]));
      if (!Number.isNaN(index) && index >= 0 && index < values.length) return values.splice(index, 1)[0];
      const found = values.findIndex(item => this.toString(item) === this.toString(args[0]));
      return found >= 0 ? values.splice(found, 1)[0] : '';
    }
    if (name === 'put' && target && typeof target === 'object' && !Array.isArray(target)) {
      const record = target as Record<string, Object>;
      const key = this.toString(args[0]);
      const previous = record[key] || '';
      record[key] = args[1];
      return previous;
    }
    if (name === 'get' && target && typeof target === 'object' && !Array.isArray(target)) {
      const record = target as Record<string, Object>;
      return record[this.toString(args[0])] || '';
    }
    if (name === 'containsKey' && target && typeof target === 'object' && !Array.isArray(target)) {
      return this.toString(args[0]) in (target as Record<string, Object>);
    }
    if (name === 'keySet' && target && typeof target === 'object' && !Array.isArray(target)) {
      return Object.keys(target as Record<string, Object>) as Object;
    }
    if (name === 'values' && target && typeof target === 'object' && !Array.isArray(target)) {
      return Object.values(target as Record<string, Object>) as Object;
    }
    if (name === 'map' && Array.isArray(target)) return this.applyArrowMap(target as Object[], this.toString(args[0]));
    if (name === 'filter' && Array.isArray(target)) return this.applyArrowFilter(target as Object[], this.toString(args[0]));
    if (name === 'push' && Array.isArray(target)) {
      const values = target as Object[];
      if (values.length + args.length > 10000) return values.length;
      values.push(...args);
      return values.length;
    }
    return '';
  }

  private isStringBuilder(value: Object): boolean {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    return this.toString((value as Record<string, Object>)['__compatType']) === 'StringBuilder';
  }

  private applyArrowMap(items: Object[], rawArrow: string): Object {
    const arrow = rawArrow.match(/^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*=>\s*([\s\S]+)$/);
    if (!arrow) return items;
    const out: Object[] = [];
    for (const item of items) {
      this.vars[arrow[1]] = item;
      out.push(this.evalExpression(arrow[2]));
    }
    return out as Object;
  }

  private applyArrowFilter(items: Object[], rawArrow: string): Object {
    const arrow = rawArrow.match(/^\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*=>\s*([\s\S]+)$/);
    if (!arrow) return items;
    const out: Object[] = [];
    for (const item of items) {
      this.vars[arrow[1]] = item;
      if (this.truthy(this.evalExpression(arrow[2]))) out.push(item);
    }
    return out as Object;
  }

  private readProperty(target: Object, key: string): Object {
    if (key === 'length') {
      if (Array.isArray(target)) return (target as Object[]).length;
      return this.toString(target).length;
    }
    if (Array.isArray(target) && /^-?\d+$/.test(key)) return (target as Object[])[Number(key)] || '';
    if (target && typeof target === 'object') {
      const record = target as Record<string, Object>;
      return record[key] !== undefined && record[key] !== null ? record[key] : '';
    }
    return '';
  }

  private asRegExp(value: Object): RegExp | null {
    const text = this.toString(value);
    const match = text.match(/^\/([\s\S]*)\/([gimsuy]*)$/);
    if (!match) return null;
    try { return new RegExp(match[1].replace(/\\\//g, '/'), match[2]); } catch (_) { return null; }
  }

  private splitStatements(code: string): string[] {
    return this.splitByTopLevel(code || '', [';', '\n']);
  }

  private splitArgs(args: string): string[] {
    return this.splitByTopLevel(args || '', [',']);
  }

  private splitTopLevel(text: string, separator: string): string[] {
    return this.splitByTopLevel(text, [separator]);
  }

  private splitByTopLevel(text: string, separators: string[]): string[] {
    const parts: string[] = [];
    let quote = '';
    let depth = 0;
    let start = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && separators.includes(ch)) {
        if (ch === '\n') {
          let next = i + 1;
          while (next < text.length && (text.charAt(next) === ' ' || text.charAt(next) === '\t' || text.charAt(next) === '\r')) {
            next++;
          }
          if (text.charAt(next) === '.') continue;
        }
        const part = text.substring(start, i).trim();
        if (part) parts.push(part);
        start = i + 1;
      }
    }
    const last = text.substring(start).trim();
    if (last) parts.push(last);
    return parts;
  }

  private indexOfTopLevel(text: string, target: string): number {
    return this.indexOfTopLevelFrom(text, target, 0);
  }

  private indexOfTopLevelFrom(text: string, target: string, from: number): number {
    let quote = '';
    let depth = 0;
    for (let i = from; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && ch === target) return i;
    }
    return -1;
  }

  private indexOfTopLevelWord(text: string, word: string): number {
    const pattern = new RegExp(`\\b${word}\\b`, 'g');
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(text)) !== null) {
      let quote = '';
      let depth = 0;
      for (let i = 0; i < match.index; i++) {
        const ch = text.charAt(i);
        if (quote) {
          if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        } else if (ch === '"' || ch === "'" || ch === '`') quote = ch;
        else if (ch === '(' || ch === '[' || ch === '{') depth++;
        else if (ch === ')' || ch === ']' || ch === '}') depth--;
      }
      if (!quote && depth === 0) return match.index;
    }
    return -1;
  }

  private findMatching(text: string, openIndex: number, open: string, close: string): number {
    let depth = 0;
    let quote = '';
    for (let i = openIndex; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === open) depth++;
      if (ch === close) {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  private unwrapParens(text: string): string {
    let value = text.trim();
    while (value.startsWith('(')) {
      const end = this.findMatching(value, 0, '(', ')');
      if (end !== value.length - 1) break;
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  private findComparison(text: string): { index: number, op: string } {
    const ops = ['===', '!==', '>=', '<=', '==', '!=', '>', '<'];
    for (const op of ops) {
      const index = this.indexOfTopLevelOperator(text, op);
      if (index >= 0) return { index: index, op: op };
    }
    return { index: -1, op: '' };
  }

  private indexOfTopLevelOperator(text: string, op: string): number {
    let quote = '';
    let depth = 0;
    for (let i = 0; i <= text.length - op.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (depth === 0 && text.substring(i, i + op.length) === op) return i;
    }
    return -1;
  }

  private compareValues(left: Object, right: Object, op: string): boolean {
    const ln = Number(this.toString(left));
    const rn = Number(this.toString(right));
    const numeric = !Number.isNaN(ln) && !Number.isNaN(rn) && this.toString(left) !== '' && this.toString(right) !== '';
    const a: Object = numeric ? ln : this.toString(left);
    const b: Object = numeric ? rn : this.toString(right);
    if (op === '===' || op === '==') return a === b;
    if (op === '!==' || op === '!=') return a !== b;
    if (op === '>=') return a >= b;
    if (op === '<=') return a <= b;
    if (op === '>') return a > b;
    if (op === '<') return a < b;
    return false;
  }

  private firstChainBreak(text: string): number {
    let quote = '';
    let depth = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (quote) {
        if (ch === quote && text.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (depth === 0 && (ch === '.' || ch === '[')) return i;
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
    }
    return -1;
  }

  private readIdentifier(text: string, start: number): { name: string, end: number } {
    let end = start;
    while (end < text.length && /[A-Za-z0-9_$]/.test(text.charAt(end))) end++;
    return { name: text.substring(start, end), end: end };
  }

  private evalTemplateLiteral(text: string): string {
    return text.replace(/\$\{([\s\S]*?)\}/g, (_: string, expr: string) => this.toString(this.evalExpression(expr)));
  }

  private unescapeString(text: string): string {
    return (text || '').replace(/\\n/g, '\n').replace(/\\r/g, '\r').replace(/\\t/g, '\t')
      .replace(/\\"/g, '"').replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  }

  private truthy(value: Object): boolean {
    if (value === undefined || value === null) return false;
    if (typeof value === 'boolean') return value;
    const text = this.toString(value);
    return text.length > 0 && text !== 'false' && text !== '0';
  }

  private toString(value: Object): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value as string;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (Array.isArray(value)) return (value as Object[]).map(item => this.toString(item)).join(',');
    if (this.isStringBuilder(value)) return this.toString((value as Record<string, Object>)['value']);
    try { return JSON.stringify(value); } catch (_) { return String(value); }
  }

  private quoteString(value: string): string {
    return `"${(value || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r/g, '\\r').replace(/\n/g, '\\n')}"`;
  }
}

export class ScriptEngine {
  private static defaultBackend?: ScriptEngineBackend = new ArkTsJsEngineBackend();
  private js: JsRuntime;
  private backend?: ScriptEngineBackend;

  static setDefaultBackend(backend?: ScriptEngineBackend): void {
    ScriptEngine.defaultBackend = backend;
  }

  constructor(js: JsRuntime, backend?: ScriptEngineBackend) {
    this.js = js;
    this.backend = backend || ScriptEngine.defaultBackend;
  }

  evalBlock(code: string, env: ScriptEngineContext): ScriptEvalResult {
    if (this.backend) {
      const backendValue = this.backend.evalBlock(code, env);
      if (backendValue.handled) return backendValue;
    }
    const result = new ScriptEvalResult();
    const value = this.evalKnownJsLibBlock(code, env);
    if (value) {
      result.handled = true;
      result.value = value;
    }
    return result;
  }

  evalResultJs(code: string, value: string, env: ScriptEngineContext): ScriptEvalResult {
    if (this.backend) {
      const backendValue = this.backend.evalResultJs(code, value, env);
      if (backendValue.handled) return backendValue;
    }
    const result = new ScriptEvalResult();
    const knownValue = this.evalKnownResultJs(code, value, env);
    if (knownValue !== null) {
      result.handled = true;
      result.value = knownValue;
      return result;
    }
    if (/\bjava\.(?:base64|hex|md5|sha|url|encodeURI|html|aes|des|getCookie|timeFormat|randomUUID|androidId)/.test(code || '')) {
      this.js.setVar('baseUrl', env.baseUrl);
      result.handled = true;
      result.value = this.js.evaluate(code, value);
    }
    return result;
  }

  private evalKnownJsLibBlock(code: string, env: ScriptEngineContext): string {
    const normalized = code || '';
    const vars: Record<string, string> = { result: env.content, baseUrl: env.baseUrl };

    if (normalized.includes('J(result)') || normalized.includes('JSON.parse')) {
      const articleId = this.extractArticleIdFromContent(env.content) || this.extractArticleIdFromUrl(env.baseUrl);
      if (articleId) {
        vars['id'] = articleId;
        vars['aid'] = articleId;
      }
    }

    const cacheGet = normalized.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
    if (cacheGet) {
      const value = env.getCache(cacheGet[1]);
      if (value) {
        vars['aid'] = value;
        vars[cacheGet[1]] = value;
      }
    }

    if (!vars['aid']) {
      const fromUrl = this.extractArticleIdFromUrl(env.baseUrl);
      if (fromUrl) vars['aid'] = fromUrl;
    }

    const cachePut = normalized.match(/cache\.putMemory\(\s*['"]([^'"]+)['"]\s*,\s*String\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\)/);
    if (cachePut) {
      const value = vars[cachePut[2]] || env.getVar(cachePut[2]) || '';
      if (value) {
        env.putCache(cachePut[1], value);
      }
    }
    this.applyHostSideEffects(normalized, vars, env);

    const baseExprIndex = normalized.lastIndexOf('Base()');
    const lastExpr = baseExprIndex >= 0 ? normalized.substring(baseExprIndex) : this.extractLastJsExpression(normalized);
    if (!lastExpr) return '';
    return this.evalKnownJsExpression(lastExpr, vars, env);
  }

  private evalKnownResultJs(code: string, value: string, env: ScriptEngineContext): string | null {
    const trimmed = (code || '').trim();
    if (/^Clean\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    if (/^T\(\s*result\s*\)\s*;?$/.test(trimmed)) return this.cleanJsLibText(value);
    const hostFunction = this.evalHostFunctionCall(trimmed, value, env);
    if (hostFunction !== null) return hostFunction;
    if (trimmed.includes('Base()')) {
      const vars: Record<string, string> = { result: value, baseUrl: env.baseUrl };
      const cacheGet = trimmed.match(/cache\.getFromMemory\(\s*['"]([^'"]+)['"]\s*\)/);
      if (cacheGet) {
        const cached = env.getCache(cacheGet[1]);
        if (cached) {
          vars['aid'] = cached;
          vars[cacheGet[1]] = cached;
        }
      }
      if (!vars['aid']) {
        const fromUrl = this.extractArticleIdFromUrl(env.baseUrl);
        if (fromUrl) vars['aid'] = fromUrl;
      }
      const baseExprIndex = trimmed.lastIndexOf('Base()');
      if (baseExprIndex >= 0) {
        const resolved = this.evalKnownJsExpression(trimmed.substring(baseExprIndex), vars, env);
        if (resolved) return resolved;
      }
    }
    return null;
  }

  private evalHostFunctionCall(code: string, value: string, env: ScriptEngineContext): string | null {
    const call = code.match(/^([A-Za-z_$][A-Za-z0-9_$]*)\(\s*(?:result|value|String\(\s*(?:result|value)\s*\))\s*\)\s*;?$/);
    if (!call) return null;
    const func = this.extractFunctionBody(env.getJsLib(), call[1]);
    if (!func) return null;
    const cipherCall = this.evalJavaCipherFunction(func, value);
    if (cipherCall !== null) return cipherCall;
    const utilityCall = this.evalJavaUtilityFunction(func, value);
    if (utilityCall !== null) return utilityCall;
    return null;
  }

  private evalJavaCipherFunction(functionBody: string, value: string): string | null {
    if (!/Cipher\.getInstance|SecretKeySpec|IvParameterSpec/.test(functionBody)) return null;
    const keyMatch = functionBody.match(/SecretKeySpec\s*\(\s*(?:new\s+)?String\s*\(\s*(['"])(.*?)\1\s*\)\.getBytes\(\s*\)\s*,\s*(['"])(.*?)\3\s*\)/) ||
      functionBody.match(/SecretKeySpec\s*\(\s*(['"])(.*?)\1\.getBytes\(\s*\)\s*,\s*(['"])(.*?)\3\s*\)/);
    const ivMatch = functionBody.match(/IvParameterSpec\s*\(\s*(?:new\s+)?String\s*\(\s*(['"])(.*?)\1\s*\)\.getBytes\(\s*\)\s*\)/) ||
      functionBody.match(/IvParameterSpec\s*\(\s*(['"])(.*?)\1\.getBytes\(\s*\)\s*\)/);
    const cipherMatch = functionBody.match(/Cipher\.getInstance\s*\(\s*(['"])(.*?)\1\s*\)/);
    const variableKeyMatch = functionBody.match(/SecretKeySpec\s*\(\s*([A-Za-z_$][A-Za-z0-9_$]*)\.getBytes\s*\([^)]*\)\s*,\s*(['"])(.*?)\2\s*\)/);
    if ((!keyMatch && !variableKeyMatch) || !cipherMatch) return null;
    const key = keyMatch ? keyMatch[2] : this.extractStringVariable(functionBody, variableKeyMatch ? variableKeyMatch[1] : '');
    const keyAlg = keyMatch ? (keyMatch[4] || '') : (variableKeyMatch ? variableKeyMatch[3] : '');
    const variableIvMatch = functionBody.match(/IvParameterSpec\s*\(\s*([A-Za-z_$][A-Za-z0-9_$]*)\.getBytes\s*\([^)]*\)\s*\)/);
    const iv = ivMatch ? ivMatch[2] :
      this.extractStringVariable(functionBody, variableIvMatch ? variableIvMatch[1] : '');
    if (!key) return null;
    const transformation = cipherMatch[2] || keyAlg || 'AES/CBC/PKCS5Padding';
    const upper = transformation.toUpperCase();
    const encrypt = /\bCipher\.ENCRYPT_MODE\b/.test(functionBody);
    const des = upper.startsWith('DES') || upper.startsWith('3DES') || upper.startsWith('TRIPLEDES');
    const method = des ?
      (encrypt ? 'java.desEncodeToBase64String' : 'java.desBase64DecodeToString') :
      (encrypt ? 'java.aesEncodeToBase64String' : 'java.aesBase64DecodeToString');
    this.js.setVar('result', value);
    return this.js.evaluate(`${method}(result,${this.quoteJsString(key)},${this.quoteJsString(transformation)},${this.quoteJsString(iv)})`, value);
  }

  private evalJavaUtilityFunction(functionBody: string, value: string): string | null {
    const normalized = ScriptCompatibility.normalize(functionBody || '');
    let method = '';
    if (/\bMessageDigest\.getInstance\s*\(\s*['"]MD5['"]\s*\)/i.test(functionBody)) method = 'java.md5Encode';
    else if (/\bMessageDigest\.getInstance\s*\(\s*['"]SHA-?1['"]\s*\)/i.test(functionBody)) method = 'java.sha1Encode';
    else if (/\bMessageDigest\.getInstance\s*\(\s*['"]SHA-?256['"]\s*\)/i.test(functionBody)) method = 'java.sha256Encode';
    else if (/\bMessageDigest\.getInstance\s*\(\s*['"]SHA-?512['"]\s*\)/i.test(functionBody)) method = 'java.sha512Encode';
    else if (/\b(?:java\.base64Decode|Base64\.decode)\s*\(/.test(normalized)) method = 'java.base64Decode';
    else if (/\b(?:java\.base64Encode(?:ToString)?|Base64\.encode(?:ToString)?)\s*\(/.test(normalized)) {
      method = 'java.base64EncodeToString';
    }
    else if (/\bjava\.urlDecode\s*\(/.test(normalized)) method = 'java.urlDecode';
    else if (/\bjava\.urlEncode\s*\(/.test(normalized)) method = 'java.urlEncode';
    if (!method) return null;
    return this.js.evaluate(`${method}(${this.quoteJsString(value)})`, value);
  }

  private extractStringVariable(code: string, name: string): string {
    if (!name) return '';
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = (code || '').match(new RegExp(`(?:var|let|const)?\\s*${escaped}\\s*=\\s*(['"])(.*?)\\1`));
    return match ? match[2] : '';
  }

  private extractFunctionBody(code: string, name: string): string {
    const pattern = new RegExp(`function\\s+${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\(`);
    const match = pattern.exec(code || '');
    if (!match) return '';
    const braceStart = (code || '').indexOf('{', match.index + match[0].length);
    if (braceStart < 0) return '';
    let depth = 0;
    let quote = '';
    for (let i = braceStart; i < code.length; i++) {
      const ch = code.charAt(i);
      if (quote) {
        if (ch === quote && code.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') {
        quote = ch;
        continue;
      }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) return code.substring(braceStart + 1, i);
      }
    }
    return '';
  }

  private quoteJsString(value: string): string {
    return `'${(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
  }

  private evalKnownJsExpression(expr: string, vars: Record<string, string>, env: ScriptEngineContext): string {
    let value = (expr || '').trim().replace(/;$/, '');
    if (!value) return '';
    const cleanCall = value.match(/^(?:Clean|T)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (cleanCall) return this.cleanJsLibText(vars[cleanCall[1]] || '');
    const sourceCall = this.evalSourceCall(value, env);
    if (sourceCall !== null) return sourceCall;
    const cacheCall = this.evalCacheCall(value, env);
    if (cacheCall !== null) return cacheCall;
    value = value.replace(/\bBase\(\)/g, `'${this.extractBaseFunctionHost(env)}'`);
    value = value.replace(/\bString\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/g, (_: string, key: string) => {
      return `'${(vars[key] || '').replace(/'/g, "\\'")}'`;
    });
    const parts = this.splitJsConcat(value);
    if (parts.length <= 1 && !/^['"]/.test(value)) return vars[value] || '';
    let out = '';
    for (const part of parts) {
      const token = part.trim();
      if (!token) continue;
      if ((token.startsWith("'") && token.endsWith("'")) || (token.startsWith('"') && token.endsWith('"'))) {
        out += token.substring(1, token.length - 1);
      } else if (vars[token] !== undefined) {
        out += vars[token];
      } else if (/^\d+$/.test(token)) {
        out += token;
      } else {
        return '';
      }
    }
    return out;
  }

  private extractLastJsExpression(code: string): string {
    const trimmed = (code || '').trim();
    const returnMatch = trimmed.match(/return\s+([\s\S]*?);?\s*$/);
    if (returnMatch) return returnMatch[1].trim();
    const parts = trimmed.split(';').map(part => part.trim()).filter(part => part.length > 0);
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (!part.startsWith('var ') && !part.startsWith('let ') && !part.startsWith('const ')) return part;
    }
    return '';
  }

  private splitJsConcat(expr: string): string[] {
    const parts: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < expr.length; i++) {
      const ch = expr.charAt(i);
      if (quote) {
        if (ch === quote && expr.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '+') {
        parts.push(expr.substring(start, i));
        start = i + 1;
      }
    }
    parts.push(expr.substring(start));
    return parts;
  }

  private applyHostSideEffects(code: string, vars: Record<string, string>, env: ScriptEngineContext): void {
    const sourceSetRe = /source\.setVariable\(([\s\S]*?)\)/g;
    let sourceSet: RegExpExecArray | null;
    while ((sourceSet = sourceSetRe.exec(code)) !== null) {
      const args = this.splitArgs(sourceSet[1]);
      if (args.length >= 2) env.setSourceVariable(this.evalHostArg(args[1], vars, env), this.evalHostArg(args[0], vars, env));
      else if (args.length === 1) env.setSourceVariable(this.evalHostArg(args[0], vars, env));
    }

    const cacheLiteralPutRe = /cache\.put(?:Memory)?\(\s*(['"])(.*?)\1\s*,\s*(['"])(.*?)\3\s*\)/g;
    let cacheLiteralPut: RegExpExecArray | null;
    while ((cacheLiteralPut = cacheLiteralPutRe.exec(code)) !== null) {
      env.putCache(cacheLiteralPut[2], cacheLiteralPut[4]);
    }
    const cacheVarPutRe = /cache\.put(?:Memory)?\(\s*(['"])(.*?)\1\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/g;
    let cacheVarPut: RegExpExecArray | null;
    while ((cacheVarPut = cacheVarPutRe.exec(code)) !== null) {
      env.putCache(cacheVarPut[2], vars[cacheVarPut[3]] || env.getVar(cacheVarPut[3]) || '');
    }
  }

  private evalSourceCall(expr: string, env: ScriptEngineContext): string | null {
    const text = (expr || '').trim().replace(/;$/, '');
    if (text === 'source.getKey()' || text === 'source.key') return env.getSourceKey();
    const noArg = text.match(/^source\.getVariable\(\s*\)$/);
    if (noArg) return env.getSourceVariable();
    const withArg = text.match(/^source\.getVariable\(\s*(['"])(.*?)\1\s*\)$/);
    if (withArg) return env.getSourceVariable(withArg[2]);
    const prop = text.match(/^source\.([A-Za-z_][A-Za-z0-9_]*)$/);
    if (prop) return env.getSourceValue(prop[1]);
    return null;
  }

  private evalCacheCall(expr: string, env: ScriptEngineContext): string | null {
    const text = (expr || '').trim().replace(/;$/, '');
    const get = text.match(/^cache\.get(?:FromMemory)?\(\s*(['"])(.*?)\1\s*\)$/);
    if (get) return env.getCache(get[2]);
    return null;
  }

  private evalHostArg(arg: string, vars: Record<string, string>, env: ScriptEngineContext): string {
    const text = (arg || '').trim();
    if (!text) return '';
    const sourceCall = this.evalSourceCall(text, env);
    if (sourceCall !== null) return sourceCall;
    const cacheCall = this.evalCacheCall(text, env);
    if (cacheCall !== null) return cacheCall;
    const stringCall = text.match(/^String\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
    if (stringCall) return vars[stringCall[1]] || env.getVar(stringCall[1]);
    if ((text.startsWith("'") && text.endsWith("'")) || (text.startsWith('"') && text.endsWith('"'))) {
      return text.substring(1, text.length - 1);
    }
    return vars[text] || env.getVar(text) || text;
  }

  private splitArgs(args: string): string[] {
    const result: string[] = [];
    let depth = 0;
    let quote = '';
    let start = 0;
    for (let i = 0; i < args.length; i++) {
      const ch = args.charAt(i);
      if (quote) {
        if (ch === quote && args.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '(' || ch === '[' || ch === '{') depth++;
      if (ch === ')' || ch === ']' || ch === '}') depth--;
      if (ch === ',' && depth === 0) {
        result.push(args.substring(start, i).trim());
        start = i + 1;
      }
    }
    const last = args.substring(start).trim();
    if (last) result.push(last);
    return result;
  }

  private extractArticleIdFromContent(content: string): string {
    try {
      const data = EncodedSourceUrl.asMap(JSON.parse(content || '{}') as Object);
      const direct = EncodedSourceUrl.str(data['articleid']);
      if (direct) return direct;
      const nested = EncodedSourceUrl.asMap(data['data'] as Object);
      return EncodedSourceUrl.str(nested['articleid']);
    } catch (_) {
      return '';
    }
  }

  private extractArticleIdFromUrl(url: string): string {
    const value = url || '';
    const match = value.match(/\/(?:detail|list)\/(\d+)(?:\D|$)/) || value.match(/[?&]articleid=(\d+)/i);
    return match ? match[1] : '';
  }

  private extractBaseFunctionHost(env: ScriptEngineContext): string {
    const raw = env.getJsLib();
    const baseMatch = raw.match(/function\s+Base\s*\(\s*\)\s*\{\s*return\s*['"]([^'"]+)['"]/);
    if (baseMatch) return baseMatch[1];
    const hostMatch = raw.match(/https?:\/\/[^'"`\s,)]+/);
    if (hostMatch) return hostMatch[0];
    const base = (env.getSourceKey() || env.baseUrl || '')
      .match(/^(https?:\/\/[^/]+)/);
    return base ? base[1] : '';
  }

  private cleanJsLibText(value: string): string {
    return (value || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<p[^>]*>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&#39;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/\r/g, '')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }
}
