// 动画示例模板

// ========== 属性动画 ==========
@Entry
@Component
struct PropertyAnimationExample {
  @State width: number = 100
  @State height: number = 100
  @State borderRadius: number = 0
  @State backgroundColor: Color = Color.Blue
  @State rotate: number = 0
  @State scale: number = 1
  
  build() {
    Column({ space: 30 }) {
      // 动画目标
      Column()
        .width(this.width)
        .height(this.height)
        .borderRadius(this.borderRadius)
        .backgroundColor(this.backgroundColor)
        .rotate({ angle: this.rotate })
        .scale({ x: this.scale, y: this.scale })
        .animation({
          duration: 500,
          curve: Curve.EaseInOut
        })
      
      Row({ space: 10 }) {
        Button('变宽')
          .onClick(() => this.width = this.width === 100 ? 200 : 100)
        
        Button('变圆')
          .onClick(() => this.borderRadius = this.borderRadius === 0 ? 50 : 0)
        
        Button('变色')
          .onClick(() => this.backgroundColor = 
            this.backgroundColor === Color.Blue ? Color.Red : Color.Blue)
      }
      
      Row({ space: 10 }) {
        Button('旋转')
          .onClick(() => this.rotate += 90)
        
        Button('缩放')
          .onClick(() => this.scale = this.scale === 1 ? 1.5 : 1)
      }
    }
    .padding(20)
  }
}

// ========== 显式动画 animateTo ==========
@Entry
@Component
struct ExplicitAnimationExample {
  @State translateX: number = 0
  @State translateY: number = 0
  @State opacity: number = 1
  
  build() {
    Column({ space: 30 }) {
      // 动画目标
      Column() {
        Text('显式动画')
          .fontColor(Color.White)
      }
      .width(100)
      .height(100)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .translate({ x: this.translateX, y: this.translateY })
      .opacity(this.opacity)
      
      Row({ space: 10 }) {
        Button('向右移动')
          .onClick(() => {
            animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
              this.translateX += 50
            })
          })
        
        Button('向下移动')
          .onClick(() => {
            animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
              this.translateY += 50
            })
          })
        
        Button('重置')
          .onClick(() => {
            animateTo({ duration: 500, curve: Curve.Spring }, () => {
              this.translateX = 0
              this.translateY = 0
            })
          })
      }
      
      Button('淡入淡出')
        .onClick(() => {
          animateTo({ duration: 500 }, () => {
            this.opacity = this.opacity === 1 ? 0.3 : 1
          })
        })
    }
    .padding(20)
  }
}

// ========== 关键帧动画 ==========
@Entry
@Component
struct KeyframeAnimationExample {
  @State state: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('关键帧动画')
          .fontColor(Color.White)
      }
      .width(100)
      .height(100)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .keyframeAnimateTo(
        2000,
        [
          { eventName: 'start', eventValue: 0 },
          { eventName: '25%', eventValue: 0.25 },
          { eventName: '50%', eventValue: 0.5 },
          { eventName: '75%', eventValue: 0.75 },
          { eventName: 'end', eventValue: 1 }
        ],
        {
          keyframes: [
            { time: 0, value: { width: 100, height: 100 } },
            { time: 0.25, value: { width: 150, height: 150 } },
            { time: 0.5, value: { width: 80, height: 80 } },
            { time: 0.75, value: { width: 130, height: 130 } },
            { time: 1, value: { width: 100, height: 100 } }
          ]
        }
      )
      
      Button('播放动画')
        .onClick(() => this.state++)
    }
    .padding(20)
  }
}

// ========== 组件转场动画 ==========
@Entry
@Component
struct TransitionExample {
  @State show: boolean = false
  
  build() {
    Column({ space: 30 }) {
      if (this.show) {
        Column() {
          Text('出现/消失动画')
            .fontColor(Color.White)
        }
        .width(150)
        .height(100)
        .backgroundColor(0x317aff)
        .borderRadius(8)
        .transition({
          type: TransitionType.All,
          opacity: 0,
          translate: { y: -50 },
          scale: { x: 0.5, y: 0.5 }
        })
      }
      
      Button(this.show ? '隐藏' : '显示')
        .onClick(() => {
          animateTo({ duration: 300 }, () => {
            this.show = !this.show
          })
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }
}

// ========== 页面转场动画 ==========
@Entry
@Component
struct PageTransitionExample {
  @State showSecondPage: boolean = false
  
  build() {
    Stack() {
      if (!this.showSecondPage) {
        Column() {
          Text('第一页')
            .fontSize(24)
          
          Button('跳转')
            .margin({ top: 20 })
            .onClick(() => {
              animateTo({ duration: 300 }, () => {
                this.showSecondPage = true
              })
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.White)
        .transition({
          type: TransitionType.Delete,
          translate: { x: -300 },
          opacity: 0
        })
      }
      
      if (this.showSecondPage) {
        Column() {
          Text('第二页')
            .fontSize(24)
          
          Button('返回')
            .margin({ top: 20 })
            .onClick(() => {
              animateTo({ duration: 300 }, () => {
                this.showSecondPage = false
              })
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(0xf5f5f5)
        .transition({
          type: TransitionType.Insert,
          translate: { x: 300 },
          opacity: 0
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// ========== 共享元素转场 ==========
@Entry
@Component
struct SharedTransitionExample {
  @State showDetail: boolean = false
  
  build() {
    Stack() {
      if (!this.showDetail) {
        Column() {
          Row() {
            Column()
              .width(80)
              .height(80)
              .backgroundColor(0x317aff)
              .borderRadius(8)
              .sharedTransition('shared-image', {
                duration: 300,
                curve: Curve.EaseInOut
              })
            
            Column() {
              Text('标题')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
              Text('描述信息')
                .fontSize(14)
                .fontColor(Color.Gray)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
            .layoutWeight(1)
          }
          .width('90%')
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            animateTo({ duration: 300 }, () => {
              this.showDetail = true
            })
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(0xf5f5f5)
      }
      
      if (this.showDetail) {
        Column() {
          Column()
            .width('100%')
            .height(300)
            .backgroundColor(0x317aff)
            .sharedTransition('shared-image', {
              duration: 300,
              curve: Curve.EaseInOut
            })
          
          Column() {
            Text('详情标题')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
            
            Text('详细描述信息...')
              .fontSize(16)
              .margin({ top: 10 })
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White)
        .onClick(() => {
          animateTo({ duration: 300 }, () => {
            this.showDetail = false
          })
        })
      }
    }
  }
}

// ========== 弹簧动画 ==========
@Entry
@Component
struct SpringAnimationExample {
  @State scale: number = 1
  @State translateY: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('弹簧动画')
          .fontColor(Color.White)
      }
      .width(100)
      .height(100)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .scale({ x: this.scale, y: this.scale })
      .translate({ y: this.translateY })
      
      Row({ space: 10 }) {
        Button('弹跳')
          .onClick(() => {
            animateTo({
              duration: 1000,
              curve: curves.springMotion(0.6, 0.8)
            }, () => {
              this.scale = this.scale === 1 ? 1.5 : 1
            })
          })
        
        Button('跳动')
          .onClick(() => {
            animateTo({
              duration: 1000,
              curve: curves.interpolatingSpring(10, 1, 228, 30)
            }, () => {
              this.translateY = this.translateY === 0 ? -100 : 0
            })
          })
      }
    }
    .padding(20)
  }
}

// ========== 按钮点击动画 ==========
@Entry
@Component
struct ButtonClickAnimation {
  @State scale: number = 1
  @State opacity: number = 1
  
  build() {
    Column({ space: 30 }) {
      Button('点击效果')
        .width(200)
        .height(50)
        .scale({ x: this.scale, y: this.scale })
        .opacity(this.opacity)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            animateTo({ duration: 100 }, () => {
              this.scale = 0.95
              this.opacity = 0.8
            })
          } else if (event.type === TouchType.Up) {
            animateTo({ duration: 100 }, () => {
              this.scale = 1
              this.opacity = 1
            })
          }
        })
    }
    .padding(20)
  }
}

// ========== 加载动画 ==========
@Entry
@Component
struct LoadingAnimationExample {
  @State rotate: number = 0
  
  aboutToAppear(): void {
    this.startAnimation()
  }
  
  startAnimation() {
    animateTo({
      duration: 1000,
      curve: Curve.Linear,
      iterations: -1  // 无限循环
    }, () => {
      this.rotate = 360
    })
  }
  
  build() {
    Column({ space: 30 }) {
      Column() {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(Color.White)
      }
      .width(80)
      .height(80)
      .backgroundColor(0x317aff)
      .borderRadius(40)
      .justifyContent(FlexAlign.Center)
      .rotate({ angle: this.rotate })
      
      Text('加载中...')
        .fontSize(16)
        .fontColor(Color.Gray)
    }
    .padding(20)
  }
}