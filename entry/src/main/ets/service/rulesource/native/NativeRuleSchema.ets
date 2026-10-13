/** native-v1 is data only: every operation and property is validated before use. */
class NativeRuleObject {}

export class NativeTransform extends NativeRuleObject {
  op: string = '';
  value: string = '';
  pattern: string = '';
  replacement: string = '';
  group: number = 0;
  amount: number = 0;
}

export class NativeValue extends NativeRuleObject {
  kind: string = 'literal';
  value: string = '';
  attribute: string = 'text';
  index: number = 0;
  transforms: NativeTransform[] = [];
  required: boolean = false;
}

export class NativeNamedValue extends NativeRuleObject {
  name: string = '';
  value: NativeValue = new NativeValue();
}

export class NativeRequest extends NativeRuleObject {
  url: NativeValue = new NativeValue();
  method: string = 'GET';
  headers: NativeNamedValue[] = [];
  form: NativeNamedValue[] = [];
  body: NativeValue = new NativeValue();
}

export class NativeStage extends NativeRuleObject {
  format: string = 'html';
  bindings: NativeNamedValue[] = [];
  request: NativeRequest = new NativeRequest();
  list: NativeValue = new NativeValue();
  fields: NativeNamedValue[] = [];
  next: NativeValue = new NativeValue();
  maxPages: number = 1;
}

export class NativeDiscovery extends NativeRuleObject {
  title: string = '';
  url: string = '';
}

export class NativeRuleDefinition extends NativeRuleObject {
  version: number = 1;
  headers: NativeNamedValue[] = [];
  discover: NativeDiscovery[] = [];
  search: NativeStage = new NativeStage();
  explore: NativeStage = new NativeStage();
  detail: NativeStage = new NativeStage();
  toc: NativeStage = new NativeStage();
  content: NativeStage = new NativeStage();
}

export class NativeRuleSchema {
  static readonly MAX_VALUE_CHARS: number = 4 * 1024 * 1024;
  static readonly MAX_REGEX_INPUT: number = 4096;

  static parse(json: string): NativeRuleDefinition {
    if (!json || json.length > 256 * 1024) throw new Error('原生规则为空或超过 256 KiB');
    const raw: NativeRuleDefinition = JSON.parse(json);
    NativeRuleSchema.shape(raw, ['version', 'headers', 'discover', 'search', 'explore', 'detail', 'toc', 'content']);
    if (raw.version !== 1) throw new Error('原生规则只支持 version=1');
    const result = new NativeRuleDefinition();
    result.headers = NativeRuleSchema.named(raw.headers);
    if (raw.discover !== undefined) {
      if (!Array.isArray(raw.discover) || raw.discover.length > 100) throw new Error('发现分类必须为最多 100 项的数组');
      for (const item of raw.discover) {
        NativeRuleSchema.shape(item, ['title', 'url']);
        const discovery = new NativeDiscovery();
        discovery.title = NativeRuleSchema.string(item.title, '', 100);
        discovery.url = NativeRuleSchema.string(item.url, '', 8192);
        if (!discovery.title || !discovery.url) throw new Error('发现分类缺少标题或地址');
        NativeRuleSchema.template(discovery.url);
        result.discover.push(discovery);
      }
    }
    result.search = NativeRuleSchema.stage(raw.search);
    result.explore = NativeRuleSchema.stage(raw.explore);
    result.detail = NativeRuleSchema.stage(raw.detail);
    result.toc = NativeRuleSchema.stage(raw.toc);
    result.content = NativeRuleSchema.stage(raw.content);
    NativeRuleSchema.fields(result.search, ['name', 'author', 'kind', 'coverUrl', 'intro', 'bookUrl', 'lastChapter', 'wordCount', 'status', 'updateTime'], ['name', 'bookUrl']);
    NativeRuleSchema.fields(result.explore, ['name', 'author', 'kind', 'coverUrl', 'intro', 'bookUrl', 'lastChapter', 'wordCount', 'status', 'updateTime'], ['name', 'bookUrl']);
    NativeRuleSchema.fields(result.detail, ['name', 'author', 'kind', 'coverUrl', 'intro', 'tocUrl', 'lastChapter', 'wordCount', 'updateTime', 'status'], []);
    NativeRuleSchema.fields(result.toc, ['chapterName', 'chapterUrl', 'isVip', 'isPay', 'isVolume', 'updateTime', 'duration'], ['chapterName', 'chapterUrl']);
    NativeRuleSchema.fields(result.content, ['title', 'content', 'audioUrl', 'nextContentUrl'], []);
    NativeRuleSchema.listStage(result.search);
    NativeRuleSchema.listStage(result.explore);
    NativeRuleSchema.listStage(result.toc);
    NativeRuleSchema.scalarStage(result.detail);
    NativeRuleSchema.scalarStage(result.content);
    if ((result.content.fields.length > 0 || result.content.request.url.value) &&
      !result.content.fields.some((item: NativeNamedValue): boolean => item.name === 'content' || item.name === 'audioUrl')) {
      throw new Error('内容阶段必须输出 content 或 audioUrl');
    }
    return result;
  }

  private static listStage(stage: NativeStage): void {
    const list = stage.list;
    if (list.index !== 0 || list.attribute !== 'text' || list.required || list.transforms.length > 0) {
      throw new Error('列表规则不支持 index、attribute、required 或 transforms 配置');
    }
    if (!list.value && stage.fields.length === 0 && !stage.request.url.value && stage.bindings.length === 0 && !stage.next.value) return;
    if (!list.value || !((list.kind === 'css' && stage.format === 'html') || (list.kind === 'json' && stage.format === 'json'))) {
      throw new Error('列表规则必须为与响应格式匹配的非空 CSS 或 JSONPath');
    }
  }

  private static scalarStage(stage: NativeStage): void {
    const list = stage.list;
    if (list.kind !== 'literal' || list.value || list.index !== 0 || list.attribute !== 'text' || list.required || list.transforms.length > 0) {
      throw new Error('详情和内容阶段不支持列表规则');
    }
  }

  private static fields(stage: NativeStage, allowed: string[], required: string[]): void {
    if (stage.fields.length === 0 && !stage.list.value && !stage.request.url.value) return;
    const names: string[] = stage.fields.map((item: NativeNamedValue): string => item.name);
    for (const name of names) if (!allowed.includes(name)) throw new Error(`阶段字段不支持：${name}`);
    for (const name of required) if (!names.includes(name)) throw new Error(`阶段缺少字段：${name}`);
  }

  private static shape(value: NativeRuleObject, keys: string[]): void {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('规则节点必须为对象');
    for (const key of Object.keys(value)) {
      if (!keys.includes(key)) throw new Error(`原生规则不支持字段：${key}`);
    }
  }

  private static string(value: string | undefined, fallback: string, limit: number = 8192): string {
    if (value === undefined) return fallback;
    if (typeof value !== 'string' || value.length > limit) throw new Error('原生规则字符串类型或长度错误');
    if (new RegExp('<script|<js>|@js:', 'i').test(value)) throw new Error('原生规则禁止嵌入脚本');
    return value;
  }

  private static integer(value: number | undefined, fallback: number, min: number, max: number): number {
    if (value === undefined) return fallback;
    if (!Number.isInteger(value) || value < min || value > max) throw new Error('原生规则整数超出范围');
    return value;
  }

  static template(value: string): void {
    const stripped = value.replace(new RegExp('\\{\\{[A-Za-z_][A-Za-z0-9_]*\\}\\}', 'g'), '');
    if (stripped.includes('{{') || stripped.includes('}}')) throw new Error('模板只允许命名变量，不支持脚本表达式');
  }

  private static named(raw: NativeNamedValue[] | undefined): NativeNamedValue[] {
    if (raw === undefined) return [];
    if (!Array.isArray(raw) || raw.length > 64) throw new Error('命名规则必须为最多 64 项的数组');
    const result: NativeNamedValue[] = [];
    const names: Set<string> = new Set();
    for (const item of raw) {
      NativeRuleSchema.shape(item, ['name', 'value']);
      const output = new NativeNamedValue();
      output.name = NativeRuleSchema.string(item.name, '', 100);
      if (!new RegExp('^[A-Za-z_][A-Za-z0-9_-]*$').test(output.name) || names.has(output.name)) {
        throw new Error('命名规则名称无效或重复');
      }
      if (item.value === undefined) throw new Error(`命名规则缺少值：${output.name}`);
      output.value = NativeRuleSchema.value(item.value);
      names.add(output.name);
      result.push(output);
    }
    return result;
  }

  private static stage(raw: NativeStage | undefined): NativeStage {
    if (raw === undefined) return new NativeStage();
    NativeRuleSchema.shape(raw, ['format', 'bindings', 'request', 'list', 'fields', 'next', 'maxPages']);
    const stage = new NativeStage();
    stage.format = NativeRuleSchema.string(raw.format, 'html');
    if (!['html', 'json', 'text'].includes(stage.format)) throw new Error('未知响应格式');
    stage.bindings = NativeRuleSchema.named(raw.bindings);
    for (const binding of stage.bindings) {
      if (['key', 'page', 'page0', 'url', 'bookUrl', 'chapterUrl', 'timestamp'].includes(binding.name)) {
        throw new Error(`绑定不能覆盖系统变量：${binding.name}`);
      }
    }
    stage.request = NativeRuleSchema.request(raw.request);
    stage.list = NativeRuleSchema.value(raw.list);
    stage.fields = NativeRuleSchema.named(raw.fields);
    stage.next = NativeRuleSchema.value(raw.next);
    stage.maxPages = NativeRuleSchema.integer(raw.maxPages, 1, 1, 100);
    return stage;
  }

  private static request(raw: NativeRequest | undefined): NativeRequest {
    if (raw === undefined) return new NativeRequest();
    NativeRuleSchema.shape(raw, ['url', 'method', 'headers', 'form', 'body']);
    const result = new NativeRequest();
    result.url = NativeRuleSchema.value(raw.url);
    result.method = NativeRuleSchema.string(raw.method, 'GET').toUpperCase();
    if (!['GET', 'POST'].includes(result.method)) throw new Error('原生请求只支持 GET/POST');
    result.headers = NativeRuleSchema.named(raw.headers);
    result.form = NativeRuleSchema.named(raw.form);
    result.body = NativeRuleSchema.value(raw.body);
    if (result.form.length > 0 && result.body.value.length > 0) throw new Error('请求不能同时设置表单和正文');
    if (result.method === 'GET' && (result.form.length > 0 || result.body.value.length > 0)) {
      throw new Error('GET 请求不能设置表单或正文');
    }
    return result;
  }

  private static value(raw: NativeValue | undefined): NativeValue {
    if (raw === undefined) return new NativeValue();
    NativeRuleSchema.shape(raw, ['kind', 'value', 'attribute', 'index', 'transforms', 'required']);
    const result = new NativeValue();
    result.kind = NativeRuleSchema.string(raw.kind, 'literal');
    if (!['literal', 'variable', 'template', 'css', 'json'].includes(result.kind)) throw new Error('未知取值操作');
    result.value = NativeRuleSchema.string(raw.value, '');
    result.attribute = NativeRuleSchema.string(raw.attribute, 'text', 100);
    result.index = NativeRuleSchema.integer(raw.index, 0, 0, 49999);
    if (raw.required !== undefined && typeof raw.required !== 'boolean') throw new Error('required 必须为布尔值');
    result.required = raw.required === true;
    if (result.kind === 'template') NativeRuleSchema.template(result.value);
    if (result.kind === 'variable' && !new RegExp('^[A-Za-z_][A-Za-z0-9_]*$').test(result.value)) {
      throw new Error('变量名无效');
    }
    if (raw.transforms !== undefined) {
      if (!Array.isArray(raw.transforms) || raw.transforms.length > 16) throw new Error('转换步骤最多 16 个');
      for (const item of raw.transforms) result.transforms.push(NativeRuleSchema.transform(item));
    }
    return result;
  }

  private static transform(raw: NativeTransform): NativeTransform {
    NativeRuleSchema.shape(raw, ['op', 'value', 'pattern', 'replacement', 'group', 'amount']);
    const result = new NativeTransform();
    result.op = NativeRuleSchema.string(raw.op, '');
    if (!['trim', 'replace', 'regexGroup', 'add', 'md5', 'urlEncode', 'base64Decode', 'resolveUrl'].includes(result.op)) {
      throw new Error(`未知转换操作：${result.op}`);
    }
    result.value = NativeRuleSchema.string(raw.value, '');
    result.pattern = NativeRuleSchema.string(raw.pattern, '', 256);
    result.replacement = NativeRuleSchema.string(raw.replacement, '');
    result.group = NativeRuleSchema.integer(raw.group, 0, 0, 16);
    result.amount = NativeRuleSchema.integer(raw.amount, 0, -1000000, 1000000);
    if (result.op === 'replace' || result.op === 'regexGroup') NativeRuleSchema.regex(result.pattern);
    return result;
  }

  /** One repeat, or digit runs separated by fixed delimiters; input is additionally capped. */
  static regex(pattern: string): void {
    if (!pattern || pattern.length > 256 || pattern.includes('|') || pattern.includes('(?') ||
      new RegExp('\\\\[1-9]|\\)[*+?{]|[+*?}][+*?{]').test(pattern)) {
      throw new Error('正则仅支持有界简单匹配，不支持回溯引用、分支或量化分组');
    }
    const starts: number[] = [];
    const ends: number[] = [];
    const numeric: boolean[] = [];
    let cursor = 0;
    while (cursor < pattern.length) {
      const start = cursor;
      const character = pattern.charAt(cursor);
      if (character === '\\') cursor += 2;
      else if (character === '[') {
        cursor++;
        while (cursor < pattern.length && pattern.charAt(cursor) !== ']') {
          cursor += pattern.charAt(cursor) === '\\' ? 2 : 1;
        }
        cursor++;
      } else {
        if ('*+?{}'.includes(character)) throw new Error('正则不支持可选项、次数范围或重复量词');
        cursor++;
      }
      const quantifier = pattern.charAt(cursor);
      if (quantifier === '*' || quantifier === '+') {
        starts.push(start);
        numeric.push(pattern.substring(start, cursor) === '\\d' && quantifier === '+');
        ends.push(++cursor);
      }
    }
    if (starts.length > 1) {
      for (let index = 0; index < starts.length; index++) {
        if (!numeric[index]) throw new Error('多个重复项仅支持固定分隔符隔开的数字');
        if (index > 0) {
          const separator = pattern.substring(ends[index - 1], starts[index]).replace(new RegExp('[()]', 'g'), '');
          if (!['-', '/', '\\.', ':', ',', '_', ' '].includes(separator)) {
            throw new Error('重复数字之间必须使用固定的非数字分隔符');
          }
        }
      }
    }
    new RegExp(pattern);
  }
}
