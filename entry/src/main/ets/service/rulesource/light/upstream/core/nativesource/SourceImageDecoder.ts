import { NativeSourceCrypto } from './NativeSourceCrypto';
import { NativeCoverDecodeSpec } from './NativeSourceSpec';
import { util } from '@kit.ArkTS';

/** Bounded reusable image decoding; no networking, files, scripts or website-specific keys. */
export class SourceImageDecoder {
  static readonly MAX_BYTES = 8 * 1024 * 1024;

  static validate(spec: NativeCoverDecodeSpec): void {
    if (!spec || !/^AES\/CBC\/PKCS(?:5|7)Padding$/i.test(spec.algorithm || '')) {
      throw new Error('coverDecode requires AES/CBC/PKCS7Padding');
    }
    const key = this.keyHex(spec);
    if (![32, 48, 64].includes(key.length)) throw new Error('Invalid AES key length');
    if (spec.ivPrefixBytes === 16) {
      if (spec.iv) throw new Error('Choose iv or ivPrefixBytes');
    } else if ((spec.ivPrefixBytes !== undefined && spec.ivPrefixBytes !== 0) ||
      !/^[a-f0-9]{32}$/i.test(spec.iv || '')) throw new Error('AES CBC requires a 16-byte IV');
  }

  private static keyHex(spec: NativeCoverDecodeSpec): string {
    if (typeof spec.key !== 'string' || spec.key.length > 128) throw new Error('Invalid image key');
    if (spec.keyEncoding === 'utf8') {
      return Array.from(new util.TextEncoder().encodeInto(spec.key))
        .map(value => value.toString(16).padStart(2, '0')).join('');
    }
    if (spec.keyEncoding !== undefined && spec.keyEncoding !== 'hex' || !/^[a-f0-9]+$/i.test(spec.key)) {
      throw new Error('Invalid hex image key');
    }
    return spec.key;
  }

  static decode(input: Uint8Array, spec: NativeCoverDecodeSpec): Uint8Array {
    this.validate(spec);
    if (!input.length || input.length > this.MAX_BYTES) throw new Error('Image exceeds byte limit');
    // Some sites mix encrypted and ordinary covers under the same rule.
    if (this.isImage(input)) return input;
    const offset = spec.ivPrefixBytes === 16 ? 16 : 0;
    if (input.length <= offset || (input.length - offset) % 16 !== 0) throw new Error('Truncated AES image');
    const iv = offset ? Array.from(input.subarray(0, offset))
      .map(value => value.toString(16).padStart(2, '0')).join('') : spec.iv || '';
    const output = NativeSourceCrypto.decryptBytes(spec.algorithm, input.subarray(offset), this.keyHex(spec), iv);
    if (!this.isImage(output)) throw new Error('Decoded content is not an image');
    return output;
  }

  static isImage(bytes: Uint8Array): boolean {
    if (bytes.length < 12) return false;
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return true;
    const head = Array.from(bytes.subarray(0, 12)).map(value => String.fromCharCode(value)).join('');
    return head.startsWith('\x89PNG\r\n\x1a\n') || head.startsWith('GIF87a') || head.startsWith('GIF89a') ||
      head.startsWith('BM') || head.startsWith('RIFF') && head.substring(8) === 'WEBP' ||
      head.substring(4) === 'ftypavif' || head.substring(4) === 'ftypavis';
  }
}
