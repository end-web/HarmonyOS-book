import { textToSpeech } from '@kit.CoreSpeechKit';

/** 每句有界收集，按 IPC 序号拼接；播放器完成后才推进阅读位置。 */
export class SpeechPcmBuffer {
  private chunks: Map<number, ArrayBuffer> = new Map();
  private bytes: number = 0;
  private rate: number = 0;
  private channels: number = 0;

  reset(): void {
    this.chunks.clear();
    this.bytes = 0;
    this.rate = 0;
    this.channels = 0;
  }

  configure(response: textToSpeech.StartResponse): void {
    if (response.audioType !== 'pcm' || response.sampleBit !== 16 ||
      response.sampleRate !== 16000 || (response.audioChannel !== 1 && response.audioChannel !== 2)) {
      throw new Error(`Unsupported speech PCM format: ${response.audioType}/${response.sampleRate}/${response.sampleBit}/${response.audioChannel}`);
    }
    this.rate = response.sampleRate;
    this.channels = response.audioChannel;
  }

  append(data: ArrayBuffer, response: textToSpeech.SynthesisResponse): void {
    if (response.audioType !== 'pcm' || !Number.isInteger(response.sequence) || response.sequence < 0 ||
      response.sequence > 100000) throw new Error('Invalid speech PCM sequence');
    if (this.chunks.has(response.sequence)) return;
    if (this.bytes + data.byteLength > 8 * 1024 * 1024 || this.chunks.size >= 4096) {
      throw new Error('Speech PCM budget exceeded');
    }
    this.chunks.set(response.sequence, data.slice(0));
    this.bytes += data.byteLength;
  }

  toWave(): ArrayBuffer {
    if (this.rate === 0 || this.bytes === 0 || this.bytes % (this.channels * 2) !== 0) {
      throw new Error('Incomplete speech PCM');
    }
    const result = new ArrayBuffer(44 + this.bytes);
    const header = new DataView(result);
    header.setUint32(0, 0x52494646, false);
    header.setUint32(4, 36 + this.bytes, true);
    header.setUint32(8, 0x57415645, false);
    header.setUint32(12, 0x666d7420, false);
    header.setUint32(16, 16, true);
    header.setUint16(20, 1, true);
    header.setUint16(22, this.channels, true);
    header.setUint32(24, this.rate, true);
    header.setUint32(28, this.rate * this.channels * 2, true);
    header.setUint16(32, this.channels * 2, true);
    header.setUint16(34, 16, true);
    header.setUint32(36, 0x64617461, false);
    header.setUint32(40, this.bytes, true);
    const output = new Uint8Array(result);
    let offset = 44;
    for (let sequence = 0; sequence < this.chunks.size; sequence++) {
      const chunk = this.chunks.get(sequence);
      if (chunk === undefined) throw new Error('Missing speech PCM packet');
      output.set(new Uint8Array(chunk), offset);
      offset += chunk.byteLength;
    }
    return result;
  }
}
