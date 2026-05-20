// 布局组件示例模板

// ========== Row 水平布局 ==========
@Entry
@Component
struct RowExample {
  build() {
    Column({ space: 20 }) {
      Text('基本Row')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      
      Row({ space: 10 }) {
        Text('1').width(50).height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('2').width(50).height(50).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        Text('3').width(50).height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      
      Text('space-between')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      
      Row() {
        Text('左').width(60).height(40).backgroundColor(0x317aff).fontColor(Color.White).textAlign(TextAlign.Center)
        Text('右').width(60).height(40).backgroundColor(0x317aff).fontColor(Color.White).textAlign(TextAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 20, right: 20 })
      
      Text('Blank填充')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      
      Row() {
        Text('标题')
        Blank()
        Text('操作')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(0xf5f5f5)
      
      Text('layoutWeight分配')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      
      Row() {
        Text('1:1').layoutWeight(1).height(40).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('2:1').layoutWeight(2).height(40).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
  }
}

// ========== Column 垂直布局 ==========
@Entry
@Component
struct ColumnExample {
  build() {
    Column({ space: 10 }) {
      Text('顶部')
        .width('100%')
        .height(50)
        .backgroundColor(0x317aff)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
      
      Text('中间（layoutWeight: 1）')
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(0xf5f5f5)
        .textAlign(TextAlign.Center)
      
      Text('底部')
        .width('100%')
        .height(50)
        .backgroundColor(0x317aff)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(300)
  }
}

// ========== Flex 弹性布局 ==========
@Entry
@Component
struct FlexExample {
  build() {
    Column({ space: 20 }) {
      Text('不换行，子元素压缩')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Flex({ wrap: FlexWrap.NoWrap }) {
        Text('1').width('40%').height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('2').width('40%').height(50).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        Text('3').width('40%').height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
      }
      .width('100%')
      .backgroundColor(0xAFEEEE)
      
      Text('换行')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Text('1').width('45%').height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('2').width('45%').height(50).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        Text('3').width('45%').height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('4').width('45%').height(50).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
      }
      .width('100%')
      
      Text('flexGrow分配')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Flex() {
        Text('固定').width(80).height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        Text('flexGrow:1').flexGrow(1).height(50).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        Text('固定').width(80).height(50).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }
}

// ========== Stack 层叠布局 ==========
@Entry
@Component
struct StackExample {
  build() {
    Column({ space: 20 }) {
      Text('层叠布局')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Stack({ alignContent: Alignment.Bottom }) {
        Text('底层')
          .width(200).height(200)
          .backgroundColor(0xF5DEB3)
          .textAlign(TextAlign.Center)
        
        Text('中层')
          .width(150).height(150)
          .backgroundColor(0xD2B48C)
          .textAlign(TextAlign.Center)
        
        Text('顶层')
          .width(100).height(100)
          .backgroundColor(0x317aff)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
      }
      .width(200)
      .height(200)
      
      Text('zIndex控制层级')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      Stack() {
        Text('红色')
          .width(100).height(100)
          .backgroundColor(Color.Red)
          .zIndex(1)
        
        Text('蓝色')
          .width(100).height(100)
          .backgroundColor(Color.Blue)
          .offset({ x: 30, y: 30 })
          .zIndex(2)
      }
      .width(150)
      .height(150)
    }
    .width('100%')
    .padding(16)
  }
}

// ========== RelativeContainer 相对布局 ==========
@Entry
@Component
struct RelativeContainerExample {
  build() {
    Column({ space: 20 }) {
      Text('相对布局 - 基本定位')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      RelativeContainer() {
        Row()
          .width(80).height(80)
          .backgroundColor(0xF5DEB3)
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
          .id('row1')
        
        Row()
          .width(80).height(80)
          .backgroundColor(0xD2B48C)
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            right: { anchor: '__container__', align: HorizontalAlign.End }
          })
          .id('row2')
        
        Row()
          .width(80).height(80)
          .backgroundColor(0x317aff)
          .alignRules({
            bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
          .id('row3')
        
        Row()
          .width(80).height(80)
          .backgroundColor(0x4caf50)
          .alignRules({
            bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
            right: { anchor: '__container__', align: HorizontalAlign.End }
          })
          .id('row4')
      }
      .width(250).height(250)
      .border({ width: 1, color: '#ccc' })
      
      Text('相对布局 - 兄弟锚点')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      RelativeContainer() {
        Row()
          .width(100).height(60)
          .backgroundColor(0xF5DEB3)
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start }
          })
          .id('header')
        
        Row()
          .width(100).height(100)
          .backgroundColor(0xD2B48C)
          .alignRules({
            top: { anchor: 'header', align: VerticalAlign.Bottom },
            left: { anchor: 'header', align: HorizontalAlign.End }
          })
          .id('content')
      }
      .width(250).height(200)
      .border({ width: 1, color: '#ccc' })
    }
    .width('100%')
    .padding(16)
  }
}

// ========== GridRow 栅格布局 ==========
@Entry
@Component
struct GridRowExample {
  @State columns: number = 2
  
  build() {
    Column({ space: 20 }) {
      Text('栅格布局 - 响应式')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      
      GridRow({ columns: this.columns, gutter: 10 }) {
        GridCol({ span: 1 }) {
          Text('1').height(60).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        }
        GridCol({ span: 1 }) {
          Text('2').height(60).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        }
        GridCol({ span: 2 }) {
          Text('跨2列').height(60).backgroundColor(0x317aff).fontColor(Color.White).textAlign(TextAlign.Center)
        }
        GridCol({ span: 1 }) {
          Text('3').height(60).backgroundColor(0xF5DEB3).textAlign(TextAlign.Center)
        }
        GridCol({ span: 1 }) {
          Text('4').height(60).backgroundColor(0xD2B48C).textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      
      Row({ space: 10 }) {
        Button('2列').onClick(() => this.columns = 2)
        Button('3列').onClick(() => this.columns = 3)
        Button('4列').onClick(() => this.columns = 4)
      }
    }
    .width('100%')
    .padding(16)
  }
}

// ========== Scroll 滚动容器 ==========
@Entry
@Component
struct ScrollExample {
  private scroller: Scroller = new Scroller()
  
  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Button('顶部').onClick(() => this.scroller.scrollToIndex(0))
        Button('底部').onClick(() => this.scroller.scrollEdge(Edge.Bottom))
      }
      
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          ForEach(Array.from({ length: 20 }, (_, i) => i + 1), (item: number) => {
            Text(`项目 ${item}`)
              .width('100%')
              .height(80)
              .backgroundColor(item % 2 === 0 ? 0xF5DEB3 : 0xD2B48C)
              .textAlign(TextAlign.Center)
              .borderRadius(8)
          })
        }
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}

// ========== 常见布局模式 ==========
@Entry
@Component
struct CommonLayoutPatterns {
  build() {
    Scroll() {
      Column({ space: 20 }) {
        // 卡片布局
        Text('卡片布局')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        
        Column() {
          Text('卡片标题')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
          
          Text('卡片内容描述文字，这里是详细的说明信息。')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ top: 8 })
          
          Row() {
            Text('标签1').fontSize(12).padding(4).backgroundColor(0xe0e0e0).borderRadius(4)
            Text('标签2').fontSize(12).padding(4).backgroundColor(0xe0e0e0).borderRadius(4).margin({ left: 8 })
          }
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 4, color: 0x1a000000, offsetX: 0, offsetY: 2 })
        
        // 列表项布局
        Text('列表项布局')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        
        Column({ space: 1 }) {
          ForEach([1, 2, 3], (item: number) => {
            Row() {
              Text(`${item}`)
                .width(40).height(40)
                .backgroundColor(0x317aff)
                .fontColor(Color.White)
                .borderRadius(20)
                .textAlign(TextAlign.Center)
              
              Column() {
                Text('标题').fontSize(16).fontWeight(FontWeight.Bold)
                Text('描述文字').fontSize(12).fontColor('#999999')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
              
              Text('>').fontColor('#cccccc')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Color.White)
          })
        }
        .borderRadius(8)
        
        // 表单布局
        Text('表单布局')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        
        Column({ space: 16 }) {
          Row() {
            Text('姓名').width(60)
            TextInput({ placeholder: '请输入姓名' }).layoutWeight(1)
          }
          
          Row() {
            Text('电话').width(60)
            TextInput({ placeholder: '请输入电话' }).layoutWeight(1)
          }
          
          Button('提交')
            .width('100%')
            .margin({ top: 16 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(8)
      }
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xf5f5f5)
  }
}