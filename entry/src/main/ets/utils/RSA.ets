/**
 * RSA - 纯 JS RSA 加密实现
 *
 * 支持 RSA/ECB/PKCS1Padding（书源最常用模式）
 * 从 PEM 格式或 hex 字符串解析公钥
 */

import { BigInteger } from './BigInt';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * 生成密码学安全的随机非零字节（用于 PKCS1 v1.5 padding）
 * 使用 HarmonyOS cryptoFramework，失败时回退到 Math.random（仅极端情况）
 */
function secureRandomNonZero(length: number): number[] {
  const result: number[] = [];
  try {
    const random = cryptoFramework.createRandom();
    // 多请求一倍字节，过滤零字节后通常足够
    const blob: cryptoFramework.DataBlob = random.generateRandomSync(length * 2);
    const data: Uint8Array = blob.data;
    for (let i = 0; i < data.length && result.length < length; i++) {
      const b: number = data[i] & 0xFF;
      if (b !== 0) {
        result.push(b);
      }
    }
    // 极端情况：零字节太多导致不够，再补一轮
    while (result.length < length) {
      const extra: cryptoFramework.DataBlob = random.generateRandomSync(length);
      const edata: Uint8Array = extra.data;
      for (let i = 0; i < edata.length && result.length < length; i++) {
        const b: number = edata[i] & 0xFF;
        if (b !== 0) {
          result.push(b);
        }
      }
    }
  } catch (e) {
    // 回退：cryptoFramework 不可用时（不应发生），用 Math.random 兜底
    for (let i = 0; i < length; i++) {
      let rnd: number;
      do {
        rnd = Math.floor(Math.random() * 256);
      } while (rnd === 0);
      result.push(rnd);
    }
  }
  return result;
}

interface RSAKey {
  n: BigInteger; // modulus
  e: BigInteger; // public exponent
}

/**
 * RSA 加密（RSA/ECB/PKCS1Padding）
 * @param data 要加密的数据（UTF-8 字符串或 hex 编码的字节）
 * @param keyModulus 公钥模数 N（hex 字符串或 base64 编码）
 * @param keyExponent 公钥指数 E（hex 字符串，默认 0x10001 即 65537）
 * @returns 加密后的 hex 字符串
 */
export function rsaEncrypt(data: string, keyModulus: string, keyExponent?: string): string {
  // 解析密钥
  const n = new BigInteger(cleanHex(keyModulus));
  const e = new BigInteger(keyExponent ? cleanHex(keyExponent) : '10001');

  // 将数据转换为字节数组
  const dataBytes = stringToBytes(data);
  const keyLen = Math.ceil(n.toHex().length / 2); // 密钥长度（字节）

  // PKCS1 v1.5 padding
  // 格式：0x00 0x02 [随机非零字节] 0x00 [数据]
  // 最小 padding 长度 = 11 字节（00 02 + 至少8字节随机 + 00）
  if (dataBytes.length > keyLen - 11) {
    throw new Error('Data too long for RSA key size');
  }

  const padded: number[] = [];
  padded.push(0x00);
  padded.push(0x02); // Block type 2 (encryption)

  // 随机填充（非零字节，使用密码学安全随机数）
  const padLen = keyLen - dataBytes.length - 3;
  const randomBytes = secureRandomNonZero(padLen);
  for (let i = 0; i < padLen; i++) {
    padded.push(randomBytes[i]);
  }

  padded.push(0x00);
  padded.push(...dataBytes);

  // 转换为大数
  const paddedHex = bytesToHex(padded);
  const m = new BigInteger(paddedHex);

  // RSA 加密：c = m^e mod n
  const c = m.modPow(e, n);

  // 输出为 hex，补齐到密钥长度
  let result = c.toHex();
  while (result.length < keyLen * 2) {
    result = '0' + result;
  }
  return result;
}

/**
 * RSA 解密（RSA/ECB/PKCS1Padding）
 * @param cipherHex 密文 hex 字符串
 * @param keyModulus 私钥模数 N
 * @param keyExponent 私钥指数 D
 * @returns 解密后的字符串
 */
export function rsaDecrypt(cipherHex: string, keyModulus: string, keyExponent: string): string {
  const n = new BigInteger(cleanHex(keyModulus));
  const d = new BigInteger(cleanHex(keyExponent));

  const c = new BigInteger(cleanHex(cipherHex));
  const m = c.modPow(d, n);

  // 转换为字节数组
  let hex = m.toHex();
  if (hex.length % 2 !== 0) hex = '0' + hex;
  const bytes = hexToBytes(hex);

  // 去除 PKCS1 padding
  // 格式：0x00 0x02 [随机字节] 0x00 [数据]
  if (bytes.length < 2 || bytes[0] !== 0x00 || bytes[1] !== 0x02) {
    throw new Error('Invalid PKCS1 padding');
  }

  let i = 2;
  while (i < bytes.length && bytes[i] !== 0x00) {
    i++;
  }
  if (i >= bytes.length) {
    throw new Error('Invalid PKCS1 padding: no separator found');
  }

  // 跳过 0x00 分隔符
  i++;

  // 返回数据部分
  const dataBytes = bytes.slice(i);
  return bytesToString(dataBytes);
}

/**
 * 从 PEM 格式解析 RSA 公钥
 * 支持：-----BEGIN PUBLIC KEY----- ... -----END PUBLIC KEY-----
 */
export function parsePublicKeyPEM(pem: string): RSAKey {
  // 提取 base64 内容
  const b64 = pem
    .replace(/-----BEGIN[^-]+-----/, '')
    .replace(/-----END[^-]+-----/, '')
    .replace(/\s+/g, '');

  const der = base64ToBytes(b64);

  // 解析 PKCS#8 DER 格式的公钥
  // 简化：查找模数和指数的位置
  // 典型 DER 结构：SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING { SEQUENCE { modulus, exponent } } }
  const result = parseRSAPublicKeyDER(der);
  return result;
}

/**
 * 解析 DER 编码的 RSA 公钥
 */
function parseRSAPublicKeyDER(der: number[]): RSAKey {
  // 简化解析：在 DER 数据中查找两个大的 INTEGER
  // RSA 公钥的关键是找到模数 N 和指数 E
  const integers: string[] = [];
  let i = 0;

  while (i < der.length) {
    const tag = der[i++];
    if (tag === 0x02) {
      // INTEGER
      let len = der[i++];
      if (len & 0x80) {
        const numBytes = len & 0x7F;
        len = 0;
        for (let j = 0; j < numBytes; j++) {
          len = (len << 8) | der[i++];
        }
      }
      // 读取整数值（跳过前导零）
      let hex = '';
      for (let j = 0; j < len; j++) {
        const b = der[i + j];
        if (hex === '' && b === 0) continue;
        hex += b.toString(16).padStart(2, '0');
      }
      if (hex === '') hex = '0';
      integers.push(hex);
      i += len;
    } else if (tag === 0x30 || tag === 0x03) {
      // SEQUENCE or BIT STRING — 跳过长度
      let len = der[i++];
      if (len & 0x80) {
        const numBytes = len & 0x7F;
        len = 0;
        for (let j = 0; j < numBytes; j++) {
          len = (len << 8) | der[i++];
        }
      }
      if (tag === 0x03 && der[i] === 0x00) {
        i++; // BIT STRING 的 unused bits 字节
      }
    } else {
      // 其他标签，跳过
      let len = der[i++];
      if (len & 0x80) {
        const numBytes = len & 0x7F;
        len = 0;
        for (let j = 0; j < numBytes; j++) {
          len = (len << 8) | der[i++];
        }
      }
      i += len;
    }
  }

  // 在 RSA 公钥中，第一个大整数是模数 N，第二个是指数 E
  if (integers.length < 2) {
    throw new Error('Invalid RSA public key format');
  }

  // E 通常很小（65537 = 0x10001），N 很大
  // 如果第一个整数很小（< 8 字节），它可能是 E，第二个是 N
  let nHex: string;
  let eHex: string;

  if (integers[0].length <= 16 && integers.length >= 2) {
    // 第一个很短，可能是 E
    eHex = integers[0];
    nHex = integers[1];
  } else {
    nHex = integers[0];
    eHex = integers.length > 1 ? integers[1] : '10001';
  }

  return {
    n: new BigInteger(nHex),
    e: new BigInteger(eHex),
  };
}

// ──────────── 工具函数 ────────────

function cleanHex(hex: string): string {
  // 移除空格、换行、0x 前缀
  return hex.replace(/\s+/g, '').replace(/^0x/i, '').replace(/^0+/, '') || '0';
}

function stringToBytes(str: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    const cp = str.charCodeAt(i);
    if (cp < 0x80) {
      bytes.push(cp);
    } else if (cp < 0x800) {
      bytes.push(0xC0 | (cp >> 6));
      bytes.push(0x80 | (cp & 0x3F));
    } else if (cp < 0xD800 || cp >= 0xE000) {
      bytes.push(0xE0 | (cp >> 12));
      bytes.push(0x80 | ((cp >> 6) & 0x3F));
      bytes.push(0x80 | (cp & 0x3F));
    } else {
      i++;
      const cp2 = 0x10000 + (((cp & 0x3FF) << 10) | (str.charCodeAt(i) & 0x3FF));
      bytes.push(0xF0 | (cp2 >> 18));
      bytes.push(0x80 | ((cp2 >> 12) & 0x3F));
      bytes.push(0x80 | ((cp2 >> 6) & 0x3F));
      bytes.push(0x80 | (cp2 & 0x3F));
    }
  }
  return bytes;
}

function bytesToString(bytes: number[]): string {
  let result = '';
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i++];
    if (b < 0x80) {
      result += String.fromCharCode(b);
    } else if (b < 0xC0) {
      continue;
    } else if (b < 0xE0) {
      result += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i++] & 0x3F));
    } else if (b < 0xF0) {
      result += String.fromCharCode(((b & 0xF) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
    } else {
      const cp = ((b & 0x7) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F);
      result += String.fromCodePoint(cp);
    }
  }
  return result;
}

function bytesToHex(bytes: number[]): string {
  return bytes.map((b) => b.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16));
  }
  return bytes;
}

function base64ToBytes(b64: string): number[] {
  const helper = new util.Base64Helper();
  const decoded = helper.decodeSync(b64);
  const bytes: number[] = [];
  for (let i = 0; i < decoded.length; i++) {
    bytes.push((decoded[i] as number) & 0xFF);
  }
  return bytes;
}
