import { NativeHtmlParser, NativeHtmlDocument } from './NativeHtmlParser';
import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlatformCompat } from '../../../utils/PlatformCompat';

/** Load the Cangjie tokenizer only on supported targets. API 20 and watches keep a script-free ArkTS path. */
export class NativeRuleDocumentRuntime {
  private static nativeUnavailable: boolean = false;

  static async parseHtml(html: string): Promise<NativeHtmlDocument> {
    if (PlatformCompat.supports(22) && !PlatformCompat.wearable && !NativeRuleDocumentRuntime.nativeUnavailable) {
      let tokens = '';
      let stage = 'import';
      try {
        const worker = await import('./NativeRuleTokenizerWorker');
        stage = 'create-task';
        const task = new taskpool.Task(worker.tokenizeNativeHtml, html);
        stage = 'execute-task';
        const result = await taskpool.execute(task);
        if (typeof result !== 'string') throw new Error('仓颉解析库返回类型错误');
        tokens = result;
      } catch (error) {
        const failure: BusinessError = error;
        const code = failure?.code ?? 0;
        const message = typeof failure?.message === 'string' ? failure.message.slice(0, 320) : '无错误详情';
        NativeRuleDocumentRuntime.nativeUnavailable = true;
        console.warn('[NativeRuleDocumentRuntime] 仓颉模块不可用，使用 ArkTS 解析：' +
          `stage=${stage} code=${code} message=${message}`);
      }
      // Parser errors and native budgets are never hidden by retrying another engine.
      if (tokens) return NativeHtmlParser.parseTokens(html, tokens);
    }
    return NativeHtmlParser.parse(html);
  }
}
