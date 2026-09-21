import { AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

export const PRIVACY_POLICY_VERSION = '3.3.0';

class PolicySection {
  id: string;
  title: ResourceStr;
  paragraphs: ResourceStr[];

  constructor(id: string, title: ResourceStr, paragraphs: ResourceStr[]) {
    this.id = id;
    this.title = title;
    this.paragraphs = paragraphs;
  }
}

const POLICY_SECTIONS: PolicySection[] = [
  new PolicySection('overview', $r('app.string.privacy_overview_title'), [
    $r('app.string.privacy_overview_identity'), $r('app.string.privacy_overview_local')
  ]),
  new PolicySection('network', $r('app.string.privacy_network_title'), [
    $r('app.string.privacy_network_huawei_account'),
    $r('app.string.privacy_network_sources'), $r('app.string.privacy_network_accounts'),
    $r('app.string.privacy_network_updates'), $r('app.string.privacy_network_tracking')
  ]),
  new PolicySection('permissions', $r('app.string.privacy_permissions_title'), [
    $r('app.string.privacy_permissions_background'), $r('app.string.privacy_permissions_vibration'),
    $r('app.string.privacy_permissions_picker')
  ]),
  new PolicySection('content', $r('app.string.privacy_content_title'), [
    $r('app.string.privacy_content_sources'), $r('app.string.privacy_content_rights')
  ]),
  new PolicySection('data', $r('app.string.privacy_data_title'), [
    $r('app.string.privacy_data_storage'), $r('app.string.privacy_data_local_backup'),
    $r('app.string.privacy_data_backup'),
    $r('app.string.privacy_data_delete')
  ]),
  new PolicySection('children', $r('app.string.privacy_children_title'), [
    $r('app.string.privacy_children_body')
  ]),
  new PolicySection('contact', $r('app.string.privacy_contact_title'), [
    $r('app.string.privacy_contact_updates'), $r('app.string.privacy_contact_channel'),
    $r('app.string.privacy_version', PRIVACY_POLICY_VERSION)
  ])
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

              ForEach(sec.paragraphs, (p: ResourceStr) => {
                Text(p)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary'))
                  .lineHeight(22)
                  .width('100%')
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
          }, (sec: PolicySection) => sec.id)
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
      Text($r('app.string.privacy_title'))
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
