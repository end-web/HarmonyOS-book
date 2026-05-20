// Menu 菜单示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/action/menu

// ========== 下拉菜单 ==========

@Builder
function dropdownMenuBuilder() {
  Menu() {
    MenuItem({ content: '菜单项1' })
    MenuItem({ content: '菜单项2' })
    MenuItem({ content: '菜单项3' })
  }
  .menuItemDivider({
    strokeWidth: LengthMetrics.vp(1),
    color: $r('sys.color.comp_background_tertiary'),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

Row() {
  Text('下拉菜单')
    .fontSize($r('sys.float.Body_L'))
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
}
.bindMenu(dropdownMenuBuilder())

// ========== 带图标的菜单 ==========

@Builder
function iconMenuBuilder() {
  Menu() {
    MenuItem({ content: '复制', iconInfo: { symbol: $r('sys.symbol.doc_on_doc') } })
    MenuItem({ content: '粘贴', iconInfo: { symbol: $r('sys.symbol.doc_on_clipboard') } })
    MenuItem({ content: '删除', iconInfo: { symbol: $r('sys.symbol.trash') } })
  }
}

// ========== 长按浮动菜单 ==========

@Builder
function longPressMenuBuilder() {
  Menu() {
    MenuItem({ content: '选项1' })
    MenuItem({ content: '选项2' })
  }
}

Text('长按显示菜单')
  .bindContextMenu(longPressMenuBuilder, ResponseType.LongPress)

// ========== 带标题的菜单 ==========

@Builder
function titleMenuBuilder() {
  Menu() {
    MenuItemGroup({ header: '分组标题' }) {
      MenuItem({ content: '选项1' })
      MenuItem({ content: '选项2' })
    }
    MenuItemGroup({ header: '其他' }) {
      MenuItem({ content: '选项3' })
    }
  }
}