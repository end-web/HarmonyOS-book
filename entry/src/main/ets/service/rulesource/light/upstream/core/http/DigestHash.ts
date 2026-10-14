import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

// HTTP Digest 认证用的摘要：algorithm 取 'MD5' / 'SHA256'，返回小写十六进制。
export function digestHashHex(algorithm: string, text: string): string {
  const md = cryptoFramework.createMd(algorithm);
  md.updateSync({ data: new util.TextEncoder().encodeInto(text) });
  const data = md.digestSync().data;
  let hex = '';
  for (let i = 0; i < data.length; i++) {
    hex += (data[i] < 16 ? '0' : '') + data[i].toString(16);
  }
  return hex;
}
