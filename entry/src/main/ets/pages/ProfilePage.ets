import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

interface ProfileItem {
  icon: Resource;
  label: string;
  id: string;
}

const PROFILE_ITEMS: ProfileItem[] = [
  { icon: $r('sys.symbol.clock'), label: '历史记录', id: 'history' },
  { icon: $r('sys.symbol.arrow_down_circle'), label: '本地导入', id: 'import' },
  { icon: $r('sys.symbol.gearshape'), label: '设置', id: 'settings' },
  { icon: $r('sys.symbol.info_circle'), label: '关于', id: 'about' }
];

@ComponentV2
export struct ProfilePage {
  @Local nickname: string = '听书用户';
  @Param navStack: NavPathStack = new NavPathStack();

  private onItemTap(id: string): void {
    if (id === 'history') {
      this.navStack.pushPathByName('history', '');
    } else if (id === 'import') {
      this.navStack.pushPathByName('import', '');
    } else if (id === 'settings') {
      this.navStack.pushPathByName('settings', '');
    } else if (id === 'about') {
      this.navStack.pushPathByName('about', '');
    }
  }

  build() {
    Column({ space: AppSpace.Lg }) {
      Row({ space: AppSpace.Md }) {
        Stack() {
          Circle()
            .width(56)
            .height(56)
            .fill(AppColor.Brand)
          Text('U')
            .fontSize(AppFont.TitleL)
            .fontColor(AppColor.OnBrand)
            .fontWeight(FontWeight.Bold)
        }
        .width(56)
        .height(56)

        Column({ space: 4 }) {
          Text(this.nickname)
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
          Text('本地模式')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Xl, left: AppSpace.Lg })

      Column() {
        ForEach(PROFILE_ITEMS, (item: ProfileItem) => {
          Row({ space: AppSpace.Md }) {
            SymbolGlyph(item.icon)
              .fontSize(20)
              .fontColor(['#666666'])
            Text(item.label)
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor(['#CCCCCC'])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.onItemTap(item.id))
        }, (item: ProfileItem) => item.id)
      }
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
      .margin({ left: AppSpace.Md, right: AppSpace.Md })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
