# 属性动画

## 动画概述

动画可在UI发生改变时，添加流畅的过渡效果，使属性值从起始状态逐渐变化到终点状态，避免因瞬间变化造成的突兀感。

**动画目的：**
- 使界面的过渡自然流畅
- 增强用户从界面获得的反馈感和互动感
- 在内容加载等场景中，增加用户的耐心
- 引导用户了解和操作设备

**动画接口分类：**
- **属性动画**：最基础的动画类型，按照动画参数逐帧驱动属性的变化
- **转场动画**：为组件在出现和消失时添加过渡动画
- **粒子动画**：粒子效果的动画

---

## 属性动画概述

### 可动画属性分类

根据变化时是否能够添加动画，属性分为可动画属性和不可动画属性。

**系统可动画属性：**

| 分类 | 说明 |
|------|------|
| 布局属性 | 位置、大小、内边距、外边距、对齐方式、权重等 |
| 仿射变换 | 平移、旋转、缩放、锚点等 |
| 背景 | 背景颜色、背景模糊等 |
| 内容 | 文字大小、文字颜色，图片对齐方式、模糊等 |
| 前景 | 前景颜色等 |
| Overlay | Overlay属性等 |
| 外观 | 透明度、圆角、边框、阴影等 |

**判断可动画属性的标准：**
1. 属性变化能够引起UI的变化
2. 属性在变化时适合添加动画作为过渡

---

## 属性动画接口

ArkUI提供三种动画接口驱动组件属性按照动画曲线等参数进行连续的变化：

| 动画接口 | 作用域 | 使用场景 |
|----------|--------|----------|
| animateTo | 闭包内改变属性引起的界面变化 | 适用对多个可动画属性配置相同动画参数的动画 |
| animation | 组件通过属性接口绑定的属性变化引起的界面变化 | 适用于对多个可动画属性配置不同参数动画的场景 |
| keyframeAnimateTo | 多个闭包内改变属性引起的分段属性动画 | 适用于同一属性需要做连续多个动画的场景 |

---

## animateTo 显式动画

### 基本语法

```typescript
animateTo(value: AnimateParam, event: () => void): void
```

### AnimateParam 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| duration | number | 动画时长（毫秒） |
| curve | Curve \| ICurve \| string | 动画曲线 |
| delay | number | 延迟时间 |
| iterations | number | 重复次数 |
| playMode | PlayMode | 播放模式 |
| onFinish | () => void | 完成回调 |

### 基本使用

```typescript
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct AnimateToDemo {
  @State rotateValue: number = 0;
  @State translateX: number = 0;
  @State opacityValue: number = 1;
  @State animate: boolean = false;

  build() {
    Row() {
      Column()
        .rotate({ angle: this.rotateValue })
        .opacity(this.opacityValue)
        .translate({ x: this.translateX })
        .backgroundColor('#317AF7')
        .width(100)
        .height(100)
        .borderRadius(30)
        .onClick(() => {
          this.getUIContext()?.animateTo({ curve: curves.springMotion() }, () => {
            this.animate = !this.animate;
            this.rotateValue = this.animate ? 90 : 0;
            this.opacityValue = this.animate ? 0.6 : 1;
            this.translateX = this.animate ? 50 : 0;
          })
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### 多属性动画

```typescript
animateTo({ duration: 1000, curve: Curve.EaseInOut }, () => {
  this.width = 200;
  this.height = 200;
  this.opacity = 0.5;
  this.rotate = 45;
});
```

---

## animation 属性动画接口

相比于animateTo需要将属性修改封装在闭包中执行，animation接口无需使用闭包，只需将其加在要做动画的可动画属性后即可。

### 基本使用

```typescript
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct AnimationDemo {
  @State rotateValue: number = 0;
  @State translateX: number = 0;
  @State opacityValue: number = 1;
  @State animate: boolean = false;

  build() {
    Row() {
      Column()
        .opacity(this.opacityValue)
        .rotate({ angle: this.rotateValue })
        .animation({ curve: curves.springMotion() })
        .backgroundColor('#317AF7')
        .width(100)
        .height(100)
        .borderRadius(30)
        .onClick(() => {
          this.animate = !this.animate;
          this.rotateValue = this.animate ? 90 : 0;
          this.translateX = this.animate ? 50 : 0;
          this.opacityValue = this.animate ? 0.6 : 1;
        })

      Column()
        .opacity(this.opacityValue)
        .translate({ x: this.translateX })
        .animation({ curve: curves.springMotion() })
        .backgroundColor('#D94838')
        .width(100)
        .height(100)
        .borderRadius(30)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### animation参数

| 参数 | 类型 | 说明 |
|------|------|------|
| duration | number | 动画时长（毫秒） |
| curve | Curve | 动画曲线 |
| delay | number | 延迟时间 |
| iterations | number | 重复次数 |
| playMode | PlayMode | 播放模式 |
| onFinish | () => void | 完成回调 |

---

## keyframeAnimateTo 关键帧动画

### 基本语法

```typescript
keyframeAnimateTo(param: KeyframeAnimateParam, keyframes: Array<KeyframeState>): void
```

### 使用场景

在同一属性存在多段动画过程的场景，通过keyframeAnimateTo可以简化代码，避免在结束回调中再创建新动画导致的衔接卡顿。

### 基本使用

```typescript
@Entry
@Component
struct KeyframeAnimateToDemo {
  @State rotateValue: number = 0;
  @State translateX: number = 0;
  @State opacityValue: number = 1;

  build() {
    Row() {
      Column()
        .rotate({ angle: this.rotateValue })
        .backgroundColor('#317AF7')
        .width(100)
        .height(100)
        .borderRadius(30)
        .onClick(() => {
          this.getUIContext()?.keyframeAnimateTo({
            iterations: 1
          }, [
            {
              duration: 800,
              event: () => {
                this.rotateValue = 90;
                this.opacityValue = 0.6;
                this.translateX = 50;
              }
            },
            {
              duration: 500,
              event: () => {
                this.rotateValue = 0;
                this.opacityValue = 1;
                this.translateX = 0;
              }
            }
          ]);
        })

      Column()
        .opacity(this.opacityValue)
        .translate({ x: this.translateX })
        .backgroundColor('#D94838')
        .width(100)
        .height(100)
        .borderRadius(30)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

---

## @AnimatableExtend 自定义属性动画

### 基本使用

通过@AnimatableExtend装饰器可以自定义可动画属性，用于控制每帧绘制的内容。

```typescript
@AnimatableExtend(Text)
function animatableText(fontSize: number) {
  .fontSize(fontSize)
}

Text('Animation')
  .animatableText(this.fontSize)
  .animation({
    duration: 1000,
    curve: Curve.EaseInOut
  })

this.fontSize = 30;
```

---

## 动画曲线

### 传统曲线 (Curve)

| 值 | 说明 |
|---|------|
| Linear | 线性 |
| Ease | 快入慢出 |
| EaseIn | 慢入 |
| EaseOut | 慢出 |
| EaseInOut | 慢入慢出 |
| FastOutSlowIn | 快出慢入 |
| Friction | 阻尼曲线 |
| Sharp | 锐利曲线 |
| Rhythm | 节奏曲线 |
| Smooth | 平滑曲线 |

### 弹簧曲线

```typescript
import { curves } from '@kit.ArkUI';

// springCurve
animateTo({
  duration: 1000,
  curve: curves.springCurve(1.0, 0.3, 0.2, 0.5)
}, () => {
  this.width = 300;
});

// springMotion
animateTo({
  curve: curves.springMotion(0.6, 0.8)
}, () => {
  this.width = 300;
});

// responsiveSpringMotion
animateTo({
  curve: curves.responsiveSpringMotion()
}, () => {
  this.width = 300;
});

// interpolatingSpring
animateTo({
  curve: curves.interpolatingSpring(0, 1, 400, 38)
}, () => {
  this.width = 300;
});
```

---

## 帧动画 (Animator)

帧动画具备逐帧回调的特性，便于开发者在每一帧中处理需调整的属性。与属性动画相比，帧动画能让开发者实时感知动画进程，具备事件即时响应和可暂停的优势。

### 对比

| 名称 | 实现方式 | 事件响应方式 | 可暂停 | 性能 |
|------|----------|--------------|--------|------|
| 帧动画 | 开发者可每帧修改UI侧属性值 | 实时响应 | 是 | 较差 |
| 属性动画 | UI侧只计算动画最终状态 | 按最终状态响应 | 否 | 较好 |

### 基本使用

```typescript
import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';

@Entry
@Component
struct AnimatorDemo {
  @State animatorResult: AnimatorResult | undefined = undefined;
  @State translateX: number = 0;
  @State translateY: number = 0;

  animatorOption: AnimatorOptions = {
    duration: 4000,
    delay: 0,
    easing: 'linear',
    iterations: 1,
    fill: "forwards",
    direction: 'normal',
    begin: 0,
    end: 300
  };

  onPageShow(): void {
    this.animatorResult = this.getUIContext().createAnimator(this.animatorOption);
    this.animatorResult.onFrame = (progress: number) => {
      this.translateX = progress;
    }
    this.animatorResult.onFinish = () => {
      console.info('Animation finished');
    }
  }

  onPageHide(): void {
    this.animatorResult = undefined;
  }

  build() {
    Column() {
      Button()
        .width(60)
        .height(60)
        .translate({ x: this.translateX, y: this.translateY })

      Row({ space: 10 }) {
        Button('Play').onClick(() => {
          this.animatorResult?.play();
        })
        Button('Pause').onClick(() => {
          this.animatorResult?.pause();
        })
        Button('Reset').onClick(() => {
          this.translateX = 0;
          this.translateY = 0;
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
```

### AnimatorOptions 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| duration | number | 动画时长（毫秒） |
| easing | string | 缓动函数 |
| delay | number | 延迟时间 |
| fill | string | 填充模式 |
| direction | string | 播放方向 |
| iterations | number | 迭代次数 |
| begin | number | 起始值 |
| end | number | 结束值 |

### AnimatorResult 方法

| 方法 | 说明 |
|------|------|
| play() | 播放动画 |
| pause() | 暂停动画 |
| cancel() | 取消动画 |
| finish() | 结束动画 |
| reverse() | 反向播放 |
| onFrame | 帧回调 |
| onFinish | 完成回调 |
| onCancel | 取消回调 |
| onRepeat | 重复回调 |

---

## 动画衔接

### 动画之间的衔接

当UI侧行为改变可动画属性终点值时，只需在animateTo动画闭包中改变属性值或者改变animation接口作用的属性值，系统会自动衔接之前的动画和当前的动画。

```typescript
import { curves } from '@kit.ArkUI';

class SetAnimationVariables {
  isAnimation: boolean = true

  set(): void {
    this.isAnimation = !this.isAnimation;
  }
}

@Entry
@Component
struct AnimationToAnimationDemo {
  @State animationController: SetAnimationVariables = new SetAnimationVariables();

  build() {
    Column() {
      Text('ArkUI')
        .fontWeight(FontWeight.Bold)
        .fontSize(12)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(0xf56c6c)
        .width(100)
        .height(100)
        .scale({
          x: this.animationController.isAnimation ? 2 : 1,
          y: this.animationController.isAnimation ? 2 : 1
        })
        .animation({ curve: curves.springMotion(0.4, 0.8) })

      Button('Click')
        .margin({ top: 200 })
        .onClick(() => {
          this.animationController.set()
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### 手势与动画的衔接

使用滑动、捏合、旋转等手势的场景中，跟手过程中一般会触发属性的改变。离手后，这部分属性往往会继续发生变化，直到到达属性终点值。

```typescript
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct SpringMotionDemo {
  @State positionX: number = 100;
  @State positionY: number = 100;
  diameter: number = 50;

  build() {
    Column() {
      Row() {
        Circle({ width: this.diameter, height: this.diameter })
          .fill(Color.Blue)
          .position({ x: this.positionX, y: this.positionY })
          .onTouch((event?: TouchEvent) => {
            if (event) {
              if (event.type === TouchType.Move) {
                this.getUIContext()?.animateTo({ curve: curves.responsiveSpringMotion() }, () => {
                  this.positionX = event.touches[0].windowX - this.diameter / 2;
                  this.positionY = event.touches[0].windowY - this.diameter / 2;
                })
              } else if (event.type === TouchType.Up) {
                this.getUIContext()?.animateTo({ curve: curves.springMotion() }, () => {
                  this.positionX = 100;
                  this.positionY = 100;
                })
              }
            }
          })
      }
      .width('100%').height('80%')
      .clip(true)
      .backgroundColor(Color.Orange)

      Text('拖动小球').fontSize(16)
    }.height('100%').width('100%')
  }
}
```

---

## 组件动画

### 组件默认动画

ArkUI为部分组件提供了默认的动画效果，如List的滑动动效、Button的点击动效等。组件默认动效具备以下功能：
- 提示用户当前状态
- 提升界面精致程度和生动性
- 减少开发者工作量

```typescript
@Entry
@Component
struct ComponentDemo {
  build() {
    Row() {
      Checkbox({ name: 'checkbox1', group: 'checkboxGroup' })
        .select(true)
        .shape(CheckBoxShape.CIRCLE)
        .size({ width: 50, height: 50 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

### 定制化动效

部分组件支持通过属性动画和转场动画自定义组件子Item的动效。

```typescript
// 在滑动过程中定制动效
Scroll(this.scroller) {
  Row({ space: this.cardSpace }) {
    ForEach(taskDataArr, (item: TaskData, index) => {
      Column()
        .width(this.cardWidth)
        .height(this.cardHeight)
        .backgroundColor(item.bgColor)
        .borderRadius(15)
        .scale(this.getProgress(index) >= 0.4 && this.getProgress(index) <= 0.6 ?
          { x: 1.1 - Math.abs(0.5 - this.getProgress(index)), y: 1.1 - Math.abs(0.5 - this.getProgress(index)) } :
          { x: 1, y: 1 })
        .animation({ curve: Curve.Smooth })
        .translate({ x: this.cardOffset })
        .animation({ curve: curves.springMotion() })
    })
  }
}
```

---

## 动画性能优化

### 1. 使用硬件加速

```typescript
Text('Text')
  .motionPath({
    path: 'M0,0 L100,100',
    from: 0,
    to: 1
  })
```

### 2. 减少布局重计算

使用transform代替width/height

```typescript
animateTo({}, () => {
  this.scale = { x: 2, y: 2 };
});
```

### 3. 合理使用animateTo

多个属性变化放在一个闭包内

```typescript
animateTo({ duration: 500 }, () => {
  this.width = 200;
  this.height = 200;
  this.opacity = 0.8;
});
```

### 4. 使用scale替代布局属性

在对组件位置大小变化做动画时，由于布局属性的改变会触发测量布局，性能开销大。而scale属性的改变不会触发测量布局，性能开销小。

```typescript
// 推荐
animateTo({}, () => {
  this.scale = { x: 2, y: 2 };
});

// 不推荐（性能开销大）
animateTo({}, () => {
  this.width = this.width * 2;
  this.height = this.height * 2;
});
```

---

## 注意事项

1. **属性动画应该作用于始终存在的组件**，对于将要出现或者将要消失的组件的动画应该使用转场动画

2. **尽量不要使用动画结束回调**，属性动画是对已经发生的状态进行的动画，不需要开发者去处理结束的逻辑

3. **在设置的开发者选项中关闭过渡动画，或UIAbility从前台切换至后台，会立即执行动画结束回调**

4. **直接使用animateTo可能导致UI上下文不明确的问题**，建议使用getUIContext()获取UIContext实例

```typescript
this.getUIContext()?.animateTo({ curve: curves.springMotion() }, () => {
  this.width = 300;
});
```