# V1到V2迁移测试用例集合

本文档包含所有V1场景需要迁移到V2的测试用例，每个用例包含V1代码输入和期望的V2实现。

---

## 一、组件内状态变量迁移

### 1.1 @State -> @Local 迁移

#### 用例1：简单类型@State迁移@Local
**场景描述**：简单类型变量从V1的@State迁移到V2的@Local

**V1代码**：
```typescript
const INITIAL_VALUE = 10;

@Entry
@Component
struct Child {
  @State val: number = INITIAL_VALUE;

  build() {
    Text(this.val.toString())
  }
}
```

**期望V2实现**：
```typescript
const INITIAL_VALUE = 10;

@Entry
@ComponentV2
struct Child {
  @Local val: number = INITIAL_VALUE;

  build() {
    Text(this.val.toString())
  }
}
```

---

#### 用例2：复杂类型@State迁移@Local配合@ObservedV2/@Trace
**场景描述**：V1的@State可以观察复杂对象的第一层属性变化，V2的@Local需要配合@ObservedV2和@Trace

**V1代码**：
```typescript
const INITIAL_VALUE = 10;

class Child {
  public value: number = INITIAL_VALUE;
}

@Component
@Entry
struct Example {
  @State child: Child = new Child();

  build() {
    Column() {
      Text(this.child.value.toString())
      Button('value+1')
        .onClick(() => {
          this.child.value++;
        })
    }
  }
}
```

**期望V2实现**：
```typescript
const INITIAL_VALUE = 10;

@ObservedV2
class Child {
  @Trace public value: number = INITIAL_VALUE;
}

@ComponentV2
@Entry
struct Example {
  @Local child: Child = new Child();

  build() {
    Column() {
      Text(this.child.value.toString())
      Button('value+1')
        .onClick(() => {
          this.child.value++;
        })
    }
  }
}
```

---

#### 用例3：@State外部初始化迁移@Param/@Once
**场景描述**：V1的@State变量可以从外部初始化，V2的@Local禁止外部初始化，需用@Param和@Once

**V1代码**：
```typescript
@Component
struct Child {
  @State value: number = 0;

  build() {
    Text(this.value.toString())
  }
}

@Entry
@Component
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

**期望V2实现**：
```typescript
@ComponentV2
struct Child {
  @Param @Once value: number = 0;

  build() {
    Text(this.value.toString())
  }
}

@Entry
@ComponentV2
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

---

### 1.2 @Link -> @Param/@Event 迁移

#### 用例4：@Link双向同步迁移@Param/@Event
**场景描述**：V1的@Link实现双向同步，V2使用@Param搭配@Event回调实现

**V1代码**：
```typescript
const INITIAL_MYVAL = 10;

@Component
struct Child {
  @Link val: number;

  build() {
    Column() {
      Text('child: ' + this.val.toString())
      Button('+1')
        .onClick(() => {
          this.val++;
        })
    }
  }
}

@Entry
@Component
struct Parent {
  @State myVal: number = INITIAL_MYVAL;

  build() {
    Column() {
      Text('parent: ' + this.myVal.toString())
      Child({ val: this.myVal })
    }
  }
}
```

**期望V2实现**：
```typescript
const INITIAL_MYVAL = 10;

@ComponentV2
struct Child {
  @Param val: number = 0;
  @Event addOne: () => void;

  build() {
    Column() {
      Text('child: ' + this.val.toString())
      Button('+1')
        .onClick(() => {
          this.addOne();
        })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local myVal: number = INITIAL_MYVAL;

  build() {
    Column() {
      Text('parent: ' + this.myVal.toString())
      Child({ val: this.myVal, addOne: () => this.myVal++ })
    }
  }
}
```

---

### 1.3 @Prop -> @Param 迁移

#### 用例5：简单类型@Prop迁移@Param
**场景描述**：简单类型参数从V1的@Prop迁移到V2的@Param

**V1代码**：
```typescript
@Component
struct Child {
  @Prop value: number;

  build() {
    Text(this.value.toString())
  }
}

@Entry
@Component
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

**期望V2实现**：
```typescript
@ComponentV2
struct Child {
  @Param value: number = 0;

  build() {
    Text(this.value.toString())
  }
}

@Entry
@ComponentV2
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

---

#### 用例6：复杂类型@Prop迁移@Param（深拷贝）
**场景描述**：复杂类型传递时需要深拷贝以实现单向数据绑定

**V1代码**：
```typescript
const APPLE_INITIAL_COUNT = 5;
const ORANGE_INITIAL_COUNT = 10;

class Fruit {
  public apple: number = APPLE_INITIAL_COUNT;
  public orange: number = ORANGE_INITIAL_COUNT;
}

@Component
struct Child {
  @Prop fruit: Fruit;

  build() {
    Column() {
      Text('child apple: ' + this.fruit.apple.toString())
      Text('child orange: ' + this.fruit.orange.toString())
      Button('apple+1')
        .onClick(() => {
          this.fruit.apple++;
        })
      Button('orange+1')
        .onClick(() => {
          this.fruit.orange++;
        })
    }
  }
}

@Entry
@Component
struct Parent {
  @State parentFruit: Fruit = new Fruit();

  build() {
    Column() {
      Text('parent apple: ' + this.parentFruit.apple.toString())
      Text('parent orange: ' + this.parentFruit.orange.toString())
      Child({ fruit: this.parentFruit })
    }
  }
}
```

**期望V2实现**：
```typescript
const APPLE_INITIAL_COUNT = 5;
const ORANGE_INITIAL_COUNT = 10;

@ObservedV2
class Fruit {
  @Trace public apple: number = APPLE_INITIAL_COUNT;
  @Trace public orange: number = ORANGE_INITIAL_COUNT;

  clone(): Fruit {
    let newFruit: Fruit = new Fruit();
    newFruit.apple = this.apple;
    newFruit.orange = this.orange;
    return newFruit;
  }
}

@ComponentV2
struct Child {
  @Param fruit: Fruit = new Fruit();

  build() {
    Column() {
      Text('child')
      Text(this.fruit.apple.toString())
      Text(this.fruit.orange.toString())
      Button('apple+1')
        .onClick(() => {
          this.fruit.apple++;
        })
      Button('orange+1')
        .onClick(() => {
          this.fruit.orange++;
        })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local parentFruit: Fruit = new Fruit();

  build() {
    Column() {
      Text('parent')
      Text(this.parentFruit.apple.toString())
      Text(this.parentFruit.orange.toString())
      Child({ fruit: this.parentFruit.clone() })
    }
  }
}
```

---

#### 用例7：@Prop子组件修改变量迁移@Param/@Once
**场景描述**：V1中子组件可以修改@Prop变量，V2中使用@Param/@Once允许本地修改 （todo:存疑）

**V1代码**：
```typescript
@Component
struct Child {
  @Prop value: number;

  build() {
    Column() {
      Text(this.value.toString())
      Button('+1')
        .onClick(() => {
          this.value++;
        })
    }
  }
}

@Entry
@Component
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

**期望V2实现**：
```typescript
@ComponentV2
struct Child {
  @Param @Once value: number = 0;

  build() {
    Column() {
      Text(this.value.toString())
      Button('+1')
        .onClick(() => {
          this.value++;
        })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  build() {
    Column() {
      Child({ value: 30 })
    }
  }
}
```

---

#### 用例8：@Prop本地可写+父组件更新迁移@Monitor
**场景描述**：子组件本地可写，且父组件更新仍能通知子组件

**V1代码**：
```typescript
const PARENT_INITIAL_STATE_VALUE = 10;

@Component
struct Child {
  @Prop localValue: number = 0;

  build() {
    Column() {
      Text(`${this.localValue}`).fontSize(25)
      Button('Child +100')
        .onClick(() => {
          this.localValue += 100;
        })
    }
  }
}

@Entry
@Component
struct Parent {
  @State value: number = PARENT_INITIAL_STATE_VALUE;

  build() {
    Column() {
      Button('Parent +1')
        .onClick(() => {
          this.value += 1;
        })
      Child({ localValue: this.value })
    }
  }
}
```

**期望V2实现**：
```typescript
const PARENT_INITIAL_LOCAL_VALUE = 10;

@ComponentV2
struct Child {
  @Local localValue: number = 0;
  @Param value: number = 0;

  @Monitor('value')
  onValueChange(mon: IMonitor) {
    this.localValue = this.value;
  }

  build() {
    Column() {
      Text(`${this.localValue}`).fontSize(25)
      Button('Child +100')
        .onClick(() => {
          this.localValue += 100;
        })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local value: number = PARENT_INITIAL_LOCAL_VALUE;

  build() {
    Column() {
      Button('Parent +1')
        .onClick(() => {
          this.value += 1;
        })
      Child({ value: this.value })
    }
  }
}
```

---

### 1.4 @Provide/@Consume -> @Provider/@Consumer 迁移

#### 用例9：@Provide/@Consume alias匹配迁移@Provider/@Consumer
**场景描述**：V1中alias和属性名都可匹配，V2中alias是唯一匹配key

**V1代码**：
```typescript
@Component
struct Child {
  @Consume('text') childMessage: string;
  @Consume message: string;

  build() {
    Column() {
      Text(this.childMessage)
      Text(this.message)
    }
  }
}

@Entry
@Component
struct Parent {
  @Provide('text') message: string = 'Hello World';

  build() {
    Column() {
      Child()
    }
  }
}
```

**期望V2实现**：
```typescript
@ComponentV2
struct Child {
  @Consumer('text') childMessage: string = 'default';
  @Consumer() message: string = 'default';

  build() {
    Column() {
      Text(this.childMessage)
      Text(this.message)
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Provider('text') message: string = 'Hello World';

  build() {
    Column() {
      Child()
    }
  }
}
```

---

#### 用例10：@Consume本地初始化迁移@Consumer
**场景描述**：V1的@Consume禁止本地初始化（API version 20之前），V2的@Consumer支持本地初始化

**V1代码**：
```typescript
@Component
struct Child {
  @Consume message: string;

  build() {
    Text(this.message)
  }
}

@Entry
@Component
struct Parent {
  @Provide message: string = 'Hello World';

  build() {
    Column() {
      Child()
    }
  }
}
```

**期望V2实现**：
```typescript
@ComponentV2
struct Child {
  @Consumer() message: string = 'Hello World';

  build() {
    Text(this.message)
  }
}

@Entry
@ComponentV2
struct Parent {
  build() {
    Column() {
      Child()
    }
  }
}
```

---

#### 用例11：@Provide从父组件初始化迁移@Param/@Once/@Provider
**场景描述**：V1的@Provide可以从父组件初始化，V2的@Provider不支持，需用@Param/@Once

**V1代码**：
```typescript
const STATE_INITIAL_PARENT_VALUE = 42;

@Entry
@Component
struct Parent {
  @State parentValue: number = STATE_INITIAL_PARENT_VALUE;

  build() {
    Column() {
      Child({ childValue: this.parentValue })
    }
  }
}

@Component
struct Child {
  @Provide childValue: number = 0;

  build() {
    Column() {
      Text(this.childValue.toString())
    }
  }
}
```

**期望V2实现**：
```typescript
const LOCAL_INITIAL_PARENT_VALUE = 42;

@Entry
@ComponentV2
struct Parent {
  @Local parentValue: number = LOCAL_INITIAL_PARENT_VALUE;

  build() {
    Column() {
      Child({ initialValue: this.parentValue })
    }
  }
}

@ComponentV2
struct Child {
  @Param @Once initialValue: number = 0;
  @Provider() childValue: number = this.initialValue;

  build() {
    Column() {
      Text(this.childValue.toString())
    }
  }
}
```

---

#### 用例12：@Provide重载迁移@Provider
**场景描述**：V1的@Provide默认不支持重载需设置allowOverride，V2的@Provider默认支持（todo:存疑）

**V1代码**：

```typescript
const GRANDPARENT_REVIEW_VOTES_INITIAL = 40;
const PARENT_REVIEW_VOTES_INITIAL = 20;

@Entry
@Component
struct GrandParent {
  @Provide('reviewVotes') reviewVotes: number = GRANDPARENT_REVIEW_VOTES_INITIAL;

  build() {
    Column() {
      Parent()
    }
  }
}

@Component
struct Parent {
  @Provide({ allowOverride: 'reviewVotes' }) reviewVotes: number = PARENT_REVIEW_VOTES_INITIAL;

  build() {
    Child()
  }
}

@Component
struct Child {
  @Consume('reviewVotes') reviewVotes: number;

  build() {
    Text(this.reviewVotes.toString())
  }
}
```

**期望V2实现**：
```typescript
const GRANDPARENT_REVIEW_VOTES_INITIAL = 40;
const PARENT_REVIEW_VOTES_INITIAL = 20;

@Entry
@ComponentV2
struct GrandParent {
  @Provider('reviewVotes') reviewVotes: number = GRANDPARENT_REVIEW_VOTES_INITIAL;

  build() {
    Column() {
      Parent()
    }
  }
}

@ComponentV2
struct Parent {
  @Provider() reviewVotes: number = PARENT_REVIEW_VOTES_INITIAL;

  build() {
    Child()
  }
}

@ComponentV2
struct Child {
  @Consumer() reviewVotes: number = 0;

  build() {
    Text(this.reviewVotes.toString())
  }
}
```

---

### 1.5 @Watch -> @Monitor 迁移

#### 用例13：单变量@Watch迁移@Monitor
**场景描述**：简单场景下@Watch直接替换为@Monitor

**V1代码**：
```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = '[Sample_StateMigration_App]';

@Entry
@Component
struct WatchExample {
  @State @Watch('onAppleChange') apple: number = 0;

  onAppleChange(): void {
    hilog.info(DOMAIN, TAG, 'apple count changed to ' + this.apple);
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Button('add apple')
        .onClick(() => {
          this.apple++;
        })
    }
  }
}
```

**期望V2实现**：
```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = '[Sample_StateMigration_App]';

@Entry
@ComponentV2
struct MonitorExample {
  @Local apple: number = 0;

  @Monitor('apple')
  onFruitChange(monitor: IMonitor) {
    hilog.info(DOMAIN, TAG, `apple changed from ${monitor.value()?.before} to ${monitor.value()?.now}`);
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Button('add apple')
        .onClick(() => {
          this.apple++;
        })
    }
  }
}
```

---

#### 用例14：多变量@Watch迁移@Monitor
**场景描述**：V1需要多个@Watch，V2可用一个@Monitor监听多个变量并获取变化前后值

**V1代码**：
```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = '[Sample_StateMigration_App]';

@Entry
@Component
struct WatchExample {
  @State @Watch('onAppleChange') apple: number = 0;
  @State @Watch('onOrangeChange') orange: number = 0;

  onAppleChange(): void {
    hilog.info(DOMAIN, TAG, 'apple count changed to ' + this.apple);
  }

  onOrangeChange(): void {
    hilog.info(DOMAIN, TAG, 'orange count changed to ' + this.orange);
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Text(`orange count: ${this.orange}`)
      Button('add apple')
        .onClick(() => {
          this.apple++;
        })
      Button('add orange')
        .onClick(() => {
          this.orange++;
        })
    }
  }
}
```

**期望V2实现**：
```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = '[Sample_StateMigration_App]';

@Entry
@ComponentV2
struct MonitorExample {
  @Local apple: number = 0;
  @Local orange: number = 0;

  @Monitor('apple','orange')
  onFruitChange(monitor: IMonitor) {
    monitor.dirty.forEach((name: string) => {
      hilog.info(DOMAIN, TAG, `${name} changed from ${monitor.value(name)?.before} to ${monitor.value(name)?.now}`);
    });
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Text(`orange count: ${this.orange}`)
      Button('add apple')
        .onClick(() => {
          this.apple++;
        })
      Button('add orange')
        .onClick(() => {
          this.orange++;
        })
    }
  }
}
```

---

### 1.6 重复计算 -> @Computed 迁移

#### 用例15：重复计算迁移@Computed计算属性
**场景描述**：V1无计算属性能力需重复计算，V2使用@Computed避免重复计算

**V1代码**：
```typescript
@Entry
@Component
struct Index {
  @State firstName: string = 'Li';
  @State lastName: string = 'Hua';

  build() {
    Column() {
      Text(this.lastName + ' ' + this.firstName)
      Text(this.lastName + ' ' + this.firstName)
      Button('changed lastName').onClick(() => {
        this.lastName += 'a';
      })
    }
  }
}
```

**期望V2实现**：
```typescript
@Entry
@ComponentV2
struct Index {
  @Local firstName: string = 'Li';
  @Local lastName: string = 'Hua';

  @Computed
  get fullName() {
    return this.firstName + ' ' + this.lastName;
  }

  build() {
    Column() {
      Text(this.fullName)
      Text(this.fullName)
      Button('changed lastName').onClick(() => {
        this.lastName += 'a';
      })
    }
  }
}
```

---

### 1.7 $$ -> !! 迁移

#### 用例16：双向绑定$$迁移!!
**场景描述**：V1使用$$实现系统组件双向绑定，V2使用!!语法

**V1代码**：
```typescript
@Entry
@Component
struct TextInputExample {
  @State text: string = '';
  controller: TextInputController = new TextInputController();

  build() {
    Column({ space: 20 }) {
      Text(this.text)
      TextInput({ text: $$this.text, placeholder: 'input your word...', controller: this.controller })
        .placeholderColor(Color.Grey)
        .placeholderFont({ size: 14, weight: 400 })
        .caretColor(Color.Blue)
        .width(300)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

**期望V2实现**：
```typescript
@Entry
@ComponentV2
struct TextInputExampleV2 {
  @Local text: string = '';
  controller: TextInputController = new TextInputController();

  build() {
    Column({ space: 20 }) {
      Text(this.text)
      TextInput({ text: this.text!!, placeholder: 'input your word...', controller: this.controller })
        .placeholderColor(Color.Grey)
        .placeholderFont({ size: 14, weight: 400 })
        .caretColor(Color.Blue)
        .width(300)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

---

## 二、数据对象状态变量迁移

### 2.1 @ObjectLink/@Observed/@Track -> @ObservedV2/@Trace 迁移

#### 用例17：嵌套对象属性观察迁移
**场景描述**：V1需要通过自定义组件和@ObjectLink观察嵌套属性，V2可直接使用@ObservedV2/@Trace

**V1代码**：
```typescript
@Observed
class Address {
  public city: string;

  constructor(city: string) {
    this.city = city;
  }
}

@Observed
class User {
  public name: string;
  public address: Address;

  constructor(name: string, address: Address) {
    this.name = name;
    this.address = address;
  }
}

@Component
struct AddressView {
  @ObjectLink address: Address;

  build() {
    Column() {
      Text(`City: ${this.address.city}`)
      Button('city +a')
        .onClick(() => {
          this.address.city += 'a';
        })
    }
  }
}

@Entry
@Component
struct UserProfile {
  @State user: User = new User('Alice', new Address('New York'));

  build() {
    Column() {
      Text(`Name: ${this.user.name}`)
      AddressView({ address: this.user.address })
    }
  }
}
```

**期望V2实现**：
```typescript
@ObservedV2
class Address {
  @Trace public city: string;

  constructor(city: string) {
    this.city = city;
  }
}

@ObservedV2
class User {
  @Trace public name: string;
  @Trace public address: Address;

  constructor(name: string, address: Address) {
    this.name = name;
    this.address = address;
  }
}

@Entry
@ComponentV2
struct UserProfile {
  @Local user: User = new User('Alice', new Address('New York'));

  build() {
    Column() {
      Text(`Name: ${this.user.name}`)
      Text(`City: ${this.user.address.city}`)
      Button('city +a')
        .onClick(() => {
          this.user.address.city += 'a';
        })
    }
  }
}
```

---

#### 用例18：类属性精确更新迁移
**场景描述**：V1的@Track用V2的@Trace取代，实现属性级别精确更新

**V1代码**：
```typescript
@Observed
class User {
  @Track public name: string;
  @Track public age: number;

  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

@Entry
@Component
struct UserProfile {
  @State user: User = new User('Alice', 30);

  build() {
    Column() {
      Text(`Name: ${this.user.name}`)
      Text(`Age: ${this.user.age}`)
      Button('increase age')
        .onClick(() => {
          this.user.age++;
        })
    }
  }
}
```

**期望V2实现**：
```typescript
@ObservedV2
class User {
  @Trace public name: string;
  @Trace public age: number;

  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

@Entry
@ComponentV2
struct UserProfile {
  @Local user: User = new User('Alice', 30);

  build() {
    Column() {
      Text(`Name: ${this.user.name}`)
      Text(`Age: ${this.user.age}`)
      Button('Increase age')
        .onClick(() => {
          this.user.age++;
        })
    }
  }
}
```

---

## 三、内置对象迁移

### 3.1 List组件ChildrenMainSize迁移

#### 用例19：List组件ChildrenMainSize迁移makeObserved
**场景描述**：V2中使用makeObserved观测ChildrenMainSize属性变化

**V1代码**：
```typescript
@Entry
@Component
struct ListExample {
  private arr: Array<number> = new Array(10).fill(0);
  private scroller: ListScroller = new ListScroller();
  @State listSpace: number = 10;
  @State listChildrenSize: ChildrenMainSize = new ChildrenMainSize(100);

  build() {
    Column() {
      Button('change Default').onClick(() => {
        this.listChildrenSize.childDefaultSize += 10;
      })

      Button('splice 5').onClick(() => {
        this.listChildrenSize.splice(0, 5, [100, 100, 100, 100, 100]);
      })

      Button('update 5').onClick(() => {
        this.listChildrenSize.update(0, 200);
      })

      List({ space: this.listSpace, scroller: this.scroller }) {
        ForEach(this.arr, (item: number) => {
          ListItem() {
            Text(`item-` + item)
          }.backgroundColor(Color.Pink)
        })
      }
      .childrenMainSize(this.listChildrenSize)
    }
  }
}
```

**期望V2实现**：
```typescript
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct ListExample {
  private arr: Array<number> = new Array(10).fill(0);
  private scroller: ListScroller = new ListScroller();
  listSpace: number = 10;
  listChildrenSize: ChildrenMainSize = UIUtils.makeObserved(new ChildrenMainSize(100));

  build() {
    Column() {
      Button('change Default').onClick(() => {
        this.listChildrenSize.childDefaultSize += 10;
      })

      Button('splice 5').onClick(() => {
        this.listChildrenSize.splice(0, 5, [100, 100, 100, 100, 100]);
      })

      Button('update 5').onClick(() => {
        this.listChildrenSize.update(0, 200);
      })

      List({ space: this.listSpace, scroller: this.scroller }) {
        ForEach(this.arr, (item: number) => {
          ListItem() {
            Text(`item-` + item)
          }.backgroundColor(Color.Pink)
        })
      }
      .childrenMainSize(this.listChildrenSize)
    }
  }
}
```

---

### 3.2 WaterFlow组件WaterFlowSections迁移

#### 用例20：WaterFlow组件WaterFlowSections迁移makeObserved
**场景描述**：V2中使用makeObserved观测WaterFlowSections属性变化

**V1代码**：
```typescript
@Entry
@Component
struct WaterFlowSample {
  @State colors: Color[] = [Color.Red, Color.Orange, Color.Yellow, Color.Green, Color.Blue, Color.Pink];
  @State sections: WaterFlowSections = new WaterFlowSections();
  scroller: Scroller = new Scroller();
  @State private arr: Array<number> = new Array(9).fill(0);
  oneColumnSection: SectionOptions = {
    itemsCount: 4,
    crossCount: 1,
    columnsGap: '5vp',
    rowsGap: 10,
  };
  twoColumnSection: SectionOptions = {
    itemsCount: 2,
    crossCount: 2,
  };
  lastSection: SectionOptions = {
    itemsCount: 3,
    crossCount: 3,
  };

  aboutToAppear(): void {
    let sectionOptions: SectionOptions[] = [this.oneColumnSection, this.twoColumnSection, this.lastSection];
    this.sections.splice(0, 0, sectionOptions);
  }

  build() {
    Column() {
      Text(`${this.arr.length}`)

      Button('push option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 1,
          crossCount: 1,
        };
        this.sections.push(section);
        this.arr.push(100);
      })

      Button('splice option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 8,
          crossCount: 2,
        };
        this.sections.splice(0, this.arr.length, [section]);
        this.arr = new Array(8).fill(10);
      })

      Button('update option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 8,
          crossCount: 2,
        };
        this.sections.update(1, section);
        this.arr = new Array(16).fill(1);
      })

      WaterFlow({ scroller: this.scroller, sections: this.sections }) {
        ForEach(this.arr, (item: number) => {
          FlowItem() {
            Text(`${item}`)
              .border({ width: 1 })
              .backgroundColor(this.colors[item % 6])
              .height(30)
              .width(50)
          }
        })
      }
    }
  }
}
```

**期望V2实现**：
```typescript
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct WaterFlowSample {
  colors: Color[] = [Color.Red, Color.Orange, Color.Yellow, Color.Green, Color.Blue, Color.Pink];
  sections: WaterFlowSections = UIUtils.makeObserved(new WaterFlowSections());
  scroller: Scroller = new Scroller();
  @Local private arr: Array<number> = new Array(9).fill(0);
  oneColumnSection: SectionOptions = {
    itemsCount: 4,
    crossCount: 1,
    columnsGap: '5vp',
    rowsGap: 10,
  };
  twoColumnSection: SectionOptions = {
    itemsCount: 2,
    crossCount: 2,
  };
  lastSection: SectionOptions = {
    itemsCount: 3,
    crossCount: 3,
  };

  aboutToAppear(): void {
    let sectionOptions: SectionOptions[] = [this.oneColumnSection, this.twoColumnSection, this.lastSection];
    this.sections.splice(0, 0, sectionOptions);
  }

  build() {
    Column() {
      Text(`${this.arr.length}`)

      Button('push option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 1,
          crossCount: 1,
        };
        this.sections.push(section);
        this.arr.push(100);
      })

      Button('splice option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 8,
          crossCount: 2,
        };
        this.sections.splice(0, this.arr.length, [section]);
        this.arr = new Array(8).fill(10);
      })

      Button('update option').onClick(() => {
        let section: SectionOptions = {
          itemsCount: 8,
          crossCount: 2,
        };
        this.sections.update(1, section);
        this.arr = new Array(16).fill(1);
      })

      WaterFlow({ scroller: this.scroller, sections: this.sections }) {
        ForEach(this.arr, (item: number) => {
          FlowItem() {
            Text(`${item}`)
              .border({ width: 1 })
              .backgroundColor(this.colors[item % 6])
              .height(30)
              .width(50)
          }
        })
      }
    }
  }
}
```

---

### 3.3 attributeModifier迁移

#### 用例21：attributeModifier迁移makeObserved
**场景描述**：V2中使用makeObserved观测attributeModifier属性变化

**V1代码**：
```typescript
class MyButtonModifier implements AttributeModifier<ButtonAttribute> {
  public isDark: boolean = false;

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (this.isDark) {
      instance.backgroundColor(Color.Black);
    } else {
      instance.backgroundColor(Color.Red);
    }
  }
}

@Entry
@Component
struct AttributeDemo {
  @State modifier: MyButtonModifier = new MyButtonModifier();

  build() {
    Row() {
      Column() {
        Button('Button')
          .attributeModifier(this.modifier)
          .onClick(() => {
            this.modifier.isDark = !this.modifier.isDark;
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
```

**期望V2实现**：
```typescript
import { UIUtils } from '@kit.ArkUI';

class MyButtonModifier implements AttributeModifier<ButtonAttribute> {
  public isDark: boolean = false;

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (this.isDark) {
      instance.backgroundColor(Color.Black);
    } else {
      instance.backgroundColor(Color.Red);
    }
  }
}

@Entry
@ComponentV2
struct AttributeDemo {
  modifier: MyButtonModifier = UIUtils.makeObserved(new MyButtonModifier());

  build() {
    Row() {
      Column() {
        Button('Button')
          .attributeModifier(this.modifier)
          .onClick(() => {
            this.modifier.isDark = !this.modifier.isDark;
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
```

---

### 3.4 AttributeUpdater迁移

#### 用例22：AttributeUpdater迁移@ObservedV2/@Trace
**场景描述**：AttributeUpdater场景需要@ObservedV2/@Trace并建立关联

**V1代码**：
```typescript
import { AttributeUpdater } from '@kit.ArkUI';

class MyButtonModifier extends AttributeUpdater<ButtonAttribute> {
  public flag: boolean = false;

  initializeModifier(instance: ButtonAttribute): void {
    instance.backgroundColor('#ff2787d9')
      .width('50%')
      .height(30)
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (this.flag) {
      instance.borderWidth(2);
    } else {
      instance.borderWidth(10);
    }
  }
}

@Entry
@Component
struct Index {
  @State modifier: MyButtonModifier = new MyButtonModifier();

  build() {
    Row() {
      Column() {
        Button('Button')
          .attributeModifier(this.modifier)
        Button('Update')
          .onClick(() => {
            this.modifier.flag = !this.modifier.flag;
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
```

**期望V2实现**：
```typescript
import { AttributeUpdater } from '@kit.ArkUI';

@ObservedV2
class MyButtonModifier extends AttributeUpdater<ButtonAttribute> {
  @Trace public flag: boolean = false;

  initializeModifier(instance: ButtonAttribute): void {
    this.flag;
    instance.backgroundColor('#ff2787d9')
      .width('50%')
      .height(30)
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (this.flag) {
      instance.borderWidth(2);
    } else {
      instance.borderWidth(10);
    }
  }
}

@Entry
@ComponentV2
struct Index {
  @Local modifier: MyButtonModifier = new MyButtonModifier();

  build() {
    Row() {
      Column() {
        Button('Button')
          .attributeModifier(this.modifier)
        Button('Update')
          .onClick(() => {
            this.modifier.flag = !this.modifier.flag;
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
```

---

## 四、应用内状态变量迁移

### 4.1 LocalStorage -> @ObservedV2/@Trace 迁移

#### 用例23：LocalStorage页面间共享迁移@ObservedV2/@Trace
**场景描述**：使用@ObservedV2/@Trace创建可观测实例替代LocalStorage

**V1代码**：
```typescript
// EntryAbility.ets
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  public para: Record<string, number> = { 'count': 47 };
  public storage: LocalStorage = new LocalStorage(this.para);

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Page1', this.storage);
  }
}
```

```typescript
// Page1.ets
@Entry({ useSharedStorage: true })
@Component
struct Page1 {
  @LocalStorageLink('count') count: number = 0;
  pageStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pageStack) {
      Column() {
        Text(`${this.count}`)
          .fontSize(50)
          .onClick(() => {
            this.count++;
          })
        Button('push to Page2')
          .onClick(() => {
            this.pageStack.pushPathByName('Page2', null);
          })
      }
    }
  }
}
```

**期望V2实现**：
```typescript
// storage.ets
@ObservedV2
export class MyStorage {
  public static singleton_: MyStorage;

  static instance() {
    if (!MyStorage.singleton_) {
      MyStorage.singleton_ = new MyStorage();
    }
    return MyStorage.singleton_;
  }
  @Trace public count: number = 47;
}
```

```typescript
// Page1.ets
import { MyStorage } from './storage';

@Entry
@ComponentV2
struct Page1 {
  storage: MyStorage = MyStorage.instance();
  pageStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pageStack) {
      Column() {
        Text(`${this.storage.count}`)
          .fontSize(50)
          .onClick(() => {
            this.storage.count++;
          })
        Button('push to Page2')
          .onClick(() => {
            this.pageStack.pushPathByName('Page2', null);
          })
      }
    }
  }
}
```

---

### 4.2 AppStorage -> AppStorageV2 迁移

#### 用例24：AppStorage跨Ability共享迁移AppStorageV2
**场景描述**：使用AppStorageV2实现跨Ability数据共享

**V1代码**：
```typescript
// EntryAbility Index.ets
import { common, Want } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @StorageLink('count') count: number = 0;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  build() {
    Column() {
      Text(`EntryAbility count: ${this.count}`)
        .fontSize(50)
        .onClick(() => {
          this.count++;
        })
      Button('Jump to EntryAbility1').onClick(() => {
        let wantInfo: Want = {
          bundleName: 'com.example.myapplication',
          abilityName: 'EntryAbility1'
        };
        this.context.startAbility(wantInfo);
      })
    }
  }
}
```

**期望V2实现**：
```typescript
import { common, Want } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class MyStorage {
  @Trace public count: number = 0;
}

@Entry
@ComponentV2
struct Index {
  @Local storage: MyStorage = AppStorageV2.connect(MyStorage, 'storage', () => new MyStorage())!;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  build() {
    Column() {
      Text(`EntryAbility1 count: ${this.storage.count}`)
        .fontSize(50)
        .onClick(() => {
          this.storage.count++;
        })
      Button('Jump to EntryAbility1').onClick(() => {
        let wantInfo: Want = {
          bundleName: 'com.example.myapplication',
          abilityName: 'EntryAbility1'
        };
        this.context.startAbility(wantInfo);
      })
    }
  }
}
```

---

### 4.3 Environment -> Ability接口迁移

#### 用例25：Environment迁移直接调用Ability接口
**场景描述**：直接通过UIAbilityContext的config属性获取系统环境变量

**V1代码**：
```typescript
Environment.envProp('languageCode', 'en');

@Entry
@Component
struct Index {
  @StorageProp('languageCode') languageCode: string = 'en';

  build() {
    Row() {
      Column() {
        Text(this.languageCode)
      }
    }
  }
}
```

**期望V2实现**：
```typescript
// Env.ets
import { ConfigurationConstant } from '@kit.AbilityKit';

export class Env {
  public language: string | undefined;
  public colorMode: ConfigurationConstant.ColorMode | undefined;
  public fontSizeScale: number | undefined;
  public fontWeightScale: number | undefined;
}

export let env: Env = new Env();
```

```typescript
// EntryAbility.ets
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { env } from '../pages/Env';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    env.language = this.context.config.language;
    env.colorMode = this.context.config.colorMode;
    env.fontSizeScale = this.context.config.fontSizeScale;
    env.fontWeightScale = this.context.config.fontWeightScale;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }
}
```

```typescript
// Index.ets
import { env } from '../pages/Env';

@Entry
@ComponentV2
struct Index {
  build() {
    Row() {
      Column() {
        Text(`languageCode: ${env.language}`).fontSize(20)
        Text(`colorMode: ${env.colorMode}`).fontSize(20)
        Text(`fontSizeScale: ${env.fontSizeScale}`).fontSize(20)
        Text(`fontWeightScale: ${env.fontWeightScale}`).fontSize(20)
      }
    }
  }
}
```

---

### 4.4 PersistentStorage -> PersistenceV2 迁移

#### 用例26：PersistentStorage迁移PersistenceV2
**场景描述**：使用PersistenceV2替代PersistentStorage实现数据持久化

**V1代码**：
```typescript
class Data {
  public name: string = 'ZhangSan';
  public id: number = 0;
}

PersistentStorage.persistProp('numProp', 47);
PersistentStorage.persistProp('dataProp', new Data());

@Entry
@Component
struct Index {
  @StorageLink('numProp') numProp: number = 48;
  @StorageLink('dataProp') dataProp: Data = new Data();

  build() {
    Column() {
      Text(`numProp: ${this.numProp}`)
        .onClick(() => {
          this.numProp += 1;
        })
        .fontSize(30)

      Text(`dataProp.name: ${this.dataProp.name}`)
        .onClick(() => {
          this.dataProp.name += 'a';
        })
        .fontSize(30)
      Text(`dataProp.id: ${this.dataProp.id}`)
        .onClick(() => {
          this.dataProp.id += 1;
        })
        .fontSize(30)
    }
    .width('100%')
  }
}
```

**期望V2实现**：
```typescript
import { PersistenceV2, Type } from '@kit.ArkUI';

@ObservedV2
class V2Data {
  @Trace public name: string = '';
  @Trace public id: number = 1;
}

@ObservedV2
export class Sample {
  @Type(V2Data)
  @Trace public num: number = 1;
  @Trace public V2: V2Data = new V2Data();
}

@Entry
@ComponentV2
struct Page1 {
  @Local p: Sample =
    PersistenceV2.globalConnect({ type: Sample, key: 'connect2', defaultCreator: () => new Sample() })!;

  build() {
    Column({ space: 5 }) {
      Text(`numProp: ${this.p.num}`)
        .onClick(() => {
          this.p.num += 1;
        })
        .fontSize(30)

      Text(`dataProp.name: ${this.p.V2.name}`)
        .onClick(() => {
          this.p.V2.name += 'a';
        })
        .fontSize(30)
      Text(`dataProp.id: ${this.p.V2.id}`)
        .onClick(() => {
          this.p.V2.id += 1;
        })
        .fontSize(30)
    }
    .width('100%')
  }
}
```

---

## 五、组件复用迁移

### 5.1 @Reusable -> @ReusableV2 迁移

#### 用例27：@Reusable迁移@ReusableV2基本场景
**场景描述**：组件复用从@Reusable迁移到@ReusableV2

**V1代码**：
```typescript
@Reusable
@Component
struct ReusableComponent {
  @State val: string = 'Hello World';
  aboutToRecycle(): void {
    console.info('ReusableComponent aboutToRecycle called');
  }
  aboutToReuse(params: ESObject): void {
    console.info('ReusableComponent aboutToReuse called');
    this.val = params.val ?? 'Hello World';
  }
  build() {
    Column() {
      Text(`val: ${this.val}`)
    }
  }
}
```

**期望V2实现**：
```typescript
@ReusableV2
@ComponentV2
struct ReusableV2Component {
  @Local val: string = 'Hello World';
  @Require @Param @Once param: string;
  aboutToRecycle(): void {
    console.info('ReusableComponent aboutToRecycle called');
  }
  aboutToReuse(): void {
    console.info('ReusableComponent aboutToReuse called');
    this.val = 'Hello ArkUI';
    this.param = 'Hello ArkUI';
  }
  build() {
    Column() {
      Text(`val: ${this.val}`)
      Text(`param: ${this.param}`)
    }
  }
}
```

---

#### 用例28：reuseId迁移reuse
**场景描述**：组件复用ID从reuseId迁移到reuse属性

**V1代码**：
```typescript
ReusableComponent().reuseId('groupA')
```

**期望V2实现**：
```typescript
ReusableV2Component().reuse({reuseId: () => 'groupA'})
```

---

## 六、循环渲染迁移

### 6.1 ForEach -> Repeat 迁移

#### 用例29：ForEach迁移Repeat基本场景
**场景描述**：ForEach循环渲染迁移到Repeat

**V1代码**：
```typescript
@Observed
class ArticleChangeChild {
  public id: string;
  public title: string;
  public brief: string;
  public isLiked: boolean;
  public likesCount: number;
}

@Entry
@Component
struct ArticleListChangeView {
  @State articleList: Array<ArticleChangeChild> = [...];

  build() {
    List() {
      ForEach(this.articleList, (item: ArticleChangeChild) => {
        ListItem() {
          ArticleCardChangeChild({ article: item })
        }
      })
    }
  }
}
```

**期望V2实现**：
```typescript
@ObservedV2
class ArticleChangeChild {
  public id: string;
  public title: string;
  public brief: string;
  @Trace public isLiked: boolean;
  @Trace public likesCount: number;
}

@Entry
@ComponentV2
struct ArticleListChangeView {
  @Local articleList: Array<ArticleChangeChild> = [...];

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

### 6.2 LazyForEach -> Repeat 迁移

#### 用例30：LazyForEach迁移Repeat懒加载场景
**场景描述**：LazyForEach懒加载迁移到Repeat

**V1代码**：
```typescript
class MyDataSource extends BasicDataSource {
  private dataArray: string[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): string {
    return this.dataArray[index];
  }

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
        ListItem() {
          Row() {
            Text(item).fontSize(50)
          }.margin({ left: 10, right: 10 })
        }
      }, (item: string) => item)
    }.cachedCount(5)
  }
}
```

**期望V2实现**：
```typescript
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
          ListItem() {
            Row() {
              Text(repeatItem.item).fontSize(50)
            }.margin({ left: 10, right: 10 })
          }
        })
        .key((item: string) => item)
        .virtualScroll()
    }.cachedCount(5)
  }
}
```

---

#### 用例31：LazyForEach数据更新迁移Repeat
**场景描述**：LazyForEach数据更新操作迁移到Repeat

**V1代码**：
```typescript
@Entry
@Component
struct MyComponent {
  private data: MyDataSource = new MyDataSource();
  private count: number = 0;

  aboutToAppear() {
    for (let i = 0; i <= 10; i++) {
      this.data.pushData(`Hello ${i}`);
    }
  }

  build() {
    Column({ space: 3 }) {
      Button('Add new item')
        .onClick(() => {
          this.data.pushData(`New item ${this.count++}`);
        })
      Button('Delete item 0')
        .onClick(() => {
          this.data.deleteData(0);
        })
      List({ space: 3 }) {
        LazyForEach(this.data, (item: string) => {
          ListItem() {
            Row() {
              Text(item).fontSize(25)
            }
          }
        }, (item: string) => item)
      }.cachedCount(5)
    }
  }
}
```

**期望V2实现**：
```typescript
@Entry
@ComponentV2
struct MyComponent {
  @Local data: Array<string> = [];
  private count: number = 0;

  aboutToAppear() {
    for (let i = 0; i <= 10; i++) {
      this.data.push(`Hello ${i}`);
    }
  }

  build() {
    Column({ space: 3 }) {
      Button('Add new item')
        .onClick(() => { this.data.push(`New item ${this.count++}`); })
      Button('Delete item 0')
        .onClick(() => { this.data.splice(0, 1); })
      List({ space: 3 }) {
        Repeat(this.data)
          .each((repeatItem: RepeatItem<string>) => {
            ListItem() {
              Row() {
                Text(repeatItem.item).fontSize(25)
              }
            }
          })
          .key((item: string) => item)
          .virtualScroll()
      }.cachedCount(5)
    }
  }
}
```

---

#### 用例32：LazyForEach拖拽排序迁移Repeat
**场景描述**：LazyForEach拖拽排序迁移到Repeat

**V1代码**：
```typescript
@Entry
@Component
struct Parent {
  private data: MyDataSource = new MyDataSource();

  aboutToAppear(): void {
    for (let i = 0; i < 100; i++) {
      this.data.pushData(i.toString());
    }
  }

  build() {
    Row() {
      List() {
        LazyForEach(this.data, (item: string) => {
          ListItem() {
            Text(item.toString())
              .fontSize(16)
              .size({ height: 100, width: '100%' })
          }
        }, (item: string) => item)
          .onMove((from: number, to: number) => {
            this.data.moveDataWithoutNotify(from, to);
          })
      }
    }
  }
}
```

**期望V2实现**：
```typescript
@Entry
@ComponentV2
struct Parent {
  @Local data: string[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < 100; i++) {
      this.data.push(i.toString());
    }
  }

  moveData(from: number, to: number) {
    let tmp = this.data.splice(from, 1);
    this.data.splice(to, 0, tmp[0]);
  }

  build() {
    Row() {
      List() {
        Repeat(this.data)
          .each((repeatItem) => {
            ListItem() {
              Text(repeatItem.item.toString())
                .fontSize(16)
                .size({ height: 100, width: '100%' })
            }
          })
          .key((item: string) => item)
          .virtualScroll()
          .onMove((from: number, to: number) => {
            this.moveData(from, to);
          })
      }
    }
  }
}
```

---

#### 用例33：LazyForEach组件复用迁移Repeat
**场景描述**：LazyForEach配合@Reusable迁移到Repeat自身复用

**V1代码**：
```typescript
@Reusable
@Component
struct ChildComponent {
  @State data: StringData = new StringData('');

  aboutToAppear(): void {
    console.info(`aboutToAppear: ${this.data.message}`);
  }

  aboutToRecycle(): void {
    console.info(`aboutToRecycle: ${this.data.message}`);
  }

  aboutToReuse(params: Record<string, ESObject>): void {
    this.data = params.data as StringData;
    console.info(`aboutToReuse: ${this.data.message}`);
  }

  build() {
    Row() {
      Text(this.data.message).fontSize(50)
    }
  }
}
```

**期望V2实现（方案1：使用Repeat自身复用）**：
```typescript
@Entry
@ComponentV2
struct MyComponent {
  @Local data: StringData[] = [];

  aboutToAppear() {
    for (let i = 0; i <= 30; i++) {
      this.data.push(new StringData(`Hello${i}`));
    }
  }

  build() {
    List({ space: 3 }) {
      Repeat(this.data)
        .each((repeatItem) => {
          ListItem() {
            Text(repeatItem.item.message).fontSize(50)
          }
        })
        .key((item: StringData, index: number) => index.toString())
        .virtualScroll()
    }.cachedCount(5)
  }
}
```

**期望V2实现（方案2：使用@ReusableV2）**：
```typescript
@ReusableV2
@ComponentV2
struct ChildComponent {
  @Param data: StringData = new StringData('');

  aboutToAppear(): void {
    console.info(`aboutToAppear: ${this.data.message}`);
  }

  aboutToRecycle(): void {
    console.info(`aboutToRecycle: ${this.data.message}`);
  }

  aboutToReuse(): void {
    console.info(`aboutToReuse: ${this.data.message}`);
  }

  build() {
    Row() {
      Text(this.data.message).fontSize(50)
    }
  }
}
```

---

## 七、AnimateTo迁移

### 7.1 animateTo执行动画前修改状态变量

#### 用例34：animateTo迁移applySync方案（API version 22+）
**场景描述**：执行动画前存在额外状态变量修改，需使用applySync同步刷新

**V1代码**：
```typescript
@Entry
@Component
struct Index {
  @State w: number = 50;
  @State h: number = 50;
  @State message: string = 'Hello';

  build() {
    Column() {
      Button('change size')
        .margin(20)
        .onClick(() => {
          this.w = 100;
          this.h = 100;
          this.message = 'Hello World';
          this.getUIContext().animateTo({
            duration: 1000
          }, () => {
            this.w = 200;
            this.h = 200;
            this.message = 'Hello ArkUI';
          })
        })
      Column() {
        Text(`${this.message}`)
      }
      .backgroundColor('#ff17a98d')
      .width(this.w)
      .height(this.h)
    }
  }
}
```

**期望V2实现**：
```typescript
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct Index {
  @Local w: number = 50;
  @Local h: number = 50;
  @Local message: string = 'Hello';

  build() {
    Column() {
      Button('change size')
        .margin(20)
        .onClick(() => {
          UIUtils.applySync(() => {
            this.w = 100;
            this.h = 100;
            this.message = 'Hello World';
          })
          this.getUIContext().animateTo({
            duration: 1000
          }, () => {
            this.w = 200;
            this.h = 200;
            this.message = 'Hello ArkUI';
          })
        })
      Column() {
        Text(`${this.message}`)
      }
      .backgroundColor('#ff17a98d')
      .width(this.w)
      .height(this.h)
    }
  }
}
```

---

#### 用例35：animateTo迁移animateToImmediately方案（API version 22之前）
**场景描述**：使用duration为0的animateToImmediately先刷新额外修改

**期望V2实现**：
```typescript
@Entry
@ComponentV2
struct Index {
  @Local w: number = 50;
  @Local h: number = 50;
  @Local message: string = 'Hello';

  build() {
    Column() {
      Button('change size')
        .margin(20)
        .onClick(() => {
          this.w = 100;
          this.h = 100;
          this.message = 'Hello World';
          animateToImmediately({
            duration: 0
          }, () => {
          })
          this.getUIContext().animateTo({
            duration: 1000
          }, () => {
            this.w = 200;
            this.h = 200;
            this.message = 'Hello ArkUI';
          })
        })
      Column() {
        Text(`${this.message}`)
      }
      .backgroundColor('#ff17a98d')
      .width(this.w)
      .height(this.h)
    }
  }
}
```

---

## 测试用例统计

| 分类 | 用例数量 |
|------|----------|
| 组件内状态变量迁移 | 16 |
| 数据对象状态变量迁移 | 2 |
| 内置对象迁移 | 4 |
| 应用内状态变量迁移 | 4 |
| 组件复用迁移 | 2 |
| 循环渲染迁移 | 5 |
| AnimateTo迁移 | 2 |
| **总计** | **35** |