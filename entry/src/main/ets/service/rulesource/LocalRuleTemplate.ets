export class LocalRuleTemplate {
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
