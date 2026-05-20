# 模态页面

## 模态概述

模态转场是新的界面覆盖在旧的界面上，旧的界面不消失的一种转场方式。模态页面允许部分底层父视图可见，帮助用户在与模态交互时保留其父视图环境。

### 模态类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| bindSheet | 半模态页面 | 展示简单的任务或信息面板 |
| bindContentCover | 全屏模态页面 | 需要完全覆盖底层内容的场景 |

---

## 半模态页面（bindSheet）

半模态页面默认是模态形式的非全屏弹窗式交互页面，允许部分底层父视图可见。

### 使用场景

半模态页面适用于展示简单的任务或信息面板，例如：
- 个人信息
- 文本简介
- 分享面板
- 创建日程
- 添加内容

### 基本使用

```typescript
@Entry
@Component
struct SheetDemo {
  @State isShowSheet: boolean = false;

  @Builder
  SheetBuilder() {
    Column() {
      Text('Sheet Content')
        .fontSize(20)
        .margin({ top: 20 })
      Button('Close')
        .margin({ top: 20 })
        .onClick(() => {
          this.isShowSheet = false;
        })
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }

  build() {
    Column() {
      Button('Open Sheet')
        .onClick(() => {
          this.isShowSheet = true;
        })
        .width('90%')
        .height('50vp')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .bindSheet($$this.isShowSheet, this.SheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      title: { title: '半模态标题' }
    })
  }
}
```

#### SheetSize 枚举

| 值 | 说明 |
|------|------|
| MEDIUM | 中等高度 |
| LARGE | 大高度 |
| FIT_CONTENT | 适应内容高度 |

#### SheetType 枚举

| 值 | 说明 |
|------|------|
| BOTTOM | 底部弹出 |
| POPUP | 弹出窗口 |

#### SheetOptions 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| detents | SheetSize \| Array\<SheetSize \| Length\> | 半模态高度档位 |
| preferType | SheetType | 半模态样式 |
| showClose | boolean \| IconOptions | 是否显示关闭按钮 |
| dragBar | boolean | 是否显示拖拽条 |
| backgroundColor | ResourceColor | 背景颜色 |
| maskColor | ResourceColor | 遮罩颜色 |
| blurStyle | BlurStyle | 背景模糊样式 |
| title | SheetTitleOptions | 标题配置 |
| subtitle | ResourceStr | 副标题 |
| enableOutsideInteractive | boolean | 点击遮罩层是否关闭 |
| shouldDismiss | (sheetDismiss: SheetDismiss) => void | 关闭前回调 |
| onWillAppear | () => void | 显示动画开始前回调 |
| onAppear | () => void | 显示动画结束后回调 |
| onWillDisappear | () => void | 消失动画开始前回调 |
| onDisappear | () => void | 消失动画结束后回调 |

---

### 生命周期

半模态页面提供了生命周期函数，用于通知用户该弹窗的生命周期状态。

| 名称 | 说明 |
|------|------|
| onWillAppear | 半模态页面显示（动画开始前）回调函数 |
| onAppear | 半模态页面显示（动画结束后）回调函数 |
| onWillDisappear | 半模态页面回退（动画开始前）回调函数 |
| onDisappear | 半模态页面回退（动画结束后）回调函数 |

触发顺序：onWillAppear -> onAppear -> onWillDisappear -> onDisappear

---

### 嵌套滚动交互

在半模态面板内容区域滑动时的操作优先级：

#### 内容处于最顶部（内容不可滚动时以此状态处理）

- 上滑时，优先向上扩展面板挡位，如无挡位可扩展，则滚动内容
- 下滑时，优先向下收缩面板挡位，如无挡位可收缩，则关闭面板

#### 内容处于中间位置（可上下滚动）

- 上/下滑时，优先滚动内容，直至页面内容到达底部/顶部

#### 内容处于底部位置（内容可滚动时）

- 上滑时，呈现内容区域回弹效果，不切换挡位
- 下滑时，滚动内容直到到达顶部

#### 设置嵌套滚动

```typescript
@Builder
SheetBuilder() {
  Column() {
    List({ space: '10vp' }) {
      ForEach(this.items, (item: number) => {
        ListItem() {
          Text(String(item))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
        }
        .width('90%')
        .height('80vp')
        .backgroundColor('#ff53ecd9')
        .borderRadius(10)
      })
    }
    .width('100%')
    .height('900px')
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST,
    })
  }
  .width('100%')
  .height('100%')
}
```

---

### 二次确认能力

推荐使用onWillDismiss接口，此接口支持在回调中处理二次确认，或自定义关闭行为。

```typescript
.bindSheet($$this.isShow, this.myBuilder(), {
  height: SheetSize.MEDIUM,
  dragBar: true,
  onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
    this.getUIContext().showAlertDialog({
      message: '是否需要关闭半模态？',
      primaryButton: {
        value: 'cancel',
        action: () => {
          console.info('Cancel clicked');
        }
      },
      secondaryButton: {
        value: 'ok',
        action: () => {
          dismissSheetAction.dismiss();
        }
      }
    })
  })
})
```

#### DismissReason 枚举

| 值 | 说明 |
|------|------|
| SLIDE_DOWN | 下滑关闭 |
| TOUCH_OUTSIDE | 点击遮罩层关闭 |
| CLOSE_BUTTON | 点击关闭按钮 |
| BACK_PRESS | 返回键关闭 |

#### 屏蔽部分关闭行为

```typescript
onWillDismiss: ((DismissSheetAction: DismissSheetAction) => {
  if (DismissSheetAction.reason === DismissReason.SLIDE_DOWN) {
    DismissSheetAction.dismiss();
  }
})
```

---

## 全屏模态（bindContentCover）

全屏模态用于完全覆盖底层内容，适用于需要完全沉浸式的交互场景。

### 基本使用

```typescript
@Entry
@Component
struct ContentCoverDemo {
  @State isCoverVisible: boolean = false;

  @Builder
  coverContent() {
    Column() {
      Text('Full Screen Content')
        .fontSize(24)
        .margin({ top: 50 })
      Button('Close')
        .margin({ top: 20 })
        .onClick(() => {
          this.isCoverVisible = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      Button('Show Cover')
        .onClick(() => {
          this.isCoverVisible = true;
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .bindContentCover($$this.isCoverVisible, this.coverContent(), {
      modalTransition: ModalTransition.DEFAULT,
      backgroundColor: Color.White
    })
  }
}
```

#### ModalTransition 枚举

| 值 | 说明 |
|------|------|
| DEFAULT | 默认动画 |
| NONE | 无动画 |
| ALPHA | 透明度动画 |

#### ContentCoverOptions 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| modalTransition | ModalTransition | 转场动画类型 |
| backgroundColor | ResourceColor | 背景颜色 |
| maskColor | ResourceColor | 遮罩颜色 |
| transition | TransitionEffect | 进出场动画效果 |
| onWillAppear | () => void | 显示动画开始前回调 |
| onAppear | () => void | 显示动画结束后回调 |
| onWillDisappear | () => void | 消失动画开始前回调 |
| onDisappear | () => void | 消失动画结束后回调 |

---

## 模态转场动画

### bindSheet 转场动画

```typescript
.bindSheet($$this.isSheetVisible, this.sheetContent(), {
  height: SheetSize.MEDIUM,
  animationDuration: 300,
  dragBar: true,
  showClose: true,
  shouldDismiss: ((sheetDismiss: SheetDismiss) => {
    sheetDismiss.dismiss();
  })
})
```

### bindContentCover 转场动画

```typescript
.bindContentCover($$this.isCoverVisible, this.coverContent(), {
  modalTransition: ModalTransition.DEFAULT,
  backgroundColor: Color.White,
  transition: TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: 1000 }))
    .animation({ curve: curves.springMotion(0.6, 0.8) })
})
```

---

## 半模态避让中轴

半模态从API version 14开始支持中轴避让，当前在2in1设备默认开启（仅窗口处于瀑布模式时产生避让）。

### enableHoverMode

开发者可以通过enableHoverMode属性主动设置是否避让中轴。

### hoverModeArea

开发者可以通过hoverModeArea属性设置避让中轴后显示区域。

```typescript
.bindSheet($$this.isShow, this.myBuilder(), {
  enableHoverMode: true,
  hoverModeArea: HoverModeAreaType.TOP_SCREEN
})
```

### HoverModeAreaType 枚举

| 值 | 说明 |
|------|------|
| TOP_SCREEN | 上半屏 |
| BOTTOM_SCREEN | 下半屏 |

---

## 模态层级

### levelOrder

从API version 18开始，可以通过设置levelOrder参数来管理模态的显示顺序。

```typescript
.bindSheet($$this.isShow, this.myBuilder(), {
  levelOrder: 1
})
```

### SubSheetLevel 枚举

| 值 | 说明 |
|------|------|
| EMBEDDED | 嵌入层级 |
| OVERLAY | 覆盖层级 |

---

## 页面级模态

页面级模态是指模态跟随导航页面切换时，可以被跳转的页面覆盖，随着页面切回原页面，模态仍然正常显示。

### 配置页面级模态

```typescript
.bindSheet($$this.isSheetVisible, this.sheetContent(), {
  height: SheetSize.MEDIUM,
  pageLevel: true
})
```

---

## 使用约束

1. 半模态内嵌UIExtension时，不支持再在UIExtension内拉起半模态/弹窗
2. 若无二次确认或者自定义关闭行为的场景，不建议使用shouldDismiss/onWillDismiss接口
3. 对于复杂或者冗长的用户流程，建议考虑其他的转场方式替代半模态

---

## 场景选择

| 场景 | 推荐方案 |
|------|----------|
| 简单的任务或信息面板 | bindSheet 半模态 |
| 需要完全沉浸式的交互 | bindContentCover 全屏模态 |
| 复杂的用户流程 | Navigation转场 |
| 缩略图点击查看大图 | bindContentCover |

---

## 相关链接

- [弹窗与菜单](dialogs-menus.md)
- [转场动画](../05-animation/transition-animation.md)
- [导航路由](../08-navigation-routing/navigation-routing.md)