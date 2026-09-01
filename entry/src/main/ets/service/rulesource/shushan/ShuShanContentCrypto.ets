import { buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const MAX_LEGACY_CIPHERTEXT_CHARS: number = 2 * 1024 * 1024;
const AES_BLOCK_BYTES: number = 16;
// 远端 5.42 规则携带 17 字节材料；AES-128 仅接受 16 字节，此处保留去掉末尾标记的兼容回退。
const LEGACY_KEY_MATERIAL: string = 'G@tY3$jK7#mL2&pW8';
const LEGACY_IV_MATERIAL: string = 'C!eH4&sM6@wP9^zX1';

/** 仅解密书山既有响应，不用于应用自身数据的加密或存储。 */
export class ShuShanContentCrypto {
  static async decryptLegacyBase64(value: string): Promise<string> {
    const clean = value.trim();
    if (clean.length === 0 || clean.length > MAX_LEGACY_CIPHERTEXT_CHARS) return '';

    try {
      const encrypted = ShuShanContentCrypto.base64Bytes(clean);
      if (encrypted.length === 0 || encrypted.length % AES_BLOCK_BYTES !== 0) return '';

      const keyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      const keyBlob: cryptoFramework.DataBlob = {
        data: ShuShanContentCrypto.utf8Bytes(LEGACY_KEY_MATERIAL.substring(0, AES_BLOCK_BYTES))
      };
      const key = await keyGenerator.convertKey(keyBlob);
      const ivBlob: cryptoFramework.DataBlob = {
        data: ShuShanContentCrypto.utf8Bytes(LEGACY_IV_MATERIAL.substring(0, AES_BLOCK_BYTES))
      };
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: ivBlob
      };
      const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
      const encryptedBlob: cryptoFramework.DataBlob = { data: encrypted };
      const decrypted = await cipher.doFinal(encryptedBlob);
      return buffer.from(decrypted.data).toString('utf-8').trim();
    } catch (_error) {
      return '';
    }
  }

  private static base64Bytes(value: string): Uint8Array {
    const decoded = buffer.from(value, 'base64');
    const output = new Uint8Array(decoded.length);
    for (let index = 0; index < decoded.length; index++) output[index] = decoded[index];
    return output;
  }

  private static utf8Bytes(value: string): Uint8Array {
    const encoded = buffer.from(value, 'utf-8');
    const output = new Uint8Array(encoded.length);
    for (let index = 0; index < encoded.length; index++) output[index] = encoded[index];
    return output;
  }
}
