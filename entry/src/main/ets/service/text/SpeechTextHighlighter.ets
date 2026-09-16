/** TTS 无字级时间戳：按字符/标点权重估计句内游标，每句由真实播放回调校准。 */
export class SpeechTextHighlighter {
  static weight(character: string): number {
    if (new RegExp('\\s').test(character)) return 0;
    if ('，、,：:'.includes(character)) return 0.7;
    if ('。！？!?；;'.includes(character)) return 1.2;
    if ('“”‘’「」『』（）()'.includes(character)) return 0.15;
    if (new RegExp('[A-Za-z0-9]').test(character)) return 0.45;
    return 1;
  }

  static totalWeight(text: string): number {
    let result = 0;
    for (const character of text) result += SpeechTextHighlighter.weight(character);
    return result;
  }

  static offsetAt(text: string, elapsedMs: number, unitMs: number): number {
    const target = Math.max(0, elapsedMs) / Math.max(1, unitMs);
    let weight = 0;
    let offset = 0;
    let last = 0;
    for (const character of text) {
      const current = SpeechTextHighlighter.weight(character);
      if (current > 0) {
        last = offset;
        weight += current;
        if (weight > target) return offset;
      }
      offset += character.length;
    }
    return last;
  }

  /** 阅读器只额外插入段首缩进，忽略两侧空白差异可准确映射回原文字。 */
  static displayOffset(display: string, source: string, sourceOffset: number): number {
    if (sourceOffset < 0 || sourceOffset >= source.length) return -1;
    let sourceIndex = 0;
    const whitespace = new RegExp('\\s');
    for (let displayIndex = 0; displayIndex < display.length; displayIndex++) {
      if (whitespace.test(display.charAt(displayIndex))) continue;
      while (sourceIndex < source.length && whitespace.test(source.charAt(sourceIndex))) sourceIndex++;
      if (sourceIndex >= sourceOffset) {
        const code = display.charCodeAt(displayIndex);
        return code >= 0xDC00 && code <= 0xDFFF ? Math.max(0, displayIndex - 1) : displayIndex;
      }
      sourceIndex++;
    }
    return -1;
  }
}
