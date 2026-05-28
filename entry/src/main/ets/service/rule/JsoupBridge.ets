/**
 * JsoupBridge - org.jsoup.Jsoup 桥接（书源 JS 规则中的 Jsoup.parse 等方法）
 *
 * 支持：
 *  - Jsoup.parse(html) - 解析 HTML 返回 Document
 *  - document.select(selector) - CSS 选择器查询
 *  - element.attr(name) - 获取属性
 *  - element.text() - 获取文本
 */

import { SimpleCSSSelector, HTMLElement } from './SimpleCSSSelector';

function detachFromParent(el: HTMLElement): void {
  const parent = el.parent;
  if (!parent) return;
  const idx = parent.children.indexOf(el);
  if (idx >= 0) parent.children.splice(idx, 1);
  for (let i = 0; i < parent.childNodes.length; i++) {
    const cn = parent.childNodes[i];
    if (cn.type === 'element' && cn.element === el) {
      parent.childNodes.splice(i, 1);
      break;
    }
  }
}

class JsoupElement {
  element: HTMLElement;

  constructor(element: HTMLElement) {
    this.element = element;
  }

  select(selector: string): JsoupElements {
    const elements = SimpleCSSSelector.querySelectorAll(this.element, selector);
    return new JsoupElements(elements);
  }

  attr(name: string): string {
    return SimpleCSSSelector.getAttribute(this.element, name) || '';
  }

  text(): string {
    return SimpleCSSSelector.getText(this.element);
  }

  html(): string {
    return SimpleCSSSelector.innerHTML(this.element);
  }

  outerHtml(): string {
    return SimpleCSSSelector.outerHTML(this.element);
  }

  remove(): void {
    detachFromParent(this.element);
  }
}

class JsoupElements {
  elements: HTMLElement[];

  constructor(elements: HTMLElement[]) {
    this.elements = elements;
  }

  attr(name: string): string {
    if (this.elements.length === 0) return '';
    return SimpleCSSSelector.getAttribute(this.elements[0], name) || '';
  }

  text(): string {
    return this.elements.map((el) => SimpleCSSSelector.getText(el)).join(' ');
  }

  html(): string {
    return this.elements.map((el) => SimpleCSSSelector.innerHTML(el)).join('');
  }

  first(): JsoupElement | null {
    return this.elements.length > 0 ? new JsoupElement(this.elements[0]) : null;
  }

  get(index: number): JsoupElement | null {
    return index >= 0 && index < this.elements.length
      ? new JsoupElement(this.elements[index])
      : null;
  }

  size(): number {
    return this.elements.length;
  }

  remove(): void {
    for (const el of this.elements) {
      detachFromParent(el);
    }
    this.elements = [];
  }
}

class JsoupDocument extends JsoupElement {
  constructor(root: HTMLElement) {
    super(root);
  }
}

class JsoupImpl {
  parse(html: string): JsoupDocument {
    const root = SimpleCSSSelector.parseHTML(html);
    return new JsoupDocument(root);
  }
}

let globalJsoup: JsoupImpl | null = null;

export function getJsoup(): JsoupImpl {
  if (!globalJsoup) {
    globalJsoup = new JsoupImpl();
  }
  return globalJsoup;
}
