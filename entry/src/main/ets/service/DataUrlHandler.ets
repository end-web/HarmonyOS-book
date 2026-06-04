/**
 * DataUrlHandler - data:base64 URL 解码器
 *
 * 处理 Legado 书源中的 data:;base64,{encoded_json},{config} 格式 URL。
 * 这是光遇聚合等代理书源的核心路由机制。
 *
 * 格式: data:;base64,{base64_encoded_json},{json_config}
 *   - base64_encoded_json: 编码的业务数据（book_id, source, tab 等）
 *   - json_config: 包含 type 字段（gydetail/gycatalog/gycontent/gysearch）
 */

const TAG = 'DataUrlHandler';

export interface DataUrlParseResult {
  data: Record<string, Object>;
  config: Record<string, Object>;
}

export class DataUrlHandler {
  /**
   * 检测 URL 是否为 data: 格式
   */
  static isDataUrl(url: string): boolean {
    return url.startsWith('data:');
  }

  /**
   * 解析 data: URL，提取编码的 JSON 数据和配置
   *
   * 支持的格式：
   *   data:;base64,{base64_json},{config_json}
   *   data:;base64,{base64_json}
   *   data:text/plain;base64,{base64_json}
   */
  static parse(dataUrl: string): DataUrlParseResult | null {
    try {
      // 去掉 data: 前缀，找到 base64, 标记
      const base64Idx = dataUrl.indexOf('base64,');
      if (base64Idx < 0) return null;

      const encoded = dataUrl.substring(base64Idx + 7);
      if (!encoded) return null;

      // 格式: {base64_data},{config_json}
      // config_json 是最后一个 {...} 块
      let base64Part = encoded;
      let configPart = '';

      // 从后往前找最后一个完整的 {...} 作为 config
      const lastBraceStart = encoded.lastIndexOf(',{');
      if (lastBraceStart > 0) {
        const afterComma = encoded.substring(lastBraceStart + 1);
        // 验证是完整的 JSON 对象
        if (afterComma.startsWith('{') && afterComma.endsWith('}')) {
          try {
            JSON.parse(afterComma);
            base64Part = encoded.substring(0, lastBraceStart);
            configPart = afterComma;
          } catch {
            // 不是有效 JSON，整个字符串都是 base64 数据
          }
        }
      }

      // 解码 base64
      const decoded = DataUrlHandler.base64Decode(base64Part);
      if (!decoded) return null;

      const data: Record<string, Object> = JSON.parse(decoded) as Record<string, Object>;
      const config: Record<string, Object> = configPart ? JSON.parse(configPart) as Record<string, Object> : {};

      const result: DataUrlParseResult = { data, config };
      return result;
    } catch (e) {
      console.error(`[${TAG}] parse error: ${e}`);
      return null;
    }
  }

  /**
   * Base64 解码（支持 UTF-8）
   */
  static base64Decode(s: string): string {
    if (!s) return '';
    try {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      const map: Map<string, number> = new Map();
      for (let i = 0; i < alphabet.length; i++) {
        map.set(alphabet.charAt(i), i);
      }
      const bytes: number[] = [];
      const clean = s.replace(/[^A-Za-z0-9+/=]/g, '');
      for (let i = 0; i < clean.length; i += 4) {
        const c1 = map.get(clean.charAt(i)) ?? 0;
        const c2 = map.get(clean.charAt(i + 1)) ?? 0;
        const c3 = map.get(clean.charAt(i + 2)) ?? 0;
        const c4 = map.get(clean.charAt(i + 3)) ?? 0;
        bytes.push(((c1 << 2) | (c2 >> 4)) & 0xFF);
        if (clean.charAt(i + 2) !== '=') bytes.push(((c2 << 4) | (c3 >> 2)) & 0xFF);
        if (clean.charAt(i + 3) !== '=') bytes.push(((c3 << 6) | c4) & 0xFF);
      }
      // UTF-8 bytes -> string
      let out = '';
      let i = 0;
      while (i < bytes.length) {
        const b = bytes[i++];
        if (b < 0x80) {
          out += String.fromCharCode(b);
        } else if (b < 0xC0) {
          continue;
        } else if (b < 0xE0) {
          out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i++] & 0x3F));
        } else if (b < 0xF0) {
          out += String.fromCharCode(((b & 0xF) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
        } else {
          const cp = ((b & 0x7) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F);
          out += String.fromCodePoint(cp);
        }
      }
      return out;
    } catch {
      return '';
    }
  }

  /**
   * Base64 编码（支持 UTF-8）
   */
  static base64Encode(s: string): string {
    if (!s) return '';
    try {
      const bytes: number[] = [];
      for (let i = 0; i < s.length; i++) {
        const cp = s.charCodeAt(i);
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
          const cp2 = 0x10000 + (((cp & 0x3FF) << 10) | (s.charCodeAt(i) & 0x3FF));
          bytes.push(0xF0 | (cp2 >> 18));
          bytes.push(0x80 | ((cp2 >> 12) & 0x3F));
          bytes.push(0x80 | ((cp2 >> 6) & 0x3F));
          bytes.push(0x80 | (cp2 & 0x3F));
        }
      }
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      let out = '';
      for (let i = 0; i < bytes.length; i += 3) {
        const b1 = bytes[i];
        const b2 = i + 1 < bytes.length ? bytes[i + 1] : -1;
        const b3 = i + 2 < bytes.length ? bytes[i + 2] : -1;
        out += alphabet.charAt((b1 >> 2) & 0x3F);
        out += alphabet.charAt(((b1 & 0x3) << 4) | (((b2 < 0 ? 0 : b2) >> 4) & 0x3F));
        out += b2 < 0 ? '=' : alphabet.charAt(((b2 & 0xF) << 2) | (((b3 < 0 ? 0 : b3) >> 6) & 0x3F));
        out += b3 < 0 ? '=' : alphabet.charAt(b3 & 0x3F);
      }
      return out;
    } catch {
      return '';
    }
  }
}
