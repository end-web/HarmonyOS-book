import { buffer, util, url } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { NativeHtmlDocument, NativeHtmlNode } from './NativeHtmlParser';
import { NativeRuleSchema, NativeTransform, NativeValue } from './NativeRuleSchema';
import { LocalRuleJsonPath } from '../LocalRuleJsonPath';

export class NativeValueContext {
  variables: Map<string, string> = new Map();
  html: NativeHtmlDocument | undefined = undefined;
  node: NativeHtmlNode | undefined = undefined;
  json: string = '';
  baseUrl: string = '';
}

/** Typed extraction and a fixed operation set. No script host or page execution. */
export class NativeRuleValues {
  /** Reject response messages before URL resolution can disguise them as relative media paths. */
  static resolveUrl(input: string, baseUrl: string): string {
    const value = input.trim();
    if (!value) return '';
    if (new RegExp('[\\s\\x00-\\x1f\\x7f<>\\{\\}\\\\]').test(value)) throw new Error('地址包含错误文本或非法字符');
    const absolute = new RegExp('^https?://', 'i').test(value);
    const relative = value.startsWith('//') || value.startsWith('/') || value.startsWith('./') || value.startsWith('../') ||
      new RegExp('^\\?[A-Za-z0-9_.%-]+=').test(value) ||
      new RegExp('^[A-Za-z0-9_%~-][^:]*[/]').test(value) ||
      new RegExp('^[A-Za-z0-9_%~-][^:]*\\.[A-Za-z0-9]{1,12}(?:[?#].*)?$').test(value);
    if (!absolute && !relative) throw new Error('规则返回的内容不是有效地址');
    try {
      const parsed = url.URL.parseURL(value, baseUrl);
      if (!new RegExp('^https?://', 'i').test(parsed.href) || !parsed.hostname || parsed.username || parsed.password) {
        throw new Error('invalid');
      }
      return parsed.href;
    } catch (_error) {
      throw new Error('地址无效或不是 HTTP/HTTPS');
    }
  }

  static async evaluate(value: NativeValue, context: NativeValueContext): Promise<string> {
    if (value.transforms.length > 16) throw new Error('原生规则转换步骤超过预算');
    let result = '';
    if (value.kind === 'literal') result = value.value;
    else if (value.kind === 'variable') result = context.variables.get(value.value) ?? '';
    else if (value.kind === 'template') result = NativeRuleValues.expand(value.value, context.variables);
    else if (value.kind === 'css') {
      if (context.html !== undefined) {
        const nodes: NativeHtmlNode[] = value.value ? context.html.select(value.value, context.node) :
          [context.node ?? context.html.root];
        if (value.index < nodes.length) {
          const node = nodes[value.index];
          result = value.attribute === 'text' ? node.text() :
            value.attribute === 'html' ? node.innerHtml() : node.attribute(value.attribute);
        }
      }
    } else if (value.kind === 'json') {
      NativeRuleValues.budget(context.json);
      const matches = LocalRuleJsonPath.queryPayload(context.json, value.value);
      if (value.index < matches.length) result = LocalRuleJsonPath.valueToString(matches[value.index]);
    } else throw new Error(`未知取值操作：${value.kind}`);
    NativeRuleValues.budget(result);
    for (const transform of value.transforms) {
      result = await NativeRuleValues.transform(result, transform, context);
      NativeRuleValues.budget(result);
    }
    if (value.required && !result.trim()) throw new Error(`必填字段提取失败：${value.value.substring(0, 100)}`);
    return result;
  }

  static expand(template: string, variables: Map<string, string>): string {
    NativeRuleSchema.template(template);
    const result = template.replace(new RegExp('\\{\\{([A-Za-z_][A-Za-z0-9_]*)\\}\\}', 'g'),
      (_match: string, name: string): string => {
        const value = variables.get(name);
        if (value === undefined) throw new Error(`模板变量未绑定：${name}`);
        return value;
      });
    NativeRuleValues.budget(result);
    return result;
  }

  private static budget(value: string): void {
    if (value.length > NativeRuleSchema.MAX_VALUE_CHARS) throw new Error('原生规则值超过 4 MiB 字符预算');
  }

  private static async transform(input: string, operation: NativeTransform,
    context: NativeValueContext): Promise<string> {
    if (operation.op === 'trim') return input.trim();
    if (operation.op === 'replace' || operation.op === 'regexGroup') {
      NativeRuleSchema.regex(operation.pattern);
      if (input.length > NativeRuleSchema.MAX_REGEX_INPUT) throw new Error('正则输入超过 4096 字符预算');
      if (operation.op === 'replace') return input.replace(new RegExp(operation.pattern, 'g'), operation.replacement);
      const match = new RegExp(operation.pattern).exec(input);
      if (match === null || operation.group >= match.length) throw new Error('正则捕获未匹配');
      return match[operation.group] ?? '';
    }
    if (operation.op === 'add') {
      if (!new RegExp('^-?[0-9]+$').test(input)) throw new Error('加法输入必须为整数');
      const output = Number(input) + operation.amount;
      if (!Number.isSafeInteger(output)) throw new Error('加法结果超出安全整数范围');
      return String(output);
    }
    if (operation.op === 'md5') {
      try {
        const digest = cryptoFramework.createMd('MD5');
        const bytes: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(input) };
        await digest.update(bytes);
        return buffer.from((await digest.digest()).data).toString('hex');
      } catch (_error) {
        throw new Error('系统 MD5 摘要计算失败');
      }
    }
    if (operation.op === 'urlEncode') return encodeURIComponent(input);
    if (operation.op === 'base64Decode') {
      try {
        return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new util.Base64Helper().decodeSync(input));
      } catch (_error) {
        throw new Error('Base64 内容或 UTF-8 编码无效');
      }
    }
    if (operation.op === 'resolveUrl') {
      return NativeRuleValues.resolveUrl(input, context.baseUrl);
    }
    throw new Error(`未知转换操作：${operation.op}`);
  }
}
