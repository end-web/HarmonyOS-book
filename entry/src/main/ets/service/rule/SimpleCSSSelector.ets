/**
 * SimpleCSSSelector - 简化版 CSS 选择器（ArkTS 兼容）
 *
 * 支持：
 *  - 标签 / #id / .class / [attr] / [attr=value]
 *  - 后代(空格) / 直接子(>)
 *  - :nth-child(n) / :nth-last-child(n) / :first-child / :last-child
 *  - Legado 自定义前缀：class.X / id.X / tag.X / text.X / children
 *  - Legado 索引语法（匹配后过滤，0-based）：
 *      sel.N          取第 N 个
 *      sel!N          排除第 N 个
 *      sel[a:b]       区间（左闭右开，支持负数）
 *      sel[a:b:step]  步长
 *      sel[a,b,c]     多选
 *      sel[!a,b]      排除多选
 */

export interface HTMLElement {
  tagName: string;
  attributes: Record<string, string>;
  children: HTMLElement[];
  textContent: string;
  parent?: HTMLElement;
  childNodes: ChildNode[];
}

export interface ChildNode {
  type: 'text' | 'element';
  text?: string;
  element?: HTMLElement;
}

export interface ParsedSelector {
  tagName?: string;
  className?: string;
  id?: string;
  attrName?: string;
  attrValue?: string;
  attrOp?: string; // = / *= / ^= / $= / ~=
  containsText?: string; // text.xxx / :contains(xxx)
  pseudo?: string; // first-child / last-child / nth-child(n) / nth-last-child(n)
  pseudoArg?: number;
  childrenOnly?: boolean; // children 关键字
}

interface SplitIndexerResult {
  base: string;
  index?: IndexSpec;
}

interface StringBuffer {
  buf: string;
}

const SELF_CLOSING_TAGS: string[] = [
  'img', 'br', 'hr', 'input', 'meta', 'link',
  'area', 'base', 'col', 'embed', 'source', 'track', 'wbr',
];

function isSelfClosing(tagName: string): boolean {
  return SELF_CLOSING_TAGS.includes(tagName.toLowerCase());
}

function parseAttributes(attrsStr: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  // 支持双引号、单引号、无引号
  const attrRegex = /([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  let match: RegExpExecArray | null = attrRegex.exec(attrsStr);
  while (match !== null) {
    const name = match[1];
    const value = match[2] !== undefined ? match[2]
      : match[3] !== undefined ? match[3]
      : match[4] !== undefined ? match[4] : '';
    attrs[name.toLowerCase()] = value;
    match = attrRegex.exec(attrsStr);
  }
  return attrs;
}

function parseHTMLImpl(html: string): HTMLElement {
  const root: HTMLElement = {
    tagName: 'root',
    attributes: {},
    children: [],
    textContent: '',
    childNodes: [],
  };

  const stack: HTMLElement[] = [root];
  // 跳过 <!DOCTYPE>、<!-- -->、<script>、<style>
  // 这里用更稳的正则:也兼容自闭合 <br />
  const tagRegex = /<!--[\s\S]*?-->|<!doctype[^>]*>|<(\/?)([\w:-]+)([^>]*)\/?>/gi;
  let lastIndex = 0;
  let match: RegExpExecArray | null = tagRegex.exec(html);

  while (match !== null) {
    const matched = match[0];
    if (matched.startsWith('<!--') || matched.toLowerCase().startsWith('<!doctype')) {
      lastIndex = tagRegex.lastIndex;
      match = tagRegex.exec(html);
      continue;
    }

    const isClosing = match[1];
    const tagName = (match[2] || '').toLowerCase();
    const attrsStr = match[3] || '';

    if (match.index > lastIndex) {
      const text = html.substring(lastIndex, match.index);
      const trimmed = text.replace(/\s+/g, ' ');
      if (trimmed.trim() && stack.length > 0) {
        const parent = stack[stack.length - 1];
        parent.textContent += trimmed;
        parent.childNodes.push({ type: 'text', text: trimmed });
      }
    }

    if (isClosing) {
      // 关闭最近的同名标签（容错:遇到不匹配则不弹栈）
      for (let i = stack.length - 1; i > 0; i--) {
        if (stack[i].tagName === tagName) {
          stack.length = i;
          break;
        }
      }
    } else if (tagName === 'script' || tagName === 'style') {
      // 跳过 script/style 内容
      const closeTag = `</${tagName}`;
      const endIdx = html.toLowerCase().indexOf(closeTag, tagRegex.lastIndex);
      if (endIdx >= 0) {
        const closeEnd = html.indexOf('>', endIdx);
        if (closeEnd > 0) {
          tagRegex.lastIndex = closeEnd + 1;
        }
      }
    } else {
      const element: HTMLElement = {
        tagName,
        attributes: parseAttributes(attrsStr),
        children: [],
        textContent: '',
        parent: stack[stack.length - 1],
        childNodes: [],
      };
      const parent = stack[stack.length - 1];
      parent.children.push(element);
      parent.childNodes.push({ type: 'element', element });
      // 自闭合或末尾带 / 的不入栈
      const selfClose = isSelfClosing(tagName) || matched.endsWith('/>');
      if (!selfClose) {
        stack.push(element);
      }
    }

    lastIndex = tagRegex.lastIndex;
    match = tagRegex.exec(html);
  }

  if (lastIndex < html.length && stack.length > 0) {
    const text = html.substring(lastIndex);
    const trimmed = text.replace(/\s+/g, ' ');
    if (trimmed.trim()) {
      const parent = stack[stack.length - 1];
      parent.textContent += trimmed;
      parent.childNodes.push({ type: 'text', text: trimmed });
    }
  }

  return root;
}

/* ───────────────── selector parsing ───────────────── */

interface IndexSpec {
  picks?: number[];         // 单选/多选索引（0-based,可负）
  excludes?: number[];      // 排除索引
  range?: [number, number, number]; // [start,end,step]
}

interface SegmentSpec {
  baseSelector: string;     // 去掉 indexer 后的纯 CSS（已 normalize）
  index?: IndexSpec;
  childrenOnly?: boolean;   // children 关键字
  combinator: string;       // ' ' | '>'
}

/**
 * 拆出末尾 indexer:.N / !N / [...]
 * 返回 [纯选择器, indexSpec]
 */
function splitIndexer(selector: string): SplitIndexerResult {
  let s = selector.trim();

  // 1) [a,b,c] / [!a,b] / [a:b] / [a:b:step]
  // 这里仅处理"末尾"的 [...]；属性选择器 [attr] 保留
  // 区分:属性选择器的内容包含字母(=非数字开头),索引器的内容只允许数字/逗号/冒号/!/-/空白
  const bracketAt = s.lastIndexOf('[');
  if (bracketAt > 0 && s.endsWith(']')) {
    const inside = s.substring(bracketAt + 1, s.length - 1);
    if (/^[!\-\d:,\s]+$/.test(inside)) {
      const base = s.substring(0, bracketAt);
      const spec = parseIndexBracket(inside);
      if (spec) {
        const result: SplitIndexerResult = { base, index: spec };
        return result;
      }
    }
  }

  // 2) !N 或 !N,M  排除
  const excludeMatch = s.match(/!(-?\d+(?:,-?\d+)*)\s*$/);
  if (excludeMatch) {
    const nums = excludeMatch[1].split(',').map((n) => parseInt(n, 10));
    const indexSpec: IndexSpec = { excludes: nums };
    const result: SplitIndexerResult = {
      base: s.substring(0, s.length - excludeMatch[0].length),
      index: indexSpec
    };
    return result;
  }

  // 3) .N 索引(纯数字结尾,且前面是合法标识符或 ] 或 ))
  // 例：a.novelname.0 → 取所有 .novelname 中第 0 个
  const dotIndexMatch = s.match(/\.(-?\d+)\s*$/);
  if (dotIndexMatch) {
    const idx = parseInt(dotIndexMatch[1], 10);
    const indexSpec: IndexSpec = { picks: [idx] };
    const result: SplitIndexerResult = {
      base: s.substring(0, s.length - dotIndexMatch[0].length),
      index: indexSpec
    };
    return result;
  }

  const noIndexResult: SplitIndexerResult = { base: s };
  return noIndexResult;
}

function parseIndexBracket(inside: string): IndexSpec | undefined {
  const trimmed = inside.trim();
  if (!trimmed) return undefined;

  // [a:b] 或 [a:b:step]
  if (trimmed.includes(':')) {
    const parts = trimmed.split(':').map((p) => p.trim());
    if (parts.length === 2 || parts.length === 3) {
      const start = parts[0] === '' ? 0 : parseInt(parts[0], 10);
      const end = parts[1] === '' ? Number.MAX_SAFE_INTEGER : parseInt(parts[1], 10);
      const step = parts.length === 3 && parts[2] !== '' ? parseInt(parts[2], 10) : 1;
      if (!Number.isNaN(start) && !Number.isNaN(end) && !Number.isNaN(step)) {
        return { range: [start, end, step] };
      }
    }
  }

  // [!a,b,c] 排除
  if (trimmed.startsWith('!')) {
    const nums = trimmed.substring(1).split(',').map((n) => parseInt(n.trim(), 10)).filter((n) => !Number.isNaN(n));
    if (nums.length > 0) return { excludes: nums };
  }

  // [a,b,c]
  const nums = trimmed.split(',').map((n) => parseInt(n.trim(), 10)).filter((n) => !Number.isNaN(n));
  if (nums.length > 0) return { picks: nums };

  return undefined;
}

/**
 * Legado 关键字前缀归一化(单段内):
 *   class.X → .X
 *   id.X    → #X
 *   tag.X   → X
 *   text.X  → :contains(X)（自定义,匹配时单独处理）
 *   children → 仅取直接子(在 parseSegments 中识别)
 */
function normalizeLegadoTokens(seg: string): string {
  let s = seg.trim();
  if (s === 'children') return s; // 占位
  // 处理"前缀.值"形式，仅识别这三种关键字
  s = s.replace(/^class\.([\w-]+)/, '.$1');
  s = s.replace(/^id\.([\w-]+)/, '#$1');
  s = s.replace(/^tag\.([\w-]+)/, '$1');
  return s;
}

function parseSelector(selector: string): ParsedSelector {
  const result: ParsedSelector = {};
  let remaining = normalizeLegadoTokens(selector);

  // text.xxx 形式 → containsText
  const textMatch = remaining.match(/^text\.(.+)$/);
  if (textMatch) {
    result.containsText = textMatch[1];
    return result;
  }
  // :contains(xxx)
  const containsMatch = remaining.match(/:contains\(([^)]+)\)/);
  if (containsMatch) {
    result.containsText = containsMatch[1];
    remaining = remaining.replace(containsMatch[0], '');
  }

  const nthMatch = remaining.match(/:nth-child\((\d+)\)/);
  if (nthMatch) {
    result.pseudo = 'nth-child';
    result.pseudoArg = parseInt(nthMatch[1], 10);
    remaining = remaining.replace(nthMatch[0], '');
  }
  const nthLastMatch = remaining.match(/:nth-last-child\((\d+)\)/);
  if (nthLastMatch) {
    result.pseudo = 'nth-last-child';
    result.pseudoArg = parseInt(nthLastMatch[1], 10);
    remaining = remaining.replace(nthLastMatch[0], '');
  }
  if (remaining.includes(':first-child')) {
    result.pseudo = 'first-child';
    remaining = remaining.replace(':first-child', '');
  }
  if (remaining.includes(':last-child')) {
    result.pseudo = 'last-child';
    remaining = remaining.replace(':last-child', '');
  }

  const idMatch = remaining.match(/#([\w-]+)/);
  if (idMatch) {
    result.id = idMatch[1];
    remaining = remaining.replace(idMatch[0], '');
  }

  // 多个 class 暂只取第一个(简化)
  const classMatch = remaining.match(/\.([\w-]+)/);
  if (classMatch) {
    result.className = classMatch[1];
    remaining = remaining.replace(classMatch[0], '');
  }

  // 属性匹配 [name], [name=value], [name*=value], [name^=value], [name$=value]
  const attrMatch = remaining.match(/\[([\w:-]+)\s*(?:([*^$~|]?=)\s*"?([^"\]]*)"?)?\]/);
  if (attrMatch) {
    result.attrName = attrMatch[1];
    if (attrMatch[2]) {
      result.attrOp = attrMatch[2];
      result.attrValue = attrMatch[3] !== undefined ? attrMatch[3] : '';
    }
    remaining = remaining.replace(attrMatch[0], '');
  }

  remaining = remaining.trim();
  if (remaining && remaining !== '*') {
    result.tagName = remaining.toLowerCase();
  }

  return result;
}

function matchesSelector(element: HTMLElement, parsed: ParsedSelector): boolean {
  if (parsed.tagName && element.tagName !== parsed.tagName) return false;
  if (parsed.id && element.attributes['id'] !== parsed.id) return false;
  if (parsed.className) {
    const classes = (element.attributes['class'] || '').split(/\s+/);
    if (!classes.includes(parsed.className)) return false;
  }
  if (parsed.attrName) {
    const attrValue = element.attributes[parsed.attrName.toLowerCase()];
    if (attrValue === undefined) return false;
    if (parsed.attrOp !== undefined && parsed.attrValue !== undefined) {
      const v = attrValue;
      const want = parsed.attrValue;
      switch (parsed.attrOp) {
        case '=': if (v !== want) return false; break;
        case '*=': if (v.indexOf(want) < 0) return false; break;
        case '^=': if (!v.startsWith(want)) return false; break;
        case '$=': if (!v.endsWith(want)) return false; break;
        case '~=': if (!v.split(/\s+/).includes(want)) return false; break;
        case '|=': if (v !== want && !v.startsWith(want + '-')) return false; break;
        default: if (v !== want) return false; break;
      }
    }
  }
  if (parsed.containsText) {
    const text = getTextImpl(element);
    if (text.indexOf(parsed.containsText) < 0) return false;
  }
  if (parsed.pseudo && element.parent) {
    const siblings = element.parent.children;
    const idx = siblings.indexOf(element);
    if (parsed.pseudo === 'first-child') {
      if (idx !== 0) return false;
    } else if (parsed.pseudo === 'last-child') {
      if (idx !== siblings.length - 1) return false;
    } else if (parsed.pseudo === 'nth-child') {
      if (idx + 1 !== parsed.pseudoArg) return false;
    } else if (parsed.pseudo === 'nth-last-child') {
      if (siblings.length - idx !== parsed.pseudoArg) return false;
    }
  }
  return true;
}

function queryBySelector(root: HTMLElement, selector: string, recursive: boolean): HTMLElement[] {
  const results: HTMLElement[] = [];
  const parsed = parseSelector(selector);

  const walk = (element: HTMLElement): void => {
    if (matchesSelector(element, parsed)) {
      results.push(element);
    }
    if (recursive) {
      for (const child of element.children) walk(child);
    }
  };

  for (const child of root.children) walk(child);
  return results;
}

function queryDirectChildren(root: HTMLElement, selector: string): HTMLElement[] {
  const results: HTMLElement[] = [];
  const parsed = parseSelector(selector);
  for (const child of root.children) {
    if (matchesSelector(child, parsed)) results.push(child);
  }
  return results;
}

/* ───────────────── public API ───────────────── */

function parseSegments(selector: string): SegmentSpec[] {
  const segs: SegmentSpec[] = [];
  // 用空格 / > 切分,保留组合器
  const tokens: string[] = [];
  const combinators: string[] = [];
  let buf = '';
  let i = 0;
  // 同时要把 [..] 的整体保留(防止内部空格被切)
  while (i < selector.length) {
    const ch = selector[i];
    if (ch === '[') {
      const end = selector.indexOf(']', i);
      if (end > 0) {
        buf += selector.substring(i, end + 1);
        i = end + 1;
        continue;
      }
    }
    if (ch === '>') {
      if (buf.trim()) tokens.push(buf.trim());
      combinators.push('>');
      buf = '';
      i++;
      while (i < selector.length && selector[i] === ' ') i++;
    } else if (ch === ' ') {
      let j = i + 1;
      while (j < selector.length && selector[j] === ' ') j++;
      if (j < selector.length && selector[j] === '>') {
        i = j;
      } else {
        if (buf.trim()) tokens.push(buf.trim());
        combinators.push(' ');
        buf = '';
        i = j;
      }
    } else {
      buf += ch;
      i++;
    }
  }
  if (buf.trim()) tokens.push(buf.trim());

  for (let idx = 0; idx < tokens.length; idx++) {
    const tok = tokens[idx];
    const split = splitIndexer(tok);
    const seg: SegmentSpec = {
      baseSelector: split.base,
      index: split.index,
      childrenOnly: split.base === 'children',
      combinator: idx === 0 ? ' ' : (combinators[idx - 1] || ' '),
    };
    segs.push(seg);
  }
  return segs;
}

function applyIndex(elements: HTMLElement[], spec?: IndexSpec): HTMLElement[] {
  if (!spec) return elements;
  const len = elements.length;
  if (len === 0) return elements;

  const norm = (n: number): number => (n < 0 ? len + n : n);

  if (spec.picks && spec.picks.length > 0) {
    const out: HTMLElement[] = [];
    for (const i of spec.picks) {
      const ix = norm(i);
      if (ix >= 0 && ix < len) out.push(elements[ix]);
    }
    return out;
  }
  if (spec.excludes && spec.excludes.length > 0) {
    const exSet = new Set<number>();
    for (const i of spec.excludes) exSet.add(norm(i));
    return elements.filter((_, i) => !exSet.has(i));
  }
  if (spec.range) {
    const rangeArray = spec.range;
    const s0 = rangeArray[0];
    const e0 = rangeArray[1];
    const step0 = rangeArray[2];
    const start = Math.max(0, norm(s0));
    const end = Math.min(len, norm(e0));
    const step = step0 === 0 ? 1 : step0;
    const out: HTMLElement[] = [];
    if (step > 0) {
      for (let i = start; i < end; i += step) out.push(elements[i]);
    } else {
      for (let i = start; i > end; i += step) {
        if (i >= 0 && i < len) out.push(elements[i]);
      }
    }
    return out;
  }
  return elements;
}

function getTextImpl(element: HTMLElement): string {
  const texts: string[] = [];
  const walk = (el: HTMLElement): void => {
    if (el.childNodes && el.childNodes.length > 0) {
      for (const node of el.childNodes) {
        if (node.type === 'text' && node.text) {
          texts.push(node.text);
        } else if (node.type === 'element' && node.element) {
          walk(node.element);
        }
      }
    } else {
      if (el.textContent) texts.push(el.textContent);
      for (const child of el.children) walk(child);
    }
  };
  walk(element);
  return texts.join(' ').replace(/\s+/g, ' ').trim();
}

function getTextNodesImpl(element: HTMLElement): string[] {
  // 遍历所有后代,但 br/p/div 等块元素之间用换行分隔
  const lines: string[] = [];
  const blockTags = new Set<string>(['p', 'div', 'br', 'tr', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', 'article']);
  const walk = (el: HTMLElement, current: StringBuffer): void => {
    if (!el.childNodes || el.childNodes.length === 0) {
      if (el.textContent) current.buf += el.textContent;
      for (const c of el.children) walk(c, current);
      return;
    }
    for (const node of el.childNodes) {
      if (node.type === 'text' && node.text) {
        current.buf += node.text;
      } else if (node.type === 'element' && node.element) {
        const sub = node.element;
        if (blockTags.has(sub.tagName)) {
          if (current.buf.trim()) lines.push(current.buf.trim());
          current.buf = '';
          walk(sub, current);
          if (current.buf.trim()) lines.push(current.buf.trim());
          current.buf = '';
        } else {
          walk(sub, current);
        }
      }
    }
  };
  const acc: StringBuffer = { buf: '' };
  walk(element, acc);
  if (acc.buf.trim()) lines.push(acc.buf.trim());
  return lines.map((l) => l.replace(/\s+/g, ' ').trim()).filter((l) => l.length > 0);
}

function innerHTMLImpl(element: HTMLElement): string {
  if (element.childNodes && element.childNodes.length > 0) {
    const parts: string[] = [];
    for (const node of element.childNodes) {
      if (node.type === 'text' && node.text) {
        parts.push(node.text);
      } else if (node.type === 'element' && node.element) {
        parts.push(outerHTMLImpl(node.element));
      }
    }
    return parts.join('');
  }
  return element.textContent + element.children.map((c) => outerHTMLImpl(c)).join('');
}

function outerHTMLImpl(element: HTMLElement): string {
  if (element.tagName === 'root') {
    if (element.childNodes && element.childNodes.length > 0) {
      const parts: string[] = [];
      for (const node of element.childNodes) {
        if (node.type === 'text' && node.text) parts.push(node.text);
        else if (node.type === 'element' && node.element) parts.push(outerHTMLImpl(node.element));
      }
      return parts.join('');
    }
    return element.children.map((c) => outerHTMLImpl(c)).join('');
  }
  const attrs = Object.keys(element.attributes)
    .map((k) => `${k}="${element.attributes[k]}"`)
    .join(' ');
  const open = attrs ? `<${element.tagName} ${attrs}>` : `<${element.tagName}>`;
  if (isSelfClosing(element.tagName)) {
    return open;
  }
  return `${open}${innerHTMLImpl(element)}</${element.tagName}>`;
}

export class SimpleCSSSelector {
  static parseHTML(html: string): HTMLElement {
    return parseHTMLImpl(html);
  }

  static querySelectorAll(root: HTMLElement, selector: string): HTMLElement[] {
    const segs = parseSegments(selector);
    let elements: HTMLElement[] = [root];

    for (let i = 0; i < segs.length; i++) {
      const seg = segs[i];
      const next: HTMLElement[] = [];

      if (seg.childrenOnly) {
        // children 关键字:取所有当前元素的直接子元素
        for (const el of elements) {
          for (const c of el.children) next.push(c);
        }
      } else {
        for (const element of elements) {
          if (seg.combinator === '>') {
            const found = queryDirectChildren(element, seg.baseSelector);
            for (const f of found) next.push(f);
          } else {
            const found = queryBySelector(element, seg.baseSelector, true);
            for (const f of found) next.push(f);
          }
        }
      }
      elements = applyIndex(next, seg.index);
    }
    return elements;
  }

  static getText(element: HTMLElement): string {
    return getTextImpl(element);
  }

  static getTextNodes(element: HTMLElement): string[] {
    return getTextNodesImpl(element);
  }

  static getAttribute(element: HTMLElement, attrName: string): string | null {
    const v = element.attributes[attrName.toLowerCase()];
    return v !== undefined ? v : null;
  }

  static outerHTML(element: HTMLElement): string {
    return outerHTMLImpl(element);
  }

  static innerHTML(element: HTMLElement): string {
    return innerHTMLImpl(element);
  }

  static getOwnText(element: HTMLElement): string {
    if (!element.childNodes || element.childNodes.length === 0) {
      return (element.textContent || '').replace(/\s+/g, ' ').trim();
    }
    const parts: string[] = [];
    for (const node of element.childNodes) {
      if (node.type === 'text' && node.text) parts.push(node.text);
    }
    return parts.join(' ').replace(/\s+/g, ' ').trim();
  }
}
