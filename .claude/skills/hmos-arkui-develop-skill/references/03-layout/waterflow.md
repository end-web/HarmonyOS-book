# WaterFlow（瀑布流）参考
## 1. 基础结构
```ts
// 最简瀑布流
WaterFlow() {
  FlowItem() {
    // 单个子组件
    Text('item 1')
  }
  FlowItem() {
    Text('item 2')
  }
}
// 带 Scroller 的可滚动瀑布流
private scroller: Scroller = new Scroller()
WaterFlow({ scroller: this.scroller }) {
  LazyForEach(this.dataSource, (item: DataModel) => {
    FlowItem() {
      // 内容
    }
  }, (item: DataModel) => item.id.toString())
}
```
- WaterFlow 子组件**只能是 FlowItem** 或以 FlowItem 为顶层组件的自定义组件。
- FlowItem **只能包含一个子组件**，多个组件需要再包一层容器（如 Column/Row）。
---
## 2. 布局模板：columnsTemplate / rowsTemplate
### 2-1 基本用法
```ts
WaterFlow() { /*...*/ }
  .columnsTemplate('1fr 1fr')     // 2 列纵向瀑布流
  .rowsTemplate('1fr 1fr 1fr')   // 3 行横向瀑布流
```
- `columnsTemplate`：设置列数及列宽占比，不设置时默认 `'1fr'`（1 列）。
- `rowsTemplate`：设置行数及行高占比，不设置时默认 `'1fr'`（1 行）。
- `fr` 个数 = 行/列数；`数字 + fr` 表示该行/列在总宽高中的占比。
### 2-2 auto-fill 自动换列/换行
```ts
WaterFlow() { /*...*/ }
  .columnsTemplate('repeat(auto-fill, 100vp)')
```
- `repeat(auto-fill, track-size)`：根据可用宽度自动计算列数，每列宽度为 `track-size`（如 100vp）。
---
## 3. 主轴方向与模板优先级（layoutDirection）
`layoutDirection` 决定主轴方向，且**优先级高于 rowsTemplate / columnsTemplate**。
```ts
WaterFlow() { /*...*/ }
  .layoutDirection(FlexDirection.Column) // 默认：纵向瀑布流
```
- **纵向布局**（`Column` / `ColumnReverse`）：`columnsTemplate` 决定列数。
- **横向布局**（`Row` / `RowReverse`）：`rowsTemplate` 决定行数。
- 不设置 `layoutDirection` 时，默认 `FlexDirection.Column`，`columnsTemplate` 生效。
---
## 4. 间距、约束尺寸与滚动条
```ts
WaterFlow() { /*...*/ }
  .columnsGap(10)       // 列间距，默认 0
  .rowsGap(8)           // 行间距，默认 0
  .itemConstraintSize({ minWidth: 0, maxWidth: '100%' }) // 子组件尺寸约束
  .scrollBar(BarState.Auto)       // 滚动条状态
  .scrollBarColor('#ff0000')
  .scrollBarWidth(4)
```
---
## 5. 数据渲染：ForEach / LazyForEach / Repeat
### 5-1 ForEach（适合短数据）
```ts
WaterFlow() {
  ForEach(this.items, (item: DataModel) => {
    FlowItem() {
      Text(item.name)
    }
  }, (item: DataModel) => item.id.toString())
}
.columnsTemplate('1fr 1fr')
```
### 5-2 LazyForEach（适合长列表 / 性能优化）
```ts
class WaterFlowDataSource implements IDataSource {
  private list: DataModel[] = []
  totalCount(): number {
    return this.list.length;
  }
  getData(index: number): DataModel {
    return this.list[index];
  }
  registerDataChangeListener(listener: DataChangeListener): void {}
  unregisterDataChangeListener(listener: DataChangeListener): void {}
}
// 使用
private dataSource: WaterFlowDataSource = new WaterFlowDataSource();
WaterFlow() {
  LazyForEach(this.dataSource, (item: DataModel) => {
    FlowItem() {
      Text(item.name)
    }
  }, (item: DataModel) => item.id.toString())
}
.columnsTemplate('1fr 1fr')
```
---
## 6. 性能关键：cachedCount
```ts
WaterFlow() { /*...*/ }
  .cachedCount(3)   // API 11+，只在 LazyForEach / Repeat(virtualScroll) 时生效
```
- 设置预加载的 FlowItem 数量，超出显示和缓存范围的节点会被释放。
- **强烈建议**：数据量较大时使用 LazyForEach + `cachedCount`，避免一次性创建大量节点。
---
## 7. 滚动控制与事件
### 7-1 Scroller 滚动控制
```ts
private scroller: Scroller = new Scroller();
WaterFlow({ scroller: this.scroller }) { /*...*/ }
// 滚动到指定索引
this.scroller.scrollToIndex(10);
```
- WaterFlow 的 `scroller` 目前主要支持 `scrollToIndex` 等滚动控制接口。
### 7-2 常用事件
```ts
WaterFlow() { /*...*/ }
  .onReachStart(() => {
    // 滚动到起始位置触发
  })
  .onReachEnd(() => {
    // 滚动到末尾触发，常用于加载更多
  })
  .onScrollIndex((start, end) => {
    // 当前显示区域起止索引变化时触发
    console.log(`可见索引范围: ${start} - ${end}`);
  })
```
---
## 8. 典型场景示例
### 8-1 基础双列纵向瀑布流
```ts
WaterFlow() {
  LazyForEach(this.dataSource, (item: Product) => {
    FlowItem() {
      Column() {
        Image(item.cover).width('100%')
        Text(item.title).margin({ top: 4 })
        Text(`¥${item.price}`).fontColor('#ff0000')
      }
      .padding(8)
      .backgroundColor('#fff')
      .borderRadius(8)
    }
    .width('100%')
  }, (item: Product) => item.id.toString())
}
.columnsTemplate('1fr 1fr')
.columnsGap(8)
.rowsGap(8)
.padding(8)
.backgroundColor('#f5f5f5')
```
### 8-2 横向瀑布流（多行）
```ts
WaterFlow() { /*...*/ }
  .layoutDirection(FlexDirection.Row)   // 横向布局
  .rowsTemplate('1fr 1fr 1fr')          // 3 行
```
---
## 9. 性能优化 CheckList
1. **长列表必须用 LazyForEach / Repeat(virtualScroll)**，避免一次性创建所有 FlowItem。
2. **合理设置 `cachedCount`**，减少滑动白块，但不要设置过大，避免内存压力。
3. **FlowItem 内部布局尽量扁平**，减少嵌套层级和测算开销。
4. **图片使用缩略图或懒加载**，减少解码和内存占用。
5. **避免在 FlowItem 中频繁创建复杂自定义组件**，必要时可使用 `@Builder` 复用逻辑。
---
## 10. 常见坑点速查
| 现象                  | 常见原因                                                     | 解决思路                                                     |
| --------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 瀑布流不显示 / 不滚动 | 高度未设置或为 0                                             | 确保 WaterFlow 有明确高度，或在父容器中使用 `layoutWeight(1)` |
| 滑动有明显白块        | 未使用 LazyForEach 或 `cachedCount` 过小                     | 改用 LazyForEach，适当增大 `cachedCount`                     |
| FlowItem 显示异常     | 包含多个子组件，或未作为 WaterFlow 子组件                    | 确保 FlowItem 只有一个根子组件，且直接挂在 WaterFlow 下      |
| 模板设置不生效        | 同时设置了 `rowsTemplate` 和 `columnsTemplate`，但 `layoutDirection` 决定了实际生效的模板 | 根据主轴方向只设置对应模板，或按纵向/横向规则设置两套模板    |
---
如果你需要，我可以把 List / Grid / WaterFlow 三张速查表合并成一份「滚动容器总表」，方便整体查阅。