export class SpeechSegment {
  start: number = 0;
  end: number = 0;
  text: string = '';
  leadingWhitespace: number = 0;
  paragraphStart: number = 0;
  paragraphEnd: number = 0;
}

/** 偏移始终对应阅读器规范化正文，分段不删除或重排原文。 */
export class SpeechTextSegmenter {
  static split(content: string, mergeShort: boolean = false): SpeechSegment[] {
    const result: SpeechSegment[] = [];
    let start = 0;
    let paragraphStart = 0;
    let paragraphEnd = content.indexOf('\n');
    if (paragraphEnd < 0) paragraphEnd = content.length;
    for (let i = 0; i < content.length; i++) {
      const ch = content.charAt(i);
      const boundary = '。！？!?；;\n'.includes(ch) ||
        (ch === '.' && (i + 1 === content.length || new RegExp('\\s').test(content.charAt(i + 1))));
      // 限制单句长度，且不把 UTF-16 代理对拆开。
      const code = content.charCodeAt(i);
      const limit = i - start >= 179 && !(code >= 0xD800 && code <= 0xDBFF);
      if (boundary || limit || i === content.length - 1) {
        let end = i + 1;
        while (end < content.length && '”’」』）'.includes(content.charAt(end))) end++;
        const segment = new SpeechSegment();
        segment.start = start;
        segment.end = end;
        const raw = content.substring(start, end);
        segment.leadingWhitespace = Math.max(0, raw.search(new RegExp('\\S')));
        segment.text = raw.trim();
        if (segment.text.length > 0) {
          const readStart = start + segment.leadingWhitespace;
          while (readStart >= paragraphEnd && paragraphEnd < content.length) {
            paragraphStart = paragraphEnd + 1;
            paragraphEnd = content.indexOf('\n', paragraphStart);
            if (paragraphEnd < 0) paragraphEnd = content.length;
          }
          segment.paragraphStart = paragraphStart;
          segment.paragraphEnd = paragraphEnd;
          result.push(segment);
        }
        start = end;
        i = end - 1;
      }
    }
    return mergeShort ? SpeechTextSegmenter.mergeShortSegments(content, result) : result;
  }

  /** HTTP 同段短句合并到约 64 字、上限约 180 字，允许附带尾部标点；不跨自然段。 */
  private static mergeShortSegments(content: string, segments: SpeechSegment[]): SpeechSegment[] {
    const result: SpeechSegment[] = [];
    const punctuationOnly = new RegExp('^[\\s。，、！？!?；;：:“”‘’「」『』（）()…—.\\-]+$');
    for (const segment of segments) {
      const previous = result.length > 0 ? result[result.length - 1] : null;
      const punctuation = punctuationOnly.test(segment.text);
      if (previous !== null && previous.paragraphStart === segment.paragraphStart &&
        (previous.text.length < 64 || punctuation) && segment.end - previous.start <= (punctuation ? 196 : 180)) {
        previous.end = segment.end;
        previous.text = content.substring(previous.start, previous.end).trim();
      } else if (!punctuation) {
        result.push(segment);
      }
    }
    return result;
  }

  static indexAt(segments: SpeechSegment[], offset: number): number {
    const index = segments.findIndex((segment: SpeechSegment): boolean => segment.end > offset);
    return index < 0 ? segments.length : index;
  }
}
