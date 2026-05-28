/**
 * JSONPath 实现（ArkTS 兼容，对齐 Legado JsonPath 能力）
 *
 * 支持：
 *  - $ 根节点
 *  - $.a.b 成员访问
 *  - $.a[0] / $.a[-1] 索引（支持负数）
 *  - $.a[0,1,2] 多索引
 *  - $.a[*] / $.a.* 通配
 *  - $..foo 递归下降
 *  - $['name'] / $["name"] 括号成员
 *  - $['a','b'] 多键
 *  - $.a[0:3] / $.a[1:] / $.a[:2] / $.a[::2] 切片
 *  - $.a[?(@.price<10)] 过滤表达式
 *  - $.a.length() 数组长度
 */

const TOK_ROOT = 0;
const TOK_RECURSE = 1;
const TOK_MEMBER = 2;
const TOK_INDEX = 3;
const TOK_WILDCARD = 4;
const TOK_SLICE = 5;
const TOK_FILTER = 6;
const TOK_MULTI_INDEX = 7;
const TOK_MULTI_MEMBER = 8;
const TOK_LENGTH = 9;

interface Tok {
  type: number;
  name?: string;
  idx?: number;
  indices?: number[];
  names?: string[];
  sliceStart?: number;
  sliceEnd?: number;
  sliceStep?: number;
  filterExpr?: string;
}

function isNameChar(c: string): boolean {
  return /[A-Za-z0-9_\-$@]/.test(c);
}

function tokenize(path: string): Tok[] {
  const tokens: Tok[] = [];
  let i = 0;
  if (path[0] === '$') {
    tokens.push({ type: TOK_ROOT });
    i++;
  }
  while (i < path.length) {
    const c = path[i];
    if (c === '.' && path[i + 1] === '.') {
      tokens.push({ type: TOK_RECURSE });
      i += 2;
      if (i < path.length && path[i] !== '.' && path[i] !== '[') {
        if (path[i] === '*') {
          tokens.push({ type: TOK_WILDCARD });
          i++;
        } else {
          let name = '';
          while (i < path.length && isNameChar(path[i])) {
            name += path[i];
            i++;
          }
          if (name === 'length()') {
            tokens.push({ type: TOK_LENGTH });
          } else if (name) {
            tokens.push({ type: TOK_MEMBER, name });
          }
        }
      }
    } else if (c === '.') {
      i++;
      if (i >= path.length) break;
      if (path[i] === '*') {
        tokens.push({ type: TOK_WILDCARD });
        i++;
      } else if (path.substring(i, i + 8) === 'length()') {
        tokens.push({ type: TOK_LENGTH });
        i += 8;
      } else {
        let name = '';
        while (i < path.length && isNameChar(path[i])) {
          name += path[i];
          i++;
        }
        if (name) tokens.push({ type: TOK_MEMBER, name });
      }
    } else if (c === '[') {
      i++;
      // 跳过空格
      while (i < path.length && path[i] === ' ') i++;

      if (path[i] === '*') {
        tokens.push({ type: TOK_WILDCARD });
        i++;
        if (i < path.length && path[i] === ']') i++;
      } else if (path[i] === '?') {
        // 过滤表达式 [?(@.xxx)]
        i++; // skip ?
        if (path[i] === '(') {
          i++; // skip (
          let depth = 1;
          let expr = '';
          while (i < path.length && depth > 0) {
            if (path[i] === '(') depth++;
            else if (path[i] === ')') {
              depth--;
              if (depth === 0) { i++; break; }
            }
            expr += path[i];
            i++;
          }
          tokens.push({ type: TOK_FILTER, filterExpr: expr });
        }
        if (i < path.length && path[i] === ']') i++;
      } else if (path[i] === "'" || path[i] === '"') {
        // 字符串键：可能是多键 ['a','b']
        const names: string[] = [];
        while (i < path.length && path[i] !== ']') {
          while (i < path.length && (path[i] === ' ' || path[i] === ',')) i++;
          if (path[i] === "'" || path[i] === '"') {
            const q = path[i];
            i++;
            let name = '';
            while (i < path.length && path[i] !== q) {
              if (path[i] === '\\' && i + 1 < path.length) {
                i++;
                name += path[i];
              } else {
                name += path[i];
              }
              i++;
            }
            i++; // skip closing quote
            names.push(name);
          } else {
            break;
          }
        }
        if (i < path.length && path[i] === ']') i++;
        if (names.length === 1) {
          tokens.push({ type: TOK_MEMBER, name: names[0] });
        } else if (names.length > 1) {
          tokens.push({ type: TOK_MULTI_MEMBER, names });
        }
      } else {
        // 数字：可能是索引、多索引、切片
        let content = '';
        let bracketDepth = 1;
        while (i < path.length && bracketDepth > 0) {
          if (path[i] === '[') bracketDepth++;
          else if (path[i] === ']') {
            bracketDepth--;
            if (bracketDepth === 0) break;
          }
          content += path[i];
          i++;
        }
        if (i < path.length && path[i] === ']') i++;

        content = content.trim();
        if (content.includes(':')) {
          // 切片 [start:end:step]
          const parts = content.split(':');
          const sliceStart = parts[0].trim() === '' ? undefined : parseInt(parts[0].trim(), 10);
          const sliceEnd = parts.length > 1 && parts[1].trim() !== '' ? parseInt(parts[1].trim(), 10) : undefined;
          const sliceStep = parts.length > 2 && parts[2].trim() !== '' ? parseInt(parts[2].trim(), 10) : 1;
          tokens.push({
            type: TOK_SLICE,
            sliceStart: sliceStart !== undefined && !Number.isNaN(sliceStart) ? sliceStart : undefined,
            sliceEnd: sliceEnd !== undefined && !Number.isNaN(sliceEnd) ? sliceEnd : undefined,
            sliceStep: sliceStep || 1,
          });
        } else if (content.includes(',')) {
          // 多索引 [0,1,2]
          const indices = content.split(',').map((s) => parseInt(s.trim(), 10)).filter((n) => !Number.isNaN(n));
          tokens.push({ type: TOK_MULTI_INDEX, indices });
        } else {
          const num = parseInt(content, 10);
          if (!Number.isNaN(num)) {
            tokens.push({ type: TOK_INDEX, idx: num });
          }
        }
      }
    } else {
      i++;
    }
  }
  return tokens;
}

function isObj(node: Object | null): boolean {
  return node !== null && typeof node === 'object' && !Array.isArray(node);
}

function walkAll(node: Object | null, out: Object[]): void {
  if (node === null || node === undefined) return;
  out.push(node);
  if (Array.isArray(node)) {
    const arr = node as Object[];
    for (const v of arr) walkAll(v, out);
  } else if (typeof node === 'object') {
    const obj = node as Record<string, Object>;
    for (const k of Object.keys(obj)) walkAll(obj[k], out);
  }
}

function walkForKey(node: Object | null, key: string, out: Object[]): void {
  if (node === null || node === undefined) return;
  if (Array.isArray(node)) {
    const arr = node as Object[];
    for (const v of arr) walkForKey(v, key, out);
  } else if (typeof node === 'object') {
    const obj = node as Record<string, Object>;
    if (obj[key] !== undefined) {
      out.push(obj[key]);
    }
    for (const k of Object.keys(obj)) {
      walkForKey(obj[k], key, out);
    }
  }
}

/**
 * 对数组执行切片操作
 */
function applySlice(arr: Object[], start?: number, end?: number, step?: number): Object[] {
  const len = arr.length;
  const s = step || 1;
  let startIdx = start !== undefined ? (start < 0 ? Math.max(0, len + start) : Math.min(start, len)) : 0;
  let endIdx = end !== undefined ? (end < 0 ? Math.max(0, len + end) : Math.min(end, len)) : len;

  if (s > 0) {
    const result: Object[] = [];
    for (let i = startIdx; i < endIdx; i += s) {
      result.push(arr[i]);
    }
    return result;
  } else {
    if (start === undefined) startIdx = len - 1;
    if (end === undefined) endIdx = -1;
    const result: Object[] = [];
    for (let i = startIdx; i > endIdx; i += s) {
      if (i >= 0 && i < len) result.push(arr[i]);
    }
    return result;
  }
}

/**
 * 简易过滤表达式求值
 * 支持：@.field, @.field==value, @.field>value, @.field<value,
 *       @.field>=value, @.field<=value, @.field!=value,
 *       @.field=~'/regex/'
 */
function evaluateFilter(items: Object[], expr: string): Object[] {
  const trimmed = expr.trim();
  const results: Object[] = [];

  for (const item of items) {
    if (evalFilterOnItem(item, trimmed)) {
      results.push(item);
    }
  }
  return results;
}

function evalFilterOnItem(item: Object, expr: string): boolean {
  if (!isObj(item) && !Array.isArray(item)) return false;

  // 支持 && 和 || 组合
  if (expr.includes('&&')) {
    const parts = expr.split('&&');
    return parts.every((p) => evalFilterOnItem(item, p.trim()));
  }
  if (expr.includes('||')) {
    const parts = expr.split('||');
    return parts.some((p) => evalFilterOnItem(item, p.trim()));
  }

  // 解析单个条件：@.field op value
  const condMatch = expr.match(/^@\.(\w[\w.]*)\s*(==|!=|>=|<=|>|<|=~)\s*(.+)$/);
  if (condMatch) {
    const fieldPath = condMatch[1];
    const op = condMatch[2];
    const rawValue = condMatch[3].trim();
    const fieldValue = getNestedValue(item, fieldPath);

    // 解析比较值
    let compareValue: Object;
    if ((rawValue.startsWith("'") && rawValue.endsWith("'")) ||
        (rawValue.startsWith('"') && rawValue.endsWith('"'))) {
      compareValue = rawValue.substring(1, rawValue.length - 1);
    } else if (rawValue === 'true') {
      compareValue = true;
    } else if (rawValue === 'false') {
      compareValue = false;
    } else if (rawValue === 'null') {
      compareValue = 'null';
    } else {
      const num = parseFloat(rawValue);
      compareValue = Number.isNaN(num) ? rawValue : num;
    }

    return compareValues(fieldValue, op, compareValue);
  }

  // 仅 @.field（存在性检查）
  const existsMatch = expr.match(/^@\.(\w[\w.]*)$/);
  if (existsMatch) {
    const val = getNestedValue(item, existsMatch[1]);
    return val !== undefined && val !== null;
  }

  // !@.field（不存在检查）
  const notExistsMatch = expr.match(/^!@\.(\w[\w.]*)$/);
  if (notExistsMatch) {
    const val = getNestedValue(item, notExistsMatch[1]);
    return val === undefined || val === null;
  }

  return true;
}

function getNestedValue(obj: Object, path: string): Object | undefined {
  const parts = path.split('.');
  let current: Object | undefined = obj;
  for (const part of parts) {
    if (current === undefined || current === null) return undefined;
    if (isObj(current)) {
      current = (current as Record<string, Object>)[part];
    } else {
      return undefined;
    }
  }
  return current;
}

function compareValues(fieldValue: Object | undefined, op: string, compareValue: Object): boolean {
  if (fieldValue === undefined || fieldValue === null) {
    if (op === '!=') return true;
    return false;
  }

  switch (op) {
    case '==':
      return String(fieldValue) === String(compareValue);
    case '!=':
      return String(fieldValue) !== String(compareValue);
    case '>': {
      const a = Number(fieldValue);
      const b = Number(compareValue);
      return !Number.isNaN(a) && !Number.isNaN(b) && a > b;
    }
    case '<': {
      const a = Number(fieldValue);
      const b = Number(compareValue);
      return !Number.isNaN(a) && !Number.isNaN(b) && a < b;
    }
    case '>=': {
      const a = Number(fieldValue);
      const b = Number(compareValue);
      return !Number.isNaN(a) && !Number.isNaN(b) && a >= b;
    }
    case '<=': {
      const a = Number(fieldValue);
      const b = Number(compareValue);
      return !Number.isNaN(a) && !Number.isNaN(b) && a <= b;
    }
    case '=~': {
      const regexStr = String(compareValue);
      const regexMatch = regexStr.match(/^\/(.+)\/([gimsuy]*)$/);
      if (regexMatch) {
        try {
          const regex = new RegExp(regexMatch[1], regexMatch[2]);
          return regex.test(String(fieldValue));
        } catch {
          return false;
        }
      }
      return false;
    }
    default:
      return false;
  }
}

export function jsonPath(data: Object, path: string): Object[] {
  const tokens = tokenize(path);
  let current: Object[] = [data];
  for (let ti = 0; ti < tokens.length; ti++) {
    const t = tokens[ti];
    if (t.type === TOK_ROOT) {
      continue;
    }
    if (t.type === TOK_RECURSE) {
      if (ti + 1 < tokens.length) {
        const nextToken = tokens[++ti];
        if (nextToken.type === TOK_MEMBER) {
          const filtered: Object[] = [];
          for (const node of current) {
            walkForKey(node, nextToken.name as string, filtered);
          }
          current = filtered;
        } else if (nextToken.type === TOK_WILDCARD) {
          const expanded: Object[] = [];
          for (const n of current) walkAll(n, expanded);
          current = expanded;
        } else {
          const expanded: Object[] = [];
          for (const n of current) walkAll(n, expanded);
          current = expanded;
          ti--;
        }
      } else {
        const expanded: Object[] = [];
        for (const n of current) walkAll(n, expanded);
        current = expanded;
      }
      continue;
    }
    if (t.type === TOK_WILDCARD) {
      const next: Object[] = [];
      for (const n of current) {
        if (Array.isArray(n)) {
          const arr = n as Object[];
          for (const v of arr) next.push(v);
        } else if (isObj(n)) {
          const obj = n as Record<string, Object>;
          for (const k of Object.keys(obj)) next.push(obj[k]);
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_MEMBER) {
      const next: Object[] = [];
      for (const n of current) {
        if (isObj(n)) {
          const obj = n as Record<string, Object>;
          const v = obj[t.name as string];
          if (v !== undefined) next.push(v);
        } else if (Array.isArray(n)) {
          // 对数组中的每个对象取成员
          const arr = n as Object[];
          for (const item of arr) {
            if (isObj(item)) {
              const obj = item as Record<string, Object>;
              const v = obj[t.name as string];
              if (v !== undefined) next.push(v);
            }
          }
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_INDEX) {
      const next: Object[] = [];
      for (const n of current) {
        if (Array.isArray(n)) {
          const arr = n as Object[];
          const idxRaw = t.idx as number;
          const idx = idxRaw >= 0 ? idxRaw : arr.length + idxRaw;
          if (idx >= 0 && idx < arr.length) next.push(arr[idx]);
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_MULTI_INDEX) {
      const next: Object[] = [];
      const indices = t.indices || [];
      for (const n of current) {
        if (Array.isArray(n)) {
          const arr = n as Object[];
          for (const idxRaw of indices) {
            const idx = idxRaw >= 0 ? idxRaw : arr.length + idxRaw;
            if (idx >= 0 && idx < arr.length) next.push(arr[idx]);
          }
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_MULTI_MEMBER) {
      const next: Object[] = [];
      const names = t.names || [];
      for (const n of current) {
        if (isObj(n)) {
          const obj = n as Record<string, Object>;
          for (const name of names) {
            const v = obj[name];
            if (v !== undefined) next.push(v);
          }
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_SLICE) {
      const next: Object[] = [];
      for (const n of current) {
        if (Array.isArray(n)) {
          const sliced = applySlice(n as Object[], t.sliceStart, t.sliceEnd, t.sliceStep);
          for (const v of sliced) next.push(v);
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_FILTER) {
      const next: Object[] = [];
      for (const n of current) {
        if (Array.isArray(n)) {
          const filtered = evaluateFilter(n as Object[], t.filterExpr || '');
          for (const v of filtered) next.push(v);
        }
      }
      current = next;
      continue;
    }
    if (t.type === TOK_LENGTH) {
      const next: Object[] = [];
      for (const n of current) {
        if (Array.isArray(n)) {
          next.push((n as Object[]).length);
        } else if (typeof n === 'string') {
          next.push((n as string).length);
        } else if (isObj(n)) {
          next.push(Object.keys(n as Record<string, Object>).length);
        }
      }
      current = next;
      continue;
    }
  }
  return current;
}

export function jsonPathFirst(data: Object, path: string): Object | null {
  const r = jsonPath(data, path);
  return r.length > 0 ? r[0] : null;
}

export function isJsonPath(rule: string): boolean {
  return rule.startsWith('$.') || rule.startsWith('$..') || rule === '$' || rule.startsWith('$[');
}
