# V2状态管理开发指南

状态管理V2是增强版本，提供深度观测、属性级更新等能力。**推荐新项目使用V2。**

## 为什么选择V2

| V1问题 | V2解决 |
|-------|-------|
| 只能观察第一层属性 | 支持深度观测 |
| 对象属性修改触发整体更新 | 属性级精准更新 |
| 状态与UI耦合 | 数据独立于UI |
| 装饰器规则复杂 | 输入/输出分离，更清晰 |

## 装饰器概览

```
┌─────────────────────────────────────────────────────────┐
│                    @ComponentV2                         │
├─────────────────────────────────────────────────────────┤
│  数据输入          │  @Param（外部输入）                  │
│                   │  @Param @Once（仅初始化一次）         │
├─────────────────────────────────────────────────────────┤
│  组件内状态         │  @Local（内部状态）                  │
├─────────────────────────────────────────────────────────┤
│  数据输出          │  @Event（回调函数）                   │
├─────────────────────────────────────────────────────────┤
│  深度观测          │  @ObservedV2 + @Trace                │
├─────────────────────────────────────────────────────────┤
│  监听/计算         │  @Monitor / @Computed                │
├─────────────────────────────────────────────────────────┤
│  跨层级            │  @Provider / @Consumer               │
└─────────────────────────────────────────────────────────┘
```

---

## 一、@Local：组件内部状态

组件内部状态，禁止从外部初始化。

### 使用规则

| 规则 | 说明 |
|-----|------|
| 组件类型 | @ComponentV2 |
| 初始化 | **必须**本地初始化，禁止外部传入 |
| 访问范围 | 组件私有 |
| 支持类型 | boolean、string、number、Object、class、Array、Map、Set、Date |

### 典型场景

```typescript
@Entry
@ComponentV2
struct Counter {
  @Local count: number = 0;  // 必须本地初始化
  
  build() {
    Column() {
      Text(`${this.count}`)
      Button('Increment')
        .onClick(() => this.count++)
    }
  }
}
```

### 配合@Trace实现深度观测

```typescript
@ObservedV2
class Info {
  @Trace name: string = '';
  @Trace age: number = 0;
}

@Entry
@ComponentV2
struct Page {
  @Local info: Info = new Info();
  
  build() {
    Column() {
      Text(`${this.info.name}, ${this.info.age}`)
        .onClick(() => {
          this.info.name = 'Tom';  // 可观察 ✓
        })
    }
  }
}
```

---

## 二、@Param：组件外部输入

接收父组件传入的数据，支持深度同步。

### 使用规则

| 规则 | 说明 |
|-----|------|
| 初始化 | 可本地初始化或外部传入 |
| 直接修改 | 禁止 |
| 对象属性修改 | 允许（同步到数据源） |
| 同步方向 | 父→子单向 |

### 典型场景

```typescript
@ComponentV2
struct Child {
  @Param message: string = '';  // 接收外部输入
  
  build() {
    Text(this.message)
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local greeting: string = 'Hello';
  
  build() {
    Column() {
      Child({ message: this.greeting })
      Button('Change')
        .onClick(() => this.greeting = 'Hi')
    }
  }
}
```

### @Require强制传入

```typescript
@ComponentV2
struct Child {
  @Require @Param id: number;      // 必须传入
  @Param optional: string = 'ok';  // 可选
}

Parent: Child({ id: 100 })  // id必须传，optional可省略
```

---

## 三、@Event：组件输出

子组件向父组件通信的事件回调机制。

### 基本概念

- **@Param**：输入，父→子
- **@Event**：输出，子→父

### 典型场景：双向绑定

```typescript
@ComponentV2
struct Counter {
  @Param count: number = 0;
  @Event $onChange: (value: number) => void;
  
  build() {
    Row() {
      Button('-')
        .onClick(() => this.$onChange(this.count - 1))
      Text(`${this.count}`)
      Button('+')
        .onClick(() => this.$onChange(this.count + 1))
    }
  }
}

@Entry
@ComponentV2
struct Parent {
  @Local value: number = 0;
  
  build() {
    Column() {
      Text(`Parent: ${this.value}`)
      Counter({ 
        count: this.value,
        $onChange: (v) => { this.value = v; }
      })
    }
  }
}
```

### @Param + @Event = 双向同步（替代@Link）

```typescript
// V1: @Link
@Component
struct V1Child {
  @Link value: number;
}

// V2: @Param + @Event
@ComponentV2
struct V2Child {
  @Param value: number = 0;
  @Event $value: (v: number) => void;
}
```

---

## 四、@ObservedV2/@Trace：深度观测

使类具有深度观察能力，追踪嵌套属性变化。

### 基本用法

```typescript
@ObservedV2
class User {
  @Trace name: string = '';       // 追踪
  @Trace age: number = 0;         // 追踪
  description: string = '';       // 不追踪
}

@ObservedV2
class Address {
  @Trace city: string = '';
  @Trace street: string = '';
}

@ObservedV2
class Person {
  @Trace name: string = '';
  @Trace address: Address = new Address();  // 嵌套对象
}

@Entry
@ComponentV2
struct Page {
  @Local person: Person = new Person();
  
  build() {
    Column() {
      Text(this.person.address.city)  // 深度可观察
        .onClick(() => {
          this.person.address.city = 'Shenzhen';  // 触发刷新
        })
    }
  }
}
```

### 支持的类型

| 类型 | 可观察的API |
|-----|------------|
| Array | push, pop, shift, unshift, splice, copyWithin, fill, reverse, sort |
| Map | set, clear, delete |
| Set | add, clear, delete |
| Date | setFullYear, setMonth 等 |

---

## 五、@Monitor：状态深度监听

深度监听状态变量变化，可获取变化前后的值。

### 基本用法

```typescript
@Entry
@ComponentV2
struct Page {
  @Local @Monitor('count') count: number = 0;
  
  @Monitor('count')
  onCountChange(monitor: IMonitor) {
    const result = monitor.value('count');
    console.log(`count: ${result?.before} -> ${result?.now}`);
  }
  
  build() {
    Column() {
      Text(`${this.count}`)
      Button('+1')
        .onClick(() => this.count++)
    }
  }
}
```

### 在类中使用

```typescript
@ObservedV2
class User {
  @Trace @Monitor('name') name: string = '';
  
  @Monitor('name')
  onNameChange(monitor: IMonitor) {
    const result = monitor.value('name');
    console.log(`name: ${result?.before} -> ${result?.now}`);
  }
}
```

### 多属性监听

```typescript
@Local @Monitor('a', 'b') a: number = 0;
@Local @Monitor('a', 'b') b: number = 0;

@Monitor('a', 'b')
onChange(monitor: IMonitor) {
  monitor.dirty.forEach((path) => {
    console.log(`${path} changed`);
  });
}
```

---

## 六、@Computed：计算属性

缓存计算结果，避免重复计算。

### 基本用法

```typescript
@Entry
@ComponentV2
struct Page {
  @Local firstName: string = 'Tom';
  @Local lastName: string = 'Smith';
  
  @Computed
  get fullName(): string {
    return `${this.firstName} ${this.lastName}`;
  }
  
  build() {
    Column() {
      Text(this.fullName)  // 使用缓存
      Text(this.fullName)  // 不重新计算
    }
  }
}
```

### 典型场景：表单验证

```typescript
@Entry
@ComponentV2
struct Form {
  @Local username: string = '';
  @Local password: string = '';
  
  @Computed
  get isValid(): boolean {
    return this.username.length >= 3 && this.password.length >= 6;
  }
  
  build() {
    Column() {
      TextInput({ text: this.username })
        .onChange((v) => this.username = v)
      TextInput({ text: this.password })
        .onChange((v) => this.password = v)
      Button('Submit')
        .enabled(this.isValid)
    }
  }
}
```

### 典型场景：购物车计算

```typescript
@Entry
@ComponentV2
struct Cart {
  @Local items: { price: number; quantity: number }[] = [];
  
  @Computed
  get totalPrice(): number {
    return this.items.reduce((sum, item) => 
      sum + item.price * item.quantity, 0);
  }
  
  @Computed
  get discount(): number {
    if (this.totalPrice >= 500) return 0.2;
    if (this.totalPrice >= 200) return 0.1;
    return 0;
  }
  
  @Computed
  get finalPrice(): number {
    return this.totalPrice * (1 - this.discount);
  }
}
```

---

## 七、@Provider/@Consumer：跨层级同步

跨多层组件的双向状态同步。

### 基本用法

```typescript
@Entry
@ComponentV2
struct GrandParent {
  @Provider('theme') theme: string = 'light';
  
  build() {
    Column() {
      Parent()
    }
  }
}

@ComponentV2
struct Child {
  @Consumer('theme') theme: string = 'default';
  
  build() {
    Text(`Theme: ${this.theme}`)
      .onClick(() => {
        this.theme = 'dark';  // 同步到GrandParent
      })
  }
}
```

---

## V1到V2快速迁移

### 组件声明

```typescript
// V1
@Component
struct MyComponent {
  @State count: number = 0;
}

// V2
@ComponentV2
struct MyComponent {
  @Local count: number = 0;
}
```

### 状态变量

```typescript
// V1 → V2
@State count: number = 0;      →  @Local count: number = 0;
@Prop name: string = '';        →  @Param name: string = '';
@Link value: number;            →  @Param value + @Event $value
@ObjectLink obj: MyClass;       →  @Param obj: MyClass;
```

### 嵌套对象

```typescript
// V1
@Observed
class Info { name: string = ''; }
@ObjectLink info: Info;

// V2
@ObservedV2
class Info { @Trace name: string = ''; }
@Param info: Info;
```

### 状态监听

```typescript
// V1
@State @Watch('onChange') count: number = 0;
onChange(propName: string) { ... }

// V2
@Local @Monitor('count') count: number = 0;
@Monitor('count')
onChange(monitor: IMonitor) {
  const { before, now } = monitor.value('count') || {};
}
```