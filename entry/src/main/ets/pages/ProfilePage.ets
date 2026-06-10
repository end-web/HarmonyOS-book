import { AppRadius, AppSpace, AppFont, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

interface ProfileItem {
  icon: Resource;
  label: string;
  id: string;
  iconBg: ResourceColor;
}

const CONTENT_ITEMS: ProfileItem[] = [
  { icon: $r('sys.symbol.arrow_down_circle'), label: '本地导入', id: 'import', iconBg: '#34C759' }
];

const SYSTEM_ITEMS: ProfileItem[] = [
  { icon: $r('sys.symbol.gearshape'), label: '设置', id: 'settings', iconBg: '#8E8E93' },
  { icon: $r('sys.symbol.info_circle'), label: '关于', id: 'about', iconBg: '#0A59F7' }
];

const ROW_INDENT: number = AppSpace.Md;

@ComponentV2
export struct ProfilePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};

  private scrollScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scrollScroller);
  }

  private onItemTap(id: string): void {
    if (id === 'import') {
      this.navStack.pushPathByName('import', '');
    } else if (id === 'settings') {
      this.navStack.pushPathByName('settings', '');
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
      .backgroundColor($r('app.color.home_card_surface_soft'))
      .borderRadius(AppRadius.Lg)
      .shadow({ radius: 12, color: HomeTheme.CardShadow, offsetY: 4 })
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
