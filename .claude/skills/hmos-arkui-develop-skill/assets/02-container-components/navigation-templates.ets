// Navigation 导航组件示例模板

// ========== 基础导航 ==========
@Entry
@Component
struct BasicNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  
  build() {
    Navigation(this.navPathStack) {
      Column() {
        Text('首页')
          .fontSize(24)
        
        Button('跳转到详情')
          .margin({ top: 20 })
          .onClick(() => {
            this.navPathStack.pushPath({ name: 'Detail', param: { id: 1 } })
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .title('导航示例')
    .titleMode(NavigationTitleMode.Mini)
    .navDestination(this.buildNavDestination)
  }
  
  @Builder
  buildNavDestination(name: string, param: ESObject) {
    if (name === 'Detail') {
      DetailPage({ param: param as DetailParam })
    }
  }
}

interface DetailParam {
  id: number
}

@Component
struct DetailPage {
  @Param param: DetailParam = { id: 0 }
  @LocalStorageProp('navPathStack') navPathStack: NavPathStack = new NavPathStack()
  
  build() {
    Column() {
      Text(`详情页 ID: ${this.param.id}`)
        .fontSize(24)
      
      Button('返回')
        .margin({ top: 20 })
        .onClick(() => {
          this.navPathStack.pop()
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

// ========== 带参数传递的导航 ==========
@Entry
@Component
struct ParamNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  
  aboutToAppear(): void {
    AppStorage.setOrCreate('navPathStack', this.navPathStack)
  }
  
  build() {
    Navigation(this.navPathStack) {
      Column({ space: 20 }) {
        ForEach([1, 2, 3], (id: number) => {
          Button(`跳转到详情 ${id}`)
            .onClick(() => {
              this.navPathStack.pushPath({
                name: 'ProductDetail',
                param: { productId: id, title: `商品${id}` }
              })
            })
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .title('商品列表')
    .navDestination(this.buildNavDestination)
  }
  
  @Builder
  buildNavDestination(name: string, param: ESObject) {
    if (name === 'ProductDetail') {
      ProductDetailPage({ param: param as ProductParam })
    }
  }
}

interface ProductParam {
  productId: number
  title: string
}

@Component
struct ProductDetailPage {
  @Param param: ProductParam = { productId: 0, title: '' }
  @LocalStorageProp('navPathStack') navPathStack: NavPathStack = new NavPathStack()
  
  build() {
    Column({ space: 20 }) {
      Text(this.param.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      
      Text(`商品ID: ${this.param.productId}`)
        .fontSize(16)
      
      Row({ space: 20 }) {
        Button('返回')
          .onClick(() => this.navPathStack.pop())
        
        Button('返回首页')
          .onClick(() => this.navPathStack.clear())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }
}

// ========== 分栏导航 (平板/横屏) ==========
@Entry
@Component
struct SplitNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  @State menuList: string[] = ['消息', '通讯录', '发现', '我的']
  @State selectedIndex: number = 0
  
  aboutToAppear(): void {
    AppStorage.setOrCreate('navPathStack', this.navPathStack)
  }
  
  build() {
    Navigation(this.navPathStack) {
      Row() {
        // 左侧菜单
        Column() {
          ForEach(this.menuList, (item: string, index: number) => {
            Text(item)
              .width('100%')
              .height(50)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.selectedIndex === index ? 0xe0e0e0 : Color.Transparent)
              .onClick(() => {
                this.selectedIndex = index
              })
          })
        }
        .width(100)
        .height('100%')
        .backgroundColor(0xf5f5f5)
        
        // 右侧内容
        Column() {
          Text(`${this.menuList[this.selectedIndex]} 内容`)
            .fontSize(24)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Split)  // 分栏模式
    .navBarWidth(200)
  }
}

// ========== 自定义标题栏 ==========
@Entry
@Component
struct CustomTitleNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  
  build() {
    Navigation(this.navPathStack) {
      Column() {
        Text('首页内容')
          .fontSize(24)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .customToolbar(this.customToolbar)
  }
  
  @Builder
  customToolbar() {
    Row() {
      SymbolGlyph($r('sys.symbol.house'))
        .fontSize(24)
      
      Text('首页')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ left: 10 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }
}

// ========== 带返回拦截的导航 ==========
@Entry
@Component
struct InterceptNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  @State showExitDialog: boolean = false
  
  aboutToAppear(): void {
    AppStorage.setOrCreate('navPathStack', this.navPathStack)
  }
  
  build() {
    Navigation(this.navPathStack) {
      Column() {
        Text('首页')
          .fontSize(24)
        
        Button('跳转到详情')
          .margin({ top: 20 })
          .onClick(() => {
            this.navPathStack.pushPath({ name: 'Detail' })
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .title('首页')
    .onBackPressed(() => {
      if (this.navPathStack.size() > 0) {
        this.navPathStack.pop()
        return true
      }
      // 显示退出确认对话框
      this.showExitDialog = true
      return true
    })
    .bindContentCover(this.showExitDialog, this.exitDialog(), {
      modalTransition: ModalTransition.DEFAULT
    })
  }
  
  @Builder
  exitDialog() {
    Column() {
      Text('确定要退出吗？')
        .fontSize(20)
        .margin({ bottom: 20 })
      
      Row({ space: 20 }) {
        Button('取消')
          .onClick(() => {
            this.showExitDialog = false
          })
        
        Button('确定')
          .onClick(() => {
            this.showExitDialog = false
            // 退出应用
          })
      }
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

// ========== 带标签页的导航 ==========
@Entry
@Component
struct TabsNavigationExample {
  private navPathStack: NavPathStack = new NavPathStack()
  @State currentTab: number = 0
  
  aboutToAppear(): void {
    AppStorage.setOrCreate('navPathStack', this.navPathStack)
  }
  
  build() {
    Navigation(this.navPathStack) {
      Tabs({ index: $$this.currentTab, barPosition: BarPosition.End }) {
        TabContent() {
          this.homeContent()
        }
        .tabBar(this.tabBarItem('首页', 'sys.symbol.house', 0))
        
        TabContent() {
          this.messageContent()
        }
        .tabBar(this.tabBarItem('消息', 'sys.symbol.message', 1))
        
        TabContent() {
          this.profileContent()
        }
        .tabBar(this.tabBarItem('我的', 'sys.symbol.person', 2))
      }
      .width('100%')
      .height('100%')
      .barHeight(56)
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
  }
  
  @Builder
  tabBarItem(title: string, icon: Resource, index: number) {
    Column() {
      SymbolGlyph($r(icon))
        .fontSize(24)
        .fontColor([this.currentTab === index ? Color.Blue : Color.Gray])
      
      Text(title)
        .fontSize(12)
        .fontColor(this.currentTab === index ? Color.Blue : Color.Gray)
        .margin({ top: 4 })
    }
  }
  
  @Builder
  homeContent() {
    Column() { Text('首页').fontSize(24) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
  
  @Builder
  messageContent() {
    Column() { Text('消息').fontSize(24) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
  
  @Builder
  profileContent() {
    Column() { Text('我的').fontSize(24) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}