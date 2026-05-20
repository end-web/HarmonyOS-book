# V1状态管理开发指南

状态管理V1是ArkUI的基础状态管理方案，使用代理观察数据机制。

## 适用场景

- 已有V1项目维护
- 不需要深度观测的场景
- 简单的父子组件通信

## 装饰器概览

```
                    ┌─────────────────────────────────────┐
                    │           应用级状态                 │
                    │  AppStorage / PersistentStorage     │
                    └──────────────┬──────────────────────┘
                                   │ @StorageLink/@StorageProp
                                   ▼
┌──────────────┐  @Provide   ┌──────────────┐  @Link/@Prop  ┌──────────────┐
│  祖父组件     │────────────▶│   父组件      │──────────────▶│   子组件      │
│  @State      │◀────────────│   @State      │◀──────────────│   @Link      │
└──────────────┘  @Consume   └──────────────┘              └──────────────┘
```

---

## 一、@State：组件内状态

最基础的状态装饰器，作为大部分状态变量的数据源。

### 什么时候用

- 组件需要内部管理的状态
- 作为子组件的数据源
- 需要触发UI刷新的本地数据

### 使用规则

| 规则 | 说明 |
|-----|------|
| 初始化 | 必须本地初始化 |
| 访问范围 | 组件私有，只能内部访问 |
| 生命周期 | 与所属组件相同 |
| 支持类型 | boolean、string、number、Object、class、Array、Map、Set、Date |

### 观察能力

V1装饰器只能观察对象第一层属性变化：

```typescript
class Model {
  value: string = 'Hello';
  nested: { name: string } = { name: 'World' };
}

@State model: Model = new Model();

// 可观察 ✓
this.model = new Model();      // 整体赋值
this.model.value = 'Hi';       // 第一层属性

// 不可观察 ✗
this.model.nested.name = 'ArkUI';  // 嵌套属性
```

### 典型场景

#### 表单状态管理

```typescript
@Entry
@Component
struct FormPage {
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;

  build() {
    Column() {
      TextInput({ placeholder: '用户名' })
        .onChange((value) => this.username = value)
      
      TextInput({ placeholder: '密码' })
        .type(InputType.Password)
        .onChange((value) => this.password = value)
      
      Button(this.isLoading ? '登录中...' : '登录')
        .enabled(!this.isLoading && this.username.length > 0)
        .onClick(() => this.login())
    }
  }

  async login() {
    this.isLoading = true;
    // 登录逻辑...
    this.isLoading = false;
  }
}
```

#### 列表数据管理

```typescript
interface Todo {
  id: number;
  text: string;
  done: boolean;
}

@Entry
@Component
struct TodoList {
  @State todos: Todo[] = [];

  build() {
    Column() {
      ForEach(this.todos, (todo: Todo) => {
        Row() {
          Checkbox()
            .select(todo.done)
            .onChange((checked) => {
              todo.done = checked;
              this.todos = [...this.todos];  // 触发刷新
            })
          Text(todo.text)
        }
      })
      
      Button('Add')
        .onClick(() => {
          this.todos.push({ id: Date.now(), text: 'New', done: false });
        })
    }
  }
}
```

---

## 二、@Prop/@Link：父子组件同步

### 快速选择

| 需求 | 装饰器 | 特点 |
|-----|-------|------|
| 父→子单向传递 | @Prop | 子组件修改不影响父组件 |
| 父↔子双向同步 | @Link | 修改双向传递 |

### @Prop：父子单向同步

#### 使用规则

| 规则 | 说明 |
|-----|------|
| 初始化 | 可本地初始化或从父组件传入 |
| 同步方向 | 父→子单向 |
| 数据传递 | 深拷贝 |
| 类型一致 | 必须与数据源类型相同 |

#### 典型场景

```typescript
@Component
struct Counter {
  @Prop count: number = 0;  // 从父组件接收
  
  build() {
    Row() {
      Text(`Count: ${this.count}`)
      Button('Reset')
        .onClick(() => {
          this.count = 0;  // 仅影响本地，不同步回父组件
        })
    }
  }
}

@Entry
@Component
struct Parent {
  @State total: number = 10;
  
  build() {
    Column() {
      Text(`Total: ${this.total}`)
      Button('Add')
        .onClick(() => this.total++)
      
      Counter({ count: this.total })
    }
  }
}
```

### @Link：父子双向同步

#### 使用规则

| 规则 | 说明 |
|-----|------|
| 初始化 | **禁止**本地初始化 |
| 同步方向 | 父↔子双向 |
| 数据传递 | 引用传递 |
| 类型一致 | 必须与数据源类型相同 |

#### 典型场景

```typescript
@Component
struct Switch {
  @Link isOn: boolean;  // 禁止本地初始化
  
  build() {
    Toggle({ isOn: this.isOn })
      .onChange((value) => {
        this.isOn = value;  // 同步回父组件
      })
  }
}

@Entry
@Component
struct Parent {
  @State enabled: boolean = false;
  
  build() {
    Column() {
      Text(`Status: ${this.enabled ? 'ON' : 'OFF'}`)
      Switch({ isOn: this.enabled })  // 双向绑定
    }
  }
}
```

### @Prop vs @Link 对比

| 特性 | @Prop | @Link |
|-----|-------|-------|
| 同步方向 | 单向（父→子） | 双向（父↔子） |
| 本地初始化 | 可选 | 禁止 |
| 数据传递 | 深拷贝 | 引用 |
| 子组件修改 | 不影响父组件 | 同步到父组件 |
| 性能 | 复杂对象有拷贝开销 | 无拷贝开销 |

---

## 三、@Observed/@ObjectLink：嵌套对象观察

解决V1装饰器只能观察第一层属性的问题。

### 什么时候用

- 数据结构有嵌套对象
- 需要观察第二层及更深层的属性变化
- 对象数组中的对象属性变化

### 核心概念

| 装饰器 | 作用 | 位置 |
|-------|------|------|
| @Observed | 类装饰器，使类具有观察能力 | 装饰class |
| @ObjectLink | 变量装饰器，接收@Observed实例 | 组件内 |

### 基本用法

```typescript
// 1. 用@Observed装饰需要观察的类
@Observed
class Book {
  public title: string;
  public author: string;
  
  constructor(title: string, author: string) {
    this.title = title;
    this.author = author;
  }
}

// 2. 子组件用@ObjectLink接收
@Component
struct BookCard {
  @ObjectLink book: Book;  // 接收@Observed实例
  
  build() {
    Column() {
      Text(this.book.title)
      Button('Change Title')
        .onClick(() => {
          this.book.title = 'New Title';  // 可观察！
        })
    }
  }
}

// 3. 父组件传递@Observed实例
@Entry
@Component
struct BookList {
  @State books: Book[] = [
    new Book('ArkUI Guide', 'Huawei')
  ];
  
  build() {
    Column() {
      ForEach(this.books, (book: Book) => {
        BookCard({ book: book })
      })
    }
  }
}
```

### 使用规则

- @Observed只能装饰class
- @ObjectLink禁止本地初始化
- @ObjectLink变量只读，但属性可修改

```typescript
@Component
struct Card {
  @ObjectLink item: Item;
  
  someMethod() {
    this.item.name = 'New';      // ✓ 允许修改属性
    this.item = new Item();      // ✗ 禁止变量赋值
  }
}
```

### 典型场景：嵌套对象

```typescript
@Observed
class Address {
  public city: string;
  public street: string;
}

@Observed
class Person {
  public name: string;
  public address: Address;  // 嵌套对象
}

@Component
struct AddressCard {
  @ObjectLink address: Address;
  
  build() {
    Row() {
      Text(`${this.address.city}`)
      Button('Change')
        .onClick(() => {
          this.address.city = 'Shenzhen';  // 可观察
        })
    }
  }
}

@Component
struct PersonCard {
  @ObjectLink person: Person;
  
  build() {
    Column() {
      Text(this.person.name)
      AddressCard({ address: this.person.address })
    }
  }
}
```

---

## 四、@Provide/@Consume：跨层级同步

跨多层组件的双向状态同步。

### 什么时候用

- 数据需要跨多层组件传递
- 避免"prop drilling"
- 多个深层组件需要访问同一状态

### 基本用法

```typescript
// 通过属性名绑定
@Component
struct GrandChild {
  @Consume theme: string;  // 自动匹配属性名
  
  build() {
    Text(`Theme: ${this.theme}`)
      .onClick(() => {
        this.theme = 'dark';  // 双向同步
      })
  }
}

@Entry
@Component
struct GrandParent {
  @Provide theme: string = 'light';  // 提供者
  
  build() {
    Column() {
      Child()  // 中间层无需传递
    }
  }
}
```

### 通过别名绑定

```typescript
@Entry
@Component
struct Parent {
  @Provide('appTheme') theme: string = 'light';  // 别名
  
  build() {
    Column() {
      DeepChild()
    }
  }
}

@Component
struct DeepChild {
  @Consume('appTheme') currentTheme: string;  // 通过别名匹配
  
  build() {
    Text(`Current: ${this.currentTheme}`)
  }
}
```

### 典型场景：全局主题

```typescript
@Entry
@Component
struct App {
  @Provide('theme') theme: 'light' | 'dark' = 'light';
  
  build() {
    Column() {
      Header()
      Content()
      Footer()
    }
    .backgroundColor(this.theme === 'dark' ? '#1a1a1a' : '#ffffff')
  }
}

@Component
struct ThemeToggle {
  @Consume('theme') theme: 'light' | 'dark';
  
  build() {
    Toggle({ isOn: this.theme === 'dark' })
      .onChange((isDark) => {
        this.theme = isDark ? 'dark' : 'light';
      })
  }
}
```

---

## 五、@Watch：状态变量监听

监听状态变量的变化并执行回调。

### 基本用法

```typescript
@Entry
@Component
struct Counter {
  @State @Watch('onCountChange') count: number = 0;
  
  onCountChange(propName: string) {
    console.log(`${propName} changed to ${this.count}`);
  }
  
  build() {
    Column() {
      Text(`${this.count}`)
      Button('Increment')
        .onClick(() => this.count++)
    }
  }
}
```

### 典型场景：表单验证

```typescript
@Entry
@Component
struct FormPage {
  @State @Watch('validateEmail') email: string = '';
  @State emailError: string = '';
  @State @Watch('validatePassword') password: string = '';
  @State passwordError: string = '';
  @State isValid: boolean = false;
  
  validateEmail() {
    this.emailError = !this.email.includes('@') ? '请输入有效邮箱' : '';
    this.checkForm();
  }
  
  validatePassword() {
    this.passwordError = this.password.length < 6 ? '密码至少6位' : '';
    this.checkForm();
  }
  
  checkForm() {
    this.isValid = !this.emailError && !this.passwordError;
  }
  
  build() {
    Column() {
      TextInput({ text: this.email })
        .onChange((value) => this.email = value)
      Text(this.emailError).fontColor(Color.Red)
      
      TextInput({ text: this.password })
        .type(InputType.Password)
        .onChange((value) => this.password = value)
      Text(this.passwordError).fontColor(Color.Red)
      
      Button('Submit').enabled(this.isValid)
    }
  }
}
```

### 注意事项

- 初始化时不触发
- 避免在回调中修改被监听的变量（防止无限循环）
- 回调应快速执行

---

## V1局限性

| 局限 | 说明 | 解决方案 |
|-----|------|---------|
| 无法深度观测 | 只能观察第一层属性 | 使用@Observed/@ObjectLink |
| 状态与UI耦合 | 数据不能独立于UI存在 | 迁移到V2 |
| 冗余更新 | 对象属性修改触发整体更新 | 迁移到V2 |
| 装饰器规则复杂 | @Link/@Prop/@ObjectLink等规则多 | 迁移到V2 |