# 渲染控制

## 概述

渲染控制用于控制UI的渲染逻辑，包括条件渲染和循环渲染。

---

## if/else - 条件渲染

根据条件决定是否渲染组件。

```typescript
Column() {
  if (this.count > 0) {
    Text(`Count: ${this.count}`)
  } else {
    Text('No data')
  }
}
```

### 使用场景

```typescript
// 登录状态判断
if (this.isLoggedIn) {
  Text('Welcome')
} else {
  Button('Login')
}

// 类型判断
if (this.type === 'admin') {
  AdminPanel()
} else if (this.type === 'user') {
  UserPanel()
}
```

### 注意事项

- 条件表达式中的变量变化会触发重新渲染
- 不支持在build函数外使用条件渲染

---

## ForEach - 循环渲染

遍历数组渲染组件。

### 基本语法

```typescript
ForEach(
  arr: Array,                    // 数据源
  itemGenerator: (item, index) => void,  // 组件生成函数
  keyGenerator?: (item, index) => string  // 键值生成函数（可选）
)
```

### 基本使用

```typescript
@State items: string[] = ['A', 'B', 'C'];

ForEach(this.items, (item: string) => {
  Text(item)
})
```

### 带键值生成

```typescript
interface Item {
  id: string;
  name: string;
}

@State items: Item[] = [
  { id: '1', name: 'A' },
  { id: '2', name: 'B' }
];

ForEach(this.items, 
  (item: Item) => {
    Text(item.name)
  },
  (item: Item) => item.id  // 使用id作为键值
)
```

### 使用建议

- 键值生成函数应返回唯一且稳定的值
- 不使用索引作为键值（可能导致渲染问题）

---

## LazyForEach - 懒加载

大数据量场景的懒加载渲染。

### 基本语法

```typescript
LazyForEach(
  dataSource: IDataSource,       // 数据源
  itemGenerator: (item) => void, // 组件生成函数
  keyGenerator?: (item) => string // 键值生成函数
)
```

### 实现IDataSource

```typescript
class MyDataSource implements IDataSource {
  private data: string[] = [];

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): string {
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    // 注册监听器
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    // 注销监听器
  }
}
```

### 使用示例

```typescript
@State dataSource: MyDataSource = new MyDataSource();

List() {
  LazyForEach(this.dataSource, 
    (item: string) => {
      ListItem() {
        Text(item)
      }
    },
    (item: string) => item
  )
}
.width('100%')
.height('100%')
```

### 缓存数量

```typescript
List() {
  LazyForEach(this.dataSource, (item) => {
    ListItem() { Text(item) }
  })
}
.cachedCount(5)  // 缓存5个列表项
```

### 优势

- 按需渲染，减少内存占用
- 支持大数据量列表
- 支持动态增删数据

---

## Repeat (V2) - 新版循环渲染

状态管理V2提供的循环渲染。

### 基本使用

```typescript
@ComponentV2
struct RepeatComponent {
  @Local items: string[] = ['A', 'B', 'C'];

  build() {
    Column() {
      Repeat(this.items)
        .each((item: string, index: number) => {
          Text(item)
        })
        .key((item: string) => item)
    }
  }
}
```

### 特性

- 支持深度观测
- 支持属性级更新
- 更好的性能

---

## 渲染控制对比

| 特性 | ForEach | LazyForEach | Repeat |
|-----|---------|-------------|--------|
| 数据量 | 小/中 | 大 | 中/大 |
| 渲染方式 | 全量渲染 | 懒加载 | 智能更新 |
| 状态管理 | V1 | V1 | V2 |
| 性能 | 中 | 高 | 高 |

---

## 使用建议

### 选择指南

1. **小数据量（<100项）**：使用ForEach
2. **大数据量（>100项）**：使用LazyForEach
3. **V2项目**：优先使用Repeat

### 性能优化

```typescript
// 使用cachedCount优化LazyForEach
List() {
  LazyForEach(this.dataSource, (item) => {
    ListItem() { /* ... */ }
  })
}
.cachedCount(5)

// 合理设置键值
ForEach(this.items, 
  (item) => { /* ... */ },
  (item) => item.id  // 稳定且唯一的键值
)
```

### 避免的问题

1. **不要在循环中使用复杂计算**
2. **不要使用索引作为键值**
3. **避免频繁更新整个数据源**

### 参考资料

[学习UI范式渲染控制-UI开发 (ArkTS声明式开发范式)-ArkUI（方舟UI框架）-应用框架 - 华为HarmonyOS开发者](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-rendering-control)