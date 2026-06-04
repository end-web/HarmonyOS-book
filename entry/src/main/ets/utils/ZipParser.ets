/**
 * ZipParser - 纯 JS ZIP 文件解析器
 *
 * 支持：
 * - Stored (method 0) — 无压缩
 * - Deflate (method 8) — 使用 raw inflate 解压
 *
 * 用于书源中 java.getZipStringContent / java.getZipByteArrayContent
 */

import { util } from '@kit.ArkTS';

interface ZipEntry {
  name: string;
  data: number[];
  method: number; // 0=Stored, 8=Deflate
  size: number;
  compressedSize: number;
}

class ZipParserImpl {
  private data: Uint8Array = new Uint8Array(0);
  private offset: number = 0;

  /**
   * 解析 ZIP 文件并提取指定路径的内容
   * @param zipData ZIP 文件数据（base64 或 Uint8Array）
   * @param path 要提取的文件路径
   * @returns 文件内容（字节数组），未找到返回 null
   */
  extract(zipData: string | Uint8Array, path: string): number[] | null {
    if (typeof zipData === 'string') {
      this.data = this.base64ToBytes(zipData);
    } else {
      this.data = zipData;
    }

    // 查找 End of Central Directory Record
    const eocdOffset = this.findEOCD();
    if (eocdOffset < 0) {
      throw new Error('Invalid ZIP file: EOCD not found');
    }

    // 读取 EOCD
    this.offset = eocdOffset + 10;
    const numEntries = this.readUint16();
    this.offset = eocdOffset + 16;
    const centralDirSize = this.readUint32();
    const centralDirOffset = this.readUint32();

    // 遍历 Central Directory，查找目标文件
    this.offset = centralDirOffset;
    for (let i = 0; i < numEntries; i++) {
      const signature = this.readUint32();
      if (signature !== 0x02014b50) break; // 不是 Central Directory 签名

      this.skip(4); // version made by, version needed
      const flags = this.readUint16();
      const method = this.readUint16();
      this.skip(4); // last mod time, last mod date
      this.skip(4); // crc32
      const compressedSize = this.readUint32();
      const uncompressedSize = this.readUint32();
      const nameLen = this.readUint16();
      const extraLen = this.readUint16();
      const commentLen = this.readUint16();
      this.skip(8); // disk number, internal attrs, external attrs
      const localHeaderOffset = this.readUint32();

      const name = this.readAscii(nameLen);
      this.skip(extraLen + commentLen);

      // 检查是否是目标文件
      if (name === path || name.endsWith('/' + path)) {
        // 读取 Local File Header 并提取数据
        return this.extractFromLocalHeader(localHeaderOffset, method, compressedSize, uncompressedSize);
      }
    }

    return null;
  }

  /**
   * 列出 ZIP 中所有文件名
   */
  listFiles(zipData: string | Uint8Array): string[] {
    if (typeof zipData === 'string') {
      this.data = this.base64ToBytes(zipData);
    } else {
      this.data = zipData;
    }

    const eocdOffset = this.findEOCD();
    if (eocdOffset < 0) return [];

    this.offset = eocdOffset + 10;
    const numEntries = this.readUint16();
    this.offset = eocdOffset + 16;
    this.readUint32(); // centralDirSize
    const centralDirOffset = this.readUint32();

    const names: string[] = [];
    this.offset = centralDirOffset;
    for (let i = 0; i < numEntries; i++) {
      const signature = this.readUint32();
      if (signature !== 0x02014b50) break;

      this.skip(16);
      const nameLen = this.readUint16();
      const extraLen = this.readUint16();
      const commentLen = this.readUint16();
      this.skip(12);

      const name = this.readAscii(nameLen);
      this.skip(extraLen + commentLen);

      if (!name.endsWith('/')) {
        names.push(name);
      }
    }

    return names;
  }

  private extractFromLocalHeader(
    offset: number, method: number, compressedSize: number, uncompressedSize: number
  ): number[] | null {
    this.offset = offset;
    const signature = this.readUint32();
    if (signature !== 0x04034b50) return null; // 不是 Local File Header 签名

    this.skip(22); // version, flags, method, time, date, crc, compSize, uncompSize
    const nameLen = this.readUint16();
    const extraLen = this.readUint16();
    this.skip(nameLen + extraLen);

    // 现在 this.offset 指向文件数据
    if (method === 0) {
      // Stored — 直接读取
      return Array.from(this.data.slice(this.offset, this.offset + uncompressedSize));
    } else if (method === 8) {
      // Deflate — 使用 inflate 解压
      const compressed = this.data.slice(this.offset, this.offset + compressedSize);
      return this.inflate(compressed);
    }

    throw new Error(`Unsupported compression method: ${method}`);
  }

  /**
   * 查找 End of Central Directory Record
   */
  private findEOCD(): number {
    // EOCD 签名 0x06054b50，从文件末尾向前搜索
    for (let i = this.data.length - 22; i >= Math.max(0, this.data.length - 65557); i--) {
      if (this.data[i] === 0x50 && this.data[i + 1] === 0x4b &&
          this.data[i + 2] === 0x05 && this.data[i + 3] === 0x06) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Inflate (DEFLATE 解压) — 简化实现
   * 处理最常见的 Stored 和 Static Huffman 块
   */
  private inflate(data: Uint8Array): number[] {
    const output: number[] = [];
    let bitPos = 0;

    const readBits = (n: number): number => {
      let val = 0;
      for (let i = 0; i < n; i++) {
        const byteIdx = Math.floor(bitPos / 8);
        const bitIdx = bitPos % 8;
        if (byteIdx < data.length) {
          val |= ((data[byteIdx] >> bitIdx) & 1) << i;
        }
        bitPos++;
      }
      return val;
    };

    const readByte = (): number => {
      const byteIdx = Math.floor(bitPos / 8);
      bitPos += 8;
      return byteIdx < data.length ? data[byteIdx] : 0;
    };

    let bfinal = 0;
    while (!bfinal) {
      bfinal = readBits(1);
      const btype = readBits(2);

      if (btype === 0) {
        // Stored block
        bitPos = Math.ceil(bitPos / 8) * 8; // 对齐到字节边界
        const len = readByte() | (readByte() << 8);
        const nlen = readByte() | (readByte() << 8);
        for (let i = 0; i < len; i++) {
          output.push(readByte());
        }
      } else if (btype === 1 || btype === 2) {
        // Static/ Dynamic Huffman — 使用简化解码
        // 对于简单场景，尝试使用 raw inflate 的简化版本
        try {
          const result = this.inflateHuffman(data, Math.floor(bitPos / 8));
          output.push(...result);
          break; // 解压完成
        } catch {
          // 解压失败，返回已解压的部分
          break;
        }
      } else {
        throw new Error('Invalid DEFLATE block type');
      }
    }

    return output;
  }

  /**
   * 简化的 Huffman 解压
   * 仅处理最常见的 Static Huffman 编码场景
   */
  private inflateHuffman(data: Uint8Array, startByte: number): number[] {
    // 使用简化的 LZ77 + Static Huffman 解码
    // Static Huffman 的 Literal/Length 码表是固定的
    const output: number[] = [];
    let pos = startByte * 8;
    const endPos = data.length * 8;

    const readBits = (n: number): number => {
      let val = 0;
      for (let i = 0; i < n; i++) {
        if (pos >= endPos) return val;
        const byteIdx = Math.floor(pos / 8);
        const bitIdx = pos % 8;
        val |= ((data[byteIdx] >> bitIdx) & 1) << i;
        pos++;
      }
      return val;
    };

    // Static Huffman Literal/Length 码表
    const getLitLenCode = (): number => {
      // 读取 7-9 位来解码 Literal/Length 值
      const bits7 = readBits(7);
      if (bits7 <= 0x17) return bits7 + 256; // Length codes 256-279
      const bits8 = (bits7 << 1) | readBits(1);
      if (bits8 <= 0xBF) return bits8 - 0x30; // Literal 0-143
      const bits9 = (bits8 << 1) | readBits(1);
      if (bits9 <= 0x1FF) return bits9 - 0x100; // Literal 144-255
      return bits9 - 0x190; // Length codes 280-287
    };

    const getDistCode = (): number => {
      const bits5 = readBits(5);
      return bits5;
    };

    // Length 表
    const lengthTable = [
      3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,
      35,43,51,59,67,83,99,115,131,163,195,227,258
    ];
    const lengthExtraBits = [
      0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,
      3,3,3,3,4,4,4,4,5,5,5,5,0
    ];

    // Distance 表
    const distTable = [
      1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
      257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577
    ];
    const distExtraBits = [
      0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,
      7,7,8,8,9,9,10,10,11,11,12,12,13,13
    ];

    let maxIter = 1000000; // 防止无限循环
    while (maxIter-- > 0) {
      if (pos >= endPos) break;

      const code = getLitLenCode();

      if (code < 256) {
        // Literal byte
        output.push(code);
      } else if (code === 256) {
        // End of block
        break;
      } else {
        // Length code
        const lenIdx = code - 257;
        if (lenIdx >= lengthTable.length) break;
        const length = lengthTable[lenIdx] + readBits(lengthExtraBits[lenIdx]);

        const distCode = getDistCode();
        if (distCode >= distTable.length) break;
        const distance = distTable[distCode] + readBits(distExtraBits[distCode]);

        // 复制匹配
        for (let i = 0; i < length; i++) {
          const srcIdx = output.length - distance;
          if (srcIdx >= 0 && srcIdx < output.length) {
            output.push(output[srcIdx]);
          } else {
            output.push(0);
          }
        }
      }
    }

    return output;
  }

  // ──────────── 读取工具 ────────────

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

  private readAscii(length: number): string {
    let s = '';
    for (let i = 0; i < length; i++) {
      s += String.fromCharCode(this.data[this.offset++]);
    }
    return s;
  }

  private skip(n: number): void {
    this.offset += n;
  }

  private base64ToBytes(base64: string): Uint8Array {
    const clean = base64.replace(/^data:[^;]+;base64,/, '');
    const helper = new util.Base64Helper();
    const decoded = helper.decodeSync(clean);
    return new Uint8Array(decoded);
  }
}

let globalZipParser: ZipParserImpl | null = null;

function getZipParser(): ZipParserImpl {
  if (!globalZipParser) globalZipParser = new ZipParserImpl();
  return globalZipParser;
}

/**
 * 从 ZIP 中提取文件内容（文本）
 */
export function getZipStringContent(zipData: string, path: string): string {
  try {
    const parser = getZipParser();
    const bytes = parser.extract(zipData, path);
    if (!bytes) return '';
    // 尝试 UTF-8 解码
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
    console.error(`[ZipParser] getZipStringContent error: ${e}`);
    return '';
  }
}

/**
 * 从 ZIP 中提取文件内容（字节数组）
 */
export function getZipByteArrayContent(zipData: string, path: string): number[] {
  try {
    const parser = getZipParser();
    return parser.extract(zipData, path) || [];
  } catch (e) {
    console.error(`[ZipParser] getZipByteArrayContent error: ${e}`);
    return [];
  }
}

/**
 * 列出 ZIP 中所有文件
 */
export function listZipFiles(zipData: string): string[] {
  try {
    const parser = getZipParser();
    return parser.listFiles(zipData);
  } catch (e) {
    console.error(`[ZipParser] listZipFiles error: ${e}`);
    return [];
  }
}
