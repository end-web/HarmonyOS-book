export class LocalRuleTemplate {
  /** Operators outside JSONPath brackets belong to the bounded JavaScript evaluator. */
  static isJsonExpression(value: string): boolean {
    if (!value.startsWith('$.') && !value.startsWith('$[')) return false;
    let quote = '';
    let escaped = false;
    let brackets = 0;
    for (let index = 1; index < value.length; index++) {
      const char = value.charAt(index);
      if (escaped) { escaped = false; continue; }
      if (char === '\\') { escaped = true; continue; }
      if (quote) {
        if (char === quote) quote = '';
        continue;
      }
      if (char === '"' || char === "'" || char === '`') { quote = char; continue; }
      if (char === '[') { brackets++; continue; }
      if (char === ']') { brackets = Math.max(0, brackets - 1); continue; }
      if (brackets > 0) continue;
      // A wildcard is a path segment; hyphens remain valid in legacy property names.
      if (char === '*' && (value.charAt(index - 1) === '.' || value.charAt(index - 1) === '[')) continue;
      if ('?=<>!&|+*/%()'.includes(char) ||
        (char === '-' && new RegExp('\\s').test(value.charAt(index - 1)))) return true;
    }
    return false;
  }

  /** Find a template boundary without consuming braces inside strings or object literals. */
  static end(value: string, start: number): number {
    let quote = '';
    let escaped = false;
    let curly = 0;
    for (let index = start; index < value.length - 1; index++) {
      const char = value.charAt(index);
      if (escaped) { escaped = false; continue; }
      if (char === '\\') { escaped = true; continue; }
      if (quote) {
        if (char === quote) quote = '';
        continue;
      }
      if (char === '"' || char === "'" || char === '`') { quote = char; continue; }
      if (char === '{') curly++;
      if (char === '}') {
        if (curly === 0 && value.charAt(index + 1) === '}') return index;
        curly = Math.max(0, curly - 1);
      }
    }
    return -1;
  }
}
