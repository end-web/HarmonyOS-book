/**
 * TTFontParser - TTF 字体解析器（用于书源字体反爬）
 *
 * 解析 TTF/OTF 字体文件的 cmap 表，提取字符码 → 字形ID 映射。
 * 支持 cmap 格式：Format 0 (byte), Format 4 (segment), Format 12 (segment coverage)
 */

import { util } from '@kit.ArkTS';

interface TTFontResult {
  charToGlyph: Map<number, number>;
  glyphToChar: Map<number, number>;
  familyName: string;
}

class TTFontParserImpl {
  private data: Uint8Array = new Uint8Array(0);
  private offset: number = 0;

  parse(fontData: string | ArrayBuffer): TTFontResult {
    if (typeof fontData === 'string') {
      this.data = this.base64ToBytes(fontData);
    } else {
      this.data = new Uint8Array(fontData);
    }
    this.offset = 0;

    const charToGlyph: Map<number, number> = new Map();
    const glyphToChar: Map<number, number> = new Map();
    let familyName = '';

    // 读取 Offset Table
    this.readUint32(); // sfVersion
    const numTables = this.readUint16();
    this.skip(6);

    // 查找 cmap 和 name 表
    let cmapOffset = 0;
    let cmapLength = 0;
    let nameOffset = 0;
    let nameLength = 0;

    for (let i = 0; i < numTables; i++) {
      const tag = this.readTag();
      this.skip(4);
      const tableOffset = this.readUint32();
      const tableLength = this.readUint32();

      if (tag === 'cmap') {
        cmapOffset = tableOffset;
        cmapLength = tableLength;
      } else if (tag === 'name') {
        nameOffset = tableOffset;
        nameLength = tableLength;
      }
    }

    if (nameOffset > 0) {
      familyName = this.parseNameTable(nameOffset);
    }

    if (cmapOffset > 0) {
      this.parseCmapTable(cmapOffset, charToGlyph);
    }

    // 构建反向映射
    charToGlyph.forEach((glyphId: number, code: number) => {
      if (!glyphToChar.has(glyphId)) {
        glyphToChar.set(glyphId, code);
      }
    });

    return { charToGlyph, glyphToChar, familyName };
  }

  private parseCmapTable(cmapOffset: number, charToGlyph: Map<number, number>): void {
    this.offset = cmapOffset;
    this.readUint16(); // version
    const numSubtables = this.readUint16();

    for (let i = 0; i < numSubtables; i++) {
      const platformID = this.readUint16();
      const encodingID = this.readUint16();
      const subtableOffset = this.readUint32();
      const savedOffset = this.offset;

      if (platformID === 3 && encodingID === 1) {
        this.parseCmapSubtable(cmapOffset + subtableOffset, charToGlyph);
        break;
      } else if (platformID === 0) {
        this.parseCmapSubtable(cmapOffset + subtableOffset, charToGlyph);
        break;
      } else if (i === numSubtables - 1) {
        this.parseCmapSubtable(cmapOffset + subtableOffset, charToGlyph);
      }

      this.offset = savedOffset;
    }
  }

  private parseCmapSubtable(offset: number, charToGlyph: Map<number, number>): void {
    this.offset = offset;
    const format = this.readUint16();

    if (format === 0) {
      this.parseCmapFormat0(offset, charToGlyph);
    } else if (format === 4) {
      this.parseCmapFormat4(offset, charToGlyph);
    } else if (format === 6) {
      this.parseCmapFormat6(offset, charToGlyph);
    } else if (format === 12) {
      this.parseCmapFormat12(offset, charToGlyph);
    }
  }

  private parseCmapFormat0(offset: number, charToGlyph: Map<number, number>): void {
    this.offset = offset;
    this.skip(2);
    const length = this.readUint16();
    this.skip(2);
    const numGlyphs = length - 6;
    for (let i = 0; i < numGlyphs; i++) {
      const glyphId = this.readUint8();
      if (glyphId !== 0) {
        charToGlyph.set(i, glyphId);
      }
    }
  }

  private parseCmapFormat4(offset: number, charToGlyph: Map<number, number>): void {
    this.offset = offset;
    this.skip(2);
    this.skip(2);
    this.skip(2);
    const segCount = this.readUint16() / 2;
    this.skip(6);

    const endCodes: number[] = [];
    for (let i = 0; i < segCount; i++) endCodes.push(this.readUint16());
    this.skip(2);

    const startCodes: number[] = [];
    for (let i = 0; i < segCount; i++) startCodes.push(this.readUint16());

    const idDeltas: number[] = [];
    for (let i = 0; i < segCount; i++) idDeltas.push(this.readInt16());

    const idRangeOffsets: number[] = [];
    for (let i = 0; i < segCount; i++) idRangeOffsets.push(this.readUint16());

    const glyphIdArrayStart = this.offset;

    for (let i = 0; i < segCount; i++) {
      const start = startCodes[i];
      const end = endCodes[i];

      for (let c = start; c <= end; c++) {
        let glyphId: number;

        if (idRangeOffsets[i] === 0) {
          glyphId = (c + idDeltas[i]) & 0xFFFF;
        } else {
          const off2 = idRangeOffsets[i] / 2 + (c - start) + i - segCount;
          this.offset = glyphIdArrayStart + off2 * 2;
          glyphId = this.readUint16();
          if (glyphId !== 0) {
            glyphId = (glyphId + idDeltas[i]) & 0xFFFF;
          }
        }

        if (glyphId !== 0) {
          charToGlyph.set(c, glyphId);
        }
      }
    }
  }

  private parseCmapFormat6(offset: number, charToGlyph: Map<number, number>): void {
    this.offset = offset;
    this.skip(2);
    this.skip(2);
    this.skip(2);
    const firstCode = this.readUint16();
    const entryCount = this.readUint16();

    for (let i = 0; i < entryCount; i++) {
      const glyphId = this.readUint16();
      if (glyphId !== 0) {
        charToGlyph.set(firstCode + i, glyphId);
      }
    }
  }

  private parseCmapFormat12(offset: number, charToGlyph: Map<number, number>): void {
    this.offset = offset;
    this.skip(2);
    this.skip(2);
    this.skip(4);
    this.skip(4);
    const numGroups = this.readUint32();

    for (let i = 0; i < numGroups; i++) {
      const startCharCode = this.readUint32();
      const endCharCode = this.readUint32();
      const startGlyphID = this.readUint32();

      for (let c = startCharCode; c <= endCharCode; c++) {
        const glyphId = startGlyphID + (c - startCharCode);
        if (glyphId !== 0) {
          charToGlyph.set(c, glyphId);
        }
      }
    }
  }

  private parseNameTable(nameOffset: number): string {
    this.offset = nameOffset;
    this.readUint16(); // format
    const count = this.readUint16();
    const stringOffset = this.readUint16();

    for (let i = 0; i < count; i++) {
      const platformID = this.readUint16();
      const encodingID = this.readUint16();
      this.readUint16(); // languageID
      const nameID = this.readUint16();
      const length = this.readUint16();
      const off = this.readUint16();

      if (nameID === 1) {
        const savedOffset = this.offset;
        if (platformID === 3 && (encodingID === 1 || encodingID === 10)) {
          this.offset = nameOffset + stringOffset + off;
          const name = this.readUtf16BE(length);
          this.offset = savedOffset;
          return name;
        } else if (platformID === 1 && encodingID === 0) {
          this.offset = nameOffset + stringOffset + off;
          const name = this.readAscii(length);
          this.offset = savedOffset;
          return name;
        }
        this.offset = savedOffset;
      }
    }
    return '';
  }

  // ──────────── 读取工具 ────────────

  private readUint8(): number {
    return this.data[this.offset++];
  }

  private readUint16(): number {
    const b1 = this.data[this.offset++];
    const b2 = this.data[this.offset++];
    return (b1 << 8) | b2;
  }

  private readInt16(): number {
    const val = this.readUint16();
    return val >= 0x8000 ? val - 0x10000 : val;
  }

  private readUint32(): number {
    const b1 = this.data[this.offset++];
    const b2 = this.data[this.offset++];
    const b3 = this.data[this.offset++];
    const b4 = this.data[this.offset++];
    return ((b1 << 24) | (b2 << 16) | (b3 << 8) | b4) >>> 0;
  }

  private readTag(): string {
    return String.fromCharCode(
      this.data[this.offset++],
      this.data[this.offset++],
      this.data[this.offset++],
      this.data[this.offset++]
    );
  }

  private readAscii(length: number): string {
    let s = '';
    for (let i = 0; i < length; i++) {
      s += String.fromCharCode(this.data[this.offset++]);
    }
    return s;
  }

  private readUtf16BE(length: number): string {
    let s = '';
    for (let i = 0; i < length; i += 2) {
      const cp = (this.data[this.offset] << 8) | this.data[this.offset + 1];
      this.offset += 2;
      s += String.fromCharCode(cp);
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

let globalParser: TTFontParserImpl | null = null;

export function parseTTFont(data: string | ArrayBuffer): TTFontResult {
  if (!globalParser) {
    globalParser = new TTFontParserImpl();
  }
  return globalParser.parse(data);
}
