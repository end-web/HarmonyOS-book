// Badge 组件示例模板
// 来源: HarmonyOSComponentUXExamples/entry/src/main/ets/components/presentation/badge

// ========== 数字徽标 ==========

Badge({
  count: 3,
  position: BadgePosition.RightTop,
  style: {}
}) {
  Rect({ width: 40, height: 40 })
    .radiusWidth(8)
    .fill($r('sys.color.background_secondary'))
}

// ========== 文本徽标 ==========

Badge({
  value: '36',
  position: BadgePosition.RightTop,
  style: {}
}) {
  Rect({ width: 40, height: 40 })
    .radiusWidth(8)
    .fill($r('sys.color.background_secondary'))
}

// ========== 超出最大值 ==========

Badge({
  count: 1000,
  maxCount: 99,
  position: BadgePosition.RightTop,
  style: {}
}) {
  Rect({ width: 40, height: 40 })
    .radiusWidth(8)
    .fill($r('sys.color.background_secondary'))
}

// ========== 圆点徽标 ==========

Badge({
  value: '',
  position: BadgePosition.RightTop,
  style: { badgeSize: 6 }
}) {
  Rect({ width: 40, height: 40 })
    .radiusWidth(8)
    .fill($r('sys.color.background_secondary'))
}

// ========== 右侧圆点 ==========

Badge({
  value: '',
  position: BadgePosition.Right,
  style: {
    badgeSize: 6,
    badgeColor: $r('sys.color.warning')
  }
}) {
  SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
    .fontSize($r('sys.float.Title_M'))
    .fontColor([$r('sys.color.icon_fourth')])
}

// ========== Grid中使用 ==========

Badge({
  value: '',
  position: BadgePosition.RightTop,
  style: { badgeSize: 6 }
}) {
  Row() {
    SymbolGlyph($r('sys.symbol.music'))
      .fontSize($r('sys.float.Title_M'))
      .fontColor([Color.Black])
  }
  .width(40)
  .height(40)
  .borderRadius(20)
  .justifyContent(FlexAlign.Center)
}