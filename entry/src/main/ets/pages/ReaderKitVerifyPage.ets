import { EpubReaderComponent } from '../components/EpubReaderComponent';
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const READER_KIT_INVALID_CALLER: number = 1016910004;
const READER_KIT_BACKGROUND: string = '#F5F2EA';

@ComponentV2
export struct ReaderKitVerifyPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local running: boolean = true;
  @Local succeeded: boolean = false;
  @Local errorCode: number = 0;
  @Local errorMessage: string = '';

  aboutToAppear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  aboutToDisappear(): void {
    WindowUtils.setStatusBarLight(false);
  }

  private handleReady(): void {
    this.running = false;
    this.succeeded = true;
    this.errorCode = 0;
    this.errorMessage = '';
  }

  private handleError(message: string, code: number): void {
    this.running = false;
    this.succeeded = false;
    this.errorCode = code;
    this.errorMessage = message;
  }

  private statusTitle(): ResourceStr {
    if (this.running) return $r('app.string.reader_kit_verify_running');
    if (this.succeeded) return $r('app.string.reader_kit_verify_success');
    return $r('app.string.reader_kit_verify_failed');
  }

  private statusDesc(): ResourceStr {
    if (this.running) return $r('app.string.reader_kit_verify_waiting');
    if (this.succeeded) return $r('app.string.reader_kit_verify_no_invalid_caller');
    if (this.errorCode === READER_KIT_INVALID_CALLER) return $r('app.string.reader_kit_verify_invalid_caller');
    return $r('app.string.reader_kit_verify_other_error');
  }

  private statusColor(): ResourceColor {
    if (this.running) return $r('sys.color.font_secondary');
    return this.succeeded ? AppColor.Brand : '#D03050';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      EpubReaderComponent({
        onReady: () => this.handleReady(),
        onError: (message: string, code: number): void => {
          this.handleError(message, code);
        }
      })
        .width('100%')
        .height('100%')

      Column() {
        Row({ space: AppSpace.Sm }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([$r('sys.color.font_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(AppRadius.Pill)
          .onClick(() => this.navStack.pop())

          Text($r('app.string.reader_kit_verify_title'))
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(WindowUtils.getStatusBarHeightVp() + 56)
        .padding({
          left: AppSpace.Sm,
          right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp()
        })
        .systemMaterial(AppMaterial.FloatingControl)

        Column({ space: AppSpace.Md }) {
          if (this.running) {
            LoadingProgress()
              .width(34)
              .height(34)
              .color(AppColor.Brand)
          } else {
            SymbolGlyph(this.succeeded ? $r('sys.symbol.checkmark') : $r('sys.symbol.exclamationmark_circle'))
              .fontSize(44)
              .fontColor([this.statusColor()])
          }

          Text(this.statusTitle())
            .fontSize(AppFont.Title)
            .fontColor(this.statusColor())
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)

          Text(this.statusDesc())
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Center)
            .maxLines(3)

          if (!this.running && !this.succeeded && this.errorCode > 0) {
            Row({ space: AppSpace.Xs }) {
              Text($r('app.string.reader_kit_verify_error_code'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
              Text(`${this.errorCode}`)
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .justifyContent(FlexAlign.Center)
          }
          if (!this.running && !this.succeeded && this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(READER_KIT_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
