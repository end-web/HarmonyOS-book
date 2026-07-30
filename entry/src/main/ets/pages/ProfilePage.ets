import { AppColor, AppRadius, AppSpace, AppFont, AppMaterial, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AuthService, HwAuthErrorCode } from '../service/AuthService';
import {
  DEFAULT_SERVER_AUDIO_API_BASE,
  ServerAudioConfig,
  ServerAudioConfigErrorCode
} from '../service/builtin/ServerAudioConfig';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface ProfileItem {
  icon: Resource;
  label: string;
  id: string;
  iconBg: ResourceColor;
}

const CONTENT_ITEMS: ProfileItem[] = [
  { icon: $r('sys.symbol.arrow_down_circle'), label: '本地导入', id: 'import', iconBg: '#34C759' },
  { icon: $r('sys.symbol.arrow_down_circle'), label: '下载管理', id: 'downloads', iconBg: '#0A84FF' }
];

const SYSTEM_ITEMS: ProfileItem[] = [
  { icon: $r('sys.symbol.gearshape'), label: '设置', id: 'settings', iconBg: '#8E8E93' },
  { icon: $r('sys.symbol.questionmark_circle'), label: '使用说明', id: 'guide', iconBg: '#5AC8FA' },
  { icon: $r('sys.symbol.info_circle'), label: '关于', id: 'about', iconBg: '#0A59F7' }
];

const ROW_INDENT: number = AppSpace.Md;

/** 华为账号登录入口开关:AGC(手动签名+指纹+client_id)配好后改 true 即显示 */
const ENABLE_HW_LOGIN: boolean = false;

@ComponentV2
export struct ProfilePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Local auth: AuthService = AuthService.instance;
  @Local serverApiBase: string = DEFAULT_SERVER_AUDIO_API_BASE;
  @Local serverApiDraft: string = DEFAULT_SERVER_AUDIO_API_BASE;
  @Local isServerConfigVisible: boolean = false;
  @Local isServerChecking: boolean = false;
  @Local isServerSaving: boolean = false;
  @Local serverCheckState: number = 0;

  private scrollScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scrollScroller);
    this.auth.restore();
    this.loadServerApiBase();
  }

  private async loadServerApiBase(): Promise<void> {
    this.serverApiBase = await ServerAudioConfig.getApiBase();
    if (!this.isServerConfigVisible) {
      this.serverApiDraft = this.serverApiBase;
    }
  }

  private openServerConfig(): void {
    this.serverApiDraft = this.serverApiBase;
    this.serverCheckState = 0;
    this.isServerConfigVisible = true;
  }

  private serverApiDisplay(): string {
    return this.serverApiBase.replace(/^https?:\/\//, '');
  }

  private async testServerApi(): Promise<void> {
    if (this.isServerChecking || this.isServerSaving) return;
    this.isServerChecking = true;
    this.serverCheckState = 1;
    try {
      const normalized = ServerAudioConfig.normalizeApiBase(this.serverApiDraft);
      this.serverApiDraft = normalized;
      const ready = await ServerAudioConfig.checkConnection(normalized);
      this.serverCheckState = ready ? 2 : 4;
    } catch (e) {
      this.serverCheckState = 3;
      this.showServerConfigError(e);
    } finally {
      this.isServerChecking = false;
    }
  }

  private restoreDefaultServerApi(): void {
    if (this.isServerChecking || this.isServerSaving) return;
    this.serverApiDraft = DEFAULT_SERVER_AUDIO_API_BASE;
    this.serverCheckState = 5;
  }

  private async saveServerApi(): Promise<void> {
    if (this.isServerChecking || this.isServerSaving) return;
    this.isServerSaving = true;
    try {
      const normalized = await ServerAudioConfig.saveApiBase(this.serverApiDraft);
      this.serverApiBase = normalized;
      this.serverApiDraft = normalized;
      this.isServerConfigVisible = false;
      this.showToast($r('app.string.cloud_source_saved'));
    } catch (e) {
      this.showServerConfigError(e, true);
    } finally {
      this.isServerSaving = false;
    }
  }

  private showServerConfigError(error: Object, saving: boolean = false): void {
    const message = error instanceof Error ? error.message : '';
    if (message === ServerAudioConfigErrorCode.EMPTY) {
      this.showToast($r('app.string.cloud_source_error_empty'));
    } else if (message === ServerAudioConfigErrorCode.INVALID_SCHEME) {
      this.showToast($r('app.string.cloud_source_error_scheme'));
    } else if (message === ServerAudioConfigErrorCode.INVALID_URL) {
      this.showToast($r('app.string.cloud_source_error_invalid'));
    } else if (saving) {
      this.showToast($r('app.string.cloud_source_error_save'));
    } else {
      this.showToast($r('app.string.cloud_source_check_failed'));
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_e) { /* ignore */ }
  }

  private async handleLogin(): Promise<void> {
    if (this.auth.logging) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.Context;
    try {
      await this.auth.login(ctx);
      this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === HwAuthErrorCode.USER_CANCEL) {
        return; // 用户主动取消,不提示
      }
      this.getUIContext().getPromptAction().showToast({ message: this.loginErrorText(err) });
    }
  }

  private loginErrorText(err: BusinessError): string {
    switch (err.code) {
      case HwAuthErrorCode.LOGIN_OUT:
        return '请先在系统设置登录华为账号';
      case HwAuthErrorCode.NETWORK:
        return '网络异常,请稍后重试';
      case HwAuthErrorCode.CERT_INVALID:
        return '签名指纹/Client ID 未配置(开发期)';
      case HwAuthErrorCode.SYSTEM_SERVICE:
        return '系统服务异常,请稍后重试';
      default:
        return `登录失败(${err.code ?? '未知'})`;
    }
  }

  private handleLogout(): void {
    this.getUIContext().showAlertDialog({
      message: '确定退出登录?将清除本地华为账号身份标识。',
      primaryButton: {
        value: '退出',
        fontColor: '#FF3B30',
        action: () => {
          this.auth.logout();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      },
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -16 }
    });
  }

  private onItemTap(id: string): void {
    if (id === 'import') {
      this.navStack.pushPathByName('import', '');
    } else if (id === 'downloads') {
      this.navStack.pushPathByName('downloads', '');
    } else if (id === 'settings') {
      this.navStack.pushPathByName('settings', '');
    } else if (id === 'guide') {
      this.navStack.pushPathByName('guide', '');
    } else if (id === 'about') {
      this.navStack.pushPathByName('about', '');
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [HomeTheme.BgWarmTop, 0.0],
            [HomeTheme.BgWarmMid, 0.35],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      Scroll(this.scrollScroller) {
        Column({ space: AppSpace.Lg }) {
          this.buildHeader()
          if (ENABLE_HW_LOGIN) {
            this.buildAccountCard()
          }
          this.buildServerGroup()
          this.buildGroup('我的内容', CONTENT_ITEMS)
          this.buildGroup('系统', SYSTEM_ITEMS)
        }
        .width('100%')
        .padding({
          left: AppSpace.Md,
          right: AppSpace.Md,
          bottom: WindowUtils.getFloatingTabBottomVp()
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(Color.Transparent)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.isServerConfigVisible, this.buildServerConfigSheet(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: true,
      systemMaterial: AppMaterial.SurfaceRegular
    })
  }

  @Builder
  buildHeader() {
    Column() {
      Text('我的')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Md,
      bottom: AppSpace.Sm
    })
  }

  @Builder
  buildAccountCard() {
    Row({ space: AppSpace.Md }) {
      // 头像
      Stack() {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
          .fontSize(40)
          .fontColor([this.auth.isLoggedIn ? '#0A59F7' : '#C7C7CC'])
      }
      .width(48)
      .height(48)

      // 文案
      Column({ space: 2 }) {
        Text(this.auth.isLoggedIn ? '华为账号用户' : '点击登录华为账号')
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(this.auth.isLoggedIn ? `ID ${this.auth.maskedId()}` : '登录后用于标识你的听书身份')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作
      if (this.auth.isLoggedIn) {
        Text('退出')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Md)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => this.handleLogout())
      } else if (this.auth.logging) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppColor.Brand)
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
    .onClick(() => {
      if (!this.auth.isLoggedIn) {
        this.handleLogin();
      }
    })
  }

  @Builder
  buildServerGroup() {
    Column() {
      Text($r('app.string.cloud_source_group_title'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })

      Row({ space: AppSpace.Sm }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(28)
        .height(28)
        .backgroundColor(AppColor.Brand)
        .borderRadius(7)

        Column({ space: 2 }) {
          Text($r('app.string.cloud_source_api_title'))
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
          Text(this.serverApiDisplay())
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .padding({
        left: ROW_INDENT,
        right: ROW_INDENT,
        top: AppSpace.Sm,
        bottom: AppSpace.Sm
      })
      .constraintSize({ minHeight: 64 })
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .onClick(() => this.openServerConfig())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildServerConfigSheet() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text($r('app.string.cloud_source_sheet_title'))
          .fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
          .width(36)
          .height(36)
          .onClick(() => {
            if (!this.isServerChecking && !this.isServerSaving) {
              this.isServerConfigVisible = false;
            }
          })
      }
      .width('100%')

      Text($r('app.string.cloud_source_sheet_desc'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Column({ space: AppSpace.Xs }) {
        Text($r('app.string.cloud_source_api_label'))
          .fontSize(AppFont.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')

        TextInput({
          text: this.serverApiDraft,
          placeholder: $r('app.string.cloud_source_api_placeholder')
        })
          .height(48)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(AppRadius.Md)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
          .enabled(!this.isServerChecking && !this.isServerSaving)
          .onChange((value: string) => {
            this.serverApiDraft = value;
            this.serverCheckState = 0;
          })

        Text($r('app.string.cloud_source_api_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.serverCheckState !== 0) {
        this.buildServerCheckStatus()
      }

      Row({ space: AppSpace.Sm }) {
        Button() {
          Row({ space: AppSpace.Xs }) {
            if (this.isServerChecking) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(AppColor.Brand)
            } else {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(17)
                .fontColor([AppColor.Brand])
            }
            Text(this.isServerChecking
              ? $r('app.string.cloud_source_checking')
              : $r('app.string.cloud_source_check'))
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
          }
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Md)
        .enabled(!this.isServerChecking && !this.isServerSaving)
        .onClick(() => this.testServerApi())

        Button() {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(17)
              .fontColor([$r('sys.color.font_secondary')])
            Text($r('app.string.cloud_source_restore_default'))
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
          }
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(AppRadius.Md)
        .enabled(!this.isServerChecking && !this.isServerSaving)
        .onClick(() => this.restoreDefaultServerApi())
      }
      .width('100%')

      Button() {
        Row({ space: AppSpace.Xs }) {
          if (this.isServerSaving) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.OnBrand)
          } else {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(17)
              .fontColor([AppColor.OnBrand])
          }
          Text(this.isServerSaving
            ? $r('app.string.cloud_source_saving')
            : $r('app.string.cloud_source_save'))
            .fontSize(AppFont.BodyL)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.OnBrand)
        }
      }
      .width('100%')
      .height(48)
      .backgroundColor(AppColor.Brand)
      .borderRadius(AppRadius.Md)
      .enabled(!this.isServerChecking && !this.isServerSaving)
      .onClick(() => this.saveServerApi())
    }
    .width('100%')
    .padding({
      left: AppSpace.Md,
      right: AppSpace.Md,
      top: AppSpace.Xs,
      bottom: AppSpace.Md + WindowUtils.getBottomSafeVp()
    })
  }

  @Builder
  buildServerCheckStatus() {
    Row({ space: AppSpace.Xs }) {
      if (this.serverCheckState === 1) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppColor.Brand)
        Text($r('app.string.cloud_source_checking'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      } else if (this.serverCheckState === 2) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(17)
          .fontColor(['#34C759'])
        Text($r('app.string.cloud_source_check_success'))
          .fontSize(AppFont.Caption)
          .fontColor('#248A3D')
      } else if (this.serverCheckState === 4) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor(['#FF9F0A'])
        Text($r('app.string.cloud_source_check_degraded'))
          .fontSize(AppFont.Caption)
          .fontColor('#C77700')
      } else if (this.serverCheckState === 5) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_secondary')])
        Text($r('app.string.cloud_source_restored_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
      } else {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor(['#FF3B30'])
        Text($r('app.string.cloud_source_check_failed'))
          .fontSize(AppFont.Caption)
          .fontColor('#D70015')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 24 })
  }

  @Builder
  buildGroup(title: string, items: ProfileItem[]) {
    Column() {
      Text(title)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })

      Column() {
        ForEach(items, (item: ProfileItem, index: number) => {
          this.buildRow(item)
          if (index < items.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: ROW_INDENT + 28 + AppSpace.Sm })
          }
        }, (item: ProfileItem) => item.id)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildRow(item: ProfileItem) {
    Row({ space: AppSpace.Sm }) {
      Stack() {
        SymbolGlyph(item.icon)
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(28)
      .height(28)
      .backgroundColor(item.iconBg)
      .borderRadius(7)

      Text(item.label)
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
    .onClick(() => this.onItemTap(item.id))
  }
}
