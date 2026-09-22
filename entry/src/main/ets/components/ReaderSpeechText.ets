import { TextToSpeechState } from '../model/TextToSpeechState';
import { SpeechTextHighlighter } from '../service/text/SpeechTextHighlighter';
import { ReaderPalette } from '../model/ReaderTheme';

/** 仅当前页文字响应游标刷新，不让高频游标重建阅读器的翻页/布局容器。 */
@ComponentV2
export struct ReaderSpeechText {
  @Param text: string = '';
  @Param source: string = '';
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param sourceStart: number = 0;
  @Param highlightEnabled: boolean = false;
  @Param fontFamily: string = 'HarmonyOS Sans';
  @Param fontWeight: number = 400;
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();

  @Computed
  get cursor(): number {
    if (!this.highlightEnabled || !this.state.active) return -1;
    return SpeechTextHighlighter.displayOffset(this.text, this.source, this.state.highlightOffset - this.sourceStart);
  }

  @Computed
  get cursorEnd(): number {
    if (this.cursor < 0) return 0;
    const code = this.text.charCodeAt(this.cursor);
    return Math.min(this.text.length, this.cursor + (code >= 0xD800 && code <= 0xDBFF ? 2 : 1));
  }

  build() {
    Text() {
      if (this.cursor >= 0) {
        Span(this.text.substring(0, this.cursor))
        Span(this.text.substring(this.cursor, this.cursorEnd))
          .fontColor(this.palette.background)
          .textBackgroundStyle({ color: this.palette.primary, radius: 3 })
        Span(this.text.substring(this.cursorEnd))
      } else {
        Span(this.text)
      }
    }
    .width('100%')
    .fontSize(this.fontSize)
    .fontColor(this.palette.primary)
    .fontFamily(this.fontFamily)
    .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
    .lineHeight(this.fontSize * this.lineHeight)
    .textAlign(TextAlign.JUSTIFY)
    .wordBreak(WordBreak.BREAK_WORD)
    .lineBreakStrategy(LineBreakStrategy.GREEDY)
  }
}
