import { AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

interface GuideItem {
  action: string;
  desc: string;
}

interface GuideGroup {
  title: string;
  items: GuideItem[];
}

/** 使用说明内容:每一条都对应代码里真实存在的交互 */
const GUIDE_GROUPS: GuideGroup[] = [
  {
    title: '首页',
    items: [
      { action: '双击底部「首页」页签', desc: '快速回到首页顶部' },
    ]
  },
  {
    title: '通用',
    items: [
      { action: '双击「书架 / 记录 / 我的」页签', desc: '快速回到当前页顶部' },
    ]
  },
  {
    title: '书架',
    items: [
      { action: '下拉', desc: '从欢 FM 刷新在线书籍的最新数据' },
      { action: '长按书籍并拖到底部删除区', desc: '移出书架(可选仅移除,或删除本地文件)' },
    ]
  },
  {
    title: '记录',
    items: [
      { action: '长按任一条记录', desc: '进入多选,批量删除收听记录' },
    ]
  },
  {
    title: '播放页',
    items: [
      { action: '长按「倍速」', desc: '恢复 1.0 倍速' },
      { action: '长按「定时」', desc: '取消睡眠定时' },
      { action: '长按「跳过」', desc: '清除片头 / 片尾跳过设置' },
    ]
  },
];

@ComponentV2
export struct GuidePage {
  @Param navStack: NavPathStack = new NavPathStack();

  @Builder
  groupCard(group: GuideGroup): void {
    Column({ space: AppSpace.Xs }) {
      Text(group.title)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ left: AppSpace.Sm, bottom: AppSpace.Xs })

      Column() {
        ForEach(group.items, (item: GuideItem, idx: number) => {
          Column({ space: 2 }) {
            Text(item.action)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
            Text(item.desc)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })

          if (idx < group.items.length - 1) {
            Divider().color('#F0F0F0').margin({ left: AppSpace.Lg, right: AppSpace.Lg })
          }
        }, (item: GuideItem) => item.action)
      }
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => this.navStack.pop())
        Text('使用说明')
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

      Scroll() {
        Column({ space: AppSpace.Lg }) {
          ForEach(GUIDE_GROUPS, (group: GuideGroup) => {
            this.groupCard(group)
          }, (group: GuideGroup) => group.title)

          Text('部分手势带轻震反馈,更多用法会持续补充')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: AppSpace.Sm, bottom: AppSpace.Xl })
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs })
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
}
