import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { AppIconOption, AppIconService } from '../service/AppIconService';

/** 主题页内的图标选择区，保留原文件名，不再注册独立路由。 */
@ComponentV2
export struct AppIconPage {
  @Local current: string = '';
  @Local loading: boolean = true;
  @Local switching: boolean = false;
  @Local loadFailed: boolean = false;
  private service: AppIconService = AppIconService.instance;
  private options: AppIconOption[] = this.service.getOptions();

  aboutToAppear(): void {
    this.loadCurrent();
  }

  private async loadCurrent(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      this.current = await this.service.getCurrent();
    } catch (_error) {
      this.loadFailed = true;
    } finally {
      this.loading = false;
    }
  }

  private async selectIcon(option: AppIconOption): Promise<void> {
    if (this.switching || !this.service.supported) return;
    if (this.loading || this.loadFailed || this.current === option.name) return;
    this.switching = true;
    try {
      this.current = await this.service.select(option.name);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.app_icon_changed') });
    } catch (_error) {
      // 再次读取实际状态，覆盖“设置成功但查询暂时失败”的情况。
      await this.loadCurrent();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.app_icon_change_failed') });
    } finally {
      this.switching = false;
    }
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.app_icon_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (this.loading || this.switching) {
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }
      }
      .width('100%')
      if (this.loadFailed) {
        Button($r('app.string.app_icon_retry'))
          .fontColor(AppColor.Brand)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .enabled(!this.loading && !this.switching)
          .onClick(() => this.loadCurrent())
      }
      if (!this.service.supported) {
        Text($r('app.string.app_icon_unsupported')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      }
      GridRow({ columns: 3, gutter: { x: 12, y: 16 } }) {
        ForEach(this.options, (option: AppIconOption) => {
          GridCol() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Image(option.preview)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Contain)
                    .borderRadius(20)
                    .clip(true)
                  if (this.service.supported && !this.loading && !this.loadFailed && this.current === option.name) {
                    Stack({ alignContent: Alignment.Center }) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor([Color.White])
                    }
                    .width(24)
                    .height(24)
                    .backgroundColor('#222222')
                    .border({ width: 2, color: Color.White })
                    .borderRadius(12)
                    .margin({ right: 4, bottom: 4 })
                    .hitTestBehavior(HitTestMode.None)
                    .accessibilityText($r('app.string.app_icon_current'))
                  }
                }
                .width('100%')
                Text(option.label)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 6, right: 6, top: 6, bottom: 10 })
            }
            .width('100%')
            .padding(0)
            .borderRadius(AppRadius.Lg)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .enabled(this.service.supported && !this.switching &&
              !this.loading && !this.loadFailed)
            .accessibilityText(option.label)
            .onClick(() => this.selectIcon(option))
          }
        }, (option: AppIconOption) => option.name || 'default')
      }
    }
    .width('100%')
  }
}
