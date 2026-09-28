import { TextToSpeechState } from '../model/TextToSpeechState';
import { SpeechHighlightRange, SpeechTextHighlighter } from '../service/text/SpeechTextHighlighter';
import { ReaderPalette } from '../model/ReaderTheme';
import { OnlineTextPage } from '../service/text/OnlineTextPaginator';
import { ReaderParagraphNodeController } from '../service/text/ReaderParagraphNode';

/** 当前自然段整体高亮；仅范围或分页内容改变时重新计算，不按字刷新。 */
@ComponentV2
export struct ReaderSpeechText {
  @Param page: OnlineTextPage = new OnlineTextPage();
  private paragraphNode: ReaderParagraphNodeController = new ReaderParagraphNodeController();
  @Param text: string = '';
  @Param source: string = '';
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param sourceStart: number = 0;
  @Param highlightEnabled: boolean = false;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();

  @Monitor('page', 'text', 'source', 'sourceStart', 'palette', 'highlightEnabled',
    'state.active', 'state.highlightOffset', 'state.highlightEnd')
  updateParagraph(): void {
    this.paragraphNode.update(this.page, this.highlightRange, this.palette);
  }

  aboutToAppear(): void { this.updateParagraph(); }
  aboutToDisappear(): void { this.paragraphNode.release(); }

  @Computed
  get highlightRange(): SpeechHighlightRange {
    if (!this.highlightEnabled || !this.state.active) return new SpeechHighlightRange();
    return SpeechTextHighlighter.displayRange(this.text, this.source,
      this.state.highlightOffset - this.sourceStart, this.state.highlightEnd - this.sourceStart);
  }

  build() {
    if (this.page.paragraph !== null) {
      NodeContainer(this.paragraphNode)
        .width('100%')
        .height(this.getUIContext().px2vp(this.page.layoutHeight))
        .accessibilityText(this.text)
    } else {
    Text() {
      if (this.highlightRange.start >= 0) {
        Span(this.text.substring(0, this.highlightRange.start))
        Span(this.text.substring(this.highlightRange.start, this.highlightRange.end))
          .fontColor(this.palette.background)
          .textBackgroundStyle({ color: this.palette.primary, radius: 3 })
        Span(this.text.substring(this.highlightRange.end))
      } else {
        Span(this.text)
      }
    }
    .width('100%')
    .fontSize(this.fontSize)
    .fontColor(this.palette.primary)
    .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
    .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
    .lineHeight(this.fontSize * this.lineHeight)
    .textAlign(TextAlign.JUSTIFY)
    .wordBreak(WordBreak.BREAK_WORD)
    .lineBreakStrategy(LineBreakStrategy.GREEDY)
    }
  }
}
