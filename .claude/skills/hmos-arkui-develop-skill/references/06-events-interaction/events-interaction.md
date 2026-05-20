# 事件与交互

## 概述

事件与交互是用户与应用程序进行沟通的主要方式。ArkUI提供了丰富的事件类型，包括触摸事件、点击事件、按键事件、焦点事件、拖拽事件、鼠标事件等，满足各种交互场景的需求。

---

## 点击事件

点击事件是最常用的用户交互方式之一。

### onClick

```typescript
Button('Click')
  .onClick((event: ClickEvent) => {
    console.info(`Clicked at: ${event.x}, ${event.y}`);
  })
```

### onDoubleClick

```typescript
Button('Double Click')
  .onDoubleClick(() => {
    console.info('Double clicked');
  })
```



### ClickEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| x | number | 点击位置相对于组件左上角的x坐标 |
| y | number | 点击位置相对于组件左上角的y坐标 |
| windowX | number | 点击位置相对于应用窗口左上角的x坐标 |
| windowY | number | 点击位置相对于应用窗口左上角的y坐标 |
| displayX | number | 点击位置相对于设备屏幕左上角的x坐标 |
| displayY | number | 点击位置相对于设备屏幕左上角的y坐标 |
| screenX | number | 点击位置相对于设备屏幕左上角的x坐标（同displayX） |
| screenY | number | 点击位置相对于设备屏幕左上角的y坐标（同displayY） |
| timestamp | number | 事件时间戳 |
| target | EventTarget | 触发事件的元素对象 |
| source | SourceType | 事件输入设备 |
| pressure | number | 按压压力值 |
| tiltX | number | 倾斜角度X |
| tiltY | number | 倾斜角度Y |
| sourceTool | SourceTool | 输入工具类型 |

## 触摸事件

触摸事件是所有手势组成的基础，有Down、Move、Up、Cancel四种类型。

### onTouch

```typescript
Column() {
  Text('Touch Area')
}
.onTouch((event: TouchEvent) => {
  switch (event.type) {
    case TouchType.Down:
      console.info('Touch down');
      break;
    case TouchType.Move:
      console.info(`Move to: ${event.touches[0].x}`);
      break;
    case TouchType.Up:
      console.info('Touch up');
      break;
    case TouchType.Cancel:
      console.info('Touch cancel');
      break;
  }
})
```

### TouchEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| type | TouchType | 触摸类型：Down/Move/Up/Cancel |
| touches | TouchObject[] | 触摸点数组 |
| changedTouches | TouchObject[] | 变化的触摸点 |
| timestamp | number | 事件时间戳 |
| target | EventTarget | 触发事件的元素对象 |
| source | SourceType | 事件输入设备 |
| pressure | number | 按压压力值 |
| tiltX | number | 倾斜角度X |
| tiltY | number | 倾斜角度Y |
| sourceTool | SourceTool | 输入工具类型 |

### TouchObject 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| x | number | 触摸点相对于组件左上角的x坐标 |
| y | number | 触摸点相对于组件左上角的y坐标 |
| windowX | number | 触摸点相对于应用窗口左上角的x坐标 |
| windowY | number | 触摸点相对于应用窗口左上角的y坐标 |
| displayX | number | 触摸点相对于设备屏幕左上角的x坐标 |
| displayY | number | 触摸点相对于设备屏幕左上角的y坐标 |
| id | number | 触摸点标识 |

### 触摸事件特点

1. **闭环性**：若一个组件收到了手指Id为0的Down事件，后续也会收到手指Id为0的Move事件和Up事件

2. **一致性**：若一个组件收到了手指Id为0的Down事件，但未收到手指Id为1的Down事件，则后续只会收到手指Id为0的touch事件

3. **父子组件触发**：对于一般的容器组件，父子组件之间onTouch事件能够同时触发，兄弟组件之间onTouch事件根据布局进行触发

---

## 按键事件

按键事件用于处理键盘输入。

### onKeyEvent

```typescript
TextInput()
  .onKeyEvent((event: KeyEvent) => {
    if (event.type === KeyType.Down) {
      if (event.keyCode === KeyCode.Enter) {
        console.info('Enter pressed');
      }
    }
    return true;
  })
```

### KeyEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| type | KeyType | 按键类型：Down/Up |
| keyCode | number | 键码 |
| keyText | string | 按键文本 |
| keySource | KeySource | 按键来源 |
| deviceId | number | 设备ID |
| metaKey | number | 元键状态 |
| timestamp | number | 事件时间戳 |
| stopPropagation | () => void | 阻止冒泡 |

### 常用 KeyCode

| KeyCode | 说明 |
|---------|------|
| Enter | 回车键 |
| Backspace | 退格键 |
| Delete | 删除键 |
| Tab | Tab键 |
| Escape | Escape键 |
| ArrowUp | 上箭头 |
| ArrowDown | 下箭头 |
| ArrowLeft | 左箭头 |
| ArrowRight | 右箭头 |
| Space | 空格键 |
| Home | Home键 |
| End | End键 |
| PageUp | PageUp键 |
| PageDown | PageDown键 |

---

## 焦点事件

焦点是当前应用界面上唯一的一个可交互元素，用于键盘、电视遥控器等非指向性输入设备的交互。

### onFocus / onBlur

```typescript
TextInput()
  .onFocus(() => {
    console.info('Gained focus');
  })
  .onBlur(() => {
    console.info('Lost focus');
  })
```

### 焦点控制

```typescript
@State focusable: boolean = true;

TextInput()
  .focusable(this.focusable)
  .defaultFocus(true)
```

### 焦点控制属性

| 属性 | 说明 |
|------|------|
| focusable | 设置组件是否可获焦 |
| defaultFocus | 设置组件是否为默认焦点 |
| focusOnTouch | 设置点击时是否申请焦点 |
| focusBox | 设置焦点框样式 |

### 焦点激活态

焦点激活态是用来显示当前获焦组件焦点框的视觉样式。

**如何进入激活态：**
- 按下外接键盘的Tab键
- 调用FocusController的activate(true)方法

**如何退出激活态：**
- 调用FocusController的activate(false)方法
- 发生点击事件时

```typescript
@Entry
@Component
struct FocusActiveExample {
  build() {
    Column() {
      Button('Set Active')
        .onClick(() => {
          this.getUIContext().getFocusController().activate(true, true);
        })
      Button('Set Not Active')
        .onClick(() => {
          this.getUIContext().getFocusController().activate(false, true);
        })
    }
  }
}
```

### 请求焦点

```typescript
Button('Request Focus')
  .onClick(() => {
    this.getUIContext().getFocusController().requestFocus('targetId');
  })

TextInput()
  .id('targetId')
```

---

## 拖拽事件

拖拽提供了一种通过鼠标或手势触屏传递数据的机制。

### 基本概念

- **拖拽操作**：在可响应拖出的组件上长按并滑动以触发拖拽行为
- **拖拽背景（背板）**：用户拖动数据时的形象化表示
- **拖拽内容**：被拖动的数据，使用UnifiedData进行封装
- **拖出对象**：触发拖拽操作并提供数据的组件
- **拖入目标**：可接收并处理拖动数据的组件

### 拖拽方式

#### 手势拖拽
- 默认支持拖出能力的组件：Search、TextInput、TextArea、RichEditor、Text、Image、Hyperlink
- 长按时间达到或超过500ms即可触发拖拽
- 长按800ms时，系统开始执行预览图的浮起动效

#### 鼠标拖拽
- 鼠标左键在可拖拽的组件上按下并移动超过1vp时，即可触发拖拽功能

### 拖拽回调

| 回调事件 | 说明 |
|----------|------|
| onDragStart | 拖出的组件产生拖出动作时触发 |
| onDragEnter | 拖拽点进入组件范围时触发 |
| onDragMove | 拖拽点在组件范围内移动时触发 |
| onDragLeave | 拖拽点移出组件范围时触发 |
| onDrop | 用户在组件范围内释放拖拽时触发 |
| onDragEnd | 拖拽活动终止时触发 |
| onPreDrag | 拖拽事件的不同阶段触发 |

### 拖拽源

```typescript
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';

Text('Drag Source')
  .draggable(true)
  .onDragStart((event: DragEvent) => {
    let data: unifiedDataChannel.Image = new unifiedDataChannel.Image();
    data.imageUri = 'resources/base/media/pic.png';
    let unifiedData = new unifiedDataChannel.UnifiedData(data);
    event.setData(unifiedData);
    
    let dragItemInfo: DragItemInfo = {
      pixelMap: this.pixmap,
      extraInfo: 'this is extraInfo',
    };
    return dragItemInfo;
  })
```

### 拖拽目标

```typescript
Column() {
  Text('Drop Target')
}
.onDrop((event: DragEvent) => {
  let data = event.getData();
  console.info(`Dropped: ${data}`);
  event.setResult(DragResult.DRAG_SUCCESSFUL);
})
```

### DragResult 说明

| 值 | 说明 |
|------|------|
| DRAG_SUCCESSFUL | 数据完全由开发者自己处理，系统不进行处理 |
| DRAG_FAILED | 数据不再由系统继续处理 |
| DRAG_CANCELED | 系统也不需要进行数据处理 |
| DROP_ENABLED | 组件允许落入 |
| DROP_DISABLED | 组件不允许落入 |

---

## 鼠标事件

### onMouse

```typescript
Column() {
  Text('Hover Me')
}
.onMouse((event: MouseEvent) => {
  switch (event.action) {
    case MouseAction.Hover:
      console.info('Hovering');
      break;
    case MouseAction.Press:
      console.info('Mouse pressed');
      break;
    case MouseAction.Move:
      console.info('Mouse moved');
      break;
    case MouseAction.Release:
      console.info('Mouse released');
      break;
  }
})
```

### onHover

```typescript
Column() {
  Text('Hover Area')
}
.onHover((isHover: boolean) => {
  this.isHovering = isHover;
})
```

### MouseEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| action | MouseAction | 鼠标动作 |
| button | MouseButton | 鼠标按键 |
| buttons | number | 鼠标按键状态 |
| x | number | 鼠标位置相对于组件左上角的x坐标 |
| y | number | 鼠标位置相对于组件左上角的y坐标 |
| windowX | number | 鼠标位置相对于应用窗口左上角的x坐标 |
| windowY | number | 鼠标位置相对于应用窗口左上角的y坐标 |
| displayX | number | 鼠标位置相对于设备屏幕左上角的x坐标 |
| displayY | number | 鼠标位置相对于设备屏幕左上角的y坐标 |
| timestamp | number | 事件时间戳 |
| target | EventTarget | 触发事件的元素对象 |
| stopPropagation | () => void | 阻止冒泡 |

### MouseAction 枚举

| 值 | 说明 |
|------|------|
| Hover | 鼠标悬停 |
| Press | 鼠标按下 |
| Move | 鼠标移动 |
| Release | 鼠标释放 |

### MouseButton 枚举

| 值 | 说明 |
|------|------|
| LeftButton | 左键 |
| RightButton | 右键 |
| MiddleButton | 中键 |
| BackButton | 后退键 |
| ForwardButton | 前进键 |

---

## 悬停事件

### onHover

```typescript
Column() {
  Text('Hover Effect')
}
.backgroundColor(this.isHover ? Color.Blue : Color.Gray)
.onHover((isHover: boolean) => {
  this.isHover = isHover;
})
```

---

## 事件拦截

### hitTestBehavior

hitTestBehavior属性可以控制触摸事件的分发，从而影响onTouch事件和手势的响应。

```typescript
Column() {
  Text('Child')
}
.hitTestBehavior(HitTestMode.Block)
```

### HitTestMode 枚举

| 值 | 说明 |
|------|------|
| Default | 默认，事件正常传递 |
| Block | 阻塞，自身响应触摸测试，阻塞子节点和兄弟节点的触摸测试 |
| Transparent | 透明，自身响应触摸测试，不会阻塞兄弟节点的触摸测试 |
| None | 不响应，自身和子节点都不响应触摸测试 |

### 触摸热区

通过responseRegion属性可以设置组件的触摸热区，触摸热区范围可以超出或者小于组件的布局范围。

```typescript
Column() {
  Text('Touch Area')
}
.responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
```

### 多个触摸热区

```typescript
Column() {
  Text('Multi Touch Area')
}
.responseRegion([
  { x: 0, y: 0, width: '50%', height: '100%' },
  { x: '50%', y: 0, width: '50%', height: '100%' }
])
```

---

## 事件传递

### 触摸事件传递

对于一般的容器组件（例如：Column），父子组件之间onTouch事件能够同时触发，兄弟组件之间onTouch事件根据布局进行触发。

```typescript
Column() {
  Column()
    .id('ComponentB')
    .onTouch(() => {
      console.info('ComponentB touch');
    })
  Column()
    .id('ComponentC')
    .onTouch(() => {
      console.info('ComponentC touch');
    })
}
.id('ComponentA')
.onTouch(() => {
  console.info('ComponentA touch');
})
```

当触摸组件B时，会触发组件A和组件B的onTouch回调，不会触发组件C的onTouch回调。

### Stack 组件的触摸事件

Stack组件的子组件之间存在遮盖关系，兄弟组件之间onTouch事件会存在遮盖关系。

```typescript
Stack() {
  Column()
    .id('ComponentB')
    .onTouch(() => {
      console.info('ComponentB touch');
    })
  Column()
    .id('ComponentC')
    .onTouch(() => {
      console.info('ComponentC touch');
    })
}
.id('StackA')
.onTouch(() => {
  console.info('StackA touch');
})
```

当触摸组件B和组件C的重叠区域时，会触发Stack A和组件C的onTouch回调，不会触发组件B的onTouch回调（组件B被组件C遮盖）。

---

## 相关链接

- [手势交互](gesture-interaction.md)
- [弹窗与模态](../07-dialogs-modals/dialogs-menus.md)