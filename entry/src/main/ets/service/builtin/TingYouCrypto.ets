/**
 * TingYouCrypto - 听友FM(tingyou.fm) 接口加解密
 *
 * 协议（已抓包逆向验证）：
 * - 响应体：XChaCha20-Poly1305，密文 hex 包在 {"payload":"<hex>"}。
 *   格式 [ver(1)][nonce(24)][ciphertext+tag(16)]；ver==2 时密文整体字节反转。
 *   XChaCha = HChaCha20(key, nonce[0:16]) 派生子钥 + ChaCha20(子钥, nonce=0000+nonce[16:24], counter=1)。
 *   解密只需 ChaCha20 keystream XOR（Poly1305 tag 不校验，服务器可信，坏数据 JSON.parse 自然失败）。
 *   → 纯 TS 实现，零依赖，已在 node 对真实 payload 验证。
 * - 请求体：AES-256-GCM，12 字节随机 IV，格式 [ver=1][iv(12)][ciphertext+tag(16)] → hex，Content-Type: text/plain。
 *   → 用 cryptoFramework（AES-GCM 标准支持）。
 *
 * 密钥 = payloadKey（页面 window.__NUXT__.config.public.payloadKey，hex→32字节）。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

/** payloadKey（硬编码在站点页面里） */
const PAYLOAD_KEY_HEX = 'ea9d9d4f9a983fe6f6382f29c7b46b8d6dc47abc6da36662e6ddff8c78902f65';

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim();
  const n = clean.length >> 1;
  const out = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    const h = bytes[i].toString(16);
    s += h.length === 1 ? '0' + h : h;
  }
  return s;
}

function utf8Decode(bytes: Uint8Array): string {
  return buffer.from(bytes).toString('utf-8');
}

function utf8Encode(str: string): Uint8Array {
  const b = buffer.from(str, 'utf-8');
  const u = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) u[i] = b[i];
  return u;
}

/* ─────────────────────── ChaCha20 / HChaCha20（纯 TS） ─────────────────────── */

function rotl(x: number, n: number): number {
  return ((x << n) | (x >>> (32 - n))) >>> 0;
}

function qr(s: Uint32Array, a: number, b: number, c: number, d: number): void {
  s[a] = (s[a] + s[b]) >>> 0; s[d] = rotl(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) >>> 0; s[b] = rotl(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b]) >>> 0; s[d] = rotl(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) >>> 0; s[b] = rotl(s[b] ^ s[c], 7);
}

function u32le(b: Uint8Array, o: number): number {
  return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
}

/** HChaCha20：从 key(32) + nonce(16) 派生 32 字节子钥 */
function hchacha20(key: Uint8Array, nonce16: Uint8Array): Uint8Array {
  const s = new Uint32Array(16);
  s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574;
  for (let i = 0; i < 8; i++) s[4 + i] = u32le(key, i * 4);
  for (let i = 0; i < 4; i++) s[12 + i] = u32le(nonce16, i * 4);
  for (let r = 0; r < 10; r++) {
    qr(s, 0, 4, 8, 12); qr(s, 1, 5, 9, 13); qr(s, 2, 6, 10, 14); qr(s, 3, 7, 11, 15);
    qr(s, 0, 5, 10, 15); qr(s, 1, 6, 11, 12); qr(s, 2, 7, 8, 13); qr(s, 3, 4, 9, 14);
  }
  const out = new Uint8Array(32);
  const w: number[] = [s[0], s[1], s[2], s[3], s[12], s[13], s[14], s[15]];
  for (let i = 0; i < 8; i++) {
    const v = w[i] >>> 0;
    out[i * 4] = v & 0xff; out[i * 4 + 1] = (v >>> 8) & 0xff;
    out[i * 4 + 2] = (v >>> 16) & 0xff; out[i * 4 + 3] = (v >>> 24) & 0xff;
  }
  return out;
}

/** ChaCha20 流：data XOR keystream(key32, nonce12, 起始 counter) */
function chacha20(key: Uint8Array, nonce12: Uint8Array, counter: number, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  const state = new Uint32Array(16);
  state[0] = 0x61707865; state[1] = 0x3320646e; state[2] = 0x79622d32; state[3] = 0x6b206574;
  for (let i = 0; i < 8; i++) state[4 + i] = u32le(key, i * 4);
  for (let i = 0; i < 3; i++) state[13 + i] = u32le(nonce12, i * 4);
  let blk = counter >>> 0;
  for (let off = 0; off < data.length; off += 64) {
    state[12] = blk >>> 0;
    const w = state.slice();
    for (let r = 0; r < 10; r++) {
      qr(w, 0, 4, 8, 12); qr(w, 1, 5, 9, 13); qr(w, 2, 6, 10, 14); qr(w, 3, 7, 11, 15);
      qr(w, 0, 5, 10, 15); qr(w, 1, 6, 11, 12); qr(w, 2, 7, 8, 13); qr(w, 3, 4, 9, 14);
    }
    const ks = new Uint8Array(64);
    for (let i = 0; i < 16; i++) {
      const v = (w[i] + state[i]) >>> 0;
      ks[i * 4] = v & 0xff; ks[i * 4 + 1] = (v >>> 8) & 0xff;
      ks[i * 4 + 2] = (v >>> 16) & 0xff; ks[i * 4 + 3] = (v >>> 24) & 0xff;
    }
    const n = Math.min(64, data.length - off);
    for (let i = 0; i < n; i++) out[off + i] = data[off + i] ^ ks[i];
    blk = (blk + 1) >>> 0;
  }
  return out;
}

export class TingYouCrypto {
  private static keyBytes: Uint8Array = hexToBytes(PAYLOAD_KEY_HEX);

  /**
   * 解密响应 payload（hex）→ JSON 字符串。同步，纯 TS。
   */
  static decryptResponse(payloadHex: string): string {
    const e = hexToBytes(payloadHex);
    if (e.length < 1 + 24 + 16) {
      throw new Error('payload 长度不足');
    }
    const ver = e[0];
    const nonce = e.subarray(1, 25);
    let data = e.subarray(25);
    if (ver === 2) {
      data = data.slice().reverse();
    }
    const subkey = hchacha20(TingYouCrypto.keyBytes, nonce.subarray(0, 16));
    const nonce12 = new Uint8Array(12);
    nonce12.set(nonce.subarray(16, 24), 4);
    const ct = data.subarray(0, data.length - 16); // 丢弃 Poly1305 tag
    const pt = chacha20(subkey, nonce12, 1, ct);
    return utf8Decode(pt);
  }

  /**
   * 加密请求体：JSON 字符串 → hex 字符串（AES-256-GCM）。
   * 格式 [ver=1][iv(12)][ciphertext+tag(16)]。
   */
  static async encryptRequest(jsonStr: string): Promise<string> {
    const plain = utf8Encode(jsonStr);
    const rand = cryptoFramework.createRandom();
    const ivBlob: cryptoFramework.DataBlob = rand.generateRandomSync(12);
    const iv = ivBlob.data;

    const keyGen = cryptoFramework.createSymKeyGenerator('AES256');
    const keyBlob: cryptoFramework.DataBlob = { data: TingYouCrypto.keyBytes };
    const symKey = await keyGen.convertKey(keyBlob);

    const ivBlobSpec: cryptoFramework.DataBlob = { data: iv };
    const aadBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
    const tagBlob: cryptoFramework.DataBlob = { data: new Uint8Array(16) };
    const gcmParams: cryptoFramework.GcmParamsSpec = {
      iv: ivBlobSpec,
      aad: aadBlob,
      authTag: tagBlob,
      algName: 'GcmParamsSpec',
    };

    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmParams);
    const plainBlob: cryptoFramework.DataBlob = { data: plain };
    const out: cryptoFramework.DataBlob = await cipher.doFinal(plainBlob);
    // GCM doFinal 输出 = ciphertext || authTag(16)
    const ctTag = out.data;

    const result = new Uint8Array(1 + iv.length + ctTag.length);
    result[0] = 1;
    result.set(iv, 1);
    result.set(ctTag, 1 + iv.length);
    return bytesToHex(result);
  }
}
