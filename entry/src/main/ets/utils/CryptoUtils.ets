/**
 * CryptoUtils - 简单的加密工具
 * 用于替代旧的 JavaBridge 中的加密方法
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class CryptoUtils {
  /**
   * MD5 哈希
   */
  static md5Encode(text: string): string {
    try {
      const md = cryptoFramework.createMd('MD5');
      const input: cryptoFramework.DataBlob = { data: new Uint8Array(util.TextEncoder.create().encodeInto(text)) };
      md.updateSync(input);
      const result = md.digestSync();
      return CryptoUtils.bytesToHex(result.data);
    } catch (e) {
      console.error('[CryptoUtils] md5Encode failed:', e);
      return '';
    }
  }

  /**
   * 字节数组转十六进制字符串
   */
  private static bytesToHex(bytes: Uint8Array): string {
    const hexChars: string[] = [];
    for (let i = 0; i < bytes.length; i++) {
      const hex = (bytes[i] & 0xff).toString(16);
      hexChars.push(hex.length === 1 ? '0' + hex : hex);
    }
    return hexChars.join('');
  }
}
