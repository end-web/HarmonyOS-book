/**
 * A typed value travelling between Legado rule stages.
 *
 * Android Legado keeps Element, JsonElement, regex group lists and JavaScript values as objects
 * until a public getString/getStringList boundary needs text.  Harmony used to flatten every
 * intermediate result immediately.  This small carrier lets the parser preserve that distinction
 * while existing callers can continue receiving strings.
 */
export class RuleValueKind {
  static readonly TEXT: string = 'text';
  static readonly HTML_ELEMENT: string = 'htmlElement';
  static readonly JSON: string = 'json';
  static readonly REGEX_GROUPS: string = 'regexGroups';
  static readonly JS_VALUE: string = 'jsValue';
}

export class RuleExecutionTarget {
  static readonly STRING: string = 'string';
  static readonly STRING_LIST: string = 'stringList';
  static readonly ELEMENTS: string = 'elements';
}

export class RuleValue {
  kind: string = RuleValueKind.TEXT;
  text: string = '';
  objectValue: Object | null = null;
  groups: string[] = [];

  constructor(kind: string = RuleValueKind.TEXT, text: string = '', objectValue: Object | null = null,
    groups: string[] = []) {
    this.kind = kind;
    this.text = text;
    this.objectValue = objectValue;
    this.groups = groups;
  }

  static textValue(value: string): RuleValue {
    return new RuleValue(RuleValueKind.TEXT, value);
  }

  static htmlElement(value: string): RuleValue {
    return new RuleValue(RuleValueKind.HTML_ELEMENT, value);
  }

  static jsonValue(value: Object, serialized: string): RuleValue {
    return new RuleValue(RuleValueKind.JSON, serialized, value);
  }

  static regexGroups(value: Record<string, string>, groups: string[]): RuleValue {
    return new RuleValue(RuleValueKind.REGEX_GROUPS, JSON.stringify(value), value, groups);
  }

  static jsValue(value: Object, serialized: string): RuleValue {
    return new RuleValue(RuleValueKind.JS_VALUE, serialized, value);
  }

  /** Rebuilds a typed carrier at compatibility boundaries that still expose strings. */
  static fromExternal(value: string): RuleValue {
    const text = value || '';
    const trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        const parsed = JSON.parse(trimmed) as Object;
        if (!Array.isArray(parsed) && parsed && typeof parsed === 'object' &&
          (parsed as Record<string, Object>)['$0'] !== undefined) {
          const record = parsed as Record<string, Object>;
          const groups: string[] = [];
          const stringRecord: Record<string, string> = {};
          for (let index = 0; record[`$${index}`] !== undefined; index++) {
            const group = String(record[`$${index}`] || '');
            groups.push(group);
            stringRecord[`$${index}`] = group;
          }
          return RuleValue.regexGroups(stringRecord, groups);
        }
        return RuleValue.jsonValue(parsed, text);
      } catch (_) {}
    }
    if (/^<[A-Za-z][\s\S]*>\s*$/.test(trimmed)) return RuleValue.htmlElement(text);
    return RuleValue.textValue(text);
  }

  /** Value supplied to a JavaScript runtime. Structured values stay structured. */
  runtimeValue(): Object {
    return this.objectValue === null ? this.text as Object : this.objectValue;
  }

  asString(): string {
    return this.text;
  }
}
