---
name: hmos-arkui-statemgt-migration
description: 帮助开发者将ArkUI状态管理从V1迁移到V2。触发场景：(1) V1项目升级到V2；(2) 迁移@Component/@State/@Prop/@Link/@Observed/@ObjectLink/@Provide/@Consume/@Watch/@Reusable装饰器；(3) 迁移LocalStorage/AppStorage/PersistentStorage/Environment应用级状态；(4) 将ForEach/LazyForEach迁移到Repeat；(5) 解决animateTo在V2中的兼容问题；(6) 处理V1与V2混用场景；(7) 询问V1和V2装饰器对应关系或差异。
---

# 状态管理 V1-V2 迁移

## 核心迁移映射

### 组件装饰器

| V1 | V2 | 说明 |
|---|---|---|
| `@Component` | `@ComponentV2` | 组件装饰器 |
| `@State` | `@Local` / `@Param @Once` | 内部状态；需外部初始化用`@Param @Once` |
| `@Prop` | `@Param` | 父→子单向传递；V2的`@Param`只读，`@Param`需要给初始值 |
| `@Link` | `@Param` + `@Event` | 双向同步需手动实现 |
| `@Observed` | `@ObservedV2` | 标记可观察类 |
| `@ObjectLink` | `@ObservedV2` + `@Trace` | 深度观测嵌套对象 |
| `@Track` | `@Trace` | 属性级精确观测 |
| `@Provide/@Consume` | `@Provider/@Consumer` | 跨组件状态共享 |
| `@Watch` | `@Monitor` | 状态变化监听 |
| `@Reusable` | `@ReusableV2` | 组件复用 |
| 无 | `@Computed` | 计算属性（V2新增） |

> 详细迁移示例参考：`references/arkts-v1-v2-migration-inner-component.md`

### 应用级状态

| V1 | V2 | 说明 |
|---|---|---|
| `LocalStorage` | `@ObservedV2` + `@Trace` 单例 | 页面间状态共享 |
| `@LocalStorageLink` | `@Local` + 单例引用 | 双向同步LocalStorage数据 |
| `@LocalStorageProp` | `@Local` + `@Monitor` | 单向接收，本地修改不同步 |
| `AppStorage` | `AppStorageV2+`@ObservedV2` + `@Trace`提供存储单例 | +跨Ability状态共享 |
| `AppStorage.setOrCreate` | `AppStorageV2.connect()`+借助类传递变量 | 创建共享状态 |
| `@StorageLink` | `AppStorageV2.connect()` + `@Local` 需要借助类 | 双向同步AppStorage数据 |
| `@StorageProp` | `@Local` + `@Monitor`需要借助类传递 | 单向接收，本地修改不同步 |
| `PersistentStorage` | `PersistenceV2` | 持久化存储 |
| `Environment` | `UIAbilityContext.config` | 系统环境变量 |

> 详细迁移示例参考：`references/arkts-v1-v2-migration-application.md`

### 渲染控制

| V1 | V2 | 说明 |
|---|---|---|
| `ForEach` | `Repeat` | 全量加载循环渲染 |
| `LazyForEach` | `Repeat` + `.virtualScroll()` | 懒加载循环渲染 |
| `$$` | `!!` | 双向绑定语法糖 |

> 详细迁移示例参考：`references/arkts-v1-v2-migration-rendering-control-repeat.md`

## 核心差异

| 特性 | V1 | V2 |
|------|----|----|
| 观测深度 | `@State`可观测第一层属性 | `@Local`只观测本身，需`@ObservedV2`+`@Trace`深度观测 |
| 初始化 | `@State`支持外部初始化 | `@Local`禁止外部初始化，需用`@Param @Once` |
| 双向绑定 | `@Link`内置双向同步 | 无内置，需`@Param`+`@Event`手动实现 |
| 参数传递 | `@Prop`可本地修改 | `@Param`只读，修改需`@Once`或`@Event` |

## 迁移工作流程

### 阶段一：环境准备
1. **版本检查** - 确认API版本≥12，低于api12需先升级版本
2. **依赖评估** - 确认三方库兼容性
3. **备份代码** - 创建迁移前备份分支

### 阶段二：代码分析
1. **扫描装饰器** - 使用grep扫描`@Component|@State|@Prop|@Link|@Observed|@ObjectLink|@Provide|@Consume|@Watch|@Reusable|@StorageLink|@StorageProp|@LocalStorageLink|@LocalStorageProp`
2. **识别组件** - 列出所有使用V1装饰器的组件文件
3. **分析依赖** - 识别组件间的父子关系和数据流向
4. **生成清单** - 按文件生成迁移清单

### 阶段三：制定计划
1. **优先级排序** - 叶子组件优先，逐层向上迁移
2. **批次划分** - 按功能模块分批次迁移
3. **风险评估** - 识别混用风险点

### 阶段四：执行迁移（按类型顺序）

#### 4.1 组件装饰器迁移
```
@Entry保持不变
@Component → @ComponentV2
@State → @Local
@Prop → @Param // 狐疑@Params要给初始值，或者给@Require
@Link → @Param + @Event
```
> 参考：`references/arkts-v1-v2-migration-inner-component.md`

#### 4.2 数据对象迁移
```
@Observed → @ObservedV2
@ObjectLink → @ObservedV2 + @Trace
@Track → @Trace
```
> 参考：`references/arkts-v1-v2-migration-inner-class.md`

#### 4.3 跨组件状态迁移
```
@Provide/@Consume → @Provider/@Consumer
@Watch → @Monitor
```
> 参考：`references/arkts-v1-v2-migration-inner-component.md`

#### 4.4 应用级状态迁移
```
LocalStorage → @ObservedV2单例
@LocalStorageLink → @Local + 单例引用
@LocalStorageProp → @Local + @Monitor
AppStorage → AppStorageV2
@StorageLink → 参考`references/arkts-v1-v2-migration-application.md`中的storageLink迁移
@StorageProp → 参考`references/arkts-v1-v2-migration-application.md`中的storageProp迁移
PersistentStorage → PersistenceV2
Environment → UIAbilityContext.config
```
> 参考：`references/arkts-v1-v2-migration-application.md`

#### 4.5 渲染控制迁移
```
ForEach → Repeat
LazyForEach → Repeat + .virtualScroll()
```
> 参考：`references/arkts-v1-v2-migration-rendering-control-repeat.md`

#### 4.6 组件复用迁移
```
@Reusable → @ReusableV2
```
> 参考：`references/arkts-v1-v2-migration-reusable.md`

### 阶段五：特殊场景处理

#### 滚动组件内置对象
List/WaterFlow的`ChildrenMainSize`/`WaterFlowSections`需用`UIUtils.makeObserved()`包装：
```typescript
import { UIUtils } from '@kit.ArkUI';
listChildrenSize = UIUtils.makeObserved(new ChildrenMainSize(100));
```
> 参考：`references/arkts-v1-v2-migration-inner-object.md`

#### animateTo兼容
V2中animateTo前的状态修改可能不生效，需用`UIUtils.applySync()`：
```typescript
import { UIUtils } from '@kit.ArkUI';
UIUtils.applySync(() => { this.w = 100; });
this.getUIContext().animateTo({ duration: 1000 }, () => { this.w = 200; });
```
> 参考：`references/arkts-v1-v2-migration-animateTo.md`

#### 双向绑定
`$$`语法替换为`!!`
> 参考：`references/arkts-v1-v2-migration-inner-component.md`

### 阶段六：验证测试
1. **编译检查** - 确保无语法错误
2. **功能测试** - 验证组件交互正常
3. **性能测试** - 检查渲染性能
4. **回归测试** - 全功能覆盖验证

## 详细迁移指南

### 按迁移阶段查阅

| 迁移阶段 | 参考文档 | 核心内容 |
|---------|----------|---------|
| **阶段一：环境准备** | `references/arkts-v1-v2-migration.md` | V1/V2差异对比、API版本要求、混用规则 |
| **阶段四：执行迁移** | | |
| 4.1 组件装饰器 | `references/arkts-v1-v2-migration-inner-component.md` | @State/@Prop/@Link/@Provide/@Consume/@Watch迁移完整示例 |
| 4.2 数据对象 | `references/arkts-v1-v2-migration-inner-class.md` | @Observed/@ObjectLink/@Track → @ObservedV2/@Trace，嵌套对象观测 |
| 4.4 应用级状态 | `references/arkts-v1-v2-migration-application.md` | LocalStorage/AppStorage/PersistentStorage/Environment完整示例 |
| 4.5 渲染控制 | `references/arkts-v1-v2-migration-rendering-control-repeat.md` | ForEach/LazyForEach → Repeat，数据更新、拖拽排序 |
| 4.6 组件复用 | `references/arkts-v1-v2-migration-reusable.md` | @Reusable → @ReusableV2，aboutToReuse变化 |
| **阶段五：特殊场景** | | |
| 内置对象 | `references/arkts-v1-v2-migration-inner-object.md` | List/WaterFlow滚动组件、Modifier迁移、makeObserved用法 |
| animateTo | `references/arkts-v1-v2-migration-animateTo.md` | V2中animateTo兼容问题、applySync用法 |

### 文档查阅建议

**首次迁移**：按顺序阅读所有文档，建立整体认知

**快速查阅**：
- 组件迁移问题 → `inner-component.md`
- 嵌套对象观测 → `inner-class.md`
- 滚动列表异常 → `inner-object.md` + `rendering-control-repeat.md`
- 动画不生效 → `animateTo.md`
- 状态持久化 → `application.md`

## 关键注意事项

### 初始值
`@Param` 和 `@Consumer` 需要有初始值：
```typescript
@Consumer('navPathStack') navPathStack: NavPathStack = new NavPathStack();
@Param todo: Todo = new Todo();
```
无法给初始值时，使用`@Require`装饰器：
```typescript
@Require @Consumer('navPathStack') navPathStack: NavPathStack;
@Require @Param todo: Todo;
```

### 观测能力差异
- V1的`@State`可观测第一层属性
- V2的`@Local`只观测本身，需配合`@ObservedV2`+`@Trace`实现深度观测

## 迁移检查清单

- [ ] `@Component` → `@ComponentV2`
- [ ] `@State` → `@Local` 或 `@Param @Once`
- [ ] `@Prop` → `@Param`
- [ ] `@Link` → `@Param` + `@Event`
- [ ] `@Observed/@ObjectLink` → `@ObservedV2/@Trace`
- [ ] `@Provide/@Consume` → `@Provider/@Consumer`
- [ ] `@Watch` → `@Monitor`
- [ ] `@Reusable` → `@ReusableV2`
- [ ] `LocalStorage` → `@ObservedV2`单例
- [ ] `@LocalStorageLink` → `@Local` + 单例引用
- [ ] `@LocalStorageProp` → `@Local` + `@Monitor`
- [ ] `PersistentStorage` → `PersistenceV2`
- [ ] `ForEach` → `Repeat`
- [ ] `LazyForEach` → `Repeat` + `.virtualScroll()`
- [ ] `$$` → `!!`
- [ ] 滚动组件内置对象使用`makeObserved`
- [ ] animateTo前的状态修改使用`applySync`

## 参考资料

1、Appstorev2的使用：[AppStorageV2: 应用全局UI状态存储-管理应用拥有的状态-状态管理（V2）-学习UI范式状态管理-UI开发 (ArkTS声明式开发范式)-ArkUI（方舟UI框架）-应用框架 - 华为HarmonyOS开发者](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-new-appstoragev2)