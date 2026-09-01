import { describe, expect, it } from '@ohos/hypium';
import { ShuShanContentCrypto } from '../../../main/ets/service/rulesource/shushan/ShuShanContentCrypto';

const LEGACY_CONTENT_FIXTURE: string =
  'Vo95033Fd9kIR4oowHuWN0L18uXOcEuTTyzKyDb1hpJbBKIbFFKJAXNPs8UGLWZyoFZy5gcuC+tjMArwnMRp44uG' +
  'Y30MLczrojf8Vbhx6udFJ8DVJOkowF/gS3T7E/lg8BIXC8N7Zh17DL1/7KAx5JqOuzopjA/JAjraT8Zvzd7bQR' +
  'BgxwWSBbKdsDTox3fSF8Yj30F79E8RyL1MJ961aG88nycEoICgH+jB7bjmvL1hgP5AsGpZbQUqTLxgNc5q';

export default function shuShanContentCryptoTest() {
  describe('ShuShanContentCrypto', () => {
    it('decrypts the AES-CBC compatibility fixture with the platform provider', 0, async () => {
      const content = await ShuShanContentCrypto.decryptLegacyBase64(LEGACY_CONTENT_FIXTURE);
      expect(content).assertContain('用于验证书山旧版正文协议');
      expect(content).assertContain('解密后必须保持段落');
    });
  });
}
