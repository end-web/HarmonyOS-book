# UIContext

## 概述

UIContext是与UI实例绑定的上下文对象，用于获取与当前UI实例相关的各种对象和功能。UIContext提供了一种明确UI上下文的方式，解决了在全局接口中UI上下文不明确的问题。

### UIContext的作用

- 明确UI上下文，避免UI上下文不明确导致的问题
- 获取与UI相关的各种管理器对象
- 提供统一的UI能力调用入口

---

## 获取UIContext

### 在组件中获取

```typescript
@Entry
@Component
struct MainPage {
  private uiContext: UIContext = this.getUIContext();

  build() {
    Column() {
      Button('Show Toast')
        .onClick(() => {
          this.uiContext.getPromptAction().showToast({ message: 'Hello' });
        })
    }
  }
}
```

### 在UIAbility中获取

```typescript
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindowSync().getUIContext();
  }
}
```

### 在NodeController中获取

```typescript
class MyNodeController extends NodeController {
  makeNode(uiContext: UIContext): FrameNode | null {
    // 在makeNode回调中获取UIContext
    return new FrameNode(uiContext);
  }
}
```

### isAvailable

判断UIContext对象对应的UI实例是否有效。

```typescript
const ctx: UIContext = this.getUIContext();
const available: boolean = ctx.isAvailable();
// true表示有效，false表示无效
```

---

## 主要功能模块

### PromptAction

创建并显示即时反馈、对话框、操作菜单以及自定义弹窗。

#### showToast

```typescript
import { PromptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  promptAction: PromptAction = this.getUIContext().getPromptAction();

  build() {
    Column() {
      Button('showToast')
        .onClick(() => {
          this.promptAction.showToast({
            message: 'Message Info',
            duration: 2000
          });
        })
    }
  }
}
```

#### showLoading / dismissLoading

```typescript
// 显示加载中
this.getUIContext().getPromptAction().showLoading({
  message: '加载中...'
});

// 隐藏加载中
this.getUIContext().getPromptAction().dismissLoading();
```

#### showDialog

```typescript
this.getUIContext().getPromptAction().showDialog({
  title: '提示',
  message: '确定要删除吗？',
  buttons: [
    { text: '取消', color: '#666666' },
    { text: '确定', color: '#007DFF' }
  ]
}).then(data => {
  console.info('click button: ' + data.index);
});
```

#### showActionMenu

```typescript
this.getUIContext().getPromptAction().showActionMenu({
  title: '选择操作',
  buttons: [
    { text: '拍照', color: '#666666' },
    { text: '相册', color: '#000000' }
  ]
}).then(data => {
  console.info('click button: ' + data.index);
});
```

#### openToast / closeToast

```typescript
@Entry
@Component
struct Index {
  @State toastId: number = 0;

  build() {
    Column() {
      Button('OpenToast')
        .onClick(() => {
          this.getUIContext().getPromptAction().openToast({
            message: 'Toast Message',
            duration: 10000,
          }).then((toastId: number) => {
            this.toastId = toastId;
          });
        })
      
      Button('Close Toast')
        .onClick(() => {
          this.getUIContext().getPromptAction().closeToast(this.toastId);
        })
    }
  }
}
```

### PromptAction 方法汇总

| 方法 | 说明 |
|------|------|
| showToast | 创建并显示即时反馈 |
| openToast | 显示即时反馈，返回id |
| closeToast | 关闭即时反馈 |
| showLoading | 显示加载弹窗 |
| dismissLoading | 隐藏加载弹窗 |
| showDialog | 创建并显示对话框 |
| showActionMenu | 创建并显示操作菜单 |
| showAlertDialog | 显示警告弹窗 |
| showActionSheet | 显示列表选择弹窗 |
| openCustomDialog | 显示自定义弹窗 |
| closeCustomDialog | 关闭自定义弹窗 |

---

### Router

提供页面路由能力，包括跳转、返回、替换等操作。

#### pushUrl

跳转到应用内的指定页面。

```typescript
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  build() {
    Column() {
      Button('pushUrl')
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/Detail',
            params: {
              id: 1,
              name: 'test'
            }
          })
          .then(() => {
            console.info('pushUrl succeeded');
          })
          .catch((error: BusinessError) => {
            console.error(`pushUrl failed, code is ${error.code}`);
          });
        })
    }
  }
}
```

#### replaceUrl

替换当前页面。

```typescript
this.getUIContext().getRouter().replaceUrl({
  url: 'pages/Login'
});
```

#### back

返回上一页或指定页面。

```typescript
// 返回上一页
this.getUIContext().getRouter().back();

// 返回指定页面
this.getUIContext().getRouter().back({
  url: 'pages/Home'
});
```

#### clear

清空页面栈。

```typescript
this.getUIContext().getRouter().clear();
```

#### getParams

获取页面参数。

```typescript
const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
```

### Router 方法汇总

| 方法 | 说明 |
|------|------|
| pushUrl | 跳转到指定页面 |
| replaceUrl | 替换当前页面 |
| back | 返回上一页 |
| clear | 清空页面栈 |
| getLength | 获取页面栈长度 |
| getState | 获取当前页面状态 |
| getParams | 获取页面参数 |
| pushNamedRoute | 跳转命名路由 |
| replaceNamedRoute | 替换命名路由 |

---

### OverlayManager

提供绘制浮层的能力。OverlayManager上节点的层级在Page页面层级之上，在Dialog、Popup、Menu等之下。

#### addComponentContent

在OverlayManager上新增指定节点。

```typescript
import { ComponentContent, OverlayManager } from '@kit.ArkUI';

class Params {
  text: string = "";
  offset: Position;

  constructor(text: string, offset: Position) {
    this.text = text;
    this.offset = offset;
  }
}

@Builder
function builderText(params: Params) {
  Column() {
    Text(params.text)
      .fontSize(30)
      .fontWeight(FontWeight.Bold)
  }.offset(params.offset)
}

@Entry
@Component
struct OverlayExample {
  private uiContext: UIContext = this.getUIContext();
  private overlayNode: OverlayManager = this.uiContext.getOverlayManager();

  build() {
    Column() {
      Button("增加ComponentContent")
        .onClick(() => {
          let componentContent = new ComponentContent(
            this.uiContext, 
            wrapBuilder<[Params]>(builderText),
            new Params("Hello", { x: 0, y: 80 })
          );
          this.overlayNode.addComponentContent(componentContent, 0);
        })
    }
  }
}
```

#### removeComponentContent

删除OverlayManager上的指定节点。

```typescript
this.overlayNode.removeComponentContent(componentContent);
```

#### showComponentContent / hideComponentContent

显示/隐藏指定节点。

```typescript
this.overlayNode.showComponentContent(componentContent);
this.overlayNode.hideComponentContent(componentContent);
```

### OverlayManager 方法汇总

| 方法 | 说明 |
|------|------|
| addComponentContent | 新增节点 |
| addComponentContentWithOrder | 新增节点并指定显示顺序 |
| removeComponentContent | 删除节点 |
| showComponentContent | 显示节点 |
| hideComponentContent | 隐藏节点 |
| showAllComponentContents | 显示所有节点 |
| hideAllComponentContents | 隐藏所有节点 |

---

### ComponentSnapshot

提供获取组件截图的能力。

#### get

获取已加载的组件的截图。

```typescript
import { image } from '@kit.ImageKit';

@Entry
@Component
struct SnapshotExample {
  @State pixmap: image.PixelMap | undefined = undefined;

  build() {
    Column() {
      Row() {
        Image(this.pixmap)
          .width(150)
          .height(150)
        
        Image($r('app.media.img'))
          .width(150)
          .height(150)
          .id("root")
      }

      Button("生成截图")
        .onClick(() => {
          this.getUIContext().getComponentSnapshot()
            .get("root", { scale: 2, waitUntilRenderFinished: true })
            .then((pixmap: image.PixelMap) => {
              this.pixmap = pixmap;
            });
        })
    }
  }
}
```

#### createFromBuilder

传入CustomBuilder自定义组件，系统对其进行离屏构建后进行截图。

```typescript
@Builder
function buildText() {
  Column() {
    Text('Custom Builder')
      .fontSize(20)
  }
  .width(100)
  .height(100)
  .backgroundColor(Color.Blue)
}

this.getUIContext().getComponentSnapshot()
  .createFromBuilder(buildText, (error: Error, pixmap: image.PixelMap) => {
    if (error) {
      console.error('error: ' + error);
      return;
    }
    this.pixmap = pixmap;
  });
```

### ComponentSnapshot 方法汇总

| 方法 | 说明 |
|------|------|
| get | 获取已加载组件的截图 |
| createFromBuilder | 对自定义组件离屏构建后截图 |

---

### FocusController

提供控制焦点的能力。

#### clearFocus

清除焦点，将焦点强制转移到页面根容器节点。

```typescript
this.getUIContext().getFocusController().clearFocus();
```

#### requestFocus

通过组件的id将焦点转移到对应的组件。

```typescript
Button('Button')
  .id("testButton")

Button('requestFocus')
  .onClick(() => {
    this.getUIContext().getFocusController().requestFocus("testButton");
  })
```

#### activate

设置当前界面的焦点激活态。

```typescript
// 进入焦点激活态
this.getUIContext().getFocusController().activate(true, false);

// 退出焦点激活态
this.getUIContext().getFocusController().activate(false);
```

### FocusController 方法汇总

| 方法 | 说明 |
|------|------|
| clearFocus | 清除焦点 |
| requestFocus | 请求焦点 |
| activate | 设置焦点激活态 |

---

### Font

提供字体注册等能力。

```typescript
this.getUIContext().getFont().registerFont({
  familySrc: '/fonts/custom.ttf'
});
```

---

### MediaQuery

提供媒体查询能力。

```typescript
this.getUIContext().getMediaQuery().matchMediaSync('(width < 600)');
```

---

### UIObserver

提供UI状态监听能力。

```typescript
@Component
struct PageOne {
  build() {
    NavDestination() {
      Text("pageOne")
    }.title("pageOne")
  }
}

@Entry
@Component
struct Index {
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear() {
    this.getUIContext().getUIObserver().on('navDestinationUpdate', (info) => {
      console.info('NavDestination state update', JSON.stringify(info));
    });
  }

  aboutToDisappear() {
    this.getUIContext().getUIObserver().off('navDestinationUpdate');
  }

  build() {
    Column() {
      Navigation(this.stack) {
        Button("push").onClick(() => {
          this.stack.pushPath({ name: "pageOne" });
        })
      }
    }
  }
}
```

---

### animateTo

提供显式动画能力。

```typescript
@Entry
@Component
struct AnimateToExample {
  @State widthSize: number = 250;
  @State heightSize: number = 100;

  build() {
    Column() {
      Button('change size')
        .width(this.widthSize)
        .height(this.heightSize)
        .onClick(() => {
          this.getUIContext().animateTo({
            duration: 2000,
            curve: Curve.EaseOut,
            onFinish: () => {
              console.info('play end');
            }
          }, () => {
            this.widthSize = 150;
            this.heightSize = 60;
          });
        })
    }
  }
}
```

---

## getHostContext

获取宿主上下文。

```typescript
import { common } from '@kit.AbilityKit';

let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
// 使用context进行操作
```

---

## 其他功能模块

| 模块 | 获取方法 | 说明 |
|------|----------|------|
| ComponentUtils | getComponentUtils() | 组件工具 |
| UIInspector | getUIInspector() | UI检查器 |
| CursorController | getCursorController() | 光标控制 |
| DragController | getDragController() | 拖拽控制 |
| FrameCallback | getFrameCallback() | 帧回调 |
| MeasureUtils | getMeasureUtils() | 测量工具 |
| DynamicSyncScene | getDynamicSyncScene() | 动态同步场景 |
| LocalStorage | getSharedLocalStorage() | 共享LocalStorage |

---

## 使用场景

### 在非组件中使用UIContext

```typescript
class Utils {
  private uiContext: UIContext;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }

  showToast(message: string) {
    this.uiContext.getPromptAction().showToast({ message });
  }
}

// 在组件中使用
private utils: Utils = new Utils(this.getUIContext());
```

### 解决UI上下文不明确问题

```typescript
// 不推荐：直接使用全局接口
import { promptAction } from '@kit.ArkUI';
promptAction.showToast({ message: 'Hello' });

// 推荐：使用UIContext
this.getUIContext().getPromptAction().showToast({ message: 'Hello' });
```

### runScopedTask

在明确的UI上下文中执行任务。

```typescript
this.getUIContext().runScopedTask(() => {
  // 在此闭包中执行的代码具有明确的UI上下文
  this.getUIContext().getPromptAction().showToast({ message: 'Hello' });
});
```

---

## 注意事项

1. **UIContext对象不可复用**：每个UI实例都有对应的UIContext对象
2. **UI实例有效性**：多次loadContent后，旧的UI实例会失效；窗口关闭后，该窗口的UI实例失效
3. **推荐使用UIContext**：避免使用全局接口，使用UIContext可以明确UI上下文
4. **OverlayManager层级**：OverlayManager上节点的层级在Page页面层级之上，在Dialog、Popup、Menu等之下
5. **截图时机**：如果在组件触发更新的同时调用截图，更新的渲染内容不会被截取到

---

## 相关链接

- [弹窗与模态](../07-dialogs-modals/dialogs-menus.md)
- [导航路由](../08-navigation-routing/navigation-routing.md)
- [焦点事件](../06-events-interaction/events-interaction.md)