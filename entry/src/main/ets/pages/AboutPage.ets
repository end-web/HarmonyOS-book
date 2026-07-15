import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { common } from '@kit.AbilityKit';
import { UpdateService, UpdateInfo } from '../service/UpdateService';

@ComponentV2
export struct AboutPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local appVersion: string = '0.0.0';
  @Local checking: boolean = false;
  /** 已知的可更新信息(缓存或本次检查),用于行内红点与二次点击 */
  @Local latestInfo: UpdateInfo | null = null;

  aboutToAppear(): void {
    this.appVersion = UpdateService.getCurrentVersion();
    const ctx = this.getUIContext().getHostContext() as common.BaseContext;
    UpdateService.getCachedInfo(ctx).then((info: UpdateInfo | null) => {
      if (info && info.hasUpdate) {
        this.latestInfo = info;
      }
    });
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async doCheckUpdate(): Promise<void> {
    if (this.checking) return;
    this.checking = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const info = await UpdateService.checkUpdate(ctx);
    this.checking = false;
    if (!info) {
      this.toast('检查失败,请检查网络后重试');
      return;
    }
    this.latestInfo = info.hasUpdate ? info : null;
    if (info.hasUpdate) {
      this.showUpdateDialog(ctx, info);
    } else {
      this.toast(`当前已是最新版本 v${info.currentVersion}`);
    }
  }

  private showUpdateDialog(ctx: common.UIAbilityContext, info: UpdateInfo): void {
    let notes = info.notes.trim();
    if (notes.length > 300) notes = notes.substring(0, 300) + '…';
    const message = `最新版本 v${info.latestVersion}（当前 v${info.currentVersion}）`
      + (notes ? `\n\n${notes}` : '');
    this.getUIContext().showAlertDialog({
      title: '发现新版本',
      message,
      primaryButton: {
        value: '前往下载',
        action: () => {
          UpdateService.openReleasePage(ctx, info.releaseUrl).catch(() => {
            this.toast('无法打开浏览器');
          });
        }
      },
      secondaryButton: {
        value: '稍后',
        action: () => {}
      },
      alignment: DialogAlignment.Center,
    });
  }

  @Builder
  checkUpdateTrailing(): void {
    if (this.checking) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color($r('sys.color.font_tertiary'))
    } else if (this.latestInfo && this.latestInfo.hasUpdate) {
      Row({ space: 4 }) {
        Column()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor('#FF3B30')
        Text(`新版 v${this.latestInfo.latestVersion}`)
          .fontSize(AppFont.Body)
          .fontColor('#FF6B3D')
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .alignItems(VerticalAlign.Center)
    } else {
      Row({ space: 4 }) {
        Text(`v${this.appVersion}`)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_tertiary'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('关于')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .margin({ left: AppSpace.Sm })
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
      })

      Column({ space: AppSpace.Lg }) {
        Column({ space: AppSpace.Sm }) {
          Image($r('app.media.app_icon_legacy'))
            .width(80)
            .height(80)
            .borderRadius(AppRadius.Xl)
            .clip(true)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })

          Text($r('app.string.EntryAbility_label'))
            .fontSize(AppFont.TitleL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Text(`v${this.appVersion}`)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ top: AppSpace.Xl })

        Column() {
          Row() {
            Text('作者')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('ylwang')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('框架')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('HarmonyOS Next / ArkUI')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('SDK')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text('API 12 (6.1.0)')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('检查更新')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            this.checkUpdateTrailing()
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.doCheckUpdate())

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('使用说明')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_tertiary')])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('guide', ''))

          Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('隐私政策')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_tertiary')])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('privacy', ''))
        }
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Lg)
        .margin({ left: AppSpace.Sm, right: AppSpace.Sm })

        Text('纯血鸿蒙听书应用')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
