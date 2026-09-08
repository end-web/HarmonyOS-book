import { buffer, util, uri, url } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { i18n } from '@kit.LocalizationKit';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleStageExtractor } from './LocalRuleStageExtractor';
import { LocalRuleExecutionLimits, LocalRuleFetchResult } from './LocalRuleRuntimeTypes';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { LocalRuleBinaryActions } from './LocalRuleBinaryActions';
import { LocalRuleDiagnostics } from './LocalRuleDiagnostics';
import { LocalRuleBrowserLoginCoordinator } from './LocalRuleBrowserLoginCoordinator';
import { LocalRuleBrowserRuntime } from './LocalRuleBrowserRuntime';
import { LocalRuleHttpClient } from './LocalRuleHttpClient';
import { LocalRuleUrlAnalyzer } from './LocalRuleUrlAnalyzer';

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
      if (operation === 'browserLogin' || operation === 'showBrowser') {
        const target = String(args['url'] ?? '');
        if (!new RegExp('^https://', 'i').test(target) || target.length > LocalRuleExecutionLimits.MAX_URL_CHARS) {
          throw new Error('网页登录仅允许有效的 HTTPS 地址');
        }
        let snapshot = '';
        let currentUrl = target;
        if (operation === 'showBrowser') {
          const html = String(args['html'] ?? '');
          const script = String(args['script'] ?? '');
          if (html.length > 512 * 1024 || script.length > 512 * 1024) throw new Error('书源浏览页面内容超过 512 KiB');
          let rendered: LocalRuleFetchResult;
          if (html.length > 0) {
            const plan = LocalRuleUrlAnalyzer.analyze(source, target, variables);
            plan.webView = true;
            plan.webJs = script;
            const response = new LocalRuleFetchResult();
            response.ok = true;
            response.statusCode = 200;
            response.requestUrl = plan.url;
            response.body = html;
            response.headers = { 'Content-Type': 'text/html; charset=utf-8',
              'Content-Security-Policy': LocalRuleExecutionLimits.INLINE_HTML_CSP };
            rendered = await LocalRuleBrowserRuntime.instance.render(source, plan, response, variables);
          } else {
            const options: Record<string, Object> = { 'webView': true, 'webJs': script };
            rendered = await LocalRuleHttpClient.fetch(source, `${target},${JSON.stringify(options)}`, variables);
            if (!rendered.ok) throw new Error(rendered.errorMessage || '书源浏览页面加载失败');
          }
          snapshot = rendered.renderedHtml || rendered.body;
          currentUrl = rendered.requestUrl;
          if (!snapshot) throw new Error('书源浏览页面没有可显示的内容');
        }
        value = await LocalRuleBrowserLoginCoordinator.request(source.bookSourceUrl, source.bookSourceName, currentUrl, snapshot);
      } else if (operation === 'extract') {
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
      } else if (operation === 'compress') {
        value = await LocalRuleBinaryActions.compress(args);
      } else if (operation === 'rsa') {
        value = await LocalRuleBinaryActions.rsa(args);
      } else if (operation === 'uri') {
        const text = String(args['text'] ?? '');
        if (text.length > 65536) throw new Error('URI 超过预算');
        const base = String(args['base'] ?? '');
        const resolved = base ? new url.URL(text, base).href : text;
        const parsed = new uri.URI(resolved).normalize();
        const fields: Record<string, Object> = { 'text': parsed.toString(), 'scheme': parsed.scheme,
          'host': parsed.host, 'port': parsed.port, 'path': parsed.path, 'query': parsed.query,
          'fragment': parsed.fragment, 'authority': parsed.authority, 'userInfo': parsed.encodedUserInfo,
          'rawPath': parsed.encodedPath, 'rawQuery': parsed.encodedQuery, 'rawFragment': parsed.encodedFragment };
        value = fields;
      } else if (operation === 'sleep') {
        const duration = Number(args['duration']);
        if (!Number.isInteger(duration) || duration < 0 || duration > 10000) throw new Error('脚本等待超过 10 秒预算');
        const deadline = Date.now() + duration;
        while (Date.now() < deadline) {
          LocalRuleDiagnostics.check(variables);
          await new Promise<void>((resolve: () => void) => { setTimeout(resolve, Math.min(50, deadline - Date.now())); });
        }
        value = true;
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
