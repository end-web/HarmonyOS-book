// List 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/container/list

// ========== 内容型列表 ==========

import { HdsListItemCard, PrefixImage } from '@kit.UIDesignKit'
import { ImageModifier } from '@kit.ArkUI'

List({ space: 12 }) {
  ListItem() {
    Row() {
      HdsListItemCard({
        prefixItem: new PrefixImage({
          image: $r('app.media.icon'),
          modifier: new ImageModifier().width(56).height(56).borderRadius(8)
        }),
        textItem: {
          primaryText: { text: '主标题' },
          secondaryText: { text: '副标题' },
          description: { text: '描述文本' }
        },
        cardPrefixMargin: 0,
        cardSuffixMargin: 0,
        cardBackgroundColor: $r('sys.color.ohos_id_color_background_transparent')
      })
    }
    .width('100%')
    .height(88)
    .borderRadius(16)
    .backgroundColor($r('sys.color.comp_background_list_card'))
  }
}

// ========== 效率型列表 ==========

import { PrefixIcon, SuffixSwitch, SuffixText, IconSize } from '@kit.UIDesignKit'

List({ space: 12 }) {
  ListItemGroup() {
    ListItem() {
      Row() {
        HdsListItemCard({
          prefixItem: new PrefixIcon({
            iconSize: IconSize.SYSTEM_ICON,
            iconValue: { symbol: $r('sys.symbol.star_circle_fill') }
          }),
          textItem: {
            primaryText: { text: '标题' },
            secondaryText: { text: '副标题' }
          },
          suffixItem: new SuffixSwitch({
            isCheck: false,
            onChange: (isOn: boolean) => {
              console.info('Switch: ' + isOn)
            }
          }),
          cardPrefixMargin: 0,
          cardSuffixMargin: 0,
          cardBackgroundColor: $r('sys.color.ohos_id_color_background_transparent')
        })
      }
      .width('100%')
      .height(64)
    }
  }
  .borderRadius(16)
  .backgroundColor($r('sys.color.comp_background_list_card'))
  .divider({
    strokeWidth: 1,
    color: $r('sys.color.comp_background_tertiary')
  })
}

// ========== 滑动交互列表 ==========

import { HdsListItem, SuffixButton } from '@kit.UIDesignKit'
import { ListItemModifier, SymbolGlyphModifier } from '@kit.ArkUI'

@ComponentV2
struct SwipeActionListExample {
  @Local dataArr: string[] = ['1', '2', '3']

  build() {
    List({ space: 12 }) {
      Repeat(this.dataArr)
        .each(() => {
          HdsListItem({
            hdsListItemCard: {
              prefixItem: new PrefixImage({
                image: $r('app.media.icon'),
                modifier: new ImageModifier().width(48).height(48).borderRadius(12)
              }),
              textItem: {
                primaryText: { text: '标题' },
                secondaryText: { text: '副标题' }
              },
              cardPrefixMargin: 0,
              cardSuffixMargin: 0,
              cardBackgroundColor: $r('sys.color.ohos_id_color_background_transparent')
            },
            swipeActionOptions: {
              icons: [
                {
                  icon: new SymbolGlyphModifier($r('sys.symbol.share'))
                    .fontColor([Color.White])
                    .fontSize($r('sys.float.Body_L')),
                  backgroundColor: $r('sys.color.confirm'),
                  onAction: () => {
                    console.info('Share clicked')
                  }
                }
              ],
              deleteIconOptions: {
                backgroundColor: Color.Red,
                iconColor: Color.White,
                onAction: () => {
                  this.dataArr.splice(0, 1)
                }
              }
            },
            listItemModifier: new ListItemModifier()
              .width('100%')
              .height(80)
              .borderRadius(16)
              .backgroundColor($r('sys.color.comp_background_list_card'))
          })
        })
    }
  }
}

// ========== 下拉菜单列表项 ==========

@Builder
function dropdownMenuBuilder() {
  Menu() {
    MenuItem({ content: '选项1' })
    MenuItem({ content: '选项2' })
    MenuItem({ content: '选项3' })
  }
  .menuItemDivider({
    strokeWidth: LengthMetrics.vp(1),
    color: $r('sys.color.comp_background_tertiary'),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

ListItem() {
  Row() {
    Text('单行列表和下拉选项')
      .fontSize($r('sys.float.Body_L'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))

    Blank()

    Row() {
      Text('右侧文本')
        .fontSize($r('sys.float.Subtitle_S'))
        .fontColor($r('sys.color.font_secondary'))
      SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
        .fontSize($r('sys.float.Body_L'))
        .fontColor([$r('sys.color.icon_fourth')])
    }
    .bindMenu(dropdownMenuBuilder())
  }
  .width('100%')
  .height(56)
}

// ========== 带单选的列表项 ==========

@ComponentV2
struct RadioListExample {
  @Local isRadioChecked: boolean = false

  build() {
    ListItem() {
      Row() {
        Text('右侧单选')
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))

        Blank()

        Radio({ value: 'Radio', group: 'radioGroup' })
          .checked(this.isRadioChecked)
          .onClick(() => {
            this.isRadioChecked = !this.isRadioChecked
          })
      }
      .width('100%')
      .height(56)
    }
  }
}