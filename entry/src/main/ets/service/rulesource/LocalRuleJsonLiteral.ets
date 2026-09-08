/** Parses source-owned JSON-style literals without evaluating their contents. */
export class LocalRuleJsonLiteral {
  private readonly text: string;
  private index: number = 0;
  private nodes: number = 0;

  private constructor(text: string) {
    this.text = text;
  }

  static parse(text: string): Object | null {
    if (text.length > 4 * 1024 * 1024) throw new Error('书源数据超过 4 MiB');
    const parser = new LocalRuleJsonLiteral(text);
    const value = parser.value(0);
    parser.space();
    if (parser.index !== text.length) throw new Error('书源数据包含多余内容');
    return value;
  }

  private value(depth: number): Object | null {
    if (depth > 32 || ++this.nodes > 10000) throw new Error('书源数据嵌套或项目数量超过预算');
    this.space();
    const current = this.text.charAt(this.index);
    if (current === '{') return this.object(depth + 1);
    if (current === '[') return this.array(depth + 1);
    if (current === '"' || current === "'") return this.string();
    const tail = this.text.substring(this.index);
    const keyword = new RegExp('^(true|false|null)\\b').exec(tail);
    if (keyword !== null) {
      this.index += keyword[0].length;
      if (keyword[0] === 'null') return null;
      return keyword[0] === 'true';
    }
    const number = new RegExp('^[+-]?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)').exec(tail);
    if (number !== null) {
      const parsed = Number(number[0]);
      if (!Number.isFinite(parsed)) throw new Error('书源数据包含无效数字');
      this.index += number[0].length;
      return parsed;
    }
    throw new Error('书源数据只允许对象、数组和字面量');
  }

  private object(depth: number): Record<string, Object | null> {
    const result: Record<string, Object | null> = {};
    this.index++;
    this.space();
    while (this.text.charAt(this.index) !== '}') {
      const current = this.text.charAt(this.index);
      let key = '';
      if (current === '"' || current === "'") key = this.string();
      else {
        const identifier = new RegExp('^[A-Za-z_$][A-Za-z0-9_$-]*').exec(this.text.substring(this.index));
        if (identifier === null) throw new Error('书源数据字段名无效');
        key = identifier[0];
        this.index += key.length;
      }
      if (key === '__proto__') throw new Error('书源数据字段名无效');
      this.space();
      if (this.text.charAt(this.index++) !== ':') throw new Error('书源数据字段缺少冒号');
      result[key] = this.value(depth);
      this.space();
      if (this.text.charAt(this.index) === '}') break;
      if (this.text.charAt(this.index++) !== ',') throw new Error('书源数据字段缺少逗号');
      this.space();
    }
    this.index++;
    return result;
  }

  private array(depth: number): (Object | null)[] {
    const result: (Object | null)[] = [];
    this.index++;
    this.space();
    while (this.text.charAt(this.index) !== ']') {
      result.push(this.value(depth));
      this.space();
      if (this.text.charAt(this.index) === ']') break;
      if (this.text.charAt(this.index++) !== ',') throw new Error('书源数据项目缺少逗号');
      this.space();
    }
    this.index++;
    return result;
  }

  private string(): string {
    const quote = this.text.charAt(this.index++);
    let result = '';
    while (this.index < this.text.length) {
      const current = this.text.charAt(this.index++);
      if (current === quote) return result;
      if (current === '\n' || current === '\r') throw new Error('书源数据字符串未闭合');
      if (current !== '\\') {
        result += current;
        continue;
      }
      const escaped = this.text.charAt(this.index++);
      if (escaped === 'u' || escaped === 'x') {
        const count = escaped === 'u' ? 4 : 2;
        const hex = this.text.substring(this.index, this.index + count);
        if (hex.length !== count || !new RegExp('^[0-9a-f]+$', 'i').test(hex)) throw new Error('书源数据转义无效');
        result += String.fromCharCode(parseInt(hex, 16));
        this.index += count;
      } else if (escaped === 'n') result += '\n';
      else if (escaped === 'r') result += '\r';
      else if (escaped === 't') result += '\t';
      else if (escaped === 'b') result += '\b';
      else if (escaped === 'f') result += '\f';
      else if (escaped === 'v') result += '\u000b';
      else if (escaped === '0') result += '\u0000';
      else if (escaped === '\r') {
        if (this.text.charAt(this.index) === '\n') this.index++;
      } else if (escaped !== '\n') result += escaped;
    }
    throw new Error('书源数据字符串未闭合');
  }

  private space(): void {
    while (this.index < this.text.length) {
      if (new RegExp('\\s').test(this.text.charAt(this.index))) {
        this.index++;
      } else if (this.text.substring(this.index, this.index + 2) === '//') {
        const end = this.text.indexOf('\n', this.index + 2);
        this.index = end < 0 ? this.text.length : end + 1;
      } else if (this.text.substring(this.index, this.index + 2) === '/*') {
        const end = this.text.indexOf('*/', this.index + 2);
        if (end < 0) throw new Error('书源数据注释未闭合');
        this.index = end + 2;
      } else return;
    }
  }
}
