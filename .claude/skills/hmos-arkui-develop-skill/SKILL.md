---
name: hmos-arkui-develop-skill
description: 编写、审查或改进ArkUI代码，遵循状态管理(V1/V2)、组件结构、布局选择、性能优化的最佳实践。触发场景：构建新页面或组件、实现状态管理、开发布局(列表/网格/瀑布流)、添加动画手势、搭建导航路由、处理弹窗模态、MVVM架构设计、V1迁移V2。
---

# ArkUI 开发技能

## 操作规则

- 新项目优先使用V2装饰器（@Local、@Param、@Event、@ObservedV2/@Trace）
- V1项目可继续使用V1装饰器，仅在需要时迁移
- 不强制架构模式 - 复杂应用用MVVM，简单需求用简单结构
- 性能从一开始就很重要 - 使用LazyForEach/Repeat，最小化更新
- 保持组件专注和可测试 - 小型、单一职责
- 遵循ArkUI约定 - 使用原生API
- 同一组件中不混用V1和V2装饰器
- 可维护性优于炫技 - 清晰胜过简洁

## 任务工作流程

### 审查现有ArkUI代码

- 阅读待审查代码，识别相关主题
- 检查状态装饰器使用是否正确（参考 `references/02-state-management/v2-state-management.md`）
- 验证组件结构是否符合最佳实践
- 检查布局组件选择是否恰当
- 验证列表模式是否使用正确的标识（不用index作为key）
- 检查性能优化模式是否应用

### 改进现有ArkUI代码

- 审计状态管理的装饰器选择（新代码优先使用V2）
- 适当时将V1装饰器替换为V2等价物
- 将复杂UI提取为可复用组件
- 使用LazyForEach或Repeat优化列表渲染
- 代码变得复杂时建议MVVM结构
- 改进动画性能

### 实现新的ArkUI功能

- 先设计数据流：识别组件状态与共享状态
- 选择合适的布局组件
- 采用Navigation作为导航结构
- 组织组件结构以保持可维护性
- 复杂功能应用MVVM架构
- 从一开始就考虑性能

## 主题路由

根据当前任务查阅相关参考文档：

| 主题 | 参考文档 |
|------|----------|
| V2状态管理 | `references/02-state-management/v2-state-management.md` |
| V1状态管理 | `references/02-state-management/v1-state-management.md` |
| 应用级状态管理 | `references/02-state-management/app-state-management.md` |
| 状态管理最佳实践 | `references/02-state-management/best-practices.md` |
| 自定义组件 | `references/01-basic-development/custom-components.md` |
| 声明式UI | `references/01-basic-development/declarative-ui.md` |
| 渲染控制 | `references/01-basic-development/rendering-control.md` |
| 资源使用 | `references/01-basic-development/resource-usage.md` |
| 通用属性 | `references/01-basic-development/common-attribute.md` |
| 视觉效果 | `references/01-basic-development/visual-effects.md` |
| 基础布局 | `references/03-layout/basic-layout.md` |
| List列表 | `references/03-layout/scroll-container/list.md` |
| Grid网格 | `references/03-layout/scroll-container/grid.md` |
| WaterFlow瀑布流 | `references/03-layout/scroll-container/waterflow.md` |
| UI组件 | `references/04-ui-components/ui-components.md` |
| 文本处理 | `references/04-ui-components/text-handling.md` |
| 动画基础 | `references/05-animation/animation.md` |
| 转场动画 | `references/05-animation/transition-animation.md` |
| 事件交互 | `references/06-events-interaction/events-interaction.md` |
| 手势交互 | `references/06-events-interaction/gesture-interaction.md` |
| 弹窗菜单 | `references/07-dialogs/dialogs-menus.md` |
| 模态页面 | `references/07-dialogs/modals-pages.md` |
| 导航路由 | `references/08-navigation-routing/navigation-routing.md` |
| 导航完整示例 | `references/08-navigation-routing/navigation-complete-example.md` |
| Tabs标签 | `references/08-navigation-routing/tabs.md` |
| 自定义节点 | `references/09-custom-nodes/custom-node.md` |
| 自定义渲染 | `references/09-custom-nodes/custom-rendering.md` |
| 图形绘制 | `references/09-custom-nodes/graphics-drawing.md` |
| 自定义能力 | `references/09-custom-nodes/custom-capabilities.md` |
| UIContext | `references/10-common-ui-func/uicontext.md` |
| 国际化 | `references/11-i18n-adaptation/internationalization.md` |
| 主题适配 | `references/11-i18n-adaptation/theming-adaptation.md` |
| 无障碍 | `references/11-i18n-adaptation/accessibility.md` |
| 稳定性 | `references/12-stability-performance/stability.md` |
| 调试与性能 | `references/12-stability-performance/debugging-performance.md` |
| MVVM架构 | `references/13-mvvm-architecture/MVVM_Architecture_Guide.md` |

## 正确性检查清单

这些是硬规则 - 违反即为错误：

### 状态管理
- [ ] 新代码使用V2装饰器（@Local、@Param、@Event）
- [ ] @Local用于组件内部状态（V2中替代@State）
- [ ] @Param用于父→子数据传递（只读时不用@Link）
- [ ] @Event用于子→父通信
- [ ] @ObservedV2/@Trace用于深度观测
- [ ] 同一组件中不混用V1和V2装饰器
- [ ] V1: @State必须有默认值初始化
- [ ] V1: @Observed必须配合@ObjectLink使用

### 组件结构
- [ ] 使用@Component或@ComponentV2装饰器
- [ ] @Entry用于页面入口组件
- [ ] build()方法简洁纯净，无副作用
- [ ] 只向子组件传递必要数据
- [ ] 子组件不直接访问父组件

### 列表渲染
- [ ] ForEach仅用于小型静态列表
- [ ] LazyForEach/Repeat用于大量数据列表
- [ ] 列表项使用稳定的key（动态内容绝不用index）
- [ ] 设置cachedCount进行列表预加载

### 导航路由
- [ ] 使用Navigation进行页面管理
- [ ] 使用NavPathStack进行编程式导航
- [ ] 页面间参数通过aboutToAppear接收

## 快速参考

### 状态装饰器选择（V2 - 推荐）

| 装饰器 | 使用场景 |
|--------|----------|
| `@Local` | 组件内部状态（替代@State） |
| `@Param` | 父→子数据传递（只读） |
| `@Param @Once` | 父→子传递，允许本地更新 |
| `@Event` | 子→父通信 |
| `@ObservedV2` | 类需要深度观测 |
| `@Trace` | 标记@ObservedV2类中的可观测属性 |
| `@Provider/@Consumer` | 跨组件状态共享 |
| `@Monitor` | 监听特定属性变化 |
| `@Computed` | 派生/缓存计算值 |

### 状态装饰器选择（V1 - 旧版）

| 装饰器 | 使用场景 |
|--------|----------|
| `@State` | 组件内部状态 |
| `@Prop` | 父→子单向绑定 |
| `@Link` | 父↔子双向绑定 |
| `@Observed/@ObjectLink` | 嵌套对象观测（必须配合使用） |
| `@Provide/@Consume` | 跨组件状态（祖先↔后代） |
| `@Watch` | 观察状态变化 |

### 布局组件选择

| 布局类型 | 组件 | 使用场景 |
|----------|------|----------|
| 线性 | Row/Column | 简单水平/垂直排列 |
| 弹性 | Flex | 弹性尺寸、换行、对齐 |
| 层叠 | Stack | 重叠元素、分层 |
| 相对 | RelativeContainer | 复杂相对定位 |
| 列表 | List | 长列表滚动（使用LazyForEach/Repeat） |
| 网格 | Grid | 规则网格项 |
| 瀑布流 | WaterFlow | 不等高项（Pinterest风格） |
| 标签 | Tabs | 标签导航与内容 |

### 常见模式

**基础组件（V2）**
```typescript
@ComponentV2
struct MyComponent {
  @Local count: number = 0;
  @Param title: string = '';
  @Event onCountChange: (value: number) => void = () => {};

  build() {
    Column() {
      Text(this.title)
      Button(`计数: ${this.count}`)
        .onClick(() => {
          this.count++;
          this.onCountChange(this.count);
        })
    }
  }
}
```

**可观测类（V2）**
```typescript
@ObservedV2
class TaskModel {
  @Trace name: string = '';
  @Trace isDone: boolean = false;
  
  toggle() {
    this.isDone = !this.isDone;
  }
}
```

**MVVM目录结构**
```
src/main/ets/
├── model/           # 数据结构
│   └── TaskModel.ets
├── viewmodel/       # 状态与逻辑
│   └── TaskViewModel.ets
├── view/            # UI组件
│   └── TaskItemView.ets
└── pages/           # 页面入口
    └── TaskPage.ets
```

## 参考文档

### 核心文档
- `references/01-basic-development/custom-components.md` - 组件创建、@Builder、@BuilderParam
- `references/01-basic-development/declarative-ui.md` - 声明式UI语法和基础
- `references/01-basic-development/rendering-control.md` - 条件渲染、ForEach、LazyForEach
- `references/01-basic-development/resource-usage.md` - 资源访问、$r、$rawfile

### 状态管理
- `references/02-state-management/v2-state-management.md` - V2装饰器：@Local、@Param、@Event、@ObservedV2
- `references/02-state-management/v1-state-management.md` - V1装饰器：@State、@Prop、@Link、@Observed
- `references/02-state-management/app-state-management.md` - AppStorage、LocalStorage、PersistentStorage
- `references/02-state-management/best-practices.md` - 状态管理模式与反模式

### 布局
- `references/03-layout/basic-layout.md` - Row、Column、Flex、Stack、RelativeContainer
- `references/03-layout/scroll-container/list.md` - List组件、LazyForEach、Repeat
- `references/03-layout/scroll-container/grid.md` - Grid组件和模式
- `references/03-layout/scroll-container/waterflow.md` - WaterFlow瀑布流布局

### 组件与UI
- `references/04-ui-components/ui-components.md` - 基础和高级组件
- `references/04-ui-components/text-handling.md` - 文本处理和格式化

### 动画与交互
- `references/05-animation/animation.md` - 属性动画、显式动画
- `references/05-animation/transition-animation.md` - 页面和组件转场
- `references/06-events-interaction/events-interaction.md` - 触摸、点击、按键事件
- `references/06-events-interaction/gesture-interaction.md` - 手势识别与处理

### 导航与弹窗
- `references/07-dialogs/dialogs-menus.md` - AlertDialog、ActionSheet、Menu、Popup
- `references/07-dialogs/modals-pages.md` - 模态页面、自定义弹窗
- `references/08-navigation-routing/navigation-routing.md` - Navigation、NavPathStack
- `references/08-navigation-routing/navigation-complete-example.md` - 导航完整示例
- `references/08-navigation-routing/tabs.md` - Tabs组件

### 高级特性
- `references/09-custom-nodes/custom-node.md` - FrameNode、RenderNode自定义
- `references/09-custom-nodes/custom-rendering.md` - 自定义渲染
- `references/09-custom-nodes/graphics-drawing.md` - Canvas、绑图API
- `references/09-custom-nodes/custom-capabilities.md` - 自定义能力
- `references/10-common-ui-func/uicontext.md` - UIContext、路由、overlay

### 质量与架构
- `references/11-i18n-adaptation/internationalization.md` - 国际化
- `references/11-i18n-adaptation/theming-adaptation.md` - 主题换肤
- `references/11-i18n-adaptation/accessibility.md` - 无障碍
- `references/12-stability-performance/stability.md` - 常见问题与解决方案
- `references/12-stability-performance/debugging-performance.md` - 调试与优化
- `references/13-mvvm-architecture/MVVM_Architecture_Guide.md` - MVVM项目结构