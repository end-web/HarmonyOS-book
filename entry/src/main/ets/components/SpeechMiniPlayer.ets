import { SpeechBookCover } from './SpeechBookCover';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppSpace } from '../theme/Theme';

@ComponentV2
export struct SpeechMiniPlayer {
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param collapsed: boolean = false;
  @Event onOpen: () => void = (): void => {};

  build() {
    Row({ space: this.collapsed ? 0 : 10 }) {
      SpeechBookCover({ cover: this.state.cover })
        .width(this.collapsed ? '100%' : 44).aspectRatio(1)
        .borderRadius(999).clip(true)
        .onClick((): void => this.onOpen()).accessibilityText($r('app.string.tts_title'))
      if (!this.collapsed) {
        Column({ space: 2 }) {
          Text(this.state.bookTitle).fontSize(15).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.state.error || this.state.chapterTitle).fontSize(12)
            .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick((): void => this.onOpen())
        Button() {
          SymbolGlyph(this.state.playing || this.state.loading ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(22).fontColor([AppColor.Brand])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText(this.state.playing || this.state.loading ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
          .onClick((): void => {
            const service = TextToSpeechService.getInstance();
            if (this.state.playing || this.state.loading) service.pause();
            else service.resume();
          })
        Button() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
        }.width(36).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.tts_stop'))
          .onClick((): void => TextToSpeechService.getInstance().stop())
      }
    }.width('100%').height('100%').padding({ left: this.collapsed ? 0 : AppSpace.Xs, right: this.collapsed ? 0 : 8 })
  }
}
