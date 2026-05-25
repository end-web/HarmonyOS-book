/**
 * RuleAnalyzer - 规则分析器（平衡分组解析）
 *
 * 参考 Legado 的 RuleAnalyzer.kt 实现
 * 核心功能：按分隔符分割规则，但保持括号/引号内的内容不被分割
 *
 * 示例：
 * - splitRule("&&"): "$.a && $.b" -> ["$.a", "$.b"]
 * - splitRule("&&"): "($.a || $.b) && $.c" -> ["($.a || $.b)", "$.c"]
 * - splitRule("@"): "div.title@text" -> ["div.title", "text"]
 */

export class RuleAnalyzer {
  private rule: string;
  private pos: number = 0;
  private balanceCode: boolean; // true=代码平衡({}), false=普通平衡([])

  // 分割结果类型（用于 ||、&&、%% 判断）
  public elementsType: string = "";

  constructor(rule: string, balanceCode: boolean = false) {
    this.rule = rule;
    this.balanceCode = balanceCode;
  }

  /**
   * 去除规则前置的 @ 或空白符
   */
  trim(): void {
    this.rule = this.rule.replace(/^[@\s]+/, '');
  }

  /**
   * 分割规则（支持多个分隔符）
   * @param separators 分隔符数组，如 ["&&", "||", "%%"]
   * @returns 分割后的规则数组
   */
  splitRule(...separators: string[]): string[] {
    if (separators.length === 0) {
      return [this.rule];
    }

    // 记录第一个匹配的分隔符类型（用于 elementsType）
    this.elementsType = "";

    const result: string[] = [];
    let current = "";
    this.pos = 0;

    while (this.pos < this.rule.length) {
      // 检查是否匹配任一分隔符
      let matched = false;
      for (const sep of separators) {
        if (this.rule.substring(this.pos, this.pos + sep.length) === sep) {
          // 记录第一次匹配的分隔符类型
          if (!this.elementsType) {
            this.elementsType = sep;
          }
          // 只有相同类型的分隔符才分割
          if (this.elementsType === sep) {
            if (current.trim()) {
              result.push(current.trim());
            }
            current = "";
            this.pos += sep.length;
            matched = true;
            break;
          }
        }
      }

      if (matched) continue;

      // 处理括号平衡
      const char = this.rule[this.pos];

      if (char === '(' || char === '[' || char === '{') {
        const closing = char === '(' ? ')' : char === '[' ? ']' : '}';
        current += char;
        this.pos++;
        current += this.consumeUntil(closing);
        continue;
      }

      // 处理引号
      if (char === '"' || char === "'") {
        current += char;
        this.pos++;
        current += this.consumeString(char);
        continue;
      }

      // 普通字符
      current += char;
      this.pos++;
    }

    // 添加最后一段
    if (current.trim()) {
      result.push(current.trim());
    }

    return result.length > 0 ? result : [this.rule];
  }

  /**
   * 消费字符直到遇到闭合符号（处理嵌套）
   */
  private consumeUntil(closing: string): string {
    let content = "";
    let depth = 1;
    const opening = closing === ')' ? '(' : closing === ']' ? '[' : '{';

    while (this.pos < this.rule.length && depth > 0) {
      const char = this.rule[this.pos];

      // 处理嵌套引号
      if (char === '"' || char === "'") {
        content += char;
        this.pos++;
        content += this.consumeString(char);
        continue;
      }

      // 处理嵌套括号
      if (char === opening) {
        depth++;
      } else if (char === closing) {
        depth--;
        if (depth === 0) {
          content += char;
          this.pos++;
          break;
        }
      }

      content += char;
      this.pos++;
    }

    return content;
  }

  /**
   * 消费字符串（处理转义）
   */
  private consumeString(quote: string): string {
    let content = "";
    let escaped = false;

    while (this.pos < this.rule.length) {
      const char = this.rule[this.pos];

      if (escaped) {
        content += char;
        escaped = false;
        this.pos++;
        continue;
      }

      if (char === '\\') {
        content += char;
        escaped = true;
        this.pos++;
        continue;
      }

      if (char === quote) {
        content += char;
        this.pos++;
        break;
      }

      content += char;
      this.pos++;
    }

    return content;
  }

  /**
   * 替换规则中的内嵌部分（如 {{...}} 或 {$...}）
   * @param start 起始标记
   * @param end 结束标记
   * @param replacer 替换函数
   * @returns 替换后的规则
   */
  innerRule(start: string, end: string, replacer: (inner: string) => string): string {
    let result = "";
    let pos = 0;

    while (pos < this.rule.length) {
      const startIdx = this.rule.indexOf(start, pos);
      if (startIdx === -1) {
        result += this.rule.substring(pos);
        break;
      }

      // 添加起始标记之前的内容
      result += this.rule.substring(pos, startIdx);

      // 查找结束标记（考虑嵌套）
      let endIdx = startIdx + start.length;
      let depth = 1;

      while (endIdx < this.rule.length && depth > 0) {
        if (this.rule.substring(endIdx, endIdx + start.length) === start) {
          depth++;
          endIdx += start.length;
        } else if (this.rule.substring(endIdx, endIdx + end.length) === end) {
          depth--;
          if (depth === 0) {
            break;
          }
          endIdx += end.length;
        } else {
          endIdx++;
        }
      }

      if (depth === 0) {
        // 提取内嵌内容并替换
        const inner = this.rule.substring(startIdx + start.length, endIdx);
        result += replacer(inner);
        pos = endIdx + end.length;
      } else {
        // 未找到闭合标记，保持原样
        result += this.rule.substring(startIdx);
        break;
      }
    }

    return result;
  }
}

