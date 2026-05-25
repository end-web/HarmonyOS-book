/**
 * SimpleCSSSelector - 简化版 CSS 选择器（ArkTS 兼容）
 */

export interface HTMLElement {
  tagName: string;
  attributes: Record<string, string>;
  children: HTMLElement[];
  textContent: string;
  parent?: HTMLElement;
}

export interface ParsedSelector {
  tagName?: string;
  className?: string;
  id?: string;
  attrName?: string;
  attrValue?: string;
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
  const attrRegex = /([\w-]+)(?:="([^"]*)")?/g;
  let match: RegExpExecArray | null = attrRegex.exec(attrsStr);
  while (match !== null) {
    const name = match[1];
    const value = match[2];
    attrs[name.toLowerCase()] = value !== undefined ? value : '';
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
  };

  const stack: HTMLElement[] = [root];
  const tagRegex = /<(\/?)([\w-]+)([^>]*)>/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null = tagRegex.exec(html);

  while (match !== null) {
    const isClosing = match[1];
    const tagName = match[2];
    const attrsStr = match[3];

    if (match.index > lastIndex) {
      const text = html.substring(lastIndex, match.index).trim();
      if (text && stack.length > 0) {
        const parent = stack[stack.length - 1];
        parent.textContent += text;
      }
    }

    if (isClosing) {
      if (stack.length > 1) {
        stack.pop();
      }
    } else {
      const element: HTMLElement = {
        tagName: tagName.toLowerCase(),
        attributes: parseAttributes(attrsStr),
        children: [],
        textContent: '',
        parent: stack[stack.length - 1],
      };
      stack[stack.length - 1].children.push(element);
      if (!isSelfClosing(tagName)) {
        stack.push(element);
      }
    }

    lastIndex = tagRegex.lastIndex;
    match = tagRegex.exec(html);
  }

  if (lastIndex < html.length && stack.length > 0) {
    const text = html.substring(lastIndex).trim();
    if (text) {
      stack[stack.length - 1].textContent += text;
    }
  }

  return root;
}

function parseSelector(selector: string): ParsedSelector {
  const result: ParsedSelector = {};
  let remaining = selector;

  const idMatch = remaining.match(/#([\w-]+)/);
  if (idMatch) {
    result.id = idMatch[1];
    remaining = remaining.replace(idMatch[0], '');
  }

  const classMatch = remaining.match(/\.([\w-]+)/);
  if (classMatch) {
    result.className = classMatch[1];
    remaining = remaining.replace(classMatch[0], '');
  }

  const attrMatch = remaining.match(/\[([\w-]+)(?:="?([^"\]]*)"?)?\]/);
  if (attrMatch) {
    result.attrName = attrMatch[1];
    result.attrValue = attrMatch[2];
    remaining = remaining.replace(attrMatch[0], '');
  }

  if (remaining) {
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
    const attrValue = element.attributes[parsed.attrName];
    if (attrValue === undefined) return false;
    if (parsed.attrValue !== undefined && attrValue !== parsed.attrValue) return false;
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
      for (const child of element.children) {
        walk(child);
      }
    }
  };

  for (const child of root.children) {
    walk(child);
  }
  return results;
}

function getTextImpl(element: HTMLElement): string {
  const texts: string[] = [];
  const walk = (el: HTMLElement): void => {
    if (el.textContent) {
      texts.push(el.textContent);
    }
    for (const child of el.children) {
      walk(child);
    }
  };
  walk(element);
  return texts.join(' ').trim();
}

function outerHTMLImpl(element: HTMLElement): string {
  if (element.tagName === 'root') {
    return element.children.map((c) => outerHTMLImpl(c)).join('');
  }
  const attrs = Object.keys(element.attributes)
    .map((k) => `${k}="${element.attributes[k]}"`)
    .join(' ');
  const open = attrs ? `<${element.tagName} ${attrs}>` : `<${element.tagName}>`;
  if (isSelfClosing(element.tagName)) {
    return open;
  }
  const childrenHtml = element.children.map((c) => outerHTMLImpl(c)).join('');
  return `${open}${element.textContent}${childrenHtml}</${element.tagName}>`;
}

export class SimpleCSSSelector {
  static parseHTML(html: string): HTMLElement {
    return parseHTMLImpl(html);
  }

  static querySelectorAll(root: HTMLElement, selector: string): HTMLElement[] {
    const parts = selector.split(/\s+/).filter((s) => s.length > 0);
    let elements: HTMLElement[] = [root];
    for (const part of parts) {
      const next: HTMLElement[] = [];
      for (const element of elements) {
        const found = queryBySelector(element, part, true);
        for (const f of found) next.push(f);
      }
      elements = next;
    }
    return elements;
  }

  static getText(element: HTMLElement): string {
    return getTextImpl(element);
  }

  static getAttribute(element: HTMLElement, attrName: string): string | null {
    const v = element.attributes[attrName.toLowerCase()];
    return v !== undefined ? v : null;
  }

  static outerHTML(element: HTMLElement): string {
    return outerHTMLImpl(element);
  }
}
