import { SpeechBookCover } from './SpeechBookCover';
import { TextToSpeechState, SpeechVoice } from '../model/TextToSpeechState';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor } from '../theme/Theme';

@ComponentV2
export struct ReaderSpeechSheet {
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param bookId: string = '';
  @Param bookTitle: string = '';
  @Param cover: string = '';
  @Param chapterTitle: string = '';
  @Param canResume: boolean = false;
  @Event onStart: (restore: boolean) => void = (): void => {};
  @Event onClose: () => void = (): void => {};
  private service: TextToSpeechService = TextToSpeechService.getInstance();

  private toggle(): void {
    if (this.state.bookId !== this.bookId) { this.onStart(false); return; }
    if (this.state.playing || this.state.loading) this.service.pause();
    else this.service.resume();
  }

  @Builder
  timerButton(label: ResourceStr, minutes: number, chapterEnd: boolean = false) {
    Button(label)
      .fontSize(13)
      .fontColor(AppColor.Brand)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick((): void => this.service.setSleep(minutes, chapterEnd))
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Row() {
          Text($r('app.string.tts_title')).fontColor($r('sys.color.font_primary')).fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
          Button($r('app.string.tts_close')).onClick((): void => this.onClose())
            .fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
        }.width('100%')

        Row({ space: 16 }) {
          SpeechBookCover({ cover: this.cover }).width(64).height(88).borderRadius(10).clip(true)
          Column({ space: 8 }) {
            Text(this.bookTitle).fontColor($r('sys.color.font_primary')).fontSize(19)
              .fontWeight(FontWeight.Medium).maxLines(2)
            Text(this.state.bookId === this.bookId ? this.state.chapterTitle : this.chapterTitle)
              .fontColor($r('sys.color.font_secondary')).fontSize(14).maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        if (this.state.error) {
          Text(this.state.error).fontColor($r('sys.color.font_secondary')).fontSize(14).width('100%')
        }
        Row({ space: 12 }) {
          Button($r('app.string.tts_previous'))
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .enabled(this.state.bookId === this.bookId && this.state.chapterIndex > 0)
            .onClick((): void => { this.service.moveChapter(-1); })
          Button(this.state.bookId === this.bookId && (this.state.playing || this.state.loading)
            ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .onClick((): void => this.toggle()).id('tts-toggle')
          Button($r('app.string.tts_next'))
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .enabled(this.state.bookId === this.bookId && this.state.chapterIndex + 1 < this.state.chapterCount)
            .onClick((): void => { this.service.moveChapter(1); })
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        if (this.state.loading) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
        Row({ space: 8 }) {
          Button($r('app.string.tts_from_page')).fontSize(13).layoutWeight(1)
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .onClick((): void => this.onStart(false)).id('tts-from-page')
          Button($r('app.string.tts_resume_saved')).fontSize(13).layoutWeight(1)
            .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
            .enabled(this.canResume).onClick((): void => this.onStart(true))
        }.width('100%')
        Text($r('app.string.tts_resume_hint')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')

        Row() {
          Text($r('app.string.tts_speed')).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Text(`${this.state.speed.toFixed(2)}×`).fontColor(AppColor.Brand)
        }.width('100%')
        Slider({ value: this.state.speed, min: 0.5, max: 2, step: 0.25 })
          .selectedColor(AppColor.Brand).width('100%')
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.service.setSpeed(value);
          })
        Row() {
          Text($r('app.string.tts_follow')).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.state.follow }).selectedColor(AppColor.Brand)
            .onChange((value: boolean): void => this.service.setFollow(value))
        }.width('100%')

        Row() {
          Text($r('app.string.tts_voice')).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Button($r('app.string.tts_refresh')).fontSize(13).fontColor(AppColor.Brand)
            .backgroundColor(Color.Transparent).onClick((): void => { this.service.refreshVoices(); })
        }.width('100%')
        ForEach(this.state.voices, (voice: SpeechVoice) => {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(voice.label).fontColor($r('sys.color.font_primary')).fontSize(15).maxLines(2)
              Text(voice.language).fontSize(12).fontColor($r('sys.color.font_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (this.state.downloadingVoice === voice.id) {
              LoadingProgress().width(24).height(24).color(AppColor.Brand)
            } else {
              Button(!voice.installed ? $r('app.string.tts_download') :
                (this.state.isVoiceSelected(voice)
                  ? $r('app.string.tts_selected') : $r('app.string.tts_select')))
                .fontSize(13).fontColor($r('sys.color.font_primary'))
                .backgroundColor($r('sys.color.comp_background_secondary'))
                .enabled(!this.state.downloadingVoice)
                .onClick((): void => { this.service.selectVoice(voice); })
            }
          }.width('100%').padding(10).borderRadius(12)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
        }, (voice: SpeechVoice): string => voice.id)

        Text($r('app.string.tts_sleep')).fontColor($r('sys.color.font_primary')).width('100%').fontWeight(FontWeight.Medium)
        Row({ space: 6 }) {
          this.timerButton($r('app.string.tts_sleep_off'), 0)
          this.timerButton($r('app.string.tts_sleep_15'), 15)
          this.timerButton($r('app.string.tts_sleep_30'), 30)
          this.timerButton($r('app.string.tts_sleep_60'), 60)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        this.timerButton($r('app.string.tts_sleep_chapter'), 0, true)
        if (this.state.remainingSeconds > 0) {
          Text($r('app.string.tts_sleep_remaining', Math.ceil(this.state.remainingSeconds / 60)))
            .fontColor(AppColor.Brand).fontSize(14)
        } else if (this.state.stopAtChapterEnd) {
          Text($r('app.string.tts_sleep_chapter_active')).fontColor(AppColor.Brand).fontSize(14)
        }
        Button($r('app.string.tts_stop')).width('100%')
          .backgroundColor($r('sys.color.comp_background_tertiary')).fontColor($r('sys.color.font_primary'))
          .onClick((): void => { this.service.stop(); this.onClose(); }).id('tts-stop')
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }
}
