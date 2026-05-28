/**
 * AnalyzeByRegex - 正则表达式解析器（对齐 Legado AnalyzeByRegex.kt）
 *
 * 支持：
 *  - 单正则提取所有匹配（含捕获组）
 *  - 多正则链式（第一个正则的结果作为第二个的输入）
 *  - 分组引用（$0 全匹配, $1 第一组, ...）
 *  - 与 AnalyzeRule 的 Regex 模式配合
 */

export class AnalyzeByRegex {
  /**
   * 获取单个元素（第一个匹配的所有捕获组）
   * @param content 待匹配内容
   * @param regs 正则数组（链式）
   * @param index 取第几个匹配（0-based）
   * @returns 捕获组数组 [fullMatch, group1, group2, ...] 或 null
   */
  static getElement(content: string, regs: string[], index: number = 0): string[] | null {
    const elements = AnalyzeByRegex.getElements(content, regs);
    if (index >= 0 && index < elements.length) {
      return elements[index];
    }
    return elements.length > 0 ? elements[0] : null;
  }

  /**
   * 获取所有匹配元素
   * @param content 待匹配内容
   * @param regs 正则数组（链式应用）
   * @returns 二维数组，每个内层数组是一个匹配的所有捕获组
   */
  static getElements(content: string, regs: string[]): string[][] {
    if (!content || regs.length === 0) return [];

    let results: string[][] = [];

    // 第一个正则应用于原始内容
    const firstResults = AnalyzeByRegex.applyRegex(content, regs[0]);
    if (firstResults.length === 0) return [];

    if (regs.length === 1) {
      return firstResults;
    }

    // 后续正则链式应用：每个前一步的 fullMatch 作为下一步的输入
    results = firstResults;
    for (let i = 1; i < regs.length; i++) {
      const nextResults: string[][] = [];
      for (const prev of results) {
        const input = prev[0]; // fullMatch
        const sub = AnalyzeByRegex.applyRegex(input, regs[i]);
        for (const s of sub) nextResults.push(s);
      }
      results = nextResults;
      if (results.length === 0) break;
    }

    return results;
  }

  /**
   * 从内容中提取字符串（使用正则 + 替换模板）
   * 模板中 $0=全匹配, $1=第一组, ...
   */
  static getString(content: string, regex: string, template?: string): string {
    if (!content || !regex) return '';

    try {
      const re = new RegExp(regex, 'g');
      const match = re.exec(content);
      if (!match) return '';

      if (!template) {
        return match[1] !== undefined ? match[1] : match[0];
      }

      let result = template;
      for (let i = 0; i <= match.length; i++) {
        const group = match[i] !== undefined ? match[i] : '';
        result = result.replace(new RegExp('\\$' + i, 'g'), group);
      }
      return result;
    } catch {
      return '';
    }
  }

  /**
   * 获取所有匹配的字符串列表（使用模板格式化）
   */
  static getStringList(content: string, regex: string, template?: string): string[] {
    if (!content || !regex) return [];

    try {
      const re = new RegExp(regex, 'g');
      const results: string[] = [];
      let match = re.exec(content);
      while (match !== null) {
        if (!template) {
          results.push(match[1] !== undefined ? match[1] : match[0]);
        } else {
          let result = template;
          for (let i = 0; i <= match.length; i++) {
            const group = match[i] !== undefined ? match[i] : '';
            result = result.replace(new RegExp('\\$' + i, 'g'), group);
          }
          results.push(result);
        }
        match = re.exec(content);
      }
      return results;
    } catch {
      return [];
    }
  }

  private static applyRegex(content: string, pattern: string): string[][] {
    try {
      const re = new RegExp(pattern, 'g');
      const results: string[][] = [];
      let match = re.exec(content);
      while (match !== null) {
        const groups: string[] = [];
        for (let i = 0; i < match.length; i++) {
          groups.push(match[i] !== undefined ? match[i] : '');
        }
        results.push(groups);
        match = re.exec(content);
      }
      return results;
    } catch {
      return [];
    }
  }
}
