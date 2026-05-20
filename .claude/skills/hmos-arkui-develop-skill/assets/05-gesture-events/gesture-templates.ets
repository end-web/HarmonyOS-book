import { GestureEvent, GestureJudgeResult, GestureRecognizer, BaseGestureEvent } from '@kit.ArkUI'

// ========== 点击手势 ==========
@Entry
@Component
struct TapGestureExample {
  @State count: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('单击我')
          .fontSize(20)
          .fontColor(Color.White)
      }
      .width(150)
      .height(100)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .gesture(
        TapGesture({ count: 1 })
          .onAction(() => {
            this.count++
            console.info('单击')
          })
      )
      
      Text(`单击次数: ${this.count}`)
        .fontSize(18)
    }
    .padding(20)
  }
}

// ========== 双击手势 ==========
@Entry
@Component
struct DoubleTapGestureExample {
  @State liked: boolean = false
  @State scale: number = 1
  
  build() {
    Column({ space: 30 }) {
      Column() {
        SymbolGlyph($r(this.liked ? 'sys.symbol.heart_fill' : 'sys.symbol.heart'))
          .fontSize(40)
          .fontColor([this.liked ? Color.Red : Color.Gray])
      }
      .width(150)
      .height(150)
      .backgroundColor(0xf5f5f5)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.scale, y: this.scale })
      .gesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.liked = !this.liked
            animateTo({ duration: 200, curve: Curve.Spring }, () => {
              this.scale = 1.2
            })
            setTimeout(() => {
              animateTo({ duration: 200 }, () => {
                this.scale = 1
              })
            }, 200)
          })
      )
      
      Text('双击点赞')
        .fontSize(16)
        .fontColor(Color.Gray)
    }
    .padding(20)
  }
}

// ========== 长按手势 ==========
@Entry
@Component
struct LongPressGestureExample {
  @State progress: number = 0
  @State isLongPressing: boolean = false
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text(`${Math.floor(this.progress)}%`)
          .fontSize(24)
          .fontColor(Color.White)
      }
      .width(150)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(75)
      .justifyContent(FlexAlign.Center)
      .gesture(
        LongPressGesture({ repeat: true })
          .onAction(() => {
            if (this.isLongPressing) {
              this.progress = Math.min(100, this.progress + 2)
              if (this.progress >= 100) {
                this.isLongPressing = false
                this.progress = 0
                console.info('长按完成')
              }
            }
          })
          .onActionStart(() => {
            this.isLongPressing = true
            this.progress = 0
            console.info('开始长按')
          })
          .onActionEnd(() => {
            this.isLongPressing = false
            this.progress = 0
            console.info('结束长按')
          })
      )
      
      Text('长按进度条')
        .fontSize(16)
        .fontColor(Color.Gray)
    }
    .padding(20)
  }
}

// ========== 拖动手势 ==========
@Entry
@Component
struct PanGestureExample {
  @State translateX: number = 0
  @State translateY: number = 0
  @State lastX: number = 0
  @State lastY: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('拖动我')
          .fontSize(18)
          .fontColor(Color.White)
      }
      .width(100)
      .height(100)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .translate({ x: this.translateX, y: this.translateY })
      .gesture(
        PanGesture()
          .onActionStart(() => {
            this.lastX = this.translateX
            this.lastY = this.translateY
          })
          .onActionUpdate((event: GestureEvent) => {
            this.translateX = this.lastX + event.offsetX
            this.translateY = this.lastY + event.offsetY
          })
      )
      
      Button('重置')
        .onClick(() => {
          animateTo({ duration: 300 }, () => {
            this.translateX = 0
            this.translateY = 0
          })
        })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
  }
}

// ========== 缩放手势 ==========
@Entry
@Component
struct PinchGestureExample {
  @State scale: number = 1
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Image($r('app.media.icon'))
          .width(200)
          .height(200)
          .objectFit(ImageFit.Contain)
      }
      .width(300)
      .height(300)
      .backgroundColor(0xf5f5f5)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.scale, y: this.scale })
      .gesture(
        PinchGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.scale = Math.max(0.5, Math.min(3, event.scale))
          })
          .onActionEnd(() => {
            if (this.scale < 0.8) {
              animateTo({ duration: 200 }, () => {
                this.scale = 1
              })
            }
          })
      )
      
      Text(`缩放: ${this.scale.toFixed(2)}`)
        .fontSize(16)
      
      Button('重置')
        .onClick(() => {
          animateTo({ duration: 200 }, () => {
            this.scale = 1
          })
        })
    }
    .padding(20)
  }
}

// ========== 旋转手势 ==========
@Entry
@Component
struct RotationGestureExample {
  @State angle: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('旋转我')
          .fontSize(20)
          .fontColor(Color.White)
      }
      .width(150)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .rotate({ angle: this.angle })
      .gesture(
        RotationGesture()
          .onActionUpdate((event: GestureEvent) => {
            this.angle += event.angle
          })
      )
      
      Text(`角度: ${this.angle.toFixed(0)}°`)
        .fontSize(16)
      
      Button('重置')
        .onClick(() => {
          animateTo({ duration: 300 }, () => {
            this.angle = 0
          })
        })
    }
    .padding(20)
  }
}

// ========== 滑动手势 ==========
@Entry
@Component
struct SwipeGestureExample {
  @State direction: string = '无'
  @State color: Color = Color.Gray
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('滑动我')
          .fontSize(20)
          .fontColor(Color.White)
      }
      .width(200)
      .height(200)
      .backgroundColor(this.color)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .gesture(
        SwipeGesture({ speed: 100 })
          .onAction((event: GestureEvent) => {
            if (event.angle > -45 && event.angle < 45) {
              this.direction = '向右'
              this.color = Color.Blue
            } else if (event.angle > 135 || event.angle < -135) {
              this.direction = '向左'
              this.color = Color.Red
            } else if (event.angle >= 45 && event.angle <= 135) {
              this.direction = '向上'
              this.color = Color.Green
            } else {
              this.direction = '向下'
              this.color = Color.Orange
            }
          })
      )
      
      Text(`方向: ${this.direction}`)
        .fontSize(18)
    }
    .padding(20)
  }
}

// ========== 组合手势 - 并行 ==========
@Entry
@Component
struct ParallelGestureExample {
  @State singleTapCount: number = 0
  @State doubleTapCount: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text(`单击: ${this.singleTapCount}`)
          .fontSize(18)
        Text(`双击: ${this.doubleTapCount}`)
          .fontSize(18)
      }
      .width(200)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          TapGesture({ count: 1 })
            .onAction(() => {
              this.singleTapCount++
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              this.doubleTapCount++
            })
        )
      )
      
      Text('单击和双击可同时触发')
        .fontSize(14)
        .fontColor(Color.Gray)
    }
    .padding(20)
  }
}

// ========== 组合手势 - 互斥 ==========
@Entry
@Component
struct ExclusiveGestureExample {
  @State singleTapCount: number = 0
  @State doubleTapCount: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text(`单击: ${this.singleTapCount}`)
          .fontSize(18)
        Text(`双击: ${this.doubleTapCount}`)
          .fontSize(18)
      }
      .width(200)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })  // 双击优先
            .onAction(() => {
              this.doubleTapCount++
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              this.singleTapCount++
            })
        )
      )
      
      Text('双击在前，单击或双击二选一')
        .fontSize(14)
        .fontColor(Color.Gray)
    }
    .padding(20)
  }
}

// ========== 组合手势 - 顺序（长按后拖动）==========
@Entry
@Component
struct SequenceGestureExample {
  @State translateX: number = 0
  @State translateY: number = 0
  @State lastX: number = 0
  @State lastY: number = 0
  @State isDragging: boolean = false
  @State borderColor: Color = Color.Blue
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text(this.isDragging ? '拖动中...' : '长按后拖动')
          .fontSize(16)
          .fontColor(Color.White)
      }
      .width(150)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .borderWidth(3)
      .borderColor(this.borderColor)
      .justifyContent(FlexAlign.Center)
      .translate({ x: this.translateX, y: this.translateY })
      .gesture(
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ duration: 300 })
            .onAction(() => {
              this.isDragging = true
              this.borderColor = Color.Orange
            }),
          PanGesture()
            .onActionStart(() => {
              this.lastX = this.translateX
              this.lastY = this.translateY
            })
            .onActionUpdate((event: GestureEvent) => {
              this.translateX = this.lastX + event.offsetX
              this.translateY = this.lastY + event.offsetY
            })
            .onActionEnd(() => {
              this.isDragging = false
              this.borderColor = Color.Blue
            })
        )
        .onCancel(() => {
          this.isDragging = false
          this.borderColor = Color.Blue
        })
      )
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
  }
}

// ========== 综合手势（缩放+旋转+拖动）==========
@Entry
@Component
struct CombinedGestureExample {
  @State scale: number = 1
  @State angle: number = 0
  @State translateX: number = 0
  @State translateY: number = 0
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('捏合缩放\n双指旋转\n单指拖动')
          .fontSize(16)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
      }
      .width(200)
      .height(200)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.scale, y: this.scale })
      .rotate({ angle: this.angle })
      .translate({ x: this.translateX, y: this.translateY })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture()
            .onActionUpdate((event: GestureEvent) => {
              this.scale = Math.max(0.5, Math.min(3, event.scale))
            }),
          RotationGesture()
            .onActionUpdate((event: GestureEvent) => {
              this.angle += event.angle
            }),
          PanGesture()
            .onActionUpdate((event: GestureEvent) => {
              this.translateX += event.offsetX
              this.translateY += event.offsetY
            })
        )
      )
      
      Button('重置')
        .onClick(() => {
          animateTo({ duration: 300 }, () => {
            this.scale = 1
            this.angle = 0
            this.translateX = 0
            this.translateY = 0
          })
        })
    }
    .padding(20)
  }
}

// ========== 触摸事件 ==========
@Entry
@Component
struct TouchEventExample {
  @State x: number = 0
  @State y: number = 0
  @State eventType: string = ''
  @State bgColor: Color = Color.Blue
  
  build() {
    Column({ space: 30 }) {
      Column() {
        Text('触摸我')
          .fontSize(20)
          .fontColor(Color.White)
      }
      .width(200)
      .height(200)
      .backgroundColor(this.bgColor)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .onTouch((event: TouchEvent) => {
        this.x = event.touches[0].x
        this.y = event.touches[0].y
        
        if (event.type === TouchType.Down) {
          this.eventType = '按下'
          this.bgColor = Color.Orange
        } else if (event.type === TouchType.Move) {
          this.eventType = '移动'
        } else if (event.type === TouchType.Up) {
          this.eventType = '抬起'
          this.bgColor = Color.Blue
        } else if (event.type === TouchType.Cancel) {
          this.eventType = '取消'
          this.bgColor = Color.Blue
        }
      })
      
      Column() {
        Text(`类型: ${this.eventType}`)
        Text(`坐标: (${this.x.toFixed(0)}, ${this.y.toFixed(0)})`)
      }
      .fontSize(16)
    }
    .padding(20)
  }
}

// ========== 手势冲突处理 - 自定义判定 ==========
@Entry
@Component
struct GestureJudgeExample {
  @State count: number = 0
  
  build() {
    Column() {
      Column() {
        Text('点击计数: ' + this.count)
          .fontSize(20)
          .fontColor(Color.White)
      }
      .width(200)
      .height(150)
      .backgroundColor(0x317aff)
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.count++
      })
      .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
        // 每5次禁用一次子组件点击
        if (this.count % 5 == 4 && gestureInfo.type == GestureControl.GestureType.CLICK) {
          return GestureJudgeResult.REJECT
        }
        return GestureJudgeResult.CONTINUE
      })
    }
    .gesture(
      TapGesture()
        .onAction(() => {
          this.count++
          console.info('父组件响应')
        })
    )
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

// ========== 多层级事件控制 ==========
@Entry
@Component
struct HitTestBehaviorExample {
  @State log: string = ''
  
  build() {
    Column({ space: 20 }) {
      Text('多层级事件测试')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      // 场景1: Default
      Column() {
        Text('子组件')
          .padding(20)
          .backgroundColor(Color.Orange)
          .onClick(() => this.log += '子组件\n' )
      }
      .padding(20)
      .backgroundColor(Color.Blue)
      .onClick(() => this.log += '父组件\n')
      // .hitTestBehavior(HitTestMode.Default)  // 默认：子组件优先
      
      // 场景2: Transparent - 父子都可响应
      Column() {
        Text('子组件(Transparent)')
          .padding(20)
          .backgroundColor(Color.Orange)
          .onClick(() => this.log += '子组件\n')
      }
      .padding(20)
      .backgroundColor(Color.Green)
      .onClick(() => this.log += '父组件\n')
      .hitTestBehavior(HitTestMode.Transparent)
      
      // 场景3: Block - 父组件阻塞子组件
      Column() {
        Text('子组件(Block)')
          .padding(20)
          .backgroundColor(Color.Orange)
          .onClick(() => this.log += '子组件\n')
      }
      .padding(20)
      .backgroundColor(Color.Red)
      .onClick(() => this.log += '父组件\n')
      .hitTestBehavior(HitTestMode.Block)
      
      Text('日志:\n' + this.log)
        .width('100%')
        .height(100)
        .border({ width: 1 })
        .fontSize(12)
      
      Button('清空')
        .onClick(() => this.log = '')
    }
    .width('100%')
    .padding(20)
  }
}

// ========== 父子手势优先级 ==========
@Entry
@Component
struct GesturePriorityExample {
  @State log: string = ''
  
  build() {
    Column({ space: 20 }) {
      Text('父子手势优先级')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      // gesture - 子组件优先
      Column() {
        Text('子组件(gesture)')
          .padding(20)
          .backgroundColor(Color.Orange)
          .gesture(
            TapGesture()
              .onAction(() => this.log += '子组件响应\n')
          )
      }
      .padding(20)
      .backgroundColor(Color.Blue)
      .gesture(
        TapGesture()
          .onAction(() => this.log += '父组件响应\n')
      )
      
      // priorityGesture - 父组件优先
      Column() {
        Text('子组件(priorityGesture)')
          .padding(20)
          .backgroundColor(Color.Orange)
          .gesture(
            TapGesture()
              .onAction(() => this.log += '子组件响应\n')
          )
      }
      .padding(20)
      .backgroundColor(Color.Green)
      .priorityGesture(
        TapGesture()
          .onAction(() => this.log += '父组件优先响应\n')
      )
      
      // parallelGesture - 父子同时
      Column() {
        Text('子组件(parallelGesture)')
          .padding(20)
          .backgroundColor(Color.Orange)
          .gesture(
            TapGesture()
              .onAction(() => this.log += '子组件响应\n')
          )
      }
      .padding(20)
      .backgroundColor(Color.Purple)
      .parallelGesture(
        TapGesture()
          .onAction(() => this.log += '父组件也响应\n')
      )
      
      Text('日志:\n' + this.log)
        .width('100%')
        .height(80)
        .border({ width: 1 })
        .fontSize(12)
      
      Button('清空')
        .onClick(() => this.log = '')
    }
    .width('100%')
    .padding(20)
  }
}