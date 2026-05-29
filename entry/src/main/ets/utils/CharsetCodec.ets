/**
 * CharsetCodec - 字符集编解码工具
 *
 * - decodeBuffer(bytes, charset)：用 ArkTS util.TextDecoder 把响应字节按 charset 解码
 * - encodeUriForCharset(str, charset)：把字符串按 charset percent-encode（URL query）
 *
 * GBK/GB2312/GB18030 编码侧：HarmonyOS 的 TextEncoder 只支持 UTF-8，
 *   需要自建 Unicode→bytes 反查表。表通过 TextDecoder 反向遍历构建一次后缓存。
 */

import { util } from '@kit.ArkTS';

const ASCII_SAFE = /[A-Za-z0-9_.\-~]/;

let gbkEncodeMap: Map<number, [number, number]> | null = null;

function isUtf8Like(charset: string): boolean {
  const s = charset.toLowerCase().replace(/-/g, '');
  return s === 'utf8' || s === '';
}

function isGbkFamily(charset: string): boolean {
  const s = charset.toLowerCase().replace(/[-_]/g, '');
  return s === 'gbk' || s === 'gb2312' || s === 'gb18030';
}

/** 用 TextDecoder 反向遍历，构造 Unicode codepoint → [lead, trail] 映射。仅 GBK 双字节区。 */
function buildGbkEncodeMap(): Map<number, [number, number]> {
  const decoder = util.TextDecoder.create('gbk', { ignoreBOM: false, fatal: false });
  const map = new Map<number, [number, number]>();
  const buf = new Uint8Array(2);
  for (let lead = 0x81; lead <= 0xFE; lead++) {
    for (let trail = 0x40; trail <= 0xFE; trail++) {
      if (trail === 0x7F) continue;
      buf[0] = lead;
      buf[1] = trail;
      let ch: string;
      try {
        ch = decoder.decodeToString(buf);
      } catch {
        continue;
      }
      if (!ch || ch.length === 0) continue;
      const cp = ch.charCodeAt(0);
      // 跳过解码异常（U+FFFD 替代字符等）
      if (cp === 0xFFFD || cp === 0x3F /* '?' */) {
        // '?' 0x3F 在 GBK 单字节区，二字节区遇到说明无效，跳过
        continue;
      }
      if (!map.has(cp)) {
        map.set(cp, [lead, trail]);
      }
    }
  }
  return map;
}

function getGbkEncodeMap(): Map<number, [number, number]> {
  if (!gbkEncodeMap) {
    gbkEncodeMap = buildGbkEncodeMap();
  }
  return gbkEncodeMap;
}

function pctByte(b: number): string {
  const hex = b.toString(16).toUpperCase();
  return '%' + (hex.length === 1 ? '0' + hex : hex);
}

export class CharsetCodec {
  /** 把响应字节按指定 charset 解码为字符串。charset 为空或 utf-8 走 UTF-8。 */
  static decodeBuffer(bytes: ArrayBuffer, charset?: string): string {
    const cs = (charset || 'utf-8').toLowerCase();
    if (isUtf8Like(cs)) {
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: false, fatal: false });
      return decoder.decodeToString(new Uint8Array(bytes));
    }
    try {
      // util.TextDecoder 支持 'gbk' / 'gb18030' / 'big5' / 'shift_jis' 等
      const normalized = cs === 'gb2312' ? 'gbk' : cs;
      const decoder = util.TextDecoder.create(normalized, { ignoreBOM: false, fatal: false });
      return decoder.decodeToString(new Uint8Array(bytes));
    } catch {
      // 不支持的 charset 退到 UTF-8
      const fallback = util.TextDecoder.create('utf-8', { ignoreBOM: false, fatal: false });
      return fallback.decodeToString(new Uint8Array(bytes));
    }
  }

  /** 按指定 charset percent-encode（用于 URL query）。GBK 系字符按双字节编码。 */
  static encodeUriForCharset(str: string, charset?: string): string {
    if (!str) return '';
    const cs = (charset || 'utf-8').toLowerCase();
    if (isUtf8Like(cs)) {
      return encodeURIComponent(str);
    }
    if (!isGbkFamily(cs)) {
      // 其它非 UTF-8 字符集暂回退到 UTF-8（极少书源用 EUC/Shift_JIS）
      return encodeURIComponent(str);
    }
    const map = getGbkEncodeMap();
    let out = '';
    for (let i = 0; i < str.length; i++) {
      const ch = str[i];
      const cp = str.charCodeAt(i);
      // ASCII 安全字符直出
      if (cp < 0x80 && ASCII_SAFE.test(ch)) {
        out += ch;
        continue;
      }
      // ASCII 但非安全：保留斜杠/冒号/问号等保留字符的处理交给调用方，这里按 percent-encode 单字节
      if (cp < 0x80) {
        out += pctByte(cp);
        continue;
      }
      // 非 ASCII：查 GBK 映射
      const pair = map.get(cp);
      if (pair) {
        out += pctByte(pair[0]) + pctByte(pair[1]);
      } else {
        // 不在 GBK 范围（如 emoji），退到 UTF-8 编码
        out += encodeURIComponent(ch);
      }
    }
    return out;
  }
}
