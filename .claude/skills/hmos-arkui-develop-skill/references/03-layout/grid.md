# Grid（网格布局）Reference
## 1. 基础结构
```ts
// 最简 Grid
Grid() {
  GridItem() {
    Text('item')
  }
}
// 带 Scroller 的可滚动 Grid
private scroller: Scroller = new Scroller()
Grid(this.scroller) {
  ForEach(this.list, (item: DataModel) => {
    GridItem() {
      Text(item.name)
    }
  }, (item: DataModel) => item.id.toString())
}
```
- Grid 子组件**只能是 GridItem**，GridItem 只能包含**一个子组件**。
---
## 2. 布局模板：rowsTemplate / columnsTemplate
### 2-1 模板语法
```ts
Grid() { /*...*/ }
  .columnsTemplate('1fr 1fr 2fr')  // 3列：第3列是前两列之和
  .rowsTemplate('1fr 1fr')        // 2行等高
```
- `columnsTemplate`：设置列数及列宽占比；不设置时默认 1 列。
- `rowsTemplate`：设置行数及行高占比；不设置时默认 1 行。
- `fr` 个数 = 行/列数；`数字 + fr` 表示该行/列在总宽高中的占比。
### 2-2 布局模式速查（关键）
| 设置方式                                              | 布局效果                                            | 是否可滚动   | 说明                                                         |
| ----------------------------------------------------- | --------------------------------------------------- | ------------ | ------------------------------------------------------------ |
| 同时设置 `rowsTemplate` 和 `columnsTemplate`          | 固定行列数，只展示这些网格，其余不显示              | **不可滚动** | 推荐：用于固定布局（计算器、固定九宫格）。                   |
| 只设置其中一个（`columnsTemplate` 或 `rowsTemplate`） | 按设置的方向排布，超出可滚动                        | **可滚动**   | 设置 `columnsTemplate`：垂直滚动；设置 `rowsTemplate`：水平滚动。 |
| 两个都不设置                                          | 按 `layoutDirection` 方向排布，行列数由多个属性决定 | **不可滚动** | 用于简单自适应网格，超出部分不显示。                         |
---
## 3. 间距与滚动条
```ts
Grid() { /*...*/ }
  .columnsGap(10)   // 列间距，默认 0
  .rowsGap(8)       // 行间距，默认 0
  .scrollBar(BarState.Auto)      // 滚动条状态：Off / On / Auto
  .scrollBarColor('#ff0000')     // 滚动条颜色
  .scrollBarWidth(4)             // 滚动条宽度(vp)，默认 4
```
---
## 4. 数据渲染：ForEach / LazyForEach
### 4-1 ForEach（适合短列表）
```ts
Grid() {
  ForEach(this.items, (item: DataModel) => {
    GridItem() {
      Text(item.name)
    }
  }, (item: DataModel) => item.id.toString())
}
.columnsTemplate('1fr 1fr 1fr')
```
### 4-2 LazyForEach（适合长列表 / 性能优化）
```ts
// 自定义数据源实现 IDataSource
class MyDataSource implements IDataSource {
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
// 在 Grid 中使用
private dataSource: MyDataSource = new MyDataSource();
Grid() {
  LazyForEach(this.dataSource, (item: DataModel) => {
    GridItem() {
      Text(item.name)
    }
  }, (item: DataModel) => item.id.toString())
}
.columnsTemplate('1fr 1fr')
.cachedCount(3)  // 预加载条目数，仅在 LazyForEach 中生效
```
- `cachedCount`：在显示区域上下各缓存 `cachedCount * 列数` 个 GridItem，超出范围的会被释放。
---
## 5. 不均匀网格 & 跨行跨列
### 5-1 使用 GridLayoutOptions（推荐，API 12+）
```ts
// 通过 layoutOptions 统一管理不规则布局
layoutOptions: GridLayoutOptions = {
  regularSize: [1, 1],  // 普通项占 1行1列
  onGetRectByIndex: (index: number) => {
    // 返回 [rowStart, columnStart, rowSpan, columnSpan]
    if (index === 0) {
      return [0, 0, 1, 2]; // 第 0 项：跨 2 列
    }
    if (index === 1) {
      return [0, 2, 2, 1]; // 第 1 项：跨 2 行
    }
    return [0, 0, 1, 1];   // 默认：1 行 1 列
  }
};
Grid(undefined, this.layoutOptions) {
  // ...
}
.columnsTemplate('1fr 1fr 1fr')
.rowsTemplate('1fr 1fr 1fr')
```
- `onGetRectByIndex`：返回 `[rowStart, columnStart, rowSpan, columnSpan]`，表示起始行列与跨越数。
### 5-2 使用 GridItem 属性（旧写法）
```ts
Grid() {
  GridItem() {
    Text('跨两列')
  }
  .columnStart(0)
  .columnEnd(1)  // 起始列 0，结束列 1（跨 2 列）
  GridItem() {
    Text('跨两行')
  }
  .rowStart(0)
  .rowEnd(1)     // 起始行 0，结束行 1（跨 2 行）
}
.columnsTemplate('1fr 1fr 1fr')
.rowsTemplate('1fr 1fr 1fr')
```
- 只有在**同时设置 `columnsTemplate` 和 `rowsTemplate`** 时，这些属性才按预期布局。
---
## 6. 主轴方向 & 自适应行列数（不使用模板时）
```ts
Grid() { /*...*/ }
  .layoutDirection(GridDirection.Row)   // 默认：先从左到右填满一行，再下一行
  .maxCount(4)                          // 主轴方向最大网格数
  .minCount(2)                          // 主轴方向最小网格数
  .cellLength(80)                       // 主轴方向一行的高度或一列的宽度
```
- **注意**：一旦设置了 `rowsTemplate` 或 `columnsTemplate`，`layoutDirection / maxCount / minCount / cellLength` 将不再生效。
---
## 7. 滚动控制与事件
### 7-1 Scroller 滚动控制
```ts
private scroller: Scroller = new Scroller();
Grid(this.scroller) { /*...*/ }
// 滚动到指定索引
this.scroller.scrollToIndex(10);
// 滚动到边缘
this.scroller.scrollEdge(Edge.Top);
// 翻页滚动
this.scroller.scrollPage({ next: true });
```
### 7-2 常用事件
```ts
Grid() { /*...*/ }
  .onScrollIndex((first: number) => {
    // 当前显示起始索引变化时触发
    console.log('当前起始索引:', first);
  })
```
- `onScrollIndex`：当前显示区域的起始 GridItem 索引变化时触发。
---
## 8. 性能优化 CheckList
1. **长列表必须用 LazyForEach**，避免一次性创建大量 GridItem。
2. **合理设置 `cachedCount`**：减少滑动白块，但不要过大，避免内存压力。
3. **简化 GridItem 内部布局**：减少嵌套层级，避免复杂测算。
4. **图片使用缩略图或懒加载**，减少解码和内存开销。
5. **优先使用模板布局模式**（`rowsTemplate + columnsTemplate`），性能优于不使用模板的模式。
---
## 9. 常见坑点速查
| 现象                                  | 常见原因                                                     | 解决思路                                                     |
| ------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Grid 不显示 / 不滚动                  | 同时设置了 `rowsTemplate` 和 `columnsTemplate`，导致不可滚动且只显示固定行列 | 想要滚动：只设置其中一个模板，或使用 `layoutDirection` 模式。 |
| 滑动有明显白块                        | 未使用 LazyForEach 或 `cachedCount` 过小                     | 改用 LazyForEach，适当增大 `cachedCount`。                   |
| GridItem 跨行跨列不生效               | 未同时设置 `columnsTemplate` 和 `rowsTemplate`，或行列号范围错误 | 确保使用模板模式，并检查 `rowStart/rowEnd/columnStart/columnEnd` 或 `onGetRectByIndex` 返回值是否合法。 |
| `layoutDirection` / `maxCount` 不生效 | 已经设置了 `rowsTemplate` 或 `columnsTemplate`               | 想用这些属性，就不要设置 `rowsTemplate` / `columnsTemplate`。 |
---
如果你希望，我可以在下一步直接把这份 Grid 速查表与之前的 List、WaterFlow 合并成一份「滚动容器总表」。