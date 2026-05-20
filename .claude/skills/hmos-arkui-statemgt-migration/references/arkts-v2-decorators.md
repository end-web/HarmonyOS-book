# V2装饰器速查

## @Local - 组件内部状态

```typescript
@ComponentV2
struct MyComponent {
  @Local count: number = 0;  // 必须本地初始化
  @Local message: string = 'Hello';
  @Local user: User = new User();  // 对象类型
  @Local items: string[] = [];     // 数组类型
}
```

**规则：**
- 禁止外部传入初始化
- 仅能观察变量本身变化
- 嵌套属性变化需配合@ObservedV2/@Trace

**可观察的内置类型API：**

| 类型 | 可观察API |
|------|-----------|
| Array | push, pop, shift, unshift, splice, copyWithin, fill, reverse, sort |
| Date | setFullYear, setMonth, setDate, setHours等 |
| Map | set, clear, delete |
| Set | add, clear, delete |

---

## @Param - 父→子数据传递

```typescript
@ComponentV2
struct Child {
  @Param value: number = 0;        // 可外部传入，有默认值
  @Require @Param id: number;       // 必须传入，无默认值
  @Param @Once localValue: number = 0;  // 保留本地副本
}
```

**规则：**
- 禁止在组件内直接修改
- 支持本地初始化，外部传入优先
- @Require标记必须传入的参数
- @Once保留本地副本，不随外部更新

**对象类型的特殊行为：**

```typescript
@ObservedV2
class User {
  @Trace name: string = '';
}

@ComponentV2
struct Child {
  @Param user: User = new User();
  
  onClick() {
    this.user = newUser;  // ❌ 禁止，编译报错
    this.user.name = 'Tom';  // ✓ 允许，修改属性会同步到父组件
  }
}
```

---

## @Event - 子→父通信

```typescript
@ComponentV2
struct Child {
  @Param value: number = 0;
  @Event onChange: (v: number) => void = () => {};  // 无参回调
  @Event $onValueChange: (v: number) => void = () => {};  // 建议用$前缀
  
  build() {
    Button('+').onClick(() => this.$onValueChange(this.value + 1))
  }
}

// 父组件
Child({ 
  value: this.count,
  $onValueChange: (v) => { this.count = v; }
})
```

**规则：**
- 只能装饰回调函数类型
- 未传入时使用本地默认值
- 建议使用$前缀命名

**异步特性：**
@Event修改父组件是立刻生效的，但同步回子组件是异步的：

```typescript
this.$onChange(20);
console.log(this.value);  // 仍然是旧值，下次渲染前更新
```

---

## @ObservedV2/@Trace - 深度观测

```typescript
@ObservedV2
class User {
  @Trace name: string = '';
  @Trace age: number = 0;
  @Trace address: Address = new Address();  // 嵌套对象
}

@ObservedV2
class Address {
  @Trace city: string = '';
  @Trace street: string = '';
}

// 使用
@Local user: User = new User();

// 以下操作都会触发刷新
this.user.name = 'Tom';
this.user.address.city = 'Shenzhen';
```

**规则：**
- @ObservedV2装饰类，@Trace装饰属性
- 两者必须配合使用
- 嵌套对象每层都需要@ObservedV2/@Trace
- 不支持与@Observed/@Track混用

**支持类型：**
- 基本类型：number, string, boolean
- 类对象
- 数组、Map、Set、Date

**继承支持：**

```typescript
@ObservedV2
class Base {
  @Trace name: string = '';
}

class Derived extends Base {
  // name仍可观察
}
```

---

## @Provider/@Consumer - 跨层级

```typescript
// 祖先组件
@ComponentV2
struct Parent {
  @Provider('theme') theme: string = 'light';
  @Provider() count: number = 0;  // 缺省aliasName，使用属性名
  
  build() {
    Column() {
      DeepChild()
    }
  }
}

// 后代组件（任意层级）
@ComponentV2
struct DeepChild {
  @Consumer('theme') theme: string = 'dark';  // 匹配aliasName
  @Consumer() count: number = 0;  // 匹配属性名
  
  build() {
    Text(this.theme)  // 'light'
  }
}
```

**规则：**
- @Provider和@Consumer通过aliasName匹配
- aliasName缺省时使用属性名
- @Consumer必须有本地默认值（找不到时使用）
- 支持双向同步

**重名查找：**

```typescript
@ComponentV2
struct GrandParent {
  @Provider() value: number = 1;
}

@ComponentV2
struct Parent {
  @Provider() value: number = 2;
  @Consumer() value: number = 0;  // 找到GrandParent，值为1
}

@ComponentV2
struct Child {
  @Consumer() value: number = 0;  // 找到最近的Parent，值为2
}
```

**配合@Trace使用：**

```typescript
@ObservedV2
class Theme {
  @Trace mode: string = 'light';
}

@ComponentV2
struct Parent {
  @Provider() theme: Theme = new Theme();
}

@ComponentV2
struct Child {
  @Consumer() theme: Theme = new Theme();
  
  build() {
    Text(this.theme.mode)  // 可观察属性变化
  }
}
```

---

## @Monitor - 状态监听

```typescript
@ComponentV2
struct Page {
  @Local count: number = 0;
  @Local name: string = '';
  
  // 监听单个变量
  @Monitor('count')
  onCountChange(monitor: IMonitor) {
    const result = monitor.value('count');
    console.log(`${result?.before} → ${result?.now}`);
  }
  
  // 监听多个变量
  @Monitor('count', 'name')
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      const result = monitor.value(path);
      console.log(`${path}: ${result?.before} → ${result?.now}`);
    });
  }
}
```

**在@ObservedV2类中使用：**

```typescript
@ObservedV2
class User {
  @Trace name: string = '';
  @Trace age: number = 0;
  
  @Monitor('name', 'age')
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach(path => {
      console.log(`${path} changed`);
    });
  }
}
```

**深层属性监听：**

```typescript
@ObservedV2
class Outer {
  @Trace inner: Inner = new Inner();
  
  @Monitor('inner.value')  // 监听嵌套属性
  onInnerChange(monitor: IMonitor) {
    console.log('inner.value changed');
  }
}
```

**规则：**
- 监听的属性必须是状态变量（@Local/@Param/@Trace装饰）
- 可同时监听多个属性
- 可获取变化前后的值
- 避免在回调中修改监听的属性（防止循环）

---

## @Computed - 计算属性

```typescript
@ComponentV2
struct Page {
  @Local price: number = 100;
  @Local quantity: number = 2;
  
  @Computed
  get total(): number {
    return this.price * this.quantity;  // 只计算一次
  }
  
  build() {
    Text(`Total: ${this.total}`)  // 读取缓存
    Text(`Total: ${this.total}`)  // 读取缓存，不重复计算
  }
}
```

**在@ObservedV2类中使用：**

```typescript
@ObservedV2
class ShoppingCart {
  @Trace items: Item[] = [];
  
  @Computed
  get total(): number {
    return this.items.reduce((sum, item) => sum + item.price, 0);
  }
  
  @Computed
  get hasItems(): boolean {
    return this.items.length > 0;
  }
}
```

**规则：**
- 只能装饰getter方法
- 计算结果缓存，依赖变化时才重新计算
- 禁止在getter中修改依赖变量（防止循环）
- 不能与双向绑定(!!)连用
- 可初始化子组件的@Param

**链式计算：**

```typescript
@Local celsius: number = 20;

@Computed
get fahrenheit(): number {
  return this.celsius * 9 / 5 + 32;
}

@Computed
get kelvin(): number {
  return (this.fahrenheit - 32) * 5 / 9 + 273.15;
}

// celsius变化 → fahrenheit重新计算 → kelvin重新计算
```

---

## @Require - 必传参数

```typescript
@ComponentV2
struct Child {
  @Require @Param id: number;      // 必须传入
  @Param name: string = 'default';  // 可选，有默认值
}

// 正确
Child({ id: 1 })

// 错误：缺少必传参数
Child({ name: 'test' })
```

---

## @Once - 本地副本

```typescript
@ComponentV2
struct Child {
  @Param @Once value: number = 0;  // 外部传入一次后保留本地副本
}

// 父组件修改不会更新Child的value
```

---

## AppStorageV2（V2全局状态）

V2版本的应用全局状态，类型安全，配合@ObservedV2使用。

### 基本用法

```typescript
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
class AppConfig {
  @Trace theme: string = 'light';
  @Trace fontSize: number = 14;
}

@Entry
@ComponentV2
struct App {
  @Local config: AppConfig = AppStorageV2.connect(
    AppConfig, 
    () => new AppConfig()
  )!;
  
  build() {
    Column() {
      Text(`Theme: ${this.config.theme}`)
        .onClick(() => {
          this.config.theme = 'dark';  // 全局同步
        })
    }
  }
}
```

---

## PersistenceV2（V2持久化）

独立的持久化能力，不依赖AppStorage。

### 基本用法

```typescript
import { PersistenceV2 } from '@kit.ArkUI';

let persistence = new PersistenceV2('myApp');

// 存取数据
persistence.set('key', 'value');
let value = persistence.get('key');
persistence.delete('key');
```

---

## 使用建议

### 场景选择

| 场景           | 推荐方案                          |
| -------------- | --------------------------------- |
| 跨页面共享状态 | AppStorage / AppStorageV2         |
| 页面内组件共享 | LocalStorage                      |
| 需要持久化     | PersistentStorage / PersistenceV2 |
| 获取系统环境   | Environment                       |
| 不涉及UI的数据 | 用户首选项                        |



## V2装饰器使用限制

| 装饰器 | 仅@ComponentV2 | 必须本地初始化 | 可外部传入 |
|--------|---------------|---------------|-----------|
| @Local | ✓ | ✓ | ✗ |
| @Param | ✓ | 可选 | ✓ |
| @Event | ✓ | 可选 | ✓ |
| @Provider | ✓ | ✓ | ✗ |
| @Consumer | ✓ | ✓ | ✗ |
| @Monitor | ✓ | - | - |
| @Computed | ✓/类中 | - | - |
| @ObservedV2 | 类 | - | - |
| @Trace | 类属性 | - | - |



