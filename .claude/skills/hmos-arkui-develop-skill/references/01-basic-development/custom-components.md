# 自定义组件

## 入口页面

### @Entry装饰器

入口页面类型，一般应用仅有一个@Entry装饰的入口页面

```typescript
@Entry
@Component
struct MainPage {
  build() {
    Column() {
      // 页面内容
    }
  }
}
```

## 创建自定义组件

### 基本结构

```typescript
@Component
struct MyComponent {
  @State count: number = 0;

  build() {
    Column() {
      Text(`${this.count}`)
      Button('Add')
        .onClick(() => this.count++)
    }
  }
}
```

### @Component装饰器

- struct关键字声明
- build()方法描述UI
- 无需new关键字创建实例

### @ComponentV2装饰器

搭配V2装饰器使用。

```typescript
@ComponentV2
struct MyComponentV2 {
  @Local count: number = 0;

  build() {
    Column() {
      Text(`${this.count}`)
    }
  }
}
```

---

## 组件生命周期

### 页面生命周期

| 回调 | 触发时机 |
|-----|---------|
| onPageShow | 页面显示时 |
| onPageHide | 页面隐藏时 |
| onBackPress | 用户点击返回键时 |

### 组件生命周期

| 回调 | 触发时机 |
|-----|---------|
| aboutToAppear | 组件即将出现时，build之前 |
| aboutToDisappear | 组件即将销毁时 |
| onDidBuild | build执行后立即触发（API 12+） |

```typescript
@Component
struct LifeCycleComponent {
  aboutToAppear() {
    console.info('Component about to appear');
  }

  aboutToDisappear() {
    console.info('Component about to disappear');
  }

  onDidBuild() {
    console.info('Build completed');
  }

  build() {
    Column() { }
  }
}
```

### 页面生命周期使用

```typescript
@Entry
@Component
struct PageComponent {
  onPageShow() {
    console.info('Page show');
  }

  onPageHide() {
    console.info('Page hide');
  }

  onBackPress(): boolean {
    console.info('Back pressed');
    return true;  // 返回true表示已处理
  }

  build() {
    Column() { }
  }
}
```

---

## 组件冻结

### @Reusable

组件复用，适用于频繁创建销毁的场景。

```typescript
@Reusable
@Component
struct ReusableComponent {
  aboutToReuse(params: Record<string, Object>) {
    // 复用时调用
  }

  aboutToRecycle(): void {
    // 回收时调用
  }

  build() {
    Column() { }
  }
}
```

### freezeWhenInactive

组件不活跃时冻结，减少刷新开销。

```typescript
@Component('freezeWhenInactive:true')
struct FreezeComponent {
  build() {
    Column() { }
  }
}
```

---

## @Builder - 轻量UI复用

### 定义

```typescript
// 全局Builder
@Builder
function MyBuilder() {
  Text('Builder Content')
}

// 组件内Builder
@Component
struct MyComponent {
  @Builder
  myBuilder() {
    Text('Component Builder')
  }

  build() {
    Column() {
      MyBuilder()       // 调用全局Builder
      this.myBuilder()  // 调用组件内Builder
    }
  }
}
```

### 参数传递

```typescript
@Builder
function ItemBuilder(item: string) {
  Text(item)
}

// 调用
ItemBuilder('Hello')
```

### 按引用传递

```typescript
interface ItemParams {
  title: string;
  count: number;
}

@Builder
function ItemBuilder($$: ItemParams) {
  Text(`${$$.title}: ${$$.count}`)
}

// 调用
ItemBuilder({ title: 'Item', count: 10 })
```

---

## @BuilderParam - UI内容占位

用于组件接收UI内容。

### 基本使用

```typescript
@Component
struct Container {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()  // 渲染传入的内容
    }
  }
}

// 使用
Container() {
  Text('Custom Content')
}
```

### 尾随闭包

```typescript
@Component
struct Panel {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
  }
}

// 尾随闭包方式
Panel() {
  Text('Content')
}
```

### 带参数BuilderParam

```typescript
@Component
struct ListContainer {
  @BuilderParam itemBuilder: (item: string) => void;

  build() {
    Column() {
      this.itemBuilder('Item 1')
      this.itemBuilder('Item 2')
    }
  }
}

// 使用
ListContainer({
  itemBuilder: (item: string) => {
    Text(item)
  }
})
```

---

## wrapBuilder

包装全局Builder，用于动态调用。

```typescript
@Builder
function DynamicBuilder(text: string) {
  Text(text)
}

// 包装并调用
let builder = wrapBuilder(DynamicBuilder);
builder('Dynamic Content');
```

---

## @LocalBuilder

组件内Builder，this指向当前组件。

```typescript
@Component
struct MyComponent {
  @Local count: number = 0;

  @LocalBuilder
  myBuilder() {
    Text(`${this.count}`)  // this指向MyComponent
  }

  build() {
    Column() {
      this.myBuilder()
    }
  }
}
```