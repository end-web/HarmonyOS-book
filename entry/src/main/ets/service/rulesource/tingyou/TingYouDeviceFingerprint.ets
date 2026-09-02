import { buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const DFP_KEY_SEED: string = 'fa317cd29b|';
const PRIVACY_FINGERPRINT: string = '||||HarmonyOS|Asia/Shanghai';

/** 生成听友访客接口要求的最小匿名设备指纹 Cookie。 */
export class TingYouDeviceFingerprint {
  static async buildCookie(): Promise<string> {
    return TingYouDeviceFingerprint.buildCookieForDate(
      TingYouDeviceFingerprint.currentDateText());
  }

  static async buildCookieForDate(dateText: string): Promise<string> {
    const cleanDate = TingYouDeviceFingerprint.requireDateText(dateText);
    const key = await TingYouDeviceFingerprint.deriveKey(cleanDate);
    const encrypted = await TingYouDeviceFingerprint.encryptFingerprint(key);
    const dateToken = Number(cleanDate).toString(36);
    const cipherText = buffer.from(encrypted).toString('base64');
    return `dfp=f-${dateToken}:f-${cipherText}`;
  }

  static async deriveKeyHexForDate(dateText: string): Promise<string> {
    const key = await TingYouDeviceFingerprint.deriveKey(
      TingYouDeviceFingerprint.requireDateText(dateText));
    let output = '';
    for (let index = 0; index < key.length; index++) {
      output += key[index].toString(16).padStart(2, '0');
    }
    return output;
  }

  private static currentDateText(): string {
    const now = new Date();
    return `${now.getFullYear()}${TingYouDeviceFingerprint.twoDigits(now.getMonth() + 1)}` +
      `${TingYouDeviceFingerprint.twoDigits(now.getDate())}`;
  }

  private static twoDigits(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  private static requireDateText(value: string): string {
    const clean = value.trim();
    if (!new RegExp('^[0-9]{8}$').test(clean) || Number(clean) <= 0) {
      throw new Error('听友设备指纹日期格式无效');
    }
    return clean;
  }

  private static async deriveKey(dateText: string): Promise<Uint8Array> {
    const digest = cryptoFramework.createMd('SHA256');
    const seedBlob: cryptoFramework.DataBlob = {
      data: TingYouDeviceFingerprint.utf8Bytes(`${DFP_KEY_SEED}${dateText}`)
    };
    await digest.update(seedBlob);
    const hash = await digest.digest();
    return hash.data.subarray(0, 16);
  }

  private static async encryptFingerprint(keyBytes: Uint8Array): Promise<Uint8Array> {
    const keyGenerator = cryptoFramework.createSymKeyGenerator('SM4_128');
    const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
    const key = await keyGenerator.convertKey(keyBlob);
    const cipher = cryptoFramework.createCipher('SM4_128|ECB|PKCS7');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, null);
    const inputBlob: cryptoFramework.DataBlob = {
      data: TingYouDeviceFingerprint.utf8Bytes(PRIVACY_FINGERPRINT)
    };
    const encrypted = await cipher.doFinal(inputBlob);
    return encrypted.data;
  }

  private static utf8Bytes(value: string): Uint8Array {
    const encoded = buffer.from(value, 'utf-8');
    const output = new Uint8Array(encoded.length);
    for (let index = 0; index < encoded.length; index++) output[index] = encoded[index];
    return output;
  }
}
