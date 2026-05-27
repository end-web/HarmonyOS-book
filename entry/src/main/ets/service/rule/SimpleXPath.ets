/**
 * SimpleXPath - 简化版 XPath 求值器（ArkTS 兼容）
 *
 * 复用 SimpleCSSSelector 的 HTMLElement 数据结构,避免重复解析 HTML。
 *
 * 支持子集（覆盖书源常见用法）：
 *  - //tag           descendant 任意层级
 *  - /tag            直接子节点
 *  - //*             任意元素
 *  - //tag[@a='v']   属性等值
 *  - //tag[@a]       属性存在
 *  - //tag[contains(@a,'v')] / [contains(text(),'v')]
 *  - //tag[starts-with(@a,'v')]
 *  - //tag[N]        1-based 索引
 *  - //tag[last()]   最后一个
 *  - //tag[position()>N]
 *  - //tag/text()    文本节点
 *  - //tag/@attr     属性
 *  - //tag/string()  文本拼接（jsoup 兼容）
 *  - //tag1//tag2    多层后代
 *  - //tag1/tag2     直接子
 *
 * API：
 *  SimpleXPath.evaluateNodes(root, xpath)   -> HTMLElement[]
 *  SimpleXPath.evaluateString(root, xpath)  -> string | null
 *  SimpleXPath.evaluateStringList(root, xp) -> string[]
 */

import { HTMLElement, SimpleCSSSelector } from './SimpleCSSSelector';

interface Predicate {
  kind: 'index' | 'last' | 'position-gt' | 'position-lt' |
        'attr-exists' | 'attr-eq' | 'attr-ne' | 'attr-contains' | 'attr-starts' |
        'text-contains' | 'text-eq';
  index?: number;
  attr?: string;
  value?: string;
}

interface Step {
  axis: 'descendant' | 'child';
  test: string;            // tag 名 / '*' / 'text()' / '@attr' / 'string()'
  attrName?: string;       // 当 test = '@attr' 时
  predicates: Predicate[];
}

const TEXT_TEST_RE = /^text\(\s*\)$/i;
const STRING_TEST_RE = /^string\(\s*\)$/i;
const NODE_TEST_RE = /^node\(\s*\)$/i;

/* ─────────────── XPath 解析 ─────────────── */

function parseXPath(xpath: string): Step[] {
  let s = xpath.trim();
  if (s.startsWith('@xpath:')) s = s.substring(7);
  else if (s.startsWith('xpath:')) s = s.substring(6);
  if (s.startsWith('./')) s = s.substring(1); // 从当前节点
  // 不允许空规则
  if (!s) return [];

  const steps: Step[] = [];
  let i = 0;
  while (i < s.length) {
    // 跳过前导空格
    while (i < s.length && s[i] === ' ') i++;
    if (i >= s.length) break;

    // 轴：// 或 /
    let axis: 'descendant' | 'child' = 'child';
    if (s[i] === '/' && s[i + 1] === '/') {
      axis = 'descendant';
      i += 2;
    } else if (s[i] === '/') {
      axis = 'child';
      i += 1;
    } else if (steps.length === 0) {
      // 没有前导 / 时，按 descendant 处理（jsoup XPath 兼容）
      axis = 'descendant';
    }

    // 读取 test：直到遇到 / 或 [
    let testStart = i;
    let test = '';
    let attrName: string | undefined;
    if (s[i] === '@') {
      // /@attr
      i++;
      while (i < s.length && /[\w:-]/.test(s[i])) i++;
      attrName = s.substring(testStart + 1, i);
      test = '@attr';
    } else {
      while (i < s.length && s[i] !== '/' && s[i] !== '[') {
        i++;
      }
      test = s.substring(testStart, i).trim();
    }

    // 谓词：[...]
    const predicates: Predicate[] = [];
    while (i < s.length && s[i] === '[') {
      const end = matchBracket(s, i);
      if (end < 0) break;
      const inner = s.substring(i + 1, end).trim();
      const pred = parsePredicate(inner);
      if (pred) predicates.push(pred);
      i = end + 1;
    }

    if (test) {
      const step: Step = { axis, test, attrName, predicates };
      steps.push(step);
    }
  }

  return steps;
}

function matchBracket(s: string, start: number): number {
  let depth = 0;
  let inStr: string | null = null;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") {
      inStr = c;
      continue;
    }
    if (c === '[') depth++;
    else if (c === ']') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function parsePredicate(inner: string): Predicate | null {
  const trimmed = inner.trim();
  // last()
  if (/^last\(\s*\)$/i.test(trimmed)) {
    return { kind: 'last' };
  }
  // 纯数字 -> 1-based 索引
  if (/^\d+$/.test(trimmed)) {
    const n = parseInt(trimmed, 10);
    return { kind: 'index', index: n };
  }
  // position()>N / position()<N
  let m = trimmed.match(/^position\(\s*\)\s*([<>])\s*(\d+)$/i);
  if (m) {
    const op = m[1];
    return { kind: op === '>' ? 'position-gt' : 'position-lt', index: parseInt(m[2], 10) };
  }
  // contains(@attr,'v') / contains(text(),'v')
  m = trimmed.match(/^contains\(\s*(@[\w:-]+|text\(\s*\))\s*,\s*['"]([^'"]*)['"]\s*\)$/i);
  if (m) {
    const target = m[1];
    if (target.startsWith('@')) {
      return { kind: 'attr-contains', attr: target.substring(1), value: m[2] };
    }
    return { kind: 'text-contains', value: m[2] };
  }
  // starts-with(@attr,'v')
  m = trimmed.match(/^starts-with\(\s*@([\w:-]+)\s*,\s*['"]([^'"]*)['"]\s*\)$/i);
  if (m) {
    return { kind: 'attr-starts', attr: m[1], value: m[2] };
  }
  // @attr='v' / @attr="v" / @attr!="v"
  m = trimmed.match(/^@([\w:-]+)\s*(=|!=)\s*['"]([^'"]*)['"]$/);
  if (m) {
    return { kind: m[2] === '=' ? 'attr-eq' : 'attr-ne', attr: m[1], value: m[3] };
  }
  // 仅 @attr  -> 属性存在
  m = trimmed.match(/^@([\w:-]+)$/);
  if (m) {
    return { kind: 'attr-exists', attr: m[1] };
  }
  // text()='v'
  m = trimmed.match(/^text\(\s*\)\s*=\s*['"]([^'"]*)['"]$/i);
  if (m) {
    return { kind: 'text-eq', value: m[1] };
  }
  return null;
}

/* ─────────────── 节点遍历 ─────────────── */

function descendantElements(root: HTMLElement, tag: string): HTMLElement[] {
  const out: HTMLElement[] = [];
  const wantAny = tag === '*';
  const lower = tag.toLowerCase();
  const walk = (el: HTMLElement): void => {
    for (const c of el.children) {
      if (wantAny || c.tagName === lower) out.push(c);
      walk(c);
    }
  };
  walk(root);
  return out;
}

function directChildren(elements: HTMLElement[], tag: string): HTMLElement[] {
  const out: HTMLElement[] = [];
  const wantAny = tag === '*';
  const lower = tag.toLowerCase();
  for (const el of elements) {
    for (const c of el.children) {
      if (wantAny || c.tagName === lower) out.push(c);
    }
  }
  return out;
}

function elementText(el: HTMLElement): string {
  return SimpleCSSSelector.getText(el);
}

function applyPredicate(elements: HTMLElement[], pred: Predicate): HTMLElement[] {
  const len = elements.length;
  switch (pred.kind) {
    case 'index': {
      const ix = (pred.index ?? 1) - 1; // 1-based
      return ix >= 0 && ix < len ? [elements[ix]] : [];
    }
    case 'last':
      return len > 0 ? [elements[len - 1]] : [];
    case 'position-gt': {
      const n = pred.index ?? 0;
      const out: HTMLElement[] = [];
      for (let i = 0; i < len; i++) if (i + 1 > n) out.push(elements[i]);
      return out;
    }
    case 'position-lt': {
      const n = pred.index ?? 0;
      const out: HTMLElement[] = [];
      for (let i = 0; i < len; i++) if (i + 1 < n) out.push(elements[i]);
      return out;
    }
    case 'attr-exists':
      return elements.filter((e) => e.attributes[(pred.attr || '').toLowerCase()] !== undefined);
    case 'attr-eq':
      return elements.filter((e) => e.attributes[(pred.attr || '').toLowerCase()] === pred.value);
    case 'attr-ne':
      return elements.filter((e) => e.attributes[(pred.attr || '').toLowerCase()] !== pred.value);
    case 'attr-contains':
      return elements.filter((e) => {
        const v = e.attributes[(pred.attr || '').toLowerCase()];
        return v !== undefined && v.includes(pred.value || '');
      });
    case 'attr-starts':
      return elements.filter((e) => {
        const v = e.attributes[(pred.attr || '').toLowerCase()];
        return v !== undefined && v.startsWith(pred.value || '');
      });
    case 'text-contains':
      return elements.filter((e) => elementText(e).includes(pred.value || ''));
    case 'text-eq':
      return elements.filter((e) => elementText(e) === pred.value);
    default:
      return elements;
  }
}

/* ─────────────── 求值入口 ─────────────── */

/**
 * 返回字符串数组：
 *  - 末尾是 text() / string() -> 文本
 *  - 末尾是 @attr -> 属性值
 *  - 否则 -> 各元素的文本
 */
function evaluateAsStrings(root: HTMLElement, xpath: string): string[] {
  const steps = parseXPath(xpath);
  if (steps.length === 0) return [];

  // 末尾步骤是 @attr / text() / string() 时,前面的步骤负责取节点
  const last = steps[steps.length - 1];
  const isAttr = last.test === '@attr';
  const isText = TEXT_TEST_RE.test(last.test);
  const isString = STRING_TEST_RE.test(last.test);
  const valueSteps = isAttr || isText || isString ? steps.slice(0, -1) : steps;

  const nodes = walkSteps(root, valueSteps);

  if (isAttr) {
    const attr = (last.attrName || '').toLowerCase();
    const out: string[] = [];
    for (const n of nodes) {
      const v = n.attributes[attr];
      if (v !== undefined) out.push(v);
    }
    return applyPredicatesToStrings(out, last.predicates);
  }
  if (isText) {
    const out: string[] = [];
    for (const n of nodes) {
      for (const node of n.childNodes) {
        if (node.type === 'text' && node.text) {
          const t = node.text.replace(/\s+/g, ' ').trim();
          if (t) out.push(t);
        }
      }
    }
    return applyPredicatesToStrings(out, last.predicates);
  }
  if (isString) {
    return nodes.map((n) => elementText(n)).filter((s) => s.length > 0);
  }

  // 普通元素步骤：返回每个元素的文本
  return nodes.map((n) => elementText(n)).filter((s) => s.length > 0);
}

function applyPredicatesToStrings(arr: string[], preds: Predicate[]): string[] {
  let out = arr;
  for (const p of preds) {
    if (p.kind === 'index') {
      const ix = (p.index ?? 1) - 1;
      out = ix >= 0 && ix < out.length ? [out[ix]] : [];
    } else if (p.kind === 'last') {
      out = out.length > 0 ? [out[out.length - 1]] : [];
    }
  }
  return out;
}

function walkSteps(root: HTMLElement, steps: Step[]): HTMLElement[] {
  let elements: HTMLElement[] = [root];
  for (const step of steps) {
    let next: HTMLElement[];
    if (step.axis === 'descendant') {
      next = [];
      for (const el of elements) {
        for (const d of descendantElements(el, step.test)) next.push(d);
      }
    } else {
      next = directChildren(elements, step.test);
    }
    for (const p of step.predicates) {
      next = applyPredicate(next, p);
    }
    elements = next;
  }
  return elements;
}

/* ─────────────── 公开 API ─────────────── */

export class SimpleXPath {
  /** 求值返回元素节点（用于链式继续操作） */
  static evaluateNodes(root: HTMLElement, xpath: string): HTMLElement[] {
    const steps = parseXPath(xpath);
    if (steps.length === 0) return [];
    const last = steps[steps.length - 1];
    if (last.test === '@attr' || TEXT_TEST_RE.test(last.test) || STRING_TEST_RE.test(last.test)
        || NODE_TEST_RE.test(last.test)) {
      // 有终结符时，节点路径取前 N-1 步
      return walkSteps(root, steps.slice(0, -1));
    }
    return walkSteps(root, steps);
  }

  /** 求值返回字符串列表 */
  static evaluateStringList(root: HTMLElement, xpath: string): string[] {
    return evaluateAsStrings(root, xpath);
  }

  /** 单值；多个时用换行拼接 */
  static evaluateString(root: HTMLElement, xpath: string): string | null {
    const arr = evaluateAsStrings(root, xpath);
    if (arr.length === 0) return null;
    return arr.length === 1 ? arr[0] : arr.join('\n');
  }
}
