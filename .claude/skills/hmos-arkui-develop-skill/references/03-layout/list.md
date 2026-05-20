# List（列表） Skill Reference
## 搭建基础列表布局
**适用情况**：需要展示一组可滚动数据（如联系人、设置项、商品列表）。
### 1. 基本结构
```ts
List() {
  ListItem() {
    // 列表项内容
  }
}
```
- List：容器组件，子组件只能是 `ListItem` 或 `ListItemGroup`，会自动按主轴方向排列，超出屏幕时滚动。
- ListItem：单个列表项，只能有一个根子组件；多个组件需要再包一层容器（如 Row）。
### 2. 列表项为多组件的情况
```ts
List() {
  ListItem() {
    Row() {
      Image($r('app.media.icon'))
        .width(40)
        .height(40)
        .margin(10)
      Text('联系人名称')
        .fontSize(20)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }
}
```
---
## 垂直 / 水平滚动与多列布局
### 1. 垂直滚动列表（默认）
```ts
List() {
  // ...
}
// 默认就是垂直滚动，无需设置 listDirection
```
### 2. 水平滚动列表
```ts
List() {
  // ...
}
.listDirection(Axis.Horizontal)
```
- 主轴方向就是滚动方向；垂直列表主轴是垂直，水平列表主轴是水平。
### 3. 多列列表（交叉轴自适应列数）
**固定列数：**
```ts
List() {
  // ...
}
.lanes(2) // 两列垂直列表
```
**根据宽度自适应列数：**
```ts
@Entry
@Component
struct AdaptiveList {
  @State egLanes: LengthConstrain = { minLength: 200, maxLength: 300 };
  build() {
    List() {
      // ...
    }
    .lanes(this.egLanes)
  }
}
```
- List 宽度为 300vp 时，1 列；宽度变为 400vp 时，自动变成 2 列。
### 4. 列表项在交叉轴对齐
```ts
List() {
  // ...
}
.alignListItem(ListItemAlign.Center) // 列表项在水平方向居中
```
---
## 数据渲染方式：ForEach / LazyForEach / Repeat
### 1. ForEach（适合短列表）
```ts
class Contact {
  public key: string = util.generateRandomUUID(true);
  public name: ResourceStr;
  public icon: Resource;
  constructor(name: ResourceStr, icon: Resource) {
    this.name = name;
    this.icon = icon;
  }
}
@Entry
@Component
struct ContactList {
  private contacts: Array<Contact> = [
    new Contact($r('app.string.peopleOne'), $r('app.media.iconA')),
    new Contact($r('app.string.peopleTwo'), $r('app.media.iconB'))
  ];
  build() {
    List() {
      ForEach(this.contacts, (item: Contact) => {
        ListItem() {
          Row() {
            Image(item.icon).width(40).height(40).margin(10)
            Text(item.name).fontSize(20)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }
      }, (item: Contact) => JSON.stringify(item))
    }
    .width('100%')
  }
}
```
- ForEach 会一次性创建所有 ListItem，适合数据量不大的短列表。
### 2. LazyForEach（适合长列表，按需加载）
```ts
// 数据源需实现 IDataSource 接口
export class ContactsGroupDataSource implements IDataSource {
  private list: object[] = [];
  constructor(list: object[]) {
    this.list = list;
  }
  totalCount(): number {
    return this.list.length;
  }
  getData(index: number): object {
    return this.list[index];
  }
  registerDataChangeListener(listener: DataChangeListener): void {}
  unregisterDataChangeListener(listener: DataChangeListener): void {}
}
// 在 List 中使用 LazyForEach
List() {
  LazyForEach(dataSource, (item: Contact) => {
    ListItem() {
      Row() {
        Image(item.icon).width(40).height(40).margin(10)
        Text(item.name).fontSize(20)
      }
      .width('100%')
    }
  }, (item: Contact) => JSON.stringify(item))
}
```
- LazyForEach 只创建并布局显示区域及缓存区域的 ListItem，适合长列表，性能更好。
### 3. Repeat（带 virtualScroll 的循环渲染）
```ts
List() {
  Repeat({ virtualScroll: true }, (item, index) => {
    ListItem() {
      // ...
    }
  })
}
```
- 使用 `virtualScroll` 时，ListItem 会从缓存池复用，滑出显示区域的 ListItem 会被回收，适合非常长的列表。
---
## 列表样式：间距、分隔线、滚动条
### 1. 设置内容间距
```ts
List({ space: 10 }) {
  // 列表项之间沿主轴方向间距 10vp
}
```
### 2. 添加分隔线
```ts
class DividerTmp {
  public strokeWidth: Length = 1;
  public startMargin: Length = 60;
  public endMargin: Length = 10;
  public color: ResourceColor = '#ffe9f0f0';
  constructor(strokeWidth: Length, startMargin: Length, endMargin: Length, color: ResourceColor) {
    this.strokeWidth = strokeWidth;
    this.startMargin = startMargin;
    this.endMargin = endMargin;
    this.color = color;
  }
}
@Entry
@Component
struct DividerList {
  @State egDivider: DividerTmp = new DividerTmp(1, 60, 10, '#ffe9f0f0');
  build() {
    List() {
      // ...
    }
    .divider(this.egDivider)
  }
}
```
- 分隔线画在两个 ListItem 之间，第一项上方和最后一项下方不会画线；多列时 startMargin / endMargin 作用于每一列。
### 3. 内置滚动条
```ts
List() {
  // ...
}
.scrollBar(BarState.Auto) // 按需显示滚动条
```
- API version 10+ 默认就是 `BarState.Auto`。
### 4. 外置滚动条（ScrollBar + Scroller）
```ts
private listScroller: Scroller = new Scroller();
// List 绑定 Scroller
List({ scroller: this.listScroller }) {
  // ...
}
// ScrollBar 绑定同一个 Scroller
ScrollBar({ scroller: this.listScroller })
```
- ScrollBar 可以配合 List、Grid、Scroll、WaterFlow 等可滚动组件使用。
---
## 分组列表与粘性标题
### 1. 使用 ListItemGroup 分组
```ts
@Entry
@Component
struct GroupedList {
  @Builder
  itemHead(text: string) {
    Text(text)
      .fontSize(20)
      .backgroundColor('#fff1f3f5')
      .width('100%')
      .padding(5)
  }
  build() {
    List() {
      ListItemGroup({ header: this.itemHead('A') }) {
        // 分组 A 的 ListItem
      }
      ListItemGroup({ header: this.itemHead('B') }) {
        // 分组 B 的 ListItem
      }
    }
  }
}
```
- ListItemGroup 宽度默认充满 List，可设置 header 作为分组标题。
### 2. 多分组使用 ForEach / LazyForEach
- 将多个分组的 `title` 和 `contacts` 数据组成数组，再用 ForEach / LazyForEach 渲染多个 ListItemGroup。
### 3. 粘性标题（吸顶）
```ts
List() {
  LazyForEach(contactsGroupsDataSource, (itemGroup: ContactsGroup) => {
    ListItemGroup({ header: this.itemHead(itemGroup.title) }) {
      // ...
    }
  }, (itemGroup: ContactsGroup) => JSON.stringify(itemGroup))
}
.sticky(StickyStyle.Header) // 分组标题吸顶
```
- `sticky` 控制头部吸顶或底部吸底，配合 ListItemGroup 使用。
---
## 滚动控制与滚动位置监听
### 1. 使用 Scroller 控制滚动位置
```ts
private listScroller: Scroller = new Scroller();
List({ space: 20, scroller: this.listScroller }) {
  // ...
}
// 点击按钮返回顶部
Button('返回顶部')
  .onClick(() => {
    this.listScroller.scrollToIndex(0);
  })
```
- Scroller 可用于 List、Grid、Scroll 等组件，实现滚动到指定索引或距离。
### 2. 监听滚动位置变化（onScrollIndex）
```ts
@Entry
@Component
struct ResponsiveScrollPositionList {
  @State selectedIndex: number = 0;
  private listScroller: Scroller = new Scroller();
  build() {
    Stack({ alignContent: Alignment.End }) {
      List({ scroller: this.listScroller }) {
        // ...
      }
      .onScrollIndex((firstIndex: number) => {
        // 根据当前索引 firstIndex 更新字母索引栏的 selectedIndex
        // ...
      })
      AlphabetIndexer({ arrayValue: alphabets, selected: 0 })
        .selected(this.selectedIndex)
        .onSelect((index: number) => {
          this.listScroller.scrollToIndex(index);
        })
    }
  }
}
```
- 适用于字母索引、多级分类等场景。
---
## 列表项侧滑操作
### 1. 左滑显示删除按钮
```ts
@Builder
itemEnd(index: number) {
  Button({ type: ButtonType.Circle }) {
    Image($r('sys.media.ohos_ic_bottomsheet_close'))
      .width(40)
      .height(40)
  }
  .onClick(() => {
    // 从数据源中删除对应项
    this.messages.splice(index, 1);
  })
}
// 在 ListItem 上绑定 swipeAction
ListItem() {
  // ...
}
.swipeAction({
  end: {
    builder: () => {
      this.itemEnd(this.index);
    }
  }
})
```
- `start`：右滑起始端滑出的组件；`end`：左滑尾端滑出的组件。
---
## 列表项标记（Badge）
```ts
ListItem() {
  Badge({
    count: 1,
    position: BadgePosition.RightTop,
    style: { badgeSize: 16, badgeColor: '#FA2A2D' }
  }) {
    // 消息内容组件
  }
}
```
- 使用 Badge 组件在列表项右上角显示未读数量等标记。
---
## 下拉刷新与上拉加载
### 1. 基本思路

下拉刷新 / 上拉加载本质是响应触摸事件，在顶部或底部显示刷新/加载视图，完成后隐藏。

文档建议使用 Refresh 组件实现下拉刷新；上拉加载可结合滚动到底部事件实现。

## 编辑模式：新增与删除列表项
### 1. 新增列表项
- 定义数据结构（如 `ToDo` 类），在数据源中新增一条记录，刷新列表即可。
### 2. 删除列表项
```ts
// 从数据源中删除选中项
this.toDoData = this.toDoData.filter(toDoItem =>
  !this.selectedItems.some(selectedItem => selectedItem.name === toDoItem.name)
);
this.isEditMode = false;
```
- 编辑模式下通过维护 `selectedItems` 集合，批量删除列表项。
---
## 长列表性能优化
### 1. 使用 LazyForEach + cachedCount
```ts
List() {
  LazyForEach(dataSource, (item) => {
    ListItem() {
      // ...
    }
  }, (item) => JSON.stringify(item))
}
.cachedCount(3) // 显示区域外预缓存 3 行
```
- ForEach 适合短列表；长列表推荐使用 LazyForEach 或 Repeat 的 `virtualScroll`，避免一次性加载所有元素。
- `cachedCount` 设置预加载的列表项数量，减少滑动白块，提升滚动体验。
---
## 边缘滑动效果
- **支持滑动离手事件 / 边缘滑动效果**：文档中对应小节主要用于定制滑动交互与边缘视觉反馈，典型场景包括侧滑菜单、边缘滑动触发抽屉等，可根据需要再查阅示例代码。

