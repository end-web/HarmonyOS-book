# 数据对象状态变量迁移

## 目录

- [嵌套对象属性观察](#嵌套对象属性观察)
- [类属性变化观测](#类属性变化观测)

---

## 嵌套对象属性观察

V1需通过`@ObjectLink`拆解嵌套对象，V2可直接使用`@ObservedV2` + `@Trace`深度观察：

```typescript
// V1 - 需子组件拆解嵌套对象
@Observed
class Address {
  public city: string;
  constructor(city: string) { this.city = city; }
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
      Button('city +a').onClick(() => { this.address.city += 'a'; })
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
      AddressView({ address: this.user.address })  // 需子组件
    }
  }
}

// V2 - 直接深度观察
@ObservedV2
class Address {
  @Trace public city: string;
  constructor(city: string) { this.city = city; }
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
      Text(`City: ${this.user.address.city}`)  // 直接访问嵌套属性
      Button('city +a').onClick(() => { this.user.address.city += 'a'; })
    }
  }
}
```

---

## 类属性变化观测

V1的`@Track`迁移为V2的`@Trace`：

```typescript
// V1
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
      Button('increase age').onClick(() => { this.user.age++; })
    }
  }
}

// V2
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
      Button('Increase age').onClick(() => { this.user.age++; })
    }
  }
}
```