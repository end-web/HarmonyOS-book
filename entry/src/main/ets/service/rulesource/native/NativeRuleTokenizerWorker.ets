import { tokenizeHtml } from 'libnative_rulecore.so';
import { BusinessError } from '@kit.BasicServicesKit';

@Concurrent
export function tokenizeNativeHtml(html: string): string {
  try {
    return tokenizeHtml(html);
  } catch (error) {
    const failure: BusinessError = error;
    const code = failure?.code ?? 0;
    const message = typeof failure?.message === 'string' ? failure.message.slice(0, 320) : '无错误详情';
    console.error(`[NativeRuleTokenizerWorker] code=${code} message=${message}`);
    throw new Error(`NativeRuleCore code=${code} message=${message}`);
  }
}
