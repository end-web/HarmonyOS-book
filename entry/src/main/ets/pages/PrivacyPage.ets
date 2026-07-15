import { AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

export const PRIVACY_POLICY_VERSION = '2.0.0';

interface PolicySection {
  title: string;
  paragraphs: string[];
}

const POLICY_SECTIONS: PolicySection[] = [
  {
    title: '一、我们如何收集和使用信息',
    paragraphs: [
      '本应用是一款本地优先的听书工具，不要求注册账号，不收集你的姓名、电话、身份证、定位、通讯录等个人身份信息。',
      '书架、收藏、播放历史和应用设置仅保存在你的设备本地（系统 Preference 与沙箱目录），不会上传到开发者服务器。'
    ]
  },
  {
    title: '二、网络访问说明',
    paragraphs: [
      '应用申请「访问网络（INTERNET）」权限，仅用于以下场景：',
      '1) 从内置的听友 FM 服务获取推荐、搜索结果、节目目录和音频地址；',
      '2) 加载书籍封面和下载你主动选择的离线音频；',
      '3) 从 GitHub Release 及其网络代理检查应用更新。',
      '网络请求只服务于上述功能，不用于广告追踪或向开发者上报使用数据。'
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
    title: '四、第三方内容说明',
    paragraphs: [
      '在线书籍与音频内容由听友 FM 相关服务提供，其内容、可用性和版权状态不受本应用控制。',
      '请在法律法规和内容提供方许可范围内使用在线内容及离线下载功能。'
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

  build() {
    Column() {
      this.buildHeader()

      Scroll() {
        Column({ space: AppSpace.Lg }) {
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
        .padding({ bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
}
