import { buffer } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** Bounded in-memory codecs. These operations never accept paths or return native handles. */
export class LocalRuleBinaryActions {
  static bytes(value: string): Uint8Array {
    if (value.length > 2 * 1024 * 1024 || value.length % 2 !== 0 || !new RegExp('^[0-9a-f]*$', 'i').test(value)) {
      throw new Error('二进制动作输入无效或超过 1 MiB');
    }
    const bytes = new Uint8Array(value.length / 2);
    for (let index = 0; index < bytes.length; index++) bytes[index] = parseInt(value.substring(index * 2, index * 2 + 2), 16);
    return bytes;
  }

  static async compress(args: Record<string, Object>): Promise<string> {
    const input = LocalRuleBinaryActions.bytes(String(args['data'] ?? ''));
    const format = String(args['format'] ?? 'zlib');
    if (!['zlib', 'gzip', 'raw'].includes(format)) throw new Error('压缩格式无效');
    const compress = args['compress'] === true;
    const output = new ArrayBuffer(1024 * 1024);
    const stream: zlib.ZStream = { nextIn: input.buffer, availableIn: input.length, nextOut: output, availableOut: output.byteLength };
    const codec = await zlib.createZip();
    const bits = format === 'raw' ? -15 : format === 'gzip' ? 31 : 15;
    const initialized = compress
      ? await codec.deflateInit2(stream, zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION, zlib.CompressMethod.DEFLATED,
        bits, zlib.MemLevel.MEM_LEVEL_DEFAULT, zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY)
      : await codec.inflateInit2(stream, bits);
    if (initialized !== zlib.ReturnStatus.OK) throw new Error('压缩流初始化失败');
    try {
      const result = compress ? await codec.deflate(stream, zlib.CompressFlushMode.FINISH)
        : await codec.inflate(stream, zlib.CompressFlushMode.FINISH);
      if (result !== zlib.ReturnStatus.STREAM_END) throw new Error('压缩数据无效、未完整结束或输出超过 1 MiB');
      const current = await codec.getZStream();
      const length = current.totalOut ?? 0;
      if (length > output.byteLength) throw new Error('压缩流输出超过预算');
      return buffer.from(output.slice(0, length)).toString('hex');
    } finally {
      if (compress) await codec.deflateEnd(stream); else await codec.inflateEnd(stream);
    }
  }

  static async rsa(args: Record<string, Object>): Promise<Object> {
    const keyBytes = LocalRuleBinaryActions.bytes(String(args['key'] ?? ''));
    if (keyBytes.length > 16384) throw new Error('RSA 密钥超过预算');
    const keyData: cryptoFramework.DataBlob = { data: keyBytes };
    const privateKey = args['privateKey'] === true;
    const generator = cryptoFramework.createAsyKeyGenerator('RSA2048');
    const pair = await generator.convertKey(privateKey ? null : keyData, privateKey ? keyData : null);
    const operation = String(args['mode'] ?? '');
    const data: cryptoFramework.DataBlob = { data: LocalRuleBinaryActions.bytes(String(args['data'] ?? '')) };
    const algorithm = String(args['algorithm'] ?? '');
    if (operation === 'sign' || operation === 'verify') {
      const digest = algorithm.toUpperCase().replace(new RegExp('[-_]', 'g'), '').replace('WITHRSA', '');
      if (!['SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512'].includes(digest)) throw new Error('RSA 签名算法无效');
      const transform = `RSA2048|PKCS1|${digest}`;
      if (operation === 'sign') {
        if (!privateKey) throw new Error('RSA 签名需要私钥');
        const signer = cryptoFramework.createSign(transform);
        await signer.init(pair.priKey);
        return buffer.from((await signer.sign(data)).data).toString('hex');
      }
      const verifier = cryptoFramework.createVerify(transform);
      await verifier.init(pair.pubKey);
      const signature: cryptoFramework.DataBlob = { data: LocalRuleBinaryActions.bytes(String(args['signature'] ?? '')) };
      return verifier.verify(data, signature);
    }
    const padding = algorithm.toUpperCase().split('/')[2] ?? 'PKCS1PADDING';
    let transform = '';
    if (padding === 'PKCS1PADDING') transform = 'RSA2048|PKCS1';
    else if (padding === 'NOPADDING') transform = 'RSA2048|NoPadding';
    else if (padding === 'OAEPWITHSHA-1ANDMGF1PADDING' || padding === 'OAEPPADDING') transform = 'RSA2048|PKCS1_OAEP|SHA1|MGF1_SHA1';
    else if (padding === 'OAEPWITHSHA-256ANDMGF1PADDING') transform = 'RSA2048|PKCS1_OAEP|SHA256|MGF1_SHA1';
    else throw new Error('RSA 填充参数无效');
    const cipher = cryptoFramework.createCipher(transform);
    const encrypt = operation === 'encrypt';
    if (!encrypt && operation !== 'decrypt') throw new Error('RSA 操作无效');
    await cipher.init(encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE,
      privateKey ? pair.priKey : pair.pubKey, null);
    return buffer.from((await cipher.doFinal(data)).data).toString('hex');
  }
}
