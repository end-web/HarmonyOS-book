// 自定义组件示例模板

// ========== 基础自定义组件 ==========
@Component
struct CustomCard {
  @Prop title: string = ''
  @Prop description: string = ''
  
  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      Text(this.description)
        .fontSize(14)
        .fontColor(Color.Gray)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 10, color: 0x20000000, offsetX: 0, offsetY: 2 })
  }
}

@Entry
@Component
struct CustomCardExample {
  build() {
    Column({ space: 16 }) {
      CustomCard({
        title: '标题一',
        description: '这是第一张卡片的描述内容'
      })
      
      CustomCard({
        title: '标题二',
        description: '这是第二张卡片的描述内容'
      })
    }
    .padding(20)
    .backgroundColor(0xf5f5f5)
  }
}

// ========== @Builder 可复用UI ==========
@Entry
@Component
struct BuilderExample {
  @State list: string[] = ['项目1', '项目2', '项目3']
  
  build() {
    Column({ space: 16 }) {
      ForEach(this.list, (item: string) => {
        this.listItemBuilder(item)
      })
    }
    .padding(20)
  }
  
  @Builder
  listItemBuilder(title: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(20)
        .fontColor([Color.Green])
      
      Text(title)
        .fontSize(16)
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
  }
}

// ========== @BuilderParam 插槽 ==========
@Component
struct ContainerComponent {
  @BuilderParam content: () => void
  @Prop title: string = ''
  
  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .padding({ bottom: 12 })
      
      this.content()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

@Entry
@Component
struct BuilderParamExample {
  build() {
    Column({ space: 16 }) {
      ContainerComponent({ title: '卡片1' }) {
        Text('这是插槽内容1')
          .fontSize(16)
      }
      
      ContainerComponent({ title: '卡片2' }) {
        Column() {
          Text('插槽内容2')
          Text('多行内容')
            .margin({ top: 8 })
        }
      }
    }
    .padding(20)
    .backgroundColor(0xf5f5f5)
  }
}

// ========== @Styles 样式复用 ==========
@Styles function cardStyle() {
  .width('100%')
  .padding(16)
  .backgroundColor(Color.White)
  .borderRadius(12)
}

@Styles function titleStyle() {
  .fontSize(20)
  .fontWeight(FontWeight.Bold)
  .fontColor(Color.Black)
}

@Entry
@Component
struct StylesExample {
  build() {
    Column({ space: 16 }) {
      Column() {
        Text('标题1')
          .titleStyle()
        
        Text('描述内容1')
          .fontSize(14)
          .fontColor(Color.Gray)
          .margin({ top: 8 })
      }
      .cardStyle()
      
      Column() {
        Text('标题2')
          .titleStyle()
        
        Text('描述内容2')
          .fontSize(14)
          .fontColor(Color.Gray)
          .margin({ top: 8 })
      }
      .cardStyle()
    }
    .padding(20)
    .backgroundColor(0xf5f5f5)
  }
}

// ========== @Extend 扩展原生组件 ==========
@Extend(Text) function primaryText() {
  .fontSize(16)
  .fontColor(0x317aff)
  .fontWeight(FontWeight.Medium)
}

@Extend(Button) function primaryButton() {
  .width(120)
  .height(40)
  .backgroundColor(0x317aff)
  .fontColor(Color.White)
  .borderRadius(20)
}

@Entry
@Component
struct ExtendExample {
  build() {
    Column({ space: 20 }) {
      Text('主要文本')
        .primaryText()
      
      Text('另一段主要文本')
        .primaryText()
      
      Button('主要按钮')
        .primaryButton()
      
      Button('另一个按钮')
        .primaryButton()
    }
    .padding(20)
  }
}

// ========== V2 自定义组件 ==========
@ComponentV2
struct V2CustomCard {
  @Param title: string = ''
  @Param description: string = ''
  @Param imageUrl: string = ''
  @Event onTap: () => void = () => {}
  
  build() {
    Column() {
      if (this.imageUrl) {
        Image(this.imageUrl)
          .width('100%')
          .height(120)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 12, topRight: 12 })
      }
      
      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        
        if (this.description) {
          Text(this.description)
            .fontSize(14)
            .fontColor(Color.Gray)
            .margin({ top: 6 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(12)
    .onClick(() => this.onTap())
  }
}

@ComponentV2
struct V2CustomCardExample {
  @Local selectedIndex: number = -1
  
  build() {
    Column({ space: 16 }) {
      V2CustomCard({
        title: '卡片标题1',
        description: '这是卡片的描述内容',
        imageUrl: 'app.media.icon',
        onTap: () => {
          this.selectedIndex = 0
          console.info('点击卡片1')
        }
      })
      
      V2CustomCard({
        title: '卡片标题2',
        description: '另一张卡片的描述内容',
        onTap: () => {
          this.selectedIndex = 1
          console.info('点击卡片2')
        }
      })
      
      if (this.selectedIndex >= 0) {
        Text(`选中: 卡片${this.selectedIndex + 1}`)
          .fontSize(16)
          .fontColor(0x317aff)
      }
    }
    .padding(20)
    .backgroundColor(0xf5f5f5)
  }
}

// ========== 带动画的自定义组件 ==========
@ComponentV2
struct AnimatedButton {
  @Param text: string = '按钮'
  @Param bgColor: Color = Color.Blue
  @Event onClick: () => void = () => {}
  @Local scale: number = 1
  @Local opacity: number = 1
  
  build() {
    Button(this.text)
      .width(150)
      .height(50)
      .backgroundColor(this.bgColor)
      .fontColor(Color.White)
      .borderRadius(25)
      .scale({ x: this.scale, y: this.scale })
      .opacity(this.opacity)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          animateTo({ duration: 100 }, () => {
            this.scale = 0.95
            this.opacity = 0.8
          })
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          animateTo({ duration: 100 }, () => {
            this.scale = 1
            this.opacity = 1
          })
        }
      })
      .onClick(() => this.onClick())
  }
}

@ComponentV2
struct AnimatedButtonExample {
  build() {
    Column({ space: 20 }) {
      AnimatedButton({
        text: '主要按钮',
        bgColor: Color.Blue,
        onClick: () => console.info('点击主要按钮')
      })
      
      AnimatedButton({
        text: '警告按钮',
        bgColor: Color.Red,
        onClick: () => console.info('点击警告按钮')
      })
      
      AnimatedButton({
        text: '成功按钮',
        bgColor: Color.Green,
        onClick: () => console.info('点击成功按钮')
      })
    }
    .padding(20)
  }
}

// ========== 复合组件 ==========
@ComponentV2
struct ListItemView {
  @Param title: string = ''
  @Param subtitle: string = ''
  @Param imageUrl: string = ''
  @Param showArrow: boolean = true
  @Event onClick: () => void = () => {}
  
  build() {
    Row() {
      // 左侧图标
      if (this.imageUrl) {
        Image(this.imageUrl)
          .width(48)
          .height(48)
          .borderRadius(24)
      } else {
        Column()
          .width(48)
          .height(48)
          .backgroundColor(0xe0e0e0)
          .borderRadius(24)
      }
      
      // 中间内容
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(14)
            .fontColor(Color.Gray)
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      
      // 右侧箭头
      if (this.showArrow) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([Color.Gray])
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .onClick(() => this.onClick())
  }
}

@ComponentV2
struct ListItemViewExample {
  build() {
    Column({ space: 1 }) {
      ListItemView({
        title: '用户名',
        subtitle: 'user@example.com',
        imageUrl: 'app.media.avatar',
        onClick: () => console.info('点击用户')
      })
      
      ListItemView({
        title: '设置',
        subtitle: '应用设置和偏好',
        showArrow: true,
        onClick: () => console.info('点击设置')
      })
      
      ListItemView({
        title: '帮助',
        subtitle: '常见问题和反馈',
        showArrow: true,
        onClick: () => console.info('点击帮助')
      })
      
      ListItemView({
        title: '退出登录',
        showArrow: false,
        onClick: () => console.info('点击退出')
      })
    }
    .backgroundColor(0xf5f5f5)
  }
}