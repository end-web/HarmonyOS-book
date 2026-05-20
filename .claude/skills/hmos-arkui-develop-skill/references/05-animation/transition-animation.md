# 转场动画

## 转场动画概述

转场动画用于对即将出现或消失的组件施加动画效果，始终显示的组件应使用属性动画。转场动画旨在简化开发者对组件消失节点的管理。

### 转场动画分类

| 转场类型 | 说明 | 适用场景 |
|----------|------|----------|
| 出现/消失转场 | 对新增、消失的控件实现动画效果 | 通用基础转场效果 |
| 模态转场 | 新的界面覆盖在旧的界面之上 | 弹框、半模态等 |
| 共享元素转场 | 界面切换时对相同或相似元素的过渡动画 | 一镜到底效果 |
| 页面转场 | 页面的路由转场方式 | 页面跳转场景 |
| 导航转场 | Navigation组件的转场方式 | 一级菜单切换到二级界面 |
| 旋转屏动画 | 屏幕显示方向变化时的自然过渡 | 横竖屏切换 |

---

## 出现/消失转场

transition是基础的组件转场接口，用于实现一个组件出现或者消失时的动画效果。

### 转场效果接口

| 转场效果 | 说明 | 动画 |
|----------|------|------|
| IDENTITY | 禁用转场效果 | 无 |
| OPACITY | 默认的转场效果，透明度转场 | 出现时透明度从0到1，消失时透明度从1到0 |
| SLIDE | 滑动转场效果 | 出现时从窗口左侧滑入，消失时从窗口右侧滑出 |
| translate | 通过设置组件平移创建转场效果 | 出现时为translate接口设置的值到默认值0 |
| rotate | 通过设置组件旋转创建转场效果 | 出现时为rotate接口设置的值到默认值0 |
| opacity | 通过设置透明度参数创建转场效果 | 出现时为opacity设置的值到默认透明度1 |
| move | 通过TransitionEdge创建从窗口哪条边缘出来的效果 | 出现时从TransitionEdge方向滑入 |
| asymmetric | 组合非对称的出现消失转场效果 | 出现和消失采用不同效果 |
| combine | 组合其他TransitionEffect | 组合多个转场效果一起生效 |
| animation | 定义转场效果的动画参数 | 设置duration、curve等 |

### 基本使用

```typescript
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct TransitionEffectDemo {
  @State isPresent: boolean = false;

  private effect: TransitionEffect =
    TransitionEffect.OPACITY.animation({
      curve: curves.springMotion(0.6, 0.8)
    })
      .combine(TransitionEffect.scale({ x: 0, y: 0 }))
      .combine(TransitionEffect.rotate({ angle: 90 }))
      .combine(TransitionEffect.translate({ y: 150 })
        .animation({ curve: curves.springMotion() }))
      .combine(TransitionEffect.move(TransitionEdge.END));

  build() {
    Stack() {
      if (this.isPresent) {
        Column() {
          Text('ArkUI')
            .fontWeight(FontWeight.Bold)
            .fontSize(20)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .width(150)
        .height(150)
        .borderRadius(10)
        .backgroundColor(0xf56c6c)
        .transition(this.effect)
      }

      Button('Click')
        .margin({ top: 320 })
        .onClick(() => {
          this.isPresent = !this.isPresent;
        })
    }
    .width('100%')
    .height('60%')
  }
}
```

### 渐次出现消失效果

对多个组件添加转场效果时，可以在animation动画参数中配置不同的delay值，实现组件渐次出现消失的效果。

```typescript
const ITEM_COUNTS = 9;
const INTERVAL = 30;
const DURATION = 300;

@Entry
@Component
struct Index {
  @State isGridShow: boolean = false;
  private dataArray: number[] = new Array(ITEM_COUNTS);

  aboutToAppear(): void {
    for (let i = 0; i < ITEM_COUNTS; i++) {
      this.dataArray[i] = i;
    }
  }

  build() {
    Stack() {
      if (this.isGridShow) {
        Grid() {
          ForEach(this.dataArray, (item: number, index: number) => {
            GridItem() {
              Stack() {
                Text((item + 1).toString())
              }
              .size({ width: 50, height: 50 })
              .backgroundColor('#ED6F21')
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.5, y: 0.5 }))
                .animation({ duration: DURATION, curve: Curve.Friction, delay: INTERVAL * index }))
              .borderRadius(10)
            }
            .transition(TransitionEffect.opacity(0.99))
          }, (item: number) => item.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(15)
        .columnsGap(15)
        .size({ width: 180, height: 180 })
        .transition(TransitionEffect.opacity(0.99))
      }
    }
    .size({ width: '100%', height: '100%' })
    .onClick(() => {
      this.getUIContext()?.animateTo({
        duration: DURATION + INTERVAL * (ITEM_COUNTS - 1),
        curve: Curve.Friction
      }, () => {
        this.isGridShow = !this.isGridShow;
      })
    })
  }
}
```

---

## 模态转场

模态转场是新的界面覆盖在旧的界面上，旧的界面不消失的一种转场方式。

### 模态转场接口

| 接口 | 说明 | 使用场景 |
|------|------|----------|
| bindContentCover | 弹出全屏的模态组件 | 自定义全屏模态展示，如查看大图 |
| bindSheet | 弹出半模态组件 | 半模态展示，如分享框 |
| bindMenu | 弹出菜单，点击组件后弹出 | Menu菜单场景 |
| bindContextMenu | 弹出菜单，长按或右键点击后弹出 | 长按浮起效果 |
| bindPopup | 弹出Popup弹框 | 临时说明提示 |
| if | 通过if新增或删除组件 | 临时显示界面 |

### bindContentCover 全屏模态转场

```typescript
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct BindContentCoverDemo {
  @State isPresent: boolean = false;

  @Builder
  MyBuilder() {
    Column() {
      Text('选择乘车人')
        .fontSize(20)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 30, bottom: 15 })
    }
    .backgroundColor(0x007dfe)
    .size({ width: '100%', height: '100%' })
    .backgroundColor(0xf5f5f5)
    .transition(TransitionEffect.translate({ y: 1000 }).animation({ curve: curves.springMotion(0.6, 0.8) }))
  }

  build() {
    Column() {
      Text('选择乘车人')
        .fontSize(18)
        .fontColor(Color.Orange)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 10, bottom: 10 })
        .width('60%')
        .textAlign(TextAlign.Center)
        .borderRadius(15)
        .bindContentCover(this.isPresent, this.MyBuilder(), {
          modalTransition: ModalTransition.DEFAULT,
          onDisappear: () => {
            if (this.isPresent) {
              this.isPresent = !this.isPresent;
            }
          }
        })
        .onClick(() => {
          this.isPresent = !this.isPresent;
        })
    }
  }
}
```

### bindSheet 半模态转场

```typescript
@Entry
@Component
struct BindSheetDemo {
  @State isShowSheet: boolean = false;
  private menuList: string[] = ['不要辣', '少放辣', '多放辣', '不要香菜'];

  @Builder
  mySheet() {
    Column() {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.menuList, (item: string) => {
          Text(item)
            .fontSize(16)
            .fontColor(0x333333)
            .backgroundColor(0xf1f1f1)
            .borderRadius(8)
            .margin(10)
            .padding(15)
        })
      }
      .padding({ top: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      Text('口味与餐具')
        .fontSize(28)
        .padding({ top: 30, bottom: 30 })

      Row()
        .width('90%')
        .padding(15)
        .backgroundColor(Color.White)
        .bindSheet(this.isShowSheet, this.mySheet(), {
          height: 300,
          dragBar: false,
          onDisappear: () => {
            this.isShowSheet = !this.isShowSheet;
          }
        })
        .onClick(() => {
          this.isShowSheet = !this.isShowSheet;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xf1f1f1)
  }
}
```

### bindMenu 菜单弹出

```typescript
@Entry
@Component
struct BindMenuDemo {
  @State items: MenuElement[] = [
    { value: '菜单项1', action: () => {} },
    { value: '菜单项2', action: () => {} },
  ]

  build() {
    Column() {
      Button('click')
        .backgroundColor(0x409eff)
        .bindMenu(this.items)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(437)
  }
}
```

### bindContextMenu 长按菜单

```typescript
@Entry
@Component
struct BindContextMenuDemo {
  private menu: string[] = ['保存图片', '收藏', '搜一搜'];

  @Builder
  myMenu() {
    Column() {
      ForEach(this.menu, (item: string) => {
        Row() {
          Text(item)
            .fontSize(18)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .padding(15)
        .border({ width: { bottom: 1 }, color: 0xcccccc })
      })
    }
    .width(140)
    .borderRadius(15)
    .backgroundColor(0xf1f1f1)
  }

  build() {
    Column() {
      Image($r('app.media.icon'))
        .width('100%')
        .bindContextMenu(this.myMenu, ResponseType.LongPress)
    }
    .width('100%')
  }
}
```

### bindPopup 气泡弹窗

```typescript
@Entry
@Component
struct BindPopupDemo {
  @State customPopup: boolean = false;

  @Builder
  popupBuilder() {
    Column({ space: 2 }) {
      Row()
        .width(64)
        .height(64)
        .backgroundColor(0x409eff)
      Text('Popup')
        .fontSize(10)
        .fontColor(Color.White)
    }
    .width(100)
    .height(100)
    .padding(5)
  }

  build() {
    Column() {
      Button('click')
        .onClick(() => {
          this.customPopup = !this.customPopup;
        })
        .bindPopup(this.customPopup, {
          builder: this.popupBuilder,
          placement: Placement.Top,
          maskColor: 0x33000000,
          popupColor: 0xf56c6c,
          enableArrow: true,
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.customPopup = false;
            }
          }
        })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(437)
  }
}
```

### 使用if实现模态转场

```typescript
@Entry
@Component
struct ModalTransitionWithIf {
  @State isShowShare: boolean = false;

  build() {
    Stack() {
      Column() {
        Text('设置')
          .fontSize(28)
          .fontColor(0x333333)

        List({ space: 12 }) {
          ListItem() {
            Row() {
              Text('连接与共享')
            }
          }
          .onClick(() => {
            this.getUIContext()?.animateTo({ duration: 500 }, () => {
              this.isShowShare = !this.isShowShare;
            })
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(0xfefefe)

      if (this.isShowShare) {
        Column() {
          Text('连接与共享')
            .fontSize(28)
            .fontColor(0x333333)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(0xffffff)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: '100%' }))
          .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
      }
    }
  }
}
```

---

## 共享元素转场 (一镜到底)

共享元素转场是一种界面切换时对相同或者相似的两个元素做的一种位置和大小匹配的过渡动画效果。

### 实现方式对比

| 实现方式 | 特点 | 适用场景 |
|----------|------|----------|
| 不新建容器直接变化原容器 | 不发生路由跳转，在一个组件中实现 | 转场开销小的简单场景 |
| 新建容器并跨容器迁移组件 | 通过NodeController将组件迁移 | 新建对象开销大的场景 |
| 使用geometryTransition共享元素转场 | 利用系统能力，自动添加过渡效果 | 创建新节点开销小的场景 |

### 不新建容器直接变化原容器

```typescript
import { common } from '@kit.AbilityKit';

class PostData {
  avatar: Resource = $r('app.media.flower');
  name: string = '';
  message: ResourceStr = '';
  images: Resource[] = [];
}

@Entry
@Component
struct Index {
  @State isExpand: boolean = false;
  @State selectedIndex: number = -1;
  private allPostData: PostData[] = [
    { name: 'Alice', message: '天气晴朗' },
    { name: 'Bob', message: '你好世界' }
  ];

  build() {
    Column({ space: 20 }) {
      ForEach(this.allPostData, (postData: PostData, index: number) => {
        if (!this.isExpand || this.selectedIndex === index) {
          Column() {
            Text(postData.name)
            Text(postData.message)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: index < this.selectedIndex ? -250 : 250 }))
            .animation({ duration: 350, curve: Curve.Friction }))
        }
      }, (postData: PostData, index: number) => index.toString())
    }
    .size({ width: '100%', height: '100%' })
    .backgroundColor('#40808080')
  }
}
```

### 使用geometryTransition

```typescript
@Entry
@Component
struct GeometryTransitionDemo {
  @State isExpanded: boolean = false;

  build() {
    Stack() {
      if (this.isExpanded) {
        Column() {
          Text('Expanded Content')
            .fontSize(24)
            .fontColor(Color.White)
        }
        .width('80%')
        .height(300)
        .backgroundColor(0xf56c6c)
        .borderRadius(20)
        .geometryTransition('transition_id')
      } else {
        Column() {
          Text('Small')
            .fontSize(16)
            .fontColor(Color.White)
        }
        .width(100)
        .height(100)
        .backgroundColor(0xf56c6c)
        .borderRadius(10)
        .geometryTransition('transition_id')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.getUIContext()?.animateTo({ duration: 500, curve: Curve.EaseInOut }, () => {
        this.isExpanded = !this.isExpanded;
      })
    })
  }
}
```

---

## 页面转场动画

为了实现更好的转场效果，推荐使用Navigation转场动画和模态转场。

### PageTransitionEnter 和 PageTransitionExit

```typescript
@Entry
@Component
struct PageTransitionSrc {
  build() {
    Column() {
      Image($r('app.media.mountain'))
        .width('90%')
        .height('80%')
        .objectFit(ImageFit.Fill)
        .margin(30)

      Row({ space: 10 }) {
        Button('pushUrl')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PageTransitionDst' });
          })
        Button('back')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
      }
    }
    .width('100%').height('100%')
  }

  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 1000 })
      .slide(SlideEffect.Right)
    PageTransitionEnter({ type: RouteType.Pop, duration: 1000 })
      .slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Push, duration: 1000 })
      .slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: 1000 })
      .slide(SlideEffect.Right)
  }
}
```

### RouteType 说明

| RouteType | 说明 |
|-----------|------|
| None | 对页面栈的push、pop操作均生效 |
| Push | 仅对页面栈的push操作生效 |
| Pop | 仅对页面栈的pop操作生效 |

### 禁用页面转场

```typescript
pageTransition() {
  PageTransitionEnter({ type: RouteType.None, duration: 0 })
  PageTransitionExit({ type: RouteType.None, duration: 0 })
}
```

---

## 导航转场

推荐使用Navigation组件实现转场动画，通过customNavContentTransition配置自定义转场。

```typescript
@Entry
@Component
struct NavigationDemo {
  private pageInfos: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pageInfos)
      .hideNavBar(true)
      .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
        let customAnimation: NavigationAnimatedTransition = {
          onTransitionEnd: (isSuccess: boolean) => {
            console.info('transition result: ' + isSuccess);
          },
          timeout: 2000,
          transition: (transitionProxy: NavigationTransitionProxy) => {
            // 自定义转场逻辑
            transitionProxy.finishTransition();
          }
        };
        return customAnimation;
      })
  }
}
```

## 转场动画注意事项

1. **转场动画应该作用于将要出现或消失的组件**，始终显示的组件应使用属性动画

2. **如果使用属性动画实现组件转场**，开发者需在动画结束回调中手动删除组件节点

3. **多个组件添加转场效果时**，注意父控件也需要添加转场效果，否则子组件的消失转场不会生效

4. **推荐使用Navigation转场和模态转场**，而不是传统的page+router方式

5. **不要在UIAbility之间实现转场**，UIAbility是一个任务，会在多任务界面独立显示为一个卡片，UIAbility之间的跳转相当于任务之间的跳转

---

## 相关链接

- [属性动画](animation.md)
- [导航路由](../08-navigation-routing/navigation-routing.md)
- [弹窗与模态](../07-dialogs-modals/modals-pages.md)