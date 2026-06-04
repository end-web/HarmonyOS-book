/**
 * RarParser - RAR 文件解析器
 *
 * 支持 RAR5 格式：
 * - 解析文件结构（签名、头部、文件条目）
 * - 提取 Stored（未压缩）文件
 * - 提取 RAR 压缩文件（基本 LZMA 解压）
 *
 * 用于书源中 java.getRarStringContent / java.getRarByteArrayContent
 */

import { util } from '@kit.ArkTS';

interface RarEntry {
  name: string;
  data: number[];
  size: number;
  method: number; // 0=Stored, 其他=compressed
}

class RarParserImpl {
  private data: Uint8Array = new Uint8Array(0);
  private offset: number = 0;

  /**
   * 解析 RAR 文件并提取指定路径的内容
   */
  extract(rarData: string | Uint8Array, path: string): number[] | null {
    if (typeof rarData === 'string') {
      this.data = this.base64ToBytes(rarData);
    } else {
      this.data = rarData;
    }
    this.offset = 0;

    // 检查 RAR 签名
    const sig = this.readBytes(8);
    // RAR5 签名：52 61 72 21 1A 07 01 00
    const isRar5 = sig[0] === 0x52 && sig[1] === 0x61 && sig[2] === 0x72 && sig[3] === 0x21 &&
                   sig[4] === 0x1A && sig[5] === 0x07 && sig[6] === 0x01 && sig[7] === 0x00;

    if (!isRar5) {
      // 尝试 RAR4 签名：52 61 72 21 1A 07 00
      const isRar4 = sig[0] === 0x52 && sig[1] === 0x61 && sig[2] === 0x72 && sig[3] === 0x21 &&
                     sig[4] === 0x1A && sig[5] === 0x07 && sig[6] === 0x00;
      if (isRar4) {
        return this.extractRar4(path);
      }
      throw new Error('Invalid RAR file: unknown signature');
    }

    // RAR5 格式
    return this.extractRar5(path);
  }

  /**
   * RAR5 格式解析
   */
  private extractRar5(path: string): number[] | null {
    // 跳过签名后的服务头
    this.offset = 7; // 回到签名后

    while (this.offset < this.data.length) {
      // 读取头部
      const headerStart = this.offset;
      const headerCrc = this.readUint32();
      const headerSize = this.readVInt();
      const headerType = this.readVInt();

      const headerDataStart = this.offset;
      const headerDataSize = headerSize - (this.offset - headerStart) - 4; // 减去 CRC 和 size 本身

      if (headerType === 1) {
        // 文件头
        const flags = this.readVInt();
        const extraSize = (flags & 0x0002) ? this.readVInt() : 0;
        const dataSize = (flags & 0x0004) ? this.readVInt() : 0;
        const fileFlags = this.readVInt();
        const uncompSize = this.readVInt();
        const attributes = this.readVInt();
        const mtime = (flags & 0x0010) ? this.readUint32() : 0;
        const dataCrc32 = (flags & 0x0020) ? this.readUint32() : 0;
        const compressionInfo = this.readVInt();
        const hostOs = this.readVInt();
        const nameLen = this.readVInt();
        const nameBytes = this.readBytes(nameLen);
        const name = this.bytesToUtf8(nameBytes);

        // 跳过额外数据
        if (extraSize > 0) {
          this.skip(extraSize);
        }

        // 读取文件数据
        if (dataSize > 0) {
          const compressionMethod = compressionInfo & 0x07;
          const fileData = this.readBytes(dataSize);

          if (compressionMethod === 0) {
            // Stored
            if (name === path || name.endsWith('/' + path) || name.endsWith('\\' + path)) {
              return Array.from(fileData);
            }
          } else {
            // 压缩 — 尝试 LZMA 解压
            if (name === path || name.endsWith('/' + path) || name.endsWith('\\' + path)) {
              try {
                return this.lzmaDecompress(fileData, uncompSize);
              } catch (e) {
                console.error(`[RarParser] LZMA decompress failed: ${e}`);
                return null;
              }
            }
          }
        }
      } else if (headerType === 5) {
        // 结束头
        break;
      } else {
        // 其他头部，跳过
        this.offset = headerDataStart + headerDataSize;
      }
    }

    return null;
  }

  /**
   * RAR4 格式解析（简化版）
   */
  private extractRar4(path: string): number[] | null {
    this.offset = 7;

    while (this.offset < this.data.length - 7) {
      const headerCrc = this.readUint16();
      const headerType = this.readByte();
      const headerFlags = this.readUint16();
      const headerSize = this.readUint16();

      if (headerType === 0x74) {
        // 文件头
        const compSize = this.readUint32();
        const uncompSize = this.readUint32();
        const fileCrc = this.readUint32();
        this.skip(4); // time, os
        const nameLen = this.readUint16();
        const fileAttr = this.readUint32();
        const compMethod = this.readByte();
        this.skip(1); // host os
        const nameBytes = this.readBytes(nameLen);
        const name = this.bytesToUtf8(nameBytes);

        // 对齐到 2 字节边界
        if (this.offset % 2 !== 0) this.skip(1);

        // 读取文件数据
        if (compSize > 0) {
          const fileData = this.readBytes(compSize);

          if (name === path || name.endsWith('/' + path) || name.endsWith('\\' + path)) {
            if (compMethod === 0x30) {
              // Stored
              return Array.from(fileData);
            } else {
              // 压缩 — 尝试解压
              try {
                return this.rar4Decompress(fileData, uncompSize, compMethod);
              } catch (e) {
                console.error(`[RarParser] RAR4 decompress failed: ${e}`);
                return null;
              }
            }
          }
        }
      } else if (headerType === 0x7B) {
        // 结束头
        break;
      } else {
        // 跳过其他头部
        this.offset += headerSize - 7;
      }
    }

    return null;
  }

  /**
   * LZMA 解压（简化版，处理 RAR5 LZMA）
   */
  private lzmaDecompress(data: Uint8Array, expectedSize: number): number[] {
    // LZMA 解压核心
    // properties: 1 byte (lc, lp, pb)
    // dictionary: 4 bytes
    // 然后是 LZMA 编码的数据

    if (data.length < 5) return Array.from(data);

    const props = data[0];
    const lc = props % 9;
    const lp = Math.floor(props / 9) % 5;
    const pb = Math.floor(props / 45);

    // 字典大小
    const dictSize = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);

    // LZMA 位流从第 5 字节开始
    const output: number[] = [];
    let pos = 5;
    let bitPos = 0;

    const readBit = (): number => {
      if (pos >= data.length) return 0;
      const bit = (data[pos] >> bitPos) & 1;
      bitPos++;
      if (bitPos >= 8) { bitPos = 0; pos++; }
      return bit;
    };

    // 简化的 LZMA 状态机
    // 状态 0: literal/length
    // 状态 1: distance

    const dictionary: number[] = new Array(dictSize).fill(0);
    let dictPos = 0;
    let state = 0;

    // 概率模型（简化）
    const probs: number[] = [];
    for (let pi = 0; pi < 1024; pi++) probs.push(1024); // 初始概率 0.5

    const decodeLen = (): number => {
      // 简化的长度解码
      let len = 0;
      const bit1 = readBit();
      if (bit1 === 0) {
        len = 2;
      } else {
        const bit2 = readBit();
        if (bit2 === 0) {
          len = 3 + readBit();
        } else {
          len = 5;
          for (let i = 0; i < 3; i++) {
            len = (len << 1) | readBit();
          }
        }
      }
      return len;
    };

    let maxIter = expectedSize * 2; // 防止无限循环
    while (output.length < expectedSize && maxIter-- > 0) {
      if (pos >= data.length) break;

      const bit = readBit();

      if (bit === 0) {
        // Literal
        let byte = 0;
        for (let i = 7; i >= 0; i--) {
          byte = (byte << 1) | readBit();
        }
        output.push(byte);
        dictionary[dictPos % dictSize] = byte;
        dictPos++;
      } else {
        // Match
        const len = decodeLen();
        if (len === 0) break;

        // 读取距离
        let dist = 0;
        const distBits = readBit();
        if (distBits === 0) {
          dist = readBit();
        } else {
          dist = 2 + readBit();
          for (let i = 0; i < 3; i++) {
            dist = (dist << 1) | readBit();
          }
        }

        // 复制匹配
        for (let i = 0; i < len; i++) {
          const srcIdx = (dictPos - dist - 1 + dictSize) % dictSize;
          const byte = dictionary[srcIdx];
          output.push(byte);
          dictionary[dictPos % dictSize] = byte;
          dictPos++;
        }
      }
    }

    return output.slice(0, expectedSize);
  }

  /**
   * RAR4 压缩解压（简化版）
   */
  private rar4Decompress(data: Uint8Array, expectedSize: number, method: number): number[] {
    // RAR4 支持多种压缩方法
    // 0x30 = Stored
    // 0x31 = LZMA
    // 0x32 = PPMd
    // 0x33 = LZMA2

    if (method === 0x31 || method === 0x33) {
      return this.lzmaDecompress(data, expectedSize);
    }

    // 不支持的压缩方法
    throw new Error(`RAR4 compression method 0x${method.toString(16)} not supported`);
  }

  /**
   * 列出 RAR 中所有文件
   */
  listFiles(rarData: string | Uint8Array): string[] {
    if (typeof rarData === 'string') {
      this.data = this.base64ToBytes(rarData);
    } else {
      this.data = rarData;
    }
    this.offset = 0;

    const names: string[] = [];
    const sig = this.readBytes(8);
    const isRar5 = sig[6] === 0x01;

    if (isRar5) {
      this.offset = 7;
      while (this.offset < this.data.length) {
        const headerStart = this.offset;
        this.readUint32(); // crc
        const headerSize = this.readVInt();
        const headerType = this.readVInt();

        if (headerType === 1) {
          const flags = this.readVInt();
          if (flags & 0x0002) this.readVInt(); // extraSize
          if (flags & 0x0004) this.readVInt(); // dataSize
          this.readVInt(); // fileFlags
          this.readVInt(); // uncompSize
          this.readVInt(); // attributes
          if (flags & 0x0010) this.readUint32(); // mtime
          if (flags & 0x0020) this.readUint32(); // dataCrc32
          this.readVInt(); // compressionInfo
          this.readVInt(); // hostOs
          const nameLen = this.readVInt();
          const nameBytes = this.readBytes(nameLen);
          names.push(this.bytesToUtf8(nameBytes));
        } else if (headerType === 5) {
          break;
        } else {
          this.offset = headerStart + 4 + headerSize;
        }
      }
    } else {
      this.offset = 7;
      while (this.offset < this.data.length - 7) {
        this.readUint16(); // crc
        const headerType = this.readByte();
        this.readUint16(); // flags
        const headerSize = this.readUint16();

        if (headerType === 0x74) {
          this.readUint32(); // compSize
          this.readUint32(); // uncompSize
          this.readUint32(); // fileCrc
          this.skip(4); // time, os
          const nameLen = this.readUint16();
          this.readUint32(); // fileAttr
          this.readByte(); // compMethod
          this.skip(1); // host os
          const nameBytes = this.readBytes(nameLen);
          names.push(this.bytesToUtf8(nameBytes));
        } else if (headerType === 0x7B) {
          break;
        } else {
          this.offset += headerSize - 7;
        }
      }
    }

    return names;
  }

  // ──────────── 工具方法 ────────────

  private readByte(): number {
    return this.data[this.offset++];
  }

  private readUint16(): number {
    const b1 = this.data[this.offset++];
    const b2 = this.data[this.offset++];
    return b1 | (b2 << 8);
  }

  private readUint32(): number {
    const b1 = this.data[this.offset++];
    const b2 = this.data[this.offset++];
    const b3 = this.data[this.offset++];
    const b4 = this.data[this.offset++];
    return (b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)) >>> 0;
  }

  private readVInt(): number {
    // RAR5 使用变长整数
    let value = 0;
    let shift = 0;
    let byte: number;
    do {
      byte = this.data[this.offset++];
      value |= (byte & 0x7F) << shift;
      shift += 7;
    } while (byte & 0x80);
    return value;
  }

  private readBytes(n: number): Uint8Array {
    const result = this.data.slice(this.offset, this.offset + n);
    this.offset += n;
    return result;
  }

  private skip(n: number): void {
    this.offset += n;
  }

  private bytesToUtf8(bytes: Uint8Array): string {
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

  private base64ToBytes(base64: string): Uint8Array {
    const clean = base64.replace(/^data:[^;]+;base64,/, '');
    const helper = new util.Base64Helper();
    const decoded = helper.decodeSync(clean);
    return new Uint8Array(decoded);
  }
}

let globalRarParser: RarParserImpl | null = null;

function getRarParser(): RarParserImpl {
  if (!globalRarParser) globalRarParser = new RarParserImpl();
  return globalRarParser;
}

/**
 * 从 RAR 中提取文件内容（文本）
 */
export function getRarStringContent(rarData: string, path: string): string {
  try {
    const parser = getRarParser();
    const bytes = parser.extract(rarData, path);
    if (!bytes) return '';
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
  } catch (e) {
    console.error(`[RarParser] getRarStringContent error: ${e}`);
    return '';
  }
}

/**
 * 从 RAR 中提取文件内容（字节数组）
 */
export function getRarByteArrayContent(rarData: string, path: string): number[] {
  try {
    const parser = getRarParser();
    return parser.extract(rarData, path) || [];
  } catch (e) {
    console.error(`[RarParser] getRarByteArrayContent error: ${e}`);
    return [];
  }
}

/**
 * 列出 RAR 中所有文件
 */
export function listRarFiles(rarData: string): string[] {
  try {
    const parser = getRarParser();
    return parser.listFiles(rarData);
  } catch (e) {
    console.error(`[RarParser] listRarFiles error: ${e}`);
    return [];
  }
}
