import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';

class LocalRuleJsonTokenKind {
  static readonly PROPERTY: number = 1;
  static readonly INDEX: number = 2;
  static readonly WILDCARD: number = 3;
  static readonly RECURSIVE_PROPERTY: number = 4;
  static readonly RECURSIVE_WILDCARD: number = 5;
  static readonly INDEX_UNION: number = 6;
  static readonly SLICE: number = 7;
  static readonly FILTER: number = 8;
}

class LocalRuleJsonToken {
  kind: number = LocalRuleJsonTokenKind.PROPERTY;
  key: string = '';
  index: number = 0;
  indexes: number[] = [];
  sliceStart: number = 0;
  sliceEnd: number = 0;
  sliceStep: number = 1;
  hasSliceStart: boolean = false;
  hasSliceEnd: boolean = false;
  filterExpression: string = '';
}

class LocalRuleJsonBudget {
  visited: number = 0;
}

class LocalRuleFilterResult {
  static readonly INVALID: number = -1;
  static readonly FALSE: number = 0;
  static readonly TRUE: number = 1;
}

class LocalRuleFilterValue {
  valid: boolean = false;
  exists: boolean = false;
  value: Object | null | undefined = undefined;
}

class LocalRuleFilterOperator {
  index: number = -1;
  value: string = '';
}

class LocalRuleDecodedString {
  valid: boolean = false;
  value: string = '';
}

class LocalRuleNumericValue {
  valid: boolean = false;
  value: number = 0;
}

class LocalRuleFilterContext {
  regexes: Map<string, RegExp> = new Map();
  invalidRegexes: Set<string> = new Set();
}

/** 受控 JSONPath：属性、数组、切片、过滤、通配和递归下降。 */
export class LocalRuleJsonPath {
  static isJsonPath(rule: string): boolean {
    const value = rule.trim();
    return value.startsWith('$') || value.startsWith('@.') ||
      value.toLowerCase().startsWith('@json:');
  }

  static queryPayload(payload: string, path: string): Object[] {
    try {
      const root = JSON.parse(payload) as Object;
      return LocalRuleJsonPath.query(root, path);
    } catch (_error) {
      return [];
    }
  }

  static query(root: Object, path: string): Object[] {
    try {
      const tokens = LocalRuleJsonPath.parse(path);
      if (tokens === undefined) return [];
      let current: Object[] = [root];
      for (const token of tokens) {
        const next: Object[] = [];
        const budget = new LocalRuleJsonBudget();
        for (const value of current) {
          LocalRuleJsonPath.applyToken(value, token, next, budget);
          if (next.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
        }
        current = next;
        if (current.length === 0) break;
      }
      return current.slice(0, LocalRuleExecutionLimits.MAX_JSON_NODES);
    } catch (_error) {
      return [];
    }
  }

  static valueToString(value: Object): string {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return '';
    }
  }

  private static parse(input: string): LocalRuleJsonToken[] | undefined {
    let path = input.trim();
    if (path.toLowerCase().startsWith('@json:')) path = path.substring(6).trim();
    if (path.startsWith('@.')) path = `$${path.substring(1)}`;
    if (!path.startsWith('$')) return undefined;

    const tokens: LocalRuleJsonToken[] = [];
    let index = 1;
    while (index < path.length) {
      const character = path.charAt(index);
      if (character === '.') {
        const recursive = index + 1 < path.length && path.charAt(index + 1) === '.';
        index += recursive ? 2 : 1;
        const start = index;
        while (index < path.length && path.charAt(index) !== '.' && path.charAt(index) !== '[') index++;
        const key = path.substring(start, index).trim();
        if (!key) return undefined;
        const token = new LocalRuleJsonToken();
        if (key === '*') {
          token.kind = recursive ? LocalRuleJsonTokenKind.RECURSIVE_WILDCARD :
            LocalRuleJsonTokenKind.WILDCARD;
        } else {
          token.kind = recursive ? LocalRuleJsonTokenKind.RECURSIVE_PROPERTY :
            LocalRuleJsonTokenKind.PROPERTY;
          token.key = key;
        }
        tokens.push(token);
        continue;
      }
      if (character === '[') {
        const end = LocalRuleJsonPath.findBracketEnd(path, index);
        if (end < 0) return undefined;
        const content = path.substring(index + 1, end).trim();
        const token = LocalRuleJsonPath.parseBracketToken(content);
        if (token === undefined) return undefined;
        tokens.push(token);
        index = end + 1;
        continue;
      }
      return undefined;
    }
    return tokens;
  }

  private static parseBracketToken(content: string): LocalRuleJsonToken | undefined {
    const token = new LocalRuleJsonToken();
    if (content === '*') {
      token.kind = LocalRuleJsonTokenKind.WILDCARD;
      return token;
    }
    if (content.startsWith('?(') && content.endsWith(')')) {
      const expression = content.substring(2, content.length - 1).trim();
      if (!expression || expression.length > LocalRuleExecutionLimits.MAX_FIELD_CHARS) return undefined;
      token.kind = LocalRuleJsonTokenKind.FILTER;
      token.filterExpression = expression;
      return token;
    }
    if (content.length >= 2 &&
      ((content.charAt(0) === '"' && content.charAt(content.length - 1) === '"') ||
      (content.charAt(0) === "'" && content.charAt(content.length - 1) === "'"))) {
      token.kind = LocalRuleJsonTokenKind.PROPERTY;
      token.key = LocalRuleJsonPath.unescapeProperty(content.substring(1, content.length - 1));
      return token;
    }
    if (content.includes(':')) {
      const parts = content.split(':');
      if (parts.length < 2 || parts.length > 3) return undefined;
      const startText = parts[0].trim();
      const endText = parts[1].trim();
      const stepText = parts.length === 3 ? parts[2].trim() : '';
      if (startText) {
        const start = LocalRuleJsonPath.parseInteger(startText);
        if (start === undefined) return undefined;
        token.sliceStart = start;
        token.hasSliceStart = true;
      }
      if (endText) {
        const end = LocalRuleJsonPath.parseInteger(endText);
        if (end === undefined) return undefined;
        token.sliceEnd = end;
        token.hasSliceEnd = true;
      }
      if (stepText) {
        const step = LocalRuleJsonPath.parseInteger(stepText);
        if (step === undefined || step === 0) return undefined;
        token.sliceStep = step;
      }
      token.kind = LocalRuleJsonTokenKind.SLICE;
      return token;
    }
    if (content.includes(',')) {
      const values = content.split(',');
      for (const value of values) {
        const parsed = Number(value.trim());
        if (!Number.isInteger(parsed)) return undefined;
        token.indexes.push(parsed);
      }
      token.kind = LocalRuleJsonTokenKind.INDEX_UNION;
      return token;
    }
    const parsed = Number(content);
    if (!Number.isInteger(parsed)) return undefined;
    token.kind = LocalRuleJsonTokenKind.INDEX;
    token.index = parsed;
    return token;
  }

  private static applyToken(value: Object, token: LocalRuleJsonToken,
    output: Object[], budget: LocalRuleJsonBudget): void {
    if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) return;
    if (token.kind === LocalRuleJsonTokenKind.PROPERTY) {
      LocalRuleJsonPath.appendProperty(value, token.key, output);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.INDEX) {
      LocalRuleJsonPath.appendIndex(value, token.index, output);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.INDEX_UNION) {
      for (const index of token.indexes) {
        LocalRuleJsonPath.appendIndex(value, index, output);
        if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.SLICE) {
      LocalRuleJsonPath.appendSlice(value, token, output);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.FILTER) {
      LocalRuleJsonPath.appendFilter(value, token.filterExpression, output, budget);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.WILDCARD) {
      LocalRuleJsonPath.appendChildren(value, output);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.RECURSIVE_PROPERTY) {
      LocalRuleJsonPath.appendRecursive(value, token.key, false, output, budget, 0);
      return;
    }
    if (token.kind === LocalRuleJsonTokenKind.RECURSIVE_WILDCARD) {
      LocalRuleJsonPath.appendRecursive(value, '', true, output, budget, 0);
    }
  }

  private static appendProperty(value: Object, key: string, output: Object[]): void {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return;
    const record = value as Record<string, Object>;
    const child = record[key];
    if (child !== undefined) output.push(child);
  }

  private static appendIndex(value: Object, rawIndex: number, output: Object[]): void {
    if (!Array.isArray(value)) return;
    const values = value as Object[];
    const index = rawIndex < 0 ? values.length + rawIndex : rawIndex;
    if (index >= 0 && index < values.length) output.push(values[index]);
  }

  private static appendSlice(value: Object, token: LocalRuleJsonToken, output: Object[]): void {
    if (!Array.isArray(value) || token.sliceStep === 0) return;
    const values = value as Object[];
    const length = values.length;
    const step = token.sliceStep;
    let start = token.hasSliceStart ? token.sliceStart : (step > 0 ? 0 : length - 1);
    let end = token.hasSliceEnd ? token.sliceEnd : (step > 0 ? length : -1);

    if (token.hasSliceStart && start < 0) start += length;
    if (token.hasSliceEnd && end < 0) end += length;
    if (step > 0) {
      start = Math.max(0, Math.min(length, start));
      end = Math.max(0, Math.min(length, end));
      for (let index = start; index < end; index += step) {
        output.push(values[index]);
        if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      return;
    }

    start = Math.max(-1, Math.min(length - 1, start));
    end = Math.max(-1, Math.min(length - 1, end));
    for (let index = start; index > end; index += step) {
      output.push(values[index]);
      if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
    }
  }

  private static appendFilter(value: Object, expression: string, output: Object[],
    budget: LocalRuleJsonBudget): void {
    const candidates: Object[] = Array.isArray(value) ? value as Object[] : [value];
    const context = new LocalRuleFilterContext();
    for (const candidate of candidates) {
      if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES ||
        budget.visited >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      budget.visited++;
      const result = LocalRuleJsonPath.evaluateFilter(candidate, expression, context);
      if (result === LocalRuleFilterResult.INVALID) return;
      if (result === LocalRuleFilterResult.TRUE) output.push(candidate);
    }
  }

  private static appendChildren(value: Object, output: Object[]): void {
    if (value === null || value === undefined || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      const values = value as Object[];
      for (const child of values) {
        output.push(child);
        if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      return;
    }
    const record = value as Record<string, Object>;
    const keys = Object.keys(record);
    for (const key of keys) {
      const child = record[key];
      if (child !== undefined) output.push(child);
      if (output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
    }
  }

  private static appendRecursive(value: Object, key: string, wildcard: boolean,
    output: Object[], budget: LocalRuleJsonBudget, depth: number): void {
    if (value === null || value === undefined || typeof value !== 'object') return;
    if (depth > LocalRuleExecutionLimits.MAX_JSON_DEPTH ||
      budget.visited >= LocalRuleExecutionLimits.MAX_JSON_NODES ||
      output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) return;
    budget.visited++;

    if (Array.isArray(value)) {
      const values = value as Object[];
      for (const child of values) {
        if (wildcard) output.push(child);
        LocalRuleJsonPath.appendRecursive(child, key, wildcard, output, budget, depth + 1);
        if (budget.visited >= LocalRuleExecutionLimits.MAX_JSON_NODES ||
          output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      return;
    }

    const record = value as Record<string, Object>;
    const keys = Object.keys(record);
    for (const childKey of keys) {
      const child = record[childKey];
      if (child === undefined) continue;
      if (wildcard || childKey === key) output.push(child);
      LocalRuleJsonPath.appendRecursive(child, key, wildcard, output, budget, depth + 1);
      if (budget.visited >= LocalRuleExecutionLimits.MAX_JSON_NODES ||
        output.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
    }
  }

  private static findBracketEnd(value: string, start: number): number {
    let quote = '';
    let escaped = false;
    let regex = false;
    let regexCharacterClass = false;
    let depth = 1;
    for (let index = start + 1; index < value.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (regex) {
        if (character === '[') regexCharacterClass = true;
        else if (character === ']') regexCharacterClass = false;
        else if (character === '/' && !regexCharacterClass) regex = false;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '/' && LocalRuleJsonPath.isFilterRegexStart(value, index)) {
        regex = true;
        regexCharacterClass = false;
        continue;
      }
      if (character === '[') depth++;
      if (character === ']') {
        depth--;
        if (depth === 0) return index;
      }
    }
    return -1;
  }

  private static parseInteger(value: string): number | undefined {
    if (!new RegExp('^-?\\d+$').test(value)) return undefined;
    const parsed = Number(value);
    return Number.isSafeInteger(parsed) ? parsed : undefined;
  }

  private static evaluateFilter(value: Object, expression: string,
    context: LocalRuleFilterContext, depth: number = 0): number {
    if (depth > LocalRuleExecutionLimits.MAX_JSON_DEPTH) return LocalRuleFilterResult.INVALID;
    const unwrapped = LocalRuleJsonPath.stripFilterParentheses(expression.trim());
    if (unwrapped === undefined || !unwrapped) return LocalRuleFilterResult.INVALID;

    const orParts = LocalRuleJsonPath.splitFilterLogical(unwrapped, '||');
    if (orParts === undefined) return LocalRuleFilterResult.INVALID;
    if (orParts.length > 1) {
      let matched = false;
      for (const part of orParts) {
        const result = LocalRuleJsonPath.evaluateFilter(value, part, context, depth + 1);
        if (result === LocalRuleFilterResult.INVALID) return result;
        if (result === LocalRuleFilterResult.TRUE) matched = true;
      }
      return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
    }

    const andParts = LocalRuleJsonPath.splitFilterLogical(unwrapped, '&&');
    if (andParts === undefined) return LocalRuleFilterResult.INVALID;
    if (andParts.length > 1) {
      let matched = true;
      for (const part of andParts) {
        const result = LocalRuleJsonPath.evaluateFilter(value, part, context, depth + 1);
        if (result === LocalRuleFilterResult.INVALID) return result;
        if (result !== LocalRuleFilterResult.TRUE) matched = false;
      }
      return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
    }

    if (unwrapped.startsWith('!')) {
      const result = LocalRuleJsonPath.evaluateFilter(value, unwrapped.substring(1), context, depth + 1);
      if (result === LocalRuleFilterResult.INVALID) return result;
      return result === LocalRuleFilterResult.TRUE ? LocalRuleFilterResult.FALSE : LocalRuleFilterResult.TRUE;
    }

    const operator = LocalRuleJsonPath.findFilterOperator(unwrapped);
    if (operator.index < 0) {
      const operand = LocalRuleJsonPath.resolveFilterValue(value, unwrapped);
      if (!operand.valid) return LocalRuleFilterResult.INVALID;
      return operand.exists ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
    }

    const leftText = unwrapped.substring(0, operator.index).trim();
    const rightText = unwrapped.substring(operator.index + operator.value.length).trim();
    if (!leftText || !rightText) return LocalRuleFilterResult.INVALID;
    const left = LocalRuleJsonPath.resolveFilterValue(value, leftText);
    if (!left.valid) return LocalRuleFilterResult.INVALID;
    if (operator.value === '=~') {
      return LocalRuleJsonPath.evaluateFilterRegex(left, rightText, context);
    }
    const right = LocalRuleJsonPath.parseFilterLiteral(rightText);
    if (!right.valid) return LocalRuleFilterResult.INVALID;
    return LocalRuleJsonPath.compareFilterValues(left, right, operator.value);
  }

  private static compareFilterValues(left: LocalRuleFilterValue, right: LocalRuleFilterValue,
    operator: string): number {
    if (!left.exists) return LocalRuleFilterResult.FALSE;
    const equality = operator === '==' || operator === '!=';
    if (left.value === null || right.value === null) {
      if (!equality) return LocalRuleFilterResult.FALSE;
      const equal = left.value === null && right.value === null;
      const matched = operator === '==' ? equal : !equal;
      return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
    }

    const leftNumber = LocalRuleJsonPath.toFilterNumber(left.value);
    const rightNumber = LocalRuleJsonPath.toFilterNumber(right.value);
    if (leftNumber.valid && rightNumber.valid) {
      return LocalRuleJsonPath.compareFilterNumbers(leftNumber.value, rightNumber.value, operator);
    }
    const leftString = LocalRuleJsonPath.filterValueToString(left.value);
    const rightString = LocalRuleJsonPath.filterValueToString(right.value);
    let matched = false;
    if (operator === '==') matched = leftString === rightString;
    else if (operator === '!=') matched = leftString !== rightString;
    else if (operator === '>') matched = leftString > rightString;
    else if (operator === '<') matched = leftString < rightString;
    else if (operator === '>=') matched = leftString >= rightString;
    else if (operator === '<=') matched = leftString <= rightString;
    else return LocalRuleFilterResult.INVALID;
    return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
  }

  private static compareFilterNumbers(left: number, right: number, operator: string): number {
    let matched = false;
    if (operator === '==') matched = left === right;
    else if (operator === '!=') matched = left !== right;
    else if (operator === '>') matched = left > right;
    else if (operator === '<') matched = left < right;
    else if (operator === '>=') matched = left >= right;
    else if (operator === '<=') matched = left <= right;
    else return LocalRuleFilterResult.INVALID;
    return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
  }

  private static evaluateFilterRegex(left: LocalRuleFilterValue, literal: string,
    context: LocalRuleFilterContext): number {
    if (!left.exists) return LocalRuleFilterResult.FALSE;
    if (!literal.startsWith('/')) return LocalRuleFilterResult.INVALID;
    const end = LocalRuleJsonPath.findRegexLiteralEnd(literal);
    if (end <= 0) return LocalRuleFilterResult.INVALID;
    const pattern = literal.substring(1, end);
    const rawFlags = literal.substring(end + 1).trim();
    if (pattern.length > 2048 || !new RegExp('^[gimsuy]*$').test(rawFlags)) {
      return LocalRuleFilterResult.INVALID;
    }
    const uniqueFlags = new Set<string>();
    for (let index = 0; index < rawFlags.length; index++) {
      const flag = rawFlags.charAt(index);
      if (uniqueFlags.has(flag)) return LocalRuleFilterResult.INVALID;
      uniqueFlags.add(flag);
    }
    const flags = rawFlags.split('g').join('');
    const cacheKey = `${pattern}\n${flags}`;
    if (context.invalidRegexes.has(cacheKey)) return LocalRuleFilterResult.INVALID;
    let regex = context.regexes.get(cacheKey);
    if (regex === undefined) {
      try {
        regex = new RegExp(pattern, flags);
        context.regexes.set(cacheKey, regex);
      } catch (_error) {
        context.invalidRegexes.add(cacheKey);
        return LocalRuleFilterResult.INVALID;
      }
    }
    regex.lastIndex = 0;
    const matched = regex.test(LocalRuleJsonPath.filterValueToString(left.value));
    regex.lastIndex = 0;
    return matched ? LocalRuleFilterResult.TRUE : LocalRuleFilterResult.FALSE;
  }

  private static resolveFilterValue(value: Object, rawPath: string): LocalRuleFilterValue {
    const result = new LocalRuleFilterValue();
    let path = rawPath.trim();
    if (path === '@') path = '$';
    else if (path.startsWith('@.') || path.startsWith('@[')) path = `$${path.substring(1)}`;
    if (!path.startsWith('$')) return result;
    const tokens = LocalRuleJsonPath.parse(path);
    if (tokens === undefined || tokens.length > LocalRuleExecutionLimits.MAX_JSON_DEPTH) return result;

    let current: Object[] = [value];
    for (const token of tokens) {
      if (token.kind !== LocalRuleJsonTokenKind.PROPERTY && token.kind !== LocalRuleJsonTokenKind.INDEX) {
        return result;
      }
      const next: Object[] = [];
      for (const currentValue of current) {
        if (token.kind === LocalRuleJsonTokenKind.PROPERTY) {
          LocalRuleJsonPath.appendProperty(currentValue, token.key, next);
        } else {
          LocalRuleJsonPath.appendIndex(currentValue, token.index, next);
        }
        if (next.length >= LocalRuleExecutionLimits.MAX_JSON_NODES) break;
      }
      current = next;
      if (current.length === 0) break;
    }
    result.valid = true;
    if (current.length > 0) {
      result.exists = true;
      result.value = current[0];
    }
    return result;
  }

  private static parseFilterLiteral(text: string): LocalRuleFilterValue {
    const result = new LocalRuleFilterValue();
    const value = text.trim();
    if (!value) return result;
    const first = value.charAt(0);
    if (first === '"' || first === "'") {
      if (value.length < 2 || value.charAt(value.length - 1) !== first) return result;
      const decoded = LocalRuleJsonPath.decodeFilterString(value.substring(1, value.length - 1));
      if (!decoded.valid) return result;
      result.valid = true;
      result.exists = true;
      result.value = decoded.value;
      return result;
    }
    if (value === 'true' || value === 'false') {
      result.valid = true;
      result.exists = true;
      result.value = value === 'true';
      return result;
    }
    if (value === 'null') {
      result.valid = true;
      result.exists = true;
      result.value = null;
      return result;
    }
    if (new RegExp('^-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?$').test(value)) {
      const number = Number(value);
      if (!Number.isFinite(number)) return result;
      result.valid = true;
      result.exists = true;
      result.value = number;
      return result;
    }
    if (!new RegExp('^[^&|=!<>\\[\\]()/]+$').test(value)) return result;
    result.valid = true;
    result.exists = true;
    result.value = value;
    return result;
  }

  private static decodeFilterString(value: string): LocalRuleDecodedString {
    const result = new LocalRuleDecodedString();
    let output = '';
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      if (character !== '\\') {
        output += character;
        index++;
        continue;
      }
      if (index + 1 >= value.length) return result;
      const escaped = value.charAt(index + 1);
      if (escaped === 'n') output += '\n';
      else if (escaped === 'r') output += '\r';
      else if (escaped === 't') output += '\t';
      else if (escaped === 'b') output += '\b';
      else if (escaped === 'f') output += '\f';
      else if (escaped === 'u') {
        if (index + 5 >= value.length) return result;
        const hex = value.substring(index + 2, index + 6);
        if (!new RegExp('^[0-9A-Fa-f]{4}$').test(hex)) return result;
        output += String.fromCharCode(Number.parseInt(hex, 16));
        index += 6;
        continue;
      } else output += escaped;
      index += 2;
    }
    result.valid = true;
    result.value = output;
    return result;
  }

  private static toFilterNumber(value: Object | null | undefined): LocalRuleNumericValue {
    const result = new LocalRuleNumericValue();
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) return result;
      result.valid = true;
      result.value = value;
      return result;
    }
    if (typeof value !== 'string' ||
      !new RegExp('^-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?$').test(value.trim())) return result;
    const number = Number(value);
    if (!Number.isFinite(number)) return result;
    result.valid = true;
    result.value = number;
    return result;
  }

  private static filterValueToString(value: Object | null | undefined): string {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return '';
    }
  }

  private static findFilterOperator(expression: string): LocalRuleFilterOperator {
    const result = new LocalRuleFilterOperator();
    let quote = '';
    let escaped = false;
    let parentheses = 0;
    let brackets = 0;
    for (let index = 0; index < expression.length; index++) {
      const character = expression.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '(') parentheses++;
      else if (character === ')') parentheses--;
      else if (character === '[') brackets++;
      else if (character === ']') brackets--;
      if (parentheses !== 0 || brackets !== 0) continue;
      const pair = expression.substring(index, index + 2);
      if (pair === '=~' || pair === '==' || pair === '!=' || pair === '>=' || pair === '<=') {
        result.index = index;
        result.value = pair;
        return result;
      }
      if (character === '>' || character === '<') {
        result.index = index;
        result.value = character;
        return result;
      }
    }
    return result;
  }

  private static splitFilterLogical(expression: string, delimiter: string): string[] | undefined {
    const parts: string[] = [];
    let start = 0;
    let quote = '';
    let escaped = false;
    let regex = false;
    let regexCharacterClass = false;
    let parentheses = 0;
    let brackets = 0;
    for (let index = 0; index < expression.length; index++) {
      const character = expression.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (regex) {
        if (character === '[') regexCharacterClass = true;
        else if (character === ']') regexCharacterClass = false;
        else if (character === '/' && !regexCharacterClass) regex = false;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '/' && LocalRuleJsonPath.isFilterRegexStart(expression, index)) {
        regex = true;
        regexCharacterClass = false;
        continue;
      }
      if (character === '(') parentheses++;
      else if (character === ')') {
        parentheses--;
        if (parentheses < 0) return undefined;
      } else if (character === '[') brackets++;
      else if (character === ']') {
        brackets--;
        if (brackets < 0) return undefined;
      }
      if (parentheses === 0 && brackets === 0 &&
        expression.substring(index, index + delimiter.length) === delimiter) {
        const part = expression.substring(start, index).trim();
        if (!part) return undefined;
        parts.push(part);
        start = index + delimiter.length;
        index += delimiter.length - 1;
      }
    }
    if (quote || regex || escaped || parentheses !== 0 || brackets !== 0) return undefined;
    const last = expression.substring(start).trim();
    if (!last) return undefined;
    parts.push(last);
    return parts;
  }

  private static stripFilterParentheses(expression: string): string | undefined {
    let value = expression.trim();
    while (value.startsWith('(')) {
      const end = LocalRuleJsonPath.findClosingParenthesis(value, 0);
      if (end < 0) return undefined;
      if (end !== value.length - 1) break;
      value = value.substring(1, value.length - 1).trim();
      if (!value) return undefined;
    }
    return value;
  }

  private static findClosingParenthesis(expression: string, start: number): number {
    let depth = 0;
    let quote = '';
    let escaped = false;
    let regex = false;
    let regexCharacterClass = false;
    for (let index = start; index < expression.length; index++) {
      const character = expression.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (regex) {
        if (character === '[') regexCharacterClass = true;
        else if (character === ']') regexCharacterClass = false;
        else if (character === '/' && !regexCharacterClass) regex = false;
        continue;
      }
      if (quote) {
        if (character === quote) quote = '';
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '/' && LocalRuleJsonPath.isFilterRegexStart(expression, index)) {
        regex = true;
        regexCharacterClass = false;
        continue;
      }
      if (character === '(') depth++;
      else if (character === ')') {
        depth--;
        if (depth === 0) return index;
        if (depth < 0) return -1;
      }
    }
    return -1;
  }

  private static findRegexLiteralEnd(value: string): number {
    let escaped = false;
    let characterClass = false;
    for (let index = 1; index < value.length; index++) {
      const character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\') {
        escaped = true;
        continue;
      }
      if (character === '[') characterClass = true;
      else if (character === ']') characterClass = false;
      else if (character === '/' && !characterClass) return index;
    }
    return -1;
  }

  private static isFilterRegexStart(value: string, slashIndex: number): boolean {
    let cursor = slashIndex - 1;
    while (cursor >= 0 && new RegExp('\\s').test(value.charAt(cursor))) cursor--;
    return cursor >= 1 && value.charAt(cursor) === '~' && value.charAt(cursor - 1) === '=';
  }

  private static unescapeProperty(value: string): string {
    return value.replace(new RegExp('\\\\([\\\\"\'])', 'g'), '$1');
  }
}
