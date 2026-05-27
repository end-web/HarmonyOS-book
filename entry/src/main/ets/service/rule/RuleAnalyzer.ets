/**
 * RuleAnalyzer - 规则分析器（对齐 Legado RuleAnalyzer.kt）
 *
 * 核心功能：按分隔符分割规则，精确跳过括号/引号/选择器内的内容
 * 区分代码平衡（JSON/JS 用 [] 主平衡 + {} 副平衡）和规则平衡（CSS/XPath 单对称）
 */

const ESC = '\\';

export class RuleAnalyzer {
  private queue: string;
  private pos: number = 0;
  private start: number = 0;
  private startX: number = 0;
  private rule: string[] = [];
  private step: number = 0;
  private code: boolean;

  public elementsType: string = "";

  constructor(data: string, code: boolean = false) {
    this.queue = data;
    this.code = code;
  }

  trim(): void {
    if (this.pos < this.queue.length &&
      (this.queue[this.pos] === '@' || this.queue.charCodeAt(this.pos) < 33)) {
      this.pos++;
      while (this.pos < this.queue.length &&
        (this.queue[this.pos] === '@' || this.queue.charCodeAt(this.pos) < 33)) {
        this.pos++;
      }
      this.start = this.pos;
      this.startX = this.pos;
    }
  }

  reSetPos(): void {
    this.pos = 0;
    this.startX = 0;
  }

  private consumeTo(seq: string): boolean {
    this.start = this.pos;
    const offset = this.queue.indexOf(seq, this.pos);
    if (offset !== -1) {
      this.pos = offset;
      return true;
    }
    return false;
  }

  private consumeToAny(...seq: string[]): boolean {
    let p = this.pos;
    while (p < this.queue.length) {
      for (const s of seq) {
        if (this.queue.substring(p, p + s.length) === s) {
          this.step = s.length;
          this.pos = p;
          return true;
        }
      }
      p++;
    }
    return false;
  }

  private findToAny(...chars: string[]): number {
    let p = this.pos;
    while (p < this.queue.length) {
      for (const c of chars) {
        if (this.queue[p] === c) return p;
      }
      p++;
    }
    return -1;
  }

  private chompCodeBalanced(open: string, close: string): boolean {
    let p = this.pos;
    let depth = 0;
    let otherDepth = 0;
    let inSingleQuote = false;
    let inDoubleQuote = false;

    while (p < this.queue.length) {
      const c = this.queue[p];
      p++;
      if (c !== ESC) {
        if (c === "'" && !inDoubleQuote) inSingleQuote = !inSingleQuote;
        else if (c === '"' && !inSingleQuote) inDoubleQuote = !inDoubleQuote;
        if (inSingleQuote || inDoubleQuote) continue;
        if (c === '[') depth++;
        else if (c === ']') depth--;
        else if (depth === 0) {
          if (c === open) otherDepth++;
          else if (c === close) otherDepth--;
        }
      } else {
        p++;
      }
      if (depth <= 0 && otherDepth <= 0) break;
    }

    if (depth > 0 || otherDepth > 0) return false;
    this.pos = p;
    return true;
  }

  private chompRuleBalanced(open: string, close: string): boolean {
    let p = this.pos;
    let depth = 0;
    let inSingleQuote = false;
    let inDoubleQuote = false;

    while (p < this.queue.length) {
      const c = this.queue[p];
      p++;
      if (c === "'" && !inDoubleQuote) inSingleQuote = !inSingleQuote;
      else if (c === '"' && !inSingleQuote) inDoubleQuote = !inDoubleQuote;
      if (inSingleQuote || inDoubleQuote) continue;
      if (c === ESC) { p++; continue; }
      if (c === open) depth++;
      else if (c === close) depth--;
      if (depth <= 0) break;
    }

    if (depth > 0) return false;
    this.pos = p;
    return true;
  }

  private chompBalanced(open: string, close: string): boolean {
    if (this.code) {
      return this.chompCodeBalanced(open, close);
    }
    return this.chompRuleBalanced(open, close);
  }

  splitRule(...split: string[]): string[] {
    this.rule = [];
    if (split.length === 0) return [this.queue];

    if (split.length === 1) {
      this.elementsType = split[0];
      if (!this.consumeTo(this.elementsType)) {
        this.rule.push(this.queue.substring(this.startX).trim());
        return this.rule;
      }
      this.step = this.elementsType.length;
    } else {
      if (!this.consumeToAny(...split)) {
        this.rule.push(this.queue.substring(this.startX).trim());
        return this.rule;
      }
    }

    // 主循环（合并首段/二段匹配逻辑）
    while (true) {
      const end = this.pos;
      this.pos = this.start;

      let resolved = false;
      while (!resolved) {
        const st = this.findToAny('[', '(');

        if (st === -1) {
          this.rule.push(this.queue.substring(this.startX, end).trim());
          if (!this.elementsType) {
            this.elementsType = this.queue.substring(end, end + this.step);
          }
          this.pos = end + this.step;
          while (this.consumeTo(this.elementsType)) {
            this.rule.push(this.queue.substring(this.start, this.pos).trim());
            this.pos += this.step;
          }
          this.rule.push(this.queue.substring(this.pos).trim());
          return this.rule;
        }

        if (st > end) {
          this.rule.push(this.queue.substring(this.startX, end).trim());
          if (!this.elementsType) {
            this.elementsType = this.queue.substring(end, end + this.step);
          }
          this.pos = end + this.step;

          while (this.consumeTo(this.elementsType) && this.pos < st) {
            this.rule.push(this.queue.substring(this.start, this.pos).trim());
            this.pos += this.step;
          }

          if (this.pos > st) {
            this.startX = this.start;
            resolved = true; // 继续外层 while 进入二段匹配
          } else {
            this.rule.push(this.queue.substring(this.pos).trim());
            return this.rule;
          }
          break;
        }

        this.pos = st;
        const next = this.queue[this.pos] === '[' ? ']' : ')';
        if (!this.chompBalanced(this.queue[this.pos], next)) {
          throw new Error(this.queue.substring(0, this.start) + ' 后未平衡');
        }

        if (end <= this.pos) {
          this.start = this.pos;
          // 继续从新位置查找下一个分隔符（多分隔符模式重新探测）
          let found: boolean;
          if (split.length === 1) {
            found = this.consumeTo(this.elementsType);
          } else {
            found = this.consumeToAny(...split);
          }
          if (!found) {
            this.rule.push(this.queue.substring(this.startX).trim());
            return this.rule;
          }
          resolved = true; // 找到新分隔位置，回到外层循环
        }
      }
    }
  }

  /**
   * 替换内嵌规则（代码平衡模式）
   * 如 {$.path} 用 chompCodeBalanced 提取平衡组
   */
  innerRuleBalanced(
    inner: string,
    startStep: number,
    endStep: number,
    fr: (rule: string) => string
  ): string {
    let st = '';
    while (this.consumeTo(inner)) {
      const posPre = this.pos;
      if (this.chompCodeBalanced('{', '}')) {
        const extracted = this.queue.substring(posPre + startStep, this.pos - endStep);
        const frv = fr(extracted);
        if (frv) {
          st += this.queue.substring(this.startX, posPre) + frv;
          this.startX = this.pos;
          continue;
        }
      }
      this.pos += inner.length;
    }
    if (this.startX === 0) return '';
    st += this.queue.substring(this.startX);
    return st;
  }

  /**
   * 替换内嵌规则（简单 start/end 匹配模式）
   * 如 {{expr}} 用 startStr="{{" endStr="}}" 提取
   */
  innerRule(
    startStr: string,
    endStr: string,
    fr: (rule: string) => string
  ): string {
    let st = '';
    while (this.consumeTo(startStr)) {
      this.pos += startStr.length;
      const posPre = this.pos;
      if (this.consumeTo(endStr)) {
        const extracted = this.queue.substring(posPre, this.pos);
        const frv = fr(extracted);
        st += this.queue.substring(this.startX, posPre - startStr.length) + frv;
        this.pos += endStr.length;
        this.startX = this.pos;
      }
    }
    if (this.startX === 0) return this.queue;
    st += this.queue.substring(this.startX);
    return st;
  }
}
