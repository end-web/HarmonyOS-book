/**
 * 最小 JSONPath 子集（ArkTS 兼容）。
 * 支持：$, $.a.b, $.a[0], $.a[*], $.a.*, $..foo, $..docs.*, $['name']
 * 不支持：filter $[?(...)]、slice、union
 */

const TOK_ROOT = 0;
const TOK_RECURSE = 1;
const TOK_MEMBER = 2;
const TOK_INDEX = 3;
const TOK_WILDCARD = 4;

interface Tok {
  type: number;
  name?: string;
  idx?: number;
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
        let name = '';
        while (i < path.length && isNameChar(path[i])) {
          name += path[i];
          i++;
        }
        if (name) tokens.push({ type: TOK_MEMBER, name });
      }
    } else if (c === '.') {
      i++;
      if (path[i] === '*') {
        tokens.push({ type: TOK_WILDCARD });
        i++;
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
      if (path[i] === '*') {
        tokens.push({ type: TOK_WILDCARD });
        i++;
        if (path[i] === ']') i++;
      } else if (path[i] === "'" || path[i] === '"') {
        const q = path[i];
        i++;
        let name = '';
        while (i < path.length && path[i] !== q) {
          name += path[i];
          i++;
        }
        i++;
        if (path[i] === ']') i++;
        tokens.push({ type: TOK_MEMBER, name });
      } else {
        let num = '';
        while (i < path.length && /[0-9-]/.test(path[i])) {
          num += path[i];
          i++;
        }
        if (path[i] === ']') i++;
        tokens.push({ type: TOK_INDEX, idx: parseInt(num, 10) });
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
