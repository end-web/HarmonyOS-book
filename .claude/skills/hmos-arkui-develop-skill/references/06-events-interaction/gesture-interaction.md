# 手势交互

## 概述

手势是用户与应用程序进行交互的重要方式。ArkUI提供了丰富的手势类型，包括点击手势、长按手势、滑动手势、捏合手势、旋转手势等，并支持组合手势和多层级手势事件。

---

## 手势绑定方法

### gesture（常规手势绑定）

gesture为通用的一种手势绑定方法，可以将手势绑定到对应的组件上。

```typescript
Text('Gesture')
  .gesture(
    TapGesture()
      .onAction(() => {
        console.info('TapGesture is onAction');
      })
  )
```

### priorityGesture（带优先级的手势绑定）

priorityGesture是带优先级的手势绑定方法，可以在组件上绑定优先识别的手势。

在默认情况下，当父组件和子组件使用gesture绑定同类型的手势时，子组件优先识别通过gesture绑定的手势。当父组件使用priorityGesture绑定与子组件同类型的手势时，父组件优先识别通过priorityGesture绑定的手势。

```typescript
Column() {
  Text('Gesture')
    .gesture(
      TapGesture()
        .onAction(() => {
          console.info('Text TapGesture is onAction');
        })
  )
}
.priorityGesture(
  TapGesture()
    .onAction(() => {
      console.info('Column TapGesture is onAction');
    }), GestureMask.IgnoreInternal
)
```

### parallelGesture（并行手势绑定）

parallelGesture是并行的手势绑定方法，可以在父子组件上绑定可以同时响应的相同手势。

```typescript
Column() {
  Text('Gesture')
    .gesture(
      TapGesture()
        .onAction(() => {
          console.info('Text TapGesture is onAction');
        })
    )
}
.parallelGesture(
  TapGesture()
    .onAction(() => {
      console.info('Column TapGesture is onAction');
    }), GestureMask.Normal
)
```

### GestureMask 说明

| 值 | 说明 |
|------|------|
| Normal | 不忽略子组件的手势，按照默认手势进行判定 |
| IgnoreInternal | 忽略子组件的gesture、priorityGesture、parallelGesture手势 |

---

## 单一手势

### 点击事件（onClick）

单击作为常用的手势，可以方便地使用onClick接口实现。尽管被称为事件，它实际上是基本手势类型，等同于将count配置为1的TapGesture。

```typescript
Column() {
  Column()
    .width('60%')
    .height('50%')
    .backgroundColor(Color.Grey)
    .onClick(() => {
      console.info('Clicked on child');
    })
}
.gesture(
  TapGesture()
    .onAction(() => {
      console.info('Clicked on parent');
    })
)
```

### 点击手势（TapGesture）

点击手势支持单次点击和多次点击。

```typescript
Text('Click twice')
  .gesture(
    TapGesture({ count: 2 })
      .onAction((event: GestureEvent|undefined) => {
        if(event){
          console.info('Double tapped');
        }
      })
  )
```

### 长按手势（LongPressGesture）

长按手势用于触发长按手势事件。

```typescript
Text('LongPress')
  .gesture(
    LongPressGesture({ repeat: true })
      .onAction((event: GestureEvent | undefined) => {
        if (event) {
          if (event.repeat) {
            console.info('Long pressing...');
          }
        }
      })
      .onActionEnd(() => {
        console.info('Long press ended');
      })
  )
```

### LongPressGesture 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| fingers | number | 触发手势需要的最少手指数量，默认值：1 |
| repeat | boolean | 是否连续触发，默认值：false |
| duration | number | 最小长按时间，单位：毫秒，默认值：500 |

### 滑动手势（PanGesture）

滑动手势用于触发滑动手势事件，滑动达到最小滑动距离（默认值为5vp）时滑动手势识别成功。

```typescript
Column()
  .width('100%')
  .height(250)
  .backgroundColor('#F5F5F5')
  .gesture(
    PanGesture()
      .onActionStart(() => {
        console.info('Pan start');
      })
      .onActionUpdate((event: GestureEvent) => {
        if (event.source === SourceType.TouchScreen) {
          console.info('finger move triggered PanGesture');
        }
        if (event.source === SourceType.Mouse && event.sourceTool === SourceTool.MOUSE) {
          if (event.axisHorizontal === 0 && event.axisVertical === 0) {
            console.info('mouse move with left button pressed triggered PanGesture');
          } else { 
            console.info('mouse wheel triggered PanGesture');
          }
        }
      })
  )
```

### PanGesture 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| fingers | number | 触发手势需要的最少手指数量，默认值：1 |
| direction | PanDirection | 滑动方向，默认值：All |
| distance | number | 最小滑动距离，默认值：5vp |

### PanDirection 枚举

| 值 | 说明 |
|------|------|
| All | 所有方向 |
| Horizontal | 水平方向 |
| Vertical | 垂直方向 |
| Left | 向左 |
| Right | 向右 |
| Up | 向上 |
| Down | 向下 |

### 捏合手势（PinchGesture）

捏合手势用于触发捏合手势事件。

```typescript
Column() {
  Column() {
    Text('PinchGesture scale:\n' + this.scaleValue)
    Text('PinchGesture center:\n(' + this.pinchX + ',' + this.pinchY + ')')
  }
  .scale({ x: this.scaleValue, y: this.scaleValue, z: 1 })
  .gesture(
    PinchGesture({ fingers: 3 })
      .onActionStart((event: GestureEvent | undefined) => {
        console.info('Pinch start');
      })
      .onActionUpdate((event: GestureEvent | undefined) => {
        if (event) {
          this.scaleValue = this.pinchValue * event.scale;
          this.pinchX = event.pinchCenterX;
          this.pinchY = event.pinchCenterY;
        }
      })
      .onActionEnd(() => {
        this.pinchValue = this.scaleValue;
        console.info('Pinch end');
      })
  )
}
```

### PinchGesture 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| fingers | number | 触发手势需要的最少手指数量，默认值：2 |
| distance | number | 最小捏合距离，默认值：3vp |

### 旋转手势（RotationGesture）

旋转手势用于触发旋转手势事件。

```typescript
Text('RotationGesture angle:' + this.angle)
  .rotate({ angle: this.angle })
  .gesture(
    RotationGesture()
      .onActionStart((event: GestureEvent|undefined) => {
        console.info('RotationGesture is onActionStart');
      })
      .onActionUpdate((event: GestureEvent|undefined) => {
        if(event){
          this.angle = this.rotateValue + event.angle;
        }
      })
      .onActionEnd(() => {
        this.rotateValue = this.angle;
        console.info('RotationGesture is onActionEnd');
      })
      .onActionCancel(() => {
        console.info('RotationGesture is onActionCancel');
      })
  )
```

### RotationGesture 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| fingers | number | 触发手势需要的最少手指数量，默认值：2 |
| angle | number | 最小旋转角度，默认值：1度 |

### 快滑手势（SwipeGesture）

快滑手势用于触发快滑事件，当滑动速度大于100vp/s时可以识别成功。

```typescript
Column() {
  Column() {
    Text('SwipeGesture speed\n' + this.speed)
    Text('SwipeGesture angle\n' + this.rotateAngle)
  }
  .rotate({ angle: this.rotateAngle })
  .gesture(
    SwipeGesture({ direction: SwipeDirection.Vertical })
      .onAction((event: GestureEvent|undefined) => {
        if(event){
          this.speed = event.speed;
          this.rotateAngle = event.angle;
        }
      })
  )
}
```

### SwipeGesture 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| fingers | number | 触发手势需要的最少手指数量，默认值：1 |
| direction | SwipeDirection | 滑动方向 |
| speed | number | 最小滑动速度，默认值：100vp/s |

### SwipeDirection 枚举

| 值 | 说明 |
|------|------|
| All | 所有方向 |
| Horizontal | 水平方向 |
| Vertical | 垂直方向 |

---

## GestureEvent 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| repeat | boolean | 是否重复触发 |
| fingerList | FingerInfo[] | 手指信息列表 |
| offsetX | number | 手势偏移量X |
| offsetY | number | 手势偏移量Y |
| scale | number | 缩放比例 |
| angle | number | 旋转角度 |
| speed | number | 滑动速度 |
| pinchCenterX | number | 捏合中心点X坐标 |
| pinchCenterY | number | 捏合中心点Y坐标 |
| source | SourceType | 事件输入设备 |
| sourceTool | SourceTool | 输入工具类型 |
| axisHorizontal | number | 水平轴值（滚轮） |
| axisVertical | number | 垂直轴值（滚轮） |

---

## 组合手势

组合手势由多种单一手势组合而成，通过在GestureGroup中使用不同的GestureMode来声明该组合手势的类型。

### GestureGroup

```typescript
GestureGroup(mode: GestureMode, gesture: GestureType[])
```

### GestureMode 枚举

| 值 | 说明 |
|------|------|
| Sequence | 顺序识别 |
| Parallel | 并行识别 |
| Exclusive | 互斥识别 |

### 顺序识别（Sequence）

顺序识别组合手势将按照手势的注册顺序识别手势，直到所有的手势识别成功。当顺序识别组合手势中有一个手势识别失败时，后续手势识别均失败。

```typescript
Column() {
  Text('sequence gesture\nLongPress count: ' + this.count + '\nPanGesture offset:\nX: ' + this.offsetX + '\nY: ' + this.offsetY)
}
.translate({ x: this.offsetX, y: this.offsetY, z: 0 })
.gesture(
  GestureGroup(GestureMode.Sequence,
    LongPressGesture({ repeat: true })
      .onAction((event: GestureEvent | undefined) => {
        if (event) {
          if (event.repeat) {
            this.count++;
          }
        }
      }),
    PanGesture()
      .onActionStart(() => {
        console.info('pan start');
      })
      .onActionUpdate((event: GestureEvent | undefined) => {
        if (event) {
          this.offsetX = this.positionX + event.offsetX;
          this.offsetY = this.positionY + event.offsetY;
        }
      })
      .onActionEnd(() => {
        this.positionX = this.offsetX;
        this.positionY = this.offsetY;
      })
  )
)
```

**说明：** 拖拽事件是一种典型的顺序识别组合手势事件，由长按手势事件和滑动手势事件组合而成。

### 并行识别（Parallel）

并行识别组合手势中注册的手势将同时进行识别，直到所有手势识别结束。并行识别手势组合中的手势进行识别时互不影响。

```typescript
Column() {
  Text('Parallel gesture\ntapGesture count is 1:' + this.count1 + '\ntapGesture count is 2:' + this.count2)
}
.gesture(
  GestureGroup(GestureMode.Parallel,
    TapGesture({ count: 1 })
      .onAction(() => {
        this.count1++;
      }),
    TapGesture({ count: 2 })
      .onAction(() => {
        this.count2++;
      })
  )
)
```

**说明：** 当由单击手势和双击手势组成一个并行识别组合手势后，在区域内进行点击时，单击手势和双击手势将同时进行识别。

### 互斥识别（Exclusive）

互斥识别组合手势中注册的手势将同时进行识别，若有一个手势识别成功，则结束手势识别，其他所有手势识别失败。

```typescript
Column() {
  Text('Exclusive gesture\ntapGesture count is 1:' + this.count1 + '\ntapGesture count is 2:' + this.count2)
}
.gesture(
  GestureGroup(GestureMode.Exclusive,
    TapGesture({ count: 1 })
      .onAction(() => {
        this.count1++;
      }),
    TapGesture({ count: 2 })
      .onAction(() => {
        this.count2++;
      })
  )
)
```

**说明：** 当由单击手势和双击手势组成一个互斥识别组合手势后，手势响应取决于绑定手势的顺序。

---

## 多层级手势事件

多层级手势事件指父子组件嵌套时，父子组件均绑定了手势或事件。在该场景下，手势或者事件的响应受到多个因素的影响，相互之间发生传递和竞争。

### 默认响应优先级

1. 当父子组件均绑定同一类手势时，子组件优先于父组件触发

2. 当一个组件绑定多个手势时，先达到手势触发条件的手势优先触发

```typescript
Column() {
  Column()
    .id('ComponentB')
    .gesture(TapGesture({ count: 1 }))
}
.id('ComponentA')
.gesture(TapGesture({ count: 1 }))
```

当在B组件上进行点击时，组件B所绑定的TapGesture的回调会被触发，而组件A所绑定的TapGesture的回调不会被触发。

### 触摸热区控制

通过responseRegion属性可以设置组件的触摸热区，触摸热区范围可以超出或者小于组件的布局范围。

```typescript
Column() {
  Column()
    .id('ComponentB')
    .onTouch(() => {})
    .gesture(TapGesture({ count: 1 }))
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
}
.id('ComponentA')
.onTouch(() => {})
.gesture(TapGesture({ count: 1 }))
.responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
```

### 触摸测试控制

通过hitTestBehavior属性可以实现在复杂的多层级场景下，控制哪些组件能够响应手势和事件。

```typescript
Column() {
  Column()
    .id('ComponentB')
    .onTouch(() => {})
    .gesture(TapGesture({ count: 1 }))
  Column() {
    Column()
      .id('ComponentD')
      .onTouch(() => {})
      .gesture(TapGesture({ count: 1 }))
  }
  .id('ComponentC')
  .onTouch(() => {})
  .gesture(TapGesture({ count: 1 }))
  .hitTestBehavior(HitTestMode.Block)
}
.id('ComponentA')
.onTouch(() => {})
.gesture(TapGesture({ count: 1 }))
```

当组件C设置了hitTestBehavior为HitTestMode.Block时，点击组件D区域，组件A和组件C的onTouch事件会触发，组件D的onTouch事件未触发。

---

## 手势冲突处理

手势冲突是指多个手势识别器在同一组件或重叠区域同时识别时产生竞争，导致识别结果不符合预期。

### 自定义手势判定

自定义手势判定是指在系统判定阈值已满足的条件下，应用可自行判断是否应拦截该手势。

#### onGestureJudgeBegin

```typescript
Stack() {
  Image($r('sys.media.ohos_app_icon'))
    .draggable(true)
    .onDragStart(() => {
      console.info('Drag triggered');
    })
    .width('200vp')
    .height('200vp')
  
  Stack() {}
    .width('200vp')
    .height('200vp')
    .hitTestBehavior(HitTestMode.Transparent)
    .gesture(
      GestureGroup(GestureMode.Parallel,
        LongPressGesture()
          .onAction((event: GestureEvent) => {
            console.info('LongPress triggered');
          })
      )
    )
    .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
      if (gestureInfo.type == GestureControl.GestureType.LONG_PRESS_GESTURE) {
        if (event.fingerList.length > 0 && event.fingerList[0].localY < 100) {
          return GestureJudgeResult.CONTINUE;
        } else {
          return GestureJudgeResult.REJECT;
        }
      }
      return GestureJudgeResult.CONTINUE;
    })
}
```

### GestureJudgeResult 枚举

| 值 | 说明 |
|------|------|
| CONTINUE | 继续识别 |
| REJECT | 拒绝识别 |

### 手势并行动态控制

手势并行动态控制指的是手势已经成功识别，但是开发者仍然可以通过调用API接口控制手势回调是否能够响应。

#### shouldBuiltInRecognizerParallelWith

用于设置系统组件内置手势与其他手势并行。

```typescript
Scroll() {
  Column() {
    // ...
  }
}
.shouldBuiltInRecognizerParallelWith((current: GestureRecognizer, others: Array<GestureRecognizer>) => {
  for (let i = 0; i < others.length; i++) {
    let target = others[i].getEventTargetInfo();
    if (target.getId() == 'inner' && others[i].isBuiltIn() && 
        others[i].getType() == GestureControl.GestureType.PAN_GESTURE) {
      this.currentRecognizer = current;
      this.childRecognizer = others[i];
      return { recognizer: others[i] };
    }
  }
  return undefined;
})
```

#### onGestureRecognizerJudgeBegin

用于手势拦截、获取手势识别器、设置手势识别器开闭状态。

```typescript
Column() {
  // ...
}
.onGestureRecognizerJudgeBegin(
  (event: BaseGestureEvent, current: GestureRecognizer, others: Array<GestureRecognizer>) => {
    if (current.getType() !== GestureControl.GestureType.PAN_GESTURE) {
      return GestureJudgeResult.CONTINUE;
    }
    if (this.isLongPress) {
      return GestureJudgeResult.CONTINUE;
    }
    return GestureJudgeResult.REJECT;
  })
```

---

## 注意事项

1. **滑动组件与子组件手势竞争**：大部分可滑动组件（如List、Grid、Scroll、Tab等）是通过PanGesture实现滑动，在组件内部的子组件绑定滑动手势或快滑手势会导致手势竞争

2. **SwipeGesture 和 PanGesture 竞争**：当SwipeGesture和PanGesture同时绑定时，若二者是以默认方式或者互斥方式进行绑定时，会发生竞争。SwipeGesture的触发条件为滑动速度达到100vp/s，PanGesture的触发条件为滑动距离达到5vp，先达到触发条件的手势触发

3. **不合理的阈值设置**：会导致滑动不跟手（响应时延慢）的问题

4. **拖拽与长按手势冲突**：手势场景触发的拖拽功能依赖于底层绑定的长按手势。如果开发者在可拖拽组件上也绑定了长按手势，这将与底层的长按手势产生冲突，可以采用并行手势的方案解决

---

## 相关链接

- [事件与交互](events-interaction.md)
- [动画](../05-animation/animation.md)