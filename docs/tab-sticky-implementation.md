# 首页 Tab 吸顶功能实现说明

## 功能概述

实现了首页搜索结果的 Tab 吸顶效果，当用户向上滑动时，Banner 区域会退出显示区域，Tab 栏会吸附在顶部，方便用户切换内容。

## 实现方案

采用 **Stack + Scroll + 自定义 TabBar** 的方案：

### 1. 布局结构

```
Stack (对齐方式: TopStart)
├── 底层: Scroll (可滚动内容)
│   └── Column
│       ├── Banner 区域 (高度: 120vp)
│       └── Tab 内容区域
│           ├── 占位 TabBar (高度: 48vp)
│           └── Grid 内容 (根据当前 Tab 显示)
│
└── 顶层: 自定义 TabBar (固定位置)
    └── position: { y: isTabBarFixed ? 0 : BANNER_HEIGHT }
```

### 2. 核心逻辑

#### 状态管理
- `scrollOffset`: 记录滚动偏移量
- `isTabBarFixed`: 标记 TabBar 是否固定在顶部
- `BANNER_HEIGHT`: Banner 高度常量 (120vp)
- `TAB_BAR_HEIGHT`: TabBar 高度常量 (48vp)

#### 滚动监听
```typescript
.onScroll((_xOffset: number, yOffset: number) => {
  this.scrollOffset += yOffset;
  this.isTabBarFixed = this.scrollOffset >= this.BANNER_HEIGHT;
})
```

当滚动偏移量超过 Banner 高度时，将 TabBar 固定在顶部。

#### 边缘处理
```typescript
.onScrollEdge((_side: Edge) => {
  if (this.mainScroller.currentOffset().yOffset <= 0) {
    this.scrollOffset = 0;
    this.isTabBarFixed = false;
  }
})
```

当滚动到顶部时，重置状态。

### 3. 组件说明

#### buildBanner()
- 显示 "发现好书" 的推荐区域
- 固定高度 120vp
- 包含标题、描述和图标

#### buildCustomTabBar()
- 自定义 TabBar，包含 "电子书" 和 "有声书" 两个 Tab
- 点击切换 `resultTab` 状态
- 根据当前选中状态显示不同的颜色和字重

#### buildResultGrid()
- 移除了内部的 Scroll 组件
- 直接渲染 Grid 布局
- 保留了双指缩放调整列数的功能

## 技术要点

1. **使用官方 Tabs 组件的替代方案**：由于官方 Tabs 组件不支持吸顶效果，采用自定义 TabBar + Stack 布局实现

2. **滚动性能优化**：
   - 使用单一外层 Scroll，避免嵌套滚动
   - Grid 内容直接渲染，减少层级

3. **动画过渡**：
   - TabBar 位置变化使用 `transition` 实现平滑过渡
   - 透明度动画时长 200ms

4. **状态同步**：
   - 通过 `@Local` 装饰器管理状态
   - 滚动事件实时更新 TabBar 位置

## 相关文件

- [HomePage.ets](../entry/src/main/ets/pages/HomePage.ets) - 首页组件实现
- [module.json5](../entry/src/main/module.json5) - 权限配置修复
- [string.json](../entry/src/main/resources/base/element/string.json) - 权限说明文案

## 参考文档

- [HarmonyOS Tabs 开发场景](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-development-scenarios-for-tabs)
- [ArkUI Scroll 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-container-scroll-V5)
- [ArkUI Stack 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-container-stack-V5)
