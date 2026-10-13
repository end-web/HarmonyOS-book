/**
 * 无 Web / 动态脚本的有界 HTML 提取子集，供原生书源和 API 20 回退使用。
 * 这是容错提取器，不实现浏览器 HTML5 树构建、布局、命名空间或脚本执行。
 * CSS 支持 tag/*、#id、.class、[attr]、[attr=value]、后代、子代和逗号组。
 * 不支持伪类、兄弟组合、转义、属性操作符/标志；调用方用 index 选择结果。
 * 实体支持常见命名实体与十/十六进制字符引用；未知实体原样保留。
 */
export class NativeHtmlNode {
  tagName: string = '';
  parent: NativeHtmlNode | undefined = undefined;
  children: NativeHtmlNode[] = [];
  attributes: Map<string, string> = new Map<string, string>();
  source: string = '';
  contentStart: number = 0;
  contentEnd: number = 0;
  textValue: string = '';

  text(): string {
    const parts: string[] = [];
    const pending: NativeHtmlNode[] = [this];
    while (pending.length > 0) {
      const node = pending.pop();
      if (node === undefined || node.tagName === 'script' || node.tagName === 'style') continue;
      if (node.tagName === '#text') parts.push(node.textValue);
      for (let index = node.children.length - 1; index >= 0; index--) pending.push(node.children[index]);
    }
    return parts.join('');
  }

  attribute(name: string): string {
    return this.attributes.get(name.toLowerCase()) ?? '';
  }

  innerHtml(): string {
    return this.source.substring(this.contentStart, this.contentEnd);
  }
}

class NativeHtmlAttributeSelector {
  name: string = '';
  value: string = '';
  hasValue: boolean = false;
}

class NativeHtmlSelectorStep {
  tag: string = '';
  ids: string[] = [];
  classes: string[] = [];
  attributes: NativeHtmlAttributeSelector[] = [];
  child: boolean = false;

  matches(node: NativeHtmlNode): boolean {
    if (this.tag && this.tag !== '*' && node.tagName !== this.tag) return false;
    for (const id of this.ids) if (node.attribute('id') !== id) return false;
    const classes = node.attribute('class').split(new RegExp('[\\t\\n\\f\\r ]+'));
    for (const name of this.classes) if (!classes.includes(name)) return false;
    for (const attribute of this.attributes) {
      if (!node.attributes.has(attribute.name)) return false;
      if (attribute.hasValue && node.attribute(attribute.name) !== attribute.value) return false;
    }
    return true;
  }
}

class NativeHtmlSelectorGroup {
  steps: NativeHtmlSelectorStep[] = [];
}

class NativeHtmlMatchState {
  node: NativeHtmlNode;
  step: number;
  constructor(node: NativeHtmlNode, step: number) {
    this.node = node;
    this.step = step;
  }
}

class NativeHtmlSelectorReader {
  private value: string;
  private cursor: number = 0;
  constructor(value: string) { this.value = value; }

  read(): NativeHtmlSelectorGroup[] {
    if (!this.value.trim() || this.value.length > 1024) throw new Error('CSS 选择器为空或超过 1024 字符');
    const groups: NativeHtmlSelectorGroup[] = [];
    while (this.cursor < this.value.length) {
      if (groups.length >= 16) throw new Error('CSS 选择器超过 16 组');
      const group = new NativeHtmlSelectorGroup();
      this.skipSpace();
      let child = false;
      while (this.cursor < this.value.length) {
        const step = this.readStep();
        step.child = child;
        group.steps.push(step);
        if (group.steps.length > 16) throw new Error('CSS 选择器超过 16 层');
        const hadSpace = this.skipSpace();
        if (this.cursor >= this.value.length || this.value.charAt(this.cursor) === ',') break;
        child = this.value.charAt(this.cursor) === '>';
        if (child) {
          this.cursor++;
          this.skipSpace();
          if (this.cursor >= this.value.length) throw new Error('CSS 子代选择器缺少右侧表达式');
        } else if (!hadSpace) {
          throw new Error('不支持的 CSS 选择器语法');
        }
      }
      groups.push(group);
      if (this.cursor < this.value.length) {
        this.cursor++;
        this.skipSpace();
        if (this.cursor >= this.value.length) throw new Error('CSS 逗号后缺少选择器');
      }
    }
    return groups;
  }

  private readStep(): NativeHtmlSelectorStep {
    const step = new NativeHtmlSelectorStep();
    if (this.value.charAt(this.cursor) === '*') { step.tag = '*'; this.cursor++; }
    else if (NativeHtmlParser.isNameStart(this.value.charAt(this.cursor))) step.tag = this.name().toLowerCase();
    while (this.cursor < this.value.length) {
      const character = this.value.charAt(this.cursor);
      if (character === '#' || character === '.') {
        this.cursor++;
        const name = this.name();
        if (character === '#') step.ids.push(name); else step.classes.push(name);
      } else if (character === '[') {
        step.attributes.push(this.attribute());
      } else break;
    }
    if (!step.tag && step.ids.length === 0 && step.classes.length === 0 && step.attributes.length === 0) {
      throw new Error('不支持或无效的 CSS 选择器');
    }
    const character = this.value.charAt(this.cursor);
    if (character && !NativeHtmlParser.isSpace(character) && character !== '>' && character !== ',') {
      throw new Error('不支持的 CSS 选择器语法（伪类、兄弟组合或转义等）');
    }
    return step;
  }

  private attribute(): NativeHtmlAttributeSelector {
    const attribute = new NativeHtmlAttributeSelector();
    this.cursor++;
    this.skipSpace();
    attribute.name = this.name().toLowerCase();
    this.skipSpace();
    if (this.value.charAt(this.cursor) === '=') {
      attribute.hasValue = true;
      this.cursor++;
      this.skipSpace();
      const quote = this.value.charAt(this.cursor);
      if (quote === '"' || quote === "'") {
        this.cursor++;
        const start = this.cursor;
        while (this.cursor < this.value.length && this.value.charAt(this.cursor) !== quote) {
          if (this.value.charAt(this.cursor) === '\\') throw new Error('CSS 属性值暂不支持转义');
          this.cursor++;
        }
        if (this.cursor >= this.value.length) throw new Error('CSS 属性引号未闭合');
        attribute.value = this.value.substring(start, this.cursor++);
      } else attribute.value = this.name();
      this.skipSpace();
    }
    if (this.value.charAt(this.cursor) !== ']') throw new Error('CSS 仅支持属性存在或等值条件');
    this.cursor++;
    return attribute;
  }

  private name(): string {
    const start = this.cursor;
    while (NativeHtmlParser.isNameCharacter(this.value.charAt(this.cursor))) this.cursor++;
    if (start === this.cursor) throw new Error('CSS 名称不能为空');
    return this.value.substring(start, this.cursor);
  }

  private skipSpace(): boolean {
    const start = this.cursor;
    while (NativeHtmlParser.isSpace(this.value.charAt(this.cursor))) this.cursor++;
    return this.cursor > start;
  }
}

export class NativeHtmlDocument {
  readonly root: NativeHtmlNode;
  constructor(root: NativeHtmlNode) { this.root = root; }

  select(selector: string, root?: NativeHtmlNode): NativeHtmlNode[] {
    const groups = new NativeHtmlSelectorReader(selector).read();
    const scope = root ?? this.root;
    const result: NativeHtmlNode[] = [];
    const pending: NativeHtmlNode[] = [];
    for (let index = scope.children.length - 1; index >= 0; index--) pending.push(scope.children[index]);
    let budget = 1000000;
    while (pending.length > 0) {
      const node = pending.pop();
      if (node === undefined) continue;
      if (--budget < 0) throw new Error('CSS 查询超过执行预算');
      if (node.tagName !== '#text') {
        for (const group of groups) {
          const states: NativeHtmlMatchState[] = [new NativeHtmlMatchState(node, group.steps.length - 1)];
          let matched = false;
          while (states.length > 0) {
            if (--budget < 0) throw new Error('CSS 查询超过执行预算');
            const state = states.pop();
            if (state === undefined) continue;
            const step = group.steps[state.step];
            if (!step.matches(state.node)) continue;
            if (state.step === 0) { matched = true; break; }
            let ancestor = state.node.parent;
            while (ancestor !== undefined && ancestor !== scope.parent) {
              if (--budget < 0) throw new Error('CSS 查询超过执行预算');
              states.push(new NativeHtmlMatchState(ancestor, state.step - 1));
              if (step.child) break;
              ancestor = ancestor.parent;
            }
          }
          if (matched) { result.push(node); break; }
        }
      }
      for (let index = node.children.length - 1; index >= 0; index--) pending.push(node.children[index]);
    }
    return result;
  }
}

class NativeHtmlTag {
  name: string = '';
  attributes: Map<string, string> = new Map<string, string>();
  end: number = 0;
  closing: boolean = false;
  selfClosing: boolean = false;
}

class NativeHtmlTokenAttribute {
  name: string = '';
  value: string = '';
}

class NativeHtmlToken {
  type: string = '';
  name: string = '';
  text: string = '';
  attributes: NativeHtmlTokenAttribute[] = [];
  selfClosing: boolean = false;
  start: number = 0;
  end: number = 0;
}

class NativeHtmlTokenEnvelope {
  tokens: NativeHtmlToken[] = [];
  error: string = '';
}

export class NativeHtmlParser {
  private static readonly MAX_INPUT: number = 4 * 1024 * 1024;
  private static readonly MAX_NODES: number = 50000;
  private static readonly MAX_DEPTH: number = 256;
  private static readonly VOID_TAGS: string[] = ['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'];
  private static readonly P_BLOCKS: string[] = ['address', 'article', 'aside', 'blockquote', 'div', 'dl', 'fieldset', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'ul'];
  private static readonly ENTITIES: Map<string, string> = NativeHtmlParser.createEntities();

  /**
   * 接收仓颉 tokenizeHtml 的数据协议；不执行任何字符串代码。
   * start/end 为原始 HTML 的 UTF-16 偏移，end 为开区间；text/属性值尚未实体解码。
   * 注释和声明可以不返回 token。以原始偏移保留 innerHtml，与 ArkTS 回退共用树与选择器。
   */
  static parseTokens(html: string, tokenJson: string): NativeHtmlDocument {
    if (html.length > NativeHtmlParser.MAX_INPUT) throw new Error('HTML 超过 4 MiB 字符预算');
    if (tokenJson.length > 32 * 1024 * 1024) throw new Error('HTML token 数据超过 32 MiB 字符预算');
    const envelope: NativeHtmlTokenEnvelope = JSON.parse(tokenJson);
    if (envelope === null || typeof envelope !== 'object' || Array.isArray(envelope) ||
      typeof envelope.error !== 'string' || !Array.isArray(envelope.tokens)) {
      throw new Error('HTML token 返回格式无效');
    }
    if (envelope.error) throw new Error(`HTML tokenizer 失败：${envelope.error.substring(0, 256)}`);
    if (envelope.tokens.length > 100000) throw new Error('HTML token 超过 100000 个');
    const root = new NativeHtmlNode();
    root.tagName = '#document';
    root.source = html;
    root.contentEnd = html.length;
    const stack: NativeHtmlNode[] = [root];
    let previousEnd = 0;
    let count = 1;
    for (const token of envelope.tokens) {
      if (token === null || typeof token !== 'object' || Array.isArray(token) ||
        !Number.isInteger(token.start) || !Number.isInteger(token.end) ||
        token.start < previousEnd || token.end <= token.start || token.end > html.length) {
        throw new Error('HTML token 偏移无效，要求顺序 UTF-16 开区间');
      }
      previousEnd = token.end;
      const parent = stack[stack.length - 1];
      if (token.type === 'text') {
        if (typeof token.text !== 'string' || token.text !== html.substring(token.start, token.end)) {
          throw new Error('HTML text token 必须保留未解码源码');
        }
        if (parent.tagName !== 'script' && parent.tagName !== 'style') {
          NativeHtmlParser.appendText(parent, token.text);
          count++;
        }
      } else if (token.type === 'open' || token.type === 'close') {
        if (typeof token.name !== 'string' || !new RegExp('^[A-Za-z_][A-Za-z0-9_:-]*$').test(token.name) ||
          html.charAt(token.start) !== '<' || html.charAt(token.end - 1) !== '>') {
          throw new Error('HTML 标签 token 无效');
        }
        const name = token.name.toLowerCase();
        const rawParent = ['script', 'style', 'title', 'textarea'].includes(parent.tagName);
        if (rawParent && (token.type !== 'close' || name !== parent.tagName)) {
          throw new Error('HTML tokenizer 未正确隔离原始文本元素');
        }
        if (token.type === 'close') {
          for (let index = stack.length - 1; index > 0; index--) {
            if (stack[index].tagName === name) {
              NativeHtmlParser.closeStack(stack, index, token.start);
              break;
            }
          }
        } else {
          if (!Array.isArray(token.attributes) || token.attributes.length > 128 || typeof token.selfClosing !== 'boolean') {
            throw new Error('HTML token 属性格式无效或超过 128 个');
          }
          NativeHtmlParser.closeOptional(stack, name, token.start);
          const node = new NativeHtmlNode();
          node.tagName = name;
          node.source = html;
          node.contentStart = token.end;
          node.contentEnd = token.end;
          node.parent = stack[stack.length - 1];
          for (const attribute of token.attributes) {
            if (attribute === null || typeof attribute !== 'object' || Array.isArray(attribute) ||
              typeof attribute.name !== 'string' || !attribute.name || typeof attribute.value !== 'string') {
              throw new Error('HTML token 属性无效');
            }
            const attributeName = attribute.name.toLowerCase();
            if (!node.attributes.has(attributeName)) {
              node.attributes.set(attributeName, NativeHtmlParser.decodeEntities(attribute.value));
            }
          }
          node.parent.children.push(node);
          count++;
          if (!token.selfClosing && !NativeHtmlParser.VOID_TAGS.includes(name)) {
            if (stack.length >= NativeHtmlParser.MAX_DEPTH) throw new Error('HTML 嵌套超过 256 层');
            stack.push(node);
          }
        }
      } else throw new Error('HTML token 类型无效');
      if (count > NativeHtmlParser.MAX_NODES) throw new Error('HTML 节点超过 50000 个');
    }
    NativeHtmlParser.closeStack(stack, 1, html.length);
    return new NativeHtmlDocument(root);
  }

  static parse(html: string): NativeHtmlDocument {
    if (html.length > NativeHtmlParser.MAX_INPUT) throw new Error('HTML 超过 4 MiB 字符预算');
    const root = new NativeHtmlNode();
    root.tagName = '#document';
    root.source = html;
    root.contentEnd = html.length;
    const stack: NativeHtmlNode[] = [root];
    // 仅折叠 ASCII，避免 İ 等 Unicode 大小写转换改变字符串长度和源码偏移。
    const lower = html.replace(new RegExp('[A-Z]', 'g'), (value: string): string => value.toLowerCase());
    let cursor = 0;
    let count = 1;
    while (cursor < html.length) {
      const parent = stack[stack.length - 1];
      if (parent.tagName === 'script' || parent.tagName === 'style' || parent.tagName === 'textarea' || parent.tagName === 'title') {
        const close = NativeHtmlParser.rawClose(lower, parent.tagName, cursor);
        const end = close < 0 ? html.length : close;
        if (parent.tagName === 'textarea' || parent.tagName === 'title') {
          if (end > cursor) {
            NativeHtmlParser.appendText(parent, html.substring(cursor, end));
            if (++count > NativeHtmlParser.MAX_NODES) throw new Error('HTML 节点超过 50000 个');
          }
        }
        parent.contentEnd = end;
        if (close < 0) { cursor = html.length; break; }
        cursor = close;
      }
      if (html.startsWith('<!--', cursor)) {
        const end = html.indexOf('-->', cursor + 4);
        cursor = end < 0 ? html.length : end + 3;
        continue;
      }
      if (html.startsWith('<!', cursor) || html.startsWith('<?', cursor)) {
        const end = html.indexOf('>', cursor + 2);
        cursor = end < 0 ? html.length : end + 1;
        continue;
      }
      const tag = html.charAt(cursor) === '<' ? NativeHtmlParser.readTag(html, cursor) : undefined;
      if (tag === undefined) {
        let end = html.indexOf('<', cursor + 1);
        if (end < 0) end = html.length;
        NativeHtmlParser.appendText(parent, html.substring(cursor, end));
        count++;
        cursor = end;
      } else if (tag.closing) {
        for (let index = stack.length - 1; index > 0; index--) {
          if (stack[index].tagName === tag.name) {
            NativeHtmlParser.closeStack(stack, index, cursor);
            break;
          }
        }
        cursor = tag.end;
      } else {
        NativeHtmlParser.closeOptional(stack, tag.name, cursor);
        const node = new NativeHtmlNode();
        node.tagName = tag.name;
        node.attributes = tag.attributes;
        node.source = html;
        node.contentStart = tag.end;
        node.contentEnd = tag.end;
        node.parent = stack[stack.length - 1];
        node.parent.children.push(node);
        count++;
        if (!tag.selfClosing && !NativeHtmlParser.VOID_TAGS.includes(tag.name)) {
          if (stack.length >= NativeHtmlParser.MAX_DEPTH) throw new Error('HTML 嵌套超过 256 层');
          stack.push(node);
        }
        cursor = tag.end;
      }
      if (count > NativeHtmlParser.MAX_NODES) throw new Error('HTML 节点超过 50000 个');
    }
    NativeHtmlParser.closeStack(stack, 1, html.length);
    return new NativeHtmlDocument(root);
  }

  static decodeEntities(value: string): string {
    const parts: string[] = [];
    let cursor = 0;
    while (cursor < value.length) {
      const start = value.indexOf('&', cursor);
      if (start < 0) { parts.push(value.substring(cursor)); break; }
      parts.push(value.substring(cursor, start));
      let end = start + 1;
      while (end < value.length && end - start <= 32 && value.charAt(end) !== ';' &&
        !NativeHtmlParser.isSpace(value.charAt(end)) && value.charAt(end) !== '&' && value.charAt(end) !== '<') end++;
      if (value.charAt(end) !== ';') { parts.push('&'); cursor = start + 1; continue; }
      const name = value.substring(start + 1, end);
      let decoded = NativeHtmlParser.ENTITIES.get(name);
      if (name.startsWith('#')) {
        const hexadecimal = name.charAt(1).toLowerCase() === 'x';
        const digits = name.substring(hexadecimal ? 2 : 1);
        if (digits && new RegExp(hexadecimal ? '^[0-9a-fA-F]+$' : '^[0-9]+$').test(digits)) {
          const code = Number.parseInt(digits, hexadecimal ? 16 : 10);
          decoded = code === 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)
            ? '\ufffd' : String.fromCodePoint(code);
        }
      }
      parts.push(decoded ?? value.substring(start, end + 1));
      cursor = end + 1;
    }
    return parts.join('');
  }

  static isSpace(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r' || value === '\f';
  }

  static isNameStart(value: string): boolean {
    if (!value) return false;
    const code = value.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || value === '_' || value === '-' || code >= 128;
  }

  static isNameCharacter(value: string): boolean {
    return NativeHtmlParser.isNameStart(value) || (value >= '0' && value <= '9');
  }

  private static appendText(parent: NativeHtmlNode, value: string): void {
    if (!value) return;
    const node = new NativeHtmlNode();
    node.tagName = '#text';
    node.parent = parent;
    node.textValue = NativeHtmlParser.decodeEntities(value);
    parent.children.push(node);
  }

  private static closeStack(stack: NativeHtmlNode[], first: number, end: number): void {
    while (stack.length > first) {
      const node = stack.pop();
      if (node !== undefined) node.contentEnd = end;
    }
  }

  private static closeOptional(stack: NativeHtmlNode[], incoming: string, offset: number): void {
    for (let index = stack.length - 1; index > 0; index--) {
      const tag = stack[index].tagName;
      const closes = (tag === 'p' && NativeHtmlParser.P_BLOCKS.includes(incoming)) ||
        (tag === 'li' && incoming === 'li') ||
        ((tag === 'dt' || tag === 'dd') && (incoming === 'dt' || incoming === 'dd')) ||
        ((tag === 'td' || tag === 'th') && (incoming === 'td' || incoming === 'th' || incoming === 'tr')) ||
        (tag === 'tr' && incoming === 'tr') || (tag === 'option' && (incoming === 'option' || incoming === 'optgroup'));
      if (closes) {
        NativeHtmlParser.closeStack(stack, index, offset);
        if (incoming === 'tr' && (tag === 'td' || tag === 'th')) continue;
        return;
      }
      // 不跨过新的同类容器关闭外层 li/dt/td；不实现完整 HTML5 insertion modes。
      if (['ul', 'ol', 'dl', 'table', 'select'].includes(tag)) return;
    }
  }

  private static rawClose(lower: string, tag: string, start: number): number {
    let cursor = start;
    while (cursor < lower.length) {
      const found = lower.indexOf(`</${tag}`, cursor);
      if (found < 0) return -1;
      const next = lower.charAt(found + tag.length + 2);
      if (next === '>' || next === '/' || NativeHtmlParser.isSpace(next)) return found;
      cursor = found + tag.length + 2;
    }
    return -1;
  }

  private static readTag(html: string, offset: number): NativeHtmlTag | undefined {
    const tag = new NativeHtmlTag();
    let cursor = offset + 1;
    if (html.charAt(cursor) === '/') { tag.closing = true; cursor++; }
    if (!NativeHtmlParser.isNameStart(html.charAt(cursor))) return undefined;
    const start = cursor;
    while (NativeHtmlParser.isNameCharacter(html.charAt(cursor)) || html.charAt(cursor) === ':') cursor++;
    tag.name = html.substring(start, cursor).toLowerCase();
    let attributeCount = 0;
    while (cursor < html.length) {
      while (NativeHtmlParser.isSpace(html.charAt(cursor))) cursor++;
      if (html.charAt(cursor) === '>') { tag.end = cursor + 1; return tag; }
      if (html.charAt(cursor) === '/' && html.charAt(cursor + 1) === '>') {
        tag.selfClosing = true;
        tag.end = cursor + 2;
        return tag;
      }
      if (html.charAt(cursor) === '<') return undefined;
      const nameStart = cursor;
      while (cursor < html.length && !NativeHtmlParser.isSpace(html.charAt(cursor)) &&
        !['=', '>', '/', '<'].includes(html.charAt(cursor))) cursor++;
      if (nameStart === cursor) { cursor++; continue; }
      const name = html.substring(nameStart, cursor).toLowerCase();
      while (NativeHtmlParser.isSpace(html.charAt(cursor))) cursor++;
      let value = '';
      if (html.charAt(cursor) === '=') {
        cursor++;
        while (NativeHtmlParser.isSpace(html.charAt(cursor))) cursor++;
        const quote = html.charAt(cursor);
        if (quote === '"' || quote === "'") {
          cursor++;
          const valueStart = cursor;
          while (cursor < html.length && html.charAt(cursor) !== quote) cursor++;
          value = html.substring(valueStart, cursor);
          if (cursor < html.length) cursor++;
        } else {
          const valueStart = cursor;
          while (cursor < html.length && !NativeHtmlParser.isSpace(html.charAt(cursor)) && html.charAt(cursor) !== '>') cursor++;
          value = html.substring(valueStart, cursor);
        }
      }
      if (!tag.attributes.has(name)) tag.attributes.set(name, NativeHtmlParser.decodeEntities(value));
      if (++attributeCount > 128) throw new Error('HTML 单节点属性超过 128 个');
    }
    // 截断的标签不创造节点，交给文本路径容错处理。
    return undefined;
  }

  private static createEntities(): Map<string, string> {
    const entities = new Map<string, string>();
    const names: string[] = ['amp', 'lt', 'gt', 'quot', 'apos', 'nbsp', 'ensp', 'emsp', 'thinsp', 'copy', 'reg', 'trade', 'hellip', 'mdash', 'ndash', 'lsquo', 'rsquo', 'ldquo', 'rdquo', 'middot', 'bull', 'laquo', 'raquo', 'times', 'divide', 'cent', 'pound', 'yen', 'euro', 'AMP', 'LT', 'GT', 'QUOT'];
    const values: string[] = ['&', '<', '>', '"', "'", '\u00a0', '\u2002', '\u2003', '\u2009', '©', '®', '™', '…', '—', '–', '‘', '’', '“', '”', '·', '•', '«', '»', '×', '÷', '¢', '£', '¥', '€', '&', '<', '>', '"'];
    for (let index = 0; index < names.length; index++) entities.set(names[index], values[index]);
    return entities;
  }
}
