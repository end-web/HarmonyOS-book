# 布局开发指南

## 概述

布局定义了组件在界面中的位置和大小关系。在声明式UI中，所有页面都由自定义组件构成，开发者需要选择合适的布局容器来管理UI组件的排列。

### 布局开发流程

1. **确定页面结构** - 分析页面的整体布局框架
2. **分析元素构成** - 识别页面中的UI元素及其关系
3. **选择布局容器** - 根据需求选用适合的布局组件

### 布局元素的组成

每个组件都包含以下区域：

| 区域 | 说明 | 相关属性 |
|-----|------|---------|
| 组件区域 | 组件的整体大小 | width、height |
| 组件内容区 | 减去border后的区域 | padding、border |
| 组件内容 | 实际内容占用空间 | 由内容决定 |
| 布局边界 | 组件区域 + margin | margin |

---

## 布局选择指南

根据场景选择合适的布局：

| 布局类型 | 组件 | 适用场景 |
|---------|------|---------|
| 线性布局 | Row/Column | 子元素可线性排列时优先选择 |
| 弹性布局 | Flex | 需要子元素自动拉伸或压缩比例时 |
| 栅格布局 | GridRow/GridCol | 多设备响应式布局，内容相同布局不同 |
| 相对布局 | RelativeContainer | 页面元素复杂，线性布局嵌套过深时 |
| 层叠布局 | Stack | 组件需要堆叠效果，如弹窗、遮罩 |

---

## 线性布局 (Row/Column)

### 概述

线性布局是最常用的布局方式，Row用于水平排列，Column用于垂直排列。

### 基本概念

- **主轴**：Row为水平方向，Column为垂直方向
- **交叉轴**：垂直于主轴的方向
- **间距**：子元素之间的距离

### 基本用法

#### Row - 水平排列

```typescript
Row({ space: 10 }) {
  Text('1').width(80).height(80).backgroundColor('#F5DEB3')
  Text('2').width(80).height(80).backgroundColor('#D2B48C')
  Text('3').width(80).height(80).backgroundColor('#F5DEB3')
}
.width('100%')
.justifyContent(FlexAlign.Center)
.alignItems(VerticalAlign.Center)
```

#### Column - 垂直排列

```typescript
Column({ space: 10 }) {
  Text('1').width('80%').height(50).backgroundColor('#F5DEB3')
  Text('2').width('80%').height(50).backgroundColor('#D2B48C')
  Text('3').width('80%').height(50).backgroundColor('#F5DEB3')
}
.width('100%')
.justifyContent(FlexAlign.Center)
.alignItems(HorizontalAlign.Center)
```

### 主轴对齐 (justifyContent)

控制子元素在主轴上的排列方式：

| 值 | 效果 |
|---|------|
| Start | 从起始端开始排列（默认） |
| Center | 居中排列 |
| End | 从末端开始排列 |
| SpaceBetween | 两端对齐，中间均匀分布 |
| SpaceAround | 每个元素两侧间距相等 |
| SpaceEvenly | 所有间距完全相等 |

```typescript
Row() {
  Text('1').width(60).height(40).backgroundColor('#F5DEB3')
  Text('2').width(60).height(40).backgroundColor('#D2B48C')
  Text('3').width(60).height(40).backgroundColor('#F5DEB3')
}
.width('100%')
.justifyContent(FlexAlign.SpaceBetween)
```

### 交叉轴对齐 (alignItems)

控制子元素在交叉轴上的对齐方式：

**Row容器：**

| 值 | 效果 |
|---|------|
| Top | 顶部对齐 |
| Center | 居中对齐（默认） |
| Bottom | 底部对齐 |

**Column容器：**

| 值 | 效果 |
|---|------|
| Start | 左对齐 |
| Center | 居中对齐（默认） |
| End | 右对齐 |

### 自适应拉伸

使用 **Blank** 组件填充空白空间：

```typescript
Row() {
  Text('Bluetooth').fontSize(18)
  Blank()  // 自动填充空白
  Toggle({ type: ToggleType.Switch, isOn: true })
}
.width('100%')
.padding(12)
```

### 自适应缩放

使用 **layoutWeight** 按比例分配空间：

```typescript
Row() {
  Column().layoutWeight(1).height('100%').backgroundColor('#F5DEB3')
  Column().layoutWeight(2).height('100%').backgroundColor('#D2B48C')
  Column().layoutWeight(1).height('100%').backgroundColor('#F5DEB3')
}
.width('100%')
.height(100)
```

### 滚动支持

内容超出屏幕时使用 **Scroll** 组件：

```typescript
Scroll() {
  Column({ space: 10 }) {
    ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], (item: number) => {
      Text(`${item}`).width('90%').height(150).backgroundColor('#FFFFFF')
    })
  }
}
.scrollBar(BarState.On)
.edgeEffect(EdgeEffect.Spring)
```

---

## 弹性布局 (Flex)

### 概述

Flex提供了更灵活的子元素排列、对齐和空间分配能力，适用于需要子元素自动压缩或拉伸的场景。

### 基本概念

- **主轴**：子元素排列方向
- **交叉轴**：垂直于主轴
- **弹性元素**：Flex容器内的子组件

### 布局方向 (direction)

```typescript
Flex({ direction: FlexDirection.Row }) {
  Text('1').width('33%').height(50).backgroundColor('#F5DEB3')
  Text('2').width('33%').height(50).backgroundColor('#D2B48C')
  Text('3').width('33%').height(50).backgroundColor('#F5DEB3')
}
```

| 值 | 说明 |
|---|------|
| Row | 水平方向，从左到右（默认） |
| RowReverse | 水平方向，从右到左 |
| Column | 垂直方向，从上到下 |
| ColumnReverse | 垂直方向，从下到上 |

### 换行设置 (wrap)

```typescript
Flex({ wrap: FlexWrap.Wrap }) {
  Text('1').width('50%').height(50).backgroundColor('#F5DEB3')
  Text('2').width('50%').height(50).backgroundColor('#D2B48C')
  Text('3').width('50%').height(50).backgroundColor('#F5DEB3')
}
```

| 值 | 说明 |
|---|------|
| NoWrap | 不换行，子元素会被压缩（默认） |
| Wrap | 换行 |
| WrapReverse | 反向换行 |

### 对齐方式

```typescript
Flex({
  justifyContent: FlexAlign.SpaceBetween,  // 主轴对齐
  alignItems: ItemAlign.Center,            // 交叉轴对齐
  alignContent: FlexAlign.Start            // 多行时交叉轴对齐
}) {
  // 子元素
}
```

### 弹性属性

#### flexBasis - 基准尺寸

设置子元素在主轴上的初始大小：

```typescript
Text('flexBasis(100)')
  .flexBasis(100)  // 宽度为100vp
  .height(100)
```

#### flexGrow - 拉伸比例

分配父容器剩余空间：

```typescript
Flex() {
  Text('flexGrow(1)').flexGrow(1).width(100).height(100)
  Text('flexGrow(4)').flexGrow(4).width(100).height(100)
  Text('no flexGrow').width(100).height(100)
}
.width(360)
```

> 剩余空间按1:4分配给前两个元素

#### flexShrink - 压缩比例

空间不足时的压缩比例：

```typescript
Flex() {
  Text('flexShrink(3)').flexShrink(3).width(200).height(100)
  Text('no flexShrink').width(200).height(100)
  Text('flexShrink(2)').flexShrink(2).width(200).height(100)
}
.width(400)
```

### alignSelf - 单独设置对齐

覆盖容器的alignItems设置：

```typescript
Flex({ alignItems: ItemAlign.Center }) {
  Text('Top').alignSelf(ItemAlign.Start)
  Text('Center')  // 使用容器的设置
  Text('Bottom').alignSelf(ItemAlign.End)
}
```

---

## 栅格布局 (GridRow/GridCol)

### 概述

栅格布局是多设备场景下的响应式布局工具，通过断点系统实现不同屏幕尺寸的自适应。

### 栅格系统断点

| 断点 | 宽度范围(vp) | 设备类型 |
|-----|-------------|---------|
| xs | [0, 320) | 最小宽度设备 |
| sm | [320, 600) | 小宽度设备 |
| md | [600, 840) | 中等宽度设备 |
| lg | [840, +∞) | 大宽度设备 |

### 基本用法

```typescript
GridRow({ columns: 4 }) {
  GridCol({ span: 1 }) {
    Text('1').width('100%').height(50)
  }.backgroundColor('#F5DEB3')
  GridCol({ span: 1 }) {
    Text('2').width('100%').height(50)
  }.backgroundColor('#D2B48C')
  GridCol({ span: 1 }) {
    Text('3').width('100%').height(50)
  }.backgroundColor('#F5DEB3')
}
```

### 响应式列数

不同断点设置不同列数：

```typescript
GridRow({
  columns: { xs: 2, sm: 4, md: 8, lg: 12 }
}) {
  // 子元素
}
```

### 子组件属性

#### span - 占用列数

```typescript
// 固定列数
GridCol({ span: 2 }) { }

// 响应式列数
GridCol({ span: { xs: 1, sm: 2, md: 3, lg: 4 } }) { }
```

#### offset - 偏移列数

```typescript
GridCol({ span: 4, offset: 2 }) {
  Text('偏移2列')
}
```

#### order - 排列顺序

```typescript
GridRow() {
  GridCol({ order: 3 }) { Text('1') }
  GridCol({ order: 1 }) { Text('2') }  // 最先显示
  GridCol({ order: 2 }) { Text('3') }
}
```

### 间距设置

```typescript
GridRow({ gutter: 10 }) { }  // 水平垂直间距相同

GridRow({ gutter: { x: 20, y: 10 } }) { }  // 分别设置
```

### 断点监听

```typescript
GridRow() {
  // 子元素
}
.onBreakpointChange((breakpoint: string) => {
  console.log(`当前断点: ${breakpoint}`)  // 'xs', 'sm', 'md', 'lg'
})
```

### 嵌套使用

```typescript
GridRow({ columns: 12 }) {
  GridCol({ span: 12 }) {
    GridRow({ columns: 12 }) {
      GridCol({ span: 4 }) { Text('Left') }
      GridCol({ span: 8 }) { Text('Right') }
    }
  }
  GridCol({ span: 12 }) {
    Text('Footer')
  }
}
```

---

## 相对布局 (RelativeContainer)

### 概述

RelativeContainer通过锚点规则实现复杂的二维布局，适用于复杂页面和减少嵌套层级的场景。

### 基本概念

- **锚点**：定位参照物（父容器、兄弟组件、辅助线、屏障）
- **参考边界**：组件自身的对齐边界（top、bottom、left、right、middle、center）
- **对齐方式**：相对于锚点的对齐位置

### 基本用法

```typescript
RelativeContainer() {
  Row() {
    Text('row1')
  }
  .width(100)
  .height(100)
  .backgroundColor('#a3cf62')
  .alignRules({
    top: { anchor: '__container__', align: VerticalAlign.Top },
    left: { anchor: '__container__', align: HorizontalAlign.Start }
  })
  .id('row1')
}
.width(300)
.height(300)
```

### 锚点类型

#### 父容器为锚点

`__container__` 代表父容器：

```typescript
.alignRules({
  top: { anchor: '__container__', align: VerticalAlign.Top },
  right: { anchor: '__container__', align: HorizontalAlign.End }
})
```

#### 兄弟组件为锚点

使用兄弟组件的id：

```typescript
Row()
  .alignRules({
    top: { anchor: 'row1', align: VerticalAlign.Bottom },
    left: { anchor: 'row1', align: HorizontalAlign.Start }
  })
  .id('row2')
```

### 对齐方式

**水平方向：**

| 边界 | 对齐值 |
|-----|--------|
| left | HorizontalAlign.Start |
| middle | HorizontalAlign.Center |
| right | HorizontalAlign.End |

**垂直方向：**

| 边界 | 对齐值 |
|-----|--------|
| top | VerticalAlign.Top |
| center | VerticalAlign.Center |
| bottom | VerticalAlign.Bottom |

### 位置偏移

```typescript
Row()
  .alignRules({
    top: { anchor: '__container__', align: VerticalAlign.Top },
    right: { anchor: '__container__', align: HorizontalAlign.End }
  })
  .offset({ x: -10, y: 20 })  // 微调位置
```

### 辅助线 (guideLine)

创建虚拟锚点便于对齐：

```typescript
RelativeContainer() {
  Row()
    .alignRules({
      left: { anchor: 'guideline1', align: HorizontalAlign.End },
      top: { anchor: 'guideline2', align: VerticalAlign.Top }
    })
}
.guideLine([
  { id: 'guideline1', direction: Axis.Vertical, position: { start: 50 } },
  { id: 'guideline2', direction: Axis.Horizontal, position: { start: 50 } }
])
```

### 屏障 (barrier)

一组组件的共同边界：

```typescript
RelativeContainer() {
  Row().id('row1')
  Row().id('row2')
  Row()
    .alignRules({
      left: { anchor: 'barrier1', align: HorizontalAlign.End }
    })
    .id('row3')
}
.barrier([
  { id: 'barrier1', direction: BarrierDirection.RIGHT, referencedId: ['row1', 'row2'] }
])
```

---

## 层叠布局 (Stack)

### 概述

Stack用于实现组件层叠效果，后入栈的子元素覆盖前面的元素。

### 基本用法

```typescript
Stack() {
  Text('Background')
    .width('100%')
    .height(200)
    .backgroundColor('#e1dede')
  Text('Foreground')
    .width('60%')
    .height('60%')
    .backgroundColor('#c1cbac')
}
.width('100%')
.height(200)
```

### 对齐方式 (alignContent)

```typescript
Stack({ alignContent: Alignment.Center }) {
  // 子元素默认居中
}
```

| 值 | 说明 |
|---|------|
| TopStart | 左上角 |
| Top | 上方居中 |
| TopEnd | 右上角 |
| Start | 左侧居中 |
| Center | 居中（默认） |
| End | 右侧居中 |
| BottomStart | 左下角 |
| Bottom | 下方居中 |
| BottomEnd | 右下角 |

### Z序控制 (zIndex)

控制层叠顺序，值越大越在上层：

```typescript
Stack() {
  Column().width(100).height(100).backgroundColor('#ffd306').zIndex(2)
  Column().width(150).height(150).backgroundColor(Color.Pink).zIndex(1)
  Column().width(200).height(200).backgroundColor(Color.Grey)
}
```

### 典型场景

**底部悬浮按钮：**

```typescript
Stack({ alignContent: Alignment.Bottom }) {
  Flex({ wrap: FlexWrap.Wrap }) {
    // 主要内容
  }
  .width('100%')
  .height('100%')

  Row() {
    Button('确认').width(120)
    Button('取消').width(120)
  }
  .margin({ bottom: 20 })
}
```

---

## 布局约束与自适应

### 拉伸能力

```typescript
// flexGrow - 拉伸
Text().flexGrow(1)

// flexShrink - 压缩
Text().flexShrink(0)
```

### 缩放能力

```typescript
// 宽高比
Image().aspectRatio(16/9)
```

### 占比能力

```typescript
// 百分比
Text().width('50%')

// layoutWeight
Text().layoutWeight(1)
```

### 隐藏能力

```typescript
// 显示优先级
Text().displayPriority(1)  // 空间不足时优先隐藏
Text().displayPriority(2)  // 较高优先级，后隐藏
```

### 定位能力

| 方式 | 说明 | 属性 |
|-----|------|-----|
| 绝对定位 | 相对父容器左上角偏移 | position |
| 相对定位 | 相对自身位置偏移 | offset |

```typescript
// 绝对定位
Text().position({ x: 100, y: 100 })

// 相对定位
Text().offset({ x: 10, y: 10 })
```

---

## 布局优化建议

1. **减少嵌套层级** - 避免过深的布局嵌套，考虑使用RelativeContainer
2. **合理使用性能属性** - 使用layoutWeight替代固定尺寸
3. **按需渲染** - 使用LazyForEach、if/else条件渲染
4. **避免重复计算** - 缓存计算结果，避免在build中做复杂运算
5. **选择合适的布局** - 根据场景选择最优布局组件