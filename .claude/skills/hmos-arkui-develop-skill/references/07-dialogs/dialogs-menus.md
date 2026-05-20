# 弹窗与菜单

## 弹窗概述

弹窗一般指打开应用时自动弹出或者用户行为操作时弹出的UI界面，用于短时间内展示用户需关注的信息或待处理的操作。

### 弹窗的种类

根据用户交互操作场景，弹窗可分为**模态弹窗**和**非模态弹窗**两种类型：

- **模态弹窗**：强交互形式，会中断用户当前的操作流程，要求用户必须做出响应才能继续其他操作
- **非模态弹窗**：弱交互形式，不会影响用户当前操作行为，用户可以不对其进行回应

### 弹窗类型

| 弹窗名称 | 应用场景 |
|----------|----------|
| 弹出框（Dialog） | 当需要展示用户当前需要或必须关注的信息内容或操作时 |
| 菜单（Menu） | 当需要给用户提供可执行的操作时 |
| 气泡提示（Popup） | 当需要给用户提供提示时 |
| 即时反馈（Toast） | 当需要在一个小的窗口中提供用户当前操作的简单反馈时 |

---

## 警告弹窗（AlertDialog）

警告弹窗通常用来展示用户当前需要或必须关注的信息或操作。如用户操作一个敏感行为时响应一个二次确认的弹出框。

### 基本使用

```typescript
this.getUIContext().showAlertDialog({
  title: '提示',
  message: '确定要删除吗？',
  primaryButton: {
    value: '取消',
    action: () => {
      console.info('Cancel clicked');
    }
  },
  secondaryButton: {
    value: '确定',
    action: () => {
      console.info('Confirmed');
    }
  }
});
```

### AlertDialog 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| title | ResourceStr | 标题 |
| message | ResourceStr | 内容 |
| autoCancel | boolean | 点击遮障层是否关闭弹窗 |
| alignment | DialogAlignment | 弹窗在竖直方向上的对齐方式 |
| gridCount | number | 弹窗宽度所占用栅格数 |
| offset | Offset | 弹窗相对alignment位置的偏移量 |
| primaryButton | ButtonInfo | 主按钮 |
| secondaryButton | ButtonInfo | 从按钮 |
| cancel | () => void | 点击遮障层关闭弹窗时的回调 |
| isModal | boolean | 是否模态弹窗 |

### 按钮样式

```typescript
this.getUIContext().showAlertDialog({
  title: '提示',
  message: '确定要删除吗？',
  primaryButton: {
    value: '取消',
    action: () => {}
  },
  secondaryButton: {
    enabled: true,
    defaultFocus: true,
    style: DialogButtonStyle.HIGHLIGHT,
    value: '确定',
    action: () => {}
  }
});
```

### DialogButtonStyle 枚举

| 值 | 说明 |
|------|------|
| DEFAULT | 默认样式 |
| HIGHLIGHT | 高亮样式 |

---

## 列表选择弹窗（ActionSheet）

列表选择弹窗用于当用户需要关注或确认的信息存在列表选择时使用。

### 基本使用

```typescript
this.getUIContext().showActionSheet({
  title: '选择操作',
  message: '请选择以下操作之一',
  confirm: {
    value: '取消',
    action: () => {
      console.info('Cancel clicked');
    }
  },
  sheets: [
    { title: '拍照', action: () => {
      console.info('Camera selected');
    }},
    { title: '从相册选择', action: () => {
      console.info('Gallery selected');
    }}
  ]
});
```

### ActionSheet 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| title | ResourceStr | 标题 |
| message | ResourceStr | 内容 |
| autoCancel | boolean | 点击遮障层是否关闭弹窗 |
| alignment | DialogAlignment | 弹窗在竖直方向上的对齐方式 |
| offset | Offset | 弹窗相对alignment位置的偏移量 |
| confirm | ButtonInfo | 确认按钮 |
| sheets | SheetInfo[] | 选项列表 |

### SheetInfo 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| title | ResourceStr | 标题 |
| icon | ResourceStr | 图标 |
| action | () => void | 点击回调 |

---

## 自定义弹窗（CustomDialog）

自定义弹窗用于当用户需要自定义弹出框内的组件和内容时使用。

### 基本使用

```typescript
@CustomDialog
struct CustomDialogExample {
  controller: CustomDialogController;
  message: string = '';

  build() {
    Column() {
      Text(this.message)
        .fontSize(20)
        .margin({ top: 10, bottom: 10 })
      Row() {
        Button('取消')
          .onClick(() => this.controller.close())
          .margin({ right: 10 })
        Button('确定')
          .onClick(() => {
            this.controller.close();
            console.info('Confirmed');
          })
      }
    }
    .padding(20)
  }
}

@Entry
@Component
struct CustomDialogDemo {
  @State dialogController: CustomDialogController = new CustomDialogController({
    builder: CustomDialogExample({ message: 'Custom Message' }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  build() {
    Column() {
      Button('Show Dialog')
        .onClick(() => {
          this.dialogController.open();
        })
    }
  }
}
```

### CustomDialogController 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| builder | CustomDialog | 自定义弹窗内容构造器 |
| autoCancel | boolean | 点击遮障层是否关闭弹窗 |
| alignment | DialogAlignment | 弹窗在竖直方向上的对齐方式 |
| offset | Offset | 弹窗相对alignment位置的偏移量 |
| customStyle | boolean | 弹窗容器样式是否自定义 |
| gridCount | number | 弹窗宽度所占用栅格数 |
| maskColor | ResourceColor | 遮障层颜色 |
| showInSubWindow | boolean | 是否在子窗口显示 |

### DialogAlignment 枚举

| 值 | 说明 |
|------|------|
| Top | 顶部对齐 |
| Center | 居中对齐 |
| Bottom | 底部对齐 |
| TopStart | 左上对齐 |
| TopEnd | 右上对齐 |
| CenterStart | 左中对齐 |
| CenterEnd | 右中对齐 |
| BottomStart | 左下对齐 |
| BottomEnd | 右下对齐 |

---

## 即时反馈（Toast）

即时反馈是一种临时性的消息提示框，用于向用户显示简短的操作反馈或状态信息。它通常在屏幕的底部或顶部短暂弹出，随后在一段时间后自动消失。

### 基本使用

```typescript
this.getUIContext().getPromptAction().showToast({
  message: '操作成功',
  duration: 2000,
  bottom: 100
});
```

### Toast 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| message | string \| Resource | 显示文本 |
| duration | number | 显示时长，单位毫秒 |
| bottom | number \| string | 距离底部的距离 |
| showMode | ToastShowMode | 显示模式 |

### ToastShowMode 枚举

| 值 | 说明 |
|------|------|
| DEFAULT | 显示在应用内 |
| TOP_MOST | 显示在应用之上 |

### 显示模式对比

| 差异点 | DEFAULT | TOP_MOST |
|--------|---------|----------|
| 是否创建子窗 | 否 | 是 |
| 层级 | 显示在主窗内 | 显示在子窗中，比主窗层级高 |
| 是否避让软键盘 | 软键盘抬起时，必定上移 | 只有被遮挡时才避让 |

### 显示和关闭Toast

```typescript
@Entry
@Component
struct OpenCloseToastExample {
  @State toastId: number = 0;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  build() {
    Column() {
      Button('Open Toast')
        .onClick(() => {
          this.promptAction.openToast({
            message: 'Toast Message',
            duration: 10000,
          }).then((toastId: number) => {
            this.toastId = toastId;
          });
        })
      
      Button('Close Toast')
        .onClick(() => {
          this.promptAction.closeToast(this.toastId);
        })
    }
  }
}
```

### 使用建议

- 合理使用弹出场景，避免过度提醒用户
- 注意文本的信息密度，即时反馈展示时间有限，应当避免长文本的出现
- 杜绝强制占位和密集弹出的提示
- 遵从系统默认弹出位置
- 即时反馈中，字体的最大放大倍数为2

---

## 加载进度弹窗

### 显示加载中

```typescript
this.getUIContext().getPromptAction().showLoading({
  message: '加载中...',
  duration: 5000
});
```

### 隐藏加载中

```typescript
this.getUIContext().getPromptAction().dismissLoading();
```

### showLoading 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| message | string \| Resource | 显示文本 |
| duration | number | 显示时长，单位毫秒 |

---

## 气泡提示（Popup）

气泡提示可绑定在组件上显示气泡弹窗提示，设置弹窗内容、交互逻辑和显示状态。主要用于屏幕录制、信息弹出提醒等显示状态。

### 文本提示气泡

```typescript
@Entry
@Component
struct TextPopupExample {
  @State handlePopup: boolean = false;

  build() {
    Column() {
      Button('PopupOptions')
        .onClick(() => {
          this.handlePopup = !this.handlePopup;
        })
        .bindPopup(this.handlePopup, {
          message: 'This is a popup with PopupOptions',
        })
    }
  }
}
```

### 带按钮的提示气泡

```typescript
@Entry
@Component
struct ButtonPopupExample {
  @State handlePopup: boolean = false;

  build() {
    Column() {
      Button('PopupOptions')
        .onClick(() => {
          this.handlePopup = !this.handlePopup;
        })
        .bindPopup(this.handlePopup, {
          message: 'This is a popup with PopupOptions',
          primaryButton: {
            value: 'Confirm',
            action: () => {
              this.handlePopup = !this.handlePopup;
            }
          },
          secondaryButton: {
            value: 'Cancel',
            action: () => {
              this.handlePopup = !this.handlePopup;
            }
          },
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.handlePopup = false;
            }
          }
        })
    }
  }
}
```

### 自定义气泡

```typescript
@Entry
@Component
struct CustomPopupExample {
  @State customPopup: boolean = false;

  @Builder
  popupBuilder() {
    Row({ space: 2 }) {
      Image($r('app.media.app_icon'))
        .width(24)
        .height(24)
        .margin({ left: 5 })
      Text('This is Custom Popup')
        .fontSize(15)
    }
    .width(200)
    .height(50)
    .padding(5)
  }

  build() {
    Column() {
      Button('CustomPopupOptions')
        .onClick(() => {
          this.customPopup = !this.customPopup;
        })
        .bindPopup(this.customPopup, {
          builder: this.popupBuilder,
          placement: Placement.Bottom,
          popupColor: Color.Pink,
          backgroundBlurStyle: BlurStyle.NONE,
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.customPopup = false;
            }
          }
        })
    }
  }
}
```

### PopupOptions 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| message | string | 显示内容 |
| placement | Placement | 弹出位置 |
| mask | boolean \| ResourceColor | 是否显示遮罩 |
| arrowOffset | Length | 箭头偏移 |
| showInSubWindow | boolean | 是否在子窗口显示 |
| primaryButton | PopupButtonOptions | 主按钮 |
| secondaryButton | PopupButtonOptions | 从按钮 |
| onStateChange | Callback\<PopupStateChangeInfo\> | 状态变化回调 |
| transition | TransitionEffect | 进出场动画效果 |

### Placement 枚举

| 值 | 说明 |
|------|------|
| Top | 顶部 |
| Bottom | 底部 |
| Left | 左侧 |
| Right | 右侧 |
| TopLeft | 左上 |
| TopRight | 右上 |
| BottomLeft | 左下 |
| BottomRight | 右下 |

### 气泡动画

```typescript
.bindPopup(this.handlePopup, {
  message: 'This is a popup with transitionEffect',
  placement: Placement.Top,
  showInSubWindow: false,
  onStateChange: (e) => {
    if (!e.isVisible) {
      this.handlePopup = false;
    }
  },
  transition: TransitionEffect.asymmetric(
    TransitionEffect.OPACITY.animation({ duration: 1000, curve: Curve.Ease }).combine(
      TransitionEffect.translate({ x: 50, y: 50 })),
    TransitionEffect.IDENTITY)
})
```

---

## 菜单（Menu）

菜单一般用于鼠标右键弹窗、点击弹窗等。

### 创建默认样式的菜单

```typescript
Button('click for Menu')
  .bindMenu([
    {
      value: 'Menu1',
      action: () => {
        console.info('handle Menu1 select');
      }
    },
    {
      value: 'Menu2',
      action: () => {
        console.info('handle Menu2 select');
      }
    }
  ])
```

### 创建自定义样式的菜单

```typescript
@Entry
@Component
struct BuilderCustomMenuExample {
  @Builder
  SubMenu() {
    Menu() {
      MenuItem({ content: '复制', labelInfo: 'Ctrl+C' })
      MenuItem({ content: '粘贴', labelInfo: 'Ctrl+V' })
    }
  }

  @Builder
  MyMenu() {
    Menu() {
      MenuItem({ startIcon: $r('app.media.icon'), content: '菜单选项' })
      MenuItem({ startIcon: $r('app.media.icon'), content: '菜单选项' })
        .enabled(false)
      MenuItem({
        startIcon: $r('app.media.icon'),
        content: '菜单选项',
        endIcon: $r('app.media.arrow_right_filled'),
        builder: this.SubMenu
      })
      MenuItemGroup({ header: '小标题' }) {
        MenuItem({ content: '菜单选项' })
          .selectIcon(true)
          .selected(this.select)
          .onChange((selected) => {
            console.info('menuItem select' + selected);
          })
      }
    }
  }

  build() {
    Column() {
      Button('click for Menu')
        .bindMenu(this.MyMenu)
    }
  }
}
```

### 右键或长按菜单

```typescript
Button('Right-click for Menu')
  .bindContextMenu(this.MyMenu, ResponseType.RightClick)
```

### ResponseType 枚举

| 值 | 说明 |
|------|------|
| LongPress | 长按触发 |
| RightClick | 右键触发 |

### 菜单参数

| 参数 | 类型 | 说明 |
|------|------|------|
| title | MenuTitleOptions | 标题 |
| icon | ResourceStr | 图标 |
| iconSize | Dimension | 图标尺寸 |
| symbolIcon | SymbolGlyphModifier | Symbol图标 |
| enableArrow | boolean | 是否显示箭头 |
| placement | Placement | 菜单弹出位置 |
| onAppear | () => void | 显示回调 |
| onDisappear | () => void | 消失回调 |

---

## 弹窗层级管理

从API version 18开始，可以通过设置levelOrder参数来管理弹出框的显示顺序。

多个弹窗组件先后弹出时，后弹出的组件的层级高于先弹出的层级，退出时按照层级从高到低的顺序逐次退出。

---

## 规格约束

1. 建议使用UIContext中的弹出框方法
2. 由于系统安全管控原因，当弹出系统权限弹窗等场景时，弹出框在此状态下无法显示
3. 不建议在非前台状态下，调用弹窗显示接口
4. 系统弹窗由系统弹出，出于安全考虑，不支持自定义样式

---

## 相关链接

- [模态页面](modals-pages.md)
- [转场动画](../05-animation/transition-animation.md)