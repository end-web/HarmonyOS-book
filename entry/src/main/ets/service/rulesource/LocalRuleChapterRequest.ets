import { LocalRuleDocument, LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleScriptRuntime } from './LocalRuleScriptRuntime';
import { LocalRuleStageExtractor } from './LocalRuleStageExtractor';

/** Keep chapter identity stable; evaluate time-sensitive request scripts when content is opened. */
export class LocalRuleChapterRequest {
  private static readonly MARKER: string = '#local-rule-chapter=';

  static needsDeferredRequest(rule: string): boolean {
    return LocalRuleScriptRuntime.hasScript(rule) || new RegExp('\\{\\{\\s*(?!\\$[.\\[]|@@|@json:)[^}]+\\}\\}').test(rule);
  }

  static create(document: LocalRuleDocument, variables: Record<string, string>): string {
    if (document.payload.length > 64 * 1024) throw new Error('章节规则上下文超过 64 KiB');
    variables['__chapterPayload'] = document.payload;
    variables['__chapterBaseUrl'] = document.baseUrl;
    const base = document.baseUrl.split('#')[0];
    return `${base}${LocalRuleChapterRequest.MARKER}${encodeURIComponent(document.payload)}`;
  }

  static async resolve(address: string, source: LocalRuleSource,
    variables: Record<string, string>): Promise<string> {
    const marker = address.indexOf(LocalRuleChapterRequest.MARKER);
    if (marker < 0) return address;
    const baseUrl = variables['__chapterBaseUrl'] || address.substring(0, marker);
    const payload = variables['__chapterPayload'] ||
      decodeURIComponent(address.substring(marker + LocalRuleChapterRequest.MARKER.length));
    if (payload.length > 64 * 1024) throw new Error('章节规则上下文超过 64 KiB');
    const document = LocalRuleStageExtractor.createDocument(payload, baseUrl);
    const result = await LocalRuleStageExtractor.extract(document, source.ruleToc.chapterUrl, source, variables, true);
    if (!result || result.includes(LocalRuleChapterRequest.MARKER)) throw new Error('章节地址规则未返回有效请求');
    if (result.length > LocalRuleExecutionLimits.MAX_FIELD_CHARS) throw new Error('章节请求超过长度限制');
    return result;
  }
}
