# 组件内状态变量迁移

## 目录

- [@State → @Local](#state--local)
  - [简单类型](#简单类型)
  - [复杂类型](#复杂类型)
  - [外部初始化](#外部初始化状态变量)
- [@Link → @Param/@Event](#link--paramevent)
- [@Prop → @Param](#prop--param)
  - [简单类型](#简单类型-1)
  - [复杂类型单向传递](#复杂类型的单向数据传递)
  - [子组件修改变量](#子组件修改变量)
- [@Provide/@Consume → @Provider/@Consumer](#provideconsume--providerconsumer)
  - [alias匹配规则](#alias和属性名匹配规则)
  - [本地初始化支持](#v1的consume不支持本地初始化v2支持)
  - [父组件初始化](#v1的provide可以从父组件初始化v2不支持)
  - [重载支持](#v1的provide默认不支持重载v2默认支持)
- [@Watch → @Monitor](#watch--monitor)
  - [单变量监听](#单变量监听)
  - [多变量监听](#多变量监听)
- [重复计算 → @Computed](#重复计算--computed计算属性)
- [双向绑定 $$ → !!](#双向绑定迁移)

---

## @State → @Local

### 简单类型

```typescript
// V1
@Entry
@Component
struct Child {
  @State val: number = 10;
  build() { Text(this.val.toString()) }
}

// V2
@Entry
@ComponentV2
struct Child {
  @Local val: number = 10;
  build() { Text(this.val.toString()) }
}
```

### 复杂类型

V1的`@State`可观察第一层属性，V2的`@Local`需配合`@ObservedV2`和`@Trace`：

```typescript
// V1
class Child {
  public value: number = 10;
}

@Entry
@Component
struct Example {
  @State child: Child = new Child();
  build() {
    Column() {
      Text(this.child.value.toString())
      Button('value+1').onClick(() => { this.child.value++; })
    }
  }
}

// V2
@ObservedV2
class Child {
  @Trace public value: number = 10;
}

@Entry
@ComponentV2
struct Example {
  @Local child: Child = new Child();
  build() {
    Column() {
      Text(this.child.value.toString())
      Button('value+1').onClick(() => { this.child.value++; })
    }
  }
}
```

### 外部初始化状态变量

V1的`@State`支持外部初始化，V2的`@Local`禁止，需用`@Param @Once`：

```typescript
// V1
@Component
struct Child {
  @State value: number = 0;
  build() { Text(this.value.toString()) }
}

@Entry
@Component
struct Parent {
  build() { Column() { Child({ value: 30 }) } }
}

// V2
@ComponentV2
struct Child {
  @Param @Once value: number = 0;
  build() { Text(this.value.toString()) }
}

@Entry
@ComponentV2
struct Parent {
  build() { Column() { Child({ value: 30 }) } }
}
```

---

## @Link → @Param/@Event

V2需用`@Param` + `@Event`模拟双向同步：

```typescript
// V1
@Component
struct Child {
  @Link val: number;
  build() {
    Column() {
      Text('child: ' + this.val.toString())
      Button('+1').onClick(() => { this.val++; })
    }
  }
}

@Entry
@Component
struct Parent {
  @State myVal: number = 10;
  build() {
    Column() {
      Text('parent: ' + this.myVal.toString())
      Child({ val: this.myVal })
    }
  }
}

// V2
@ComponentV2
struct Child {
  @Param val: number = 0;
  @Event addOne: () => void;
  build() {
    Column() {
      Text('child: ' + this.val.toString())
      Button('+1').onClick(() => { this.addOne(); })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local myVal: number = 10;
  build() {
    Column() {
      Text('parent: ' + this.myVal.toString())
      Child({ val: this.myVal, addOne: () => this.myVal++ })
    }
  }
}
```

---

## @Prop → @Param

### 简单类型

@Params一定要给初始值

```typescript
// V1
@Component
struct Child {
  @Prop value: number;
  build() { Text(this.value.toString()) }
}

// V2
@ComponentV2
struct Child {
  @Param value: number = 0;
  build() { Text(this.value.toString()) }
}
```

### 复杂类型的单向数据传递

V2传递复杂对象需深拷贝：

```typescript
// V1
class Fruit {
  public apple: number = 5;
  public orange: number = 10;
}

@Component
struct Child {
  @Prop fruit: Fruit;
  build() {
    Column() {
      Text('apple: ' + this.fruit.apple.toString())
      Button('apple+1').onClick(() => { this.fruit.apple++; })
    }
  }
}

// V2 - 需实现深拷贝
@ObservedV2
class Fruit {
  @Trace public apple: number = 5;
  @Trace public orange: number = 10;
  
  clone(): Fruit {
    let newFruit = new Fruit();
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
      Text('apple: ' + this.fruit.apple.toString())
      Button('apple+1').onClick(() => { this.fruit.apple++; })
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local parentFruit: Fruit = new Fruit();
  build() {
    Column() {
      Child({ fruit: this.parentFruit.clone() })  // 深拷贝
    }
  }
}
```

### 子组件修改变量

使用`@Param @Once`允许子组件本地修改：

```typescript
// V1
@Component
struct Child {
  @Prop value: number;
  build() {
    Column() {
      Text(this.value.toString())
      Button('+1').onClick(() => { this.value++; })
    }
  }
}

// V2
@ComponentV2
struct Child {
  @Param @Once value: number = 0;
  build() {
    Column() {
      Text(this.value.toString())
      Button('+1').onClick(() => { this.value++; })
    }
  }
}
```

使用`@Local` + `@Monitor`实现父组件更新仍能通知子组件：

```typescript
@ComponentV2
struct Child {
  @Local localValue: number = 0;
  @Param value: number = 0;

  @Monitor('value')
  onValueChange(mon: IMonitor) {
    this.localValue = this.value;  // 父组件变化时更新本地值
  }

  build() {
    Column() {
      Text(`${this.localValue}`).fontSize(25)
      Button('Child +100').onClick(() => { this.localValue += 100; })
    }
  }
}
```

---

## @Provide/@Consume → @Provider/@Consumer

### alias和属性名匹配规则

V2中alias是唯一匹配key：

```typescript
// V1 - alias和属性名都可匹配
@Component
struct Child {
  @Consume('text') childMessage: string;
  @Consume message: string;  // 匹配到@Provide('text')
  build() {
    Column() {
      Text(this.childMessage)  // Hello World
      Text(this.message)       // Hello World
    }
  }
}

@Entry
@Component
struct Parent {
  @Provide('text') message: string = 'Hello World';
  build() { Column() { Child() } }
}

// V2 - alias是唯一匹配key
@ComponentV2
struct Child {
  @Consumer('text') childMessage: string = 'default';
  @Consumer() message: string = 'default';  // 无匹配，使用默认值
  build() {
    Column() {
      Text(this.childMessage)  // Hello World
      Text(this.message)       // default
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Provider('text') message: string = 'Hello World';
  build() { Column() { Child() } }
}
```

### V1的@Consume不支持本地初始化，V2支持

```typescript
// V1 - @Consume禁止本地初始化
@Component
struct Child {
  @Consume message: string;  // 必须依赖父组件@Provide
  build() { Text(this.message) }
}

// V2 - @Consumer允许本地初始化
@ComponentV2
struct Child {
  @Consumer() message: string = 'Hello World';  // 找不到@Provider时使用默认值
  build() { Text(this.message) }
}
```

### V1的@Provide可以从父组件初始化，V2不支持

```typescript
// V1
@Entry
@Component
struct Parent {
  @State parentValue: number = 42;
  build() { Child({ childValue: this.parentValue }) }
}

@Component
struct Child {
  @Provide childValue: number = 0;
  build() { Text(this.childValue.toString()) }
}

// V2 - 用@Param接收初始值再赋给@Provider
@Entry
@ComponentV2
struct Parent {
  @Local parentValue: number = 42;
  build() { Child({ initialValue: this.parentValue }) }
}

@ComponentV2
struct Child {
  @Param @Once initialValue: number = 0;
  @Provider() childValue: number = this.initialValue;
  build() { Text(this.childValue.toString()) }
}
```

### V1的@Provide默认不支持重载，V2默认支持

```typescript
// V1 - 需设置allowOverride
@Entry
@Component
struct GrandParent {
  @Provide('reviewVotes') reviewVotes: number = 40;
  build() { Column() { Parent() } }
}

@Component
struct Parent {
  @Provide({ allowOverride: 'reviewVotes' }) reviewVotes: number = 20;
  build() { Child() }
}

@Component
struct Child {
  @Consume('reviewVotes') reviewVotes: number;
  build() { Text(this.reviewVotes.toString()) }  // 20
}

// V2 - 默认支持重载
@Entry
@ComponentV2
struct GrandParent {
  @Provider('reviewVotes') reviewVotes: number = 40;
  build() { Column() { Parent() } }
}

@ComponentV2
struct Parent {
  @Provider() reviewVotes: number = 20;  // 覆盖上层
  build() { Child() }
}

@ComponentV2
struct Child {
  @Consumer() reviewVotes: number = 0;
  build() { Text(this.reviewVotes.toString()) }  // 20
}
```

---

## @Watch → @Monitor

### 单变量监听

```typescript
// V1
@Entry
@Component
struct WatchExample {
  @State @Watch('onAppleChange') apple: number = 0;

  onAppleChange(): void {
    console.info('apple count changed to ' + this.apple);
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Button('add apple').onClick(() => { this.apple++; })
    }
  }
}

// V2
@Entry
@ComponentV2
struct MonitorExample {
  @Local apple: number = 0;

  @Monitor('apple')
  onFruitChange(monitor: IMonitor) {
    console.info(`apple changed from ${monitor.value()?.before} to ${monitor.value()?.now}`);
  }

  build() {
    Column() {
      Text(`apple count: ${this.apple}`)
      Button('add apple').onClick(() => { this.apple++; })
    }
  }
}
```

### 多变量监听

```typescript
// V1 - 每个变量单独监听
@Entry
@Component
struct WatchExample {
  @State @Watch('onAppleChange') apple: number = 0;
  @State @Watch('onOrangeChange') orange: number = 0;

  onAppleChange(): void { console.info('apple: ' + this.apple); }
  onOrangeChange(): void { console.info('orange: ' + this.orange); }
}

// V2 - 一个@Monitor监听多个变量
@Entry
@ComponentV2
struct MonitorExample {
  @Local apple: number = 0;
  @Local orange: number = 0;

  @Monitor('apple', 'orange')
  onFruitChange(monitor: IMonitor) {
    monitor.dirty.forEach((name: string) => {
      console.info(`${name} changed from ${monitor.value(name)?.before} to ${monitor.value(name)?.now}`);
    });
  }
}
```

---

## 重复计算 → @Computed计算属性

```typescript
// V1 - 每次刷新都重复计算
@Entry
@Component
struct Index {
  @State firstName: string = 'Li';
  @State lastName: string = 'Hua';

  build() {
    Column() {
      Text(this.lastName + ' ' + this.firstName)  // 重复计算
      Text(this.lastName + ' ' + this.firstName)  // 重复计算
      Button('changed lastName').onClick(() => { this.lastName += 'a'; })
    }
  }
}

// V2 - 使用@Computed避免重复计算
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
      Button('changed lastName').onClick(() => { this.lastName += 'a'; })
    }
  }
}
```

---

## 双向绑定 $$→!!

```typescript
// V1
@Entry
@Component
struct TextInputExample {
  @State text: string = '';
  build() {
    TextInput({ text: $$this.text, placeholder: 'input...' })
  }
}

// V2
@Entry
@ComponentV2
struct TextInputExample {
  @Local text: string = '';
  build() {
    TextInput({ text: this.text!!, placeholder: 'input...' })
  }
}
```