# 最佳实践与迁移指南

## 一、装饰器选择决策树

### 按数据作用范围选择

```
数据需要在哪里使用？
│
├─ 仅组件内部
│   └─ @State (V1) / @Local (V2)
│
├─ 父子组件间
│   ├─ 单向传递（父→子）
│   │   └─ @Prop (V1) / @Param (V2)
│   │
│   └─ 双向同步（父↔子）
│       └─ @Link (V1) / @Param+@Event (V2)
│
├─ 跨多层组件
│   └─ @Provide/@Consume (V1) / @Provider/@Consumer (V2)
│
└─ 全局共享
    └─ AppStorage (V1) / AppStorageV2 (V2)
```

### 按数据结构选择

| 数据结构 | V1方案 | V2方案 |
|---------|-------|-------|
| 简单类型 | @State/@Prop/@Link | @Local/@Param |
| 对象（第一层属性） | @State/@Prop/@Link | @Local/@Param |
| 嵌套对象 | @Observed/@ObjectLink | @ObservedV2/@Trace |
| 数组 | @State | @Local |
| 二维数组 | @Observed包装 | @ObservedV2/@Trace |

---

## 二、V1到V2迁移指南

### 装饰器对应关系

| V1 | V2 | 说明 |
|----|----|----|
| @Component | @ComponentV2 | 组件装饰器 |
| @State | @Local | 组件内状态 |
| @Prop | @Param | 外部输入 |
| @Link | @Param + @Event | 双向同步 |
| @ObjectLink | @Param | 嵌套对象 |
| @Observed | @ObservedV2 + @Trace | 类装饰器 |
| @Watch | @Monitor | 状态监听 |
| @Provide/@Consume | @Provider/@Consumer | 跨层级 |

### 迁移示例

#### 简单组件

```typescript
// V1
@Component
struct V1Component {
  @State count: number = 0;
  build() { Text(`${this.count}`) }
}

// V2
@ComponentV2
struct V2Component {
  @Local count: number = 0;
  build() { Text(`${this.count}`) }
}
```

#### 父子双向同步

```typescript
// V1
@Component
struct V1Child {
  @Link value: number;
  build() {
    Button('+1').onClick(() => this.value++)
  }
}

// V2
@ComponentV2
struct V2Child {
  @Param value: number = 0;
  @Event $onChange: (v: number) => void;
  build() {
    Button('+1').onClick(() => this.$onChange(this.value + 1))
  }
}
```

#### 嵌套对象

```typescript
// V1
@Observed
class V1Info { name: string = ''; }

// V2
@ObservedV2
class V2Info { @Trace name: string = ''; }
```

---

## 三、常见问题与解决方案

### Q: 修改嵌套属性不刷新？

**V1方案**：使用@Observed/@ObjectLink或整体赋值
```typescript
this.model = { ...this.model, nested: { name: 'new' } };
```

**V2方案**：使用@ObservedV2/@Trace
```typescript
@ObservedV2
class Model {
  @Trace nested: { name: string } = { name: '' };
}
```

### Q: @Param无法修改？

使用@Event通知父组件，或使用@Param @Once保留本地副本。

### Q: 数组元素对象属性不刷新？

**V1**：使用@Observed装饰元素类型
**V2**：使用@ObservedV2/@Trace

### Q: animateTo动画异常（V2）？

```typescript
import { UIUtils } from '@kit.ArkUI';

UIUtils.applySync(() => { this.value = 100; });
animateTo({ duration: 1000 }, () => { this.value = 200; });
```

---

## 四、性能优化建议

### 使用@Computed缓存计算

```typescript
@Computed
get total(): number {
  return this.items.reduce((s, i) => s + i.price, 0);
}
```

### 合理使用@Trace

只追踪需要观察的属性，减少不必要的更新。

### 避免深度嵌套

扁平化数据结构可简化状态管理。

### 状态分层

```
全局状态（AppStorage）→ 用户信息、主题
页面状态（LocalStorage）→ 页面共享数据
组件状态（@Local）→ 组件私有数据
```