import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';

const DOMAIN = 0xFF00;
const TAG = 'PrivacyPage';

export const PRIVACY_POLICY_VERSION = '1.0.0';

interface PolicySection {
  title: string;
  paragraphs: string[];
}

const POLICY_SECTIONS: PolicySection[] = [
  {
    title: '一、我们如何收集和使用信息',
    paragraphs: [
      '本应用是一款本地优先的听书工具，不要求注册账号，不收集你的姓名、电话、身份证、定位、通讯录等个人身份信息。',
      '所有书架、收藏、播放历史、阅读偏好、书源订阅地址都仅保存在你的设备本地（系统 Preference 与沙箱目录），我们无服务器，不会上传到任何后端。'
    ]
  },
  {
    title: '二、网络访问说明',
    paragraphs: [
      '应用申请「访问网络（INTERNET）」权限，仅用于以下场景：',
      '1) 拉取你主动添加的书源订阅 JSON；',
      '2) 按你保存的书源规则向对应站点发起搜索、章节、正文、音频请求；',
      '3) 加载书籍封面图片。',
      '所有目标地址都由你自行添加的书源决定，与我们无关；我们不向任何第三方服务上报数据。'
    ]
  },
  {
    title: '三、设备权限说明',
    paragraphs: [
      '• 后台运行（KEEP_BACKGROUND_RUNNING）+ 音频后台模式：用于在你锁屏或切换其他应用时继续播放有声内容、保持系统媒体卡片可控。',
      '• 振动（VIBRATE）：用于按钮触感反馈，可在系统设置中关闭。',
      '应用不申请位置、相机、麦克风、通讯录、短信、日历等任何隐私权限。'
    ]
  },
  {
    title: '四、第三方书源风险',
    paragraphs: [
      '应用本身不内置任何书源。你添加的订阅源由第三方提供，其内容、协议、JS 解析逻辑均不受本应用控制。',
      '请仅添加你信任来源的书源；对书源内容及由此产生的版权问题，本应用不承担责任。'
    ]
  },
  {
    title: '五、未成年人保护',
    paragraphs: [
      '本应用不针对 14 周岁以下儿童设计。如你是未成年人，请在监护人陪同下使用并阅读本政策。'
    ]
  },
  {
    title: '六、政策更新',
    paragraphs: [
      '当本政策有重大调整时，应用会在更新后再次弹出同意页，由你重新确认。',
      `当前版本：v${PRIVACY_POLICY_VERSION}`
    ]
  }
];

@ComponentV2
export struct PrivacyPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param mode: string = 'view';
  @Event onAgreed: () => void = () => {};

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private async agree(): Promise<void> {
    try {
      await PreferenceService.setPrivacyAgreedVersion(PRIVACY_POLICY_VERSION);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'save privacy agreed failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    this.onAgreed();
  }

  private exitApp(): void {
    try {
      this.context.getApplicationContext().killAllProcesses();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'killAllProcesses failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  build() {
    Column() {
      if (this.mode === 'view') {
        this.buildHeader()
      } else {
        this.buildConsentTitle()
      }

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          if (this.mode === 'consent') {
            Text('请在使用前阅读以下隐私政策。继续使用即代表你已阅读并同意本政策内容。')
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(22)
              .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
          }

          ForEach(POLICY_SECTIONS, (sec: PolicySection) => {
            Column({ space: AppSpace.Sm }) {
              Text(sec.title)
                .fontSize(AppFont.BodyL)
                .fontColor($r('sys.color.font_primary'))
                .fontWeight(FontWeight.Bold)
                .width('100%')

              ForEach(sec.paragraphs, (p: string) => {
                Text(p)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary'))
                  .lineHeight(22)
                  .width('100%')
              }, (p: string, idx: number) => `${sec.title}_${idx}_${p.length}`)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
          }, (sec: PolicySection) => sec.title)
        }
        .width('100%')
        .padding({ bottom: this.mode === 'consent' ? 160 : WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.mode === 'consent') {
        this.buildConsentFooter()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Text('隐私政策')
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
  }

  @Builder
  buildConsentTitle() {
    Column({ space: AppSpace.Xs }) {
      Text('欢迎使用网听')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
      Text('隐私政策')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xl,
      left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg
    })
  }

  @Builder
  buildConsentFooter() {
    Column({ space: AppSpace.Sm }) {
      Button('同意并继续')
        .width('100%')
        .height(48)
        .backgroundColor(AppColor.Brand)
        .fontColor('#FFFFFF')
        .fontSize(AppFont.BodyL)
        .borderRadius(AppRadius.Md)
        .onClick(() => this.agree())

      Button('不同意并退出')
        .width('100%')
        .height(48)
        .backgroundColor(Color.Transparent)
        .fontColor($r('sys.color.font_tertiary'))
        .fontSize(AppFont.Body)
        .onClick(() => this.exitApp())
    }
    .width('100%')
    .padding({
      left: AppSpace.Lg, right: AppSpace.Lg,
      top: AppSpace.Md,
      bottom: WindowUtils.getBottomSafeVp() + AppSpace.Md
    })
    .backgroundColor($r('sys.color.background_primary'))
  }
}
