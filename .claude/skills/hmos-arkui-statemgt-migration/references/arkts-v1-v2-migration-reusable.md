# 组件复用迁移

## 目录

- [迁移规则](#迁移规则)
- [if使用场景](#if使用场景)
- [列表滚动-Repeat使用场景](#列表滚动-repeat使用场景)
- [列表滚动-if使用场景](#列表滚动-if使用场景)
- [列表滚动-Repeat全量加载](#列表滚动-repeat全量加载)
- [Grid使用场景](#grid使用场景)
- [WaterFlow使用场景](#waterflow使用场景)
- [Swiper使用场景](#swiper使用场景)
- [ListItemGroup使用场景](#listitemgroup使用场景)
- [多种条目类型使用场景](#多种条目类型使用场景)

---

## 迁移规则

### 装饰器迁移
- `@Reusable` → `@ReusableV2`
- `@Component` → `@ComponentV2`
- 状态变量迁移参考[组件内状态变量迁移](./arkts-v1-v2-migration-inner-component.md)

### 生命周期迁移
- `aboutToRecycle`：无需改动
- `aboutToReuse`：V2去掉参数，自动重置状态变量

```typescript
// V1
@Reusable
@Component
struct ReusableComponent {
  @State val: string = 'Hello World';
  aboutToRecycle(): void { console.info('aboutToRecycle called'); }
  aboutToReuse(params: ESObject): void {
    this.val = params.val ?? 'Hello World';
  }
}

// V2
@ReusableV2
@ComponentV2
struct ReusableV2Component {
  @Local val: string = 'Hello World';
  @Require @Param @Once param: string;
  aboutToRecycle(): void { console.info('aboutToRecycle called'); }
  aboutToReuse(): void {
    // @Local已自动重置，@Param @Once已重置为外部传入值
    console.info('aboutToReuse called');
  }
}
```

### reuseId → reuse

```typescript
// V1
ReusableComponent().reuseId('groupA')

// V2
ReusableV2Component().reuse({ reuseId: () => 'groupA' })
```

---

## if使用场景

```typescript
@ObservedV2
class Message {
  @Trace value: string | undefined;
  constructor(value: string) { this.value = value; }
}

@Entry
@ComponentV2
struct Index {
  @Local switch: boolean = true;

  build() {
    Column() {
      Button('Hello').onClick(() => { this.switch = !this.switch; })
      if (this.switch) {
        Child({ message: new Message('Child') }).reuse({ reuseId: () => 'Child' })
      }
    }
  }
}

@ReusableV2
@ComponentV2
struct Child {
  @Require @Param @Once message: Message = new Message('AboutToReuse');

  aboutToReuse() {
    console.info('Recycle====Child==');
  }

  build() {
    Column() {
      Text(this.message.value).fontSize(30)
    }
  }
}
```

---

## 列表滚动-Repeat使用场景

```typescript
@Entry
@ComponentV2
struct ReuseV2Demo {
  private data: string[] = [];

  aboutToAppear() {
    for (let i = 1; i < 1000; i++) {
      this.data.push(i + '');
    }
  }

  build() {
    Column() {
      List() {
        Repeat(this.data)
          .virtualScroll()
          .each((ri) => {
            ListItem() {
              CardViewV2({ item: ri.item })
            }
          })
      }
    }
  }
}

@ReusableV2
@ComponentV2
export struct CardViewV2 {
  @Param @Once item: string = '';

  aboutToReuse(): void {
    // Repeat自身能够进行复用，不会走到自定义组件复用的生命周期
  }

  build() {
    Column() {
      Text(this.item).fontSize(30)
    }
  }
}
```

---

## 列表滚动-if使用场景

```typescript
@Entry
@ComponentV2
struct Index {
  private dataSource: FriendMoment[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < 20; i++) {
      this.dataSource.push(new FriendMoment(i.toString(), `${i + 1}test_if`, 'app.media.startIcon'));
    }
    for (let i = 0; i < 50; i++) {
      this.dataSource.push(new FriendMoment(i.toString(), `${i + 1}test_if`, ''));
    }
  }

  build() {
    Column() {
      List({ space: 3 }) {
        Repeat(this.dataSource)
          .virtualScroll()
          .each((ri) => {
            ListItem() {
              if (ri.item.image) {
                OneMoment({ moment: ri.item }).reuse({ reuseId: () => 'withImage' })
              } else {
                OneMoment({ moment: ri.item }).reuse({ reuseId: () => 'noImage' })
              }
            }
          })
      }
    }
  }
}

@ObservedV2
class FriendMoment {
  @Trace id: string = '';
  @Trace text: string = '';
  @Trace title: string = '';
  @Trace image: string = '';
}

@ReusableV2
@ComponentV2
export struct OneMoment {
  @Require @Param moment: FriendMoment;

  aboutToReuse(): void {
    console.info(`aboutToReuse====OneMoment==复用了==${this.moment.text}`);
  }

  build() {
    Column() {
      Text(this.moment.text)
      if (this.moment.image !== '') {
        Image($r(this.moment.image)).height(50).width(50)
      }
    }
  }
}
```

---

## 列表滚动-Repeat全量加载

```typescript
@Entry
@ComponentV2
struct Index {
  @Local dataSource: ListItemObject[] = [];

  build() {
    Column() {
      List({ space: 10 }) {
        Repeat(this.dataSource)
          .each((ri) => {
            ListItem() {
              ListItemView({ obj: ri.item })
            }
          })
      }
    }
  }
}

@ReusableV2
@ComponentV2
struct ListItemView {
  @Require @Param obj: ListItemObject;

  aboutToAppear(): void {
    console.info('aboutToAppear==ListItemView==创建了==');
  }

  aboutToReuse() {
    console.info('aboutToReuse====ListItemView==复用了==');
  }

  build() {
    Column() {
      Text(`${this.obj.id}.标题`)
      if (this.obj.isExpand) {
        Text('expand')
      }
    }
    .onClick(() => { this.obj.isExpand = !this.obj.isExpand; })
  }
}

@ObservedV2
class ListItemObject {
  @Trace uuid: string = '';
  @Trace id: number = 0;
  @Trace isExpand: boolean = false;
}
```

---

## Grid使用场景

```typescript
@Entry
@ComponentV2
struct MyComponent {
  @Local data: number[] = [];

  aboutToAppear() {
    for (let i = 1; i < 1000; i++) {
      this.data.push(i);
    }
  }

  build() {
    Column() {
      Grid() {
        Repeat(this.data)
          .virtualScroll()
          .each((ri) => {
            GridItem() {
              ReusableV2ChildComponent({ item: ri.item })
            }
          })
      }
      .columnsTemplate('1fr 1fr 1fr')
    }
  }
}

@ReusableV2
@ComponentV2
struct ReusableV2ChildComponent {
  @Param item: number = 0;

  build() {
    Column() {
      Image($r('app.media.startIcon')).layoutWeight(1)
      Text(`图片${this.item}`)
    }
  }
}
```

---

## WaterFlow使用场景

```typescript
@ReusableV2
@ComponentV2
struct ReusableV2FlowItem {
  @Param item: number = 0;

  build() {
    Column() {
      Text('N' + this.item).fontSize(24)
      Image($r('app.media.startIcon')).width(50).height(50)
    }
  }
}

@Entry
@ComponentV2
struct Index {
  @Local dataSource: number[] = [];

  aboutToAppear() {
    for (let i = 0; i <= 60; i++) {
      this.dataSource.push(i);
    }
  }

  build() {
    Column() {
      WaterFlow() {
        Repeat(this.dataSource)
          .virtualScroll()
          .each((ri) => {
            FlowItem() {
              ReusableV2FlowItem({ item: ri.item })
            }
          })
      }
    }
  }
}
```

---

## Swiper使用场景

```typescript
@Entry
@ComponentV2
struct Index {
  private dataSource: Question[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < 1000; i++) {
      this.dataSource.push(new Question(i.toString(), `${i + 1}test_swiper`, $r('app.media.startIcon'), ['test1', 'test2']));
    }
  }

  build() {
    Column() {
      Swiper() {
        Repeat(this.dataSource)
          .virtualScroll()
          .each((ri) => {
            QuestionSwiperItem({ itemData: ri.item })
          })
      }
    }
  }
}

@ObservedV2
class Question {
  @Trace id: string = '';
  @Trace title: ResourceStr = '';
  @Trace image: ResourceStr = '';
  @Trace answers: Array<ResourceStr> = [];
}

@ReusableV2
@ComponentV2
struct QuestionSwiperItem {
  @Param itemData: Question | null = null;

  build() {
    Column() {
      Text(this.itemData?.title).fontSize(18)
      Image(this.itemData?.image).width(80).height(80)
    }
  }
}
```

---

## ListItemGroup使用场景

```typescript
@Entry
@ComponentV2
struct ListItemGroupAndReusable {
  dataSource: DataSrc[] = [];

  aboutToAppear() {
    for (let i = 0; i < 10000; i++) {
      let data = new DataSrc();
      for (let j = 0; j < 12; j++) {
        data.dataScr1.push(`测试条目数据: ${i} - ${j}`);
      }
      this.dataSource.push(data);
    }
  }

  build() {
    List() {
      Repeat(this.dataSource)
        .virtualScroll()
        .each((ri) => {
          ListItemGroup({ header: Text(ri.index.toString()) }) {
            Repeat(ri.item.dataScr1)
              .virtualScroll()
              .each((ri) => {
                ListItem() {
                  Inner({ str: ri.item })
                }
              })
          }
        })
    }
  }
}

@ReusableV2
@ComponentV2
struct Inner {
  @Param str: string = '';
  build() { Text(this.str) }
}

@ObservedV2
class DataSrc {
  @Trace dataScr1: string[] = [];
}
```

---

## 多种条目类型使用场景

### 有限变化型

```typescript
@Entry
@ComponentV2
struct Index {
  private data: number[] = [];

  aboutToAppear() {
    for (let i = 0; i < 1000; i++) {
      this.data.push(i);
    }
  }

  build() {
    Column() {
      List({ space: 10 }) {
        Repeat(this.data)
          .virtualScroll()
          .each((ri) => {
            ListItem() {
              if (ri.item % 2 === 0) {
                ReusableV2Component({ item: ri.item }).reuse({ reuseId: () => 'One' })
              } else {
                ReusableV2Component({ item: ri.item }).reuse({ reuseId: () => 'Two' })
              }
            }
          })
      }
    }
  }
}

@ReusableV2
@ComponentV2
struct ReusableV2Component {
  @Param item: number = 0;

  build() {
    Column() {
      if (this.item % 2 === 0) {
        Text(`Item ${this.item} One`).fontSize(20)
      } else {
        Text(`Item ${this.item} Two`).fontSize(20)
      }
    }
  }
}
```

### 组合型

```typescript
@Entry
@ComponentV2
struct MyComponentV2 {
  private data: string[] = [];

  aboutToAppear() {
    for (let i = 0; i < 1000; i++) {
      this.data.push(i.toString());
    }
  }

  build() {
    List({ space: 40 }) {
      Repeat(this.data)
        .virtualScroll()
        .each((ri) => {
          ListItem() {
            if (ri.index % 3 === 0) {
              this.itemBuilderOne(ri.item)
            } else if (ri.index % 5 === 0) {
              this.itemBuilderTwo(ri.item)
            } else {
              this.itemBuilderThree(ri.item)
            }
          }
        })
    }
  }

  @Builder
  itemBuilderOne(item: string) {
    Column() {
      ChildComponentA({ item: item })
      ChildComponentB({ item: item })
    }
  }
}

@ReusableV2
@ComponentV2
struct ChildComponentA {
  @Param item: string = '';
  build() {
    Column() {
      Text(`Item ${this.item} Child A`).fontColor(Color.Blue)
    }
  }
}

@ReusableV2
@ComponentV2
struct ChildComponentB {
  @Param item: string = '';
  build() {
    Row() {
      Text(`Item ${this.item} Child B`).fontColor(Color.Red)
    }
  }
}
```