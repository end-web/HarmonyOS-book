export class SpeechHighlightRange {
  start: number = -1;
  end: number = -1;
}

/** 把自然段与当前页/滚动行的交集映射到显示正文，只处理分页插入的空白差异。 */
export class SpeechTextHighlighter {
  static displayRange(display: string, source: string, start: number, end: number): SpeechHighlightRange {
    const range = new SpeechHighlightRange();
    if (end <= start || end <= 0 || start >= source.length) return range;
    const from = Math.max(0, start);
    const to = Math.min(source.length, end);
    const whitespace = new RegExp('\\s');
    let sourceIndex = 0;
    let displayIndex = 0;
    for (const character of display) {
      if (!whitespace.test(character)) {
        while (sourceIndex < source.length && whitespace.test(source.charAt(sourceIndex))) sourceIndex++;
        if (sourceIndex >= to) break;
        if (sourceIndex + character.length > from) {
          if (range.start < 0) range.start = displayIndex;
          range.end = displayIndex + character.length;
        }
        sourceIndex += character.length;
      }
      displayIndex += character.length;
    }
    return range;
  }
}
