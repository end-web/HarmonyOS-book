import { LocalRuleQuickJsRequest, LocalRuleQuickJsRuntime } from './LocalRuleQuickJsRuntime';

class ChaCha20Poly1305Input {
  key: string = '';
  iv: string = '';
  data: string = '';
  aad: string = '';
  encrypt: boolean = false;
}

/** RFC 8439 AEAD, including API 20 devices without the API 22 Poly1305 SDK API. */
export class LocalRuleChaCha20Poly1305 {
  static async execute(key: string, iv: string, data: string, aad: string,
    tagLength: number, encrypt: boolean): Promise<string> {
    LocalRuleChaCha20Poly1305.validateHex(key, 32);
    LocalRuleChaCha20Poly1305.validateHex(iv, 12);
    LocalRuleChaCha20Poly1305.validateHex(data, 1024 * 1024 + (encrypt ? 0 : 16));
    LocalRuleChaCha20Poly1305.validateHex(aad, 1024 * 1024);
    if (key.length !== 64) throw new Error('ChaCha20 密钥必须为 32 字节');
    if (iv.length !== 24) throw new Error('ChaCha20-Poly1305 nonce 必须为 12 字节');
    if (tagLength !== 128) throw new Error('ChaCha20-Poly1305 认证标签必须为 128 位');
    if (!encrypt && data.length < 32) throw new Error('ChaCha20-Poly1305 密文缺少认证标签');
    const input = new ChaCha20Poly1305Input();
    input.key = key;
    input.iv = iv;
    input.data = data;
    input.aad = aad;
    input.encrypt = encrypt;
    const request = new LocalRuleQuickJsRequest();
    request.sourceUrl = 'local-rule-chacha20-poly1305';
    request.timeoutMs = 5000;
    request.maxPendingJobs = 0;
    request.script = `(${LocalRuleChaCha20Poly1305.program()})(${JSON.stringify(input)})`;
    const result = await LocalRuleQuickJsRuntime.execute(request);
    if (!result.success) throw new Error(result.errorMessage || 'ChaCha20-Poly1305 执行失败');
    return result.value;
  }

  private static validateHex(value: string, maxBytes: number): void {
    if (value.length > maxBytes * 2 || value.length % 2 !== 0 || !new RegExp('^[0-9a-f]*$', 'i').test(value)) {
      throw new Error('ChaCha20-Poly1305 输入无效或超过预算');
    }
  }

  /** Fixed trusted algorithm; data is JSON encoded, and all execution stays in bounded taskpool QuickJS. */
  private static program(): string {
    return String.raw`function(input) {
      function bytes(hex) {
        var out = new Uint8Array(hex.length / 2);
        for (var i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
        return out;
      }
      function hex(data) {
        var out = '';
        for (var i = 0; i < data.length; i++) out += data[i].toString(16).padStart(2, '0');
        return out;
      }
      function word(data, offset) {
        return (data[offset] | data[offset + 1] << 8 | data[offset + 2] << 16 | data[offset + 3] << 24) >>> 0;
      }
      function rotate(value, count) { return (value << count | value >>> (32 - count)) >>> 0; }
      function quarter(x, a, b, c, d) {
        x[a] = (x[a] + x[b]) >>> 0; x[d] = rotate(x[d] ^ x[a], 16);
        x[c] = (x[c] + x[d]) >>> 0; x[b] = rotate(x[b] ^ x[c], 12);
        x[a] = (x[a] + x[b]) >>> 0; x[d] = rotate(x[d] ^ x[a], 8);
        x[c] = (x[c] + x[d]) >>> 0; x[b] = rotate(x[b] ^ x[c], 7);
      }
      var key = bytes(input.key), nonce = bytes(input.iv);
      var initial = new Uint32Array(16);
      initial.set([0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]);
      for (var i = 0; i < 8; i++) initial[4 + i] = word(key, i * 4);
      for (var i = 0; i < 3; i++) initial[13 + i] = word(nonce, i * 4);
      function block(counter) {
        initial[12] = counter;
        var x = new Uint32Array(initial);
        for (var round = 0; round < 10; round++) {
          quarter(x, 0, 4, 8, 12); quarter(x, 1, 5, 9, 13);
          quarter(x, 2, 6, 10, 14); quarter(x, 3, 7, 11, 15);
          quarter(x, 0, 5, 10, 15); quarter(x, 1, 6, 11, 12);
          quarter(x, 2, 7, 8, 13); quarter(x, 3, 4, 9, 14);
        }
        var out = new Uint8Array(64);
        for (var i = 0; i < 16; i++) {
          var value = (x[i] + initial[i]) >>> 0;
          for (var j = 0; j < 4; j++) out[i * 4 + j] = value >>> (j * 8);
        }
        return out;
      }
      function crypt(data) {
        var out = new Uint8Array(data.length);
        for (var offset = 0; offset < data.length; offset += 64) {
          var stream = block(1 + offset / 64);
          for (var j = 0; j < 64 && offset + j < data.length; j++) out[offset + j] = data[offset + j] ^ stream[j];
        }
        return out;
      }
      function little(data, start, count) {
        var value = 0n;
        for (var i = count - 1; i >= 0; i--) value = (value << 8n) | BigInt(data[start + i]);
        return value;
      }
      var polyKey = block(0);
      var r = little(polyKey, 0, 16) & 0x0ffffffc0ffffffc0ffffffc0fffffffn;
      var s = little(polyKey, 16, 16);
      var p = (1n << 130n) - 5n;
      function tag(aad, cipher) {
        var accumulator = 0n;
        function padded(data) {
          for (var offset = 0; offset < data.length; offset += 16) {
            var n = little(data, offset, Math.min(16, data.length - offset));
            accumulator = ((accumulator + n + (1n << 128n)) * r) % p;
          }
        }
        padded(aad); padded(cipher);
        var lengths = BigInt(aad.length) | (BigInt(cipher.length) << 64n);
        accumulator = ((accumulator + lengths + (1n << 128n)) * r) % p;
        var value = (accumulator + s) & ((1n << 128n) - 1n);
        var out = new Uint8Array(16);
        for (var i = 0; i < 16; i++) { out[i] = Number(value & 255n); value >>= 8n; }
        return out;
      }
      var data = bytes(input.data), aad = bytes(input.aad);
      if (input.encrypt) {
        var cipher = crypt(data);
        return hex(cipher) + hex(tag(aad, cipher));
      }
      var cipher = data.subarray(0, data.length - 16), expected = tag(aad, cipher);
      var difference = 0;
      for (var i = 0; i < 16; i++) difference |= expected[i] ^ data[cipher.length + i];
      if (difference !== 0) throw new Error('ChaCha20-Poly1305 authentication failed');
      return hex(crypt(cipher));
    }`;
  }
}
