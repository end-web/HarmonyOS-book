import { buffer, util } from '@kit.ArkTS';
import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';

/** Inline source payloads are data, never an implicit request or executable code. */
export class LocalRuleDataUrl {
  static decode(address: string): string {
    const comma = address.indexOf(',');
    if (!address.toLowerCase().startsWith('data:') || comma < 0) throw new Error('data 地址格式无效');
    if (address.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS * 3) throw new Error('data 地址超过预算');
    const metadata = address.substring(5, comma);
    const payload = address.substring(comma + 1);
    const charset = new RegExp('(?:^|;)charset=([^;]+)', 'i').exec(metadata)?.[1] ?? 'utf-8';
    const base64 = metadata.toLowerCase().split(';').includes('base64');
    const bytes: number[] = [];
    if (base64) {
      const encoded = decodeURIComponent(payload).replace(new RegExp('\\s', 'g'), '');
      if (!new RegExp('^[A-Za-z0-9+/]*={0,2}$').test(encoded) || encoded.length % 4 === 1) {
        throw new Error('data 地址 Base64 无效');
      }
      const decoded = buffer.from(encoded, 'base64');
      for (let index = 0; index < decoded.length; index++) bytes.push(decoded[index]);
    } else {
      for (let index = 0; index < payload.length; index++) {
        if (payload.charAt(index) === '%') {
          const hex = payload.substring(index + 1, index + 3);
          if (!new RegExp('^[0-9a-f]{2}$', 'i').test(hex)) throw new Error('data 地址百分号编码无效');
          bytes.push(parseInt(hex, 16));
          index += 2;
        } else {
          const cp = payload.codePointAt(index) ?? 0;
          const encoded = buffer.from(String.fromCodePoint(cp), 'utf-8');
          for (let offset = 0; offset < encoded.length; offset++) bytes.push(encoded[offset]);
          if (cp > 65535) index++;
        }
      }
    }
    if (bytes.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) throw new Error('data 内容超过预算');
    return util.TextDecoder.create(charset.toLowerCase() === 'gb2312' ? 'gbk' : charset)
      .decodeToString(new Uint8Array(bytes));
  }
}
