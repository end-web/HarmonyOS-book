# 循环渲染迁移

## 目录

- [ForEach迁移Repeat](#foreach迁移repeat)
- [LazyForEach迁移Repeat](#lazyforeach迁移repeat)
  - [数据首次渲染](#数据首次渲染)
  - [数据更新操作](#数据更新操作)
  - [修改数据子属性](#修改数据子属性)
  - [拖拽排序](#拖拽排序)
  - [组件复用](#组件复用)
  - [模板渲染](#模板渲染)

---

## 基础使用

Repeat的基础使用

```typescript
@ComponentV2
struct TodoItem {
    @Params todo:Todo = new Todo('','')
    build() {
        // 组件内容
    }
}

// 访问时，需要通过RepeatItem包裹，
Repeat(this.todos).each((todo: RepeatItem<Todo>) => {
  Column() {
      // 给组件赋值时，通过.item取值
    TodoItem({ todo:todo.item })
  }
  .height(108)
})
```

## ForEach迁移Repeat

```typescript
// V1 - ForEach
@Observed
class ArticleChangeChild {
  public id: string;
  public title: string;
  public isLiked: boolean;
  public likesCount: number;
}

@Entry
@Component
struct ArticleListChangeView {
  @State articleList: Array<ArticleChangeChild> = [/* ... */];
  build() {
    List() {
      ForEach(this.articleList, (item: ArticleChangeChild) => {
        ListItem() {
          ArticleCardChangeChild({ article: item })
        }
      }, (item: ArticleChangeChild) => item.id)
    }
  }
}

// V2 - Repeat
@ObservedV2
class ArticleChangeChild {
  public id: string;
  public title: string;
  @Trace public isLiked: boolean;
  @Trace public likesCount: number;
}

@Entry
@ComponentV2
struct ArticleListChangeView {
  @Local articleList: Array<ArticleChangeChild> = [/* ... */];
  build() {
    List() {
      Repeat(this.articleList)
        .each((obj: RepeatItem<ArticleChangeChild>) => {
          ListItem() {
            ArticleCardChangeChild({ article: obj.item })
          }
        })
        .key(item => item.id)
    }
  }
}
```

---

## LazyForEach迁移Repeat

### 数据首次渲染

```typescript
// V1 - LazyForEach
class MyDataSource implements IDataSource {
  private dataArray: string[] = [];
  public totalCount(): number { return this.dataArray.length; }
  public getData(index: number): string { return this.dataArray[index]; }
  public pushData(data: string): void {
    this.dataArray.push(data);
    this.notifyDataAdd(this.dataArray.length - 1);
  }
}

@Entry
@Component
struct MyComponent {
  private data: MyDataSource = new MyDataSource();
  aboutToAppear() {
    for (let i = 0; i <= 20; i++) {
      this.data.pushData(`Hello ${i}`);
    }
  }
  build() {
    List({ space: 3 }) {
      LazyForEach(this.data, (item: string) => {
        ListItem() { Text(item).fontSize(50) }
      }, (item: string) => item)
    }.cachedCount(5)
  }
}

// V2 - Repeat
@Entry
@ComponentV2
struct MyComponent {
  @Local data: Array<string> = [];

  aboutToAppear() {
    for (let i = 0; i <= 20; i++) {
      this.data.push(`Hello ${i}`);
    }
  }

  build() {
    List({ space: 3 }) {
      Repeat(this.data)
        .each((repeatItem: RepeatItem<string>) => {
          ListItem() { Text(repeatItem.item).fontSize(50) }
        })
        .key((item: string) => item)
        .virtualScroll()
    }.cachedCount(5)
  }
}
```

### 数据更新操作

```typescript
// V1 - 需调用notifyDataChange等方法
class MyDataSource extends BasicDataSource {
  public changeData(index: number, data: string): void {
    this.dataArray.splice(index, 1, data);
    this.notifyDataChange(index);
  }
}

// V2 - 直接修改数组即可
@Entry
@ComponentV2
struct MyComponent {
  @Local data: Array<string> = [];

  build() {
    Column() {
      Button('Add new item').onClick(() => { this.data.push(`New item`); })
      Button('Delete item 0').onClick(() => { this.data.splice(0, 1); })
      Button('Change item 0').onClick(() => { this.data.splice(0, 1, `Changed item`); })
      Button('Change all').onClick(() => {
        this.data = this.data.map((item: string) => 'Changed ' + item);
      })
      List() {
        Repeat(this.data)
          .each((ri) => { ListItem() { Text(ri.item) } })
          .key((item) => item)
          .virtualScroll()
      }
    }
  }
}
```

### 修改数据子属性

```typescript
// V1 - @Observed + @ObjectLink
@Observed
class StringData {
  message: string;
}

@Entry
@Component
struct MyComponent {
  private data: MyDataSource = new MyDataSource();
  build() {
    List() {
      LazyForEach(this.data, (item: StringData) => {
        ListItem() {
          ChildComponent({ data: item })
        }
      }, (item, index) => index.toString())
    }
  }
}

@Component
struct ChildComponent {
  @ObjectLink data: StringData;
  build() { Text(this.data.message) }
}

// V2 - @ObservedV2 + @Trace
@ObservedV2
class StringData {
  @Trace message: string;
}

@Entry
@ComponentV2
struct MyComponent {
  @Local data: StringData[] = [];

  build() {
    List() {
      Repeat(this.data)
        .each((ri) => {
          ListItem() {
            Text(ri.item.message).onClick(() => { ri.item.message += '0'; })
          }
        })
        .key((item, index) => index.toString())
        .virtualScroll()
    }
  }
}
```

### 拖拽排序

```typescript
// V1
LazyForEach(this.data, (item: string) => {
  ListItem() { Text(item) }
}, (item: string) => item)
  .onMove((from: number, to: number) => {
    this.data.moveDataWithoutNotify(from, to);
  })

// V2
Repeat(this.data)
  .each((ri) => { ListItem() { Text(ri.item) } })
  .key((item) => item)
  .virtualScroll()
  .onMove((from: number, to: number) => {
    let tmp = this.data.splice(from, 1);
    this.data.splice(to, 0, tmp[0]);
  })
```

### 组件复用

```typescript
// V1 - @Reusable
@Reusable
@Component
struct ChildComponent {
  @State data: StringData = new StringData('');
  aboutToReuse(params: Record<string, ESObject>): void {
    this.data = params.data as StringData;
  }
  build() { Text(this.data.message) }
}

// V2方案1 - Repeat自身复用能力
@Entry
@ComponentV2
struct MyComponent {
  @Local data: StringData[] = [];
  build() {
    List() {
      Repeat(this.data)  // Repeat自身具备复用功能
        .each((ri) => { ListItem() { Text(ri.item.message) } })
        .key((item, index) => index.toString())
        .virtualScroll()
    }
  }
}

// V2方案2 - @ReusableV2
@Entry
@ComponentV2
struct MyComponent {
  @Local data: StringData[] = [];
  build() {
    List() {
      Repeat(this.data)
        .each((ri) => { ListItem() { ChildComponent({ data: ri.item }) } })
        .key((item, index) => index.toString())
        .virtualScroll({ reusable: false })  // 关闭Repeat自身复用
    }
  }
}

@ReusableV2
@ComponentV2
struct ChildComponent {
  @Param data: StringData = new StringData('');
  aboutToReuse(): void { console.info('aboutToReuse'); }
  build() { Text(this.data.message) }
}
```

### 模板渲染

```typescript
// V1 - 手动if判断
LazyForEach(this.data, (item: StringData) => {
  ListItem() {
    if (item.getType() == 0) {
      ChildComponentA({ data: item })
    } else {
      ChildComponentB({ data: item })
    }
  }
}, (item, index) => index.toString())

// V2方案1 - Repeat自身模板渲染
Repeat(this.data)
  .each((ri) => { ListItem() { Text('Default') } })
  .template('A', (ri) => { ListItem() { Row() { Text(ri.item.message); Button('Type A') } } })
  .template('B', (ri) => { ListItem() { Row() { Text(ri.item.message).fontColor(Color.Gray); Text('Type B') } } })
  .templateId((item: StringData) => item.getType() == 0 ? 'A' : 'B')
  .key((item, index) => index.toString())
  .virtualScroll()

// V2方案2 - 手动判断 + @ReusableV2
Repeat(this.data)
  .each((ri) => {
    ListItem() {
      if (ri.item.getType() == 0) {
        ChildComponentA({ data: ri.item })
      } else {
        ChildComponentB({ data: ri.item })
      }
    }
  })
  .key((item, index) => index.toString())
  .virtualScroll({ reusable: false })  // 必须关闭Repeat自身复用

@ReusableV2
@ComponentV2
struct ChildComponentA {
  @Param data: StringData = new StringData('', 0);
  build() { Row() { Text(this.data.message); Button('Type A') } }
}
```

## 注意事项