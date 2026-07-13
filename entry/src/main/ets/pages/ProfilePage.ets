import { AppRadius, AppSpace, AppFont, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AuthService, HwAuthErrorCode } from '../service/AuthService';
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
  { icon: $r('sys.symbol.doc_text'), label: '书源管理', id: 'sourceManage', iconBg: '#FF9500' },
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

  private scrollScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scrollScroller);
    this.auth.restore();
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
    } else if (id === 'sourceManage') {
      this.navStack.pushPathByName('sourceManage', '');
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
          .color('#0A59F7')
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
