# 状态管理

在声明式UI中，UI是状态的运行结果。状态变化驱动UI重新渲染，这种机制称为状态管理。

## 核心概念

- **View（UI）**：渲染界面，将状态映射为可视化组件
- **State（状态）**：驱动UI更新的数据源，状态变化触发UI刷新
- **状态变量**：被装饰器装饰的变量，具有观察变化的能力

## 版本选择

| 场景 | 推荐版本 |
|-----|---------|
| 新项目 | V2 |
| 已使用V1且满足需求 | 继续使用V1 |
| 需要深度观测 | V2 |
| 需要属性级精准更新 | V2 |

## 快速决策：选择哪个装饰器？

### 按数据流向选择

```
组件内状态 → @State(V1) / @Local(V2)
      ↓
父子单向 → @Prop(V1) / @Param(V2)
      ↓
父子双向 → @Link(V1) / @Param+@Event(V2)
      ↓
跨层级 → @Provide/@Consume(V1) / @Provider/@Consumer(V2)
      ↓
应用全局 → AppStorage(V1) / AppStorageV2(V2)
```

### 按数据结构选择

| 数据结构 | V1方案 | V2方案 |
|---------|-------|-------|
| 简单类型 | @State/@Prop/@Link | @Local/@Param |
| 对象（一层属性） | @State/@Prop/@Link | @Local/@Param + @Trace |
| 嵌套对象 | @Observed/@ObjectLink | @ObservedV2/@Trace |
| 数组 | @State观察数组项 | @Local观察数组项 |
| 二维数组 | @Observed包装数组 | @ObservedV2/@Trace |

## V1与V2对比速查

| 能力 | V1 | V2 |
|-----|----|----|
| 组件装饰器 | @Component | @ComponentV2 |
| 组件内状态 | @State | @Local |
| 外部输入 | @Prop | @Param |
| 双向同步 | @Link | @Param + @Event |
| 嵌套对象 | @Observed/@ObjectLink | @ObservedV2/@Trace |
| 跨层级同步 | @Provide/@Consume | @Provider/@Consumer |
| 状态监听 | @Watch | @Monitor |
| 全局状态 | AppStorage | AppStorageV2 |
| 深度观测 | 不支持 | 支持（@Trace） |
| 属性级更新 | 不支持 | 支持 |

## 文档导航

- [V1状态管理开发指南](./v1-state-management.md) - V1完整开发指南
- [V2状态管理开发指南](./v2-state-management.md) - V2完整开发指南
- [应用级状态管理](./app-state-management.md) - 全局状态管理
- [最佳实践与迁移](./best-practices.md) - 实践建议与迁移指南

## 使用限制

- 状态管理功能仅支持在UI主线程使用
- 状态管理非类装饰器，不允许在类中使用，如@State、@Prop、@Link等  以及V2的 @Local、@Params、@Event等
- 不支持在Worker、TaskPool中使用
- V1和V2装饰器不能在同一个组件内混用