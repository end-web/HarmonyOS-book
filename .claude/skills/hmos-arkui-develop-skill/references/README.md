# ArkTS UI 开发知识树

## 目录结构（13个模块）

```
reference/
├── 01-basic-development/          # 基础开发
│   ├── declarative-ui.md
│   ├── custom-components.md
│   ├── rendering-control.md
│   ├── common-attribute.md
│   ├── resource-usage.md
│   └── visual-effects.md
├── 02-state-management/           # 状态管理
│   ├── v1-state-management.md
│   ├── v2-state-management.md
│   ├── app-state-management.md
│   ├── best-practices.md
│   └── README.md
├── 03-layout/                     # 布局开发
│   ├── basic-layout.md
│   └── scroll-container/
│       ├── list.md
│       ├── grid.md
│       └── waterflow.md
├── 04-ui-components/              # UI组件
│   ├── ui-components.md
│   └── text-handling.md
├── 05-animation/                  # 动画
│   ├── animation.md
│   └── transition-animation.md
├── 06-events-interaction/         # 事件与交互
│   ├── events-interaction.md
│   └── gesture-interaction.md
├── 07-dialogs/                    # 弹窗与模态
│   ├── dialogs-menus.md
│   └── modals-pages.md
├── 08-navigation-routing/         # 导航路由
│   ├── navigation-routing.md
│   └── tabs.md
├── 09-custom-nodes/               # 自定义节点
│   ├── custom-capabilities.md
│   ├── custom-node.md
│   ├── custom-rendering.md
│   └── graphics-drawing.md
├── 10-common-ui-func/             # UI通用功能
│   └── uicontext.md
├── 11-i18n-adaptation/            # 国际化与适配
│   ├── internationalization.md
│   ├── accessibility.md
│   └── theming-adaptation.md
├── 12-stability-performance/      # 稳定性与性能
│   ├── stability.md
│   └── debugging-performance.md
└── 13-mvvm-architecture/          # MVVM架构
    └── MVVM_Architecture_Guide.md
```

## 模块概览

| 模块 | 说明 | 核心内容 |
|-----|------|---------|
| 基础开发 | 开发基础 | 声明式UI、自定义组件、渲染控制、通用属性、资源访问、视觉效果 |
| 状态管理 | 数据驱动UI | V1/V2装饰器、应用级状态管理、最佳实践 |
| 布局开发 | 界面布局 | 基础布局、List/Grid/WaterFlow滚动容器 |
| UI组件 | 组件使用 | 基础组件、高级组件、文本处理 |
| 动画 | 视觉效果 | 属性动画、转场动画 |
| 事件与交互 | 用户交互 | 点击、触摸、手势事件 |
| 弹窗与模态 | 弹出内容 | Dialog、Menu、Popup、模态页面 |
| 导航路由 | 页面导航 | Navigation、NavPathStack、Tabs |
| 自定义节点 | 底层定制 | 自定义能力、FrameNode、RenderNode、图形绘制 |
| UI通用功能 | 上下文管理 | UIContext、PromptAction、Router、OverlayManager |
| 国际化与适配 | 多语言适配 | 国际化、可访问性、主题换肤 |
| 稳定性与性能 | 质量保障 | 崩溃问题、性能优化、调试技巧 |
| MVVM架构 | 架构模式 | Model-View-ViewModel、工程目录结构、最佳实践 |

## 快速查找

### 按场景查找

| 场景 | 推荐模块 |
|-----|---------|
| 创建页面 | 基础开发 → 导航路由 |
| 数据驱动UI | 状态管理 |
| 界面布局 | 布局开发 |
| 列表/网格展示 | 布局开发 → scroll-container |
| 使用组件 | UI组件 |
| 添加动画 | 动画 |
| 用户交互 | 事件与交互 |
| 提示反馈 | 弹窗与模态 |
| 底层定制 | 自定义节点 |
| 多语言适配 | 国际化与适配 |
| 资源访问、$r、$rawfile | 基础开发 → resource-usage |
| 性能优化 | 稳定性与性能 |
| 项目架构 | MVVM架构 |

### 按组件查找

| 组件 | 模块 |
|-----|------|
| Row/Column/Flex | 布局开发 → basic-layout |
| Stack/RelativeContainer | 布局开发 → basic-layout |
| List | 布局开发 → scroll-container/list |
| Grid | 布局开发 → scroll-container/grid |
| WaterFlow | 布局开发 → scroll-container/waterflow |
| Navigation/Tabs | 导航路由 |

### 按装饰器查找

| 装饰器 | 模块 |
|-------|------|
| @Component/@ComponentV2 | 基础开发 |
| @Builder/@BuilderParam | 基础开发 |
| @State/@Local/@Param | 状态管理 |
| @Observed/@ObservedV2 | 状态管理 |
| @Watch/@Monitor | 状态管理 |

---

**统计**：13个模块，36个文件