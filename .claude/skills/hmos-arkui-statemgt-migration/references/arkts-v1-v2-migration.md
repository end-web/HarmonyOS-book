# V1-V2迁移概述

## 目录

- [V1V2使用指引](#v1v2使用指引)
- [V1与V2能力对照迁移表](#v1与v2能力对照迁移表)
- [逐步迁移策略](#逐步迁移策略)

---

## V1V2使用指引

1. **新开发应用**：直接采用V2版本
2. **已使用V1应用**：功能满足需求无需立即切换
3. **混用场景**：参考混用规则文档

---

## V1与V2能力对照迁移表

| V1装饰器 | V2装饰器 | 说明 |
| -------- | -------- | ---- |
| `@Component` | `@ComponentV2` | 组件装饰器 |
| `@State` | `@Local` 或 `@Param @Once` | 无外部初始化用`@Local`，外部初始化一次用`@Param @Once` |
| `@Prop` | `@Param` | 参数传递，V2的`@Param`只读 |
| `@Link` | `@Param` + `@Event` | 双向同步需手动实现 |
| `@Observed` | `@ObservedV2` | 可观察类标记 |
| `@ObjectLink` | `@ObservedV2` + `@Trace` | 嵌套对象观测 |
| `@Track` | `@Trace` | 属性级精确观测 |
| `@Provide/@Consume` | `@Provider/@Consumer` | 跨组件状态共享 |
| `@Watch` | `@Monitor` | 状态变化监听 |
| 无 | `@Computed` | 计算属性（V2新增） |
| `LocalStorage` | `@ObservedV2` + `@Trace` | 页面间状态共享 |
| `@LocalStorageLink` | `@Local` + 单例引用 | 双向同步LocalStorage |
| `@LocalStorageProp` | `@Local` + `@Monitor` | 单向接收LocalStorage |
| `AppStorage` | `AppStorageV2` | 跨Ability状态共享 |
| `@StorageLink` | `AppStorageV2.connect()` + `@Local` | 双向同步AppStorage |
| `@StorageProp` | `@Local` + `@Monitor` | 单向接收AppStorage |
| `PersistentStorage` | `PersistenceV2` | 持久化存储 |
| `Environment` | `UIAbilityContext.config` | 系统环境变量 |

---

## 逐步迁移策略

1. **优先级排序**：叶子组件优先，逐层向上迁移
2. **批次划分**：按功能模块分批次迁移
3. **混用处理**：参考混用规则文档

---

## 相关文档索引

| 迁移场景 | 参考文档 |
| -------- | -------- |
| 组件内状态变量 | `arkts-v1-v2-migration-inner-component.md` |
| 数据对象状态变量 | `arkts-v1-v2-migration-inner-class.md` |
| 内置对象迁移 | `arkts-v1-v2-migration-inner-object.md` |
| 应用级状态变量 | `arkts-v1-v2-migration-application.md` |
| 组件复用迁移 | `arkts-v1-v2-migration-reusable.md` |
| 循环渲染迁移 | `arkts-v1-v2-migration-rendering-control-repeat.md` |
| animateTo迁移 | `arkts-v1-v2-migration-animateTo.md` |