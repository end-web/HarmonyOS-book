import { buffer, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { i18n } from '@kit.LocalizationKit';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleStageExtractor } from './LocalRuleStageExtractor';
import { LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';
import { CharsetCodec } from '../../utils/CharsetCodec';

/** Typed, bounded operations requested by QuickJS. No platform object crosses the bridge. */
export class LocalRuleScriptActions {
  static readonly PREFIX: string = 'local-rule-action:';

  static async execute(address: string, source: LocalRuleSource,
    variables: Record<string, string>, baseUrl: string): Promise<string> {
    try {
      if (address.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) throw new Error('脚本动作输入超过预算');
      const args: Record<string, Object> = JSON.parse(address.substring(LocalRuleScriptActions.PREFIX.length));
      const operation = String(args['operation'] ?? '');
      let value: Object = '';
      if (operation === 'extract') {
        const rule = String(args['rule'] ?? '');
        if (new RegExp('@js:|<js>|\\{\\{|@put:', 'i').test(rule)) throw new Error('脚本内提取仅接受声明式规则');
        const document = LocalRuleStageExtractor.createDocument(String(args['content'] ?? ''), baseUrl);
        if (args['elements'] === true) {
          const elements = await LocalRuleStageExtractor.selectList(document, rule, source, variables);
          value = elements.map(item => item.payload);
        } else {
          value = await LocalRuleStageExtractor.extractValues(document, rule, source, variables);
        }
      } else if (operation === 'digest' || operation === 'hmac') {
        const algorithm = String(args['algorithm'] ?? '').toUpperCase().replace(new RegExp('[-_]', 'g'), '');
        if (!['MD5', 'SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512'].includes(algorithm)) {
          throw new Error(`不支持的摘要算法：${algorithm}`);
        }
        const data: cryptoFramework.DataBlob = { data: LocalRuleScriptActions.hexBytes(String(args['data'] ?? '')) };
        if (operation === 'hmac') {
          const keyData: cryptoFramework.DataBlob = { data: LocalRuleScriptActions.hexBytes(String(args['key'] ?? '')) };
          const key = await cryptoFramework.createSymKeyGenerator('HMAC').convertKey(keyData);
          const mac = cryptoFramework.createMac(algorithm);
          await mac.init(key);
          await mac.update(data);
          value = buffer.from((await mac.doFinal()).data).toString('hex');
        } else {
          const digest = cryptoFramework.createMd(algorithm);
          await digest.update(data);
          value = buffer.from((await digest.digest()).data).toString('hex');
        }
      } else if (operation === 'cipher') {
        value = await LocalRuleScriptActions.cipher(args);
      } else if (operation === 'chinese') {
        const direction = String(args['direction'] ?? '');
        if (!['Traditional-Simplified', 'Simplified-Traditional'].includes(direction)) throw new Error('文字转换方向无效');
        const text = String(args['text'] ?? '');
        if (text.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) throw new Error('文字转换超过预算');
        value = i18n.Transliterator.getInstance(direction).transform(text);
      } else if (operation === 'encode') {
        const encoded = CharsetCodec.encodeUriForCharset(String(args['text'] ?? ''), String(args['charset'] ?? 'utf-8'));
        value = encoded.replace(new RegExp('%([0-9a-f]{2})|([^%])', 'gi'), (_match: string, hex: string, char: string): string =>
          hex || char.charCodeAt(0).toString(16).padStart(2, '0')).toLowerCase();
      } else if (operation === 'decode') {
        const charset = String(args['charset'] ?? 'utf-8').toLowerCase();
        value = util.TextDecoder.create(charset === 'gb2312' ? 'gbk' : charset)
          .decodeToString(LocalRuleScriptActions.hexBytes(String(args['data'] ?? '')));
      } else {
        throw new Error(`不支持的脚本动作：${operation}`);
      }
      const result: Record<string, Object> = { 'value': value };
      const json = JSON.stringify(result);
      if (json.length > LocalRuleExecutionLimits.MAX_RESPONSE_CHARS) throw new Error('脚本动作输出超过预算');
      return json;
    } catch (error) {
      const failure: Record<string, string> = { 'error': error instanceof Error ? error.message : String(error) };
      return JSON.stringify(failure);
    }
  }

  private static hexBytes(value: string): Uint8Array {
    if (value.length > 2 * 1024 * 1024 || value.length % 2 !== 0 || !new RegExp('^[0-9a-f]*$', 'i').test(value)) {
      throw new Error('二进制动作输入无效或超过 1 MiB');
    }
    const bytes = new Uint8Array(value.length / 2);
    for (let index = 0; index < bytes.length; index++) bytes[index] = parseInt(value.substring(index * 2, index * 2 + 2), 16);
    return bytes;
  }

  private static async cipher(args: Record<string, Object>): Promise<string> {
    const parts = String(args['algorithm'] ?? 'AES/CBC/PKCS5Padding').toUpperCase().split('/');
    const mode = parts[1] ?? 'CBC';
    const padding = parts[2] ?? 'PKCS5PADDING';
    if (parts[0] !== 'AES' || !['CBC', 'CTR', 'ECB'].includes(mode) ||
      !['PKCS5PADDING', 'PKCS7PADDING', 'NOPADDING'].includes(padding)) {
      throw new Error('对称加密参数不在当前兼容范围内');
    }
    const keyBytes = LocalRuleScriptActions.hexBytes(String(args['key'] ?? ''));
    if (![16, 24, 32].includes(keyBytes.length)) throw new Error('AES 密钥必须为 16、24 或 32 字节');
    const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
    const algorithm = `AES${keyBytes.length * 8}`;
    const key = await cryptoFramework.createSymKeyGenerator(algorithm).convertKey(keyBlob);
    const cipher = cryptoFramework.createCipher(`${algorithm}|${mode}|${padding === 'NOPADDING' ? 'NoPadding' : 'PKCS7'}`);
    const cryptoMode = args['encrypt'] === true ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE;
    if (mode === 'ECB') {
      await cipher.init(cryptoMode, key, null);
    } else {
      const ivBytes = LocalRuleScriptActions.hexBytes(String(args['iv'] ?? ''));
      if (ivBytes.length !== 16) throw new Error('AES IV 必须为 16 字节');
      const iv: cryptoFramework.DataBlob = { data: ivBytes };
      const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: iv };
      await cipher.init(cryptoMode, key, params);
    }
    const data: cryptoFramework.DataBlob = { data: LocalRuleScriptActions.hexBytes(String(args['data'] ?? '')) };
    return buffer.from((await cipher.doFinal(data)).data).toString('hex');
  }
}
