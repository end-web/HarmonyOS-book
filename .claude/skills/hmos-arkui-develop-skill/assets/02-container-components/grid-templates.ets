// Grid 组件示例模板

// ========== 基础网格 ==========
@Entry
@Component
struct BasicGridExample {
  @State data: string[] = Array.from({ length: 12 }, (_, i) => `项目${i + 1}`)
  
  build() {
    Grid() {
      ForEach(this.data, (item: string) => {
        GridItem() {
          Text(item)
            .width('100%')
            .height(80)
            .textAlign(TextAlign.Center)
            .backgroundColor(0xf5f5f5)
            .borderRadius(8)
        }
      })
    }
    .columnsTemplate('1fr 1fr 1fr')  // 3列
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height('100%')
    .padding(16)
  }
}

// ========== 自适应网格 ==========
@Entry
@Component
struct AdaptiveGridExample {
  @State data: string[] = Array.from({ length: 20 }, (_, i) => `项目${i + 1}`)
  
  build() {
    Grid() {
      ForEach(this.data, (item: string) => {
        GridItem() {
          Text(item)
            .width('100%')
            .height(60)
            .textAlign(TextAlign.Center)
            .backgroundColor(0xf5f5f5)
            .borderRadius(8)
        }
      })
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')  // 4列
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height('100%')
    .padding(16)
    .edgeEffect(EdgeEffect.Spring)
  }
}

// ========== 不规则网格 ==========
@Entry
@Component
struct IrregularGridExample {
  build() {
    Grid() {
      GridItem() {
        Text('横跨2列')
          .width('100%')
          .height(80)
          .textAlign(TextAlign.Center)
          .backgroundColor(0x317aff)
          .fontColor(Color.White)
          .borderRadius(8)
      }
      .columnStart(0)
      .columnEnd(1)  // 横跨2列
      
      GridItem() {
        Text('普通')
          .width('100%')
          .height(80)
          .textAlign(TextAlign.Center)
          .backgroundColor(0xf5f5f5)
          .borderRadius(8)
      }
      
      GridItem() {
        Text('普通')
          .width('100%')
          .height(80)
          .textAlign(TextAlign.Center)
          .backgroundColor(0xf5f5f5)
          .borderRadius(8)
      }
      
      GridItem() {
        Text('横跨3列')
          .width('100%')
          .height(80)
          .textAlign(TextAlign.Center)
          .backgroundColor(0xff6b6b)
          .fontColor(Color.White)
          .borderRadius(8)
      }
      .columnStart(0)
      .columnEnd(2)  // 横跨3列
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height(400)
    .padding(16)
  }
}

// ========== 可滚动网格 ==========
@Entry
@Component
struct ScrollableGridExample {
  @State data: string[] = Array.from({ length: 50 }, (_, i) => `项目${i + 1}`)
  private scroller: Scroller = new Scroller()
  
  build() {
    Column() {
      Row() {
        Button('滚动到顶部')
          .onClick(() => this.scroller.scrollToIndex(0))
        
        Button('滚动到底部')
          .onClick(() => this.scroller.scrollToIndex(this.data.length - 1))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .margin({ bottom: 10 })
      
      Grid(this.scroller) {
        ForEach(this.data, (item: string, index: number) => {
          GridItem() {
            Text(item)
              .width('100%')
              .height(80)
              .textAlign(TextAlign.Center)
              .backgroundColor(0xf5f5f5)
              .borderRadius(8)
          }
          .onClick(() => {
            console.info(`点击: ${item}`)
          })
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(10)
      .columnsGap(10)
      .width('100%')
      .layoutWeight(1)
      .padding(16)
    }
  }
}

// ========== 分组网格 ==========
@Entry
@Component
struct GroupedGridExample {
  build() {
    Grid() {
      GridItem() {
        Text('分组1')
          .width('100%')
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
      }
      .columnStart(0)
      .columnEnd(2)
      
      ForEach(['1-1', '1-2', '1-3'], (item: string) => {
        GridItem() {
          Text(item)
            .width('100%')
            .height(80)
            .textAlign(TextAlign.Center)
            .backgroundColor(0xf5f5f5)
            .borderRadius(8)
        }
      })
      
      GridItem() {
        Text('分组2')
          .width('100%')
          .height(40)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
      }
      .columnStart(0)
      .columnEnd(2)
      
      ForEach(['2-1', '2-2'], (item: string) => {
        GridItem() {
          Text(item)
            .width('100%')
            .height(80)
            .textAlign(TextAlign.Center)
            .backgroundColor(0xf5f5f5)
            .borderRadius(8)
        }
      })
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height(400)
    .padding(16)
  }
}

// ========== LazyForEach 网格 ==========
interface GridItemData {
  id: string
  title: string
  color: string
}

class GridDataSource implements IDataSource {
  private data: GridItemData[] = []
  private listeners: DataChangeListener[] = []
  
  constructor(count: number) {
    const colors = ['#317aff', '#ff6b6b', '#4caf50', '#ff9800', '#9c27b0']
    for (let i = 0; i < count; i++) {
      this.data.push({
        id: `id_${i}`,
        title: `项目 ${i + 1}`,
        color: colors[i % colors.length]
      })
    }
  }
  
  totalCount(): number {
    return this.data.length
  }
  
  getData(index: number): GridItemData {
    return this.data[index]
  }
  
  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }
  
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter(l => l !== listener)
  }
}

@Entry
@Component
struct LazyGridExample {
  private dataSource: GridDataSource = new GridDataSource(100)
  
  build() {
    Grid() {
      LazyForEach(this.dataSource, (item: GridItemData) => {
        GridItem() {
          Text(item.title)
            .width('100%')
            .height(80)
            .textAlign(TextAlign.Center)
            .backgroundColor(item.color)
            .fontColor(Color.White)
            .borderRadius(8)
        }
      }, (item: GridItemData) => item.id)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height('100%')
    .padding(16)
    .cachedCount(10)
  }
}

// ========== 图片网格 ==========
@Entry
@Component
struct ImageGridExample {
  private images: string[] = [
    'app.media.img1', 'app.media.img2', 'app.media.img3',
    'app.media.img4', 'app.media.img5', 'app.media.img6',
    'app.media.img7', 'app.media.img8', 'app.media.img9'
  ]
  
  build() {
    Grid() {
      ForEach(this.images, (img: string, index: number) => {
        GridItem() {
          Image($r(img))
            .width('100%')
            .height(120)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
      })
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(4)
    .columnsGap(4)
    .width('100%')
    .height('100%')
    .padding(4)
  }
}

// ========== V2 Repeat 网格 ==========
@ObservedV2
class GridItemModel {
  @Trace id: string = ''
  @Trace title: string = ''
  
  constructor(id: string, title: string) {
    this.id = id
    this.title = title
  }
}

@ComponentV2
struct V2GridExample {
  @Local items: GridItemModel[] = Array.from({ length: 40 }, (_, i) => 
    new GridItemModel(`grid_${i}`, `项目 ${i + 1}`)
  )
  
  build() {
    Grid() {
      Repeat(this.items)
        .virtualScroll()
        .cachedCount(8)
        .each((item: GridItemModel) => {
          GridItem() {
            Text(item.title)
              .width('100%')
              .height(80)
              .textAlign(TextAlign.Center)
              .backgroundColor(0xf5f5f5)
              .borderRadius(8)
          }
        })
        .key((item: GridItemModel) => item.id)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsGap(10)
    .columnsGap(10)
    .width('100%')
    .height('100%')
    .padding(16)
  }
}